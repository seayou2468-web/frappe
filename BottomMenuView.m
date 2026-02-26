#import "BottomMenuView.h"
#import "ThemeEngine.h"

@interface BottomMenuView ()
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
    [ThemeEngine applyLiquidGlassStyleToView:self cornerRadius:30];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisHorizontal;
    self.stackView.distribution = UIStackViewDistributionFillEqually;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    [self addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
    ]];

    [self addButtonWithTitle:@"Tabs" systemImage:@"square.on.square" action:BottomMenuActionTabs];
    [self addButtonWithTitle:@"Favs" systemImage:@"star" action:BottomMenuActionFavorites];
    [self addButtonWithTitle:@"Set" systemImage:@"gear" action:BottomMenuActionSettings];
    [self addButtonWithTitle:@"Other" systemImage:@"ellipsis.circle" action:BottomMenuActionOthers];
}

- (void)addButtonWithTitle:(NSString *)title systemImage:(NSString *)imgName action:(BottomMenuAction)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];

    UIImage *img = [UIImage systemImageNamed:imgName];
    [btn setImage:img forState:UIControlStateNormal];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];
    btn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];

    btn.configuration = [UIButtonConfiguration plainButtonConfiguration];
    btn.configuration.imagePlacement = NSDirectionalRectEdgeTop;
    btn.configuration.imagePadding = 4;
    btn.configuration.baseForegroundColor = [UIColor whiteColor];

    btn.tag = action;
    [btn addTarget:self action:@selector(btnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.stackView addArrangedSubview:btn];
}

- (void)btnTapped:(UIButton *)sender {
    if (self.onAction) {
        self.onAction(sender.tag);
    }
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 70);
}

@end