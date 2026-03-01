#import "FileInfoViewController.h"
#import "ThemeEngine.h"
#import <sys/stat.h>
#import <string.h>

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

- (NSString *)permissionStringFromMode:(short)mode {
    char s[11];
    strcpy(s, "----------");
    if (S_ISDIR(mode)) s[0] = 'd';
    if (S_ISLNK(mode)) s[0] = 'l';
    if (mode & S_IRUSR) s[1] = 'r';
    if (mode & S_IWUSR) s[2] = 'w';
    if (mode & S_IXUSR) s[3] = 'x';
    if (mode & S_IRGRP) s[4] = 'r';
    if (mode & S_IWGRP) s[5] = 'w';
    if (mode & S_IXGRP) s[6] = 'x';
    if (mode & S_IROTH) s[7] = 'r';
    if (mode & S_IWOTH) s[8] = 'w';
    if (mode & S_IXOTH) s[9] = 'x';
    return [NSString stringWithUTF8String:s];
}

- (void)prepareData {
    NSDictionary *attrs = self.item.attributes;

    NSMutableArray *basicInfo = [NSMutableArray array];
    [basicInfo addObject:@{@"label": @"名前", @"value": self.item.name ?: @""}];
    [basicInfo addObject:@{@"label": @"種類", @"value": [self localizedFileType:attrs[NSFileType]]}];
    if (self.item.isSymbolicLink) {
        [basicInfo addObject:@{@"label": @"リンク先", @"value": self.item.linkTarget ?: @""}];
    }
    [basicInfo addObject:@{@"label": @"拡張子", @"value": [self.item.fullPath pathExtension] ?: @"なし"}];

    NSMutableArray *sizeInfo = [NSMutableArray array];
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    [sizeInfo addObject:@{@"label": @"サイズ", @"value": [NSByteCountFormatter stringFromByteCount:size countStyle:NSByteCountFormatterCountStyleFile]}];
    [sizeInfo addObject:@{@"label": @"バイト数", @"value": [NSString stringWithFormat:@"%llu バイト", size]}];

    NSMutableArray *dateInfo = [NSMutableArray array];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy年MM月dd日 HH:mm:ss";
    df.locale = [NSLocale localeWithLocaleIdentifier:@"ja_JP"];

    [dateInfo addObject:@{@"label": @"作成日", @"value": [df stringFromDate:attrs[NSFileCreationDate]] ?: @"-"}];
    [dateInfo addObject:@{@"label": @"最終変更日", @"value": [df stringFromDate:attrs[NSFileModificationDate]] ?: @"-"}];

    NSMutableArray *permissionInfo = [NSMutableArray array];
    short mode = [attrs[NSFilePosixPermissions] shortValue];
    [permissionInfo addObject:@{@"label": @"アクセス権", @"value": [self permissionStringFromMode:mode]}];
    [permissionInfo addObject:@{@"label": @"アクセス権 (8進数)", @"value": [NSString stringWithFormat:@"%o", mode]}];
    [permissionInfo addObject:@{@"label": @"オーナー", @"value": attrs[NSFileOwnerAccountName] ?: @"-"}];
    [permissionInfo addObject:@{@"label": @"グループ", @"value": attrs[NSFileGroupOwnerAccountName] ?: @"-"}];
    [permissionInfo addObject:@{@"label": @"オーナーID", @"value": [attrs[NSFileOwnerAccountID] stringValue] ?: @"-"}];
    [permissionInfo addObject:@{@"label": @"グループID", @"value": [attrs[NSFileGroupOwnerAccountID] stringValue] ?: @"-"}];

    NSMutableArray *systemInfo = [NSMutableArray array];
    [systemInfo addObject:@{@"label": @"iノード番号", @"value": [attrs[NSFileSystemFileNumber] stringValue] ?: @"-"}];
    [systemInfo addObject:@{@"label": @"デバイスID", @"value": [attrs[NSFileSystemNumber] stringValue] ?: @"-"}];
    [systemInfo addObject:@{@"label": @"ハードリンク数", @"value": [attrs[NSFileReferenceCount] stringValue] ?: @"-"}];
    [systemInfo addObject:@{@"label": @"拡張属性", @"value": [attrs objectForKey:@"NSFileExtendedAttributes"] ? @"あり" : @"なし"}];

    self.sections = @[
        @{@"title": @"一般情報", @"rows": basicInfo},
        @{@"title": @"サイズ情報", @"rows": sizeInfo},
        @{@"title": @"時間情報", @"rows": dateInfo},
        @{@"title": @"権限とアクセス", @"rows": permissionInfo},
        @{@"title": @"システム詳細", @"rows": systemInfo},
        @{@"title": @"場所", @"rows": @[@{@"label": @"フルパス", @"value": self.item.fullPath ?: @""}]}
    ];
}

- (NSString *)localizedFileType:(NSString *)type {
    if ([type isEqualToString:NSFileTypeDirectory]) return @"フォルダ";
    if ([type isEqualToString:NSFileTypeRegular]) return @"ファイル";
    if ([type isEqualToString:NSFileTypeSymbolicLink]) return @"シンボリックリンク";
    if ([type isEqualToString:NSFileTypeSocket]) return @"ソケット";
    if ([type isEqualToString:NSFileTypeCharacterSpecial]) return @"キャラクタデバイス";
    if ([type isEqualToString:NSFileTypeBlockSpecial]) return @"ブロックデバイス";
    return type ?: @"不明";
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
