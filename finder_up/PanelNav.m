// PanelNav — Ammonia tweak: separate Back, Forward and Up (Enclosing Folder) buttons
// in the Open/Save panels, replacing the Back/Forward segmented control.
//
// Covers sandboxed apps, whose panels run in the shared system service
// com.apple.appkit.xpc.openAndSavePanelService.
// Install: /var/ammonia/core/tweaks/libpanelnav.dylib,
//          whitelist "com.apple.appkit.xpc.openAndSavePanelService".

#import "FUShared.h"

// Findings from lldb (macOS 27, openAndSavePanelService, panel NSOpenPanelServicePanel):
//   no NSToolbar: the top bar is an NSStackView (Auto Layout) holding
//     FI_TSegmentedControl (Back/Forward), FIViewOptionsPopUp, FIArrangeByPopUp
//   FI_TSegmentedControl: segmentStyle 1 (Rounded), controlSize 0 (Regular),
//     action cmdBackForward:, target FIFinderViewOpenPanelGutsController
//   the controller also answers cmdBack:, cmdForward:, cmdOpenParent:
//   but cmdOpenParent: is only forwarded and does nothing; the real "up" is
//   -_goUpToParentFolder in FIFinderViewGutsController, the common parent class of
//   the Open and Save panel controllers (tested live in lldb: goes up one level)
//   it greys each arrow with -setEnabled:forSegment:; no validateUserInterfaceItem:

static const void *kFUPanelKey = &kFUPanelKey;   // our three controls, attached to the original
static IMP gOrigMoveToWindow = NULL;
static IMP gOrigSetEnabled   = NULL;

// The action a button sends to the panel's controller. Same as the Go menu's
// for Back and Forward; for Up, the panel's own method (see the findings above),
// with the Go menu action as a fallback if a future macOS drops it.
static SEL FUPanelAction(NSSegmentedControl *model, const FUButton *b) {
    SEL up = NSSelectorFromString(@"_goUpToParentFolder");
    if ([b->action isEqualToString:@"cmdOpenParent:"] && [model.target respondsToSelector:up])
        return up;
    return NSSelectorFromString(b->action);
}

// One button = a one-segment control with the original's style and size,
// so it draws exactly like the original arrows.
static NSSegmentedControl *FUMakeSegment(NSSegmentedControl *model, const FUButton *b) {
    NSImage *img = [NSClassFromString(@"NSImage") imageWithSystemSymbolName:b->symbol
                                                   accessibilityDescription:b->paletteLabel];
    img.template = YES;
    NSSegmentedControl *seg = [NSClassFromString(@"NSSegmentedControl")
        segmentedControlWithImages:@[img]
                      trackingMode:NSSegmentSwitchTrackingMomentary   // a click, not a toggle
                            target:model.target                      // the panel's controller
                            action:FUPanelAction(model, b)];
    seg.segmentStyle = model.segmentStyle;
    seg.controlSize  = model.controlSize;
    seg.toolTip      = b->paletteLabel;
    CGFloat w = [model widthForSegment:0];
    if (w > 0) [seg setWidth:w forSegment:0];
    seg.translatesAutoresizingMaskIntoConstraints = NO;
    return seg;
}

// Mirror the panel's own greying of the arrows onto our Back and Forward.
// Up stays enabled: the controller offers no way to ask; at the root it does nothing.
static void FUPanelSync(NSSegmentedControl *orig) {
    NSArray *mine = objc_getAssociatedObject(orig, kFUPanelKey);
    if (mine.count < 2) return;
    ((NSControl *)mine[0]).enabled = [orig isEnabledForSegment:0];
    ((NSControl *)mine[1]).enabled = [orig isEnabledForSegment:1];
}

