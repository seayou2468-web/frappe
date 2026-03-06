#import "IdeviceAppDetailViewController.h"
#import "ThemeEngine.h"
#import "IdeviceManager.h"

@interface IdeviceAppDetailViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSDictionary *appInfo;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSDictionary *sectionData;
@end

@implementation IdeviceAppDetailViewController

- (instancetype)initWithAppInfo:(NSDictionary *)appInfo {
    self = [super init];
    if (self) {
        _appInfo = appInfo;
        [self prepareSections];
    }
    return self;
}

- (void)prepareSections {
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];

    // Categorize common keys
    NSArray *basicKeys = @[@"CFBundleDisplayName", @"CFBundleName", @"CFBundleIdentifier", @"CFBundleShortVersionString", @"CFBundleVersion"];
    NSArray *pathKeys = @[@"Path", @"Container", @"DataContainer"];

    NSMutableArray *basics = [NSMutableArray array];
    NSMutableArray *paths = [NSMutableArray array];
    NSMutableArray *others = [NSMutableArray array];

    NSArray *allKeys = [[self.appInfo allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in allKeys) {
        if ([basicKeys containsObject:key]) [basics addObject:key];
        else if ([key containsString:@"Path"] || [key containsString:@"Container"]) [paths addObject:key];
        else [others addObject:key];
    }

    NSMutableArray *sectionList = [NSMutableArray array];
    NSMutableDictionary *data = [NSMutableDictionary dictionary];

    if (basics.count > 0) { [sectionList addObject:@"基本情報"]; data[@"基本情報"] = basics; }
    if (paths.count > 0) { [sectionList addObject:@"パス・コンテナ"]; data[@"パス・コンテナ"] = paths; }
    if (others.count > 0) { [sectionList addObject:@"その他詳細"]; data[@"その他詳細"] = others; }

    self.sections = sectionList;
    self.sectionData = data;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.appInfo[@"CFBundleDisplayName"] ?: self.appInfo[@"CFBundleName"] ?: @"アプリ詳細";
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

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    UIButton *launchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    launchBtn.frame = CGRectMake(20, 20, footer.frame.size.width - 40, 50);
    [ThemeEngine applyGlassStyleToView:launchBtn cornerRadius:12];
    [launchBtn setTitle:@"アプリを起動" forState:UIControlStateNormal];
    [launchBtn setTitleColor:[ThemeEngine liquidColor] forState:UIControlStateNormal];
    [launchBtn addTarget:self action:@selector(launchApp) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:launchBtn];
    self.tableView.tableFooterView = footer;

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)launchApp {
    NSString *bid = self.appInfo[@"CFBundleIdentifier"];
    if (!bid) return;

    [[IdeviceManager sharedManager] launchAppWithBundleId:bid completion:^(NSError *error) {
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"起動エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            // Success
        }
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSString *title = self.sections[section];
    return [self.sectionData[title] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section];
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

    NSString *sectionTitle = self.sections[indexPath.section];
    NSString *key = self.sectionData[sectionTitle][indexPath.row];
    id value = self.appInfo[key];

    cell.textLabel.text = [self localizedKey:key];
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = @"[詳細データ...]";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", value];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (NSString *)localizedKey:(NSString *)key {
    NSDictionary *map = @{
        @"CFBundleDisplayName": @"表示名",
        @"CFBundleName": @"名前",
        @"CFBundleIdentifier": @"識別子",
        @"CFBundleShortVersionString": @"バージョン",
        @"CFBundleVersion": @"ビルド",
        @"Path": @"パス",
        @"Container": @"コンテナ",
        @"DataContainer": @"データ"
    };
    return map[key] ?: key;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *sectionTitle = self.sections[indexPath.section];
    NSString *key = self.sectionData[sectionTitle][indexPath.row];
    id value = self.appInfo[key];

    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        IdeviceAppDetailViewController *vc = [[IdeviceAppDetailViewController alloc] initWithAppInfo:(NSDictionary *)value];
        vc.title = key;
        [self.navigationController pushViewController:vc animated:YES];
    }
}

@end
