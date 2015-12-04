//
//  LVTraceRouteManager.m
//  LineVod
//
//  Created by Naver on 2015. 11. 20..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import "LVTraceRouteManager.h"
#import "LVTraceRouteOperation.h"

#include <netdb.h>
#include <arpa/inet.h>
#include <sys/time.h>

#define RESPONSE_PACKET_LENGTH 64


@interface LVTraceRouteManager()<TraceRouteOperationDelegate>
@property (strong, nonatomic) NSMutableDictionary *checkedHosts;

@property (strong, nonatomic) NSOperationQueue *traceRouteOperationQueue;
@end

@implementation LVTraceRouteManager

- (instancetype) init
{
    self = [super init];
    if (self) {
        self.timeoutMillisec = 15000;
        self.maxTTL = 255;
        self.port = 30000;
        self.tryCount = 3;
        
        self.traceRouteOperationQueue = [[NSOperationQueue alloc] init];
        self.traceRouteOperationQueue.name = @"TraceRoute Queue";
        self.traceRouteOperationQueue.maxConcurrentOperationCount = 1;
        
        self.checkedHosts = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (void)setTraceRouteConcurrentOperationCount:(int)count
{
    self.traceRouteOperationQueue.maxConcurrentOperationCount = count;
}

- (void)addHost:(NSString *)host
{
    // Queue에 추가
    if ([self isCheckedHost:host] == NO) {
        LVTraceRouteOperation *traceRouteOperation = [[LVTraceRouteOperation alloc] initWithHostname:host
                                                                                     timeoutMillisec:self.timeoutMillisec
                                                                                              maxTTL:self.maxTTL
                                                                                                port:self.port
                                                                                            tryCount:self.tryCount];
        traceRouteOperation.delegate = self;
        
        [self.traceRouteOperationQueue addOperation:traceRouteOperation];
    } else {
        if (self.success) {
            self.success([self resultForHost:host]);
        }
        NSLog(@"result - %@", [self resultForHost:host]);
    }
}

- (NSString *)stringForRoundTripTimeArray:(NSArray *)array
{
    NSMutableString *arrString = [[NSMutableString alloc] init];
    
    [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [arrString appendString:[NSString stringWithFormat:@"%.3f ", [obj doubleValue]]];
    }];
    
    return arrString;
}

- (NSString *)resultForHost:(NSString *)host
{
    // Destination : 127.0.0.1 (www.hostname.com)
    // ------- Trace Route Result -------
    // TTL  IP (HostName)  RoundTripTime
    //  1   10.64.160.2 (-) 1.28  0.87  1.02
    //  2   10.64.160.2 (-) 0.04
    //      10.28.158.7 (-) 0.47  0.32
    //  3   10.22.0.25 (-) 0.93  1.04  1.21
    //  ...
    NSDictionary *resultDict = self.checkedHosts[host];
    NSMutableString *resultStr = [NSMutableString stringWithFormat:@"Destination : %@ (%@)\n", resultDict[kIpAddresss], resultDict[kHostName]];
    [resultStr appendString:@"-------- Trace Route Result --------\n"];
    [resultStr appendString:@"TTL\tIP (HostName) - RoundTripTime\n"];
    
    NSArray *resultArr = resultDict[kResultArray];
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
    
    NSLog(@"%@", resultStr);
    return resultStr;
}

- (BOOL)isCheckedHost:(NSString *)host
{
    return self.checkedHosts[host] != nil;
}

- (void)traceRouteDidFinish:(NSDictionary *)result
{
    NSString *hostName = result[kHostName];
    self.checkedHosts[hostName] = result;
    
    NSString *resultString = [self resultForHost:hostName];
    NSLog(@"result - %@", resultString);
    
    if (self.success) {
        self.success(resultString);
    }
}

- (void)traceRouteDidFailWithError:(NSError *)error
{
    NSLog(@"error : %@", error);
    if (self.fail) {
        self.fail(error);
    }
}

@end
