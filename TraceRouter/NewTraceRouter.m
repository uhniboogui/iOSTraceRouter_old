//
//  NewTraceRouter.m
//  TraceRouter
//
//  Created by Naver on 2015. 12. 15..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import "NewTraceRouter.h"
#include <sys/time.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <errno.h>


struct IPHeader {
    uint8_t     versionAndHeaderLength;
    uint8_t     differentiatedServices;
    uint16_t    totalLength;
    uint16_t    identification;
    uint16_t    flagsAndFragmentOffset;
    uint8_t     timeToLive;
    uint8_t     protocol;
    uint16_t    headerChecksum;
    uint8_t     sourceAddress[4];
    uint8_t     destinationAddress[4];
    // options...
    // data...
};
typedef struct IPHeader IPHeader;

enum {
    kICMPTypeEchoReply   = 0,           // code is always 0
    kICMPTypeEchoRequest = 8,            // code is always 0
    kICMPTypeTimeExceed = 11            // code is 0 for "TTL expired in transit"
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

@interface NewTraceRouter()
{
    int try_cnt;
    int max_ttl;
    int response_timeout_msec;
    int overall_timeout_sec;

    CFHostRef hostRef;
    CFSocketRef socketRef;

    double traceroute_start_time;
    double traceroute_end_time;
    double sendTime;
}
@property (nonatomic, copy, readwrite) NSData *hostAddress;
@property (nonatomic, strong) NSString *hostIpString;
@property (nonatomic, strong, readwrite) NSString *hostName;
@property (nonatomic, assign, readwrite) uint16_t identifier;
@property (nonatomic, assign, readwrite) uint16_t sequenceNumber;
@property (nonatomic, strong) NSMutableArray *routeArray;
@property (nonatomic, strong) NSMutableDictionary *currentTTLResult;

@property (copy) completionBlock completion;
@property (copy) failureBlock failure;
@end

@implementation NewTraceRouter

- (instancetype) initWithHostname:(NSString *)hostName
                         tryCount:(int)tryCount
                           maxTTL:(int)maxTTL
          responseTimeoutMilliSec:(int)responseTimeoutMilliSec
                overallTimeoutSec:(int)overallTimeoutSec
                  completionBlock:(completionBlock)completionBlock
                     failureBlock:(failureBlock)failureBlock
{
    self = [super init];
    
    if (self) {
        self.hostName = hostName;
        
        response_timeout_msec = responseTimeoutMilliSec;
        max_ttl = maxTTL;
        try_cnt = tryCount;
        overall_timeout_sec = overallTimeoutSec;
        
        self.completion = completionBlock;
        self.failure = failureBlock;
        
        self.identifier = (uint16_t)arc4random();
    }
    
    return self;
}
- (instancetype)initWithHostName:(NSString *)hostName
                 completionBlock:(completionBlock)completionBlock
                    failureBlock:(failureBlock)failureBlock
{
    return [self initWithHostname:hostName
                         tryCount:3
                           maxTTL:64
          responseTimeoutMilliSec:20000 // 20 sec
                overallTimeoutSec:360   // 6 minutes
                  completionBlock:completionBlock
                     failureBlock:failureBlock];
}

- (void)dealloc
{
    if (hostRef != NULL) {
        CFRelease(hostRef);
        hostRef = NULL;
    }
    
    if (socketRef != NULL) {
        CFRelease(socketRef);
        socketRef = NULL;
    }
}

#pragma mark - Utility Functions

+ (double)currentTimeMillis
{
    struct timeval t;
    gettimeofday(&t, NULL);
    
    return (t.tv_sec * 1000) + ((double)t.tv_usec / 1000);
}

+ (NSUInteger)icmpHeaderOffsetInPacket:(NSData *)packet
// Returns the offset of the ICMPHeader within an IP packet.
{
    NSUInteger              result;
    const struct IPHeader * ipPtr;
    size_t                  ipHeaderLength;
    
    result = NSNotFound;
    if ([packet length] >= (sizeof(IPHeader) + sizeof(ICMPHeader))) {
        ipPtr = (const IPHeader *) [packet bytes];
        assert((ipPtr->versionAndHeaderLength & 0xF0) == 0x40);     // IPv4
        assert(ipPtr->protocol == 1);                               // ICMP
        ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t);
        if ([packet length] >= (ipHeaderLength + sizeof(ICMPHeader))) {
            result = ipHeaderLength;
        }
    }
    return result;
}

#pragma mark - Network Related Functions

