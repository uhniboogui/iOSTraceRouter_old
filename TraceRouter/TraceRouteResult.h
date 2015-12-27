//
//  TraceRouteResult.h
//  TraceRouter
//
//  Created by Naver on 2015. 12. 24..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NewTraceRouter.h"

#define kHostName @"HostName"
#define kIpAddresss @"IpAddress"
#define kResultArray @"ResultArray"
#define kRoundTripTime @"RoundTripTime"
#define kCompletedFlag @"CompletedFlag"
#define kTotalRunTimeSec @"TotalRunTimeSec"

@interface TraceRouteResult : NSObject<NewTraceRouterDelegate>
@property (strong, nonatomic, readonly) NSString *hostName;
@property (strong, nonatomic, readonly) NSString *hostIPAddress;
@property (strong, nonatomic, readonly) NSMutableArray *resultsForTTL;
@property (assign, nonatomic, readonly) BOOL isCompleted;
@property (assign, nonatomic, readonly) double elapsedTime;
@end
