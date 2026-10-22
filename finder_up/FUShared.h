// FUShared.h — shared by FinderUp.m (Finder) and PanelNav.m (Open/Save panels):
// the three buttons. Runtime helpers come from shared/Tweak.h.
//
// Both dylibs link only Foundation: AppKit classes are looked up at runtime,
// since every target process already has AppKit loaded.

#import <AppKit/AppKit.h>
#import "../shared/Tweak.h"

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
