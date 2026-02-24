#import "PlistEditorViewController.h"

@interface PlistEditorViewController () <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) id rootObject;
@property (strong, nonatomic) id currentObject;
@property (strong, nonatomic) NSString *currentKey;
@property (assign, nonatomic) NSPropertyListFormat format;
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSMutableArray *keys;
@end

@implementation PlistEditorViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = path;
        [self loadPlist];
    }
    return self;
}

- (instancetype)initWithValue:(id)value key:(NSString *)key root:(id)root {
    self = [super init];
    if (self) {
        _currentObject = value;
        _currentKey = key;
        _rootObject = root;
        self.title = key;
    }
    return self;
}

- (void)loadPlist {
    NSData *data = [NSData dataWithContentsOfFile:self.path];
    if (!data) {
        _rootObject = [NSMutableDictionary dictionary];
        _format = NSPropertyListXMLFormat_v1_0;
    } else {
        NSError *error;
        _rootObject = [NSPropertyListSerialization propertyListWithData:data
                                                                options:NSPropertyListMutableContainersAndLeaves
                                                                 format:&_format
                                                                  error:&error];
    }
    _currentObject = _rootObject;
    self.title = self.path.lastPathComponent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(savePlist)];
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addItem)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, addBtn];

    [self refreshKeys];
}

- (void)refreshKeys {
    if ([_currentObject isKindOfClass:[NSDictionary class]]) {
        _keys = [[[_currentObject allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)] mutableCopy];
    } else if ([_currentObject isKindOfClass:[NSArray class]]) {
        _keys = [NSMutableArray array];
        for (NSInteger i = 0; i < [_currentObject count]; i++) {
            [_keys addObject:@(i)];
        }
    }
    [self.tableView reloadData];
}

- (void)savePlist {
    if (!self.path) return;

    NSError *error;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:_rootObject
                                                              format:_format
                                                             options:0
                                                               error:&error];
    if (data) {
        [data writeToFile:self.path atomically:YES];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)addItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Item" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Key"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Value (String)"; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *key = alert.textFields[0].text;
        NSString *val = alert.textFields[1].text;
        if ([self.currentObject isKindOfClass:[NSDictionary class]]) {
            self.currentObject[key] = val;
        } else if ([self.currentObject isKindOfClass:[NSArray class]]) {
            [(NSMutableArray *)self.currentObject addObject:val];
        }
        [self refreshKeys];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _keys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"PlistCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    id key = _keys[indexPath.row];
    id value = _currentObject[key];

    cell.textLabel.text = [NSString stringWithFormat:@"%@", key];

    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%lu items)", [value class], (unsigned long)[value count]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %@", [value class], value];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id key = _keys[indexPath.row];
    id value = _currentObject[key];

    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        PlistEditorViewController *vc = [[PlistEditorViewController alloc] initWithValue:value key:[NSString stringWithFormat:@"%@", key] root:_rootObject];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        [self editValueForKey:key];
    }
}

- (void)editValueForKey:(id)key {
    id value = _currentObject[key];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Value" message:[NSString stringWithFormat:@"Key: %@", key] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [NSString stringWithFormat:@"%@", value]; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        self.currentObject[key] = alert.textFields[0].text;
        [self.tableView reloadData];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        if ([self.currentObject isKindOfClass:[NSDictionary class]]) {
            [self.currentObject removeObjectForKey:key];
        } else if ([self.currentObject isKindOfClass:[NSArray class]]) {
            [self.currentObject removeObjectAtIndex:[key integerValue]];
        }
        [self refreshKeys];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
