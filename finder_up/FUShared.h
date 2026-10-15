// FUShared.h — shared by FinderUp.m (Finder) and PanelNav.m (Open/Save panels).
// The three buttons, and the runtime helpers both tweaks use.
//
// Both dylibs link only Foundation: AppKit classes are looked up at runtime,
// since every target process already has AppKit loaded.

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// One row per button: identifier, toolbar label, Customize Toolbar label, glyph, Go menu action.
// String literals live for the whole process, so unretained pointers are safe here.
typedef struct {
    __unsafe_unretained NSString *ident, *label, *paletteLabel, *symbol, *action;
} FUButton;

static const FUButton kFUButtons[] __attribute__((unused)) = {
    { @"com.nsklaus.finderup.BACK",    @"Back",    @"Back",             @"chevron.left",  @"cmdBack:"       },
    { @"com.nsklaus.finderup.FORWARD", @"Forward", @"Forward",          @"chevron.right", @"cmdForward:"    },
    { @"com.nsklaus.finderup.UP",      @"Up",      @"Enclosing Folder", @"chevron.up",    @"cmdOpenParent:" },
};
static const int kFUCount __attribute__((unused)) = sizeof(kFUButtons) / sizeof(kFUButtons[0]);

// Replace a method's implementation with a block, keeping the original in *orig.
static inline void FUHook(Class cls, SEL sel, id block, IMP *orig) {
    Method m = class_getInstanceMethod(cls, sel);
    *orig = method_getImplementation(m);
    IMP imp = imp_implementationWithBlock(block);
    // Add on the class itself if the method is inherited; otherwise replace it.
    if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(m)))
        method_setImplementation(m, imp);
}

// Install now; if the classes aren't registered yet, retry just before launch completes,
// which is still before any window is built.
static inline void FUOnLaunch(void (*install)(void)) {
    install();
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"NSApplicationWillFinishLaunchingNotification"
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) { install(); }];
}
