#import "MainContainerViewController.h"
#import "TabManager.h"
#import "TabSwitcherViewController.h"
#import "FileBrowserViewController.h"
#import "WebBrowserViewController.h"
#import "ThemeEngine.h"



@interface MainContainerViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIViewController *currentContentController;


@end

@implementation MainContainerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

        if ([TabManager sharedManager].tabs.count == 0) {
        NSString *startPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultStartPath"] ?: NSHomeDirectory();
        [[TabManager sharedManager] addNewTabWithType:TabTypeFileBrowser path:startPath];
    }
    [self displayActiveTab];
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
        nav.navigationBar.barStyle = UIBarStyleBlack;
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
        UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, YES, 0);
        [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
        active.screenshot = UIGraphicsGetImageFromCurrentImageContext();
        if (active.type == TabTypeWebBrowser) {
            UINavigationController *nav = (UINavigationController *)self.currentContentController;
            WebBrowserViewController *webVC = (WebBrowserViewController *)nav.topViewController;
            if ([webVC isKindOfClass:[WebBrowserViewController class]]) {
                active.currentPath = webVC.webView.URL.absoluteString;
            }
        }
        UIGraphicsEndImageContext();
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
            [[TabManager sharedManager] addNewTabWithType:TabTypeWebBrowser path:@"https://www.google.com"];
            [self displayActiveTab];
            break;
        }
        case BottomMenuActionTabs: {
            [self showTabSwitcher];
            break;
        }
        default: break;
    }
}

@end

