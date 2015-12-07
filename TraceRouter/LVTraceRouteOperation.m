//
//  LVTraceRouteOperation.m
//  TraceRouter
//
//  Created by Naver on 2015. 12. 4..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import "LVTraceRouteOperation.h"

#include <netdb.h>
#include <arpa/inet.h>
#include <sys/time.h>

#define RESPONSE_PACKET_LENGTH 64

@interface LVTraceRouteOperation()
{
    int timeout_sec;
    int timeout_usec;
    int max_ttl;
    int port;
    int try_cnt;
    int overall_timeout_sec;
}
@property (strong, nonatomic, readwrite) NSString *hostName;
@end

@implementation LVTraceRouteOperation
- (instancetype) initWithHostname:(NSString *)hostName
                  timeoutMillisec:(int)timeoutMillisec
                           maxTTL:(int)maxTTL
                             port:(int)destPort
                         tryCount:(int)tryCount
                overallTimeoutSec:(int)overallTimeoutSec;
{
    self = [super init];
    
    if (self) {
        self.hostName = hostName;
        
        timeout_sec = timeoutMillisec / 1000;
        timeout_usec = timeoutMillisec % 1000;
        max_ttl = maxTTL;
        port = destPort;
        try_cnt = tryCount;
        overall_timeout_sec = overallTimeoutSec;
    }
    
    return self;
}

+ (double)currentTimeMillis
{
    struct timeval t;
    gettimeofday(&t, NULL);
    
    return (t.tv_sec * 1000) + ((double)t.tv_usec / 1000);
}

- (void)sendErrorwithCode:(int)errorCode reason:(NSString *)reason description:(NSString *)description
{
    if ([self.delegate respondsToSelector:@selector(traceRouteDidFailWithError:)]) {
        NSMutableDictionary *userInfo = [@{ @"Host": self.hostName, @"Reason": reason} mutableCopy];
        
        if ([description length] > 0) {
            userInfo[@"Desc"] = description;
        }
        NSError *error = [[NSError alloc] initWithDomain:@"TraceRouteErrorDomain"
                                                    code:errorCode
                                                userInfo:userInfo];
        
        [self.delegate traceRouteDidFailWithError:error];
    }
}

