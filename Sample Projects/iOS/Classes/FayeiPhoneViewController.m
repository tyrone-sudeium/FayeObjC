//
//  fayeiPhoneViewController.m
//  fayeiPhone
//
//  Created by Paul Crawford on 11-03-04.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "FayeiPhoneViewController.h"

@implementation FayeiPhoneViewController

@synthesize faye;
@synthesize connected;
@synthesize messageTextField;
@synthesize editToolbar;
@synthesize messageView;

/*
// The designated initializer. Override to perform setup that is required before the view is loaded.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}
*/

/*
// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView {
}
*/



// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
    
    self.connected = NO;
    self.faye = [FayeClient fayeClientWithURL: [NSURL URLWithString: @"http://localhost:8000/faye"]];
    self.faye.delegate = self;
    self.faye.debug = YES;
    [self.faye subscribeToChannel: @"/testing"];
    [self.faye connect];
}

- (void) keyboardWillShow:(NSNotification *)notification {
    CGRect rect = editToolbar.frame, keyboardFrame;
    [[notification.userInfo valueForKey:UIKeyboardBoundsUserInfoKey] getValue:&keyboardFrame];
    rect.origin.y -= keyboardFrame.size.height;
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.3];
    editToolbar.frame = rect;
    messageView.frame = CGRectMake(0, 0, 320, messageView.frame.size.height-keyboardFrame.size.height);
    [UIView commitAnimations];
}

- (void) keyboardWillHide:(NSNotification *)notification {
    CGRect rect = editToolbar.frame, keyboardFrame;
    [[notification.userInfo valueForKey:UIKeyboardBoundsUserInfoKey] getValue:&keyboardFrame];
    rect.origin.y += keyboardFrame.size.height;
    
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:0.3];
    editToolbar.frame = rect;
    messageView.frame = CGRectMake(0, 0, 320, messageView.frame.size.height+keyboardFrame.size.height);
    [UIView commitAnimations];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    DLog(@"text field should return");
    [self sendMessage];
    return YES;
}

/*
// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
*/

- (IBAction) sendMessage {
    DLog(@"send message %@", messageTextField.text);
    NSString *message = [NSString stringWithString:messageTextField.text];
    NSDictionary *messageDict = [NSDictionary dictionaryWithObjectsAndKeys:message, @"message", nil];
    [self.faye sendMessage: messageDict toChannel: @"/testing" extension: nil completionHandler:^{
        DLog(@"message came back!");
    }];
    self.messageTextField.text = @"";
}

- (IBAction) hideKeyboard {
    self.messageTextField.text = @"";
    [self.messageTextField resignFirstResponder];
}

#pragma mark -
#pragma mark FayeObjc delegate
- (void) fayeClient:(FayeClient *)client didReceiveMessage:(NSDictionary *)message onChannel:(NSString *)channelPath
{
    DLog(@"message recieved %@", message);
    if([message objectForKey:@"message"]) {
        self.messageView.text = [self.messageView.text stringByAppendingString:[NSString stringWithFormat:@"%@\n", [message objectForKey:@"message"]]];
        //[self.messagesText insertText:[NSString stringWithFormat:@"%@\n", [messageDict objectForKey:@"message"]]];
    }
}

- (void)connectedToServer {
    DLog(@"Connected");
    self.connected = YES;
    //[self.connectIndicator setImage:[NSImage imageNamed:@"green.png"]];
    //[self.connectBtn setTitle:@"Disconnect"];
    //[connectBtn setAction:@selector(disconnectFromServer:)];
}

- (void)disconnectedFromServer {
    DLog(@"Disconnected");
    self.connected = NO;
    //[self.connectIndicator setImage:[NSImage imageNamed:@"red.png"]];
    //[self.connectBtn setTitle:@"Connect"];
    //[connectBtn setAction:@selector(connectToServer:)];
}

#pragma mark -
#pragma mark Memory management
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}

@end
