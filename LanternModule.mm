#import <UIKit/UIKit.h>

@protocol CCUIContentModule <NSObject>
@required
- (UIViewController *)contentViewController;

@optional
- (UIViewController *)contentViewControllerForContext:(id)context;
- (UIViewController *)backgroundViewController;
- (UIViewController *)backgroundViewControllerForContext:(id)context;
@end

@interface LanternModuleViewController : UIViewController
@end

@implementation LanternModuleViewController

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [UIColor clearColor];

    UIImage *image = [UIImage systemImageNamed:@"lightbulb.fill"];
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:image];

    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.tintColor = [UIColor labelColor];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;

    [view addSubview:imageView];

    [NSLayoutConstraint activateConstraints:@[
        [imageView.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [imageView.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [imageView.widthAnchor constraintEqualToConstant:24.0],
        [imageView.heightAnchor constraintEqualToConstant:24.0]
    ]];

    self.view = view;
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
