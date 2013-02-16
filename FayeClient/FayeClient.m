/* The MIT License
 
 Copyright (c) 2011 Paul Crawford
 Copyright (c) 2013 Tyrone Trevorrow
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE. */

//
//  FayeClient.m
//  FayeObjC
//

#import "FayeClient.h"
#import "FayeMessage.h"
#import "FayeChannel.h"
#import "FayeServer.h"
#import "SRWebSocket.h"

static NSString * const FayeClientBayeuxVersion = @"1.0";

NSString * const FayeClientHandshakeChannel = @"/meta/handshake";
NSString * const FayeClientConnectChannel = @"/meta/connect";
NSString * const FayeClientDisconnectChannel = @"/meta/disconnect";
NSString * const FayeClientSubscribeChannel = @"/meta/subscribe";
NSString * const FayeClientUnsubscribeChannel = @"/meta/unsubscribe";

@interface FayeClient () <SRWebSocketDelegate, NSURLConnectionDataDelegate, NSURLConnectionDelegate>
@property (nonatomic, retain) SRWebSocket* webSocket;
@property (nonatomic, strong) NSMutableDictionary *subscriptions;
@property (nonatomic, strong) NSFileHandle *logFile;
@property (nonatomic, strong) FayeServer *currentServer;
@property (nonatomic, strong) NSMutableDictionary *servers;
@property (nonatomic, copy) FayeClientConnectionStatusHandlerBlock connectionStatusHandler;
@property (nonatomic, strong) NSURLResponse *lastResponse;
@property (nonatomic, strong) NSMutableArray *queuedMessages;
@property (nonatomic, strong) NSURLConnection *httpConnection;

- (void) _debugMessage: (NSString*) format, ... NS_FORMAT_FUNCTION(1,2);

@end

@implementation FayeClient {
    struct {
        BOOL statusChanged:1;
        BOOL receivedMessage:1;
        BOOL subscribed:1;
        BOOL unsubscribed:1;
        BOOL sentMessage:1;
    } _delegateRespondsTo;
    
    NSInteger _nextSortIndex;
    NSInteger _messageID;
}

#pragma mark - Initialization

- (id) init
{
    self = [super init];
    if (self) {
        self.servers = [NSMutableDictionary dictionary];
        self.timeout = 10;
        self.handshakeExtension = @{};
        self.connectExtension = @{};
        self.extension = @{};
        _nextSortIndex = 0;
    }
    return self;
}

+ (instancetype) fayeClientWithURL:(NSURL *)url
{
    FayeClient *client = [[self alloc] init];
    [client addServerWithURL: url];
    return client;
}

- (void) addServerWithURL:(NSURL *)url
{
    NSString *serverKey = [url absoluteString];
    if (self.servers[serverKey] != nil) {
        [self _debugMessage: @"Server: '%@' already added... ignoring.", url];
        return;
    }
    
    FayeServer *server = [FayeServer fayeServerWithURL: url];
    server.sortIndex = _nextSortIndex++;
    self.servers[serverKey] = server;
}

- (void) setDelegate:(id<FayeClientDelegate>)delegate
{
    if (delegate != _delegate) {
        [self willChangeValueForKey: @"delegate"];
        _delegate = delegate;
        _delegateRespondsTo.statusChanged = [delegate respondsToSelector: @selector(fayeClientConnectionStatusChanged:)];
        _delegateRespondsTo.receivedMessage = [delegate respondsToSelector: @selector(fayeClient:receivedMessage:onChannel:)];
        _delegateRespondsTo.subscribed = [delegate respondsToSelector: @selector(fayeClient:subscribedToChannel:)];
        _delegateRespondsTo.unsubscribed = [delegate respondsToSelector: @selector(fayeClient:unsubscribedFromChannel:)];
        _delegateRespondsTo.sentMessage = [delegate respondsToSelector: @selector(fayeClient:sentMessage:toChannel:)];
        [self didChangeValueForKey: @"delegate"];
    }
}

#pragma mark - Channels

- (void) subscribeToChannel:(NSString *)channel
{
    
}

- (void) subscribeToChannel:(NSString *)channel messageHandler:(FayeClientChannelMessageHandlerBlock)handler
{
    
}

- (void) subscribeToChannel:(NSString *)channel
             messageHandler:(FayeClientChannelMessageHandlerBlock)messageHandler
          completionHandler:(dispatch_block_t)completionHandler
{
    
}

