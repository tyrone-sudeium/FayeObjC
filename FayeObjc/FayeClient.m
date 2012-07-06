/* The MIT License
 
 Copyright (c) 2011 Paul Crawford
 
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

// allows definition of private property
@interface FayeClient ()
@property (nonatomic, strong) NSMutableDictionary *mySubscribedChannels;
@property (retain) NSDictionary *connectionExtension;

@end

@interface FayeClient (Private)

- (void) openWebSocketConnection;
- (void) closeWebSocketConnection;
- (void) connect;
- (void) disconnect;
- (void) handshake;
- (void) publish:(NSDictionary *)messageDict withExt:(NSDictionary *)extension toChannel: (FayeChannel*) channel;
- (void) parseFayeMessage:(NSString *)message;

@end


@implementation FayeClient
@synthesize mySubscribedChannels;
@synthesize fayeURLString;
@synthesize webSocket;
@synthesize fayeClientId;
@synthesize webSocketConnected;
@synthesize delegate;
@synthesize connectionExtension;

/*
 Example websocket url string
 // ws://localhost:8000/faye
 */
- (id) initWithURLString:(NSString *)aFayeURLString
{
    self = [super init];
    if (self != nil) {
        self.fayeURLString = aFayeURLString;
        self.webSocketConnected = NO;
        self.mySubscribedChannels = [NSMutableDictionary new];
        fayeConnected = NO;
    }
    return self;
}

- (NSArray*) subscribedChannels
{
    return [self.mySubscribedChannels allValues];
}

#pragma mark -
#pragma mark Faye

// fire up a connection to the websocket
// handshake with the server
// establish a faye connection
- (void) connectToServer {
    [self openWebSocketConnection];
}

- (void) connectToServerWithExt:(NSDictionary *)extension {
    self.connectionExtension = extension;  
    [self connectToServer];
}

- (void) disconnectFromServer {  
    [self disconnect];  
}

- (void) sendMessage:(NSDictionary *)messageDict toChannel:(FayeChannel *)channel {
    [self publish:messageDict withExt:nil toChannel: channel];
}

- (void) sendMessage:(NSDictionary *)messageDict withExt:(NSDictionary *)extension toChannel:(FayeChannel *)channel {
    [self publish:messageDict withExt:extension toChannel: channel];
}


// {
// "channel": "/meta/subscribe",
// "clientId": "Un1q31d3nt1f13r",
// "subscription": "/foo/**"
// }

- (FayeChannel*) subscribeToChannel: (NSString*) channelPath messageHandler: (FayeChannelMessageHandlerBlock) handler
{
    FayeChannel *channel = [self.mySubscribedChannels objectForKey: channelPath];
    if (channel != nil) {
        return channel;
    } else {
        channel = [FayeChannel channelWithPath: channelPath];
        channel.messageHandlerBlock = handler;
    }
    [self.mySubscribedChannels setValue: channel forKey: channel.channelPath];
    
    NSDictionary *dict = nil;
    if(nil == self.connectionExtension) {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:SUBSCRIBE_CHANNEL, @"channel", 
                self.fayeClientId, @"clientId", 
                channel.channelPath, @"subscription", nil];
    } else {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:SUBSCRIBE_CHANNEL, @"channel", 
                self.fayeClientId, @"clientId", 
                channel.channelPath, @"subscription", 
                self.connectionExtension, @"ext", nil];
    }
    
    NSData *json = [NSJSONSerialization dataWithJSONObject: dict options: 0 error:NULL];
    [webSocket send:json];
    return channel;
}


// {
// "channel": "/meta/unsubscribe",
// "clientId": "Un1q31d3nt1f13r",
// "subscription": "/foo/**"
// }

- (void) unsubscribeFromChannel:(NSString*)channelPath {
    __strong FayeChannel *channel = [self.mySubscribedChannels objectForKey: channel];
    [self.mySubscribedChannels removeObjectForKey: channelPath];
    
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:UNSUBSCRIBE_CHANNEL, @"channel", 
                          self.fayeClientId, @"clientId", 
                          channel.channelPath, @"subscription", nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject: dict options: 0 error: NULL];
    [webSocket send:json];
}

#pragma -
#pragma mark SRWebSocketDelegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
{
    self.webSocketConnected = YES;  
    [self handshake];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{  
    // TODO: add more explicit error handling based on status codes.
    // NSLog(@"Error %@", [error localizedDescription]);
    self.webSocketConnected = NO;
    fayeConnected = NO;
    [self.mySubscribedChannels removeAllObjects];
    if (self.delegate != NULL && [self.delegate respondsToSelector: @selector(fayeClient:didFailToConnectToServerWithError:)]) {
        [self.delegate fayeClient: self didFailToConnectToServerWithError: error];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(NSString *)message;
{
    [self parseFayeMessage:message];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    self.webSocketConnected = NO;  
    fayeConnected = NO;
    [self.mySubscribedChannels removeAllObjects];
    if(self.delegate != NULL && [self.delegate respondsToSelector:@selector(fayeClientDidDisconnectFromServer:)]) {
        [self.delegate fayeClientDidDisconnectFromServer: self];
    }
}

#pragma mark -
#pragma mark Deallocation
- (void) dealloc
{
    self.delegate = nil;
}

@end

#pragma mark -
#pragma mark Private
@implementation FayeClient (Private)

#pragma mark -
#pragma mark WebSocket connection
- (void) openWebSocketConnection {
    // clean up any existing socket
    [webSocket setDelegate:nil];
    [webSocket close];
    webSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.fayeURLString]]];
    webSocket.delegate = self;
    [webSocket open];
}

- (void) closeWebSocketConnection { 
    [webSocket close];	    
}

#pragma mark -
#pragma mark Private Bayeux procotol functions

