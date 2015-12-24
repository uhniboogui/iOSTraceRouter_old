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


@interface LVTraceRouteManager() //<TraceRouteOperationDelegate>
@property (strong, nonatomic) NSMutableDictionary *tracerouteDict;

@property (strong, nonatomic) NSOperationQueue *traceRouteOperationQueue;
@end

@implementation LVTraceRouteManager

- (instancetype) init
{
    self = [super init];
    if (self) {
        self.timeoutMillisec = 25000;
        self.maxTTL = 64;
        self.port = 80;
        self.tryCount = 3;
        self.overallTimeoutSec = 30;
        
        self.traceRouteOperationQueue = [[NSOperationQueue alloc] init];
        self.traceRouteOperationQueue.name = @"TraceRoute Queue";
        self.traceRouteOperationQueue.maxConcurrentOperationCount = 1;
        
        self.tracerouteDict = [[NSMutableDictionary alloc] init];
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
        LVTraceRouteOperation *trOperation = [[LVTraceRouteOperation alloc] initWithHostname:host
                                                                             timeoutMillisec:self.timeoutMillisec
                                                                                      maxTTL:self.maxTTL
                                                                                        port:self.port
                                                                                    tryCount:self.tryCount
                                                                           overallTimeoutSec:self.overallTimeoutSec
                                                                             completionBlock:^(NSDictionary *result) {
                                                                                 NSString *hostName = result[kHostName];
                                                                                 self.tracerouteDict[hostName] = result;
                                                                                 
                                                                                 NSString *resultString = [self resultForHost:hostName];
                                                                                 NSLog(@"result - %@", resultString);
                                                                                 if (self.success) {
                                                                                     self.success(resultString);
                                                                                 }
                                                                             } errorBlock:^(NSError *error) {
                                                                                 NSLog(@"error : %@", error);
                                                                                 if (self.fail) {
                                                                                     self.fail(error);
                                                                                 }
                                                                             }];
        //        traceRouteOperation.delegate = self;
        
        self.tracerouteDict[host] = trOperation;
        [self.traceRouteOperationQueue addOperation:trOperation];
    } else {
        if (self.success) {
            self.success([self resultForHost:host]);
        }
        NSLog(@"result - %@", [self resultForHost:host]);
    }
}

- (void)cancelTracerouteForHost:(NSString *)host
{
    id tracerouteElement = self.tracerouteDict[host];
    
    if ([tracerouteElement isKindOfClass:[LVTraceRouteOperation class]]) {
        [(LVTraceRouteOperation *)tracerouteElement cancel];
        [self.tracerouteDict removeObjectForKey:host];
    }
}

- (NSString *)stringForRoundTripTimeArray:(NSArray *)array
{
    NSMutableString *arrString = [[NSMutableString alloc] init];
    
    [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [arrString appendString:[NSString stringWithFormat:@"%.3f ms ", [obj doubleValue]]];
    }];
    
    return arrString;
}

- (NSString *)resultForHost:(NSString *)host
{
    // Destination : 127.0.0.1 (www.hostname.com)
    // ------- Trace Route Result -------
    // TTL  IP (HostName)  RoundTripTime
    //  1   10.64.160.2 (10.64.160.2) 1.28 ms 0.87 ms 1.02 ms
    //  2   10.64.160.2 (10.64.160.2) 0.04 ms
    //      10.28.158.7 (10.28.158.7) 0.47 ms 0.32 ms
    //  3   10.22.0.25 (some-host.name.net) 0.93 ms 1.04 ms 1.21 ms
    //  ...
    if (self.tracerouteDict[host] == nil) {
        return [NSString stringWithFormat:@"Traceroute for host %@ is not created", host];
    } else if ([self.tracerouteDict[host] isKindOfClass:[LVTraceRouteOperation class]]) {
        return [NSString stringWithFormat:@"Traceroute for host %@ is now creating", host];
    }
    
    NSDictionary *resultDict = self.tracerouteDict[host];
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
    
    if ([resultDict[kCompletedFlag] boolValue] == YES) {
        [resultStr appendString:@"Trace route completed "];
    } else {
        [resultStr appendString:@"Trace route aborted "];
    }
    
    [resultStr appendString:[NSString stringWithFormat:@"(%.3f sec)", [resultDict[kTotalRunTimeSec] doubleValue]]];
    
    return resultStr;
}

- (BOOL)isCheckedHost:(NSString *)host
{
    return self.tracerouteDict[host] != nil;
}

#pragma mark - TraceRouteOperationDelegate

- (void)traceRouteDidFinish:(NSDictionary *)result
{
    NSString *hostName = result[kHostName];
    self.tracerouteDict[hostName] = result;
    
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
