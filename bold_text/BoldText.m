// BoldText — Ammonia tweak: bold text everywhere, like iOS's Bold Text accessibility option.
// The system font is at least semibold in every app (AppKit and SwiftUI), the Dock, the menu
// bar (MenuBarAgent), Spotlight, System Settings and its panes, and Open/Save panels.
// Fonts an app picks by name (documents, Terminal's Menlo, symbol fonts) are left alone.
//
// Turn off: defaults write -g TweaksBoldText -bool NO   (YES, or unset: on), then relaunch apps.
//
// Install: /var/ammonia/core/tweaks/libboldtext.dylib, whitelist ".app/Contents/MacOS/" (every
// app, no daemon), "com.apple.appkit.xpc.openAndSavePanelService" (Open/Save panels of sandboxed
// apps), "/System/Library/ExtensionKit/Extensions/" (System Settings panes; the other
// extensions there are skipped by the constructor) and "DockHelper.xpc/Contents/MacOS/DockHelper"
// (the Dock's menus).

#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <dlfcn.h>
#include <ptrauth.h>
#include "../shared/dobby/dobby.h"

// Findings (macOS 27):
//   every system UI font is made by CoreText, whatever the framework; hooking there covers
//   AppKit, nib fonts, SwiftUI and the Dock at once. Traced with name breakpoints in a test
//   program (fonts are made once at launch and cached):
//     CTFontDescriptorCreateForUIType(uiType, size, language): AppKit's size-only fonts
//       (+systemFontOfSize:, menu, label... via __NSGetMetaFontInstanceWithType), fonts
//       archived in nibs (-[NSFont initWithCoder:]), the Dock (directly and through
//       CTFontCreateUIFontForLanguage). Regular types have NSCTFontUIUsageAttribute =
//       CTFontRegularUsage and the name .AppleSystemUIFont; emphasized ones CTFontEmphasizedUsage
//       or CTFontBoldUsage; types 0, 1, 14 are Helvetica, Menlo, .Keyboard (no usage)
//     CTFontDescriptorCopyNameForSystemFontOfWeight(1, weight): +systemFontOfSize:weight:
//       (through __NSGetSystemFontVariants); 0.3 gives .AppleSystemUIFontDemi
//     CTFontCreateWithFontDescriptor(descriptor, size, matrix): every font. Text styles carry
//       NSCTFontUIUsageAttribute = UICTFontTextStyle*; SwiftUI's .system(size:) and default
//       fonts carry NSCTFontTraitsAttribute = {NSCTFontUIFontDesignTrait, NSCTFontWeightTrait}
//   rule: hand back the same kind of font the system would have (see CLAUDE.md):
//     - AppKit makes its semibold system font from {usage CTFontDemiUsage, name
//       .AppleSystemUIFontDemi}: +fontWithName: finds it. A semibold derived from the regular
//       descriptor is .SFNS-Semibold, which it doesn't (apps rebuild fonts by name: iTerm2
//       does +fontWithName:font.fontName size: for its window subtitle)
//     - SwiftUI's .body.weight(.semibold) adds NSCTFontWeightTrait 0.3 to the text style
//       descriptor; stock text style fonts are .SFNS-* and not found by name either
//   semibold and bold fonts have the bold symbolic trait, regular ones don't
//   panes of System Settings are /System/Library/ExtensionKit/Extensions/*.appex, one process
//     each, with EXAppExtensionAttributes.EXExtensionPointIdentifier =
//     com.apple.Settings.extension.ui (most other extensions there have no UI)
//   the Dock doesn't link AppKit (SwiftUICore, QuartzCore, CoreText): no NSApplication check
//   a Dock icon's right-click menu is drawn by DockHelper (an AppKit XPC service inside
//     Dock.app, menu window layer 101), not by the Dock; tooltips are drawn by the Dock
//   Spotlight (⌘Space) is drawn by /System/Applications/Siri AI.app (com.apple.campo)
//   BackToCatalina keeps the Finder sidebar regular (hooks _NSConvertFontToWeightIfNeeded)
//   C functions are hooked with Dobby (shared/dobby, as BackToCatalina): ObjC swizzling can't

static const CGFloat kBTMinWeight = 0.3;   // NSFontWeightSemibold
static NSString *const kBTUsage = @"NSCTFontUIUsageAttribute";

static CTFontDescriptorRef (*gOrigForUIType)(uint32_t, CGFloat, CFStringRef);
static CFStringRef (*gOrigNameForWeight)(int, CGFloat);
static CTFontRef (*gOrigCreate)(CTFontDescriptorRef, CGFloat, const CGAffineTransform *);

