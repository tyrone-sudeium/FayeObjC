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
//  FayeClient.h
//  FayeObjC
//
#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif

#import "SRWebSocket.h"
#import "FayeChannel.h"

enum _fayeStates {
  kWebSocketDisconnected,
  kWebSocketConnected,
  kFayeDisconnected,
  kFayeConnected  
} fayeStates;

#ifdef FAYEOBJC_DEBUGGING
#   define FAYE_DLog(fmt, ...) {NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);}
#else
#   define FAYE_DLog(...) {}
#endif

#define kFayeErrorDomain @"FayeErrorDomain"

// Bayeux protocol channels
#define HANDSHAKE_CHANNEL @"/meta/handshake"
#define CONNECT_CHANNEL @"/meta/connect"
#define DISCONNECT_CHANNEL @"/meta/disconnect"
#define SUBSCRIBE_CHANNEL @"/meta/subscribe"
#define UNSUBSCRIBE_CHANNEL @"/meta/unsubscribe"

@class FayeClient;

@protocol FayeClientDelegate <NSObject>

- (void) fayeClient: (FayeClient*) client didReceiveMessage:(NSDictionary *)messageDict forChannel: (FayeChannel*) channel;
- (void) fayeClientDidConnectToServer: (FayeClient*) client;
- (void) fayeClientDidDisconnectFromServer: (FayeClient*) client;
- (void) fayeClient: (FayeClient*) client didFailToConnectToServerWithError: (NSError*) error;
- (void) fayeClient: (FayeClient*) client didFailSubscriptionWithError: (NSError*) error;

@end


@interface FayeClient : NSObject <SRWebSocketDelegate> {
    NSString *fayeURLString;
    SRWebSocket* webSocket;
    NSString *fayeClientId;
    BOOL webSocketConnected;  
    NSString *activeSubChannel;
@private
    BOOL fayeConnected;  
    NSDictionary *connectionExtension;
}

@property (nonatomic, retain) NSString *fayeURLString;
@property (nonatomic, retain) SRWebSocket* webSocket;
@property (nonatomic, retain) NSString *fayeClientId;
@property (nonatomic, assign) BOOL webSocketConnected;
@property (nonatomic, unsafe_unretained) id <FayeClientDelegate> delegate;
@property (nonatomic, readonly) NSArray *subscribedChannels;

- (id) initWithURLString:(NSString *)aFayeURLString;
- (FayeChannel*) subscribeToChannel: (NSString*) channelPath messageHandler: (FayeChannelMessageHandlerBlock) handler;
- (void) unsubscribeFromChannel: (NSString*) channelPath;
- (void) connectToServer;
- (void) connectToServerWithExt:(NSDictionary *)extension;
- (void) disconnectFromServer;
- (void) sendMessage:(NSDictionary *)messageDict toChannel: (FayeChannel*) channel;
- (void) sendMessage:(NSDictionary *)messageDict withExt:(NSDictionary *)extension toChannel: (FayeChannel*) channel;

@end
