#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, CustomMenuActionStyle) {
    CustomMenuActionStyleDefault,
    CustomMenuActionStyleDestructive,
    CustomMenuActionStyleCancel
};

@interface CustomMenuAction : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *systemImageName;
@property (nonatomic, assign) CustomMenuActionStyle style;
@property (nonatomic, copy) void (^handler)(void);

+ (instancetype)actionWithTitle:(NSString *)title systemImage:(NSString *)image style:(CustomMenuActionStyle)style handler:(void (^)(void))handler;
@end

@interface CustomMenuView : UIView

@property (nonatomic, copy) NSString *menuTitle;

+ (instancetype)menuWithTitle:(NSString *)title;
- (void)addAction:(CustomMenuAction *)action;
- (void)showInView:(UIView *)view;
- (void)dismiss;

@end
