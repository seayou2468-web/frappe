#import "CustomMenuView.h"
#import "ThemeEngine.h"

@implementation CustomMenuAction
+ (instancetype)actionWithTitle:(NSString *)title systemImage:(NSString *)image style:(CustomMenuActionStyle)style handler:(void (^)(void))handler {
    CustomMenuAction *a = [[CustomMenuAction alloc] init];
    a.title = title;
    a.systemImageName = image;
    a.style = style;
    a.handler = handler;
    return a;
}
@end

@interface CustomMenuView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) NSMutableArray<CustomMenuAction *> *actions;
@property (nonatomic, strong) UIView *backgroundDimmer;
@property (nonatomic, strong) NSLayoutConstraint *contentBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentHeightConstraint;
@property (nonatomic, assign) CGPoint panStartPoint;
@property (nonatomic, assign) CGFloat initialHeight;
@end

@implementation CustomMenuView

+ (instancetype)menuWithTitle:(NSString *)title {
    CustomMenuView *m = [[CustomMenuView alloc] initWithFrame:CGRectZero];
    m.menuTitle = title;
    m.actions = [NSMutableArray array];
    return m;
}

- (void)setupUI {
    CGRect screenBounds = CGRectZero;
    UIWindow *window = self.window ?: self.superview.window;
    if (window.windowScene) {
        screenBounds = window.windowScene.screen.bounds;
    }

    if (CGRectIsEmpty(screenBounds)) {
        screenBounds = self.superview ? self.superview.bounds : CGRectMake(0, 0, 393, 852);
    }

    self.frame = screenBounds;

    self.backgroundDimmer = [[UIView alloc] initWithFrame:self.bounds];
    self.backgroundDimmer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    self.backgroundDimmer.alpha = 0;
    [self addSubview:self.backgroundDimmer];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [self.backgroundDimmer addGestureRecognizer:tap];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.contentView cornerRadius:25];
    self.contentView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.contentView.clipsToBounds = YES;
    [self addSubview:self.contentView];

    for (UIView *subview in self.contentView.subviews) {
        if ([subview isKindOfClass:[UIVisualEffectView class]]) {
            subview.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
            subview.layer.cornerRadius = 25;
            subview.clipsToBounds = YES;
        }
    }

    UIView *grabber = [[UIView alloc] init];
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3];
    grabber.layer.cornerRadius = 2.5;
    [self.contentView addSubview:grabber];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = self.menuTitle;
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    [self.contentView addSubview:titleLabel];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 2;
    self.stackView.distribution = UIStackViewDistributionFill;
    [self.contentView addSubview:self.stackView];

    self.contentBottomConstraint = [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:800];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        self.contentBottomConstraint,
        [self.contentView.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor multiplier:0.95],

        [grabber.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [grabber.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:36],
        [grabber.heightAnchor constraintEqualToConstant:5],

        [titleLabel.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:10],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.stackView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-15],
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.contentView addGestureRecognizer:pan];

    [self layoutIfNeeded];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.panStartPoint = translation;
        self.initialHeight = self.contentView.frame.size.height;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat y = translation.y - self.panStartPoint.y;
        if (y > 0) {
            // Drag down to dismiss
            self.contentBottomConstraint.constant = y;
            self.backgroundDimmer.alpha = 1.0 - (y / 300.0);
        } else {
            // Pull up to expand
            CGFloat resistance = 0.3; // Elastic feel
            self.contentBottomConstraint.constant = y * resistance;
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat y = translation.y - self.panStartPoint.y;
        if (y > 100) {
            [self dismiss];
        } else {
            [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.contentBottomConstraint.constant = 0;
                self.backgroundDimmer.alpha = 1.0;
                [self layoutIfNeeded];
            } completion:nil];
        }
    }
}

- (void)addAction:(CustomMenuAction *)action {
    [self.actions addObject:action];
}

- (void)btnTapped:(UIButton *)sender {
    CustomMenuAction *a = self.actions[sender.tag];
    [self dismissWithCompletion:^{
        if (a.handler) a.handler();
    }];
}

- (void)showInView:(UIView *)view {
    [view addSubview:self];
    [self setupUI];

    for (NSInteger i = 0; i < self.actions.count; i++) {
        CustomMenuAction *action = self.actions[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.backgroundColor = [UIColor clearColor];
        btn.translatesAutoresizingMaskIntoConstraints = NO;

        NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:action.title attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:18 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: (action.style == CustomMenuActionStyleDestructive) ? [UIColor systemRedColor] : [UIColor whiteColor]
        }];
        [btn setAttributedTitle:str forState:UIControlStateNormal];

        if (action.systemImageName) {
            UIImage *img = [UIImage systemImageNamed:action.systemImageName];
            [btn setImage:img forState:UIControlStateNormal];
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.imagePadding = 16;
            config.contentInsets = NSDirectionalEdgeInsetsMake(0, 16, 0, 16);
            config.imagePlacement = NSDirectionalRectEdgeLeading;
            btn.configuration = config;
        } else {
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.contentInsets = NSDirectionalEdgeInsetsMake(0, 16, 0, 16);
            btn.configuration = config;
        }

        btn.tintColor = (action.style == CustomMenuActionStyleDestructive) ? [UIColor systemRedColor] : [UIColor whiteColor];
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [btn addTarget:self action:@selector(btnTapped:) forControlEvents:UIControlEventTouchUpInside];
        btn.tag = i;

        [self.stackView addArrangedSubview:btn];
        [btn.heightAnchor constraintEqualToConstant:54].active = YES;

        if (i < self.actions.count - 1) {
            UIView *sep = [[UIView alloc] init];
            sep.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
            [self.stackView addArrangedSubview:sep];
            [sep.heightAnchor constraintEqualToConstant:0.5].active = YES;
        }
    }

    [self layoutIfNeeded];

    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.backgroundDimmer.alpha = 1.0;
        self.contentBottomConstraint.constant = 0;
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)dismiss {
    [self dismissWithCompletion:nil];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.backgroundDimmer.alpha = 0;
        self.contentBottomConstraint.constant = 800;
        [self layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

@end
