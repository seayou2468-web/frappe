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
    [ThemeEngine applyGlassStyleToView:self cornerRadius:0];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisHorizontal;
    self.stackView.distribution = UIStackViewDistributionFillEqually;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    [self addSubview:self.stackView];

    UILayoutGuide *safe = self.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.stackView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    [self addButtonWithSystemImage:@"square.on.square" action:BottomMenuActionTabs];
    [self addButtonWithSystemImage:@"star" action:BottomMenuActionFavorites];
    [self addButtonWithSystemImage:@"gear" action:BottomMenuActionSettings];
    [self addButtonWithSystemImage:@"ellipsis.circle" action:BottomMenuActionOthers];
}

- (void)addButtonWithSystemImage:(NSString *)imgName action:(BottomMenuAction)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium];
    UIImage *img = [UIImage systemImageNamed:imgName withConfiguration:config];
    [btn setImage:img forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];

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
