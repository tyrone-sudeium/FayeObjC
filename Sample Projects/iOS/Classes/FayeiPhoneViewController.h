//
//  fayeiPhoneViewController.h
//  fayeiPhone
//
//  Created by Paul Crawford on 11-03-04.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FayeClient.h"

@interface FayeiPhoneViewController : UIViewController <FayeClientDelegate, UITextFieldDelegate> {
    FayeClient *faye;
    BOOL connected;
    UITextField *messageTextField;
    UIToolbar *editToolbar;
    UITextView *messageView;
}

@property (retain) FayeClient *faye;
@property (assign) BOOL connected;
@property (nonatomic, retain) IBOutlet UITextField *messageTextField;
@property (nonatomic, retain) IBOutlet UIToolbar *editToolbar;
@property (nonatomic, retain) IBOutlet UITextView *messageView;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *connectDisconnectButton;

- (IBAction) sendMessage;
- (IBAction) hideKeyboard;
- (IBAction)channelsButtonAction:(id)sender;
- (IBAction)connectDisconnectButtonAction:(id)sender;

@end

