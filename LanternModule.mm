#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <notify.h>
#import <substrate.h>
#include <stdint.h>
#include <string.h>

@protocol CCUIContentModule <NSObject>
@required
- (UIViewController *)contentViewController;
@optional
- (UIViewController *)contentViewControllerForContext:(id)context;
@end

typedef uint32_t (*NotifyRegisterFn)(const char *, int *);
typedef uint32_t (*NotifySetFn)(int, uint64_t);
typedef uint32_t (*NotifyPostFn)(const char *);
static const char *kLanternStateNotification = "com.ochium.lantern.state";
static NotifySetFn gSetState;
static NotifyPostFn gPost;
static int gStateToken = -1;
static BOOL gWarm = NO; // UI intent, main-thread only; not physical power state.
static BOOL gActive = NO;
static BOOL gRefreshing = NO;
static IMP gAppleButton;
static IMP gAppleSlider;
static IMP gAppleUpdate;
static IMP gFallback[3];
static Class gLanternControllerClass;
static NSHashTable *gControls;
static NSTimer *gPendingTimer;
static dispatch_block_t gPendingAction;

static id LanternFlashlight(void)
{
    return ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"SBUIFlashlightController"),
        NSSelectorFromString(@"sharedInstance"));
}

static NSUInteger LanternLevel(void)
{
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(LanternFlashlight(), NSSelectorFromString(@"level"));
}

static BOOL LanternAvailable(void)
{
    return ((BOOL (*)(id, SEL))objc_msgSend)(LanternFlashlight(), NSSelectorFromString(@"isAvailable"));
}

static BOOL LanternPublish(BOOL warm)
{
    if (gSetState(gStateToken, warm ? 1 : 0) != 0) return NO;
    if (gPost(kLanternStateNotification) != 0) return NO;
    gWarm = warm;
    return YES; // Publication only: NOT consumer acknowledgement.
}

static BOOL LanternSelectMode(BOOL warm)
{
    return gWarm == warm || LanternPublish(warm);
}

static void LanternCancelPending(void)
{
    [gPendingTimer invalidate];
    gPendingTimer = nil;
    gPendingAction = nil;
}

static void LanternRefresh(void)
{
    if (gRefreshing) return;
    gRefreshing = YES;
    @try {
        for (id controller in [gControls allObjects])
            ((void (*)(id, SEL))objc_msgSend)(controller, NSSelectorFromString(@"_updateControls"));
    } @finally { gRefreshing = NO; }
}

static void LanternNativeOff(void)
{
    ((void (*)(id, SEL, id))objc_msgSend)(LanternFlashlight(),
        NSSelectorFromString(@"turnFlashlightOffForReason:"), @"Control Center");
}

static void LanternNativeIntensity(double intensity, NSUInteger powerChange)
{
    id flashlight = LanternFlashlight();
    float width = ((float (*)(id, SEL))objc_msgSend)(flashlight, NSSelectorFromString(@"width"));
    // Exact verified v44@0:8d16d24B32Q36; only the handoff uses nonanimation.
    ((void (*)(id, SEL, double, double, BOOL, NSUInteger))objc_msgSend)(flashlight,
        NSSelectorFromString(@"_setIntensity:width:animated:withPowerChange:"),
        intensity, (double)width, NO, powerChange);
}

static void LanternSchedule(dispatch_block_t action)
{
    LanternCancelPending();
    gPendingAction = [action copy];
    // Practical delivery window, not an ACK/deadline. No main-thread sleep.
    gPendingTimer = [NSTimer timerWithTimeInterval:0.05 repeats:NO block:^(NSTimer *timer) {
        if (timer != gPendingTimer) return;
        dispatch_block_t pending = gPendingAction;
        gPendingTimer = nil;
        gPendingAction = nil;
        if (gActive && LanternAvailable()) pending();
        if (LanternLevel() == 0) LanternSelectMode(NO);
        LanternRefresh();
    }];
    [[NSRunLoop mainRunLoop] addTimer:gPendingTimer forMode:NSRunLoopCommonModes];
}

static void LanternButtonForMode(BOOL warm)
{
    if (gPendingTimer) {
        if (gWarm == warm) {
            LanternCancelPending();
            LanternNativeOff();
            LanternSelectMode(NO);
        } else {
            dispatch_block_t pending = gPendingAction;
            if (LanternSelectMode(warm)) LanternSchedule(pending);
            else { LanternCancelPending(); LanternNativeOff(); }
        }
    } else if (LanternLevel() > 0 && gWarm == warm) {
        LanternNativeOff();
        LanternSelectMode(NO);
    } else if (LanternAvailable()) {
        id flashlight = LanternFlashlight();
        float intensity = ((float (*)(id, SEL))objc_msgSend)(flashlight, NSSelectorFromString(@"intensity"));
        if (intensity > 0) LanternNativeIntensity(0, 1);
        if (!LanternSelectMode(warm)) { LanternNativeOff(); return; }
        LanternSchedule(^{
            if (intensity > 0) LanternNativeIntensity((double)intensity, 0);
            else ((void (*)(id, SEL, id))objc_msgSend)(LanternFlashlight(),
                NSSelectorFromString(@"turnFlashlightOnForReason:"), @"Control Center");
        });
    }
    LanternRefresh();
}

