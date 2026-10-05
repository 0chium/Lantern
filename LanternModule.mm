#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <notify.h>
#import <stdint.h>
#import <substrate.h>

@protocol CCUIContentModule <NSObject>
@required
- (UIViewController *)contentViewController;
@optional
- (UIViewController *)contentViewControllerForContext:(id)context;
@end

typedef uint32_t (*NotifyRegisterCheckFn)(const char *, int *);
typedef uint32_t (*NotifySetStateFn)(int, uint64_t);
typedef uint32_t (*NotifyGetStateFn)(int, uint64_t *);
typedef uint32_t (*NotifyPostFn)(const char *);
typedef uint32_t (*NotifyCancelFn)(int);

static const char *kLanternStateNotification = "com.ochium.lantern.state";
static IMP gAppleButtonTapped = NULL;
static IMP gAppleSliderChanged = NULL;
static IMP gAppleUpdateControls = NULL;
static void (*gOriginalTurnOn)(id, SEL, id) = NULL;
static void (*gOriginalTurnOff)(id, SEL, id) = NULL;
static void (*gOriginalTurnOffCoolDown)(id, SEL, id, BOOL) = NULL;
static BOOL gLanternPowerRequest = NO;

static BOOL LanternState(BOOL write, BOOL value, BOOL *result)
{
    NotifyRegisterCheckFn reg = (NotifyRegisterCheckFn)dlsym(RTLD_DEFAULT, "notify_register_check");
    NotifySetStateFn set = (NotifySetStateFn)dlsym(RTLD_DEFAULT, "notify_set_state");
    NotifyGetStateFn get = (NotifyGetStateFn)dlsym(RTLD_DEFAULT, "notify_get_state");
    NotifyPostFn post = (NotifyPostFn)dlsym(RTLD_DEFAULT, "notify_post");
    NotifyCancelFn cancel = (NotifyCancelFn)dlsym(RTLD_DEFAULT, "notify_cancel");
    if (!reg || !get || !cancel || (write && (!set || !post))) return NO;

    int token = -1;
    if (reg(kLanternStateNotification, &token) != 0) return NO;

    BOOL ok = NO;
    if (write) {
        ok = set(token, value ? 1 : 0) == 0;
        if (ok) post(kLanternStateNotification);
    } else {
        uint64_t state = 0;
        ok = get(token, &state) == 0;
        if (ok && result) *result = state != 0;
    }
    cancel(token);
    return ok;
}

static BOOL LanternSetWarm(BOOL enabled)
{
    return LanternState(YES, enabled, NULL);
}

static BOOL LanternIsWarm(void)
{
    BOOL enabled = NO;
    LanternState(NO, NO, &enabled);
    return enabled;
}

static id LanternFlashlight(void)
{
    Class cls = NSClassFromString(@"SBUIFlashlightController");
    SEL sel = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![cls respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, sel);
}

static NSUInteger LanternLevel(void)
{
    id flashlight = LanternFlashlight();
    SEL sel = NSSelectorFromString(@"level");
    if (!flashlight || ![flashlight respondsToSelector:sel]) return 0;
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(flashlight, sel);
}

static void LanternReapplyLevel(NSUInteger level)
{
    id flashlight = LanternFlashlight();
    SEL sel = NSSelectorFromString(@"setLevel:");
    if (flashlight && [flashlight respondsToSelector:sel]) {
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(flashlight, sel, level);
    }
}

static void LanternTurnOnHook(id self, SEL cmd, id reason)
{
    if (!gLanternPowerRequest && LanternIsWarm()) LanternSetWarm(NO);
    gOriginalTurnOn(self, cmd, reason);
}

static void LanternTurnOffHook(id self, SEL cmd, id reason)
{
    LanternSetWarm(NO);
    gOriginalTurnOff(self, cmd, reason);
}

static void LanternTurnOffCoolDownHook(id self, SEL cmd, id reason, BOOL coolDown)
{
    LanternSetWarm(NO);
    gOriginalTurnOffCoolDown(self, cmd, reason, coolDown);
}

static void LanternInstallPowerHooks(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"SBUIFlashlightController");
        if (!cls) return;

        Method on = class_getInstanceMethod(cls, NSSelectorFromString(@"turnFlashlightOnForReason:"));
        Method off = class_getInstanceMethod(cls, NSSelectorFromString(@"turnFlashlightOffForReason:"));
        Method offCool = class_getInstanceMethod(cls, NSSelectorFromString(@"turnFlashlightOffForReason:withCoolDown:"));

        if (on) MSHookFunction((void *)method_getImplementation(on),
                               (void *)LanternTurnOnHook,
                               (void **)&gOriginalTurnOn);
        if (off) MSHookFunction((void *)method_getImplementation(off),
                                (void *)LanternTurnOffHook,
                                (void **)&gOriginalTurnOff);
        if (offCool) MSHookFunction((void *)method_getImplementation(offCool),
                                    (void *)LanternTurnOffCoolDownHook,
                                    (void **)&gOriginalTurnOffCoolDown);
    });
}

