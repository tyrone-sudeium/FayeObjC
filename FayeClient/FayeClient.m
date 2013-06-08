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

@interface FayeMessageQueueItem : NSObject
@property (nonatomic, copy) FayeMessageQueueItemGetMessageBlock block;
@property (nonatomic, copy) dispatch_block_t sentMessageHandler;
@end

@implementation FayeMessageQueueItem
+ (instancetype) itemWithBlock: (FayeMessageQueueItemGetMessageBlock) block
{
    FayeMessageQueueItem *item = [FayeMessageQueueItem new];
    item.block = block;
    return item;
}
- (NSString*) description
{
    NSString *desc = @"invalid message";
    if (self.block) {
        desc = @"custom message";
        NSDictionary *d = self.block();
        if ([d[@"channel"] isEqualToString: FayeClientConnectChannel]) {
            desc = @"connect";
        } else if ([d[@"channel"] isEqualToString: FayeClientHandshakeChannel]) {
            desc = @"handshake";
        } else if ([d[@"channel"] isEqualToString: FayeClientDisconnectChannel]) {
            desc = @"disconnect";
        } else if ([d[@"channel"] isEqualToString: FayeClientSubscribeChannel]) {
            desc = [NSString stringWithFormat: @"subscribe %@", d[@"subscription"]];
        } else if ([d[@"channel"] isEqualToString: FayeClientUnsubscribeChannel]) {
            desc = [NSString stringWithFormat: @"unsubscribe %@", d[@"subscription"]];
        }
    }
    return [NSString stringWithFormat: @"<%@: %p> (%@)", self.class, self, desc];
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
@property (strong) NSMutableArray *queuedMessages;
@property (strong) NSMutableArray *alternateQueue;
@property (nonatomic, strong) NSURLConnection *httpConnection;
@property (nonatomic, strong) NSMutableData *httpData;
@property (nonatomic, strong) NSMutableDictionary *sentMessageHandlers;
@property (nonatomic, assign) dispatch_queue_t readQueue;
@property (nonatomic, assign) dispatch_queue_t writeQueue;

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
    
    struct {
        BOOL willSend:1;
        BOOL willReceive:1;
    } _dataDelegateRespondsTo;
    
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
        self.sentMessageHandlers = [NSMutableDictionary dictionary];
        self.timeout = 10;
        self.handshakeExtension = @{};
        self.connectExtension = @{};
        self.extension = @{};
        self.httpData = [NSMutableData data];
        self.debugLogFileName = @"faye.log";
        _nextSortIndex = 0;
        self.readQueue = dispatch_queue_create("com.sudeium.fayeclient-readqueue", DISPATCH_QUEUE_SERIAL);
        self.writeQueue = dispatch_queue_create("com.sudeium.fayeclient-writequeue", DISPATCH_QUEUE_SERIAL);
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
    [self _debugMessage: @"Registered server: %@", url.absoluteString];
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

- (void) setDataDelegate:(id<FayeClientDataDelegate>)dataDelegate
{
    if (_dataDelegate != dataDelegate) {
        [self willChangeValueForKey: @"dataDelegate"];
        _dataDelegateRespondsTo.willSend = [dataDelegate respondsToSelector: @selector(fayeClient:willSendMessage:)];
        _dataDelegateRespondsTo.willReceive = [dataDelegate respondsToSelector: @selector(fayeClient:willReceiveMessage:)];
        [self didChangeValueForKey: @"dataDelegate"];
    }
}

- (NSString*) clientID
{
    return self.currentServer.clientID;
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
                dispatch_async(dispatch_get_main_queue(), completionHandler);
            }
            [self _debugMessage: @"Channel: %@ subscribed.", channel];
        }
    };
    if ([self subscriptionStatusForChannel:channel] == FayeChannelSubscriptionStatusUnsubscribed) {
        [self queueChannelSubscription: channel];
        [self _debugMessage: @"Channel: %@ queued for subscription.", channel];
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
    fayeChannel.statusHandlerBlock = ^(FayeClient *client, NSString* channelPath, FayeChannelSubscriptionStatus status) {
        if (status == FayeChannelSubscriptionStatusUnsubscribed) {
            [self.subscriptions removeObjectForKey: channelPath];
            if (handler != NULL) {
                dispatch_async(dispatch_get_main_queue(), handler);
            }
        }
        [self _debugMessage: @"Channel: %@ unsubscribed.", channel];
    };
    if ([self subscriptionStatusForChannel:channel] == FayeChannelSubscriptionStatusSubscribed) {
        [self queueChannelUnsubscription: channel];
        [self _debugMessage: @"Channel: %@ queued for unsubscription.", channel];
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

- (NSSet*) subscribedChannels
{
    NSMutableSet *channels = [NSMutableSet new];
    for (FayeChannel *channel in self.subscriptions.allValues) {
        [channels addObject: channel.channelPath];
    }
    return channels.copy;
}

#pragma mark - Publishing Messages

- (void) sendMessage:(NSDictionary *)message toChannel:(NSString *)channel
{
    [self sendMessage: message toChannel: channel extension: nil completionHandler: NULL];
}

- (void) sendMessage:(NSDictionary *)message
           toChannel:(NSString *)channel
           extension:(NSDictionary *)extension
{
    [self sendMessage: message toChannel: channel extension: extension completionHandler: NULL];
}

- (void) sendMessage:(NSDictionary *)message
           toChannel:(NSString *)channel
           extension:(NSDictionary *)extension
   completionHandler:(dispatch_block_t)handler
{
    if (message == nil) {
        [self _debugMessage: @"Ignoring send message: no data."];
        return;
    }
    FayeMessageQueueItem *queueItem = [FayeMessageQueueItem itemWithBlock:^NSDictionary *{
        return [self publishMessageForChannelPath: channel withData: message extension:extension];
    }];
    
    if (self.subscriptions[channel] != nil) {
        // We only support sent message callbacks if you're subscribed to the channel you're sending to.
        queueItem.sentMessageHandler = handler;
    }
    [self queueMessage: queueItem];
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
    if (self.connectionStatus != FayeClientConnectionStatusDisconnected) {
        [self _debugMessage: @"Ignoring connect message: already connecting."];
    }
    self.connectionStatusHandler = handler;
    self.currentServer = [[self sortedServers] objectAtIndex: 0];
    [self.queuedMessages removeAllObjects];
    self.connectionStatus = FayeClientConnectionStatusConnecting;
    if ([self.currentServer connectsWithLongPolling]) {
        [self connectWithLongPolling];
    } else {
        [self connectWithWebSocket];
    }
    [self _debugMessage: @"Connecting to server: %@", self.currentServer.url.absoluteString];
}

- (void) disconnect
{
    if ([self.currentServer connectsWithLongPolling]) {
        self.connectionStatus = FayeClientConnectionStatusDisconnecting;
        [self queueMessage: [FayeMessageQueueItem itemWithBlock:^NSDictionary *{
            return [self disconnectMessage];
        }]];
    } else {
        if (self.connectionStatus == FayeClientConnectionStatusConnecting) {
            // Just close the connection.
            [self disconnectNow];
        } else if (self.connectionStatus == FayeClientConnectionStatusConnected) {
            // We need to send a disconnect message.
            self.connectionStatus = FayeClientConnectionStatusDisconnecting;
            dispatch_async(self.writeQueue, ^{
                self.alternateQueue = self.queuedMessages.mutableCopy;
                [self.queuedMessages removeAllObjects];
                [self.queuedMessages addObject: [FayeMessageQueueItem itemWithBlock:^NSDictionary *{
                    return [self disconnectMessage];
                }]];
                NSData *data = [self dataForNextUpload];
                if (data) {
                    [self.webSocket send: data];
                }
            });
        }
    }
}

#pragma mark - WebSockets

- (void) connectWithWebSocket
{
    NSURLRequest *request = [NSURLRequest requestWithURL: self.currentServer.url
                                             cachePolicy: NSURLCacheStorageNotAllowed
                                         timeoutInterval: self.timeout];
    self.webSocket = [[SRWebSocket alloc] initWithURLRequest: request];
    self.webSocket.delegate = self;
    [self.webSocket open];
}

- (void) webSocketDidOpen:(SRWebSocket *)webSocket
{
    [self _debugMessage: @"WebSocket: Opened.  Sending handshake."];
    dispatch_async(self.writeQueue, ^{
        self.alternateQueue = self.queuedMessages.mutableCopy;
        [self.queuedMessages removeAllObjects];
        [self.queuedMessages addObject: [FayeMessageQueueItem itemWithBlock:^NSDictionary *{
            return [self handshakeMessage];
        }]];
        NSData *data = [self dataForNextUploadWithConnectMessage: NO];
        [self.queuedMessages removeAllObjects];
        if (data) {
            [self.webSocket send: data];
        }
    });
}

- (void) webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    [self _debugMessage: @"WebSocket: Connection failure."];
    self.currentServer.failures += 1;
    if (self.connectionStatus != FayeClientConnectionStatusDisconnecting) {
        [self cycleConnection];
    }
}

- (void) webSocket:(SRWebSocket *)webSocket
  didCloseWithCode:(NSInteger)code
            reason:(NSString *)reason
          wasClean:(BOOL)wasClean
{
    [self _debugMessage: @"WebSocket: Closed."];
    if (self.connectionStatus == FayeClientConnectionStatusDisconnecting) {
        self.connectionStatus = FayeClientConnectionStatusDisconnected;
        self.connectionStatusHandler = nil;
    }
}

- (void) webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    if ([message isKindOfClass: [NSString class]]) {
        dispatch_async(self.readQueue, ^{
            [self handleReceivedData: [(NSString*) message dataUsingEncoding: NSUTF8StringEncoding]];
        });
    }
}

