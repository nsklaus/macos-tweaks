// AppToggle — Ammonia tweak: a click on an app's Dock icon shows or hides the app, and
// selecting an app (Dock, ⌘Tab, Spotlight...) shows its windows, minimized ones included.
//
//   Dock click, app in the background or hidden: all windows minimized -> all restored;
//     otherwise the app comes to the front as usual (minimized windows stay minimized)
//   Dock click, app already in front: a window visible -> the app hides; all windows
//     minimized -> all restored
//   app without windows: as usual (the app opens one its own way)
//   any other activation (⌘Tab...): all windows minimized -> all restored, unless the system
//     activated the app only because another one was hidden or quit
//
// Turn off: defaults write -g TweaksAppToggle -bool NO   (YES, or unset: on), then relaunch apps.
//
// Install: /var/ammonia/core/tweaks/libapptoggle.dylib, whitelist ".app/Contents/MacOS/" (every app).

#import <AppKit/AppKit.h>  // types only: this dylib does not link AppKit
#import <dlfcn.h>
#import <ptrauth.h>

// Findings (macOS 27):
//   a Dock click on a running app, in front or not: the Dock brings it to the front
//     (_CPSSetFrontProcessWithOptions), then sends it the reopen Apple event (aevt/rapp), every
//     time (logged inside the Dock). ⌘Tab, drawn by the Dock too, only activates: no reopen
//   AppKit handles reopen in -[NSApplication _handleAEReopen:] (an NSAppleEventDescriptor):
//     with no visible window it restores the most recently minimized window, or opens a new one.
//     Finder doesn't go through it: it installs its own aevt/rapp handler (a function in the
//     Finder binary), so the hook is on the Apple event handler itself, whoever installed it.
//     It is wrapped at NSApplicationDidFinishLaunchingNotification, after the app's own
//     handlers; a reopen during launch goes to the original (AppKit delays it until launched)
//   the activation lands just before reopen, and -isActive is already YES when reopen arrives,
//     sometimes before NSApplicationDidBecomeActiveNotification is posted: "was it in front
//     before the click" comes from the notifications only (became active, and not just now)
//   the Dock can't do this on its own: it isn't accessibility-trusted, and minimizing and
//     restoring are done by the app, which reports them to the Dock (MinimizedWindowList)
//   when an app is hidden (⌘H, or a Dock click here) or quits, the system activates another
//     one (often Finder): every app gets NSWorkspaceDidActivateApplicationNotification for it
//     and NSWorkspaceDidHideApplicationNotification at the same time, or
//     NSWorkspaceDidTerminateApplicationNotification up to ~25 ms later
//   Chromium apps (Brave) start from a small executable that links only libSystem, and load
//     AppKit later from their framework: at constructor time NSApplication may not exist yet,
//     so what needs AppKit waits for NSApplicationDidFinishLaunchingNotification, which only an
//     AppKit app posts; the activation observers need only Foundation and are added at once
//   Finder's desktop is a window, palettes are panels: only titled, miniaturizable windows that
//     aren't panels count

// Seconds between activation and reopen; a second click that fast (a double click) doesn't hide.
static const NSTimeInterval kATJustActivated = 0.2;
// An activation this close to another app being hidden or quitting was made by the system;
// the decision waits kATFallbackWait for the notification that may come after it.
static const NSTimeInterval kATFallbackWindow = 0.3;
static const NSTimeInterval kATFallbackWait = 0.15;

static BOOL gActive = NO;   // as the activation notifications say, not -isActive
static CFAbsoluteTime gActivatedAt = 0;
static CFAbsoluteTime gOtherAppLeftAt = 0;   // another app was hidden or quit
static AEEventHandlerUPP gOrigReopen = NULL;
static SRefCon gOrigReopenRefcon = 0;

// The app's document windows, shown or minimized.
static NSArray<NSWindow *> *ATWindows(NSApplication *app) {
    Class panel = NSClassFromString(@"NSPanel");
    NSMutableArray *windows = [NSMutableArray array];
    for (NSWindow *w in app.windows) {
        NSWindowStyleMask mask = w.styleMask;
        if ([w isKindOfClass:panel] || !(mask & NSWindowStyleMaskTitled)
            || !(mask & NSWindowStyleMaskMiniaturizable)) continue;
        if (w.isVisible || w.isMiniaturized) [windows addObject:w];
    }
    return windows;
}

