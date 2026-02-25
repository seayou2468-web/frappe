#import "BottomMenuView.h"
#import "ThemeEngine.h"

NS_ASSUME_NONNULL_BEGIN

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

    // Use safe area for bottom padding
    UILayoutGuide *safe = self.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.stackView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
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
    btn.titleLabel.font = [UIFont systemFontOfSize:10];

    btn.configuration = [UIButtonConfiguration plainButtonConfiguration];
    btn.configuration.imagePlacement = NSDirectionalRectEdgeTop;
    btn.configuration.imagePadding = 5;

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

NS_ASSUME_NONNULL_END
