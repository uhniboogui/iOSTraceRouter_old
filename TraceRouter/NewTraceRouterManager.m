//
//  NewTraceRouterManager.m
//  TraceRouter
//
//  Created by Naver on 2015. 12. 22..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import "NewTraceRouterManager.h"
#import "NewTraceRouter.h"

@interface NewTraceRouterManager()<NewTraceRouterDelegate>
@property (nonatomic, strong) NSMutableDictionary *trResults;
@end

@implementation NewTraceRouterManager
- (instancetype)init
{
    self = [super init];
    
    if (self) {
        self.trResults = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

- (void)tracerouteWithHost:(NSString *)host
                completion:(void(^)(NSDictionary *, NSError*))completion
{
    if ([self isCheckedHost:host] == NO) {
        
    } else {
        // 이미 TraceRoute를 수행한 Host의 경우
        if (completion) {
            // 수행한 결과 넘김
            completion(self.trResults[host], nil);
        }
    }
}

- (BOOL)isCheckedHost:(NSString *)host
{
    return self.trResults[host] != nil;
}

#pragma mark - NewTraceRouterDelegate
- (void)traceRouter:(NewTraceRouter *)traceRouter didReceiveResponseICMPPacketHeader:(ICMPHeader)icmpHeader
{
    // traceRouter의 호스트로???
}

- (void)traceRouter:(NewTraceRouter *)traceRouter didFailWithError:(NSError *)error
{
    
}
@end
