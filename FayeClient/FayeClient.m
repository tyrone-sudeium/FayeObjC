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

typedef NSDictionary*(^FayeMessageQueueItemGetMessageBlock)(void);


//@interface FayeSubscriptionQueue : NSObject
//@property (nonatomic, strong) NSMutableDictionary *channelActions;
//@end
//
//
//@implementation FayeSubscriptionQueue
//
//- (void) queueSubscriptionToChannel: (NSString*) channel
//{
//    
//}
//
//- (void) queueUnsubscriptionToChannel: (NSString*) channel
//{
//    
//}
//
//@end

@interface FayeMessageQueueItem : NSObject
@property (nonatomic, copy) FayeMessageQueueItemGetMessageBlock block;
@end

@implementation FayeMessageQueueItem
+ (instancetype) itemWithBlock: (FayeMessageQueueItemGetMessageBlock) block
{
    FayeMessageQueueItem *item = [FayeMessageQueueItem new];
    item.block = block;
    return item;
}
@end

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
@property (nonatomic, strong) NSMutableData *httpData;

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
        self.subscriptions = [NSMutableDictionary dictionary];
        self.queuedMessages = [NSMutableArray array];
        self.timeout = 10;
        self.handshakeExtension = @{};
        self.connectExtension = @{};
        self.extension = @{};
        self.httpData = [NSMutableData data];
        self.debugLogFileName = @"faye.log";
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
        _delegateRespondsTo.statusChanged = [delegate respondsToSelector: @selector(fayeClientDidChangeConnectionStatus:)];
        _delegateRespondsTo.receivedMessage = [delegate respondsToSelector: @selector(fayeClient:didReceiveMessage:onChannel:)];
        _delegateRespondsTo.subscribed = [delegate respondsToSelector: @selector(fayeClient:didSubscribeToChannel:)];
        _delegateRespondsTo.unsubscribed = [delegate respondsToSelector: @selector(fayeClient:didUnsubscribeFromChannel:)];
        _delegateRespondsTo.sentMessage = [delegate respondsToSelector: @selector(fayeClient:didSendMessage:toChannel:)];
        [self didChangeValueForKey: @"delegate"];
    }
}

#pragma mark - Channels

- (void) subscribeToChannel:(NSString *)channel
{
    [self subscribeToChannel: channel messageHandler: NULL completionHandler: NULL];
}

- (void) subscribeToChannel:(NSString *)channel messageHandler:(FayeClientChannelMessageHandlerBlock)handler
{
    [self subscribeToChannel: channel messageHandler: handler completionHandler: NULL];
}

- (void) subscribeToChannel:(NSString *)channel
             messageHandler:(FayeClientChannelMessageHandlerBlock)messageHandler
          completionHandler:(dispatch_block_t)completionHandler
{
    FayeChannel *fayeChannel = self.subscriptions[channel];
    if (fayeChannel == nil) {
        fayeChannel = [FayeChannel new];
        fayeChannel.channelPath = channel;
        self.subscriptions[channel] = fayeChannel;
        [self setSubscriptionStatus: FayeChannelSubscriptionStatusUnsubscribed forChannel: channel];
    }
    fayeChannel.messageHandlerBlock = messageHandler;
    fayeChannel.statusHandlerBlock = ^(FayeClient *client, NSString* channelPath, FayeChannelSubscriptionStatus status) {
        if (status == FayeChannelSubscriptionStatusSubscribed) {
            if (completionHandler != NULL) {
                completionHandler();
            }
        }
    };
    if ([self subscriptionStatusForChannel:channel] == FayeChannelSubscriptionStatusUnsubscribed) {
        [self queueChannelSubscription: channel];
    } else if ([self subscriptionStatusForChannel:channel] == FayeChannelSubscriptionStatusUnsubscribing) {
        fayeChannel.markedForUnsubscription = NO;
        fayeChannel.markedForSubscription = YES;
    }
}

- (void) unsubscribeFromChannel:(NSString *)channel
{
    [self unsubscribeFromChannel: channel completionHandler: NULL];
}

