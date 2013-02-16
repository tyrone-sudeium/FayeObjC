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
//  FayeClient.h
//  FayeObjC
//

#import <Foundation/Foundation.h>

#define kFayeErrorDomain @"FayeErrorDomain"

// Bayeux protocol channels
extern NSString * const FayeClientHandshakeChannel;
extern NSString * const FayeClientConnectChannel;
extern NSString * const FayeClientDisconnectChannel;
extern NSString * const FayeClientSubscribeChannel;
extern NSString * const FayeClientUnsubscribeChannel;

@class FayeClient;
typedef void(^FayeClientChannelMessageHandlerBlock)(FayeClient *client, NSString* channelPath, NSDictionary *messageDict);
typedef void(^FayeClientConnectionStatusHandlerBlock)(FayeClient *client, NSError *error);

@protocol FayeClientDelegate <NSObject>
@optional
- (void) fayeClientConnectionStatusChanged: (FayeClient*) client;
- (void) fayeClient: (FayeClient*) client
    receivedMessage: (NSDictionary*) message
          onChannel: (NSString*) channelPath;
- (void) fayeClient: (FayeClient*) client
subscribedToChannel: (NSString*) channel;
- (void) fayeClient: (FayeClient*) client unsubscribedFromChannel: (NSString*) channel;
- (void) fayeClient: (FayeClient*) client
        sentMessage: (NSDictionary*) message
          toChannel: (NSString*) channel;
@end

typedef NS_ENUM(NSInteger, FayeClientConnectionStatus) {
    FayeClientConnectionStatusDisconnected,
    FayeClientConnectionStatusConnecting,
    FayeClientConnectionStatusConnected,
    FayeClientConnectionStatusDisconnecting
};

@interface FayeClient : NSObject
@property (nonatomic, retain) NSString *clientID;
@property (nonatomic, weak) id <FayeClientDelegate> delegate;
@property (nonatomic, readonly) NSSet *subscribedChannels;
@property (nonatomic, copy) NSDictionary *extension;
@property (nonatomic, copy) NSDictionary *handshakeExtension;
@property (nonatomic, copy) NSDictionary *connectExtension;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, readonly, assign) FayeClientConnectionStatus connectionStatus;
@property (nonatomic, assign) BOOL debug;

+ (instancetype) fayeClientWithURL: (NSURL*) url;

- (void) addServerWithURL: (NSURL*) url;

- (void) connect;
- (void) connectWithConnectionStatusChangedHandler: (FayeClientConnectionStatusHandlerBlock) handler;
- (void) disconnect;

- (void) subscribeToChannel: (NSString*) channel;
- (void) subscribeToChannel: (NSString *) channel
             messageHandler: (FayeClientChannelMessageHandlerBlock) handler;
- (void) subscribeToChannel: (NSString *) channel
             messageHandler: (FayeClientChannelMessageHandlerBlock) messageHandler
          completionHandler: (dispatch_block_t) completionHandler;
- (void) setExtension: (NSDictionary*) extension
           forChannel: (NSString*) channel;

- (void) unsubscribeFromChannel: (NSString*) channel;
- (void) unsubscribeFromChannel: (NSString*) channel
              completionHandler: (dispatch_block_t) handler;

- (void) sendMessage: (NSDictionary*) message
           toChannel: (NSString*) channel;
- (void) sendMessage: (NSDictionary*) message
           toChannel: (NSString*) channel
           extension: (NSDictionary*) extension;
- (void) sendMessage: (NSDictionary*) message
           toChannel: (NSString*) channel
           extension: (NSDictionary*) extension
   completionHandler: (dispatch_block_t) handler;

@end
