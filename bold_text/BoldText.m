// BoldText — Ammonia tweak: bold text everywhere, like iOS's Bold Text accessibility option.
// AppKit's system and text style fonts are at least semibold, in every app (windows, menus,
// labels, Finder's file names) and in MenuBarAgent (the menu bar titles of all apps).
//
// Turn off: defaults write -g TweaksBoldText -bool NO   (YES, or unset: on), then relaunch apps.
//
// Install: /var/ammonia/core/tweaks/libboldtext.dylib, whitelist ".app/Contents/MacOS/"
// (every app, no daemon or XPC service) and "com.apple.appkit.xpc.openAndSavePanelService"
// (the Open/Save panels of sandboxed apps).

#import <AppKit/AppKit.h>  // types only: this dylib does not link AppKit
#import "../shared/Tweak.h"

// Findings (macOS 27):
//   app UI text (windows, dropdown menus, labels) comes from NSFont's system font class
//     methods; AppKit caches the menu font at launch, so hooks must be in place before
//   text style fonts come from +preferredFontForTextStyle:options: and its private variants
//     +preferredFontForTextStyle:addingSymbolicTraits: and
//     +fontForTextStyle:contentSizeCategory:addingSymbolicTraits: (traits: uint32_t), or are
//     built from +[NSFontDescriptor preferredFontDescriptorForTextStyle:options:] then
//     +[NSFont fontWithDescriptor:size:]: Finder's file names (NSFontTextStyleCallout), made
//     once at launch. fontWithDescriptor:size: itself is left alone: it serves every font,
//     document fonts included
//   BackToCatalina blocks the semibold sidebar font (hooks _NSConvertFontToWeightIfNeeded
//     during NSTableCellView -_updateFont), so the Finder sidebar stays regular
//   fonts archived in nibs are rebuilt by -[NSFont initWithCoder:] (.AppleSystemUIFont,
//     CTFontRegularUsage), not by the class methods: nib buttons and labels stay regular
//     (Open/Save panel's Open, Cancel, Show Options). Left as is: an init hook in every app
//     is too risky for a few buttons
//   semibold and bold fonts have the bold symbolic trait (2), regular ones don't
//   rule: hand back the same kind of font the system would have. Apps rebuild fonts by name
//     (iTerm2's window subtitle: +fontWithName:font.fontName size:, which crashed on nil):
//     - the size-only fonts are named .AppleSystemUIFont* and +fontWithName: finds them; a
//       semibold made from their descriptor is .SFNS-Semibold, which it doesn't (nil). So
//       they are replaced by the original +systemFontOfSize:weight: (.AppleSystemUIFontDemi)
//     - text style fonts are .SFNS-* already without the tweak (+fontWithName: returns nil
//       for them too), so their semibold variant made from the descriptor is no worse
//   menu bar titles are drawn by MenuBarAgent (com.apple.MenuBarAgent), an AppKit app; the
//     menu bar window itself belongs to WindowServer
//   tested with a throwaway dylib in TextEdit and MenuBarAgent: windows, dropdown menus and
//     menu bar titles all turned semibold
//   AppKit constants, as their values since this dylib does not link AppKit:
//     NSFontTraitsAttribute = "NSCTFontTraitsAttribute", NSFontWeightTrait =
//     "NSCTFontWeightTrait", NSFontWeightSemibold = 0.3

static const CGFloat kBTMinWeight = 0.3;   // NSFontWeightSemibold

// Class methods taking only a size; boldSystemFontOfSize: is bold already.
static NSString *const kBTSizeSelectors[] = {
    @"systemFontOfSize:", @"menuFontOfSize:", @"menuBarFontOfSize:", @"labelFontOfSize:",
    @"messageFontOfSize:", @"controlContentFontOfSize:", @"toolTipsFontOfSize:",
    @"titleBarFontOfSize:", @"paletteFontOfSize:",
};
static const NSUInteger kBTSizeCount = sizeof(kBTSizeSelectors) / sizeof(kBTSizeSelectors[0]);

static IMP gOrigSize[sizeof(kBTSizeSelectors) / sizeof(kBTSizeSelectors[0])];
static IMP gOrigSizeWeight = NULL;
static IMP gOrigTextStyleOptions = NULL;
static IMP gOrigTextStyleTraits = NULL;
static IMP gOrigTextStyleCategory = NULL;
static IMP gOrigTextStyleDescriptor = NULL;

// Semibold or bolder already.
static BOOL BTIsBold(NSFont *font) {
    return (font.fontDescriptor.symbolicTraits & 2) != 0;   // NSFontDescriptorTraitBold
}

static NSFontDescriptor *BTSemibold(NSFontDescriptor *d) {
    return [d fontDescriptorByAddingAttributes:
        @{@"NSCTFontTraitsAttribute": @{@"NSCTFontWeightTrait": @(kBTMinWeight)}}];
}

