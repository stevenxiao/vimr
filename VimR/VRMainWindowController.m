/**
 * Tae Won Ha — @hataewon
 *
 * http://taewon.de
 * http://qvacua.com
 *
 * See LICENSE
 */

#import <PSMTabBarControl/PSMTabBarControl.h>
#import <MacVimFramework/MacVimFramework.h>
#import "VRMainWindowController.h"
#import "VRLog.h"
#import "MMAlert.h"
#import "VRUtils.h"


@interface VRMainWindowController ()

@property BOOL processOngoing;
@property BOOL needsToResize;
@property BOOL isReplyToGuiResize;
@property BOOL setUpDone;

@end

@implementation VRMainWindowController

#pragma mark Public
- (void)cleanupAndClose {
    log4Mark;
    [self close];
}

#pragma mark IBActions
- (IBAction)newTab:(id)sender {
    [self sendCommandToVim:@":tabe"];
}

- (IBAction)firstDebugAction:(id)sender {
    log4Mark;

    log4Debug(@"%@", [self.vimController currentTab]);
    log4Debug(@"%@", [NSValue valueWithSize:self.vimView.frame.size]);
}

- (IBAction)performClose:(id)sender {
    log4Mark;
    // TODO: when the doc is dirty, we could ask to save here!
    NSArray *descriptor = @[@"File", @"Close"];
    [self.vimController sendMessage:ExecuteMenuMsgID data:[self dataFromDescriptor:descriptor]];
}

- (IBAction)saveDocument:(id)sender {
    log4Mark;

    MMBuffer *currentBuffer = self.vimController.currentTab.buffer;
    if (currentBuffer.fileName == nil) {
        log4Debug(@"file name nil");
    }

    NSArray *descriptor = @[@"File", @"Save"];
    [self.vimController sendMessage:ExecuteMenuMsgID data:[self dataFromDescriptor:descriptor]];
}

- (IBAction)saveDocumentAs:(id)sender {
    log4Mark;
    [self sendCommandToVim:@"browse confirm sav"];
}

- (IBAction)revertDocumentToSaved:(id)sender {
    log4Mark;
    [self sendCommandToVim:@":e!"];
}

#pragma mark NSWindowController
- (id)initWithWindowNibName:(NSString *)windowNibName {
    self = [super initWithWindowNibName:windowNibName];
    if (self == nil) {
        return nil;
    }

    return self;
}

- (void)dealloc {
    log4Mark;

    [self.vimView removeFromSuperviewWithoutNeedingDisplay];
    [self.vimView cleanup];
}

#pragma mark MMViewDelegate informal protocol
- (void)liveResizeWillStart {
    /**
    * NOTE: During live resize Cocoa goes into "event tracking mode".  We have
    * to add the backend connection to this mode in order for resize messages
    * from Vim to reach MacVim.  We do not wish to always listen to requests
    * in event tracking mode since then MacVim could receive DO messages at
    * unexpected times (e.g. when a key equivalent is pressed and the menu bar
    * momentarily lights up).
    */
    log4Debug(@"starting resize");
    [self.connectionToBackend addRequestMode:NSEventTrackingRunLoopMode];
}

