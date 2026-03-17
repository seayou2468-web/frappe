#import "AppListViewController.h"
#import "AppManager.h"
#import "ThemeEngine.h"
#import "DdiManager.h"
#import "idevice.h"

// ─── App Card Cell ─────────────────────────────────────────────────────────────
@interface AppCardCell : UITableViewCell
@property (nonatomic, strong) UIView      *iconBox;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel     *nameLabel;
@property (nonatomic, strong) UILabel     *bundleIdLabel;
@property (nonatomic, strong) UIView      *jitBadge;
@property (nonatomic, strong) UILabel     *jitLabel;
- (void)configureWithApp:(AppInfo *)app;
@end

@implementation AppCardCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    self = [super initWithStyle:s reuseIdentifier:r];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.selectedBackgroundView = [[UIView alloc] init];

    UIView *cv = self.contentView;

    // Icon with rounded box
    _iconBox = [[UIView alloc] init];
    _iconBox.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBox.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.15];
    _iconBox.layer.cornerRadius = 14;
    _iconBox.layer.cornerCurve = kCACornerCurveContinuous;
    _iconBox.clipsToBounds = YES;
    [cv addSubview:_iconBox];

    _iconView = [[UIImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.clipsToBounds = YES;
    [_iconBox addSubview:_iconView];

    // Name
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [ThemeEngine fontBody];
    _nameLabel.textColor = [ThemeEngine textPrimary];
    [cv addSubview:_nameLabel];

    // Bundle ID
    _bundleIdLabel = [[UILabel alloc] init];
    _bundleIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bundleIdLabel.font = [ThemeEngine fontCaption];
    _bundleIdLabel.textColor = [ThemeEngine textTertiary];
    [cv addSubview:_bundleIdLabel];

    // JIT badge
    _jitBadge = [[UIView alloc] init];
    _jitBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _jitBadge.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.2];
    _jitBadge.layer.cornerRadius = 6;
    _jitBadge.hidden = YES;
    [cv addSubview:_jitBadge];

    _jitLabel = [[UILabel alloc] init];
    _jitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _jitLabel.text = @" JIT ";
    _jitLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    _jitLabel.textColor = [ThemeEngine accent];
    [_jitBadge addSubview:_jitLabel];

    // Separator
    UIView *sep = [[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    sep.backgroundColor = [ThemeEngine border];
    [cv addSubview:sep];

    [NSLayoutConstraint activateConstraints:@[
        [_iconBox.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [_iconBox.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
        [_iconBox.widthAnchor constraintEqualToConstant:50],
        [_iconBox.heightAnchor constraintEqualToConstant:50],

        [_iconView.topAnchor constraintEqualToAnchor:_iconBox.topAnchor],
        [_iconView.bottomAnchor constraintEqualToAnchor:_iconBox.bottomAnchor],
        [_iconView.leadingAnchor constraintEqualToAnchor:_iconBox.leadingAnchor],
        [_iconView.trailingAnchor constraintEqualToAnchor:_iconBox.trailingAnchor],

        [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconBox.trailingAnchor constant:13],
        [_nameLabel.topAnchor constraintEqualToAnchor:cv.centerYAnchor constant:-14],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],

        [_bundleIdLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_bundleIdLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3],

        [_jitBadge.leadingAnchor constraintEqualToAnchor:_bundleIdLabel.trailingAnchor constant:6],
        [_jitBadge.centerYAnchor constraintEqualToAnchor:_bundleIdLabel.centerYAnchor],
        [_jitBadge.heightAnchor constraintEqualToConstant:16],

        [_jitLabel.leadingAnchor constraintEqualToAnchor:_jitBadge.leadingAnchor constant:4],
        [_jitLabel.trailingAnchor constraintEqualToAnchor:_jitBadge.trailingAnchor constant:-4],
        [_jitLabel.centerYAnchor constraintEqualToAnchor:_jitBadge.centerYAnchor],
        [_jitBadge.trailingAnchor constraintEqualToAnchor:_jitLabel.trailingAnchor constant:4],

        [sep.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor],
        [sep.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor],
        [sep.heightAnchor constraintEqualToConstant:0.4],
    ]];
    return self;
}

- (void)configureWithApp:(AppInfo *)app {
    _nameLabel.text = app.name ?: app.bundleId;
    _bundleIdLabel.text = app.bundleId;

    if (app.icon) {
        _iconView.image = app.icon;
        _iconBox.backgroundColor = [UIColor clearColor];
    } else {
        _iconView.image = nil;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
            configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
        UIImage *placeholder = [UIImage systemImageNamed:@"app.fill" withConfiguration:cfg];
        _iconView.image = placeholder;
        _iconView.tintColor = [ThemeEngine accent];
        _iconBox.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.15];
    }
    _jitBadge.hidden = app.isSystem;
}

- (void)setHighlighted:(BOOL)h animated:(BOOL)a {
    [super setHighlighted:h animated:a];
    [UIView animateWithDuration:a ? 0.15 : 0 animations:^{
        self.contentView.alpha = h ? 0.6 : 1.0;
        self->_iconBox.transform = h ?
            CGAffineTransformMakeScale(0.88, 0.88) : CGAffineTransformIdentity;
    }];
}
@end

// ─── AppListViewController ─────────────────────────────────────────────────────
static inline NSString *appListSafeErrorMessage(struct IdeviceFfiError *err) {
    if (!err || !err->message || err->message[0] == '\0') return @"(no detail)";
    return [NSString stringWithUTF8String:err->message];
}

@interface AppListViewController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<AppInfo *> *apps;
@property (nonatomic, strong) NSArray<AppInfo *> *filteredApps;
@property (nonatomic, assign) NSInteger currentFilter;
@end

@implementation AppListViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider {
    self = [super init];
    if (self) { _provider = provider; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"アプリ";
    self.view.backgroundColor = [ThemeEngine bg];

    // Search
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"アプリを検索";
    _searchController.searchBar.tintColor = [ThemeEngine accent];
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    // Segment filter
    _filterControl = [[UISegmentedControl alloc] initWithItems:@[@"ユーザー", @"システム"]];
    _filterControl.selectedSegmentIndex = 0;
    _filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    _filterControl.selectedSegmentTintColor = [[ThemeEngine accent] colorWithAlphaComponent:0.35];
    [_filterControl setTitleTextAttributes:@{NSForegroundColorAttributeName:[ThemeEngine textPrimary]}
                                  forState:UIControlStateNormal];
    [_filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_filterControl];

    // Table
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0);
    [_tableView registerClass:[AppCardCell class] forCellReuseIdentifier:@"AppCard"];
    [self.view addSubview:_tableView];

    // Empty state
    _emptyLabel = [[UILabel alloc] init];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.text = @"アプリが見つかりません";
    _emptyLabel.font = [ThemeEngine fontBody];
    _emptyLabel.textColor = [ThemeEngine textTertiary];
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    // Loading
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _loadingIndicator.color = [ThemeEngine accent];
    _loadingIndicator.hidesWhenStopped = YES;
    _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loadingIndicator];

    // Refresh button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(refreshApps)];
    self.navigationItem.rightBarButtonItem.tintColor = [ThemeEngine accent];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_filterControl.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [_filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_filterControl.heightAnchor constraintEqualToConstant:36],

        [_tableView.topAnchor constraintEqualToAnchor:_filterControl.bottomAnchor constant:12],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];

    [self refreshApps];
}