- (BOOL)canUseHostAddress
{
    Boolean result = FALSE;
    NSArray * addresses = NULL;
    
    hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)self.hostName);
    if (hostRef)
    {
        result = CFHostStartInfoResolution(hostRef, kCFHostAddresses, NULL); // pass an error instead of NULL here to find out why it failed
        if (result == TRUE)
        {
            addresses = (__bridge NSArray *)CFHostGetAddressing(hostRef, &result);
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
                char *ip_address;
                struct sockaddr_in* remoteAddr;
                remoteAddr = (struct sockaddr_in*) addrPtr;//CFDataGetBytePtr([address bytes]);
                if (remoteAddr != NULL)
                {
                    ip_address = inet_ntoa(remoteAddr->sin_addr);
                    self.hostIpString = [NSString stringWithCString:ip_address encoding:NSUTF8StringEncoding];
                }
                return YES;
            }
        }
    }
    
    return NO;
}

- (BOOL)canUseSocket
{
    int err;
    int fd;
    
    const struct sockaddr *addrPtr;
    
    addrPtr = (const struct sockaddr *)[self.hostAddress bytes];
    
    fd = -1;
    err = 0;
    
    switch (addrPtr->sa_family) {
        case AF_INET:
        {
            fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
            if (fd < 0) {
                err = errno;
            }
        } break;
        case AF_INET6:
        {
            // ipv6 is not supported
        } break;
        default:
        {
            
        } break;
    }
    
    if (err != 0) {
        // failed open socket
        return NO;
    }
    
    CFSocketContext socketContext = {0, (__bridge void *)(self), NULL, NULL, NULL};
    CFRunLoopSourceRef rls;
    
    // Wrap it in a CFSocket and schedule it on the runloop.
    
    socketRef = CFSocketCreateWithNative(NULL, fd, kCFSocketReadCallBack, SocketReadCallback, &socketContext);
    
    if (socketRef == NULL) {
        // fail...
        return NO;
    }
    
    // The socket will now take care of cleaning up our file descriptor.
    
    rls = CFSocketCreateRunLoopSource(NULL, socketRef, 0);
    if (rls == NULL) {
        //fail..
        return NO;
    }
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    
    CFRelease(rls);
    
    return YES;
}

- (void)failWithErrorCode:(int)errorCode reason:(NSString *)reason description:(NSDictionary *)description
{
    if (self.failure) {
//        NSMutableDictionary *userInfo = [@{ @"Host": self.hostName, @"Reason": reason} mutableCopy];
        
        NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
        userInfo[@"Host"] = self.hostName;
        userInfo[@"Reason"] = reason;

        if ([description count] > 0) {
            [userInfo addEntriesFromDictionary:description];
        }
        NSError *error = [[NSError alloc] initWithDomain:@"TraceRouteErrorDomain"
                                                    code:errorCode
                                                userInfo:userInfo];
        
        self.failure(error);
    }
}

- (void)startTraceRoute
{
    // get host address
    if ([self canUseHostAddress] == NO) {
        NSLog(@"Get Host Address Failed");
        return;
    }
    
    // set socket for data transfer
    if ([self canUseSocket] == NO) {
        NSLog(@"Open Socket Failed");
        return;
    }
    
    struct timeval tv;
    tv.tv_sec = response_timeout_msec / 1000;
    tv.tv_usec = response_timeout_msec % 1000;
    
    if (setsockopt(CFSocketGetNative(socketRef), SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(struct timeval)) < 0) {
        NSLog(@"SET Option for receive time out failed");
        return;
    }
    
    self.routeArray = [[NSMutableArray alloc] init];
    
    // start send icmp packet
    traceroute_start_time = [[self class] currentTimeMillis];
    traceroute_end_time = traceroute_start_time + (overall_timeout_sec * 1000);
    self.sequenceNumber = 0;
    [self sendICMPPacket];
}