- (void)liveResizeDidEnd {
    // See comment regarding event tracking mode in -liveResizeWillStart.
    [self.connectionToBackend removeRequestMode:NSEventTrackingRunLoopMode];

    /**
    * NOTE: During live resize messages from MacVim to Vim are often dropped
    * (because too many messages are sent at once).  This may lead to
    * inconsistent states between Vim and MacVim; to avoid this we send a
    * synchronous resize message to Vim now (this is not fool-proof, but it
    * does seem to work quite well).
    * Do NOT send a SetTextDimensionsMsgID message (as opposed to
    * LiveResizeMsgID) since then the view is constrained to not be larger
    * than the screen the window mostly occupies; this makes it impossible to
    * resize the window across multiple screens.
    */

    int constrained[2];
    NSView <MMTextViewProtocol> *textView = self.vimView.textView;
    NSSize textViewSize = textView.frame.size;
    [textView constrainRows:&constrained[0] columns:&constrained[1] toSize:textViewSize];

    log4Debug(@"End of live resize, notify Vim that text dimensions are %dx%d", constrained[1], constrained[0]);

    NSData *data = [NSData dataWithBytes:constrained length:2 * sizeof(int)];
    BOOL liveResizeMsgSuccessful = [self.vimController sendMessageNow:LiveResizeMsgID data:data timeout:.5];

    if (!liveResizeMsgSuccessful) {
        /**
        * Sending of synchronous message failed.  Force the window size to
        * match the last dimensions received from Vim, otherwise we end up
        * with inconsistent states.
        */
        log4Debug(@"failed");
        [self resizeWindowToFitContentSize:self.vimView.desiredSize];
    }
}

#pragma mark MMVimControllerDelegate
- (void)vimController:(MMVimController *)controller handleShowDialogWithButtonTitles:(NSArray *)buttonTitles
                style:(NSAlertStyle)style message:(NSString *)message text:(NSString *)text
      textFieldString:(NSString *)textFieldString data:(NSData *)data {

    log4Mark;

    // copied from MacVim {
    MMAlert *alert = [[MMAlert alloc] init];

    // NOTE! This has to be done before setting the informative text.
    if (textFieldString) {
        alert.textFieldString = textFieldString;
    }

    alert.alertStyle = style;

    if (message) {
        alert.messageText = message;
    } else {
        // If no message text is specified 'Alert' is used, which we don't
        // want, so set an empty string as message text.
        alert.messageText = @"";
    }

    if (text) {
        alert.informativeText = text;
    } else if (textFieldString) {
        // Make sure there is always room for the input text field.
        alert.informativeText = @"";
    }

    unsigned i, count = buttonTitles.count;
    for (i = 0; i < count; ++i) {
        NSString *title = buttonTitles[i];
        // NOTE: The title of the button may contain the character '&' to
        // indicate that the following letter should be the key equivalent
        // associated with the button.  Extract this letter and lowercase it.
        NSString *keyEquivalent = nil;
        NSRange hotkeyRange = [title rangeOfString:@"&"];
        if (NSNotFound != hotkeyRange.location) {
            if ([title length] > NSMaxRange(hotkeyRange)) {
                NSRange keyEquivRange = NSMakeRange(hotkeyRange.location + 1, 1);
                keyEquivalent = [title substringWithRange:keyEquivRange].lowercaseString;
            }

            NSMutableString *string = [NSMutableString stringWithString:title];
            [string deleteCharactersInRange:hotkeyRange];
            title = string;
        }

        [alert addButtonWithTitle:title];

        // Set key equivalent for the button, but only if NSAlert hasn't
        // already done so.  (Check the documentation for
        // - [NSAlert addButtonWithTitle:] to see what key equivalents are
        // automatically assigned.)
        NSButton *btn = alert.buttons.lastObject;
        if (btn.keyEquivalent.length == 0 && keyEquivalent) {
            btn.keyEquivalent = keyEquivalent;
        }
    }

    [alert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:@selector(alertDidEnd:code:context:)
                        contextInfo:NULL];
    // } copied from MacVim
}

- (void)vimController:(MMVimController *)controller showScrollbarWithIdentifier:(int32_t)identifier
                state:(BOOL)state data:(NSData *)data {

    [self.vimView showScrollbarWithIdentifier:identifier state:state];
    self.needsToResize = YES;
}

