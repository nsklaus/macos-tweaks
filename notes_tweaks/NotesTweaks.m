// NotesTweaks — Ammonia tweak for Notes (macOS 27).
//
// 1. Black body text: the note editor uses the system text color (opaque black in Light mode,
//    opaque white in Dark mode), like TextEdit and every plain NSTextView, instead of Notes'
//    own grey (default_body_text_color: #454545 in Light, #DCDCDC in Dark).
// 2. Bordered Markup button: the toolbar's Markup button gets a button frame like the others,
//    in the main window and in note windows, instead of a bare symbol.
// 3. Always Bold: a toolbar button, offered in Customize Toolbar. While it is on, everything
//    typed is bold, in every note and window, until it is turned off. The bold is real text
//    formatting, saved in the note. The setting is kept across launches.
//
// Install: /var/ammonia/core/tweaks/libnotestweaks.dylib, whitelist "Notes.app/Contents/MacOS/Notes".

#import <AppKit/AppKit.h>  // types only: this dylib does not link AppKit
#import "../shared/Tweak.h"

// Findings from lldb (macOS 27, Notes):
//   editor view   : ICTK2MacTextView -> ICMacTextView -> ICMacBaseTextView -> NSTextView (TextKit 2)
//   default color : +[NSColor(IC) preferredDefaultFontColor] (NotesUI) loads the asset
//     default_body_text_color once and returns it; the editor's textColor and typingAttributes
//     hold that very object
//   callers (traced while switching notes): -[ICTTTextController styleForModelAttributes:...]
//     (editor styling and typing attributes) and -[ICAuthorHighlightsController ...] (author
//     highlights in shared notes) only; the note list uses labelColor / secondaryLabelColor
//   the note model (ICTTMergeableAttributedString) stores no color, only TTStyle, for existing
//     and newly typed text: the color is applied on screen only, nothing reaches iCloud
//   toolbar items: built by -toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:, and
//     offered by -toolbarAllowedItemIdentifiers:, which ICMMainWindowController (main window)
//     and ICMSingleNoteWindowController (note windows) each implement
//   ICMMarkupToolbarItem derives straight from NSToolbarItem and keeps its default
//     bordered = NO; every other button (ICMToolbarItem, NSMenuToolbarItem) is bordered.
//     Setting bordered = YES live gave it the same frame as the others (with BackToCatalina)
//   Notes' own buttons: NSToolbarButton (an NSButton), bezel style 11, 40 x 25 points
//   bold in the model: TTHints, a bit mask (1 = bold, 2 = italic). Adding only TTHints = 1 to
//     the editor's typing attributes is enough: typed text is saved with TTHints = 1 and
//     drawn with the bold system font (.AppleSystemUIFontEmphasized)
//   every typing attributes change (Return, caret moves, empty note) ends in
//     -[ICMacBaseTextView setTypingAttributes:]

static NSString *const kNTAlwaysBoldKey  = @"NotesTweaksAlwaysBold";          // NSUserDefaults
static NSString *const kNTAlwaysBoldItem = @"com.nsklaus.notestweaks.ALWAYSBOLD";
static const NSUInteger kNTBoldHint = 1;   // TTHints bit for bold

static BOOL gAlwaysBold = NO;

static IMP gOrigDefaultFontColor  = NULL;   // not called: the grey is never wanted
static IMP gOrigSetTypingAttributes = NULL;
static IMP gOrigToolbarItem[2]    = { NULL, NULL };
static IMP gOrigAllowedItems[2]   = { NULL, NULL };

static void NTInstallTextColor(void) {
    static BOOL done = NO;
    if (done) return;

    Class color = NSClassFromString(@"NSColor");
    // A class method: hook it on the metaclass.
    if (!TWHook(object_getClass(color), NSSelectorFromString(@"preferredDefaultFontColor"), ^NSColor *(id self) {
        return [color textColor];
    }, &gOrigDefaultFontColor)) {
        NSLog(@"[NotesTweaks] +[NSColor preferredDefaultFontColor] not found, black text not installed");
        return;
    }
    done = YES;

    NSLog(@"[NotesTweaks] black text installed");
}

// Typing attributes with the bold hint set or cleared, the other hints (italic...) kept.
static NSDictionary *NTWithBold(NSDictionary *attrs, BOOL bold) {
    NSUInteger hints = [attrs[@"TTHints"] unsignedIntegerValue];
    NSMutableDictionary *m = [attrs mutableCopy];
    m[@"TTHints"] = @(bold ? (hints | kNTBoldHint) : (hints & ~kNTBoldHint));
    return m;
}

static void NTInstallAlwaysBold(void) {
    static BOOL done = NO;
    if (done) return;

    SEL sel = @selector(setTypingAttributes:);
    if (!TWHook(NSClassFromString(@"ICMacBaseTextView"), sel, ^(NSTextView *self, NSDictionary *attrs) {
        if (gAlwaysBold && attrs) attrs = NTWithBold(attrs, YES);
        ((void (*)(id, SEL, NSDictionary *))gOrigSetTypingAttributes)(self, sel, attrs);
    }, &gOrigSetTypingAttributes)) {
        NSLog(@"[NotesTweaks] -[ICMacBaseTextView setTypingAttributes:] not found, Always Bold not installed");
        return;
    }
    done = YES;
    gAlwaysBold = [NSUserDefaults.standardUserDefaults boolForKey:kNTAlwaysBoldKey];

    NSLog(@"[NotesTweaks] Always Bold installed");
}