static void LanternSetSelected(id self, BOOL selected)
{
    SEL sel = NSSelectorFromString(@"setSelected:");
    if ([self respondsToSelector:sel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, sel, selected);
    }
}

static void LanternButtonTapped(id self, SEL cmd, id sender, id event)
{
    NSUInteger level = LanternLevel();

    if (level > 0 && LanternIsWarm()) {
        LanternReapplyLevel(0);
        LanternSetWarm(NO);
        return;
    }

    if (level > 0) {
        if (LanternSetWarm(YES)) LanternReapplyLevel(level);
        LanternSetSelected(self, YES);
        return;
    }

    if (!LanternSetWarm(YES)) return;
    gLanternPowerRequest = YES;
    if (gAppleButtonTapped)
        ((void (*)(id, SEL, id, id))gAppleButtonTapped)(self, cmd, sender, event);
    gLanternPowerRequest = NO;
    if (LanternLevel() == 0) LanternSetWarm(NO);
}

static void LanternSliderChanged(id self, SEL cmd, id sender)
{
    SEL stepSel = NSSelectorFromString(@"step");
    NSUInteger step = [sender respondsToSelector:stepSel]
        ? ((NSUInteger (*)(id, SEL))objc_msgSend)(sender, stepSel)
        : 0;

    LanternSetWarm(step > 1);
    if (gAppleSliderChanged)
        ((void (*)(id, SEL, id))gAppleSliderChanged)(self, cmd, sender);
}

static void LanternUpdateControls(id self, SEL cmd)
{
    if (gAppleUpdateControls)
        ((void (*)(id, SEL))gAppleUpdateControls)(self, cmd);
}

static Class LanternControllerClass(void)
{
    static Class cls = Nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        LanternInstallPowerHooks();
        dlopen("/System/Library/ControlCenter/Bundles/FlashlightModule.bundle/FlashlightModule",
               RTLD_NOW | RTLD_GLOBAL);

        Class apple = NSClassFromString(@"CCUIFlashlightModuleViewController");
        if (!apple) return;

        Method button = class_getInstanceMethod(apple, NSSelectorFromString(@"buttonTapped:forEvent:"));
        Method slider = class_getInstanceMethod(apple, NSSelectorFromString(@"_sliderValueDidChange:"));
        Method update = class_getInstanceMethod(apple, NSSelectorFromString(@"_updateControls"));
        if (!button || !slider || !update) return;

        gAppleButtonTapped = method_getImplementation(button);
        gAppleSliderChanged = method_getImplementation(slider);
        gAppleUpdateControls = method_getImplementation(update);

        cls = objc_allocateClassPair(apple, "LanternNativeFlashlightViewController", 0);
        if (!cls) {
            cls = NSClassFromString(@"LanternNativeFlashlightViewController");
            return;
        }

        class_addMethod(cls, NSSelectorFromString(@"buttonTapped:forEvent:"),
                        (IMP)LanternButtonTapped, method_getTypeEncoding(button));
        class_addMethod(cls, NSSelectorFromString(@"_sliderValueDidChange:"),
                        (IMP)LanternSliderChanged, method_getTypeEncoding(slider));
        class_addMethod(cls, NSSelectorFromString(@"_updateControls"),
                        (IMP)LanternUpdateControls, method_getTypeEncoding(update));
        objc_registerClassPair(cls);
    });

    return cls;
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
            [UIImage systemImageNamed:@"flashlight.off.fill"]);
    if ([controller respondsToSelector:selectedGlyphSel])
        ((void (*)(id, SEL, id))objc_msgSend)(controller, selectedGlyphSel,
            [UIImage systemImageNamed:@"flashlight.on.fill"]);
    if ([controller respondsToSelector:colorSel])
        ((void (*)(id, SEL, id))objc_msgSend)(controller, colorSel,
            [UIColor systemYellowColor]);

    return controller;
}

@interface LanternModule : NSObject <CCUIContentModule>
@property(nonatomic, strong) UIViewController *viewController;
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

- (BOOL)expandsGridSizeClassesForAccessibility
{
    return YES;
}

@end
