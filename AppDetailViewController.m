#import "AppDetailViewController.h"
#import "ThemeEngine.h"

@interface AppDetailViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) AppInfo *appInfo;
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *details;
@end

@implementation AppDetailViewController

- (instancetype)initWithAppInfo:(AppInfo *)appInfo provider:(struct IdeviceProviderHandle *)provider {
    self = [super init];
    if (self) {
        _appInfo = appInfo;
        _provider = provider;
        [self prepareDetails];
    }
    return self;
}

- (void)prepareDetails {
    NSMutableArray *d = [NSMutableArray array];
    if (self.appInfo.name) [d addObject:@{@"label": @"Name", @"value": self.appInfo.name}];
    if (self.appInfo.bundleId) [d addObject:@{@"label": @"Bundle ID", @"value": self.appInfo.bundleId}];
    if (self.appInfo.version) [d addObject:@{@"label": @"Version", @"value": self.appInfo.version}];
    if (self.appInfo.type) [d addObject:@{@"label": @"Type", @"value": self.appInfo.type}];
    if (self.appInfo.signer) [d addObject:@{@"label": @"Signer", @"value": self.appInfo.signer}];
    if (self.appInfo.diskUsage) [d addObject:@{@"label": @"Disk Usage", @"value": self.appInfo.diskUsage}];
    if (self.appInfo.path) [d addObject:@{@"label": @"App Path", @"value": self.appInfo.path}];
    if (self.appInfo.container) [d addObject:@{@"label": @"Container Path", @"value": self.appInfo.container}];
    self.details = [d copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.appInfo.name;
    self.view.backgroundColor = [UIColor blackColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    [ThemeEngine applyGlassStyleToView:self.view cornerRadius:0];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.details.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DetailCell"];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        cell.detailTextLabel.numberOfLines = 0;
    }

    NSDictionary *d = self.details[indexPath.row];
    cell.textLabel.text = d[@"label"];
    cell.detailTextLabel.text = d[@"value"];

    return cell;
}

@end
