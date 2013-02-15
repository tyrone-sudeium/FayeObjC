//
//  fayeiPhoneAppDelegate.h
//  fayeiPhone
//
//  Created by Paul Crawford on 11-03-04.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FayeiPhoneViewController;

@interface FayeiPhoneAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *window;
    FayeiPhoneViewController *viewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet FayeiPhoneViewController *viewController;

@end

