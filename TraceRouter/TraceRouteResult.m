//
//  TraceRouteResult.m
//  TraceRouter
//
//  Created by Naver on 2015. 12. 24..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import "TraceRouteResult.h"

#include <netdb.h>
#include <arpa/inet.h>

@interface TraceRouteResult()

@property (strong, nonatomic, readwrite) NSString *hostName;
@property (strong, nonatomic, readwrite) NSString *hostIPAddress;
@property (strong, nonatomic, readwrite) NSMutableArray *resultsForTTL;
@property (assign, nonatomic, readwrite) BOOL isCompleted;
@property (assign, nonatomic, readwrite) double elapsedTime;

@end

@implementation TraceRouteResult

- (instancetype) initWithHostname:(NSString *)hostName
{
    self = [super init];
    
    if (self) {
        self.hostName = hostName;
        self.resultsForTTL = [[NSMutableArray alloc] init];
        self.isCompleted = NO;
        self.elapsedTime = 0.0;
    }
    
    return self;
}

- (NSString *)hostNameForSockaddr:(struct sockaddr_in)addr
{
    struct hostent *hostent = gethostbyaddr(&addr.sin_addr, sizeof(addr.sin_addr), AF_INET);
    NSString *addrHostName = nil;
    
    if (hostent != NULL && hostent->h_name != NULL) {
        addrHostName = [NSString stringWithCString:hostent->h_name encoding:NSASCIIStringEncoding];
    }
    
    return addrHostName;
}

- (void)didReceiveResponseForTTL:(int)ttl fromAddr:(struct sockaddr_in)fromAddr roundTripTime:(double)roundTripTime
{
    char addr_str[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &fromAddr.sin_addr.s_addr, addr_str, sizeof(addr_str));
    
    NSString *fromAddrString = [NSString stringWithCString:addr_str encoding:NSASCIIStringEncoding];
    
    if (self.resultsForTTL[ttl] == nil) {
        self.resultsForTTL[ttl] = [[NSMutableDictionary alloc] init];
    }
    
    NSMutableDictionary *ttlResultDic = self.resultsForTTL[ttl];
    if (ttlResultDic[fromAddrString] == nil) {
        ttlResultDic[fromAddrString] = @{
                                         kHostName: [self hostNameForSockaddr:fromAddr],
                                         kRoundTripTime: [NSMutableArray arrayWithObject:@(roundTripTime)]
                                         };
    } else {
        NSMutableArray *roundTripTimeArray = ttlResultDic[fromAddrString][kRoundTripTime];
        [roundTripTimeArray addObject:@(roundTripTime)];
    }
}

- (void)didFinishTraceRouteWithEndFlag:(BOOL)endFlag elapsedTime:(double)elapsedTime
{
    self.isCompleted = endFlag;
    self.elapsedTime = elapsedTime;
}


#pragma mark - make string from result dictionary

- (NSString *)stringForRoundTripTimeArray:(NSArray *)array
{
    NSMutableString *arrString = [[NSMutableString alloc] init];
    
    [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [arrString appendString:[NSString stringWithFormat:@"%.3f ms ", [obj doubleValue]]];
    }];
    
    return arrString;
}

- (NSString *)descriptionForTraceRouteResult
{
    // Destination : 127.0.0.1 (www.hostname.com)
    // ------- Trace Route Result -------
    // TTL  IP (HostName)  RoundTripTime
    //  1   10.64.160.2 (10.64.160.2) 1.28 ms 0.87 ms 1.02 ms
    //  2   10.64.160.2 (10.64.160.2) 0.04 ms
    //      10.28.158.7 (10.28.158.7) 0.47 ms 0.32 ms
    //  3   10.22.0.25 (some-host.name.net) 0.93 ms 1.04 ms 1.21 ms
    //  ...
    
    NSMutableString *resultStr = [NSMutableString stringWithFormat:@"Destination : %@ (%@)\n", self.hostIPAddress, self.hostName];
    [resultStr appendString:@"-------- Trace Route Result --------\n"];
    [resultStr appendString:@"TTL\tIP (HostName) - RoundTripTime\n"];
    
    NSArray *resultArr = self.resultsForTTL;
    for (int i = 0; i < resultArr.count; i++) {
        NSDictionary *hop = resultArr[i];
        [resultStr appendString:[NSString stringWithFormat:@"%3d", i+1]];
        
        if ([hop count] == 0) {
            [resultStr appendString:@"\t*\n"];
        } else {
            [hop enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                [resultStr appendString:
                 [NSString stringWithFormat:@"\t%@ (%@) - %@", key, obj[kHostName], [self stringForRoundTripTimeArray:obj[kRoundTripTime]]]];
                [resultStr appendString:@"\n"];
            }];
        }
    }
    
    if (self.isCompleted == YES) {
        [resultStr appendString:@"Trace route completed "];
    } else {
        [resultStr appendString:@"Trace route aborted "];
    }
    
    [resultStr appendString:[NSString stringWithFormat:@"(%.3f sec)", self.elapsedTime]];
    
    return resultStr;
}

@end
