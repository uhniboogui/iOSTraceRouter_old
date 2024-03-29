//
//  LVTraceRouteOperation.h
//  TraceRouter
//
//  Created by Naver on 2015. 12. 4..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kHostName @"HostName"
#define kIpAddresss @"IpAddress"
#define kResultArray @"ResultArray"
#define kRoundTripTime @"RoundTripTime"
#define kCompletedFlag @"CompletedFlag"
#define kTotalRunTimeSec @"TotalRunTimeSec"

typedef void (^completionBlock)(NSDictionary *);
typedef void (^errorBlock)(NSError *);

//@protocol TraceRouteOperationDelegate <NSObject>
//- (void)traceRouteDidFinish:(NSDictionary *)result;
//
//@optional
//- (void)traceRouter:DidFailWithError:(NSError *)error;
//@end

@interface LVTraceRouteOperation : NSOperation
- (instancetype) initWithHostname:(NSString *)hostName
                  timeoutMillisec:(int)timeoutMillisec
                           maxTTL:(int)maxTTL
                             port:(int)destPort
                         tryCount:(int)tryCount
                overallTimeoutSec:(int)overallTimeoutSec
                  completionBlock:(completionBlock)completionBlock
                       errorBlock:(errorBlock)errorBlock;

//@property (weak, nonatomic) id<TraceRouteOperationDelegate> delegate;
@property (strong, nonatomic, readonly) NSString *hostName;
@end
