#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BottomMenuAction) {
    BottomMenuActionTabs,
    BottomMenuActionFavorites,
    BottomMenuActionSettings,
    BottomMenuActionOthers
};

@interface BottomMenuView : UIView

@property (copy, nonatomic, _Nullable) void (^onAction)(BottomMenuAction action);

@end

NS_ASSUME_NONNULL_END
