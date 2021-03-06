// This file is part of Scroll Reverser <https://pilotmoon.com/scrollreverser/>
// Licensed under Apache License v2.0 <http://www.apache.org/licenses/LICENSE-2.0>

#import "DebugWindowController.h"
#import "Logger.h"
#import "LoggerScrollView.h"
#import "AppDelegate.h"

@interface DebugWindowController ()
@property NSDateFormatter *df;
@property NSTimer *refreshTimer;
@end

@implementation DebugWindowController

- (void)setLogger:(Logger *)logger
{
    if (_logger) {
        [_logger unbind:@"enabled"];
    }
    if (logger) {
        [logger bind:@"enabled" toObject:self withKeyPath:@"paused" options:@{NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];
    }
   _logger=logger;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.logger=nil;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.df=[[NSDateFormatter alloc] init];
    self.df.dateFormat=@"HH:mm:ss.S";
    self.consoleTableView.dataSource=self;
    self.consoleTableView.delegate=self;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(observeLogEntriesChange:) name:LoggerEntriesChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(observeLogUpdatesWaiting:) name:LoggerUpdatesWaiting object:nil];
    [self addObserver:self forKeyPath:@"paused" options:NSKeyValueObservingOptionInitial context:nil];
    [self.consoleTableView reloadData];
    [self updateConsole];
}

- (void)observeLogEntriesChange:(NSNotification *)note
{
    NSIndexSet *const appendedIndexes=[note userInfo][LoggerEntriesAppended];
    NSIndexSet *const removedIndexes=[note userInfo][LoggerEntriesRemoved];

    if (removedIndexes) {
        [self.consoleTableView removeRowsAtIndexes:removedIndexes withAnimation:NSTableViewAnimationEffectNone];
    }
    else if (appendedIndexes) {
        [self.consoleTableView insertRowsAtIndexes:appendedIndexes withAnimation:NSTableViewAnimationEffectNone];
    }
    else {
         [self.consoleTableView reloadData];
    }
}

- (void)observeLogUpdatesWaiting:(NSNotification *)note
{
    if (self.window.isVisible && ![self.refreshTimer isValid]) {
        self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(updateConsole) userInfo:nil repeats:NO];
    }
}

- (void)showWindow:(id)sender
{
    [[self window] setLevel:NSFloatingWindowLevel];
    [[self window] setFrameAutosaveName:@"DebugWindow"];
    [[self window] center];
    [NSApp activateIgnoringOtherApps:YES];
    // small delay to prevent flash of window drawing
    dispatch_after(0.05, dispatch_get_main_queue(), ^{
        [super showWindow:sender];
    });
}

- (IBAction)clearLog:(id)sender {
    [self.logger clear];
    [self.appDelegate logAppEvent:@"Log cleared"];
}

- (IBAction)logState:(id)sender {
    [self.appDelegate logAppEvent:@"Settings"];
}

- (IBAction)showDemoWindow:(id)sender {
    [self.appDelegate showTestWindow:sender];
}

- (void)updateConsole
{
    [self.consoleTableView beginUpdates];
    [self.logger process];
    [self.consoleTableView endUpdates];
    [self scrollToBottom];
}

- (void)scrollToBottom
{
    const NSPoint newScrollOrigin=NSMakePoint(0.0,NSMaxY([[self.consoleScrollView documentView] frame])
                                              -NSHeight([[self.consoleScrollView contentView] bounds]));
    [[self.consoleScrollView documentView] scrollPoint:newScrollOrigin];
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object==self && [keyPath isEqualToString:@"paused"]) {
        self.consoleScrollView.scrollingAllowed=self.paused;
        self.consoleScrollView.hasVerticalScroller=self.paused;
        self.consoleScrollView.hasHorizontalScroller=self.paused;
        if (self.paused) {
            [self.consoleScrollView flashScrollers];
        }
        else {
            [self.consoleTableView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        }
        [self.appDelegate logAppEvent:self.paused?@"Log paused":@"Log started"];
    }
}

- (AppDelegate *)appDelegate {
    return (AppDelegate *)[NSApp delegate];
}

#pragma mark pasteboard copy

- (void)copy:(id)sender
{
    NSMutableString *str=[@"" mutableCopy];
    [[self.consoleTableView selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [str appendString:[[self formatEntry:[self.logger entryAtIndex:idx]] string]];
        [str appendString:@"\n"];
    }];
    
    if ([str length]>0) {
        NSPasteboard *const pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb writeObjects:@[str]];
    }
    
}

#pragma mark Table view delegate/datasource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.logger.entryCount;
}

- (NSAttributedString *)formatEntry:(NSDictionary *)entry
{
    NSMutableAttributedString *result=[[NSMutableAttributedString alloc] initWithString:@""];
    
    // data to log
    NSString *const messageString=entry[LoggerKeyMessage];
    const BOOL special=[entry[LoggerKeyType] isEqualToString:LoggerTypeSpecial];
    NSDate *const timestamp=entry[LoggerKeyTimestamp];
    
    if (timestamp) {
        NSDictionary *const dateAttributes=@{NSForegroundColorAttributeName: [NSColor grayColor]};
        NSString *const dateString=[[self.df stringFromDate:timestamp] stringByAppendingString:@" "];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:dateString
                                                                       attributes:dateAttributes]];
        
    }
    
    if (messageString) {
        NSDictionary *const messageAttributes=special?@{NSForegroundColorAttributeName: [NSColor blueColor]}:@{};
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:messageString
                                                                       attributes:messageAttributes]];
    }
    
    return result;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    NSTableCellView *const result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    result.textField.attributedStringValue=[self formatEntry:[self.logger entryAtIndex:row]];
    return result;
}

- (NSIndexSet *)tableView:(NSTableView *)tableView selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes
{
    return self.paused?proposedSelectionIndexes:nil;
}

#pragma mark Strings

- (NSString *)uiStringDebugConsole {
    return @"Scroll Reverser Debug Console";
}

- (NSString *)uiStringClear {
    return @"Clear";
}

- (NSString *)uiStringPause {
    return @"Pause";
}

- (NSString *)uiStringLogState {
    return @"Log Current Settings";
}

- (NSString *)uiStringShowTestWindow {
    return @"Show Test Window";
}


@end