- (void)sendICMPPacket
{
//    double currentTime = [[self class] currentTimeMillis];
    
    //-------------------뺄거-------------------
//    if ((self.sequenceNumber > max_ttl * try_cnt) || currentTime > traceroute_end_time) {
//        // quit traceroute
//        if (self.completion) {
//            if (self.currentTTLResult) {
//                [self.routeArray addObject:self.currentTTLResult];
//            }
//            NSDictionary *resultDictionary = @{
//                                               kHostName: self.hostName,
//                                               kIpAddresss: self.hostIpString,
//                                               kResultArray: self.routeArray,
//                                                   kCompletedFlag: @(1),
//                                               kTotalRunTimeSec: @((currentTime - traceroute_start_time)/1000)
//                                               };
//            self.completion(resultDictionary);
//        }
//    }
    //------------------------------------------

//    int err = 0;
    NSData *payload;
    NSMutableData *packet;
    ICMPHeader *icmpPtr;
    ssize_t bytesSent;
    
    // Set Socket option for TTL
    if (self.sequenceNumber % try_cnt == 0) {
        // new TTL
        NSLog(@"sequenceNumber : %d", self.sequenceNumber);
        int ttl = self.sequenceNumber / try_cnt;
        if (setsockopt(CFSocketGetNative(socketRef), IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) < 0) {
            [self failWithErrorCode:TraceRouterErrorCodeSetSocketOptionFailed
                             reason:@"Set option for TTL Failed"
                        description:@{@"TTL":@(ttl)}];
            return;
        }
        
        if (self.sequenceNumber > 0) {
            [self.routeArray addObject:self.currentTTLResult];
        }
        self.currentTTLResult = [[NSMutableDictionary alloc] init];
    }
    
    // Make ICMP Packet
    payload = [[NSString stringWithFormat:@"%44zd", 0] dataUsingEncoding:NSASCIIStringEncoding];
    
    packet = [NSMutableData dataWithLength:sizeof(*icmpPtr) + [payload length]];
    if (packet == nil) {
        // ... fail
        NSLog(@"Creating icmp packet failed");
        [self failWithErrorCode:TraceRouterErrorCodeCreatingICMPPacketFailed reason:@"Creating ICMP packet failed" description:nil];
    }
    
    icmpPtr = [packet mutableBytes];
    icmpPtr->type = kICMPTypeEchoRequest;
    icmpPtr->code = 0;
    icmpPtr->checksum = 0;
    icmpPtr->identifier = OSSwapHostToBigInt16(self.identifier);
    icmpPtr->sequenceNumber = OSSwapHostToBigInt16(self.sequenceNumber);
    memcpy(&icmpPtr[1], [payload bytes], [payload length]);
    
    // The IP checksum returns a 16-bit number that's already in correct byte order
    // (due to wacky 1's complement maths), so we just put it into the packet as a 16-bit unit.
    icmpPtr->checksum = in_cksum([packet bytes], [packet length]);
    
    // set socket option for ttl ?????
    
    
    // send icmp packet
    if (socketRef == NULL) {
        bytesSent = -1;
        [self failWithErrorCode:TraceRouterErrorCodeSendingError reason:@"SocketRef is null" description:@{@"Data":packet}];
    } else {
        sendTime = [[self class] currentTimeMillis];
        bytesSent = sendto(
                           CFSocketGetNative(socketRef),
                           [packet bytes],
                           [packet length],
                           0,
                           (struct sockaddr *)[self.hostAddress bytes],
                           (socklen_t)[self.hostAddress length]
                           );
        if (bytesSent < 0) {
            [self failWithErrorCode:TraceRouterErrorCodeSendingError reason:@"Sending ICMP Packet Failed" description:@{@"Data":packet}];
        }
    }
    
    // Handle the results of the send.
    if ((NSUInteger)bytesSent != [packet length]) {
        [self failWithErrorCode:TraceRouterErrorCodeSendingError reason:@"Sending ICMP Packet Error" description:@{@"Data":packet}];
    }
}
//
//- (void) addRouteAddress:(struct sockaddr_in)addr receivedTime:(double)recvTime
//{
//    char addr_str[INET_ADDRSTRLEN];
//    inet_ntop(AF_INET, &addr.sin_addr.s_addr, addr_str, sizeof(addr_str));
//    NSString *fromAddrString = [NSString stringWithCString:addr_str encoding:NSASCIIStringEncoding];
//    
//    double elapsedTime = recvTime-sendTime;
//    if (self.currentTTLResult[fromAddrString] == nil) {
//        struct hostent *hostent = gethostbyaddr(&addr.sin_addr, sizeof(addr.sin_addr), AF_INET);
//        NSString *addrHostName;
//        
//        if (hostent == NULL || hostent->h_name == NULL) {
//            addrHostName = fromAddrString;
//        } else {
//            addrHostName = [NSString stringWithCString:hostent->h_name encoding:NSASCIIStringEncoding];
//        }
//        
//        self.currentTTLResult[fromAddrString] = @{
//                                                  kHostName: addrHostName,
//                                                  kRoundTripTime: [NSMutableArray arrayWithObject:@(elapsedTime)]
//                                                  };
//    } else {
//        NSMutableArray *roundTripTimeArray = self.currentTTLResult[fromAddrString][kRoundTripTime];
//        [roundTripTimeArray addObject:@(elapsedTime)];
//    }
//}

