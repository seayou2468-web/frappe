#import "AppListViewController.h"
#import "AppManager.h"
#import "ThemeEngine.h"

@interface AppListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<AppInfo *> *apps;
@property (nonatomic, strong) UISegmentedControl *filterControl;
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
    self.title = @"APP_MANIFEST";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self refreshApps];
}

- (void)setupUI {
    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"USER", @"SYSTEM", @"ALL"]];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterControl.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.filterControl.selectedSegmentTintColor = [UIColor systemGreenColor];
    [self.filterControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont fontWithName:@"Courier-Bold" size:12]} forState:UIControlStateNormal];
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.filterControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.2];
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.filterControl.heightAnchor constraintEqualToConstant:35],

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
                NSLog(@"[TERMINAL] APP_FETCH_ERR: %@", error);
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
        cell.backgroundColor = [UIColor blackColor];
        cell.textLabel.font = [UIFont fontWithName:@"Courier-Bold" size:14];
        cell.detailTextLabel.font = [UIFont fontWithName:@"Courier" size:10];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    AppInfo *app = [self filteredApps][indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"> %@", app.name];
    cell.textLabel.textColor = [UIColor systemGreenColor];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"  ID: %@", app.bundleId];
    cell.detailTextLabel.textColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.6];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    AppInfo *app = [self filteredApps][indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"EXEC_CMD" message:[NSString stringWithFormat:@"Target: %@", app.bundleId] preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"RUN (NORMAL)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jit:NO];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"RUN (WITH_JIT)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jit:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"CANCEL" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)launch:(NSString *)bid jit:(BOOL)jit {
    [[AppManager sharedManager] launchApp:bid withJit:jit provider:self.provider completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                UIAlertController *err = [UIAlertController alertControllerWithTitle:@"EXEC_FAILED" message:message preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"ACK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:err animated:YES completion:nil];
            }
        });
    }];
}

@end
