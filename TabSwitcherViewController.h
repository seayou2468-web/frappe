#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TabSwitcherViewController : UIViewController <UICollectionViewDelegate, UICollectionViewDataSource>
@property (nonatomic, copy, _Nullable) void (^onTabSelected)(NSInteger index);
@property (nonatomic, copy, _Nullable) void (^onNewTabRequested)(void);
@end

NS_ASSUME_NONNULL_END