static void LanternStockButton(id self, SEL cmd, id sender, id event)
{
    if (!gActive || ![NSThread isMainThread]) {
        ((void (*)(id, SEL, id, id))(gAppleButton ?: gFallback[0]))(self, cmd, sender, event);
        return;
    }
    LanternButtonForMode(NO);
}

static void LanternWarmButton(id self, SEL cmd, id sender, id event)
{
    if (gActive && [NSThread isMainThread]) LanternButtonForMode(YES);
}

static void LanternSliderForMode(id self, SEL cmd, id sender, BOOL warm)
{
    // Inspect only zero versus positive; Apple retains all step/level mapping.
    Method stepMethod = sender ? class_getInstanceMethod(object_getClass(sender), NSSelectorFromString(@"step")) : NULL;
    const char *stepTypes = stepMethod ? method_getTypeEncoding(stepMethod) : NULL;
    if (!stepTypes || (strcmp(stepTypes, "Q16@0:8") != 0 && strcmp(stepTypes, "q16@0:8") != 0)) {
        LanternCancelPending();
        LanternNativeOff();
        LanternSelectMode(NO);
        return;
    }
    NSUInteger step = ((NSUInteger (*)(id, SEL))objc_msgSend)(sender, NSSelectorFromString(@"step"));
    LanternCancelPending();
    if (step <= 1) {
        ((void (*)(id, SEL, id))gAppleSlider)(self, cmd, sender);
        LanternSelectMode(NO);
    } else {
        if (LanternSelectMode(warm))
            // Consume this event before refresh can reset the live sender to off.
            ((void (*)(id, SEL, id))gAppleSlider)(self, cmd, sender);
        else LanternNativeOff();
    }
    LanternRefresh();
}

static void LanternStockSlider(id self, SEL cmd, id sender)
{
    if (!gActive || ![NSThread isMainThread]) {
        ((void (*)(id, SEL, id))(gAppleSlider ?: gFallback[1]))(self, cmd, sender);
        return;
    }
    LanternSliderForMode(self, cmd, sender, NO);
}

static void LanternWarmSlider(id self, SEL cmd, id sender)
{
    if (gActive && [NSThread isMainThread]) LanternSliderForMode(self, cmd, sender, YES);
}

static void LanternUpdateControls(id self, SEL cmd)
{
    ((void (*)(id, SEL))(gAppleUpdate ?: gFallback[2]))(self, cmd);
    if (!gActive || ![NSThread isMainThread]) return;
    [gControls addObject:self];
    BOOL warmTile = [self isKindOfClass:gLanternControllerClass];
    BOOL selected = LanternAvailable() && LanternLevel() > 0 && gWarm == warmTile;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, NSSelectorFromString(@"setSelected:"), selected);
}

@interface LanternLevelObserver : NSObject
- (void)flashlightLevelDidChange:(NSUInteger)level;
- (void)flashlightAvailabilityDidChange:(BOOL)available;
@end
@implementation LanternLevelObserver
- (void)flashlightLevelDidChange:(NSUInteger)level
{
    // Native callback is main-thread UI work; defer reset beyond Apple's setter.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (LanternLevel() == 0 && !gPendingTimer) LanternSelectMode(NO);
        LanternRefresh();
    });
}

- (void)flashlightAvailabilityDidChange:(BOOL)available
{
    dispatch_async(dispatch_get_main_queue(), ^{
        LanternRefresh();
    });
}
@end
static LanternLevelObserver *gObserver;

static BOOL LanternMethodMatches(Class cls, NSString *name, const char *types)
{
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    const char *actual = method ? method_getTypeEncoding(method) : NULL;
    return actual && strcmp(actual, types) == 0;
}

