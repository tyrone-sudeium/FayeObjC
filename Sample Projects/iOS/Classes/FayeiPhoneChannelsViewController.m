//
//  FayeiPhoneChannelsViewController.m
//  FayeiPhone
//
//  Created by Tyrone Trevorrow on 17-02-13.
//
//

#import "FayeiPhoneChannelsViewController.h"

@interface FayeiPhoneChannelsViewController () <UIAlertViewDelegate>
@property (nonatomic, strong) NSArray *channels;
@end

@implementation FayeiPhoneChannelsViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Channels";

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target: self action: @selector(addButtonAction:)];
    self.navigationItem.rightBarButtonItem = item;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear: animated];
    [self.navigationController setNavigationBarHidden: NO animated: animated];
    [self reloadData];
}

- (void) reloadData
{
    self.channels = [self.faye.subscribedChannels.allObjects sortedArrayUsingSelector: @selector(compare:)];
    [self.tableView reloadData];
}

- (void) addButtonAction: (id) sender
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle: @"Subscribe Channel" message: @"Enter channel path" delegate: self cancelButtonTitle: @"Cancel" otherButtonTitles: @"Done", nil];
    [alertView setAlertViewStyle: UIAlertViewStylePlainTextInput];
    [alertView show];
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 1) {
        NSString *channelPath = [[alertView textFieldAtIndex: 0] text];
        if (channelPath.length > 1 && [channelPath hasPrefix: @"/"]) {
            [self.faye subscribeToChannel: channelPath messageHandler: NULL completionHandler:^{
                [self reloadData];
            }];
        }
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    return self.channels.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }

    cell.textLabel.text = self.channels[indexPath.row];
    return cell;
}


// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    if ([self.channels[indexPath.row] isEqualToString: @"/testing"]) {
        return NO;
    } else {
        return YES;
    }
}



// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [self.faye unsubscribeFromChannel: self.channels[indexPath.row] completionHandler:^{
            self.channels = [self.faye.subscribedChannels.allObjects sortedArrayUsingSelector: @selector(compare:)];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }];
    }
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath: indexPath animated: indexPath];
}

@end