/* 
 Bayeux Handshake
 "channel": "/meta/handshake",
 "version": "1.0",
 "minimumVersion": "1.0beta",
 "supportedConnectionTypes": ["long-polling", "callback-polling", "iframe", "websocket]
 */
- (void) handshake {
    NSArray *connTypes = [NSArray arrayWithObjects: /*@"long-polling", @"callback-polling", @"iframe",*/ @"websocket", nil];   
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:HANDSHAKE_CHANNEL, @"channel", @"1.0", @"version", @"1.0beta", @"minimumVersion", connTypes, @"supportedConnectionTypes", nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject: dict options: 0 error: NULL];
    [webSocket send:json];  
}

/*
 Bayeux Connect
 "channel": "/meta/connect",
 "clientId": "Un1q31d3nt1f13r",
 "connectionType": "long-polling"
 */
- (void) connect {
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:CONNECT_CHANNEL, @"channel", self.fayeClientId, @"clientId", @"websocket", @"connectionType", nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject: dict options: 0 error: NULL];
    [webSocket send:json];
}

/*
 {
 "channel": "/meta/disconnect",
 "clientId": "Un1q31d3nt1f13r"
 }
 */
- (void) disconnect {
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:DISCONNECT_CHANNEL, @"channel", self.fayeClientId, @"clientId", nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject: dict options: 0 error: NULL];
    [webSocket send:json];
}

/*
 {
 "channel": "/some/channel",
 "clientId": "Un1q31d3nt1f13r",
 "data": "some application string or JSON encoded object",
 "id": "some unique message id"
 }
 */
- (void) publish:(NSDictionary *)messageDict withExt:(NSDictionary *)extension toChannel:(FayeChannel *)channel {
    NSString *messageId = [NSString stringWithFormat:@"msg_%d_%d", (NSInteger)[[NSDate date] timeIntervalSince1970], 1];
    NSDictionary *dict = nil;
    
    if(nil == extension) {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:channel.channelPath, @"channel", self.fayeClientId, @"clientId", messageDict, @"data", messageId, @"id", nil];
    } else {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:channel.channelPath, @"channel", self.fayeClientId, @"clientId", messageDict, @"data", messageId, @"id", extension, @"ext",nil];
    }
    
    NSData *json = [NSJSONSerialization dataWithJSONObject: dict options: 0 error: NULL];
    [webSocket send:json];
}

#pragma mark -
#pragma mark Faye message handling
- (void) parseFayeMessage:(NSString *)message {
    // interpret the message(s)
    NSArray *messageArray = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding] options: 0 error: NULL];
    for(NSDictionary *messageDict in messageArray) {
        FayeMessage *fm = [[FayeMessage alloc] initWithDict:messageDict];
        
        if ([fm.channel isEqualToString:HANDSHAKE_CHANNEL]) {    
            if ([fm.successful boolValue]) {
                self.fayeClientId = fm.clientId;        
                if(self.delegate != NULL && [self.delegate respondsToSelector:@selector(fayeClientDidConnectToServer:)]) {
                    [self.delegate fayeClientDidConnectToServer: self];
                }
                [self connect];
            } else {
                NSLog(@"ERROR WITH HANDSHAKE");
            }    
        } else if ([fm.channel isEqualToString:CONNECT_CHANNEL]) {      
            if ([fm.successful boolValue]) {        
                fayeConnected = YES;
                [self connect];
            } else {
                NSLog(@"ERROR CONNECTING TO FAYE");
            }
        } else if ([fm.channel isEqualToString:DISCONNECT_CHANNEL]) {
            if ([fm.successful boolValue]) {        
                fayeConnected = NO;  
                [self closeWebSocketConnection];
//                if(self.delegate != NULL && [self.delegate respondsToSelector:@selector(fayeClientDidDisconnectFromServer:)]) {
//                    [self.delegate fayeClientDidDisconnectFromServer: self];
//                }
            } else {
                NSLog(@"ERROR DISCONNECTING TO FAYE");
            }
        } else if ([fm.channel isEqualToString:SUBSCRIBE_CHANNEL]) {      
            if ([fm.successful boolValue]) {
                NSLog(@"SUBSCRIBED TO CHANNEL %@ ON FAYE", fm.subscription);        
            } else {
                NSLog(@"ERROR SUBSCRIBING TO %@ WITH ERROR %@", fm.subscription, fm.error);
                if(self.delegate != NULL && [self.delegate respondsToSelector:@selector(fayeClient:didFailSubscriptionWithError:)]) {
                    NSError *error = [NSError errorWithDomain: kFayeErrorDomain code: 1337 userInfo: [NSDictionary dictionaryWithObject: fm.error forKey: NSLocalizedDescriptionKey]];
                    [self.delegate fayeClient: self didFailSubscriptionWithError: error];
                }        
            }      
        } else if ([fm.channel isEqualToString:UNSUBSCRIBE_CHANNEL]) {
            NSLog(@"UNSUBSCRIBED FROM CHANNEL %@ ON FAYE", fm.subscription);
        } else if ([self.mySubscribedChannels objectForKey: fm.channel] != nil) {
            FayeChannel *channel = [self.mySubscribedChannels objectForKey: fm.channel];
            if(fm.data) {        
                if(self.delegate != NULL && [self.delegate respondsToSelector:@selector(fayeClient:didReceiveMessage:forChannel:)]) {          
                    [self.delegate fayeClient: self didReceiveMessage: fm.data forChannel: channel];
                }
            }
            if (channel.messageHandlerBlock != NULL) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                     channel.messageHandlerBlock(fm.data);
                });
            }
        } else {
            NSLog(@"NO MATCH FOR CHANNEL %@", fm.channel);      
        }    
    }  
}

@end