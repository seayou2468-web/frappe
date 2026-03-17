#import "TabSwitcherViewController.h"
#import "TabManager.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import "MainContainerViewController.h"
#import <LocalAuthentication/LocalAuthentication.h>

// ─── Tab Card Cell ─────────────────────────────────────────────────────────────
@interface TabCardCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UILabel     *titleLabel;
@property (nonatomic, strong) UILabel     *typeLabel;
@property (nonatomic, strong) UIButton    *closeBtn;
@property (nonatomic, copy)   void (^onClose)(void);
@end

@implementation TabCardCell
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;

    self.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    self.contentView.layer.cornerRadius = kCornerL;
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.borderWidth = 0.6;
    self.contentView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 6);
    self.layer.shadowOpacity = 0.45;
    self.layer.shadowRadius = 14;
    self.layer.masksToBounds = NO;

    // Preview image (fills card)
    _preview = [[UIImageView alloc] init];
    _preview.contentMode = UIViewContentModeScaleAspectFill;
    _preview.clipsToBounds = YES;
    _preview.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1];
    _preview.frame = self.contentView.bounds;
    _preview.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:_preview];

    // Gradient overlay at top
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.colors = @[(__bridge id)[UIColor colorWithWhite:0 alpha:0.75].CGColor,
                    (__bridge id)[UIColor clearColor].CGColor];
    grad.startPoint = CGPointMake(0, 0);
    grad.endPoint   = CGPointMake(0, 1);
    grad.frame = CGRectMake(0, 0, f.size.width, 60);
    [self.contentView.layer addSublayer:grad];

    // Title
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [ThemeEngine textPrimary];
    _titleLabel.numberOfLines = 1;
    [self.contentView addSubview:_titleLabel];

    // Type badge
    _typeLabel = [[UILabel alloc] init];
    _typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _typeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    _typeLabel.textColor = [ThemeEngine accent];
    _typeLabel.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.18];
    _typeLabel.layer.cornerRadius = 5;
    _typeLabel.clipsToBounds = YES;
    _typeLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:_typeLabel];

    // Close button
    _closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    [_closeBtn setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:cfg] forState:UIControlStateNormal];
    _closeBtn.tintColor = [ThemeEngine textSecondary];
    _closeBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _closeBtn.layer.cornerRadius = 12;
    [_closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_closeBtn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [_closeBtn.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [_closeBtn.widthAnchor constraintEqualToConstant:24],
        [_closeBtn.heightAnchor constraintEqualToConstant:24],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_closeBtn.leadingAnchor constant:-4],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_closeBtn.centerYAnchor],

        [_typeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [_typeLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        [_typeLabel.heightAnchor constraintEqualToConstant:18],
        [_typeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:40],
    ]];
    return self;
}
- (void)closeTapped { if (self.onClose) self.onClose(); }

- (void)configureWithTab:(TabInfo *)tab isActive:(BOOL)active {
    _titleLabel.text = tab.title ?: @"無題";
    _preview.image = tab.screenshot;
    _typeLabel.text = (tab.type == TabTypeWebBrowser) ? @" WEB " : @" FILES ";
    _typeLabel.textColor = active ? [ThemeEngine accent] : [ThemeEngine textSecondary];
    _typeLabel.backgroundColor = active
        ? [[ThemeEngine accent] colorWithAlphaComponent:0.2]
        : [UIColor colorWithWhite:1 alpha:0.08];
    self.contentView.layer.borderColor = active
        ? [[ThemeEngine accent] colorWithAlphaComponent:0.55].CGColor
        : [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    self.contentView.layer.borderWidth = active ? 1.2 : 0.6;
}

- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:0.15 animations:^{
        self.transform = h ? CGAffineTransformMakeScale(0.95,0.95) : CGAffineTransformIdentity;
    }];
}
@end

// ─── TabSwitcherViewController ────────────────────────────────────────────────
@interface TabSwitcherViewController () <UICollectionViewDelegate, UICollectionViewDataSource>
@property (strong) UICollectionView *grid;
@property (strong) UIVisualEffectView *bgBlur;
@end

