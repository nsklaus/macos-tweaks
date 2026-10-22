// NotesTweaks — Ammonia tweak for Notes (macOS 27).
//
// Body text in the note editor uses the system text color (opaque black in Light mode,
// opaque white in Dark mode), like TextEdit and every plain NSTextView, instead of Notes'
// own grey (default_body_text_color: #454545 in Light, #DCDCDC in Dark).
//
// Install: /var/ammonia/core/tweaks/libnotestweaks.dylib, whitelist "Notes.app/Contents/MacOS/Notes".

#import <AppKit/AppKit.h>  // types only: this dylib does not link AppKit
#import <objc/runtime.h>

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

static void NTInstall(void) {
    static BOOL done = NO;
    if (done) return;

    Class color = NSClassFromString(@"NSColor");
    Method m = color ? class_getClassMethod(color, NSSelectorFromString(@"preferredDefaultFontColor")) : NULL;
    if (!m) {
        NSLog(@"[NotesTweaks] +[NSColor preferredDefaultFontColor] not found, not installing");
        return;
    }
    done = YES;

    // Every call is answered by the hook: the original's cached grey is never handed out again.
    method_setImplementation(m, imp_implementationWithBlock(^NSColor *(id self) {
        return [color textColor];
    }));

    NSLog(@"[NotesTweaks] installed");
}

__attribute__((constructor))
static void NTInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Notes"]) return;
        NTInstall();
        // If NotesUI's category isn't attached yet, retry just before launch completes,
        // which is still before any note is styled.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"NSApplicationWillFinishLaunchingNotification"
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) { NTInstall(); }];
    }
}
