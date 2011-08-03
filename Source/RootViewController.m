//
//  RootViewController.m
//  Couchbase Mobile
//
//  Created by Jan Lehnardt on 27/11/2010.
//  Copyright 2011 Couchbase, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.
//

#import "RootViewController.h"
#import "DemoAppDelegate.h"
#import <CouchCocoa/CouchCocoa.h>
#import <Couchbase/CouchbaseEmbeddedServer.h>


@interface RootViewController ()
@property(nonatomic, retain)NSMutableArray *items;
@property(nonatomic, retain)UIBarButtonItem *activityButtonItem;
@property(nonatomic, retain)UIActivityIndicatorView *activity;
@property(nonatomic, retain)CouchDatabase *database;
@property(nonatomic, retain)CouchLiveQuery *query;
-(void)loadItemsIntoView;
-(void)setupSync;
@end


@implementation RootViewController


@synthesize items;
@synthesize activityButtonItem;
@synthesize activity;
@synthesize database;
@synthesize query;
@synthesize tableView;


#pragma mark -
#pragma mark View lifecycle


-(void)useDatabase:(CouchDatabase*)theDatabase {
    self.database = theDatabase;
    self.query = [[database getAllDocuments] asLiveQuery];
    query.descending = YES;  // Sort by descending ID, which will imply descending create time

    // Detect when the query results change:
    [query addObserver: self forKeyPath: @"rows" options: 0 context: NULL];

    [self loadItemsIntoView];
    [self setupSync];
    self.navigationItem.leftBarButtonItem.enabled = YES;
}


- (void)viewDidLoad {
    [super viewDidLoad];

    self.activity = [[[UIActivityIndicatorView alloc] 
                     initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite] autorelease];
    [self.activity startAnimating];
    self.activityButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:activity] autorelease];
    self.activityButtonItem.enabled = NO;
    self.navigationItem.rightBarButtonItem = activityButtonItem;

    [self.tableView setBackgroundView:nil];
    [self.tableView setBackgroundColor:[UIColor clearColor]];
    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        [addItemBackground setFrame:CGRectMake(45, 8, 680, 44)];
        [addItemTextField setFrame:CGRectMake(56, 8, 665, 43)];
    }
}


- (void)dealloc {
    [query removeObserver: self forKeyPath: @"rows"];
    [items release];
    [query release];
    [database release];
    [super dealloc];
}


- (void)showErrorAlert: (NSString*)message forOperation: (RESTOperation*)op {
    NSLog(@"%@: op=%@, error=%@", message, op, op.error);
    [(DemoAppDelegate*)[[UIApplication sharedApplication] delegate] 
        showAlert: message error: op.error fatal: NO];
}


-(void)setupSync {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *syncpoint = [defaults objectForKey:@"syncpoint"];
    NSURL *remoteURL = [NSURL URLWithString:syncpoint];

    RESTOperation *pull = [database pullFromDatabaseAtURL: remoteURL
                                                  options: kCouchReplicationContinuous];
    [pull onCompletion:^() {
        if (pull.isSuccessful)
            NSLog(@"continous sync triggered from %@", syncpoint);
        else
            [self showErrorAlert: @"Unable to sync with the server. You may still work offline."
                  forOperation: pull];
	}];

    RESTOperation *push = [database pushToDatabaseAtURL: remoteURL
                                                options: kCouchReplicationContinuous];
    [push onCompletion:^() {
        if (push.isSuccessful)
            NSLog(@"continous sync triggered to %@", syncpoint);
        else
            [self showErrorAlert: @"Unable to sync with the server. You may still work offline." 
                  forOperation: pull];
	}];
}


-(void)loadItemsIntoView {
    CouchQueryEnumerator* updatedRows = query.rows;
    if (updatedRows) {
        self.items = [[updatedRows.allObjects mutableCopy] autorelease];
        NSLog(@"loadItemsIntoView: %u rows!", items.count);
        [self.tableView reloadData];
        [self.activity stopAnimating];
    }
}


- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object
                        change: (NSDictionary*)change context: (void*)context 
{
    if (object == query)
        [self loadItemsIntoView];
}


#pragma mark -
#pragma mark Table view data source


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 50;
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.items count];
}


// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Reuse or create a cell:
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier: @"Cell"];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle: UITableViewCellStyleDefault
                                       reuseIdentifier: @"Cell"] autorelease];
        cell.textLabel.font = [UIFont fontWithName: @"Helvetica" size:18.0];
        cell.textLabel.backgroundColor = [UIColor clearColor];
        
        static UIColor* kBGColor;
        if (!kBGColor)
            kBGColor = [[UIColor colorWithPatternImage: [UIImage imageNamed:@"item_background"]] 
                            retain];
        cell.backgroundColor = kBGColor;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }

    // Configure the cell contents:
    CouchQueryRow *row = [self.items objectAtIndex:indexPath.row];
    NSDictionary* properties = row.document.properties;
    BOOL checked = [[properties valueForKey:@"check"] boolValue];
    
    UILabel *labelWithText = cell.textLabel;
    labelWithText.text = [properties valueForKey:@"text"];
    labelWithText.textColor = checked ? [UIColor grayColor] : [UIColor blackColor];

    [cell.imageView setImage:[UIImage imageNamed:
            (checked ? @"list_area___checkbox___checked" : @"list_area___checkbox___unchecked")]];
    return cell;
}


- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle 
     forRowAtIndexPath:(NSIndexPath *)indexPath {

    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the document from the database, asynchronously.
        RESTOperation* op = [[[items objectAtIndex:indexPath.row] document] DELETE];
        [op onCompletion: ^{
            if (!op.isSuccessful) {
                // If the delete failed, undo the table row deletion by reloading from the query:
                [self showErrorAlert: @"Failed to delete item" forOperation: op];
                [self loadItemsIntoView];
            }
        }];
        [op start];
        
        // Delete the row from the table data source.
        [items removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                              withRowAnimation:UITableViewRowAnimationFade];
    }
}


#pragma mark -
#pragma mark Table view delegate


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CouchQueryRow *row = [self.items objectAtIndex:indexPath.row];
    CouchDocument *doc = [row document];

    // Toggle the document's 'checked' property:
    NSMutableDictionary *docContent = [[doc.properties mutableCopy] autorelease];
    BOOL wasChecked = [[docContent valueForKey:@"check"] boolValue];
    [docContent setObject:[NSNumber numberWithBool:!wasChecked] forKey:@"check"];

    // Save changes, asynchronously:
    RESTOperation* op = [doc putProperties:docContent];
    [op onCompletion: ^{
        if (op.error)
            [self showErrorAlert: @"Failed to update item" forOperation: op];
        else
            NSLog(@"updated doc! %@", [op description]);
        // Re-run the query:
		[self.query start];
    }];
    [op start];
}


#pragma mark -
#pragma mark UITextField delegate


- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
    [addItemBackground setImage:[UIImage imageNamed:@"textfield___inactive.png"]];

	return YES;
}


- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [addItemBackground setImage:[UIImage imageNamed:@"textfield___active.png"]];
}


-(void)textFieldDidEndEditing:(UITextField *)textField {
    // Get the name of the item from the text field:
	NSString *text = addItemTextField.text;
    if (text.length == 0) {
        return;
    }
    [addItemTextField setText:nil];

    // Construct a unique document ID that will sort chronologically:
    CFUUIDRef uuid = CFUUIDCreate(nil);
    NSString *guid = (NSString*)CFUUIDCreateString(nil, uuid);
    CFRelease(uuid);
	NSString *docId = [NSString stringWithFormat:@"%f-%@", CFAbsoluteTimeGetCurrent(), guid];
    [guid release];

    // Create the new document's properties:
	NSDictionary *inDocument = [NSDictionary dictionaryWithObjectsAndKeys:text, @"text"
                                , [NSNumber numberWithBool:NO], @"check"
                                , [[NSDate date] description], @"created_at"
                                , nil];

    // Save the document, asynchronously:
    CouchDocument* doc = [database documentWithID: docId];
    RESTOperation* op = [doc putProperties:inDocument];
    [op onCompletion: ^{
        if (op.error)
            [self showErrorAlert: @"Failed to save new item" forOperation: op];
        else
            NSLog(@"saved doc! %@", [op description]);
        // Re-run the query:
		[self.query start];
	}];
    [op start];
}


@end