// Restore every window if all of them are minimized. Returns whether it did.
static BOOL ATRestoreIfAllMinimized(NSArray<NSWindow *> *windows) {
    if (windows.count == 0) return NO;
    for (NSWindow *w in windows)
        if (!w.isMiniaturized) return NO;
    for (NSWindow *w in windows)
        [w deminiaturize:nil];
    return YES;
}

// The reopen Apple event (aevt/rapp), in place of the app's own handler.
static OSErr ATReopen(const AppleEvent *event, AppleEvent *reply, SRefCon refcon) {
    NSApplication *app = [NSClassFromString(@"NSApplication") sharedApplication];
    NSArray<NSWindow *> *windows = ATWindows(app);
    BOOL wasInFront = gActive && CFAbsoluteTimeGetCurrent() - gActivatedAt > kATJustActivated;
    if (ATRestoreIfAllMinimized(windows)) return noErr;
    if (wasInFront) {
        for (NSWindow *w in windows) {
            if (!w.isMiniaturized) { [app hide:nil]; return noErr; }
        }
    }
    return gOrigReopen(event, reply, gOrigReopenRefcon);
}

// Once the app has launched (AppKit is loaded): watch other apps, wrap the reopen handler the
// app installed while launching.
static void ATInstallOnLaunch(void) {
    NSNotificationCenter *workspace = [[NSClassFromString(@"NSWorkspace") sharedWorkspace] notificationCenter];
    for (NSString *name in @[@"NSWorkspaceDidHideApplicationNotification",
                             @"NSWorkspaceDidTerminateApplicationNotification"]) {
        [workspace addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            gOtherAppLeftAt = CFAbsoluteTimeGetCurrent();
        }];
    }
    if (AEGetEventHandler(kCoreEventClass, kAEReopenApplication, &gOrigReopen,
                          &gOrigReopenRefcon, false) != noErr || !gOrigReopen) {
        NSLog(@"[AppToggle] no reopen handler, nothing installed for Dock clicks");
        return;
    }
    if (AEInstallEventHandler(kCoreEventClass, kAEReopenApplication, ATReopen, 0, false) != noErr) {
        NSLog(@"[AppToggle] could not install the reopen handler");
        return;
    }
    Dl_info info;
    const char *owner = dladdr(ptrauth_strip((void *)gOrigReopen, ptrauth_key_function_pointer),
                               &info) ? info.dli_fname : "?";
    NSLog(@"[AppToggle] installed in %@ (reopen handler from %s)",
          NSBundle.mainBundle.bundleIdentifier, strrchr(owner, '/') ? strrchr(owner, '/') + 1 : owner);
}

static void ATInstall(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:@"NSApplicationDidBecomeActiveNotification" object:nil queue:nil
                    usingBlock:^(NSNotification *note) {
        gActive = YES;
        CFAbsoluteTime activatedAt = gActivatedAt = CFAbsoluteTimeGetCurrent();
        NSApplication *app = note.object;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kATFallbackWait * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gActive || gActivatedAt != activatedAt) return;   // left or activated again
            if (fabs(gOtherAppLeftAt - activatedAt) < kATFallbackWindow) return;   // by the system
            ATRestoreIfAllMinimized(ATWindows(app));
        });
    }];
    [center addObserverForName:@"NSApplicationDidResignActiveNotification" object:nil queue:nil
                    usingBlock:^(NSNotification *note) { gActive = NO; }];
    [center addObserverForName:@"NSApplicationDidFinishLaunchingNotification" object:nil queue:nil
                    usingBlock:^(NSNotification *note) { ATInstallOnLaunch(); }];
}

__attribute__((constructor))
static void ATInit(void) {
    @autoreleasepool {
        id setting = [NSUserDefaults.standardUserDefaults objectForKey:@"TweaksAppToggle"];
        if (setting && ![setting boolValue]) return;   // turned off
        ATInstall();
    }
}
