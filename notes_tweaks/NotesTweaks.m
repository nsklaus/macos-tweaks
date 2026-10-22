// NotesTweaks — Ammonia tweak for Notes (macOS 27).
//
// 1. Black body text: the note editor uses the system text color (opaque black in Light mode,
//    opaque white in Dark mode), like TextEdit and every plain NSTextView, instead of Notes'
//    own grey (default_body_text_color: #454545 in Light, #DCDCDC in Dark).
// 2. Bordered Markup button: the toolbar's Markup button gets a button frame like the others,
//    in the main window and in note windows, instead of a bare symbol.
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
//   toolbar items: built by -toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:, which
//     ICMMainWindowController (main window) and ICMSingleNoteWindowController (note windows)
//     each implement; both return a new ICMMarkupToolbarItem for "MarkupToolbarItem"
//   ICMMarkupToolbarItem derives straight from NSToolbarItem and keeps its default
//     bordered = NO; every other button (ICMToolbarItem, NSMenuToolbarItem) is bordered.
//     Setting bordered = YES live gave it the same frame as the others (with BackToCatalina)

static IMP gOrigDefaultFontColor = NULL;   // not called: the grey is never wanted
static IMP gOrigToolbarItem[2]   = { NULL, NULL };

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

static void NTInstallMarkupButton(void) {
    static BOOL done = NO;
    if (done) return;

    Class markup = NSClassFromString(@"ICMMarkupToolbarItem");
    NSArray *controllers = @[@"ICMMainWindowController", @"ICMSingleNoteWindowController"];
    SEL itemSel = @selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:);
    if (!markup || !NSClassFromString(controllers[0]) || !NSClassFromString(controllers[1])) {
        NSLog(@"[NotesTweaks] Notes toolbar classes not found, bordered Markup button not installed");
        return;
    }
    done = YES;

    for (NSUInteger i = 0; i < controllers.count; i++) {
        IMP *orig = &gOrigToolbarItem[i];
        if (!TWHook(NSClassFromString(controllers[i]), itemSel,
                    ^NSToolbarItem *(id self, NSToolbar *toolbar, NSString *ident, BOOL insert) {
            NSToolbarItem *item = ((NSToolbarItem *(*)(id, SEL, NSToolbar *, NSString *, BOOL))*orig)
                (self, itemSel, toolbar, ident, insert);
            if ([item isKindOfClass:markup]) item.bordered = YES;
            return item;
        }, orig))
            NSLog(@"[NotesTweaks] -[%@ %@] not found, skipped", controllers[i], NSStringFromSelector(itemSel));
    }

    NSLog(@"[NotesTweaks] bordered Markup button installed");
}

__attribute__((constructor))
static void NTInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Notes"]) return;
        TWOnLaunch(NTInstallTextColor);     // NotesUI's category may not be attached yet
        TWOnLaunch(NTInstallMarkupButton);  // before the first window and its toolbar are built
    }
}
