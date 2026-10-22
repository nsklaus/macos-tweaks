// iTermTweaks — Ammonia tweak for iTerm2 (3.7.5, macOS 27).
//
// 1. Short context menu: the terminal's right-click menu keeps only Copy, Paste, Select All and
//    Clear Buffer (plus Copy Link Address / Copy URL, which iTerm2 adds on links).
// 2. Sequoia-style tabs fill the tab bar: on macOS 26+ iTerm2 keeps the 8pt padding meant for its
//    rounded Tahoe tabs even with "Use Sequoia-style tabs", leaving a strip under the tabs.
//
// Install: /var/ammonia/core/tweaks/libitermtweaks.dylib, whitelist "iTerm.app/Contents/MacOS/iTerm2".

#import <AppKit/AppKit.h>  // types only: this dylib does not link AppKit
#import "../shared/Tweak.h"

// Findings from the iTerm2 3.7.5 sources (sources/ContextMenu/iTermTextViewContextMenuHelper.m,
// sources/TerminalView/PseudoTerminal.m):
//   right-click goes through -[iTermTextViewContextMenuHelper contextMenuWithEvent:] (both the
//     NSView menuForEvent: path and openContextMenuAt:event:); the item actions are stable
//     selectors, unlike the localized titles
//   image, mark and timestamp menus come from the same method but have no Paste item
//   -[PseudoTerminal tabBarInsets] returns {0, 8, 8, 8} for the Regular/Light/Dark themes on
//     macOS 26+, whatever the tab style; compact windows return a left inset only

static IMP gOrigContextMenu = NULL;
static IMP gOrigTabBarInsets = NULL;

static BOOL ITKeepItem(NSMenuItem *item) {
    static NSSet<NSString *> *kept;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kept = [NSSet setWithArray:@[@"copy:", @"paste:", @"selectAll:", @"clearTextViewBuffer:",
                                     @"copyLinkAddress:", @"copyDetectedURL:"]];
    });
    return item.isSeparatorItem || (item.action && [kept containsObject:NSStringFromSelector(item.action)]);
}

// Drop separators that end up leading, trailing or doubled once items are removed.
static void ITTidySeparators(NSMenu *menu) {
    BOOL previousWasSeparator = YES;
    for (NSMenuItem *item in menu.itemArray.copy) {
        if (item.isSeparatorItem && previousWasSeparator) [menu removeItem:item];
        else previousWasSeparator = item.isSeparatorItem;
    }
    if (menu.itemArray.lastObject.isSeparatorItem) [menu removeItem:menu.itemArray.lastObject];
}

static void ITInstall(void) {
    SEL menuSel = @selector(contextMenuWithEvent:);
    if (!TWHook(NSClassFromString(@"iTermTextViewContextMenuHelper"), menuSel, ^NSMenu *(id self, NSEvent *event) {
        NSMenu *menu = ((NSMenu *(*)(id, SEL, NSEvent *))gOrigContextMenu)(self, menuSel, event);
        NSUInteger paste = [menu.itemArray indexOfObjectPassingTest:^BOOL(NSMenuItem *i, NSUInteger idx, BOOL *stop) {
            return i.action == @selector(paste:);
        }];
        if (paste == NSNotFound) return menu;  // image, mark or timestamp menu: leave it alone
        for (NSMenuItem *item in menu.itemArray.copy)
            if (!ITKeepItem(item)) [menu removeItem:item];
        ITTidySeparators(menu);
        return menu;
    }, &gOrigContextMenu))
        NSLog(@"[iTermTweaks] -[iTermTextViewContextMenuHelper contextMenuWithEvent:] not found, skipped");

    SEL insetsSel = @selector(tabBarInsets);
    if (!TWHook(NSClassFromString(@"PseudoTerminal"), insetsSel, ^NSEdgeInsets(id self) {
        NSEdgeInsets insets = ((NSEdgeInsets (*)(id, SEL))gOrigTabBarInsets)(self, insetsSel);
        if (insets.left == 8 && insets.right == 8 &&
            [NSUserDefaults.standardUserDefaults boolForKey:@"UseSequoiaStyleTabs"])
            return NSEdgeInsetsZero;
        return insets;
    }, &gOrigTabBarInsets))
        NSLog(@"[iTermTweaks] -[PseudoTerminal tabBarInsets] not found, skipped");

    NSLog(@"[iTermTweaks] installed");
}

__attribute__((constructor))
static void ITInit(void) {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.googlecode.iterm2"])
            ITInstall();  // iTerm2's own classes are registered before inserted libraries run
    }
}