// AppKit, nib and Dock fonts: regular usage becomes demi usage, named as AppKit names it.
static CTFontDescriptorRef BTForUIType(uint32_t type, CGFloat size, CFStringRef language) {
    CTFontDescriptorRef d = gOrigForUIType(type, size, language);
    if (!d) return d;
    NSString *usage = CFBridgingRelease(CTFontDescriptorCopyAttribute(d, (__bridge CFStringRef)kBTUsage));
    if (![usage isEqual:@"CTFontRegularUsage"]) return d;
    NSString *name = CFBridgingRelease(gOrigNameForWeight(1, kBTMinWeight));
    if (!name) return d;
    NSMutableDictionary *attributes = [CFBridgingRelease(CTFontDescriptorCopyAttributes(d)) mutableCopy];
    attributes[kBTUsage] = @"CTFontDemiUsage";
    attributes[(id)kCTFontNameAttribute] = name;
    CTFontDescriptorRef semibold = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
    if (!semibold) return d;
    CFRelease(d);
    return semibold;
}

// +[NSFont systemFontOfSize:weight:]: at least semibold.
static CFStringRef BTNameForWeight(int kind, CGFloat weight) {
    return gOrigNameForWeight(kind, MAX(weight, kBTMinWeight));
}

// Text styles and SwiftUI system fonts that came out regular: add the semibold weight trait,
// as SwiftUI does for .weight(.semibold). Every other font passes through.
static CTFontRef BTCreate(CTFontDescriptorRef d, CGFloat size, const CGAffineTransform *matrix) {
    CTFontRef font = gOrigCreate(d, size, matrix);
    if (!d || !font || (CTFontGetSymbolicTraits(font) & kCTFontTraitBold)) return font;
    NSString *usage = CFBridgingRelease(CTFontDescriptorCopyAttribute(d, (__bridge CFStringRef)kBTUsage));
    NSDictionary *traits = CFBridgingRelease(CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute));
    BOOL textStyle = [usage isKindOfClass:NSString.class] && [usage hasPrefix:@"UICTFontTextStyle"];
    BOOL systemDesign = [traits isKindOfClass:NSDictionary.class] && traits[@"NSCTFontUIFontDesignTrait"];
    if (!textStyle && !systemDesign) return font;
    NSMutableDictionary *semiboldTraits = [traits isKindOfClass:NSDictionary.class] ? [traits mutableCopy] : [NSMutableDictionary new];
    semiboldTraits[(id)kCTFontWeightTrait] = @(kBTMinWeight);
    CTFontDescriptorRef semibold = CTFontDescriptorCreateCopyWithAttributes(d,
        (__bridge CFDictionaryRef)@{(id)kCTFontTraitsAttribute: semiboldTraits});
    CTFontRef bolder = semibold ? gOrigCreate(semibold, size, matrix) : NULL;
    if (semibold) CFRelease(semibold);
    if (!bolder) return font;
    CFRelease(font);
    return bolder;
}

static BOOL BTHook(const char *symbol, void *replacement, void **orig) {
    void *address = dlsym(RTLD_DEFAULT, symbol);
    if (address) address = ptrauth_strip(address, ptrauth_key_function_pointer);
    if (address && DobbyHook(address, replacement, orig) == 0) return YES;
    NSLog(@"[BoldText] could not hook %s", symbol);
    return NO;
}

__attribute__((constructor))
static void BTInit(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        // Every app (AppKit or not: the Dock is SwiftUI and CoreText), but of the extensions
        // only System Settings panes.
        if ([bundle.bundlePath.pathExtension isEqual:@"appex"]) {
            NSString *point = bundle.infoDictionary[@"EXAppExtensionAttributes"][@"EXExtensionPointIdentifier"];
            if (![point isEqual:@"com.apple.Settings.extension.ui"]) return;
        }
        id setting = [NSUserDefaults.standardUserDefaults objectForKey:@"TweaksBoldText"];
        if (setting && ![setting boolValue]) return;   // turned off

        // BTForUIType calls the original name lookup: hook it first, and stop if it fails.
        if (!BTHook("CTFontDescriptorCopyNameForSystemFontOfWeight", (void *)BTNameForWeight, (void **)&gOrigNameForWeight))
            return;
        BTHook("CTFontDescriptorCreateForUIType", (void *)BTForUIType, (void **)&gOrigForUIType);
        BTHook("CTFontCreateWithFontDescriptor", (void *)BTCreate, (void **)&gOrigCreate);
        NSLog(@"[BoldText] installed in %@", bundle.bundleIdentifier);
    }
}
