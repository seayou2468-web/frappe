#import "MainContainerViewController.h"
#import "TabManager.h"
#import "TabSwitcherViewController.h"
#import "FileBrowserViewController.h"
#import "ThemeEngine.h"

@interface MainContainerViewController ()
@property (nonatomic, strong) UIViewController *currentContentController;
@end

@implementation MainContainerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    if ([TabManager sharedManager].tabs.count == 0) {
        [[TabManager sharedManager] addNewTabWithType:TabTypeFileBrowser path:@"/"];
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
    nav.navigationBar.barStyle = UIBarStyleBlack;

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

@end