- (void)vimController:(MMVimController *)controller setTextDimensionsWithRows:(int)rows columns:(int)columns
               isLive:(BOOL)live keepOnScreen:(BOOL)isReplyToGuiResize data:(NSData *)data {

    log4Mark;
    log4Debug(@"%d X %d\tlive: %@\tkeepOnScreen: %@", rows, columns, @(live), @(isReplyToGuiResize));
    [self.vimView setDesiredRows:rows columns:columns];

    if (!self.setUpDone) {
        log4Debug(@"not yet setup");
        return;
    }

    if (!live) {
        self.needsToResize = YES;
        self.isReplyToGuiResize = isReplyToGuiResize;
    }
}

- (void)vimController:(MMVimController *)controller openWindowWithData:(NSData *)data {
    log4Mark;

    self.window.acceptsMouseMovedEvents = YES; // Vim wants to have mouse move events

    self.vimView.tabBarControl.styleNamed = @"Metal";

    [self.window.contentView addSubview:self.vimView];
    self.vimView.autoresizingMask = NSViewNotSizable;

    [self.vimView addNewTabViewItem];

    self.setUpDone = YES;
    self.isReplyToGuiResize = YES;

    [self updateResizeConstraints];
    [self resizeWindowToFitContentSize:self.vimView.desiredSize];

    [self.window makeFirstResponder:self.vimView.textView];
}

- (void)vimController:(MMVimController *)controller showTabBarWithData:(NSData *)data {
    [self.vimView.tabBarControl setHidden:NO];

    log4Mark;
}

- (void)vimController:(MMVimController *)controller setScrollbarThumbValue:(float)value proportion:(float)proportion
           identifier:(int32_t)identifier data:(NSData *)data {

    log4Mark;
}

- (void)vimController:(MMVimController *)controller destroyScrollbarWithIdentifier:(int32_t)identifier
                 data:(NSData *)data {

    log4Mark;
    self.needsToResize = YES;
}

- (void)vimController:(MMVimController *)controller tabShouldUpdateWithData:(NSData *)data {
    log4Mark;
}

- (void)vimController:(MMVimController *)controller tabDidUpdateWithData:(NSData *)data {
    log4Mark;

    log4Debug(@"tabs: %@", [self.vimController tabs]);
}

- (void)vimController:(MMVimController *)controller tabDraggedWithData:(NSData *)data {
    log4Mark;
}

- (void)vimController:(MMVimController *)controller hideTabBarWithData:(NSData *)data {
    log4Mark;
}

- (void)vimController:(MMVimController *)controller setBufferModified:(BOOL)modified data:(NSData *)data {
    log4Mark;

    [self setDocumentEdited:modified];
}

- (void)vimController:(MMVimController *)controller setDocumentFilename:(NSString *)filename data:(NSData *)data {
    log4Mark;

    [self.window setRepresentedFilename:filename];
}

- (void)vimController:(MMVimController *)controller setWindowTitle:(NSString *)title data:(NSData *)data {
    self.window.title = title;
}

- (void)vimController:(MMVimController *)controller processFinishedForInputQueue:(NSArray *)inputQueue {
    if (self.processOngoing) {
        log4Debug(@"setting process ongoing to no");
        self.processOngoing = NO;
    }

    if (!self.needsToResize) {
        return;
    }

    log4Debug(@"resizing window to fit Vim view");
    self.needsToResize = NO;

    NSSize contentSize = self.vimView.desiredSize;
    contentSize = [self constrainContentSizeToScreenSize:contentSize];
    log4Debug(@"uncorrected size: %@", [NSValue valueWithSize:contentSize]);
    int rows = 0, cols = 0;
    contentSize = [self.vimView constrainRows:&rows columns:&cols toSize:contentSize];

    log4Debug(@"%d X %d", rows, cols);
    log4Debug(@"corrected size: %@", [NSValue valueWithSize:contentSize]);

    self.vimView.frameSize = contentSize;

    [self resizeWindowToFitContentSize:contentSize];

    self.isReplyToGuiResize = NO;
}

- (void)vimController:(MMVimController *)controller removeToolbarItemWithIdentifier:(NSString *)identifier {
    log4Mark;
}

