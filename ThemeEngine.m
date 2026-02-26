#import "ThemeEngine.h"

@implementation ThemeEngine

+ (UIColor *)mainBackgroundColor {
    return [UIColor colorWithRed:0.05 green:0.05 blue:0.07 alpha:1.0]; // Deeper dark
}

+ (UIColor *)clayColor {
    return [UIColor colorWithRed:0.18 green:0.18 blue:0.20 alpha:1.0];
}

+ (void)applyClayStyleToView:(UIView *)view cornerRadius:(CGFloat)radius {
    view.backgroundColor = [self clayColor];
    view.layer.cornerRadius = radius;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOffset = CGSizeMake(4, 4);
    view.layer.shadowOpacity = 0.5;
    view.layer.shadowRadius = 8;
}

+ (void)applyGlassStyleToView:(UIView *)view cornerRadius:(CGFloat)radius {
    view.backgroundColor = [UIColor clearColor];
    UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    blurEffectView.frame = view.bounds;
    blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurEffectView.layer.cornerRadius = radius;
    blurEffectView.clipsToBounds = YES;
    [view insertSubview:blurEffectView atIndex:0];

    view.layer.cornerRadius = radius;
    view.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    view.layer.borderWidth = 0.5;
}

+ (void)applyLiquidGlassStyleToView:(UIView *)view cornerRadius:(CGFloat)radius {
    view.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];

    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurEffectView.frame = view.bounds;
    blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurEffectView.layer.cornerRadius = radius;
    blurEffectView.clipsToBounds = YES;
    [view insertSubview:blurEffectView atIndex:0];

    view.layer.cornerRadius = radius;
    view.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    view.layer.borderWidth = 0.3; // Thinner for Liquidglass

    // Soft shadow
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOffset = CGSizeMake(0, 8);
    view.layer.shadowOpacity = 0.3;
    view.layer.shadowRadius = 15;
    view.layer.masksToBounds = NO;
}

@end

@implementation ClayView {
    CAShapeLayer *_innerShadowTop;
    CAShapeLayer *_innerShadowBottom;
}

- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius {
    self = [super initWithFrame:frame];
    if (self) {
        _cornerRadius = radius;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [ThemeEngine clayColor];
    self.layer.cornerRadius = _cornerRadius;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(6, 6);
    self.layer.shadowOpacity = 0.4;
    self.layer.shadowRadius = 10;
    _innerShadowTop = [CAShapeLayer layer];
    _innerShadowBottom = [CAShapeLayer layer];
    [self.layer addSublayer:_innerShadowTop];
    [self.layer addSublayer:_innerShadowBottom];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateInnerShadows];
}

- (void)updateInnerShadows {
    CGRect rect = self.bounds;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:_cornerRadius];
    UIBezierPath *topPath = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, -5, -5) cornerRadius:_cornerRadius];
    [topPath appendPath:path];
    topPath.usesEvenOddFillRule = YES;
    _innerShadowTop.path = topPath.CGPath;
    _innerShadowTop.fillRule = kCAFillRuleEvenOdd;
    _innerShadowTop.fillColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
    _innerShadowTop.shadowColor = [UIColor whiteColor].CGColor;
    _innerShadowTop.shadowOffset = CGSizeMake(-4, -4);
    _innerShadowTop.shadowOpacity = 0.5;
    _innerShadowTop.shadowRadius = 4;
    _innerShadowTop.masksToBounds = YES;
    _innerShadowTop.frame = rect;
    UIBezierPath *bottomPath = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, -5, -5) cornerRadius:_cornerRadius];
    [bottomPath appendPath:path];
    bottomPath.usesEvenOddFillRule = YES;
    _innerShadowBottom.path = bottomPath.CGPath;
    _innerShadowBottom.fillRule = kCAFillRuleEvenOdd;
    _innerShadowBottom.fillColor = [[UIColor blackColor] colorWithAlphaComponent:0.1].CGColor;
    _innerShadowBottom.shadowColor = [UIColor blackColor].CGColor;
    _innerShadowBottom.shadowOffset = CGSizeMake(4, 4);
    _innerShadowBottom.shadowOpacity = 0.8;
    _innerShadowBottom.shadowRadius = 6;
    _innerShadowBottom.masksToBounds = YES;
    _innerShadowBottom.frame = rect;
}

@end