@implementation TabSwitcherViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Dark blur background
    _bgBlur = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    _bgBlur.frame = self.view.bounds;
    _bgBlur.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_bgBlur];
    self.view.backgroundColor = [[ThemeEngine bg] colorWithAlphaComponent:0.7];

    // Header bar
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.text = @"タブ";
    titleLbl.font = [ThemeEngine fontTitle];
    titleLbl.textColor = [ThemeEngine textPrimary];
    [header addSubview:titleLbl];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [doneBtn setTitle:@"完了" forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    doneBtn.tintColor = [ThemeEngine accent];
    [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:doneBtn];

    UIButton *newBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    newBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    [newBtn setImage:[UIImage systemImageNamed:@"plus.square" withConfiguration:cfg]
            forState:UIControlStateNormal];
    newBtn.tintColor = [ThemeEngine accent];
    [newBtn addTarget:self action:@selector(newTabTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:newBtn];

    // Collection view
    CGFloat pad = 16, gap = 14;
    CGFloat w = (self.view.bounds.size.width > 0 ? self.view.bounds.size.width : 390);
    CGFloat cellW = (w - pad*2 - gap) / 2.0;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(cellW, cellW * 1.4);
    layout.sectionInset = UIEdgeInsetsMake(16, pad, 30, pad);
    layout.minimumInteritemSpacing = gap;
    layout.minimumLineSpacing = gap + 6;

    _grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _grid.translatesAutoresizingMaskIntoConstraints = NO;
    _grid.backgroundColor = [UIColor clearColor];
    _grid.delegate = self;
    _grid.dataSource = self;
    _grid.alwaysBounceVertical = YES;
    [_grid registerClass:[TabCardCell class] forCellWithReuseIdentifier:@"TabCard"];
    [self.view addSubview:_grid];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [header.heightAnchor constraintEqualToConstant:52],

        [titleLbl.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [titleLbl.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [newBtn.trailingAnchor constraintEqualToAnchor:doneBtn.leadingAnchor constant:-16],
        [newBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [doneBtn.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [doneBtn.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [_grid.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],
        [_grid.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_grid.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_grid.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Entrance animation
    self.view.alpha = 0;
    _grid.transform = CGAffineTransformMakeTranslation(0, 40);
    [UIView animateWithDuration:0.35 delay:0
         usingSpringWithDamping:0.75 initialSpringVelocity:0.5
                        options:0 animations:^{
        self.view.alpha = 1;
        self->_grid.transform = CGAffineTransformIdentity;
    } completion:nil];
}

// ─── Collection ───────────────────────────────────────────────────────────────
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    return [TabManager sharedManager].tabs.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv
                  cellForItemAtIndexPath:(NSIndexPath *)ip {
    TabCardCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"TabCard" forIndexPath:ip];
    NSArray *tabs = [TabManager sharedManager].tabs;
    if (ip.item >= tabs.count) return nil;
    TabInfo *tab = tabs[ip.item];
    BOOL active = (ip.item == [TabManager sharedManager].activeTabIndex);
    [cell configureWithTab:tab isActive:active];
    __weak typeof(self) ws = self;
    cell.onClose = ^{
        [[TabManager sharedManager] removeTabAtIndex:ip.item];
        [cv performBatchUpdates:^{ [cv deleteItemsAtIndexPaths:@[ip]]; } completion:nil];
        if ([TabManager sharedManager].tabs.count == 0 && ws.onNewTabRequested) {
            ws.onNewTabRequested();
        }
    };
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (ip.item < [TabManager sharedManager].tabs.count && self.onTabSelected) self.onTabSelected(ip.item);
}

// ─── Actions ──────────────────────────────────────────────────────────────────
- (void)doneTapped {
    [UIView animateWithDuration:0.25 animations:^{ self.view.alpha = 0; }
                     completion:^(BOOL f){ [self dismissViewControllerAnimated:NO completion:nil]; }];
}

- (void)newTabTapped {
    if (self.onNewTabRequested) self.onNewTabRequested();
}

// ─── Auth helpers (keep existing) ────────────────────────────────────────────
- (void)authenticateWithTab:(TabInfo *)tab completion:(void(^)(BOOL))c {
    if (tab.useFaceID) {
        LAContext *ctx = [[LAContext alloc] init];
        [ctx evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
            localizedReason:@"認証が必要です"
                      reply:^(BOOL s, NSError *e){ dispatch_async(dispatch_get_main_queue(), ^{ c(s); }); }];
    } else if (tab.password) {
        [self showPasswordPromptForItem:tab completion:c];
    } else { c(YES); }
}

- (void)showPasswordPromptForItem:(id)item completion:(void(^)(BOOL))c {
    NSString *pw = [item isKindOfClass:[TabInfo class]] ? ((TabInfo*)item).password : ((TabGroup*)item).password;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"パスワード入力"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.secureTextEntry=YES; }];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *_){ c([a.textFields.firstObject.text isEqualToString:pw]); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel
        handler:^(UIAlertAction *_){ c(NO); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)refreshUI { [_grid reloadData]; }
- (void)updateDisplayItems {}
- (void)groupSwitcherTapped {}

@end