// The system font at least semibold, as the system builds it (a name +fontWithName: finds).
static NSFont *BTBolderSystemFont(NSFont *font) {
    if (!font || BTIsBold(font) || !gOrigSizeWeight) return font;
    return ((NSFont *(*)(id, SEL, CGFloat, CGFloat))gOrigSizeWeight)
        (NSClassFromString(@"NSFont"), @selector(systemFontOfSize:weight:), font.pointSize, kBTMinWeight) ?: font;
}

// A text style font, at least semibold: left alone if already semibold or bolder, or if no
// such weight exists.
static NSFont *BTBolder(NSFont *font) {
    if (!font || BTIsBold(font)) return font;
    return [NSClassFromString(@"NSFont") fontWithDescriptor:BTSemibold(font.fontDescriptor)
                                                       size:font.pointSize] ?: font;
}

static void BTInstall(void) {
    Class meta = object_getClass(NSClassFromString(@"NSFont"));

    for (NSUInteger i = 0; i < kBTSizeCount; i++) {
        SEL sel = NSSelectorFromString(kBTSizeSelectors[i]);
        IMP *orig = &gOrigSize[i];
        if (!TWHook(meta, sel, ^NSFont *(id self, CGFloat size) {
            return BTBolderSystemFont(((NSFont *(*)(id, SEL, CGFloat))*orig)(self, sel, size));
        }, orig))
            NSLog(@"[BoldText] +[NSFont %@] not found, skipped", kBTSizeSelectors[i]);
    }

    SEL weightSel = @selector(systemFontOfSize:weight:);
    if (!TWHook(meta, weightSel, ^NSFont *(id self, CGFloat size, CGFloat weight) {
        return ((NSFont *(*)(id, SEL, CGFloat, CGFloat))gOrigSizeWeight)
            (self, weightSel, size, MAX(weight, kBTMinWeight));
    }, &gOrigSizeWeight))
        NSLog(@"[BoldText] +[NSFont systemFontOfSize:weight:] not found, skipped");

    // Text style fonts.
    SEL optionsSel = @selector(preferredFontForTextStyle:options:);
    if (!TWHook(meta, optionsSel, ^NSFont *(id self, NSString *style, NSDictionary *options) {
        return BTBolder(((NSFont *(*)(id, SEL, NSString *, NSDictionary *))gOrigTextStyleOptions)
            (self, optionsSel, style, options));
    }, &gOrigTextStyleOptions))
        NSLog(@"[BoldText] +[NSFont preferredFontForTextStyle:options:] not found, skipped");

    SEL traitsSel = NSSelectorFromString(@"preferredFontForTextStyle:addingSymbolicTraits:");
    if (!TWHook(meta, traitsSel, ^NSFont *(id self, NSString *style, uint32_t traits) {
        return BTBolder(((NSFont *(*)(id, SEL, NSString *, uint32_t))gOrigTextStyleTraits)
            (self, traitsSel, style, traits));
    }, &gOrigTextStyleTraits))
        NSLog(@"[BoldText] +[NSFont preferredFontForTextStyle:addingSymbolicTraits:] not found, skipped");

    SEL categorySel = NSSelectorFromString(@"fontForTextStyle:contentSizeCategory:addingSymbolicTraits:");
    if (!TWHook(meta, categorySel, ^NSFont *(id self, NSString *style, id category, uint32_t traits) {
        return BTBolder(((NSFont *(*)(id, SEL, NSString *, id, uint32_t))gOrigTextStyleCategory)
            (self, categorySel, style, category, traits));
    }, &gOrigTextStyleCategory))
        NSLog(@"[BoldText] +[NSFont fontForTextStyle:contentSizeCategory:addingSymbolicTraits:] not found, skipped");

    // Text style descriptors, for fonts made with fontWithDescriptor:size: (the Finder).
    SEL descriptorSel = @selector(preferredFontDescriptorForTextStyle:options:);
    if (!TWHook(object_getClass(NSClassFromString(@"NSFontDescriptor")), descriptorSel,
                ^NSFontDescriptor *(id self, NSString *style, NSDictionary *options) {
        NSFontDescriptor *d = ((NSFontDescriptor *(*)(id, SEL, NSString *, NSDictionary *))gOrigTextStyleDescriptor)
            (self, descriptorSel, style, options);
        if (!d || BTIsBold([NSClassFromString(@"NSFont") fontWithDescriptor:d size:0])) return d;
        return BTSemibold(d);
    }, &gOrigTextStyleDescriptor))
        NSLog(@"[BoldText] +[NSFontDescriptor preferredFontDescriptorForTextStyle:options:] not found, skipped");

    NSLog(@"[BoldText] installed in %@", NSBundle.mainBundle.bundleIdentifier);
}

__attribute__((constructor))
static void BTInit(void) {
    @autoreleasepool {
        if (!NSClassFromString(@"NSApplication") || !NSClassFromString(@"NSFont")) return;   // not an AppKit app
        id setting = [NSUserDefaults.standardUserDefaults objectForKey:@"TweaksBoldText"];
        if (setting && ![setting boolValue]) return;   // turned off
        BTInstall();   // now: AppKit caches some fonts (the menu font) at launch
    }
}
