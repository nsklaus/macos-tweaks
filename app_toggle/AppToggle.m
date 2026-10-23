// AppToggle — Ammonia tweak: a click on an app's Dock icon shows or hides the app, and
// selecting an app (Dock, ⌘Tab, Spotlight...) shows its windows, minimized ones included.
//
//   Dock click, app in the background or hidden: all windows minimized -> all restored;
//     otherwise the app comes to the front as usual (minimized windows stay minimized)
//   Dock click, app already in front: a window visible -> the app hides; all windows
//     minimized -> all restored
//   app without windows: as usual (the app opens one its own way)
//   any other activation (⌘Tab...): all windows minimized -> all restored
//
// Turn off: defaults write -g TweaksAppToggle -bool NO   (YES, or unset: on), then relaunch apps.
//
// Install: /var/ammonia/core/tweaks/libapptoggle.dylib, whitelist ".app/Contents/MacOS/" (every app).

#import <AppKit/AppKit.h>  // types only: this dylib does not link AppKit
#import "../shared/Tweak.h"

// Findings (macOS 27):
//   a Dock click on a running app, in front or not: the Dock brings it to the front
//     (_CPSSetFrontProcessWithOptions), then sends it the reopen Apple event (aevt/rapp), every
//     time (logged inside the Dock). ⌘Tab, drawn by the Dock too, only activates: no reopen
//   AppKit handles reopen in -[NSApplication _handleAEReopen:] (an NSAppleEventDescriptor):
//     with no visible window it restores the most recently minimized window, or opens a new one
//   the activation lands just before reopen, and -isActive is already YES when reopen arrives,
//     sometimes before NSApplicationDidBecomeActiveNotification is posted: "was it in front
//     before the click" comes from the notifications only (became active, and not just now)
//   the Dock can't do this on its own: it isn't accessibility-trusted, and minimizing and
//     restoring are done by the app, which reports them to the Dock (MinimizedWindowList)
//   Finder's desktop is a window, palettes are panels: only titled, miniaturizable windows that
//     aren't panels count

// Seconds between activation and reopen; a second click that fast (a double click) doesn't hide.
static const NSTimeInterval kATJustActivated = 0.2;

static BOOL gActive = NO;   // as the activation notifications say, not -isActive
static CFAbsoluteTime gActivatedAt = 0;
static IMP gOrigReopen = NULL;

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

static void ATInstall(void) {
    Class appClass = NSClassFromString(@"NSApplication");
    SEL reopen = NSSelectorFromString(@"_handleAEReopen:");
    if (!TWHook(appClass, reopen, ^(NSApplication *app, id event) {
        NSArray<NSWindow *> *windows = ATWindows(app);
        BOOL wasInFront = gActive && CFAbsoluteTimeGetCurrent() - gActivatedAt > kATJustActivated;
        if (ATRestoreIfAllMinimized(windows)) return;
        if (wasInFront) {
            for (NSWindow *w in windows) {
                if (!w.isMiniaturized) { [app hide:nil]; return; }
            }
        }
        ((void (*)(id, SEL, id))gOrigReopen)(app, reopen, event);
    }, &gOrigReopen)) {
        NSLog(@"[AppToggle] -[NSApplication _handleAEReopen:] not found, nothing installed");
        return;
    }

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:@"NSApplicationDidBecomeActiveNotification" object:nil queue:nil
                    usingBlock:^(NSNotification *note) {
        gActive = YES;
        gActivatedAt = CFAbsoluteTimeGetCurrent();
        ATRestoreIfAllMinimized(ATWindows(note.object));
    }];
    [center addObserverForName:@"NSApplicationDidResignActiveNotification" object:nil queue:nil
                    usingBlock:^(NSNotification *note) { gActive = NO; }];
    NSLog(@"[AppToggle] installed in %@", NSBundle.mainBundle.bundleIdentifier);
}

__attribute__((constructor))
static void ATInit(void) {
    @autoreleasepool {
        if (!NSClassFromString(@"NSApplication")) return;   // not an AppKit app
        id setting = [NSUserDefaults.standardUserDefaults objectForKey:@"TweaksAppToggle"];
        if (setting && ![setting boolValue]) return;   // turned off
        ATInstall();
    }
}
