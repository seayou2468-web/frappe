#import "IdeviceAppDetailViewController.h"
#import "ThemeEngine.h"

@interface IdeviceAppDetailViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSDictionary *appInfo;
@property (nonatomic, strong) NSArray *keys;
@end

@implementation IdeviceAppDetailViewController

- (instancetype)initWithAppInfo:(NSDictionary *)appInfo {
    self = [super init];
    if (self) {
        _appInfo = appInfo;
        _keys = [[appInfo allKeys] sortedArrayUsingSelector:@selector(compare:)];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.appInfo[@"CFBundleDisplayName"] ?: self.appInfo[@"CFBundleName"] ?: @"App Details";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    [self setupUI];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.keys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:@"DetailCell"];
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.05];
        cell.textLabel.textColor = [ThemeEngine liquidColor];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.numberOfLines = 0;
    }

    NSString *key = self.keys[indexPath.row];
    id value = self.appInfo[key];

    cell.textLabel.text = key;
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = @"[Complex Data]";
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", value];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *key = self.keys[indexPath.row];
    id value = self.appInfo[key];

    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        IdeviceAppDetailViewController *vc = [[IdeviceAppDetailViewController alloc] initWithAppInfo:(NSDictionary *)value];
        vc.title = key;
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
