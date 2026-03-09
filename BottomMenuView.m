#import "BottomMenuView.h"
#import "ThemeEngine.h"

@interface BottomMenuView ()
@property (strong, nonatomic) UIStackView *stackView;


@end

@implementation BottomMenuView

- (instancetype)initWithMode:(BottomMenuMode)mode {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _mode = mode;
        [self setupUI];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setupUI) name:@"SettingsChanged" object:nil];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithMode:BottomMenuModeFiles];
}

- (void)setupUI {
    // Standardize background to Liquid Glass style
    [ThemeEngine applyGlassStyleToView:self cornerRadius:0];

    // Remove existing subviews if any (for dynamic mode switching if needed)
    for (UIView *v in self.subviews) if (v != self.stackView) [v removeFromSuperview];
    [self.stackView removeFromSuperview];

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

    if (self.mode == BottomMenuModeWeb) {
        [self addButtonWithSystemImage:@"chevron.left" action:BottomMenuActionWebBack];
        [self addButtonWithSystemImage:@"chevron.right" action:BottomMenuActionWebForward];
        [self addButtonWithSystemImage:@"house" action:BottomMenuActionWebHome];
        [self addButtonWithSystemImage:@"square.on.square" action:BottomMenuActionTabs];
        [self addButtonWithSystemImage:@"arrow.down.circle" action:BottomMenuActionDownloads];
    } else {
        [self addButtonWithSystemImage:@"square.on.square" action:BottomMenuActionTabs];
        [self addButtonWithSystemImage:@"globe" action:BottomMenuActionWeb];
        [self addButtonWithSystemImage:@"star" action:BottomMenuActionFavorites];
        [self addButtonWithSystemImage:@"gear" action:BottomMenuActionSettings];
        [self addButtonWithSystemImage:@"ellipsis.circle" action:BottomMenuActionOthers];
        [self addButtonWithSystemImage:@"iphone" action:BottomMenuActionIdevice];
    }
}

- (void)addButtonWithSystemImage:(NSString *)imgName action:(BottomMenuAction)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImage *img = [UIImage systemImageNamed:imgName withConfiguration:config];
    [btn setImage:img forState:UIControlStateNormal];
    btn.tintColor = [ThemeEngine liquidColor];
    btn.tag = action;
    [btn addTarget:self action:@selector(btnTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.stackView addArrangedSubview:btn];
}

- (void)btnTapped:(UIButton *)sender {
    if (self.onAction) self.onAction(sender.tag);
}



- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self];  }

@end