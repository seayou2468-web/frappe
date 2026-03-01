#import "FileInfoViewController.h"
#import "ThemeEngine.h"

@interface FileInfoViewController ()
@property (nonatomic, strong) FileItem *item;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *sections;
@end

@implementation FileInfoViewController

- (instancetype)initWithItem:(FileItem *)item {
    self = [super init];
    if (self) {
        _item = item;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"詳細情報";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    [self prepareData];
}

- (void)prepareData {
    NSMutableArray *basicInfo = [NSMutableArray array];
    [basicInfo addObject:@{@"label": @"名前", @"value": self.item.name ?: @""}];
    [basicInfo addObject:@{@"label": @"種類", @"value": self.item.attributes[NSFileType] ?: @""}];

    if (self.item.isSymbolicLink) {
        [basicInfo addObject:@{@"label": @"リンク先", @"value": self.item.linkTarget ?: @""}];
    }

    NSMutableArray *sizeInfo = [NSMutableArray array];
    unsigned long long size = [self.item.attributes[NSFileSize] unsignedLongLongValue];
    [sizeInfo addObject:@{@"label": @"サイズ", @"value": [NSByteCountFormatter stringFromByteCount:size countStyle:NSByteCountFormatterCountStyleFile]}];

    NSMutableArray *dateInfo = [NSMutableArray array];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateStyle = NSDateFormatterMediumStyle;
    df.timeStyle = NSDateFormatterShortStyle;
    df.locale = [NSLocale localeWithLocaleIdentifier:@"ja_JP"];

    [dateInfo addObject:@{@"label": @"作成日", @"value": [df stringFromDate:self.item.attributes[NSFileCreationDate]] ?: @"-"}];
    [dateInfo addObject:@{@"label": @"変更日", @"value": [df stringFromDate:self.item.attributes[NSFileModificationDate]] ?: @"-"}];

    NSMutableArray *permissionInfo = [NSMutableArray array];
    [permissionInfo addObject:@{@"label": @"アクセス権", @"value": [NSString stringWithFormat:@"%o", [self.item.attributes[NSFilePosixPermissions] intValue]]}];
    [permissionInfo addObject:@{@"label": @"オーナー", @"value": self.item.attributes[NSFileOwnerAccountName] ?: @"-"}];
    [permissionInfo addObject:@{@"label": @"グループ", @"value": self.item.attributes[NSFileGroupOwnerAccountName] ?: @"-"}];

    self.sections = @[
        @{@"title": @"一般", @"rows": basicInfo},
        @{@"title": @"サイズ", @"rows": sizeInfo},
        @{@"title": @"時間", @"rows": dateInfo},
        @{@"title": @"権限", @"rows": permissionInfo},
        @{@"title": @"パス", @"rows": @[@{@"label": @"絶対パス", @"value": self.item.fullPath ?: @""}]}
    ];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"InfoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellId];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
        cell.detailTextLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    cell.textLabel.text = row[@"label"];
    cell.detailTextLabel.text = row[@"value"];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if ([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
        header.textLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
        header.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    }
}

@end