- (void) sendCurrentMessageQueueToWebSocket
{
    dispatch_async(self.writeQueue, ^{
        NSData *data = [self dataForNextUpload];
        if (data) {
            [self.webSocket send: data];
        }
        [self.queuedMessages removeAllObjects];
    });
}

#pragma mark - HTTP Long Polling

- (void) connectWithLongPolling
{
    [self startHTTPConnection];
}

- (void) startHTTPConnection
{
    dispatch_async(self.writeQueue, ^{
        NSData *data = nil;
        if (self.currentServer.clientID) {
            data = [self dataForNextUpload];
            if (data == nil) {
                return;
            }
            [self.queuedMessages removeAllObjects];
        } else {
            NSError *error = nil;
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
        dispatch_async(dispatch_get_main_queue(), ^{
            self.httpConnection = [NSURLConnection connectionWithRequest: request delegate: self];
            [self.httpConnection start];
        });
    });
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
    NSData *data = [self.httpData copy]; // Probably not the most efficient way, but I can't think of a better way...
    dispatch_async(self.readQueue, ^{
        [self handleReceivedData: data];
    });
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
    if (self.currentServer.clientID) {
        [self startHTTPConnection];
    }
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
     @{ @"channel": FayeClientUnsubscribeChannel,
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

- (NSDictionary*) publishMessageForChannelPath: (NSString*) channelPath withData: (NSDictionary*) data extension: (NSDictionary*) extension
{
    NSMutableDictionary *publishMessage = [NSMutableDictionary new];
    [publishMessage addEntriesFromDictionary: @{
     @"channel": channelPath,
     @"data": data,
     @"clientId": self.currentServer.clientID,
     @"id": [self nextMessageID]
     }];
    FayeChannel *fayeChannel = self.subscriptions[channelPath];
    if (extension == nil) {
        extension = @{};
    }
    NSDictionary *ext = [self mergeExtensionDictionaries: @[self.extension, fayeChannel.extension, extension]];
    if ([ext count] > 0) {
        publishMessage[@"ext"] = ext;
    }
    return publishMessage.copy;
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

- (NSData*) dataForNextUpload
{
    if (self.currentServer.connectsWithLongPolling) {
        return [self dataForNextUploadWithConnectMessage: YES];
    } else {
        return [self dataForNextUploadWithConnectMessage: NO];
    }
}

- (NSData*) dataForNextUploadWithConnectMessage: (BOOL) connectMessage
{
    NSMutableArray *proposedMessages = [NSMutableArray new];
    if (connectMessage) {
        [proposedMessages addObject: [self connectMessage]];
    }
    NSArray *queueMessages = [self messagesFromCurrentQueue];
    [proposedMessages addObjectsFromArray: queueMessages];
    NSMutableArray *actualMessages = [NSMutableArray new];
    NSInteger index = 0;
    for (NSDictionary *message in queueMessages) {
        if (message[@"data"] != nil) {
            // It's a publish
            FayeMessageQueueItem *item = [self.queuedMessages objectAtIndex: index];
            if (item.sentMessageHandler != NULL) {
                self.sentMessageHandlers[message[@"id"]] = item.sentMessageHandler;
            }
        }
        index++;
    }
    if (_dataDelegateRespondsTo.willSend) {
        for (NSDictionary *message in proposedMessages) {
            NSDictionary *override = [self.dataDelegate fayeClient: self willSendMessage: message];
            // At this time, I'm going to allow returning nil to mean "don't send the message".
            if (override != nil) {
                [actualMessages addObject: override];
            }
        }
    } else {
        [actualMessages addObjectsFromArray: proposedMessages];
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject: actualMessages options: 0 error: &error];
    if (error) {
        [self _failWithError: error];
        return nil;
    }
    return data;
}

#pragma mark - Internals

- (void) queueMessage: (FayeMessageQueueItem*) queueItem
{
    [self queueMessage: queueItem atIndex: self.queuedMessages.count];
}

- (void) queueMessage: (FayeMessageQueueItem*) queueItem atIndex: (NSUInteger) index
{
    if (self.alternateQueue != nil) {
        [self.alternateQueue insertObject: queueItem atIndex: index];
    } else {
        [self.queuedMessages insertObject: queueItem atIndex: index];
    }
    if ([self.currentServer connectsWithWebSockets]) {
        if (self.connectionStatus == FayeClientConnectionStatusConnected) {
            [self sendMessagesAndEmptyQueueDelayed];
        } else {
            [self _debugMessage: @"WebSocket: Not sending messages because the WebSocket isn't ready!"];
        }
    } else {
        [self sendMessagesAndEmptyQueueDelayed];
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

- (void) queueConnectMessage
{
    // Connect messages should probably always go first.
    if ([self.currentServer connectsWithLongPolling]) {
        [self queueMessage: [FayeMessageQueueItem itemWithBlock:^NSDictionary *{
            return [self connectMessage];
        }] atIndex: 0];
    } else {
        // Send them up immediately for WebSockets.  Faye's got this weird behaviour
        // where if you send up other messages with the connect payload, it won't
        // respond at all until the connect interval.  Probably technically a bug in
        // the Faye server, but this workaround works well enough.
        dispatch_async(self.writeQueue, ^{
            self.alternateQueue = self.queuedMessages.mutableCopy;
            [self.queuedMessages removeAllObjects];
            NSData *data = [self dataForNextUploadWithConnectMessage: YES];
            self.queuedMessages = self.alternateQueue;
            self.alternateQueue = nil;
            [self _debugMessage: @"Sending connect message: %@", [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding]];
            if (data) {
                [self.webSocket send: data];
            }
        });
    }
}

- (void) sendMessagesAndEmptyQueueDelayed
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // The only thread I know *for sure* that supports the runloop mode that this requires is main
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(sendMessagesAndEmptyQueue) object: nil];
        [self performSelector: @selector(sendMessagesAndEmptyQueue) withObject: nil afterDelay: 0.2];
    });
}

- (void) sendMessagesAndEmptyQueue
{
    if (self.queuedMessages.count > 0 && self.currentServer.clientID) {
        [self _debugMessage: @"Sending queue: %@", self.queuedMessages];
        if ([self.currentServer connectsWithLongPolling]) {
            [self startHTTPConnection];
        } else {
            [self sendCurrentMessageQueueToWebSocket];
        }
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
    
    // Any received data means it didn't time out.
    [self resetTimeoutTimer];
    
    for (NSDictionary *proposedMessageJSON in messages) {
        NSDictionary *messageJSON = proposedMessageJSON;
        if (_dataDelegateRespondsTo.willReceive) {
            messageJSON = [self.dataDelegate fayeClient: self willReceiveMessage: proposedMessageJSON];
        }
        // At this time, I'm going to allow returning nil to mean "ignore the message completely".
        if (messageJSON == nil) {
            continue;
        }
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
    if ([self.currentServer connectsWithWebSockets]) {
        [self _debugMessage: @"WebSocket: Connect interval."];
        [self queueConnectMessage];
    }
}

- (void) handleDisconnectMessage: (FayeMessage*) message
{
    for (NSString *channelPath in self.subscriptions) {
        [self setSubscriptionStatus: FayeChannelSubscriptionStatusUnsubscribed forChannel: channelPath];
    }
    if (self.connectionStatus == FayeClientConnectionStatusDisconnecting) {
        [self disconnectNow];
        [self _closeLogFile];
        [self.queuedMessages removeAllObjects];
        if (self.currentServer.connectsWithLongPolling) {
            self.connectionStatus = FayeClientConnectionStatusDisconnected;
            self.connectionStatusHandler = nil;
        } else {
            // We need to wait for the socket to close
        }
    }
}

- (void) handleHandshakeMessage: (FayeMessage*) message
{
    self.currentServer.clientID = message.clientId;
    [self _debugMessage: @"Handshake complete.  New client ID: '%@'", message.clientId];
    
    if ([self.currentServer connectsWithWebSockets]) {
        if (self.alternateQueue) {
            [self.queuedMessages addObjectsFromArray: self.alternateQueue];
            self.alternateQueue = nil;
        }
        [self queueConnectMessage];
    }
    
    if (self.connectionStatus == FayeClientConnectionStatusConnecting) {
        self.connectionStatus = FayeClientConnectionStatusConnected;
    }
    
    for (NSString *channelPath in self.subscriptions) {
        FayeChannelSubscriptionStatus channelStatus = [self subscriptionStatusForChannel: channelPath];
        if (channelStatus != FayeChannelSubscriptionStatusSubscribing &&
            channelStatus != FayeChannelSubscriptionStatusUnsubscribing)
        {
            [self queueChannelSubscription: channelPath];
        }
    }
}

- (void) handleSubscribeMessage: (FayeMessage*) message
{
    FayeChannel *channel = self.subscriptions[message.subscription];
    NSAssert(channel != nil, @"Received subscribe message for channel: '%@' but I don't remember subscribing to it.", message.subscription);
    NSAssert([self subscriptionStatusForChannel: channel.channelPath] == FayeChannelSubscriptionStatusSubscribing, @"Received subscribe message for channel: '%@' but its subscription status is in the wrong state.", message.subscription);
    [self setSubscriptionStatus: FayeChannelSubscriptionStatusSubscribed forChannel: channel.channelPath];
    [self _debugMessage: @"Subscribed to: '%@'", channel.channelPath];
}

- (void) handleUnsubscribeMessage: (FayeMessage*) message
{
    FayeChannel *channel = self.subscriptions[message.subscription];
    NSAssert(channel != nil, @"Received unsubscribe message for channel: '%@' but I don't remember subscribing to it.", message.subscription);
    NSAssert([self subscriptionStatusForChannel: channel.channelPath] == FayeChannelSubscriptionStatusUnsubscribing, @"Received unsubscribe message for channel: '%@' but its subscription status is in the wrong state.", message.subscription);
    [self setSubscriptionStatus: FayeChannelSubscriptionStatusUnsubscribed forChannel: channel.channelPath];
    [self _debugMessage: @"Unsubscribed from: '%@'", channel.channelPath];
}

- (void) handleOtherMessage: (FayeMessage*) message
{
    dispatch_block_t sentHandler = self.sentMessageHandlers[message.fayeId];
    if (sentHandler) {
        dispatch_async(dispatch_get_main_queue(), sentHandler);
        [self.sentMessageHandlers removeObjectForKey: message.fayeId];
    }
    
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
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate fayeClient: self didReceiveMessage: message.data onChannel: message.channel];
                });
            }
        }
        if (channel.messageHandlerBlock != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
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
    [self resetTimeoutTimer];
    self.connectionStatus = FayeClientConnectionStatusConnecting;
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
    if (self.alternateQueue) {
        [self.queuedMessages addObjectsFromArray: self.alternateQueue];
        self.alternateQueue = nil;
    }
    if (self.httpConnection) {
        [self.httpConnection cancel];
        self.httpConnection = nil;
    }
    if (self.webSocket) {
        [self.webSocket close];
    }
    [self _closeLogFile];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(failWithTimeout) object: nil];
    });
}

- (NSArray*) sortedServers
{
    return [self.servers.allValues sortedArrayUsingSelector: @selector(compareServer:)];
}

- (void) failWithTimeout
{
    [self _debugMessage: @"Server timed out.  Retrying..."];
    [self cycleConnection];
}

- (void) resetTimeoutTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(failWithTimeout) object: nil];
        [self performSelector: @selector(failWithTimeout) withObject: nil afterDelay: self.currentServer.timeoutAdvice + 10.0];
    });
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
    [self _debugMessage: @"%@", error];
    [self disconnectNow];
    self.connectionStatus = FayeClientConnectionStatusDisconnected;
}

- (void) dealloc
{
    dispatch_release(self.readQueue);
    dispatch_release(self.writeQueue);
    self.readQueue = nil;
    self.writeQueue = nil;
}

@end
