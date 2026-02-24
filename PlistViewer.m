#import "PlistViewer.h"

@interface PlistViewer ()
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSMutableArray<NSString *> *items;
@property (strong, nonatomic) NSMutableArray *paths;
@property (strong, nonatomic) NSString *currentPath;
@property (strong, nonatomic) id plistObject;
@property (assign, nonatomic) NSPropertyListFormat plistFormat;
@end

@implementation PlistViewer

- (instancetype)initWithPlistPath:(NSString *)path {
    self = [super init];
    if (self) {
        _currentPath = path;
        _items = [NSMutableArray array];
        _paths = [NSMutableArray array];
        [self loadPlist:path];
    }
    return self;
}

- (instancetype)initWithPlistObject:(id)obj title:(NSString *)title parentPath:(NSString *)path {
    self = [super init];
    if (self) {
        _currentPath = path;
        _plistObject = obj;
        _items = [NSMutableArray array];
        _paths = [NSMutableArray array];
        self.title = title;
        [self loadPlistObject:obj];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                            target:self
                                                                            action:@selector(addItem)];
    self.navigationItem.rightBarButtonItem = addBtn;
}

#pragma mark - plist読み込み

- (void)loadPlist:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    NSError *error = nil;
    id obj = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:&_plistFormat
                                                         error:&error];
    if (!obj) { NSLog(@"plist読み込み失敗: %@ / %@", path, error); return; }
    _plistObject = obj;
    [self loadPlistObject:obj];
}

- (void)loadPlistObject:(id)obj {
    [_items removeAllObjects];
    [_paths removeAllObjects];

    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in obj) {
            [_items addObject:key];
            [_paths addObject:obj[key]];
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (NSInteger i=0;i<[(NSArray*)obj count];i++) {
            [_items addObject:[NSString stringWithFormat:@"[%ld]", (long)i]];
            [_paths addObject:obj[i]];
        }
    }

    [self.tableView reloadData];
}

- (void)savePlist {
    if (!_plistObject || !_currentPath) return;
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:_plistObject
                                                              format:_plistFormat
                                                             options:0
                                                               error:&error];
    if (!data) { NSLog(@"plist保存失敗: %@", error); return; }
    [data writeToFile:_currentPath atomically:YES];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"PlistCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];

    NSString *title = _items[indexPath.row];
    id value = _paths[indexPath.row];

    cell.textLabel.text = title;
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"(%@)", [value class]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
        cell.detailTextLabel.text = [value boolValue] ? @"YES" : @"NO";
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", value];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    id value = _paths[indexPath.row];
    NSString *title = _items[indexPath.row];

    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        PlistViewer *vc = [[PlistViewer alloc] initWithPlistObject:value title:title parentPath:_currentPath];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    // ポップアップで編集
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:@"値を編集"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.text = [NSString stringWithFormat:@"%@", value]; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action){
        UITextField *tf = alert.textFields.firstObject;
        id newValue = tf.text;

        // 型変換
        if ([value isKindOfClass:[NSNumber class]]) {
            NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
            NSNumber *num = [fmt numberFromString:newValue];
            if (num) newValue = num;
        } else if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
            newValue = @([newValue boolValue]);
        }

        if ([_plistObject isKindOfClass:[NSDictionary class]]) {
            _plistObject[title] = newValue;
        } else if ([_plistObject isKindOfClass:[NSArray class]]) {
            NSUInteger idx = [[title stringByTrimmingCharactersInSet:
                              [[NSCharacterSet decimalDigitCharacterSet] invertedSet]] integerValue];
            if (idx < [_plistObject count]) _plistObject[idx] = newValue;
        }

        [self savePlist];
        [self loadPlistObject:_plistObject];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action){
        if ([_plistObject isKindOfClass:[NSDictionary class]]) {
            [_plistObject removeObjectForKey:title];
        } else if ([_plistObject isKindOfClass:[NSArray class]]) {
            NSUInteger idx = [[title stringByTrimmingCharactersInSet:
                              [[NSCharacterSet decimalDigitCharacterSet] invertedSet]] integerValue];
            if (idx < [_plistObject count]) [_plistObject removeObjectAtIndex:idx];
        }
        [self savePlist];
        [self loadPlistObject:_plistObject];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - 追加

- (void)addItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"追加"
                                                                   message:@"新しいキー/値を入力"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.placeholder = @"キー (配列は空欄)"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.placeholder = @"値"; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"追加" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action){
        NSString *key = alert.textFields[0].text;
        NSString *valueStr = alert.textFields[1].text;
        id value = valueStr;

        if ([_plistObject isKindOfClass:[NSArray class]]) {
            [_plistObject addObject:value];
        } else if ([_plistObject isKindOfClass:[NSDictionary class]] && key.length > 0) {
            _plistObject[key] = value;
        }

        [self savePlist];
        [self loadPlistObject:_plistObject];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end