// Turn Always Bold on or off: save it, update the button in every window, and apply it at
// once where the caret is (off: back to Notes' own behaviour from the next caret move).
static void NTSetAlwaysBold(BOOL on) {
    gAlwaysBold = on;
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kNTAlwaysBoldKey];

    Class textView = NSClassFromString(@"ICMacBaseTextView");
    for (NSWindow *window in [[NSClassFromString(@"NSApplication") sharedApplication] windows]) {
        for (NSToolbarItem *item in window.toolbar.items)
            if ([item.itemIdentifier isEqualToString:kNTAlwaysBoldItem])
                ((NSButton *)item.view).state = on;
        NSTextView *editor = (NSTextView *)window.firstResponder;
        if ([editor isKindOfClass:textView])
            editor.typingAttributes = NTWithBold(editor.typingAttributes, on);
    }
}

// The button's target: a one-method class, created at runtime since this dylib does not link
// AppKit. The button switches its own state before sending the action.
static id NTAlwaysBoldTarget(void) {
    static id target = nil;
    if (target) return target;
    Class cls = objc_allocateClassPair([NSObject class], "NTAlwaysBoldTarget", 0);
    class_addMethod(cls, @selector(toggle:), imp_implementationWithBlock(^(id self, NSButton *sender) {
        NTSetAlwaysBold(sender.state == NSControlStateValueOn);
    }), "v@:@");
    objc_registerClassPair(cls);
    target = [cls new];
    return target;
}

// Built like Notes' own buttons (NSButton, bezel style 11, 40 x 25 points), as a two-state
// button showing whether Always Bold is on.
static NSToolbarItem *NTMakeAlwaysBoldItem(void) {
    NSImage *img = [NSClassFromString(@"NSImage") imageWithSystemSymbolName:@"bold"
                                                   accessibilityDescription:@"Always Bold"];
    img.template = YES;

    NSButton *button = [NSClassFromString(@"NSButton") buttonWithImage:img
                                                                target:NTAlwaysBoldTarget()
                                                                action:@selector(toggle:)];
    button.buttonType = NSButtonTypePushOnPushOff;
    button.bezelStyle = 11;   // NSBezelStyleTexturedRounded
    button.frame = NSMakeRect(0, 0, 40, 25);
    button.state = gAlwaysBold;

    NSToolbarItem *item = [[NSClassFromString(@"NSToolbarItem") alloc] initWithItemIdentifier:kNTAlwaysBoldItem];
    item.label        = @"Bold";
    item.paletteLabel = @"Always Bold";
    item.toolTip      = @"Type everything in bold";
    item.view         = button;
    return item;
}

static void NTInstallToolbar(void) {
    static BOOL done = NO;
    if (done) return;

    Class markup = NSClassFromString(@"ICMMarkupToolbarItem");
    NSArray *controllers = @[@"ICMMainWindowController", @"ICMSingleNoteWindowController"];
    SEL itemSel    = @selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:);
    SEL allowedSel = @selector(toolbarAllowedItemIdentifiers:);
    if (!markup || !NSClassFromString(controllers[0]) || !NSClassFromString(controllers[1])) {
        NSLog(@"[NotesTweaks] Notes toolbar classes not found, toolbar changes not installed");
        return;
    }
    done = YES;
    BOOL offerAlwaysBold = (gOrigSetTypingAttributes != NULL);   // the button needs the typing hook

    for (NSUInteger i = 0; i < controllers.count; i++) {
        Class cls = NSClassFromString(controllers[i]);

        // Build the Always Bold button; give Notes' Markup button its frame.
        IMP *origItem = &gOrigToolbarItem[i];
        if (!TWHook(cls, itemSel, ^NSToolbarItem *(id self, NSToolbar *toolbar, NSString *ident, BOOL insert) {
            if (offerAlwaysBold && [ident isEqualToString:kNTAlwaysBoldItem]) return NTMakeAlwaysBoldItem();
            NSToolbarItem *item = ((NSToolbarItem *(*)(id, SEL, NSToolbar *, NSString *, BOOL))*origItem)
                (self, itemSel, toolbar, ident, insert);
            if ([item isKindOfClass:markup]) item.bordered = YES;
            return item;
        }, origItem))
            NSLog(@"[NotesTweaks] -[%@ %@] not found, skipped", controllers[i], NSStringFromSelector(itemSel));

        // Offer the Always Bold button in Customize Toolbar.
        IMP *origAllowed = &gOrigAllowedItems[i];
        if (offerAlwaysBold && !TWHook(cls, allowedSel, ^NSArray *(id self, NSToolbar *toolbar) {
            NSArray *ids = ((NSArray *(*)(id, SEL, NSToolbar *))*origAllowed)(self, allowedSel, toolbar);
            if (ids == nil || [ids containsObject:kNTAlwaysBoldItem]) return ids;
            return [ids arrayByAddingObject:kNTAlwaysBoldItem];
        }, origAllowed))
            NSLog(@"[NotesTweaks] -[%@ %@] not found, skipped", controllers[i], NSStringFromSelector(allowedSel));
    }

    NSLog(@"[NotesTweaks] toolbar installed");
}

__attribute__((constructor))
static void NTInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Notes"]) return;
        TWOnLaunch(NTInstallTextColor);    // NotesUI's category may not be attached yet
        TWOnLaunch(NTInstallAlwaysBold);
        TWOnLaunch(NTInstallToolbar);      // after Always Bold, before the first window is built
    }
}