static Class LanternControllerClass(void)
{
    if (![NSThread isMainThread]) return Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/ControlCenter/Bundles/FlashlightModule.bundle/FlashlightModule", RTLD_NOW | RTLD_GLOBAL);
        Class apple = NSClassFromString(@"CCUIFlashlightModuleViewController");
        Class flashlight = NSClassFromString(@"SBUIFlashlightController");
        if (!apple || !flashlight ||
            !LanternMethodMatches(apple, @"buttonTapped:forEvent:", "v32@0:8@16@24") ||
            !LanternMethodMatches(apple, @"_sliderValueDidChange:", "v24@0:8@16") ||
            !LanternMethodMatches(apple, @"_updateControls", "v16@0:8") ||
            !LanternMethodMatches(apple, @"setSelected:", "v20@0:8B16") ||
            !LanternMethodMatches(object_getClass(flashlight), @"sharedInstance", "@16@0:8") ||
            !LanternMethodMatches(flashlight, @"level", "Q16@0:8") ||
            !LanternMethodMatches(flashlight, @"isAvailable", "B16@0:8") ||
            !LanternMethodMatches(flashlight, @"intensity", "f16@0:8") ||
            !LanternMethodMatches(flashlight, @"width", "f16@0:8") ||
            !LanternMethodMatches(flashlight, @"_setIntensity:width:animated:withPowerChange:", "v44@0:8d16d24B32Q36") ||
            !LanternMethodMatches(flashlight, @"turnFlashlightOnForReason:", "v24@0:8@16") ||
            !LanternMethodMatches(flashlight, @"turnFlashlightOffForReason:", "v24@0:8@16") ||
            !LanternMethodMatches(flashlight, @"addObserver:", "v24@0:8@16")) return;
        NotifyRegisterFn reg = (NotifyRegisterFn)dlsym(RTLD_DEFAULT, "notify_register_check");
        gSetState = (NotifySetFn)dlsym(RTLD_DEFAULT, "notify_set_state");
        gPost = (NotifyPostFn)dlsym(RTLD_DEFAULT, "notify_post");
        if (!reg || !gSetState || !gPost || reg(kLanternStateNotification, &gStateToken) != 0 ||
            !LanternPublish(NO)) return;
        Class cls = objc_allocateClassPair(apple, "LanternNativeFlashlightViewController", 0);
        if (!cls) return;
        SEL button = NSSelectorFromString(@"buttonTapped:forEvent:");
        SEL slider = NSSelectorFromString(@"_sliderValueDidChange:");
        if (!class_addMethod(cls, button, (IMP)LanternWarmButton, method_getTypeEncoding(class_getInstanceMethod(apple, button))) ||
            !class_addMethod(cls, slider, (IMP)LanternWarmSlider, method_getTypeEncoding(class_getInstanceMethod(apple, slider)))) {
            objc_disposeClassPair(cls); return;
        }
        gControls = [NSHashTable weakObjectsHashTable];
        gObserver = [LanternLevelObserver new];
        if (!gControls || !gObserver || !LanternFlashlight()) { objc_disposeClassPair(cls); return; }
        gFallback[0] = class_getMethodImplementation(apple, button);
        gFallback[1] = class_getMethodImplementation(apple, slider);
        gFallback[2] = class_getMethodImplementation(apple, NSSelectorFromString(@"_updateControls"));
        MSHookMessageEx(apple, button, (IMP)LanternStockButton, &gAppleButton);
        MSHookMessageEx(apple, slider, (IMP)LanternStockSlider, &gAppleSlider);
        MSHookMessageEx(apple, NSSelectorFromString(@"_updateControls"), (IMP)LanternUpdateControls, &gAppleUpdate);
        if (!gAppleButton || !gAppleSlider || !gAppleUpdate ||
            class_getMethodImplementation(apple, button) != (IMP)LanternStockButton ||
            class_getMethodImplementation(apple, slider) != (IMP)LanternStockSlider ||
            class_getMethodImplementation(apple, NSSelectorFromString(@"_updateControls")) != (IMP)LanternUpdateControls) {
            objc_disposeClassPair(cls); return;
        }
        gLanternControllerClass = cls;
        objc_registerClassPair(cls);
        ((void (*)(id, SEL, id))objc_msgSend)(LanternFlashlight(), NSSelectorFromString(@"addObserver:"), gObserver);
        gActive = YES;
    });
    return gActive ? gLanternControllerClass : Nil;
}

