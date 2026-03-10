#import "AppListViewController.h"
#import "AppManager.h"
#import "ThemeEngine.h"

@interface AppListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<AppInfo *> *apps;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, assign) NSInteger currentFilter;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@end

@implementation AppListViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider {
    self = [super init];
    if (self) { _provider = provider; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Applications";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self refreshApps];
}

- (void)setupUI {
    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"User", @"System", @"Mixed"]];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterControl.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    self.filterControl.selectedSegmentTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
    [self.filterControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} forState:UIControlStateNormal];
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.filterControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.color = [UIColor whiteColor];
    self.loadingIndicator.hidesWhenStopped = YES;
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.loadingIndicator];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.filterControl.heightAnchor constraintEqualToConstant:35],

        [self.tableView.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    self.currentFilter = sender.selectedSegmentIndex;
    [self.tableView reloadData];
}

- (void)refreshApps {
    [self.loadingIndicator startAnimating];
    [[AppManager sharedManager] fetchAppsWithProvider:self.provider completion:^(NSArray<AppInfo *> *apps, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
            if (apps) {
                self.apps = apps;
                [self.tableView reloadData];
            } else if (error) {
                NSLog(@"[AppList] Fetch error: %@", error);
            }
        });
    }];
}

- (NSArray<AppInfo *> *)filteredApps {
    if (self.currentFilter == 2) return self.apps;
    BOOL wantSystem = (self.currentFilter == 1);
    NSMutableArray *filtered = [NSMutableArray array];
    for (AppInfo *app in self.apps) {
        if (app.isSystem == wantSystem) [filtered addObject:app];
    }
    return [filtered copy];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self filteredApps].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

        UIView *bg = [[UIView alloc] init];
        bg.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.selectedBackgroundView = bg;
    }

    AppInfo *app = [self filteredApps][indexPath.row];
    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = app.bundleId;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppInfo *app = [self filteredApps][indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:app.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [ThemeEngine applyGlassStyleToView:alert.view cornerRadius:20];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch Normal" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jit:NO];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch with JIT" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jit:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)launch:(NSString *)bid jit:(BOOL)jit {
    [self.loadingIndicator startAnimating];
    self.view.userInteractionEnabled = NO;

    [[AppManager sharedManager] launchApp:bid withJit:jit provider:self.provider completion:^(BOOL success, NSString *message) {
        // AppManager's completion is now guaranteed to be on the main thread
        [self.loadingIndicator stopAnimating];
        self.view.userInteractionEnabled = YES;

        if (!success) {
            UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Launch Failed" message:message preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:err animated:YES completion:nil];
        }
    }];
}

@end
