#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, BottomMenuAction) {
    BottomMenuActionTabs,
    BottomMenuActionFavorites,
    BottomMenuActionSettings,
    BottomMenuActionOthers,
    BottomMenuActionWeb, BottomMenuActionIdevice,
    // Web specific actions
    BottomMenuActionWebBack,
    BottomMenuActionWebForward,
    BottomMenuActionWebShare,
    BottomMenuActionWebHome,
    BottomMenuActionDownloads
};

typedef NS_ENUM(NSInteger, BottomMenuMode) {
    BottomMenuModeFiles,
    BottomMenuModeWeb
};

@interface BottomMenuView : UIView
@property (copy, nonatomic) void (^onAction)(BottomMenuAction action);
@property (assign, nonatomic) BottomMenuMode mode;
- (instancetype)initWithMode:(BottomMenuMode)mode;
- (void)setupUI;
@end
