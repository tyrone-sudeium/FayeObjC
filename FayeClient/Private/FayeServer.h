//
//  FayeServer.h
//  FayeClient
//
//  Created by Tyrone Trevorrow on 16-02-13.
//  Copyright (c) 2013 Sudeium. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, FayeServerConnectionType) {
    FayeServerConnectionTypeSecureWebsocket,
    FayeServerConnectionTypeWebsocket,
    FayeServerConnectionTypeSecureLongPolling,
    FayeServerConnectionTypeLongPolling
};

@interface FayeServer : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, readonly, assign) FayeServerConnectionType connectionType;
@property (nonatomic, assign) NSInteger failures;
@property (nonatomic, copy) NSDictionary *extension;

+ (instancetype) fayeServerWithURL: (NSURL*) url;

@end