- (void)refreshApps {
    [_loadingIndicator startAnimating];
    _tableView.hidden = YES;
    _emptyLabel.hidden = YES;
    [[AppManager sharedManager] fetchAppsWithProvider:_provider completion:^(NSArray<AppInfo *> *apps, NSString *error) {
        if (error) {
            [self showError:error];
            return;
        }
        self.apps = apps ?: @[];
        [self applyFilter];
        [self->_loadingIndicator stopAnimating];
        self->_tableView.hidden = NO;
        self->_emptyLabel.hidden = self->_filteredApps.count > 0;
    }];
}

- (void)applyFilter {
    BOOL wantSystem = (_currentFilter == 1);
    NSString *q = _searchController.searchBar.text;
    NSArray *base = [_apps filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(AppInfo *a, id _) { return a.isSystem == wantSystem; }]];
    if (q.length > 0) {
        base = [base filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR bundleId CONTAINS[cd] %@", q, q]];
    }
    _filteredApps = base;
    [_tableView reloadData];
    _emptyLabel.hidden = _filteredApps.count > 0;
}

- (void)filterChanged:(UISegmentedControl *)s {
    _currentFilter = s.selectedSegmentIndex;
    [self applyFilter];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    [self applyFilter];
}

// ─── TableView ────────────────────────────────────────────────────────────────
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _filteredApps.count; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return 70; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    AppCardCell *cell = (AppCardCell *)[tv dequeueReusableCellWithIdentifier:@"AppCard" forIndexPath:ip];
    [cell configureWithApp:_filteredApps[ip.row]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    AppInfo *app = _filteredApps[ip.row];
    [self showLaunchSheet:app fromCell:[tv cellForRowAtIndexPath:ip]];
}

