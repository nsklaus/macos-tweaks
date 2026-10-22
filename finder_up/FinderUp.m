// FinderUp — Ammonia tweak: separate Back, Forward and Up (Enclosing Folder) buttons
// in Finder's toolbar, built like Finder's own buttons.
//
// Install: /var/ammonia/core/tweaks/libfinderup.dylib, whitelist "Finder.app/Contents/MacOS/Finder".
//
// Findings from lldb (macOS 27, Finder):
//   toolbar class   : TToolbar
//   delegate class  : TToolbarController
//   allowed items   : -toolbarAllowedItemIdentifiers:                (standard NSToolbarDelegate)
//   item factory    : -toolbar:itemForItemIdentifier:withPropertyListRepresentation:willBeInsertedIntoToolbar:
//   Go menu actions : cmdBack:, cmdForward:, cmdOpenParent: — target nil (first responder)
//   model button    : New Folder (com.apple.finder.NFLD), NSButton, bezel 11, 40 x 25

#import "FUShared.h"

static IMP gOrigAllowed = NULL;
static IMP gOrigItem    = NULL;

static const FUButton *FUFind(NSString *ident) {
    for (int i = 0; i < kFUCount; i++)
        if ([kFUButtons[i].ident isEqualToString:ident]) return &kFUButtons[i];
    return NULL;
}

// Finder's own single buttons (New Folder, com.apple.finder.NFLD), measured in lldb:
// a plain NSButton, bezel style 11 (NSBezelStyleTexturedRounded), 40 x 25 points.
static const CGFloat kFUButtonWidth  = 40.0;
static const CGFloat kFUButtonHeight = 25.0;

// A toolbar item that holds a view is not validated by AppKit on its own: Apple's
// documented pattern is to subclass NSToolbarItem and override -validate. The
// subclass is created at runtime, since this dylib does not link AppKit.
// -validate asks the responder that would receive the action (Finder's window
// controller) whether it is currently possible, exactly as the Go menu does.
static Class FUItemClass(void) {
    static Class cls = Nil;
    if (cls) return cls;
    cls = objc_allocateClassPair(NSClassFromString(@"NSToolbarItem"), "FUToolbarItem", 0);
    IMP validate = imp_implementationWithBlock(^(NSToolbarItem *self) {
        id app    = [NSClassFromString(@"NSApplication") sharedApplication];
        id target = [app targetForAction:self.action to:nil from:self];
        BOOL ok   = (target != nil);
        if (ok && [target respondsToSelector:@selector(validateUserInterfaceItem:)])
            ok = [target validateUserInterfaceItem:self];
        ((NSControl *)self.view).enabled = ok;
    });
    class_addMethod(cls, @selector(validate), validate, "v@:");
    objc_registerClassPair(cls);
    return cls;
}

static NSToolbarItem *FUMakeItem(const FUButton *b) {
    Class imageClass  = NSClassFromString(@"NSImage");
    Class buttonClass = NSClassFromString(@"NSButton");
    SEL action        = NSSelectorFromString(b->action);

    NSToolbarItem *item = [[FUItemClass() alloc] initWithItemIdentifier:b->ident];
    item.label        = b->label;
    item.paletteLabel = b->paletteLabel;
    item.toolTip      = b->paletteLabel;

    NSImage *img = [imageClass imageWithSystemSymbolName:b->symbol
                                accessibilityDescription:b->paletteLabel];
    img.template = YES;   // monochrome glyph, tinted by AppKit

    // Built like Finder's own buttons, so it draws and reacts to clicks like them.
    // No explicit target, same route as the Go menu: the action goes to the first
    // responder of the window.
    NSButton *button = [buttonClass buttonWithImage:img target:nil action:action];
    button.bezelStyle = 11;   // NSBezelStyleTexturedRounded
    // Fixed frame, like Finder's buttons. Not Auto Layout constraints: those size the
    // alignment rect, and the bezel's overhang would be added around it (measured:
    // 42 x 28 instead of 40 x 25, sitting 2 points higher than Finder's buttons).
    button.frame = NSMakeRect(0, 0, kFUButtonWidth, kFUButtonHeight);

    item.view   = button;
    item.action = action;   // read back by -validate
    return item;
}

static void FUInstall(void) {
    static BOOL done = NO;
    if (done) return;

    Class cls      = NSClassFromString(@"TToolbarController");
    SEL allowedSel = @selector(toolbarAllowedItemIdentifiers:);
    SEL itemSel    = NSSelectorFromString(
        @"toolbar:itemForItemIdentifier:withPropertyListRepresentation:willBeInsertedIntoToolbar:");

    // Install both hooks or none: a listed item that can't be built would be worse than nothing.
    if (!cls || !class_getInstanceMethod(cls, allowedSel) || !class_getInstanceMethod(cls, itemSel)) {
        NSLog(@"[FinderUp] Finder internals not found, not installing");
        return;
    }
    done = YES;

    // 1. Offer our buttons in Customize Toolbar.
    FUHook(cls, allowedSel, ^NSArray *(id self, NSToolbar *toolbar) {
        NSArray *ids = ((NSArray *(*)(id, SEL, NSToolbar *))gOrigAllowed)(self, allowedSel, toolbar);
        if (ids == nil) return ids;
        NSMutableArray *all = [ids mutableCopy];
        for (int i = 0; i < kFUCount; i++)
            if (![all containsObject:kFUButtons[i].ident]) [all addObject:kFUButtons[i].ident];
        return all;
    }, &gOrigAllowed);

    // 2. Build our items when asked for them; leave every other item to Finder.
    FUHook(cls, itemSel, ^NSToolbarItem *(id self, NSToolbar *toolbar, NSString *ident, id plist, BOOL insert) {
        const FUButton *b = FUFind(ident);
        if (b) return FUMakeItem(b);
        return ((NSToolbarItem *(*)(id, SEL, NSToolbar *, NSString *, id, BOOL))gOrigItem)
            (self, itemSel, toolbar, ident, plist, insert);
    }, &gOrigItem);

    NSLog(@"[FinderUp] installed");
}

__attribute__((constructor))
static void FUInit(void) {
    @autoreleasepool {
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.finder"])
            FUOnLaunch(FUInstall);
    }
}
