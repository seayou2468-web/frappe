#import "IdeviceAppListViewController.h"
#import "IdeviceManager.h"
#import "ThemeEngine.h"
#import "IdeviceAppDetailViewController.h"

@interface IdeviceAppListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *apps;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation IdeviceAppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"インストール済みアプリ";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    [self setupUI];
    [self loadApps];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center; self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)loadApps {
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[IdeviceManager sharedManager] getAppListWithCompletion:^(NSArray *apps, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf; if (!strongSelf) return;
        [strongSelf.spinner stopAnimating];
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
        } else {
            // Sort apps by name
            strongSelf.apps = [apps sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                NSString *n1 = obj1[@"CFBundleDisplayName"] ?: obj1[@"CFBundleName"] ?: @"";
                NSString *n2 = obj2[@"CFBundleDisplayName"] ?: obj2[@"CFBundleName"] ?: @"";
                return [n1 localizedCompare:n2];
            }];
            [strongSelf.tableView reloadData];
        }
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.apps.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    id item = (indexPath.row < self.apps.count) ? self.apps[indexPath.row] : nil;
    NSString *name = @"不明なアプリ";
    NSString *bid = @"";
    if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *app = (NSDictionary *)item;
        name = [NSString stringWithFormat:@"%@", app[@"CFBundleDisplayName"] ?: app[@"CFBundleName"] ?: @"不明"];
        bid = [NSString stringWithFormat:@"%@", app[@"CFBundleIdentifier"] ?: @""];
    }
    cell.textLabel.text = name;
    cell.detailTextLabel.text = bid;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id item = self.apps[indexPath.row];
    if ([item isKindOfClass:[NSDictionary class]]) {
        IdeviceAppDetailViewController *vc = [[IdeviceAppDetailViewController alloc] initWithData:item title:@"アプリ詳細"];
        [self.navigationController pushViewController:vc animated:YES];
    }
}
@end