- (void)vimController:(MMVimController *)controller handleBrowseWithDirectoryUrl:(NSURL *)url browseDir:(BOOL)dir saving:(BOOL)saving data:(NSData *)data {

    if (!saving) {
        return;
    }

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    if (url != nil) {
        [savePanel setDirectoryURL:url];
    }

    [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
        NSString *path = nil;
        if (result == NSOKButton) {
            path = savePanel.URL.path;
        }

        [savePanel orderBack:self];

        if (![controller sendDialogReturnToBackend:path]) {
            log4Error(@"some error occurred sending dialog return value %@ to backend!", path);
            return;
        }
    }];
}

#pragma mark NSWindowDelegate
- (void)windowDidBecomeMain:(NSNotification *)notification {
    [self.vimController sendMessage:GotFocusMsgID data:nil];
}

- (void)windowDidResignMain:(NSNotification *)notification {
    [self.vimController sendMessage:LostFocusMsgID data:nil];
}

- (BOOL)windowShouldClose:(id)sender {
    log4Mark;
    /**
    * this gets called when Cmd-W
    */

    // don't close the window or tab; instead let Vim decide what to do
    [self.vimController sendMessage:VimShouldCloseMsgID data:nil];

    return NO;
}

- (void)windowDidResize:(id)sender {
    /**
    * NOTE: Since we have no control over when the window may resize (Cocoa
    * may resize automatically) we simply set the view to fill the entire
    * window.  The vim view takes care of notifying Vim if the number of
    * (rows,columns) changed.
    */
    self.vimView.frameSize = [self.window contentRectForFrameRect:self.window.frame].size;
}

#pragma mark Private
- (NSUInteger)indexOfSelectedDocument {
    PSMTabBarControl *tabBar = self.vimView.tabBarControl;
    return [tabBar.representedTabViewItems indexOfObject:tabBar.tabView.selectedTabViewItem];
}

- (void)sendCommandToVim:(NSString *)command {
    while (self.processOngoing) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }

    self.processOngoing = YES;

    log4Debug(@"sending command %@", command);
    [self.vimController addVimInput:SF(@"<C-\\><C-N>%@<CR>", command)];
}

- (NSData *)dataFromDescriptor:(NSArray *)descriptor {
    return [@{@"descriptor" : descriptor} dictionaryAsData];
}

- (void)alertDidEnd:(MMAlert *)alert code:(int)code context:(void *)controllerContext {
    // copied from MacVim {
    NSArray *ret = nil;
    code = code - NSAlertFirstButtonReturn + 1;

    if ([alert isKindOfClass:[MMAlert class]] && alert.textField) {
        ret = @[@(code), alert.textField.stringValue];
    } else {
        ret = @[@(code)];
    }

    log4Debug(@"Alert return=%@", ret);

    // NOTE!  This causes the sheet animation to run its course BEFORE the rest
    // of this function is executed.  If we do not wait for the sheet to
    // disappear before continuing it can happen that the controller is
    // released from under us (i.e. we'll crash and burn) because this
    // animation is otherwise performed in the default run loop mode!
    [alert.window orderOut:self];

    // TODO: why not use -sendDialogReturnToBackend:?
    [self.vimController tellBackend:ret];
    // } copied from MacVim
}

- (NSRect)constrainFrame:(NSRect)frame {
    // Constrain the given (window) frame so that it fits an even number of
    // rows and columns.
    NSWindow *window = self.window;
    NSRect contentRect = [window contentRectForFrameRect:frame];
    NSSize constrainedSize = [self.vimView constrainRows:NULL columns:NULL toSize:contentRect.size];

    contentRect.origin.y += contentRect.size.height - constrainedSize.height;
    contentRect.size = constrainedSize;

    return [window frameRectForContentRect:contentRect];
}