- (void) unsubscribeFromChannel:(NSString *)channel
{
    
}

- (void) unsubscribeFromChannel:(NSString *)channel completionHandler:(dispatch_block_t)handler
{
    
}

- (void) setExtension:(NSDictionary *)extension forChannel:(NSString *)channel
{
    
}

#pragma mark - Publishing Messages

- (void) sendMessage:(NSDictionary *)message toChannel:(NSString *)channel
{
    
}

- (void) sendMessage:(NSDictionary *)message
           toChannel:(NSString *)channel
           extension:(NSDictionary *)extension
{
    
}

- (void) sendMessage:(NSDictionary *)message
           toChannel:(NSString *)channel
           extension:(NSDictionary *)extension
   completionHandler:(dispatch_block_t)handler
{
    
}

#pragma mark - Connection / Disconnection

- (void) connect
{
    [self connectWithConnectionStatusChangedHandler: nil];
}

- (void) connectWithConnectionStatusChangedHandler:(FayeClientConnectionStatusHandlerBlock)handler
{
    if ([self.servers count] == 0) {
        [self _debugMessage: @"Ignoring connect message: no servers."];
        return;
    }
    self.connectionStatusHandler = handler;
    self.currentServer = [[self sortedServers] objectAtIndex: 0];
    self.connectionStatus = FayeClientConnectionStatusConnecting;
    if ([self.currentServer connectsWithLongPolling]) {
        [self connectWithLongPolling];
    } else {
        [self connectWithWebSocket];
    }
}

- (void) disconnect
{
    self.connectionStatusHandler = nil;
}

#pragma mark - WebSockets

- (void) connectWithWebSocket
{
    
}

- (void) webSocketDidOpen:(SRWebSocket *)webSocket
{
    
}

- (void) webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    
}

- (void) webSocket:(SRWebSocket *)webSocket
  didCloseWithCode:(NSInteger)code
            reason:(NSString *)reason
          wasClean:(BOOL)wasClean
{
    
}

- (void) webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    
}

#pragma mark - HTTP Long Polling

- (void) connectWithLongPolling
{
    [self.queuedMessages insertObject: [self handshakeMessage] atIndex: 0];
    [self startHTTPConnection];
}

- (void) startHTTPConnection
{
    [self.queuedMessages insertObject: [self connectMessage] atIndex: 0];
    NSArray *messages = self.queuedMessages.copy;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject: messages options: 0 error: &error];
    if (error) {
        [self _failWithError: error];
        return;
    }
    [self.queuedMessages removeAllObjects];
    
    if (self.httpConnection != nil) {
        [self.httpConnection cancel];
        self.httpConnection = nil;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: self.currentServer.url
                                                           cachePolicy: NSURLCacheStorageNotAllowed
                                                       timeoutInterval: self.timeout];
    [request setHTTPMethod: @"POST"];
    [request setHTTPBody: data];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    self.httpConnection = [NSURLConnection connectionWithRequest: request delegate: self];
    [self.httpConnection start];
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    self.currentServer.failures += 1;
    [self connectWithConnectionStatusChangedHandler: self.connectionStatusHandler];
}

- (void) connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    
}

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    
}

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self _debugMessage: @"LONG-POLLING: Interval"];
    if ([self.lastResponse isKindOfClass: [NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *response = (NSHTTPURLResponse*) self.lastResponse;
        if (response.statusCode >= 400) {
            // EPIC FAIL
            [self disconnectNow];
            return;
        }
    }
    [self startHTTPConnection];
}

#pragma mark - Message Assembly

- (NSDictionary*) handshakeMessage
{
    NSArray *connectionTypes = nil;
    if ([self.currentServer connectsWithLongPolling]) {
        connectionTypes = @[@"long-polling"];
    } else {
        connectionTypes = @[@"websocket"];
    }
    NSMutableDictionary *handshakeMessage = [NSMutableDictionary new];
    [handshakeMessage addEntriesFromDictionary:
     @{ @"channel": FayeClientHandshakeChannel,
     @"version": FayeClientBayeuxVersion,
     @"minimumVersion": FayeClientBayeuxVersion,
     @"supportedConnectionTypes": connectionTypes
     }];
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, self.handshakeExtension]];
    if ([ext count] > 0) {
        handshakeMessage[@"ext"] = ext;
    }
    if (self.clientID) {
        handshakeMessage[@"clientId"] = self.clientID;
    }
    return handshakeMessage.copy;
}

