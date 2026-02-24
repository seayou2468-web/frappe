#import "AppListViewController.h"
#import "JITEnableContext.h"
#import "ThemeEngine.h"
#import "PlistEditorViewController.h"

@interface AppListViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSDictionary *allApps;
@property (nonatomic, strong) NSArray *filteredBundleIDs;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, strong) UISearchBar *searchBar;
@end

@implementation AppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Applications";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    [self setupUI];
    [self reloadData];
}

- (void)setupUI {
    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[@"All", @"User", @"System"]];
    self.filterSegment.selectedSegmentIndex = 0;
    self.filterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterSegment addTarget:self action:@selector(reloadData) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.filterSegment];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.delegate = self;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.filterSegment.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.filterSegment.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.filterSegment.bottomAnchor constant:10],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)reloadData {
    NSError *error = nil;
    self.allApps = [[JITEnableContext shared] getAllAppsInfoWithError:&error];
    if (error) {
        NSLog(@"Error fetching apps: %@", error);
        return;
    }

    [self filterApps];
}

- (void)filterApps {
    NSMutableArray *ids = [NSMutableArray array];
    NSString *query = self.searchBar.text.lowercaseString;

    for (NSString *bid in self.allApps) {
        NSDictionary *info = self.allApps[bid];
        NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bid;

        BOOL matchesSearch = (query.length == 0 || [name.lowercaseString containsString:query] || [bid.lowercaseString containsString:query]);
        if (!matchesSearch) continue;

        NSString *type = info[@"ApplicationType"];
        if (self.filterSegment.selectedSegmentIndex == 1 && ![type isEqualToString:@"User"]) continue;
        if (self.filterSegment.selectedSegmentIndex == 2 && ![type isEqualToString:@"System"]) continue;

        [ids addObject:bid];
    }

    self.filteredBundleIDs = [ids sortedArrayUsingComparator:^NSComparisonResult(NSString *id1, NSString *id2) {
        NSString *n1 = self.allApps[id1][@"CFBundleDisplayName"] ?: id1;
        NSString *n2 = self.allApps[id2][@"CFBundleDisplayName"] ?: id2;
        return [n1 compare:n2 options:NSCaseInsensitiveSearch];
    }];

    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterApps];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredBundleIDs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];

        UIView *clayBg = [[ClayView alloc] initWithFrame:CGRectMake(10, 5, self.view.bounds.size.width-20, 60) cornerRadius:15];
        cell.backgroundView = [[UIView alloc] init];
        [cell.backgroundView addSubview:clayBg];
    }

    NSString *bid = self.filteredBundleIDs[indexPath.row];
    NSDictionary *info = self.allApps[bid];
    cell.textLabel.text = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bid;
    cell.detailTextLabel.text = bid;

    UIImage *icon = [[JITEnableContext shared] getAppIconWithBundleId:bid error:nil];
    cell.imageView.image = icon ?: [UIImage systemImageNamed:@"app"];
    cell.imageView.layer.cornerRadius = 8;
    cell.imageView.clipsToBounds = YES;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 70;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *bid = self.filteredBundleIDs[indexPath.row];
    [self showAppActions:bid];
}

- (void)showAppActions:(NSString *)bundleID {
    NSDictionary *info = self.allApps[bundleID];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:info[@"CFBundleDisplayName"] message:bundleID preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[JITEnableContext shared] launchAppWithoutDebug:bundleID args:@[] logger:^(NSString *msg) {
            NSLog(@"Launch: %@", msg);
        }];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Show Info (Plist)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]];
        [info writeToFile:tmpPath atomically:YES];
        PlistEditorViewController *evc = [[PlistEditorViewController alloc] initWithPath:tmpPath];
        [self.navigationController pushViewController:evc animated:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
