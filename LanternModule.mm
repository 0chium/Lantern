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

@interface CCUISliderButtonModuleViewController : UIViewController
- (id)sliderView;
- (id)createSliderView;
- (id)buttonView;
- (BOOL)isSelected;
- (BOOL)isExpanded;
- (void)setSelected:(BOOL)selected;
- (void)setTitle:(NSString *)title;
- (void)setGlyphImage:(UIImage *)image;
- (void)setSelectedGlyphImage:(UIImage *)image;
- (void)setSelectedGlyphColor:(UIColor *)color;
@end

@interface CCUISteppedSliderView : UIControl
- (void)setNumberOfSteps:(NSUInteger)steps;
- (void)setFirstStepIsOff:(BOOL)firstStepIsOff;
- (NSUInteger)step;
- (void)setStep:(NSUInteger)step;
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

static NSUInteger LanternFlashlightLevel(id controller)
{
    SEL selector = NSSelectorFromString(@"level");

    if (controller == nil ||
        ![controller respondsToSelector:selector]) {
        return 0;
    }

    return ((NSUInteger (*)(id, SEL))objc_msgSend)(
        controller,
        selector
    );
}

static BOOL LanternFlashlightAvailable(id controller)
{
    SEL selector = NSSelectorFromString(@"isAvailable");

    if (controller == nil ||
        ![controller respondsToSelector:selector]) {
        return NO;
    }

    return ((BOOL (*)(id, SEL))objc_msgSend)(
        controller,
        selector
    );
}

static void LanternSetFlashlightLevel(
    id controller,
    NSUInteger level
)
{
    SEL selector = NSSelectorFromString(@"setLevel:");

    if (controller != nil &&
        [controller respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(
            controller,
            selector,
            level
        );
    }
}

@interface LanternModuleViewController :
    CCUISliderButtonModuleViewController
@property(nonatomic, strong) id flashlight;
@end

@implementation LanternModuleViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        _flashlight = LanternFlashlightController();

        [self setTitle:@"Lantern"];

        [self setGlyphImage:
            [UIImage systemImageNamed:@"flashlight.off.fill"]];

        [self setSelectedGlyphImage:
            [UIImage systemImageNamed:@"flashlight.on.fill"]];

        [self setSelectedGlyphColor:
            [UIColor systemYellowColor]];
    }

    return self;
}

- (id)createSliderView
{
    Class sliderClass =
        NSClassFromString(@"CCUISteppedSliderView");

    if (sliderClass == Nil)
        return [super createSliderView];

    return [[sliderClass alloc]
        initWithFrame:self.view.bounds];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    CCUISteppedSliderView *slider =
        (CCUISteppedSliderView *)[self sliderView];

    [slider setNumberOfSteps:5];
    [slider setFirstStepIsOff:YES];

    [slider addTarget:self
               action:@selector(lanternSliderValueDidChange:)
     forControlEvents:(UIControlEvents)4096];

    [self lanternUpdateControls];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self lanternUpdateControls];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    [self lanternUpdateSliderValue];
}

- (BOOL)_canShowWhileLocked
{
    return YES;
}

- (BOOL)shouldBeginTransitionToExpandedContentModule
{
    return LanternFlashlightAvailable(self.flashlight);
}

- (BOOL)shouldFinishTransitionToExpandedContentModule
{
    return LanternFlashlightAvailable(self.flashlight);
}

- (void)buttonTapped:(id)sender forEvent:(id)event
{
    BOOL selected =
        LanternFlashlightAvailable(self.flashlight) &&
        ![self isSelected];

    [self setSelected:selected];

    if (selected) {
        if (!LanternSetWarmState(YES)) {
            [self setSelected:NO];
            return;
        }

        SEL selector =
            NSSelectorFromString(
                @"turnFlashlightOnForReason:"
            );

        if ([self.flashlight respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                self.flashlight,
                selector,
                @"Control Center"
            );
        }
        else {
            LanternSetWarmState(NO);
            [self setSelected:NO];
        }
    }
    else {
        SEL selector =
            NSSelectorFromString(
                @"turnFlashlightOffForReason:"
            );

        if ([self.flashlight respondsToSelector:selector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                self.flashlight,
                selector,
                @"Control Center"
            );
        }

        LanternSetWarmState(NO);
    }

    [self lanternUpdateControls];
}

- (void)lanternSliderValueDidChange:(id)sender
{
    NSUInteger step =
        [(CCUISteppedSliderView *)sender step];

    if (step > 0) {
        LanternSetWarmState(YES);
    }

    LanternSetFlashlightLevel(self.flashlight, step);

    if (step == 0) {
        LanternSetWarmState(NO);
    }

    [self lanternUpdateControls];
}

- (void)lanternUpdateSliderValue
{
    if (![self isExpanded])
        return;

    CCUISteppedSliderView *slider =
        (CCUISteppedSliderView *)[self sliderView];

    NSUInteger level =
        LanternFlashlightLevel(self.flashlight);

    NSUInteger step =
        (level >= 1 && level <= 4)
            ? level + 1
            : 1;

    [slider setStep:step];
}

- (void)lanternUpdateControls
{
    BOOL available =
        LanternFlashlightAvailable(self.flashlight);

    NSUInteger level =
        LanternFlashlightLevel(self.flashlight);

    id button = [self buttonView];
    SEL enabledSelector =
        NSSelectorFromString(@"setEnabled:");

    if ([button respondsToSelector:enabledSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            button,
            enabledSelector,
            available
        );
    }

    id slider = [self sliderView];

    if ([slider respondsToSelector:enabledSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            slider,
            enabledSelector,
            available
        );
    }

    [self setSelected:(available && level != 0)];
    [self lanternUpdateSliderValue];
}

- (void)flashlightLevelDidChange:(NSUInteger)level
{
    [self lanternUpdateControls];
}

- (void)flashlightAvailabilityDidChange:(BOOL)available
{
    [self lanternUpdateControls];
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
    LanternModuleViewController *controller =
        [[LanternModuleViewController alloc] init];

    if (self.viewController == nil) {
        self.viewController = controller;
    }

    return controller;
}

- (BOOL)expandsGridSizeClassesForAccessibility
{
    return YES;
}

@end