- (NSDictionary*) connectMessage
{
    NSString *connectionType = @"websocket";
    if ([self.currentServer connectsWithLongPolling]) {
        connectionType = @"long-polling";
    }
    NSMutableDictionary *connectMessage = [NSMutableDictionary new];
    [connectMessage addEntriesFromDictionary:
     @{ @"channel": FayeClientConnectChannel,
     @"connectionType": connectionType,
     @"id": [self nextMessageID],
     }];
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, self.connectExtension]];
    if ([ext count] > 0) {
        connectMessage[@"ext"] = ext;
    }
    if (self.clientID) {
        connectMessage[@"clientId"] = self.clientID;
    }
    return connectMessage.copy;
}

- (NSDictionary*) subscribeMessageForChannelPath: (NSString*) channelPath
{
    NSMutableDictionary *subscribeMessage = [NSMutableDictionary new];
    [subscribeMessage addEntriesFromDictionary:
     @{ @"channel": FayeClientSubscribeChannel,
     @"id": [self nextMessageID],
     @"subscription": channelPath}];
    FayeChannel *channel = self.subscriptions[channelPath];
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, channel.extension]];
    if ([ext count] > 0) {
        subscribeMessage[@"ext"] = ext;
    }
    if (self.clientID) {
        subscribeMessage[@"clientId"] = self.clientID;
    }
}

- (NSString*) nextMessageID
{
    static const char chars[] = "0123456789abcdefghijklmnopqrstuvwxyz";
    _messageID++;
    if (_messageID == NSIntegerMax) {
        _messageID = 1;
    }
    NSInteger val = _messageID;
    // Why 14? log(2^64) / log(36) = ~12.4 + 1 (for the NULL terminator), rounded up = 14
    char buffer[14];
    unsigned int offset = sizeof(buffer);
    // NULL terminate the string...
    buffer[--offset] = '\0';
    do {
        buffer[--offset] = chars[val % 36];
    } while (val /= 36);
    char *finalCString = strdup(&buffer[offset]);
    NSString *finalString = [NSString stringWithUTF8String: finalCString];
    free(finalCString);
    return finalString;
}

- (NSDictionary*) mergeExtensionDictionaries: (NSArray*) dictionaries
{
    NSMutableDictionary *mergedDictionary = [NSMutableDictionary new];
    for (NSDictionary *dictionary in dictionaries) {
        [mergedDictionary addEntriesFromDictionary: dictionary];
    }
    return mergedDictionary.copy;
}

#pragma mark - Internals

- (void) queueMessage: (NSDictionary*) message
{
    if (self.connectionStatus == FayeClientConnectionStatusConnected && [self.currentServer connectsWithWebSockets]) {
        // WebSockets can send messages straight away!
    } else {
        [self.queuedMessages addObject: message];
    }
}

- (void) setConnectionStatus:(FayeClientConnectionStatus)connectionStatus
{
    if (connectionStatus != _connectionStatus) {
        [self willChangeValueForKey: @"connectionStatus"];
        _connectionStatus = connectionStatus;
        [self didChangeValueForKey: @"connectionStatus"];
        if (self.connectionStatusHandler != NULL) {
            self.connectionStatusHandler(self, nil);
        }
        if (_delegateRespondsTo.statusChanged) {
            [self.delegate fayeClientConnectionStatusChanged: self];
        }
    }
}

// Doesn't unsubscribe, doesn't update connection status.
- (void) disconnectNow
{
    if (self.httpConnection) {
        [self.httpConnection cancel];
        self.httpConnection = nil;
    }
}

- (NSArray*) sortedServers
{
    return [self.servers.allValues sortedArrayUsingSelector: @selector(compareServer:)];
}

- (void) _debugMessage:(NSString *)format, ...
{
    if (self.debug == NO) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *str = [[NSString alloc] initWithFormat: format arguments: args];
    va_end(args);
    NSLog(@"FayeClient: %@", str);
}

- (void) _failWithError: (NSError*) error
{
    [self disconnectNow];
    _connectionStatus = FayeClientConnectionStatusDisconnected;
    if (self.connectionStatusHandler != NULL) {
        self.connectionStatusHandler(self, error);
    }
    if (_delegateRespondsTo.statusChanged) {
        [self.delegate fayeClientConnectionStatusChanged: self];
    }
}

@end