- (void)resizeWindowToFitContentSize:(NSSize)contentSize {
    logSize4Debug(@"contentSize", contentSize);
    NSWindow *window = self.window;
    NSRect frame = window.frame;
    NSRect contentRect = [window contentRectForFrameRect:frame];

    // Keep top-left corner of the window fixed when resizing.
    contentRect.origin.y -= contentSize.height - contentRect.size.height;
    contentRect.size = contentSize;

    NSRect newFrame = [window frameRectForContentRect:contentRect];

    logRect4Debug(@"old", frame);
    logRect4Debug(@"new", newFrame);

    NSScreen *screen = window.screen;
    if (self.isReplyToGuiResize && screen) {
        // Ensure that the window fits inside the visible part of the screen.
        // If there are more than one screen the window will be moved to fit
        // entirely in the screen that most of it occupies.
        NSRect maxFrame = screen.visibleFrame;
        maxFrame = [self constrainFrame:maxFrame];

        if (newFrame.size.width > maxFrame.size.width) {
            newFrame.size.width = maxFrame.size.width;
            newFrame.origin.x = maxFrame.origin.x;
        }

        if (newFrame.size.height > maxFrame.size.height) {
            newFrame.size.height = maxFrame.size.height;
            newFrame.origin.y = maxFrame.origin.y;
        }

        if (newFrame.origin.y < maxFrame.origin.y) {
            newFrame.origin.y = maxFrame.origin.y;
        }

        if (NSMaxY(newFrame) > NSMaxY(maxFrame)) {
            newFrame.origin.y = NSMaxY(maxFrame) - newFrame.size.height;
        }

        if (newFrame.origin.x < maxFrame.origin.x) {
            newFrame.origin.x = maxFrame.origin.x;
        }

        if (NSMaxX(newFrame) > NSMaxX(maxFrame)) {
            newFrame.origin.x = NSMaxX(maxFrame) - newFrame.size.width;
        }
    }

    [window setFrame:newFrame display:YES];

    NSPoint oldTopLeft = {frame.origin.x, NSMaxY(frame)};
    NSPoint newTopLeft = {newFrame.origin.x, NSMaxY(newFrame)};
    if (NSEqualPoints(oldTopLeft, newTopLeft)) {
        log4Debug(@"returning since top left point equal");
        return;
    }

    // NOTE: The window top left position may change due to the window
    // being moved e.g. when the tabline is shown so we must tell Vim what
    // the new window position is here.
    // NOTE 2: Vim measures Y-coordinates from top of screen.
    int pos[2] = {(int) newTopLeft.x, (int) (NSMaxY(window.screen.frame) - newTopLeft.y)};
    [self.vimController sendMessage:SetWindowPositionMsgID data:[NSData dataWithBytes:pos length:2 * sizeof(int)]];
}

- (NSSize)constrainContentSizeToScreenSize:(NSSize)contentSize {
    NSWindow *win = self.window;
    if (!win.screen) {
        return contentSize;
    }

    // NOTE: This may be called in both windowed and full-screen mode.  The
    // "visibleFrame" method does not overlap menu and dock so should not be
    // used in full-screen.
    NSRect screenRect = win.screen.visibleFrame;
    NSRect rect = [win contentRectForFrameRect:screenRect];

    if (contentSize.height > rect.size.height) {
        contentSize.height = rect.size.height;
    }

    if (contentSize.width > rect.size.width) {
        contentSize.width = rect.size.width;
    }

    return contentSize;
}

- (NSConnection *)connectionToBackend {
    NSDistantObject *proxy = self.vimController.backendProxy;

    return proxy.connectionForProxy;
}

- (void)updateResizeConstraints {
    if (!self.setUpDone) {
        return;
    }

    // Set the resize increments to exactly match the font size; this way the
    // window will always hold an integer number of (rows,columns).
    self.window.contentResizeIncrements = self.vimView.textView.cellSize;

    self.window.contentMinSize = self.vimView.minSize;
}

@end