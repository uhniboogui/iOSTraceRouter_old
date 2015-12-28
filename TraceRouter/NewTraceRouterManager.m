//
//  NewTraceRouterManager.m
//  TraceRouter
//
//  Created by Naver on 2015. 12. 22..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import "NewTraceRouterManager.h"
#import "NewTraceRouter.h"
#import "TraceRouteResult.h"

@interface NewTraceRouterManager()
@property (nonatomic, strong) NSMutableDictionary *trResults;
@end

@implementation NewTraceRouterManager
- (instancetype)initWithCompletion:(CompletionBlock)completion
{
    self = [super init];
    
    if (self) {
        self.trResults = [[NSMutableDictionary alloc] init];
        
        self.tryCount = 3;
        self.maxTTL = 64;
        self.responseTimeoutMSec = 20000;
        self.overallTimeoutSec = 240;
        
        self.completion = completion;
    }
    
    return self;
}

- (void)tracerouteWithHost:(NSString *)host
{
    if ([self isCheckedHost:host] == NO) {
        
        NewTraceRouter *newTr = [[NewTraceRouter alloc] initWithHostname:host tryCount:self.tryCount maxTTL:self.maxTTL responseTimeoutMilliSec:self.responseTimeoutMSec overallTimeoutSec:self.overallTimeoutSec completionBlock:^(NSDictionary *resultDict) {
            if (self.completion != nil) {
                self.completion(resultDict, nil);
            }
        } failureBlock:^(NSError *error) {
            if (self.completion != nil) {
                self.completion(nil, error);
            }
        }];
        
        TraceRouteResult *trResult = [[TraceRouteResult alloc] init];
        newTr.resultDelegate = trResult;
        
        // newTr을 dictionary에 넣어서 관리??
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [newTr startTraceRoute];
        });
        
    } else {
        // 이미 TraceRoute를 수행한 Host의 경우
        if (self.completion) {
            // 수행한 결과 넘김
            self.completion(self.trResults[host], nil);
        }
    }
}

- (BOOL)isCheckedHost:(NSString *)host
{
    return self.trResults[host] != nil;
}

@end