- (void)main {
    @autoreleasepool {
        // 1. Host의 ip 획득
        if (self.isCancelled) {
            return;
        }
        
        struct addrinfo hints, *hostAddrInfo;
        const char *hostName = [self.hostName UTF8String];
        int status;
        struct sockaddr_in *hostIp;
        char hostIp_str[INET_ADDRSTRLEN];
        
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_DGRAM;
        if ((status = getaddrinfo(hostName, NULL, &hints, &hostAddrInfo))) {
            [self sendErrorwithCode:2000 reason:@"getaddrinfo failed" description:@(gai_strerror(status))];
            return;
        }
        
        if (hostAddrInfo->ai_family == AF_INET) { // IPv4
            hostIp = (struct sockaddr_in *)hostAddrInfo->ai_addr;
            inet_ntop(AF_INET, &(hostIp->sin_addr), hostIp_str, sizeof(hostIp_str));
        } else if(hostAddrInfo->ai_family == AF_INET6) { // IPv6
            [self sendErrorwithCode:2001 reason:@"Ipv6 is not supported" description:nil];
            return;
            //        struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)res->ai_addr;
            //        inet_ntop(res->ai_family, &(ipv6->sin6_addr), ipstr, sizeof(ipstr));
        } else {
            [self sendErrorwithCode:2002 reason:@"Convert Host to Ip Failed" description:nil];
            return;
        }
        // host ip : destinationIP (human readable) / ipv4
        
        NSLog(@"Host Ip Address : %s", hostIp_str);
        
        // 2. 소켓 생성
        if (self.isCancelled) {
            return;
        }
        
        int recv_socket, send_socket;
        if ((recv_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)) < 0) {
            [self sendErrorwithCode:2003 reason:@"Creating receive socket failed" description:nil];
            return;
        }
        
        if ((send_socket = socket(AF_INET, SOCK_DGRAM, 0)) < 0 ) {
            [self sendErrorwithCode:2004 reason:@"Creating send socket failed" description:nil];
            return;
        }

        // 3. 소켓 옵션 설정
        if (self.isCancelled) {
            return;
        }
        
        struct timeval tv;
        tv.tv_sec = timeout_sec;
        tv.tv_usec = timeout_usec;
        
        int errCode;
        if ((errCode = setsockopt(recv_socket, SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(struct timeval))) < 0) {
            [self sendErrorwithCode:2005 reason:@"Setting option for receive time out failed" description:nil];
            NSLog(@"set option for receive time out failed");
        }
        
        // 4. TTL increase시키면서 송신
        if (self.isCancelled) {
            return;
        }
        
        struct sockaddr_in toAddr, fromAddr;
        socklen_t fromAdddrLen = sizeof(fromAddr);
        
        memset(&toAddr, 0, sizeof(toAddr));
        toAddr.sin_family = AF_INET;
        toAddr.sin_addr = hostIp->sin_addr;
        toAddr.sin_port = htons(port);
        
        char *msg = "GET / HTTP/1.1\r\n\r\n";
        
        u_char responsePacket[RESPONSE_PACKET_LENGTH];
        char fromIp_str[INET_ADDRSTRLEN];
        
        NSMutableArray *routeArray = [[NSMutableArray alloc] init];
        
        double overallStartTime = [LVTraceRouteOperation currentTimeMillis]; // < 60 (sec) * 1000 (msec)
        bool endFlag = false, timeoutFlag = false;;
        for (int ttl = 1; ttl <= max_ttl && !endFlag && !timeoutFlag; ttl++) {
            memset(&fromAddr, 0, sizeof(fromAddr));
            
            if(setsockopt(send_socket, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
                [self sendErrorwithCode:2006 reason:@"Setting option for TTL failed" description:[NSString stringWithFormat:@"TTL : %d", ttl]];
                continue;
            }
            
            NSMutableDictionary *currentTTLResult = [[NSMutableDictionary alloc] init];
            for (int try = 0; try < try_cnt; try++) {
                if (self.isCancelled) {
                    return;
                }
                
                if ([LVTraceRouteOperation currentTimeMillis] > overallStartTime + (overall_timeout_sec * 1000)) {
                    timeoutFlag = true;
                    break;
                }
                
                double startTime = [LVTraceRouteOperation currentTimeMillis];
                
                if (sendto(send_socket, msg, sizeof(msg), 0, (struct sockaddr *)&toAddr, sizeof(toAddr)) != sizeof(msg) ) {
                    NSLog (@"Sending ICMP message failed. TTL - %d\n", ttl);
                    [self sendErrorwithCode:2007 reason:@"Sending ICMP message failed" description:[NSString stringWithFormat:@"TTL : %d", ttl]];
                    continue;
                }
                
                ssize_t receivedLength = 0;
                memset(&responsePacket, 0, RESPONSE_PACKET_LENGTH);
                receivedLength = recvfrom(recv_socket, responsePacket, RESPONSE_PACKET_LENGTH, 0,
                                          (struct sockaddr *)&fromAddr, &fromAdddrLen);
                
                if (receivedLength < 0 ) {
                    NSLog(@"Timed out - TTL : %d, try cnt : %d", ttl, try);
                } else {
                    double endTime = [LVTraceRouteOperation currentTimeMillis];
                    double elapsedTime = endTime - startTime;
                    
                    inet_ntop(AF_INET, &fromAddr.sin_addr.s_addr, fromIp_str, sizeof(fromIp_str));
                    
                    NSString *fromIpString = [NSString stringWithCString:fromIp_str encoding:NSASCIIStringEncoding];
                    
                    if (currentTTLResult[fromIpString] == nil) {
                        struct hostent *hostEnt = gethostbyaddr(&fromAddr, sizeof(fromAddr), AF_INET);
                        NSString *currentHopHostName;
                        
                        if (hostEnt == NULL || hostEnt->h_name == NULL) {
                            // host name is null
                            currentHopHostName = fromIpString;
                        } else {
                            // hostEnt->h_name : host name
                            currentHopHostName = [NSString stringWithCString:hostEnt->h_name encoding:NSASCIIStringEncoding];
                        }
                        
                        currentTTLResult[fromIpString] = @{
                                                           kHostName: currentHopHostName,
                                                           kRoundTripTime: [NSMutableArray arrayWithObject:@(elapsedTime)]
                                                           };
                    } else {
                        NSMutableArray *roundTripTimeArray = currentTTLResult[fromIpString][kRoundTripTime];
                        [roundTripTimeArray addObject:@(elapsedTime)];
                    }
                    
                    NSLog(@"currentTTLResult - %@", currentTTLResult);
                }
                
                if (responsePacket[20] == 0x03 && responsePacket[21] == 0x03) {
                    NSLog(@"Destination port unreachable => Reached destination host");
                    endFlag = true;
                }
            }
            [routeArray addObject:currentTTLResult];
        }

        // 5. 마무리
        if (self.isCancelled) {
            return;
        }
        
        NSDictionary *resultDictionary = @{
                                           kHostName: self.hostName,
                                           kIpAddresss: @(hostIp_str),
                                           kResultArray: routeArray,
                                           kCompletedFlag: @(endFlag)
                                           };
        close(send_socket);
        close(recv_socket);
        
        freeaddrinfo(hostAddrInfo);
        hostAddrInfo = NULL;
        
        [self.delegate traceRouteDidFinish:resultDictionary];
    }
}
@end
