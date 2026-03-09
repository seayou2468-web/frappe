#import "AppListViewController.h"
#import "AppManager.h"
#import "ThemeEngine.h"

@interface AppListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<AppInfo *> *apps;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, assign) NSInteger currentFilter; // 0: User, 1: System, 2: Mixed
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
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    [self setupUI];
    [self refreshApps];
}

- (void)setupUI {
    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"User", @"System", @"Mixed"]];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
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

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.filterControl.heightAnchor constraintEqualToConstant:40],

        [self.tableView.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    self.currentFilter = sender.selectedSegmentIndex;
    [self.tableView reloadData];
}

- (void)refreshApps {
    [[AppManager sharedManager] fetchAppsWithProvider:self.provider completion:^(NSArray<AppInfo *> *apps, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (apps) {
                self.apps = apps;
                [self.tableView reloadData];
            } else if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:error preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
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
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];

    AppInfo *app = [self filteredApps][indexPath.row];
    cell.textLabel.text = app.name;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.text = app.bundleId;
    cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    cell.backgroundColor = [UIColor clearColor];

    UIView *selView = [[UIView alloc] init];
    selView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    cell.selectedBackgroundView = selView;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppInfo *app = [self filteredApps][indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:app.name message:@"Launch Options" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Launch Normal" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[AppManager sharedManager] launchApp:app.bundleId withJit:NO provider:self.provider completion:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success) {
                    UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Launch Failed" message:message preferredStyle:UIAlertControllerStyleAlert];
                    [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:errAlert animated:YES completion:nil];
                }
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Launch with JIT" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[AppManager sharedManager] launchApp:app.bundleId withJit:YES provider:self.provider completion:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!success) {
                    UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"JIT Launch Failed" message:message preferredStyle:UIAlertControllerStyleAlert];
                    [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:errAlert animated:YES completion:nil];
                }
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    // iPad support for ActionSheet
    alert.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
