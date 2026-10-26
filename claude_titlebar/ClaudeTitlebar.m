// ClaudeTitlebar — Ammonia tweak for Claude desktop (Electron, macOS 27).
//
// Gives Claude's windows a real title bar: grey (BackToCatalina's look), with the title and the
// window buttons in it, and the app's content starting below it, instead of Electron's
// "hidden" title bar style where the web content runs under a transparent title bar.
//
// Turn off: defaults write -g TweaksClaudeTitlebar -bool NO   (YES, or unset: on), then relaunch Claude.
//
// Install: /var/ammonia/core/tweaks/libclaudetitlebar.dylib, whitelist
// "Claude.app/Contents/MacOS/Claude" (the main process only: the Helpers live in
// Contents/Frameworks/Claude Helper*.app, and Claude Code's own "claude.app/Contents/MacOS/claude"
// differs in case, which Ammonia's strstr match respects).

#import <AppKit/AppKit.h>  // types only: this dylib does not link AppKit
#import "../shared/Tweak.h"
#include <ptrauth.h>

// Findings with lldb on Claude 1.x (Electron, app.asar sets titleBarStyle "hidden"/"hiddenInset"):
//   main window: ElectronNSWindow <- NativeWidgetMacNSWindow (Chromium) <- NSWindow,
//     content view BridgedContentView, delegate ElectronNSWindowDelegate, no toolbar
//   styleMask 15 (titled, closable, miniaturizable, resizable): NO FullSizeContentView, unlike
//     Calendar/Freeform which BackToCatalina fixes by dropping that bit
//   titlebarAppearsTransparent YES, titleVisibility NSWindowTitleHidden
//   the content view still fills the whole frame (949x1034 for a 1034-high window): Claude's windows
//     are frameless for Electron. -[ElectronNSWindow contentRectForFrameRect:] disassembled:
//       shell = self->shell_ (ivar, offset 624); if (!shell || !shell->has_frame_) return frameRect;
//       return [super contentRectForFrameRect:frameRect];
//     with has_frame_ the byte read by `ldrb w8, [x8, #0x225]` (Electron of Claude 1.x)
//   Electron answers the app's JS from that same model, so restyling only AppKit (as BackToCatalina
//     does for Calendar) left the app laying out for a frameless window: its main
//     WebContentsViewCocoa got the whole window height and lost 22 pt at the bottom
//   and the title bar container grew to 46 pt over the app's toolbar: for a frameless window,
//     Electron places the buttons at Claude's trafficLightPosition (15 pt down: 16 + 2 x 15)
// So the tweak only tells Electron the window has a frame (has_frame_ = 1) as soon as
// ElectronNSWindow is made. Electron then does the rest itself (checked with lldb): opaque title
// bar, visible title, buttons at AppKit's place in a 22 pt title bar, and the app's views sized to
// the content area below it. The offset of has_frame_ is read from the instructions of
// -contentRectForFrameRect: at start, not hard-coded: no match, no install.

static IMP gOrigInitWithShell;
static long gHasFrameOffset = -1;

// A window we restyle: a titled window that does not ask for full-size content on its own.
static BOOL CTWantsTitlebar(NSWindow *window) {
    NSWindowStyleMask mask = window.styleMask;
    return (mask & NSWindowStyleMaskTitled) && !(mask & NSWindowStyleMaskFullSizeContentView);
}

// The offset of NativeWindow::has_frame_: in the first instructions of Electron's
// -contentRectForFrameRect:, the `ldrb w8, [x8, #imm]` that a `cbz w8` follows. -1 if not found.
static long CTFindHasFrameOffset(Class cls) {
    Method m = class_getInstanceMethod(cls, @selector(contentRectForFrameRect:));
    if (!m) return -1;
    const uint32_t *code = ptrauth_strip((const uint32_t *)method_getImplementation(m), ptrauth_key_function_pointer);
    for (int i = 0; i < 8; i++) {
        uint32_t insn = code[i];
        BOOL isLdrbW8 = (insn & 0xFFC0001F) == 0x39400008;   // LDRB (unsigned offset) into w8
        BOOL nextIsCbzW8 = (code[i + 1] & 0xFF00001F) == 0x34000008;
        if (isLdrbW8 && nextIsCbzW8) return (insn >> 10) & 0xFFF;
    }
    return -1;
}

static void CTInstall(void) {
    static BOOL done;
    Class cls = NSClassFromString(@"ElectronNSWindow");
    if (done || !cls) return;
    done = YES;

    gHasFrameOffset = CTFindHasFrameOffset(cls);
    if (gHasFrameOffset < 0) {
        NSLog(@"[ClaudeTitlebar] has_frame_ not found in -[ElectronNSWindow contentRectForFrameRect:], not installing");
        return;
    }

    // Electron's window model: framed, so it gives the app AppKit's content rect below the title bar.
    SEL initSel = NSSelectorFromString(@"initWithShell:styleMask:");
    if (!TWHook(cls, initSel, ^id(NSWindow *self, uint8_t *shell, NSUInteger mask) {
        NSWindow *window = ((id (*)(id, SEL, void *, NSUInteger))gOrigInitWithShell)(self, initSel, shell, mask);
        if (window && shell && CTWantsTitlebar(window)) shell[gHasFrameOffset] = 1;
        return window;
    }, &gOrigInitWithShell)) {
        NSLog(@"[ClaudeTitlebar] -[ElectronNSWindow initWithShell:styleMask:] not found, not installing");
        return;
    }

    NSLog(@"[ClaudeTitlebar] installed");
}

__attribute__((constructor))
static void CTInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.anthropic.claudefordesktop"]) return;
        id setting = [NSUserDefaults.standardUserDefaults objectForKey:@"TweaksClaudeTitlebar"];
        if (setting && ![setting boolValue]) return;   // turned off
        TWOnLaunch(CTInstall);   // Electron's classes may only be registered once its framework is up
    }
}
