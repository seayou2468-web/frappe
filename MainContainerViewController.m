#import "MainContainerViewController.h"
#import "TabManager.h"
#import "TabSwitcherViewController.h"
#import "FileBrowserViewController.h"
#import "WebBrowserViewController.h"
#import "ThemeEngine.h"
#import "IdeviceViewController.h"
#import "BottomMenuView.h"



@interface MainContainerViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIViewController *currentContentController;
@end

@implementation MainContainerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshUI) name:@"SettingsChanged" object:nil];
    self.view.backgroundColor = [ThemeEngine bg];

        if ([TabManager sharedManager].tabs.count == 0) {
        NSString *startPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: NSHomeDirectory();
        [[TabManager sharedManager] addNewTabWithType:TabTypeFileBrowser path:startPath];
    }
    [self displayActiveTab];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)displayActiveTab {
    TabInfo *active = [[TabManager sharedManager] activeTab];
    if (!active) return;

    if (self.currentContentController) {
        [self.currentContentController willMoveToParentViewController:nil];
        [self.currentContentController.view removeFromSuperview];
        [self.currentContentController removeFromParentViewController];
    }

    UINavigationController *nav = (UINavigationController *)active.viewController;
    if (!nav) {
        nav = [[UINavigationController alloc] init];
        NSMutableArray *vcs = [NSMutableArray array];
        if (active.type == TabTypeFileBrowser) {
            NSString *tempPath = @"/";
            [vcs addObject:[[FileBrowserViewController alloc] initWithPath:tempPath]];
            NSArray *components = [active.currentPath pathComponents];
            for (NSString *comp in components) {
                if ([comp isEqualToString:@"/"]) continue;
                tempPath = [tempPath stringByAppendingPathComponent:comp];
                [vcs addObject:[[FileBrowserViewController alloc] initWithPath:tempPath]];
            }
        } else if (active.type == TabTypeWebBrowser) {
            [vcs addObject:[[WebBrowserViewController alloc] initWithURL:active.currentPath]];
        } else {
            [vcs addObject:[[FileBrowserViewController alloc] initWithPath:@"/"]];
        }
        [nav setViewControllers:vcs animated:NO];
        nav.interactivePopGestureRecognizer.delegate = self;
        // iOS 26: premium dark navigation bar
        UINavigationBarAppearance *_navAppearance = [[UINavigationBarAppearance alloc] init];
        [_navAppearance configureWithTransparentBackground];
        _navAppearance.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _navAppearance.titleTextAttributes = @{
            NSFontAttributeName: [ThemeEngine fontHeadline],
            NSForegroundColorAttributeName: [ThemeEngine textPrimary]
        };
        _navAppearance.largeTitleTextAttributes = @{
            NSFontAttributeName: [ThemeEngine fontTitle],
            NSForegroundColorAttributeName: [ThemeEngine textPrimary]
        };
        UINavigationBarAppearance *_navAppearanceBlur = [_navAppearance copy];
        [_navAppearanceBlur configureWithDefaultBackground];
        _navAppearanceBlur.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        _navAppearanceBlur.backgroundColor = [[ThemeEngine bg] colorWithAlphaComponent:0.85];
        _navAppearanceBlur.titleTextAttributes = _navAppearance.titleTextAttributes;
        nav.navigationBar.standardAppearance = _navAppearanceBlur;
        nav.navigationBar.scrollEdgeAppearance = _navAppearance;
        nav.navigationBar.compactAppearance = _navAppearanceBlur;
        nav.navigationBar.tintColor = [ThemeEngine accent];
        nav.navigationBar.prefersLargeTitles = NO;
        active.viewController = nav;
    }

    [self addChildViewController:nav];
    nav.view.frame = self.view.bounds;
    [self.view addSubview:nav.view];
    [nav didMoveToParentViewController:self];
    self.currentContentController = nav;
}

- (void)showTabSwitcher {
    TabInfo *active = [[TabManager sharedManager] activeTab];
    if (active && self.currentContentController) {
        // iOS 17+: UIGraphicsImageRenderer replaces deprecated UIGraphicsBeginImageContextWithOptions
        UIGraphicsImageRenderer *_renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:self.view.bounds];
        active.screenshot = [_renderer imageWithActions:^(UIGraphicsImageRendererContext *_ctx) {
            [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
        }];
        if (active.type == TabTypeWebBrowser) {
            UINavigationController *nav = (UINavigationController *)self.currentContentController;
            WebBrowserViewController *webVC = (WebBrowserViewController *)nav.topViewController;
            if ([webVC isKindOfClass:[WebBrowserViewController class]]) {
                active.currentPath = webVC.webView.URL.absoluteString;
            }
        }
    }

    TabSwitcherViewController *switcher = [[TabSwitcherViewController alloc] init];
    switcher.modalPresentationStyle = UIModalPresentationFullScreen;
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


- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([self.currentContentController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)self.currentContentController;
        return nav.viewControllers.count > 1;
    }
    return NO;
}


- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionWeb: {
            [[TabManager sharedManager] addNewTabWithType:TabTypeWebBrowser path:@"about:blank"];
            [self displayActiveTab];
            break;
        }
        case BottomMenuActionTabs: {
            [self showTabSwitcher];
            break;
        }
        case BottomMenuActionIdevice: {
            dispatch_async(dispatch_get_main_queue(), ^{
                TabInfo *active = [[TabManager sharedManager] activeTab];
                if (active && [active.viewController isKindOfClass:[UINavigationController class]]) {
                    UINavigationController *nav = (UINavigationController *)active.viewController;
                    IdeviceViewController *ideviceVC = [[IdeviceViewController alloc] init];
                    [nav pushViewController:ideviceVC animated:YES];
                }
            });
            break;
        }
        default: break;
    }
}


- (void)refreshUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.view.backgroundColor = [ThemeEngine bg];
        [self displayActiveTab];
    });
}

@end
