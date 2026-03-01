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
    CustomMenuView *m = [[CustomMenuView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    m.menuTitle = title;
    m.actions = [NSMutableArray array];
    [m setupUI];
    return m;
}

- (void)setupUI {
    self.backgroundDimmer = [[UIView alloc] initWithFrame:self.bounds];
    self.backgroundDimmer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
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
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:titleLabel];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 2;
    self.stackView.distribution = UIStackViewDistributionFillEqually;
    [self.contentView addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-20],

        [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:15],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],

        [self.stackView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:15],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
    ]];

    self.contentView.transform = CGAffineTransformMakeTranslation(0, 400);
}

- (void)addAction:(CustomMenuAction *)action {
    [self.actions addObject:action];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    btn.layer.cornerRadius = 12;
    btn.tintColor = (action.style == CustomMenuActionStyleDestructive) ? [UIColor systemRedColor] : [UIColor whiteColor];

    NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:action.title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17]}];
    [btn setAttributedTitle:str forState:UIControlStateNormal];

    if (action.systemImageName) {
        UIImage *img = [UIImage systemImageNamed:action.systemImageName];
        [btn setImage:img forState:UIControlStateNormal];
        btn.configuration = [UIButtonConfiguration plainButtonConfiguration];
        btn.configuration.imagePadding = 10;
        btn.configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 12, 12, 12);
    }

    [btn addTarget:self action:@selector(btnTapped:) forControlEvents:UIControlEventTouchUpInside];
    btn.tag = self.actions.count - 1;

    [self.stackView addArrangedSubview:btn];
    [btn.heightAnchor constraintEqualToConstant:50].active = YES;
}

- (void)btnTapped:(UIButton *)sender {
    CustomMenuAction *a = self.actions[sender.tag];
    [self dismissWithCompletion:^{
        if (a.handler) a.handler();
    }];
}

- (void)showInView:(UIView *)view {
    [view addSubview:self];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        self.backgroundDimmer.alpha = 1.0;
        self.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    [self dismissWithCompletion:nil];
}

- (void)dismissWithCompletion:(void (^)(void))completion {
    [UIView animateWithDuration:0.3 animations:^{
        self.backgroundDimmer.alpha = 0;
        self.contentView.transform = CGAffineTransformMakeTranslation(0, 500);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        if (completion) completion();
    }];
}

@end
