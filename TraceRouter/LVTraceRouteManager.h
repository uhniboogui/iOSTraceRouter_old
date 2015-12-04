//
//  LVTraceRouteManager.h
//  LineVod
//
//  Created by Naver on 2015. 11. 20..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^successBlock)(NSString *);
typedef void (^failBlock)(NSError *);

@interface LVTraceRouteManager : NSObject
@property (assign, nonatomic) int timeoutMillisec;
@property (assign, nonatomic) int maxTTL;
@property (assign, nonatomic) int port;
@property (assign, nonatomic) int tryCount;

@property (copy) successBlock success;
@property (copy) failBlock fail;

- (void)addHost:(NSString *)host;
@end
