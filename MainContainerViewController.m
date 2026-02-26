#import "MainContainerViewController.h"
#import "TabManager.h"
#import "TabSwitcherViewController.h"
#import "FileBrowserViewController.h"
#import "ThemeEngine.h"
#import "BottomMenuView.h"
#import "PathBarView.h"
#import "AppDelegate.h"

@interface MainContainerViewController ()
@property (nonatomic, strong) UIViewController *currentContentController;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@end

@implementation MainContainerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    if ([TabManager sharedManager].tabs.count == 0) {
        [[TabManager sharedManager] addNewTabWithType:TabTypeFileBrowser path:@"/"];
    }
    [self displayActiveTab];
    [self setupBottomMenu];
}

- (void)setupBottomMenu {
    self.bottomMenu = [[BottomMenuView alloc] init];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.bottomMenu];

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [self.bottomMenu.heightAnchor constraintEqualToConstant:70]
    ]];

    __weak typeof(self) weakSelf = self;
    self.bottomMenu.onAction = ^(BottomMenuAction action) {
        [weakSelf handleMenuAction:action];
    };
}

- (void)handleMenuAction:(BottomMenuAction)action {
    UINavigationController *nav = (UINavigationController *)self.currentContentController;
    if (![nav isKindOfClass:[UINavigationController class]]) return;

    UIViewController *top = nav.topViewController;
    if ([top respondsToSelector:@selector(handleMenuAction:)]) {
        [top performSelector:@selector(handleMenuAction:) withObject:@(action)];
    } else {
        // Fallback for non-responding VCs
        switch (action) {
            case BottomMenuActionTabs: [self showTabSwitcher]; break;
            default: break;
        }
    }
}

- (void)displayActiveTab {
    TabInfo *active = [[TabManager sharedManager] activeTab];
    if (!active) return;

    if (self.currentContentController) {
        [self.currentContentController willMoveToParentViewController:nil];
        [self.currentContentController.view removeFromSuperview];
        [self.currentContentController removeFromParentViewController];
    }

    UIViewController *vc;
    switch (active.type) {
        case TabTypeFileBrowser:
            vc = [[FileBrowserViewController alloc] initWithPath:active.currentPath];
            break;
        default:
            vc = [[FileBrowserViewController alloc] initWithPath:@"/"];
            break;
    }

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];

    // Liquidglass Navigation Bar
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};
    appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [UIColor whiteColor]};

    nav.navigationBar.standardAppearance = appearance;
    nav.navigationBar.scrollEdgeAppearance = appearance;
    nav.navigationBar.compactAppearance = appearance;
    nav.navigationBar.tintColor = [UIColor whiteColor];
    nav.navigationBar.prefersLargeTitles = YES;

    [self addChildViewController:nav];
    nav.view.frame = self.view.bounds;
    [self.view insertSubview:nav.view belowSubview:self.bottomMenu];
    [nav didMoveToParentViewController:self];
    self.currentContentController = nav;

    // Add additional bottom padding to the top VC's scroll view if possible
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([vc isKindOfClass:[FileBrowserViewController class]]) {
            FileBrowserViewController *fbvc = (FileBrowserViewController *)vc;
            UIEdgeInsets insets = fbvc.tableView.contentInset;
            insets.bottom += 90;
            fbvc.tableView.contentInset = insets;
            fbvc.tableView.verticalScrollIndicatorInsets = insets;
        }
    });
}

- (void)showTabSwitcher {
    TabInfo *active = [[TabManager sharedManager] activeTab];
    if (active && self.currentContentController) {
        UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, YES, 0);
        [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
        active.screenshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }

    TabSwitcherViewController *switcher = [[TabSwitcherViewController alloc] init];
    switcher.modalPresentationStyle = UIModalPresentationOverFullScreen;
    switcher.onTabSelected = ^(NSInteger index) {
        [TabManager sharedManager].activeTabIndex = index;
        [self dismissViewControllerAnimated:YES completion:^{
            [self displayActiveTab];
        }];
    };
    switcher.onNewTabRequested = ^{
        [[TabManager sharedManager] addNewTabWithType:TabTypeFileBrowser path:@"/"];
        [self dismissViewControllerAnimated:YES completion:^{
            [self displayActiveTab];
        }];
    };
    [self presentViewController:switcher animated:YES completion:nil];
}

@end
