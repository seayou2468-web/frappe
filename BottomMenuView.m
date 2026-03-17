#import "BottomMenuView.h"
#import "ThemeEngine.h"

// ─── Tab Item Model ───────────────────────────────────────────────────────────
@interface TabItemView : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, assign) BottomMenuAction action;
@property (nonatomic, assign) BOOL isActive;
- (instancetype)initWithSymbol:(NSString *)sym action:(BottomMenuAction)action;
- (void)setActive:(BOOL)active animated:(BOOL)animated;
@end

@implementation TabItemView
- (instancetype)initWithSymbol:(NSString *)sym action:(BottomMenuAction)act {
    self = [super init];
    if (!self) return nil;
    _action = act;

    _iconView = [[UIImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_iconView];
    [NSLayoutConstraint activateConstraints:@[
        [_iconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:22],
        [_iconView.heightAnchor constraintEqualToConstant:22],
    ]];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:20
                                                        weight:UIImageSymbolWeightMedium];
    _iconView.image = [UIImage systemImageNamed:sym withConfiguration:cfg];
    _iconView.tintColor = [ThemeEngine textTertiary];

    return self;
}

- (void)setActive:(BOOL)active animated:(BOOL)animated {
    _isActive = active;
    void (^upd)(void) = ^{
        UIColor *tint = active ? [ThemeEngine accent] : [ThemeEngine textTertiary];
        self.iconView.tintColor = tint;
        self.transform = active ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformIdentity;
    };
    if (animated) {
        [UIView animateWithDuration:0.3
                              delay:0
             usingSpringWithDamping:0.65
              initialSpringVelocity:0.8
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:upd
                         completion:nil];
    } else { upd(); }
}

- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesBegan:t withEvent:e];
    [UIView animateWithDuration:0.12 animations:^{ self.transform = CGAffineTransformMakeScale(0.85, 0.85); }];
}
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesEnded:t withEvent:e];
    [UIView animateWithDuration:0.3
                          delay:0
         usingSpringWithDamping:0.55
          initialSpringVelocity:1.2
                        options:0
                     animations:^{ self.transform = CGAffineTransformIdentity; }
                     completion:nil];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e {
    [super touchesCancelled:t withEvent:e];
    [UIView animateWithDuration:0.2 animations:^{ self.transform = CGAffineTransformIdentity; }];
}
@end

// ─── BottomMenuView ───────────────────────────────────────────────────────────
@interface BottomMenuView ()
@property (strong, nonatomic) UIView *pill;
@property (strong, nonatomic) UIView *activeIndicator;
@property (strong, nonatomic) NSMutableArray<TabItemView *> *items;
@property (strong, nonatomic) NSLayoutConstraint *indicatorCX;
@end

@implementation BottomMenuView

- (instancetype)initWithMode:(BottomMenuMode)mode {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _mode = mode;
        _items = [NSMutableArray array];
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(buildUI) name:@"SettingsChanged" object:nil];
    }
    return self;
}
- (instancetype)initWithFrame:(CGRect)f { return [self initWithMode:BottomMenuModeFiles]; }

- (void)buildUI {
    // Clear
    for (UIView *v in self.subviews) [v removeFromSuperview];
    [_items removeAllObjects];

    self.backgroundColor = [UIColor clearColor];

    // ── Floating pill ──────────────────────────────────────────────────────
    _pill = [[UIView alloc] init];
    _pill.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassToView:_pill radius:kCornerXL];
    // extra shadow for depth
    _pill.layer.shadowColor = [UIColor blackColor].CGColor;
    _pill.layer.shadowOffset = CGSizeMake(0, 8);
    _pill.layer.shadowOpacity = 0.55;
    _pill.layer.shadowRadius = 20;
    [self addSubview:_pill];

    // ── Active dot indicator ───────────────────────────────────────────────
    _activeIndicator = [[UIView alloc] init];
    _activeIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _activeIndicator.backgroundColor = [ThemeEngine accent];
    _activeIndicator.layer.cornerRadius = 2.5;
    [_pill addSubview:_activeIndicator];

    // ── Build items ────────────────────────────────────────────────────────
    NSArray *defs; // [sym, @(action)]
    if (_mode == BottomMenuModeWeb) {
        defs = @[@[@"chevron.left",          @(BottomMenuActionWebBack)],
                 @[@"chevron.right",          @(BottomMenuActionWebForward)],
                 @[@"house.fill",             @(BottomMenuActionWebHome)],
                 @[@"square.on.square.fill",  @(BottomMenuActionTabs)],
                 @[@"arrow.down.circle.fill", @(BottomMenuActionDownloads)]];
    } else {
        defs = @[@[@"square.on.square",   @(BottomMenuActionTabs)],
                 @[@"globe",              @(BottomMenuActionWeb)],
                 @[@"star.fill",          @(BottomMenuActionFavorites)],
                 @[@"iphone",             @(BottomMenuActionIdevice)],
                 @[@"gearshape.fill",     @(BottomMenuActionSettings)]];
    }

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentCenter;
    [_pill addSubview:stack];

    for (NSArray *def in defs) {
        TabItemView *item = [[TabItemView alloc] initWithSymbol:def[0]
                                                         action:[def[1] integerValue]];
        item.translatesAutoresizingMaskIntoConstraints = NO;
        [item addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:item];
        [item.heightAnchor constraintEqualToConstant:54].active = YES;
        [_items addObject:item];
    }

    // First item active by default
    if (_items.count > 0) [_items.firstObject setActive:YES animated:NO];

    UILayoutGuide *safe = self.safeAreaLayoutGuide;
    _indicatorCX = [_activeIndicator.centerXAnchor
        constraintEqualToAnchor:_pill.leadingAnchor constant:0];

    [NSLayoutConstraint activateConstraints:@[
        // Pill: centered, not full-width
        [_pill.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_pill.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],
        [_pill.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor constant:-32],
        [_pill.widthAnchor constraintGreaterThanOrEqualToConstant:260],

        // Stack fills pill
        [stack.topAnchor constraintEqualToAnchor:_pill.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:_pill.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:_pill.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:_pill.trailingAnchor constant:-8],

        // Active dot
        _indicatorCX,
        [_activeIndicator.bottomAnchor constraintEqualToAnchor:_pill.bottomAnchor constant:-6],
        [_activeIndicator.widthAnchor constraintEqualToConstant:5],
        [_activeIndicator.heightAnchor constraintEqualToConstant:5],
    ]];
}

- (void)itemTapped:(TabItemView *)sender {
    // Update active states
    for (TabItemView *item in _items) {
        [item setActive:(item == sender) animated:YES];
    }
    // Animate dot to center of tapped item (within pill coordinate space)
    CGPoint centerInPill = [sender convertPoint:CGPointMake(sender.bounds.size.width / 2.0,
                                                            sender.bounds.size.height / 2.0)
                                         toView:_pill];
    _indicatorCX.constant = MAX(0, centerInPill.x);
    [UIView animateWithDuration:0.35
                          delay:0
         usingSpringWithDamping:0.65
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ [self layoutIfNeeded]; }
                     completion:nil];

    if (self.onAction) self.onAction(sender.action);
}

- (void)setupUI { [self buildUI]; }

- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 80); }

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
