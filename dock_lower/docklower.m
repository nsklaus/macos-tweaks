// docklower - Ammonia tweak, active only inside the Dock (com.apple.dock)
// Receives a window number through a distributed notification and moves
// that window to the back of its level, like yabai's --lower.

#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef int     (*SLSMainConnectionID_t)(void);
typedef int32_t (*SLSOrderWindow_t)(int cid, uint32_t wid, int mode, uint32_t relativeWid);

static SLSMainConnectionID_t pMainConnectionID;
static SLSOrderWindow_t      pOrderWindow;

@interface DLObserver : NSObject
@end

@implementation DLObserver
- (void)lower:(NSNotification *)note {
    uint32_t wid = (uint32_t)[(NSString *)note.object longLongValue];
    if (wid == 0) return;
    // mode -1 = below; relative window 0 = below everything in its level
    int32_t err = pOrderWindow(pMainConnectionID(), wid, -1, 0);
    if (err) NSLog(@"docklower: SLSOrderWindow(%u) error %d", wid, err);
}
@end

__attribute__((constructor))
static void docklower_init(void) {
    // do nothing outside the Dock
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.dock"]) return;

    pMainConnectionID = (SLSMainConnectionID_t)dlsym(RTLD_DEFAULT, "SLSMainConnectionID");
    pOrderWindow      = (SLSOrderWindow_t)dlsym(RTLD_DEFAULT, "SLSOrderWindow");
    if (!pMainConnectionID || !pOrderWindow) {
        NSLog(@"docklower: SkyLight functions not found");
        return;
    }
    static DLObserver *observer;
    observer = [DLObserver new];
    // DeliverImmediately: the Dock is never the active app, without it
    // notifications would stay queued
    [[NSDistributedNotificationCenter defaultCenter]
        addObserver:observer
           selector:@selector(lower:)
               name:@"org.nsklaus.docklower"
             object:nil
 suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    NSLog(@"docklower: loaded");
}