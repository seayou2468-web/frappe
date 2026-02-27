#import <UIKit/UIKit.h>



@interface TabSwitcherViewController : UIViewController <UICollectionViewDelegate, UICollectionViewDataSource>
@property (nonatomic, copy) void (^onTabSelected)(NSInteger index);
@property (nonatomic, copy) void (^onNewTabRequested)(void);
@end