- (void) unsubscribeFromChannel:(NSString *)channel completionHandler:(dispatch_block_t)handler
{
    FayeChannel *fayeChannel = self.subscriptions[channel];
    if (fayeChannel == nil) {
        [self _debugMessage: @"Attempt to unsubscribe from channel '%@' which is not subscribed to.", channel];
        return;
    }
    fayeChannel.messageHandlerBlock = NULL;
    if (handler != NULL) {
        fayeChannel.statusHandlerBlock = ^(FayeClient *client, NSString* channelPath, FayeChannelSubscriptionStatus status) {
            if (status == FayeChannelSubscriptionStatusUnsubscribed) {
                handler();
            }
        };
    } else {
        fayeChannel.statusHandlerBlock = NULL;
    }
    if ([self subscriptionStatusForChannel:channel] == FayeChannelSubscriptionStatusSubscribed) {
        [self queueChannelUnsubscription: channel];
    } else if ([self subscriptionStatusForChannel:channel] == FayeChannelSubscriptionStatusSubscribing) {
        fayeChannel.markedForUnsubscription = YES;
        fayeChannel.markedForSubscription = NO;
    }
}

- (void) setExtension:(NSDictionary *)extension forChannel:(NSString *)channel
{
    FayeChannel *fayeChannel = self.subscriptions[channel];
    if (fayeChannel == nil) {
        fayeChannel = [FayeChannel new];
        fayeChannel.channelPath = channel;
    }
    fayeChannel.extension = extension;
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
    [self _openLogFile];
    
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
    [self _closeLogFile];
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
    [self startHTTPConnection];
}

- (void) startHTTPConnection
{
    NSData *data = nil;
    NSError *error = nil;
    if (self.currentServer.clientID) {
        NSMutableArray *messages = [NSMutableArray new];
        [messages addObject: [self connectMessage]];
        [messages addObjectsFromArray: [self messagesFromCurrentQueue]];
        data = [NSJSONSerialization dataWithJSONObject: messages options: 0 error: &error];
        if (error) {
            [self _failWithError: error];
            return;
        }
        [self.queuedMessages removeAllObjects];
    } else {
        data = [NSJSONSerialization dataWithJSONObject: @[[self handshakeMessage]] options: 0 error: &error];
        if (error) {
            [self _failWithError: error];
            return;
        }
    }
    
    if (self.httpConnection != nil) {
        [self.httpConnection cancel];
        self.httpConnection = nil;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: self.currentServer.url
                                                           cachePolicy: NSURLCacheStorageNotAllowed
                                                       timeoutInterval: self.currentServer.timeoutAdvice];
    [request setHTTPMethod: @"POST"];
    [request setHTTPBody: data];
    [request setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    self.httpConnection = [NSURLConnection connectionWithRequest: request delegate: self];
    [self.httpConnection start];
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self _debugMessage: @"LONG-POLLING: Connection failure."];
    self.currentServer.failures += 1;
    [self cycleConnection];
}

- (void) connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    // I think only sendMessage has completion handlers to run here...
}

- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.httpData appendData: data];
}

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.lastResponse = response;
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self handleReceivedData: self.httpData];
    [self.httpData setLength: 0];
    [self _debugMessage: @"LONG-POLLING: Interval.  Timeout: %.1f", self.currentServer.timeoutAdvice];
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
     @"clientId": self.currentServer.clientID
     }];
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, self.connectExtension]];
    if ([ext count] > 0) {
        connectMessage[@"ext"] = ext;
    }
    if (self.queuedMessages.count > 0 && [self.currentServer connectsWithLongPolling]) {
        connectMessage[@"advice"] = @{ @"timeout": @0 };
    }
    return connectMessage.copy;
}

- (NSDictionary*) disconnectMessage
{
    NSMutableDictionary *disconnectMessage = [NSMutableDictionary new];
    [disconnectMessage addEntriesFromDictionary:
     @{ @"channel": FayeClientDisconnectChannel,
     @"id": [self nextMessageID],
     @"clientId": self.currentServer.clientID
     }];
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, self.connectExtension]];
    if ([ext count] > 0) {
        disconnectMessage[@"ext"] = ext;
    }
    return disconnectMessage.copy;
}