static void FUPanelSetup(NSSegmentedControl *orig) {
    if (orig.window == nil || objc_getAssociatedObject(orig, kFUPanelKey)) return;
    NSStackView *stack = (NSStackView *)orig.superview;
    if (![stack isKindOfClass:NSClassFromString(@"NSStackView")] || orig.segmentCount != 2) return;
    NSUInteger idx = [stack.arrangedSubviews indexOfObject:orig];
    if (idx == NSNotFound) return;

    NSArray *mine = @[ FUMakeSegment(orig, &kFUButtons[0]),
                       FUMakeSegment(orig, &kFUButtons[1]),
                       FUMakeSegment(orig, &kFUButtons[2]) ];
    objc_setAssociatedObject(orig, kFUPanelKey, mine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    for (NSUInteger i = 0; i < mine.count; i++)
        [stack insertArrangedSubview:mine[i] atIndex:idx + 1 + i];
    orig.hidden = YES;   // NSStackView drops hidden views from the layout
    FUPanelSync(orig);

    // The "view mode" and "group" pop-ups use the textured toolbar bezel (style 11):
    // BackToCatalina draws it with a grey gradient and lighter borders, 1 point taller
    // than the arrows (measured on a screenshot). The folder pop-up uses the rounded
    // bezel (style 1), drawn exactly like the arrows: white, same borders, same shadow.
    // Give the two pop-ups that bezel too.
    for (NSView *v in stack.arrangedSubviews)
        if ([v.className isEqualToString:@"FIViewOptionsPopUp"] ||
            [v.className isEqualToString:@"FIArrangeByPopUp"])
            ((NSButton *)v).bezelStyle = 1;   // NSBezelStyleRounded
}

// The "view mode" and "group" pop-ups (FIViewOptionsPopUp, FIArrangeByPopUp)
// declare 4 points of bezel overhang below their alignment rect (macOS 27 metrics),
// and BackToCatalina draws the Catalina bezel over the whole frame: they end up
// 2 points taller than the arrows and hanging lower. Measured in lldb:
//   segments  frame 282 -> 306, alignment 284 -> 305 (overhang: bottom 2, top 1)
//   pop-ups   frame 280 -> 306, alignment 284 -> 305 (overhang: bottom 4, top 1)
// Fix: keep their side overhangs, take the top/bottom ones of a segmented control
// of the same size. Auto Layout then gives them the same frame height and position.
static IMP gOrigViewOptionsInsets = NULL;
static IMP gOrigArrangeByInsets   = NULL;
static IMP gOrigLocationInsets    = NULL;

static NSEdgeInsets FUSegmentInsets(NSControlSize size) {
    static NSEdgeInsets cache[4];
    static BOOL cached[4];
    if (size > 3) size = NSControlSizeRegular;
    if (!cached[size]) {
        NSSegmentedControl *seg = [[NSClassFromString(@"NSSegmentedControl") alloc] init];
        seg.segmentStyle = NSSegmentStyleRounded;   // same as the original arrows
        seg.controlSize  = size;
        seg.segmentCount = 1;
        cache[size]  = seg.alignmentRectInsets;
        cached[size] = YES;
    }
    return cache[size];
}

// shiftDown: points to move the frame down while keeping its height, for controls
// whose artwork sits higher in the frame than the arrows' artwork does.
static void FUHookInsets(NSString *className, IMP *orig, CGFloat shiftDown) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = @selector(alignmentRectInsets);
    TWHook(cls, sel, ^NSEdgeInsets(NSControl *self) {
        NSEdgeInsets in  = ((NSEdgeInsets (*)(id, SEL))*orig)(self, sel);
        NSEdgeInsets seg = FUSegmentInsets(self.controlSize);
        in.top    = seg.top    - shiftDown;
        in.bottom = seg.bottom + shiftDown;
        return in;
    }, orig);
}

static void FUPanelInstall(void) {
    static BOOL done = NO;
    if (done) return;
    Class cls = NSClassFromString(@"FI_TSegmentedControl");
    if (!cls) return;
    done = YES;

    SEL moveSel    = @selector(viewDidMoveToWindow);
    SEL enabledSel = @selector(setEnabled:forSegment:);

    // When the arrows land in a panel window, swap in our three controls.
    TWHook(cls, moveSel, ^(NSSegmentedControl *self) {
        ((void (*)(id, SEL))gOrigMoveToWindow)(self, moveSel);
        FUPanelSetup(self);
    }, &gOrigMoveToWindow);

    // When the panel greys or enables an arrow, follow it.
    TWHook(cls, enabledSel, ^(NSSegmentedControl *self, BOOL enabled, NSInteger segment) {
        ((void (*)(id, SEL, BOOL, NSInteger))gOrigSetEnabled)(self, enabledSel, enabled, segment);
        FUPanelSync(self);
    }, &gOrigSetEnabled);

    // Same height and position as the arrows for the two pop-ups next to them.
    // Measured on a screenshot with the rounded bezel: in the same frame as the arrows,
    // these two pull-down menus are drawn 1 point higher (border rows 24 -> 44 against
    // 25 -> 45 for the arrows, the folder pop-up and the search field).
    FUHookInsets(@"FIViewOptionsPopUp", &gOrigViewOptionsInsets, 1);
    FUHookInsets(@"FIArrangeByPopUp",   &gOrigArrangeByInsets,   1);
    // The folder pop-up is drawn 1 point lower than the arrows (frame 303 -> 328
    // against 305 -> 329): same treatment.
    FUHookInsets(@"FILocationPopUp",    &gOrigLocationInsets,    0);

    NSLog(@"[PanelNav] installed");
}

__attribute__((constructor))
static void FUInit(void) {
    @autoreleasepool {
        if ([[[NSBundle mainBundle] bundleIdentifier]
                isEqualToString:@"com.apple.appkit.xpc.openAndSavePanelService"])
            TWOnLaunch(FUPanelInstall);
    }
}
