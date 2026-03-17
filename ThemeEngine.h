#import <UIKit/UIKit.h>

#define kCornerS   10.0f
#define kCornerM   16.0f
#define kCornerL   24.0f
#define kCornerXL  32.0f
#define kSpaceXS   4.0f
#define kSpaceS    8.0f
#define kSpaceM    14.0f
#define kSpaceL    20.0f

@interface ThemeEngine : NSObject
+ (UIColor *)bg;
+ (UIColor *)surface;
+ (UIColor *)surfaceHigh;
+ (UIColor *)border;
+ (UIColor *)accent;
+ (UIColor *)textPrimary;
+ (UIColor *)textSecondary;
+ (UIColor *)textTertiary;
+ (UIColor *)tintForExtension:(NSString *)ext;
+ (NSString *)symbolForExtension:(NSString *)ext;
+ (UIColor *)tintForFolder;
+ (void)applyGlassToView:(UIView *)view radius:(CGFloat)radius;
+ (UIVisualEffectView *)makeBlurView:(UIBlurEffectStyle)style radius:(CGFloat)r;
+ (UIFont *)fontTitle;
+ (UIFont *)fontHeadline;
+ (UIFont *)fontBody;
+ (UIFont *)fontSubhead;
+ (UIFont *)fontCaption;
+ (UIFont *)fontMono;

// Legacy compat
+ (UIColor *)mainBackgroundColor;
+ (UIColor *)liquidColor;
+ (void)applyLiquidStyleToView:(UIView *)view cornerRadius:(CGFloat)radius;
+ (void)applyGlassStyleToView:(UIView *)view cornerRadius:(CGFloat)radius;
@end

@interface LiquidGlassView : UIView
@property (nonatomic, assign) CGFloat cornerRadius;
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius;
@end