- (NSDictionary*) subscribeMessageForChannelPath: (NSString*) channelPath
{
    NSMutableDictionary *subscribeMessage = [NSMutableDictionary new];
    [subscribeMessage addEntriesFromDictionary:
     @{ @"channel": FayeClientSubscribeChannel,
     @"id": [self nextMessageID],
     @"subscription": channelPath,
     @"clientId": self.currentServer.clientID
     }];
    FayeChannel *channel = self.subscriptions[channelPath];
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, channel.extension]];
    if ([ext count] > 0) {
        subscribeMessage[@"ext"] = ext;
    }
    return subscribeMessage.copy;
}

- (NSDictionary*) unsubscribeMessageForChannelPath: (NSString*) channelPath
{
    NSMutableDictionary *unsubscribeMessage = [NSMutableDictionary new];
    [unsubscribeMessage addEntriesFromDictionary:
     @{ @"channel": FayeClientSubscribeChannel,
     @"id": [self nextMessageID],
     @"subscription": channelPath,
     @"clientId": self.currentServer.clientID
     }];
    FayeChannel *channel = self.subscriptions[channelPath];
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, channel.extension]];
    if ([ext count] > 0) {
        unsubscribeMessage[@"ext"] = ext;
    }
    return unsubscribeMessage.copy;
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

- (NSArray*) messagesFromCurrentQueue
{
    NSMutableArray *messages = [NSMutableArray new];
    for (FayeMessageQueueItem *item in self.queuedMessages.copy) {
        NSDictionary *message = nil;
        if (item.block != NULL) {
            message = item.block();
        }
        if (message != nil) {
            [messages addObject: message];
        }
    }
    return messages.copy;
}

#pragma mark - Internals

- (void) queueMessage: (FayeMessageQueueItem*) queueItem
{
    if (self.connectionStatus == FayeClientConnectionStatusConnected && [self.currentServer connectsWithWebSockets]) {
        // WebSockets can send messages straight away!
    } else {
        [self.queuedMessages addObject: queueItem];
    }
}

- (void) queueChannelSubscription: (NSString*) channel
{
    [self setSubscriptionStatus: FayeChannelSubscriptionStatusSubscribing forChannel: channel];
    [self queueMessage: [FayeMessageQueueItem itemWithBlock:^NSDictionary *{
        return [self subscribeMessageForChannelPath: channel];
    }]];
}

- (void) queueChannelUnsubscription: (NSString*) channel
{
    [self setSubscriptionStatus: FayeChannelSubscriptionStatusUnsubscribing forChannel: channel];
    [self queueMessage: [FayeMessageQueueItem itemWithBlock:^NSDictionary *{
        return [self unsubscribeMessageForChannelPath: channel];
    }]];
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
            [self.delegate fayeClientDidChangeConnectionStatus: self];
        }
    }
}

- (void) handleReceivedData: (NSData*) data
{
    NSError *error = nil;
    NSArray *messages = [NSJSONSerialization JSONObjectWithData: data options: 0 error: &error];
    if (error) {
        [self _failWithError: error];
        return;
    }
    
    if (self.debug) {
        [self _debugFayeMessage: messages];
    }
    
    for (NSDictionary *messageJSON in messages) {
        FayeMessage *message = [[FayeMessage alloc] initWithDict: messageJSON];
        if (message.advice) {
            [self handleAdvice: message.advice];
            // Advice can cause a disconnect... we shouldn't proceed if we've been disconnected.
            if (self.connectionStatus == FayeClientConnectionStatusDisconnected) {
                return;
            }
        }
        if (message.successful != nil && message.successful.boolValue == NO) {
            [self _debugMessage: @"Unsuccessful faye message: %@", message];
            continue;
        }
        
        if ([message.channel isEqualToString: FayeClientConnectChannel]) {
            [self handleConnectMessage: message];
        } else if ([message.channel isEqualToString: FayeClientDisconnectChannel]) {
            [self handleDisconnectMessage: message];
        } else if ([message.channel isEqualToString: FayeClientHandshakeChannel]) {
            [self handleHandshakeMessage: message];
        } else if ([message.channel isEqualToString: FayeClientSubscribeChannel]) {
            [self handleSubscribeMessage: message];
        } else if ([message.channel isEqualToString: FayeClientUnsubscribeChannel]) {
            [self handleUnsubscribeMessage: message];
        } else {
            [self handleOtherMessage: message];
        }
    }
}

