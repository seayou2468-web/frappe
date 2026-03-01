#import "ThemeEngine.h"



@implementation ThemeEngine

+ (UIColor *)mainBackgroundColor {
    return [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0]; // Dark theme
}

+ (UIColor *)liquidColor {
    return [UIColor colorWithRed:0.18 green:0.18 blue:0.20 alpha:1.0];
}

+ (void)applyLiquidStyleToView:(UIView *)view cornerRadius:(CGFloat)radius {
    view.backgroundColor = [self liquidColor];
    view.layer.cornerRadius = radius;

    // Outer shadow
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOffset = CGSizeMake(4, 4);
    view.layer.shadowOpacity = 0.5;
    view.layer.shadowRadius = 8;

    // Inner shadow is harder with just layers, often requires extra layers or drawing
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

@end

@implementation LiquidGlassView {
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
    self.backgroundColor = [ThemeEngine liquidColor];
    self.layer.cornerRadius = _cornerRadius;

    // Outer Shadow
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(6, 6);
    self.layer.shadowOpacity = 0.4;
    self.layer.shadowRadius = 10;

    // Inner Shadow Layers
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

    // Top Inner Shadow (Highlight)
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

    // Bottom Inner Shadow (Dark)
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

