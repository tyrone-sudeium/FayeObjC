//
//  FayeServer.m
//  FayeClient
//
//  Created by Tyrone Trevorrow on 16-02-13.
//  Copyright (c) 2013 Sudeium. All rights reserved.
//

#import "FayeServer.h"

@implementation FayeServer

+ (instancetype) fayeServerWithURL:(NSURL *)url
{
    FayeServer *server = [FayeServer new];
    server.url = url;
    return server;
}

- (void) setUrl:(NSURL *)url
{
    _url = url;
    if ([[url scheme] isEqualToString: @"wss"]) {
        _connectionType = FayeServerConnectionTypeSecureWebsocket;
    } else if ([[url scheme] isEqualToString: @"ws"]) {
        _connectionType = FayeServerConnectionTypeWebsocket;
    } else if ([[url scheme] isEqualToString: @"https"]) {
        _connectionType = FayeServerConnectionTypeSecureLongPolling;
    } else if ([[url scheme] isEqualToString: @"http"]) {
        _connectionType = FayeServerConnectionTypeLongPolling;
    } else {
        [NSException raise: NSInvalidArgumentException format: @"Unrecognised Faye URL scheme: '%@'", [url scheme]];
    }
}

@end