static UIImage *LanternCustomGlyph(BOOL selected)
{
    NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(@"LanternModule")];
    UIImage *image = [UIImage imageNamed:selected ? @"LanternCustom-on" : @"LanternCustom-off"
        inBundle:bundle compatibleWithTraitCollection:nil];
    if (!image) image = [UIImage systemImageNamed:selected ? @"light.beacon.min.fill" : @"light.beacon.min"];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIViewController *LanternCreateController(void)
{
    Class cls = LanternControllerClass();
    if (!cls) return nil;

    UIViewController *controller = [[cls alloc] initWithNibName:nil bundle:nil];
    if (!controller) return nil;

    SEL titleSel = NSSelectorFromString(@"setTitle:");
    SEL glyphSel = NSSelectorFromString(@"setGlyphImage:");
    SEL selectedGlyphSel = NSSelectorFromString(@"setSelectedGlyphImage:");
    SEL colorSel = NSSelectorFromString(@"setSelectedGlyphColor:");

    if ([controller respondsToSelector:titleSel])
        ((void (*)(id, SEL, id))objc_msgSend)(controller, titleSel, @"Lantern");
    if ([controller respondsToSelector:glyphSel])
        ((void (*)(id, SEL, id))objc_msgSend)(controller, glyphSel,
            LanternCustomGlyph(NO));
    if ([controller respondsToSelector:selectedGlyphSel])
        ((void (*)(id, SEL, id))objc_msgSend)(controller, selectedGlyphSel,
            LanternCustomGlyph(YES));
    if ([controller respondsToSelector:colorSel])
        ((void (*)(id, SEL, id))objc_msgSend)(controller, colorSel,
            [UIColor systemYellowColor]);

    return controller;
}

static Class gLanternBackgroundClass;
static UIImage *gLanternHeaderOff, *gLanternHeaderOn;

static BOOL LanternBackgroundCanShowWhileLocked(id self, SEL cmd)
{
    return YES;
}

static void LanternBackgroundUpdate(id self, SEL cmd)
{
    if (![NSThread isMainThread]) return;
    BOOL selected = gActive && LanternAvailable() && LanternLevel() > 0 && gWarm;
    ((void (*)(id, SEL, id, double))objc_msgSend)(self, NSSelectorFromString(@"setHeaderGlyphImage:unscaledSymbolPointSize:"),
        selected ? gLanternHeaderOn : gLanternHeaderOff, 30.0);
}

static void LanternBackgroundWillAppear(id self, SEL cmd, BOOL animated)
{
    struct objc_super parent = { self, class_getSuperclass(gLanternBackgroundClass) };
    ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&parent, cmd, animated);
    LanternBackgroundUpdate(self, NSSelectorFromString(@"_updateControls"));
}

static UIViewController *LanternCreateBackground(void)
{
    if (![NSThread isMainThread] || !LanternControllerClass()) return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = NSClassFromString(@"CCUISliderModuleBackgroundViewController");
        if (!base || !LanternMethodMatches(base, @"setHeaderGlyphImage:unscaledSymbolPointSize:", "v32@0:8@16d24") ||
            !LanternMethodMatches(base, @"viewWillAppear:", "v20@0:8B16") ||
            !LanternMethodMatches(base, @"_canShowWhileLocked", "B16@0:8")) return;
        UIImage *off = LanternCustomGlyph(NO);
        UIImage *on = LanternCustomGlyph(YES);
        if (!off || !on) return;
        Class cls = objc_allocateClassPair(base, "LanternHeaderBackgroundViewController", 0);
        if (!cls) return;
        if (!class_addMethod(cls, NSSelectorFromString(@"_updateControls"), (IMP)LanternBackgroundUpdate, "v16@0:8") ||
            !class_addMethod(cls, NSSelectorFromString(@"viewWillAppear:"), (IMP)LanternBackgroundWillAppear, "v20@0:8B16") ||
            !class_addMethod(cls, NSSelectorFromString(@"_canShowWhileLocked"), (IMP)LanternBackgroundCanShowWhileLocked, "B16@0:8")) {
            objc_disposeClassPair(cls); return;
        }
        gLanternHeaderOff = [off imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        gLanternHeaderOn = [on imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        gLanternBackgroundClass = cls;
        objc_registerClassPair(cls);
    });
    if (!gLanternBackgroundClass) return nil;
    UIViewController *background = [[gLanternBackgroundClass alloc] initWithNibName:nil bundle:nil];
    if (background) {
        [gControls addObject:background];
        LanternBackgroundUpdate(background, NSSelectorFromString(@"_updateControls"));
    }
    return background;
}

@interface LanternModule : NSObject <CCUIContentModule>
@property(nonatomic, strong) UIViewController *viewController;
@property(nonatomic, strong) UIViewController *headerController;
@end

@implementation LanternModule

- (UIViewController *)contentViewController
{
    return self.viewController;
}

- (UIViewController *)contentViewControllerForContext:(id)context
{
    UIViewController *controller = LanternCreateController();
    if (self.viewController == nil) self.viewController = controller;
    return controller;
}

- (UIViewController *)backgroundViewController
{
    return self.headerController;
}

- (UIViewController *)backgroundViewControllerForContext:(id)context
{
    UIViewController *background = LanternCreateBackground();
    if (self.headerController == nil) self.headerController = background;
    return background;
}

- (BOOL)expandsGridSizeClassesForAccessibility
{
    return YES;
}

@end