// ─── Launch Sheet ─────────────────────────────────────────────────────────────
- (void)showLaunchSheet:(AppInfo *)app fromCell:(UITableViewCell *)cell {
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:app.name
        message:app.bundleId
        preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *normal = [UIAlertAction actionWithTitle:@"🚀  通常起動"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [self launch:app.bundleId jitMode:JitModeNone];
        }];

    UIAlertAction *jitNative = [UIAlertAction actionWithTitle:@"⚡  JIT 起動 (GodSpeed)"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [self launch:app.bundleId jitMode:JitModeNative];
        }];

    UIAlertAction *jitJS = [UIAlertAction actionWithTitle:@"📜  JIT 起動 (JavaScript)"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [self launch:app.bundleId jitMode:JitModeJS];
        }];

    [sheet addAction:normal];
    [sheet addAction:jitNative];
    [sheet addAction:jitJS];
    [sheet addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)launch:(NSString *)bid jitMode:(JitMode)jitMode {
    [_loadingIndicator startAnimating];
    self.view.userInteractionEnabled = NO;

    if (jitMode != JitModeNone) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            struct LockdowndClientHandle *ld = NULL;
            struct IdeviceFfiError *err = lockdownd_connect(self.provider, &ld);
            if (err) {
                idevice_error_free(err);
                [self finishLaunch:NO message:@"ロックダウン接続に失敗しました"];
                return;
            }
            [[DdiManager sharedManager] checkAndMountDdiWithProvider:self.provider lockdown:ld
                completion:^(BOOL ok, NSString *msg) {
                    lockdownd_client_free(ld);
                    if (!ok) { [self finishLaunch:NO message:[NSString stringWithFormat:@"DDI 必要: %@", msg]]; return; }
                    [[AppManager sharedManager] launchApp:bid jitMode:jitMode provider:self.provider
                        completion:^(BOOL s, NSString *m){ [self finishLaunch:s message:m]; }];
                }];
        });
    } else {
        [[AppManager sharedManager] launchApp:bid jitMode:JitModeNone provider:_provider
            completion:^(BOOL s, NSString *m){ [self finishLaunch:s message:m]; }];
    }
}

- (void)finishLaunch:(BOOL)ok message:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_loadingIndicator stopAnimating];
        self.view.userInteractionEnabled = YES;
        if (!ok) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"起動失敗"
                message:msg preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:a animated:YES completion:nil];
        }
    });
}

- (void)showError:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_loadingIndicator stopAnimating];
        self->_emptyLabel.text = msg ?: @"エラーが発生しました";
        self->_emptyLabel.hidden = NO;
    });
}
@end
