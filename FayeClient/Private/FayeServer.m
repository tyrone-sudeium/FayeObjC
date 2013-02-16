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
        _connectionType = FayeServerConnectionTypeSecureWebSocket;
    } else if ([[url scheme] isEqualToString: @"ws"]) {
        _connectionType = FayeServerConnectionTypeWebSocket;
    } else if ([[url scheme] isEqualToString: @"https"]) {
        _connectionType = FayeServerConnectionTypeSecureLongPolling;
    } else if ([[url scheme] isEqualToString: @"http"]) {
        _connectionType = FayeServerConnectionTypeLongPolling;
    } else {
        [NSException raise: NSInvalidArgumentException format: @"Unrecognised Faye URL scheme: '%@'", [url scheme]];
    }
}

- (NSComparisonResult) compareServer:(FayeServer *)otherServer
{
    NSComparisonResult byFailures = [@(self.failures) compare: @(otherServer.failures)];
    if (byFailures == NSOrderedSame) {
        NSComparisonResult byConnectionType = [@(self.connectionType) compare: @(otherServer.connectionType)];
        if (byConnectionType == NSOrderedSame) {
            return [@(self.sortIndex) compare: @(otherServer.sortIndex)];
        } else {
            return byConnectionType;
        }
    } else {
        return byFailures;
    }
}

- (BOOL) connectsWithLongPolling
{
    return _connectionType == FayeServerConnectionTypeLongPolling || _connectionType == FayeServerConnectionTypeSecureLongPolling;
}

- (BOOL) connectsWithWebSockets
{
    return _connectionType == FayeServerConnectionTypeWebSocket || _connectionType == FayeServerConnectionTypeSecureWebSocket;
}

@end
