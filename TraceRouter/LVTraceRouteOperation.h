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

@protocol TraceRouteOperationDelegate <NSObject>
- (void)traceRouteDidFinish:(NSDictionary *)result;

@optional
- (void)traceRouteDidFailWithError:(NSError *)error;
@end

@interface LVTraceRouteOperation : NSOperation
- (instancetype) initWithHostname:(NSString *)hostName
                  timeoutMillisec:(int)timeoutMillisec
                           maxTTL:(int)maxTTL
                             port:(int)destPort
                         tryCount:(int)tryCount;

@property (weak, nonatomic) id<TraceRouteOperationDelegate> delegate;
@property (strong, nonatomic, readonly) NSString *hostName;
@end
