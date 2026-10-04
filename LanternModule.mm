#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#import <stdint.h>

@protocol CCUIContentModule <NSObject>
@required
- (UIViewController *)contentViewController;

@optional
- (UIViewController *)contentViewControllerForContext:(id)context;
- (UIViewController *)backgroundViewController;
- (UIViewController *)backgroundViewControllerForContext:(id)context;
@end

typedef uint32_t (*LanternNotifyRegisterCheckFunction)(
    const char *name,
    int *outToken
);

typedef uint32_t (*LanternNotifySetStateFunction)(
    int token,
    uint64_t state
);

typedef uint32_t (*LanternNotifyPostFunction)(
    const char *name
);

typedef uint32_t (*LanternNotifyCancelFunction)(
    int token
);

static const char *kLanternStateNotification =
    "com.ochium.lantern.state";

static BOOL LanternSetWarmState(BOOL enabled)
{
    LanternNotifyRegisterCheckFunction notifyRegisterCheck =
        (LanternNotifyRegisterCheckFunction)dlsym(
            RTLD_DEFAULT,
            "notify_register_check"
        );

    LanternNotifySetStateFunction notifySetState =
        (LanternNotifySetStateFunction)dlsym(
            RTLD_DEFAULT,
            "notify_set_state"
        );

    LanternNotifyPostFunction notifyPost =
        (LanternNotifyPostFunction)dlsym(
            RTLD_DEFAULT,
            "notify_post"
        );

    LanternNotifyCancelFunction notifyCancel =
        (LanternNotifyCancelFunction)dlsym(
            RTLD_DEFAULT,
            "notify_cancel"
        );

    if (notifyRegisterCheck == NULL ||
        notifySetState == NULL ||
        notifyPost == NULL ||
        notifyCancel == NULL) {
        return NO;
    }

    int token = -1;

    if (notifyRegisterCheck(
            kLanternStateNotification,
            &token
        ) != 0) {
        return NO;
    }

    BOOL success =
        notifySetState(token, enabled ? 1 : 0) == 0;

    if (success) {
        notifyPost(kLanternStateNotification);
    }

    notifyCancel(token);
    return success;
}

static id LanternFlashlightController(void)
{
    Class controllerClass =
        NSClassFromString(@"SBUIFlashlightController");

    SEL sharedInstanceSelector =
        NSSelectorFromString(@"sharedInstance");

    if (controllerClass == Nil ||
        ![controllerClass respondsToSelector:
            sharedInstanceSelector]) {
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(
        controllerClass,
        sharedInstanceSelector
    );
}

static NSInteger LanternFlashlightLevel(id controller)
{
    SEL levelSelector =
        NSSelectorFromString(@"level");

    if (controller == nil ||
        ![controller respondsToSelector:levelSelector]) {
        return 0;
    }

    return ((NSInteger (*)(id, SEL))objc_msgSend)(
        controller,
        levelSelector
    );
}

@interface LanternModuleViewController : UIViewController
@property(nonatomic, strong) UIButton *button;
@end

@implementation LanternModuleViewController

- (void)loadView
{
    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.backgroundColor = [UIColor clearColor];
    button.tintColor = [UIColor labelColor];

    UIImage *image =
        [UIImage systemImageNamed:@"flashlight.on.fill"];

    [button setImage:image forState:UIControlStateNormal];

    button.imageView.contentMode =
        UIViewContentModeScaleAspectFit;

    [button addTarget:self
               action:@selector(lanternTapped:)
     forControlEvents:UIControlEventTouchUpInside];

    self.button = button;
    self.view = button;

    [self updateAppearance];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self updateAppearance];
}

- (void)updateAppearance
{
    id controller = LanternFlashlightController();
    BOOL active = LanternFlashlightLevel(controller) > 0;

    self.button.tintColor =
        active ? [UIColor systemYellowColor]
               : [UIColor labelColor];
}

- (void)lanternTapped:(id)sender
{
    id controller = LanternFlashlightController();

    if (controller == nil)
        return;

    BOOL active =
        LanternFlashlightLevel(controller) > 0;

    if (active) {
        SEL offSelector =
            NSSelectorFromString(
                @"turnFlashlightOffForReason:"
            );

        if ([controller respondsToSelector:offSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                controller,
                offSelector,
                @"Control Center"
            );
        }

        LanternSetWarmState(NO);
    }
    else {
        if (!LanternSetWarmState(YES))
            return;

        SEL onSelector =
            NSSelectorFromString(
                @"turnFlashlightOnForReason:"
            );

        if ([controller respondsToSelector:onSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                controller,
                onSelector,
                @"Control Center"
            );
        }
        else {
            LanternSetWarmState(NO);
        }
    }

    [self updateAppearance];
}

@end

@interface LanternModule : NSObject <CCUIContentModule>
@property(nonatomic, strong) LanternModuleViewController *viewController;
@end

@implementation LanternModule

- (instancetype)init
{
    self = [super init];

    if (self) {
        _viewController =
            [[LanternModuleViewController alloc] init];
    }

    return self;
}

- (UIViewController *)contentViewController
{
    return self.viewController;
}

- (UIViewController *)contentViewControllerForContext:(id)context
{
    return self.viewController;
}

@end
