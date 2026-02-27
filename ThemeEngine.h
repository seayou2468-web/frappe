#import <UIKit/UIKit.h>



@interface ThemeEngine : NSObject
+ (UIColor *)mainBackgroundColor;
+ (UIColor *)liquidColor;
+ (void)applyLiquidStyleToView:(UIView *)view cornerRadius:(CGFloat)radius;
+ (void)applyGlassStyleToView:(UIView *)view cornerRadius:(CGFloat)radius;
@end

@interface LiquidGlassView : UIView
@property (nonatomic, assign) CGFloat cornerRadius;
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius;
@end

