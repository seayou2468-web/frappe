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
    self.filterControl.frame = CGRectMake(10, 10, self.view.bounds.size.width - 20, 40);
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.filterControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 60, self.view.bounds.size.width, self.view.bounds.size.height - 60) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.tableView];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    self.currentFilter = sender.selectedSegmentIndex;
    [self.tableView reloadData];
}

- (void)refreshApps {
    [[AppManager sharedManager] fetchAppsWithProvider:self.provider completion:^(NSArray<AppInfo *> *apps, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (apps) { self.apps = apps; [self.tableView reloadData]; }
            else { NSLog(@"[Apps] Error: %@", error); }
        });
    }];
}

- (NSArray<AppInfo *> *)filteredApps {
    if (self.currentFilter == 2) return self.apps;
    BOOL wantSystem = (self.currentFilter == 1);
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isSystem == %d", wantSystem];
    return [self.apps filteredArrayUsingPredicate:pred];
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
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppInfo *app = [self filteredApps][indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:app.name message:@"Launch Options" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Launch Normal" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[AppManager sharedManager] launchApp:app.bundleId withJit:NO provider:self.provider completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Launch with JIT" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[AppManager sharedManager] launchApp:app.bundleId withJit:YES provider:self.provider completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