// in cfsocket callback function
// 1. get address packet from
// 2. send icmp packet
- (void)readReceivedData
{
    struct sockaddr_in addr;
    socklen_t addrLen;
    ssize_t bytesRead;
    void *buffer;
    enum { kBufferSize = 256 };
    // 65535 is the maximum IP Packet size, which seems like a reasonable bound
    
    BOOL endFlag;
    NSUInteger icmpHeaderOffset;
    ICMPHeader *icmpPtr;
    uint16_t receivedChecksum;
    uint16_t calculatedChecksum;
    
    buffer = malloc(kBufferSize);
    
    // Actually read the data.
    addrLen = sizeof(addr);
    bytesRead = recvfrom(CFSocketGetNative(socketRef), buffer, kBufferSize, 0, (struct sockaddr *)&addr, &addrLen);
    double recvTime = [[self class] currentTimeMillis];
    if (bytesRead < 0) {
        [self failWithErrorCode:TraceRouterErrorCodeCannotReceiveData reason:@"Cannot receive response packet" description:nil];
    }
    
    // Process the data we read.
    if (bytesRead > 0) {
        NSMutableData *packet;
        packet = [NSMutableData dataWithBytes:buffer length:(NSUInteger)bytesRead];
        
        icmpHeaderOffset = [[self class] icmpHeaderOffsetInPacket:packet];
        if (icmpHeaderOffset != NSNotFound) {
            icmpPtr = (struct ICMPHeader *) (((uint8_t *)[packet mutableBytes]) + icmpHeaderOffset);
            
            receivedChecksum = icmpPtr->checksum;
            icmpPtr->checksum = 0;
            calculatedChecksum = in_cksum(icmpPtr, [packet length] - icmpHeaderOffset);
            icmpPtr->checksum = receivedChecksum;
            
//            if (receivedChecksum == calculatedChecksum) {
            if ((icmpPtr->type == kICMPTypeTimeExceed || icmpPtr->type == kICMPTypeEchoReply) && icmpPtr->code == 0) {
                endFlag = icmpPtr == kICMPTypeEchoReply;
                
//                [self.resultDelegate traceRouter:self didReceiveResponseICMPPacketHeader:icmpPtr];
                int ttl = self.sequenceNumber / try_cnt;
                // if (sendTime == 0) { // error occured }
                double roundTripTime = [[self class] currentTimeMillis] - sendTime;
                sendTime = 0;
                
                [self.resultDelegate didReceiveReceiveForTTL:ttl fromAddr:addr roundTripTime:roundTripTime];
                // Round Trip Time 은 어떻게 넘길까
            } else {
                NSLog(@"Received the other packet");
                [self failWithErrorCode:TraceRouterErrorCodeReceivedUnknownPacket reason:@"Received unknown packet" description:@{@"Data":packet}];
                endFlag = YES;
            }
            
//            [self addRouteAddress:addr receivedTime:recvTime];
//            } else {
                // checksum...
//                NSLog(@"Checksum is incorrect");
//            }
        }
    }
    
    free(buffer);
    
    if (endFlag || traceroute_end_time <= [[self class] currentTimeMillis]) {
        if (self.completion) {
            self.completion(nil);
        }
        
        return;
    }
    
    self.sequenceNumber++;
    [self sendICMPPacket];

    //-------------------Hop 정보 추가 방법 변경 필요--------------------
//    if (endFlag == YES && self.sequenceNumber % try_cnt == 0) {
//        if (self.completion) {
//            [self.routeArray addObject:self.currentTTLResult];
//            double currentTime = [[self class] currentTimeMillis];
//            NSDictionary *resultDictionary = @{
//                                               kHostName: self.hostName,
//                                               kIpAddresss: self.hostIpString,
//                                               kResultArray: self.routeArray,
//                                               kCompletedFlag: @(YES),
//                                               kTotalRunTimeSec: @((currentTime - traceroute_start_time)/1000)
//                                               };
//            self.completion(resultDictionary);
//        }
//    } else {
//        self.sequenceNumber++;
//        [self sendICMPPacket];
//    }
    //---------------------------------------------------
}

static void SocketReadCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
// This C routine is called by CFSocket when there's data waiting on our ICMP socket.
// It just redirects the call to Objective-C code.
{
    NewTraceRouter *traceRouter;
    
    traceRouter = (__bridge NewTraceRouter *)info;
    [traceRouter readReceivedData];
}



@end