- (void) handleConnectMessage: (FayeMessage*) message
{
    if (![message.clientId isEqualToString: self.currentServer.clientID]) {
        self.currentServer.clientID = message.clientId;
    }
    if (self.connectionStatus == FayeClientConnectionStatusConnecting) {
        self.connectionStatus = FayeClientConnectionStatusConnected;
    }
}

- (void) handleDisconnectMessage: (FayeMessage*) message
{
    for (NSString *channelPath in self.subscriptions) {
        [self setSubscriptionStatus: FayeChannelSubscriptionStatusUnsubscribed forChannel: channelPath];
    }
    if (self.connectionStatus == FayeClientConnectionStatusDisconnecting) {
        [self disconnectNow];
    }
}

- (void) handleHandshakeMessage: (FayeMessage*) message
{
    self.currentServer.clientID = message.clientId;
    [self _debugMessage: @"Handshake complete.  New client ID: '%@'", message.clientId];
    
    for (NSString *channelPath in self.subscriptions) {
        if ([self subscriptionStatusForChannel: channelPath] == FayeChannelSubscriptionStatusUnsubscribed) {
            [self queueChannelSubscription: channelPath];
        }
    }
}

- (void) handleSubscribeMessage: (FayeMessage*) message
{
    FayeChannel *channel = self.subscriptions[message.subscription];
    NSAssert(channel != nil, @"Received subscribe message for channel: '%@' but I don't remember subscribing to it.", message.channel);
    NSAssert([self subscriptionStatusForChannel: channel.channelPath] == FayeChannelSubscriptionStatusSubscribing, @"Received subscribe message for channel: '%@' but its subscription status is in the wrong state.", message.channel);
    [self setSubscriptionStatus: FayeChannelSubscriptionStatusSubscribed forChannel: message.channel];
    [self _debugMessage: @"Subscribed to: '%@'", channel.channelPath];
}

- (void) handleUnsubscribeMessage: (FayeMessage*) message
{
    FayeChannel *channel = self.subscriptions[message.subscription];
    NSAssert(channel != nil, @"Received unsubscribe message for channel: '%@' but I don't remember subscribing to it.", message.channel);
    NSAssert([self.currentServer.channelStatus[message.channel] integerValue] == FayeChannelSubscriptionStatusUnsubscribing, @"Received unsubscribe message for channel: '%@' but its subscription status is in the wrong state.", message.channel);
    [self setSubscriptionStatus: FayeChannelSubscriptionStatusUnsubscribed forChannel: message.channel];
    [self _debugMessage: @"Unsubscribed from: '%@'", channel.channelPath];
}

- (void) handleOtherMessage: (FayeMessage*) message
{
    FayeChannel *channel = self.subscriptions[message.channel];
    if (channel == nil) {
        // Try to match a wildcard channel
        NSMutableArray *messageChannelComponents = [message.channel componentsSeparatedByString:@"/"].mutableCopy;
        [messageChannelComponents removeLastObject];
        [messageChannelComponents addObject: @"*"];
        NSString *channelKey = [messageChannelComponents componentsJoinedByString: @"/"];
        channel = self.subscriptions[channelKey];
    }
    if (channel != nil) {
        if(message.data) {
            if (_delegateRespondsTo.receivedMessage) {
                [self.delegate fayeClient: self didReceiveMessage: message.data onChannel: message.channel];
            }
        }
        if (channel.messageHandlerBlock != NULL) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                channel.messageHandlerBlock(self, message.channel, message.data);
            });
        }
    } else {
        [self _debugMessage: @"NO MATCH FOR CHANNEL %@", message.channel];
    }
}

