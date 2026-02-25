#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, BottomMenuAction) {
    BottomMenuActionTabs,
    BottomMenuActionFavorites,
    BottomMenuActionSettings,
    BottomMenuActionOthers
};

@interface BottomMenuView : UIView

@property (copy, nonatomic) void (^onAction)(BottomMenuAction action);

@end
