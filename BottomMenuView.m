#import "BottomMenuView.h"

@interface BottomMenuView ()
@property (strong, nonatomic) UIVisualEffectView *glassView;
@property (strong, nonatomic) UIStackView *stackView;
@end

@implementation BottomMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.glassView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    self.glassView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    self.glassView.layer.borderWidth = 1.0;
    self.glassView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.glassView];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisHorizontal;
    self.stackView.distribution = UIStackViewDistributionFillEqually;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    [self.glassView.contentView addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:self.glassView.contentView.topAnchor],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.glassView.contentView.bottomAnchor],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.glassView.contentView.leadingAnchor],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.glassView.contentView.trailingAnchor],
    ]];

    [self addButtonWithTitle:@"Tabs" action:BottomMenuActionTabs];
    [self addButtonWithTitle:@"Favs" action:BottomMenuActionFavorites];
    [self addButtonWithTitle:@"Set" action:BottomMenuActionSettings];
    [self addButtonWithTitle:@"Other" action:BottomMenuActionOthers];
}

- (void)addButtonWithTitle:(NSString *)title action:(BottomMenuAction)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.tag = action;
    [btn addTarget:self action:@selector(btnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.stackView addArrangedSubview:btn];
}

- (void)btnTapped:(UIButton *)sender {
    if (self.onAction) {
        self.onAction(sender.tag);
    }
}

@end
