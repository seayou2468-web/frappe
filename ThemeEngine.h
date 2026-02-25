#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ThemeEngine : NSObject
+ (UIColor *)mainBackgroundColor;
+ (UIColor *)clayColor;
+ (void)applyClayStyleToView:(UIView *)view cornerRadius:(CGFloat)radius;
+ (void)applyGlassStyleToView:(UIView *)view cornerRadius:(CGFloat)radius;
@end

@interface ClayView : UIView
@property (nonatomic, assign) CGFloat cornerRadius;
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius;
@end

NS_ASSUME_NONNULL_END
