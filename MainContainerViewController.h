#import <UIKit/UIKit.h>



#import "BottomMenuView.h"
@interface MainContainerViewController : UIViewController
- (void)showTabSwitcher;
- (void)displayActiveTab;
- (void)handleMenuAction:(BottomMenuAction)action;
@end

