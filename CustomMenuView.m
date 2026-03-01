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

@interface CustomMenuView ()
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) NSMutableArray<CustomMenuAction *> *actions;
@property (nonatomic, strong) UIView *backgroundDimmer;
@end

@implementation CustomMenuView

+ (instancetype)menuWithTitle:(NSString *)title {
    CustomMenuView *m = [[CustomMenuView alloc] initWithFrame:CGRectZero];
    m.menuTitle = title;
    m.actions = [NSMutableArray array];
    return m;
}

- (void)setupUI {
    // Determine screen bounds from window context
    CGRect screenBounds = self.window.windowScene.screen.bounds;
    if (CGRectIsEmpty(screenBounds)) screenBounds = [UIScreen mainScreen].bounds; // Fallback if necessary but it will be deprecated

    self.frame = screenBounds;

    self.backgroundDimmer = [[UIView alloc] initWithFrame:self.bounds];
    self.backgroundDimmer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    self.backgroundDimmer.alpha = 0;
    [self addSubview:self.backgroundDimmer];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [self.backgroundDimmer addGestureRecognizer:tap];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.contentView cornerRadius:25];
    [self addSubview:self.contentView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = self.menuTitle;
    titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    [self.contentView addSubview:titleLabel];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 10;
    self.stackView.distribution = UIStackViewDistributionFillProportionally;
    [self.contentView addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.85],
        [self.contentView.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor multiplier:0.8],

        [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:25],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.stackView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:20],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-20],
    ]];

    self.contentView.alpha = 0;
    self.contentView.transform = CGAffineTransformMakeScale(0.8, 0.8);
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

    // Add buttons to stack view here
    for (NSInteger i = 0; i < self.actions.count; i++) {
        CustomMenuAction *action = self.actions[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
        btn.layer.cornerRadius = 14;

        btn.titleLabel.numberOfLines = 0;
        btn.titleLabel.textAlignment = NSTextAlignmentCenter;

        NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:action.title attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: (action.style == CustomMenuActionStyleDestructive) ? [UIColor systemRedColor] : [UIColor whiteColor]
        }];
        [btn setAttributedTitle:str forState:UIControlStateNormal];

        if (action.systemImageName) {
            UIImage *img = [UIImage systemImageNamed:action.systemImageName];
            [btn setImage:img forState:UIControlStateNormal];
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.imagePadding = 12;
            config.contentInsets = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
            config.imagePlacement = NSDirectionalRectEdgeLeading;
            btn.configuration = config;
        } else {
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.contentInsets = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
            btn.configuration = config;
        }

        btn.tintColor = (action.style == CustomMenuActionStyleDestructive) ? [UIColor systemRedColor] : [UIColor whiteColor];
        [btn addTarget:self action:@selector(btnTapped:) forControlEvents:UIControlEventTouchUpInside];
        btn.tag = i;

        [self.stackView addArrangedSubview:btn];
        [btn.heightAnchor constraintGreaterThanOrEqualToConstant:54].active = YES;
    }

    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.4 options:0 animations:^{
        self.backgroundDimmer.alpha = 1.0;
        self.contentView.alpha = 1.0;
        self.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    [self dismissWithCompletion:nil];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    [UIView animateWithDuration:0.25 animations:^{
        self.backgroundDimmer.alpha = 0;
        self.contentView.alpha = 0;
        self.contentView.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

@end
