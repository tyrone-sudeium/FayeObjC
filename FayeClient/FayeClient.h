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
#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif

#ifdef FAYEOBJC_DEBUGGING
#   define FAYE_DLog(fmt, ...) {NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);}
#else
#   define FAYE_DLog(...) {}
#endif

#define kFayeErrorDomain @"FayeErrorDomain"

// Bayeux protocol channels
extern NSString * const FayeClientHandshakeChannel;
extern NSString * const FayeClientConnectChannel;
extern NSString * const FayeClientDisconnectChannel;
extern NSString * const FayeClientSubscribeChannel;
extern NSString * const FayeClientUnsubscribeChannel;

@class FayeClient;
typedef void(^FayeClientChannelMessageHandlerBlock)(FayeClient *client, NSString* channelPath, NSDictionary *messageDict);
typedef void(^FayeClientConnectionStatusHandlerBlock)(FayeClient *client);

@protocol FayeClientDelegate <NSObject>

- (void) fayeClient: (FayeClient*) client didReceiveMessage:(NSDictionary *)messageDict forChannel: (NSString*) channel;
- (void) fayeClientDidConnectToServer: (FayeClient*) client;
- (void) fayeClientDidDisconnectFromServer: (FayeClient*) client;
- (void) fayeClient: (FayeClient*) client didFailToConnectToServerWithError: (NSError*) error;
- (void) fayeClient: (FayeClient*) client didFailSubscriptionWithError: (NSError*) error;

@end


@interface FayeClient : NSObject
@property (nonatomic, retain) NSString *clientID;
@property (nonatomic, weak) id <FayeClientDelegate> delegate;
@property (nonatomic, readonly) NSArray *subscribedChannels;
@property (nonatomic, assign) BOOL debug;

- (void) addServerWithURL: (NSURL*) url;

//- (void) subscribeToChannel: (NSString*) channelPath messageHandler: (FayeChannelMessageHandlerBlock) handler;
//- (void) unsubscribeFromChannel: (NSString*) channelPath;
//- (void) connectToServer;
//- (void) connectToServerWithExt:(NSDictionary *)extension;
//- (void) disconnectFromServer;
//- (void) sendMessage:(NSDictionary *)messageDict toChannel: (FayeChannel*) channel;
//- (void) sendMessage:(NSDictionary *)messageDict withExt:(NSDictionary *)extension toChannel: (FayeChannel*) channel;

@end
