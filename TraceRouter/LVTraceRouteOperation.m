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

struct ICMPHeader {
    uint8_t     type;
    uint8_t     code;
    uint16_t    checksum;
    uint16_t    identifier;
    uint16_t    sequenceNumber;
    // data...
};
typedef struct ICMPHeader ICMPHeader;

enum {
    kICMPTypeEchoReply   = 0,           // code is always 0
    kICMPTypeEchoRequest = 8            // code is always 0
};

static uint16_t in_cksum(const void *buffer, size_t bufferLen)
// This is the standard BSD checksum code, modified to use modern types.
{
    size_t              bytesLeft;
    int32_t             sum;
    const uint16_t *    cursor;
    union {
        uint16_t        us;
        uint8_t         uc[2];
    } last;
    uint16_t            answer;
    
    bytesLeft = bufferLen;
    sum = 0;
    cursor = buffer;
    
    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1) {
        last.uc[0] = * (const uint8_t *) cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff); /* add hi 16 to low 16 */
    sum += (sum >> 16);         /* add carry */
    answer = (uint16_t) ~sum;   /* truncate to 16 bits */
    
    return answer;
}


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
@property (nonatomic, copy, readwrite) NSData *hostAddress;
@property (copy) completionBlock completion;
@property (copy) errorBlock errorHandleBlock;
@end

@implementation LVTraceRouteOperation
{
    CFHostRef _host;
    CFSocketRef _socket;
}
- (instancetype) initWithHostname:(NSString *)hostName
                  timeoutMillisec:(int)timeoutMillisec
                           maxTTL:(int)maxTTL
                             port:(int)destPort
                         tryCount:(int)tryCount
                overallTimeoutSec:(int)overallTimeoutSec
                  completionBlock:(completionBlock)completionBlock
                       errorBlock:(errorBlock)errorBlock;
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
        
        self.completion = completionBlock;
        self.errorHandleBlock = errorBlock;
    }
    
    return self;
}

- (void)dealloc {
    if (_host != NULL) {
        CFRelease(_host);
        _host = NULL;
    }
}

+ (double)currentTimeMillis
{
    struct timeval t;
    gettimeofday(&t, NULL);
    
    return (t.tv_sec * 1000) + ((double)t.tv_usec / 1000);
}

- (void)sendErrorwithCode:(int)errorCode reason:(NSString *)reason description:(NSString *)description
{
//    if ([self.delegate respondsToSelector:@selector(traceRouteDidFailWithError:)]) {
    if (self.errorHandleBlock) {
        NSMutableDictionary *userInfo = [@{ @"Host": self.hostName, @"Reason": reason} mutableCopy];
        
        if ([description length] > 0) {
            userInfo[@"Desc"] = description;
        }
        NSError *error = [[NSError alloc] initWithDomain:@"TraceRouteErrorDomain"
                                                    code:errorCode
                                                userInfo:userInfo];
        
//        [self.delegate traceRouteDidFailWithError:error];
        self.errorHandleBlock(error);
    }
}
- (void)iPAddressFromHostName:(NSString *)hostName
{
    Boolean result = FALSE;
//    CFHostRef hostRef;
    NSArray * addresses = NULL;
    
    _host = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)hostName);
    if (_host)
    {
        result = CFHostStartInfoResolution(_host, kCFHostAddresses, NULL); // pass an error instead of NULL here to find out why it failed
        if (result == TRUE)
        {
            addresses = (__bridge NSArray *)CFHostGetAddressing(_host, &result);
        }
    }
    
    if (result == TRUE && (addresses != nil))
    {
        result = false;
        for (NSData *address in addresses) {
            const struct sockaddr *addrPtr;
            addrPtr = (struct sockaddr *)[address bytes];
            if ([address length] >= sizeof(struct sockaddr) && addrPtr->sa_family == AF_INET) {
                self.hostAddress = address;
                result = true;
                break;
            }
        }
    }
    if (!result) {
        self.hostAddress = nil;
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
        
        [self iPAddressFromHostName:self.hostName];

        
        u_char responsePacket[RESPONSE_PACKET_LENGTH];
        char fromIp_str[INET_ADDRSTRLEN];
        
        NSMutableArray *routeArray = [[NSMutableArray alloc] init];
        
        double overallStartTime = [LVTraceRouteOperation currentTimeMillis]; // < 60 (sec) * 1000 (msec)
        double overallEndTime = overallStartTime + (overall_timeout_sec * 1000);
        bool endFlag = false, timeoutFlag = false;
        
        ICMPHeader *icmpPtr;
        for (int ttl = 1; ttl <= max_ttl && !endFlag && !timeoutFlag; ttl++) {
            memset(&fromAddr, 0, sizeof(fromAddr));
            
            NSData *payload = [[NSString stringWithFormat:@"%28zd bottles of beer on the wall", (ssize_t) 99 - (size_t) (ttl) ] dataUsingEncoding:NSASCIIStringEncoding];
            
            NSMutableData *packet = [NSMutableData dataWithLength:sizeof(*icmpPtr) + [payload length]];
            
            icmpPtr = [packet mutableBytes];
            icmpPtr->type = kICMPTypeEchoRequest;
            icmpPtr->code = 0;
            icmpPtr->checksum=0;
            icmpPtr->identifier = OSSwapHostToBigInt16((uint16_t) arc4random());
            icmpPtr->sequenceNumber = OSSwapHostToBigInt16(ttl);
            memcpy(&icmpPtr[1], [payload bytes], [packet length]);
            
            icmpPtr->checksum = in_cksum([packet bytes], [packet length]);
            
            if(setsockopt(send_socket, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
                [self sendErrorwithCode:2006 reason:@"Setting option for TTL failed" description:[NSString stringWithFormat:@"TTL : %d", ttl]];
                continue;
            }
            
            NSMutableDictionary *currentTTLResult = [[NSMutableDictionary alloc] init];
            for (int try = 0; try < try_cnt; try++) {
                if (self.isCancelled) {
                    return;
                }
                
                if ([LVTraceRouteOperation currentTimeMillis] > overallEndTime) {
                    timeoutFlag = true;
                    break;
                }
                
                double startTime = [LVTraceRouteOperation currentTimeMillis];
                
//                if (sendto(send_socket, [packet bytes], [packet length], 0, (struct sockaddr *)[self.hostAddress bytes], (socklen_t)[packet length]) != [packet length] ) {
//                if (sendto(send_socket, [packet bytes], [packet length], 0, (struct sockaddr *)&toAddr, sizeof(toAddr)) != [packet length] ) {
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
                        struct hostent *hostEnt = gethostbyaddr(&fromAddr.sin_addr, sizeof(fromAddr.sin_addr), AF_INET);
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
                    
                    if (responsePacket[20] == 0x00 && responsePacket[21] == 0x00) {
                        NSLog(@"Destination port unreachable => Reached destination host22222");
                        endFlag = true;
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
                                           kCompletedFlag: @(endFlag),
                                           kTotalRunTimeSec: @(([LVTraceRouteOperation currentTimeMillis] - overallStartTime)/1000)
                                           };
        close(send_socket);
        close(recv_socket);
        
        freeaddrinfo(hostAddrInfo);
        hostAddrInfo = NULL;
        
//        [self.delegate traceRouteDidFinish:resultDictionary];
        if (self.completion) {
            self.completion(resultDictionary);
        }
    }
}
@end