- (void) handleAdvice: (NSDictionary*) advice
{
    self.currentServer.advice = advice;
    if ([self.currentServer.reconnectAdvice isEqualToString: @"handshake"] && self.connectionStatus != FayeClientConnectionStatusDisconnected) {
        [self _debugMessage: @"Re-handshaking with server on server's advice."];
        self.currentServer.clientID = nil;
        [self cycleConnection];
    }
}

- (FayeChannelSubscriptionStatus) subscriptionStatusForChannel: (NSString*) channel
{
    NSNumber *num = self.currentServer.channelStatus[channel];
    if (num == nil) {
        return FayeChannelSubscriptionStatusUnsubscribed;
    } else {
        return [num integerValue];
    }
}

- (void) setSubscriptionStatus: (FayeChannelSubscriptionStatus) status forChannel: (NSString*) channel
{
    FayeChannelSubscriptionStatus oldStatus = [self subscriptionStatusForChannel: channel];
    if (status != oldStatus) {
        [self _debugMessage: @"Status for '%@': %i", channel, status];
        self.currentServer.channelStatus[channel] = @(status);
        FayeChannel *fayeChannel = self.subscriptions[channel];
        if (fayeChannel.statusHandlerBlock != NULL) {
            fayeChannel.statusHandlerBlock(self, channel, status);
        }
        if (status == FayeChannelSubscriptionStatusSubscribed && _delegateRespondsTo.subscribed) {
            [self.delegate fayeClient: self didSubscribeToChannel: channel];
        } else if (status == FayeChannelSubscriptionStatusUnsubscribed && _delegateRespondsTo.unsubscribed) {
            [self.delegate fayeClient: self didUnsubscribeFromChannel: channel];
        }
        
        if (status == FayeChannelSubscriptionStatusSubscribed && fayeChannel.markedForUnsubscription) {
            fayeChannel.markedForSubscription = NO;
            fayeChannel.markedForUnsubscription = NO;
            [self queueChannelUnsubscription: channel];
        } else if (status == FayeChannelSubscriptionStatusUnsubscribed && fayeChannel.markedForSubscription) {
            fayeChannel.markedForSubscription = NO;
            fayeChannel.markedForUnsubscription = NO;
            [self queueChannelSubscription: channel];
        }
    }
}

- (void) cycleConnection
{
    [self disconnectNow];
    self.connectionStatus = FayeClientConnectionStatusDisconnected;
    double delayInSeconds = self.currentServer.intervalAdvice;
    if (delayInSeconds < 3) {
        delayInSeconds = 3;
    }
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self connectWithConnectionStatusChangedHandler: self.connectionStatusHandler];
    });
}

// Doesn't unsubscribe, doesn't update connection status.
- (void) disconnectNow
{
    if (self.httpConnection) {
        [self.httpConnection cancel];
        self.httpConnection = nil;
    }
    [self _closeLogFile];
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

- (void) _debugFayeMessage: (NSArray*) messageArray
{
    if (self.debug == NO) {
        return;
    }
    NSString *logLine = [[NSString alloc] initWithData: [NSJSONSerialization dataWithJSONObject: messageArray options: NSJSONWritingPrettyPrinted error: NULL] encoding: NSUTF8StringEncoding];
    logLine = [NSString stringWithFormat: @"[%@]: %@\n", [NSDate date], logLine];
    [self.logFile writeData: [logLine dataUsingEncoding: NSUTF8StringEncoding]];
}

- (void) _openLogFile
{
    if (self.debug && self.logFile == nil) {
        NSString* cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
        NSString* logFile = [cacheDir stringByAppendingPathComponent: self.debugLogFileName];
        if (![[NSFileManager defaultManager] fileExistsAtPath: logFile]) {
            [[NSFileManager defaultManager] createFileAtPath: logFile contents: nil attributes: nil];
        }
        self.logFile = [NSFileHandle fileHandleForWritingAtPath: logFile];
        [self.logFile seekToEndOfFile];
    }
}

- (void) _closeLogFile
{
    if (self.debug && self.logFile != nil) {
        [self.logFile closeFile];
        self.logFile = nil;
    }
}

- (void) _failWithError: (NSError*) error
{
    [self disconnectNow];
    self.connectionStatus = FayeClientConnectionStatusDisconnected;
}

@end