//
//  NewTraceRouterManager.h
//  TraceRouter
//
//  Created by Naver on 2015. 12. 22..
//  Copyright (c) 2015년 Naver. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NewTraceRouterManager : NSObject
- (void)tracerouteWithHost:(NSString *)host
                completion:(void(^)(NSDictionary *, NSError*))completion;
// HOST를 입력 받으면 Dictionary에서 이미 수행한지 판별 후 수행하지 않은 경우에 대해서만 TraceRoute 실행
// 마지막 수행시간을 비교할까??
@end
