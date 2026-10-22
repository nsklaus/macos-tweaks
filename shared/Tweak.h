// Tweak.h — runtime helpers shared by every tweak that hooks methods.
// Header only: each dylib gets its own copy, so any tweak can be installed on its own.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Replace a method's implementation with a block, keeping the original in *orig.
// For a class method, pass the metaclass: object_getClass(cls).
// Returns NO, and changes nothing, if the method doesn't exist.
static inline BOOL TWHook(Class cls, SEL sel, id block, IMP *orig) {
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!m) return NO;
    *orig = method_getImplementation(m);
    IMP imp = imp_implementationWithBlock(block);
    // Add on the class itself if the method is inherited; otherwise replace it.
    if (!class_addMethod(cls, sel, imp, method_getTypeEncoding(m)))
        method_setImplementation(m, imp);
    return YES;
}

// Install now; if the classes aren't registered yet, retry just before launch completes,
// which is still before any window is built.
static inline void TWOnLaunch(void (*install)(void)) {
    install();
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"NSApplicationWillFinishLaunchingNotification"
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) { install(); }];
}
