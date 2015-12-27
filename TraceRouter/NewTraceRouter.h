//
//  NewTraceRouter.h
//  TraceRouter
//
//  Created by Naver on 2015. 12. 15..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import <Foundation/Foundation.h>



typedef void (^completionBlock)(NSDictionary *);
typedef void (^failureBlock)(NSError *);


struct ICMPHeader {
    uint8_t     type;
    uint8_t     code;
    uint16_t    checksum;
    uint16_t    identifier;
    uint16_t    sequenceNumber;
    // data...
};
typedef struct ICMPHeader ICMPHeader;


typedef NS_ENUM(NSInteger, TraceRouterErrorCode) {
    TraceRouterErrorCodeCannotFindHost = 2000,
    TraceRouterErrorCodeCannotOpenSocket = 2001,
    TraceRouterErrorCodeSetSocketOptionFailed = 2002,
    TraceRouterErrorCodeCreatingICMPPacketFailed = 2003,
    TraceRouterErrorCodeReceivedUnknownPacket = 2004,
    TraceRouterErrorCodeSendingError = 2005,
    TraceRouterErrorCodeCannotReceiveData = 2006,
    
};


@protocol NewTraceRouterDelegate;

@interface NewTraceRouter : NSObject
@property (nonatomic, strong) id<NewTraceRouterDelegate> resultDelegate;

- (instancetype) initWithHostname:(NSString *)hostName
                         tryCount:(int)tryCount
                           maxTTL:(int)maxTTL
          responseTimeoutMilliSec:(int)responseTimeoutMilliSec
                overallTimeoutSec:(int)overallTimeoutSec
                  completionBlock:(completionBlock)completionBlock
                     failureBlock:(failureBlock)failureBlock;
- (void)startTraceRoute;

//+ (NSString *)resultForDictionary:(NSDictionary *)resultDict;
@end

@protocol NewTraceRouterDelegate <NSObject>
- (void)didReceiveResponseForTTL:(int)ttl fromAddr:(struct sockaddr_in)fromAddr roundTripTime:(double)roundTripTime;
- (void)didFinishTraceRouteWithEndFlag:(BOOL)endFlag elapsedTime:(double)elapsedTime;
@end
