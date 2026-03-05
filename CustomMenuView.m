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

@interface CustomMenuView () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) NSMutableArray<CustomMenuAction *> *actions;
@property (nonatomic, strong) UIView *backgroundDimmer;
@property (nonatomic, strong) NSLayoutConstraint *contentBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentHeightConstraint;
@property (nonatomic, assign) CGPoint panStartPoint;
@property (nonatomic, assign) CGFloat neutralHeight;
@property (nonatomic, strong) UIView *bottomExtension;
@property (nonatomic, assign) BOOL isExpanded;
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
    self.backgroundDimmer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.backgroundDimmer.alpha = 0;
    [self addSubview:self.backgroundDimmer];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [self.backgroundDimmer addGestureRecognizer:tap];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.contentView cornerRadius:30];
    self.contentView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.contentView.clipsToBounds = YES;
    [self addSubview:self.contentView];

    self.bottomExtension = [[UIView alloc] init];
    self.bottomExtension.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomExtension.backgroundColor = [[UIColor colorWithRed:0.08 green:0.08 blue:0.1 alpha:1.0] colorWithAlphaComponent:0.95];
    [self insertSubview:self.bottomExtension belowSubview:self.contentView];

    UIView *grabber = [[UIView alloc] init];
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4];
    grabber.layer.cornerRadius = 2.5;
    [self.contentView addSubview:grabber];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = self.menuTitle;
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    [self.contentView addSubview:titleLabel];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.delegate = self;
    [self.contentView addSubview:self.scrollView];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 1;
    self.stackView.distribution = UIStackViewDistributionFill;
    [self.scrollView addSubview:self.stackView];

    self.contentBottomConstraint = [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:1000];
    self.contentHeightConstraint = [self.contentView.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        self.contentBottomConstraint,
        self.contentHeightConstraint,
        [self.contentView.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor multiplier:0.95],

        [self.bottomExtension.topAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-30],
        [self.bottomExtension.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.bottomExtension.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.bottomExtension.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:1000],

        [grabber.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [grabber.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:36],
        [grabber.heightAnchor constraintEqualToConstant:5],

        [titleLabel.topAnchor constraintEqualToAnchor:grabber.bottomAnchor constant:10],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.scrollView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:5],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:14],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-14],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20],
        [self.stackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-28],
    ]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    [self.contentView addGestureRecognizer:pan];

    [self layoutIfNeeded];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.panStartPoint = translation;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat y = translation.y - self.panStartPoint.y;
        if (y > 0) {
            // Pulling down
            if (self.isExpanded) {
                // If expanded, reduce height first
                CGFloat newHeight = (self.frame.size.height * 0.95) - y;
                if (newHeight < self.neutralHeight) {
                    // Transition back to neutral and then drag down
                    self.contentHeightConstraint.constant = self.neutralHeight;
                    self.contentBottomConstraint.constant = y - (self.frame.size.height * 0.95 - self.neutralHeight);
                } else {
                    self.contentHeightConstraint.constant = newHeight;
                }
            } else {
                // Not expanded, drag down to dismiss
                self.contentBottomConstraint.constant = y;
                self.backgroundDimmer.alpha = 1.0 - (y / 400.0);
            }
        } else {
            // Pulling up
            CGFloat newHeight = (self.isExpanded ? self.frame.size.height * 0.95 : self.neutralHeight) - y;
            self.contentHeightConstraint.constant = MIN(newHeight, self.frame.size.height * 0.95);
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat y = translation.y - self.panStartPoint.y;
        if (!self.isExpanded && y > 150) {
            [self dismiss];
        } else {
            [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.contentBottomConstraint.constant = 0;
                if (y < -50) {
                    self.isExpanded = YES;
                    self.contentHeightConstraint.constant = self.frame.size.height * 0.95;
                } else if (y > 50 && self.isExpanded) {
                    self.isExpanded = NO;
                    self.contentHeightConstraint.constant = self.neutralHeight;
                } else {
                    self.contentHeightConstraint.constant = self.isExpanded ? self.frame.size.height * 0.95 : self.neutralHeight;
                }
                self.backgroundDimmer.alpha = 1.0;
                [self layoutIfNeeded];
            } completion:nil];
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)otherGestureRecognizer.view;
        if (sv.contentOffset.y <= 0) return YES;
    }
    return NO;
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
            NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: (action.style == CustomMenuActionStyleDestructive) ? [UIColor systemRedColor] : [UIColor whiteColor]
        }];
        [btn setAttributedTitle:str forState:UIControlStateNormal];

        if (action.systemImageName) {
            UIImage *img = [UIImage systemImageNamed:action.systemImageName];
            [btn setImage:img forState:UIControlStateNormal];
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.imagePadding = 18;
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
        [btn.heightAnchor constraintEqualToConstant:56].active = YES;

        if (i < self.actions.count - 1) {
            UIView *sep = [[UIView alloc] init];
            sep.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
            [self.stackView addArrangedSubview:sep];
            [sep.heightAnchor constraintEqualToConstant:0.5].active = YES;
        }
    }

    [self layoutIfNeeded];
    CGFloat contentSizeHeight = self.stackView.frame.size.height + 150;
    self.neutralHeight = MIN(contentSizeHeight, self.frame.size.height * 0.75);
    self.contentHeightConstraint.constant = self.neutralHeight;
    [self layoutIfNeeded];

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.backgroundDimmer.alpha = 1.0;
        self.contentBottomConstraint.constant = 0;
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)dismiss {
    [self dismissWithCompletion:nil];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.backgroundDimmer.alpha = 0;
        self.contentBottomConstraint.constant = 1000;
        [self layoutIfNeeded];
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

@end
