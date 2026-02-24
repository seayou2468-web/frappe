#import "PlistEditorViewController.h"
#import "ThemeEngine.h"

@interface PlistEditorViewController () <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) id rootObject;
@property (strong, nonatomic) id currentObject;
@property (strong, nonatomic) NSString *currentKey;
@property (assign, nonatomic) NSPropertyListFormat format;
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSMutableArray *keys;
@property (strong, nonatomic) NSUndoManager *plistUndoManager;
@end

@implementation PlistEditorViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = path;
        _plistUndoManager = [[NSUndoManager alloc] init];
        [self loadPlist];
    }
    return self;
}

- (instancetype)initWithValue:(id)value key:(NSString *)key root:(id)root undo:(NSUndoManager *)undo {
    self = [super init];
    if (self) {
        _currentObject = value;
        _currentKey = key;
        _rootObject = root;
        _plistUndoManager = undo;
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
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
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
    UIBarButtonItem *undoBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemUndo target:self action:@selector(undoAction)];
    UIBarButtonItem *redoBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRedo target:self action:@selector(redoAction)];

    self.navigationItem.rightBarButtonItems = @[saveBtn, addBtn];
    self.navigationItem.leftBarButtonItems = @[undoBtn, redoBtn];

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

- (void)undoAction { if ([_plistUndoManager canUndo]) { [_plistUndoManager undo]; [self refreshKeys]; } }
- (void)redoAction { if ([_plistUndoManager canRedo]) { [_plistUndoManager redo]; [self refreshKeys]; } }

- (void)savePlist {
    if (!self.path) return;
    NSError *error;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:_rootObject format:_format options:0 error:&error];
    if (data) {
        [data writeToFile:self.path atomically:YES];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)updateObject:(id)obj forKey:(id)key newValue:(id)newVal {
    id oldVal = obj[key];
    [[_plistUndoManager prepareWithInvocationTarget:self] updateObject:obj forKey:key newValue:oldVal];
    if (newVal) obj[key] = newVal;
    else [obj removeObjectForKey:key];
    [self refreshKeys];
}

- (void)addItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Entry" message:nil preferredStyle:UIAlertControllerStyleAlert];
    if ([_currentObject isKindOfClass:[NSDictionary class]]) [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Key"; }];

    NSArray *types = @[@"String", @"Number", @"Boolean", @"Date", @"Data", @"Array", @"Dictionary"];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = ([self.currentObject isKindOfClass:[NSDictionary class]]) ? alert.textFields[0].text : nil;
        [self showTypeSelectionForKey:key];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showTypeSelectionForKey:(id)key {
    UIAlertController *typeAlert = [UIAlertController alertControllerWithTitle:@"Select Type" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *types = @[@"String", @"Number", @"Boolean", @"Date", @"Data", @"Array", @"Dictionary"];
    for (NSString *t in types) {
        [typeAlert addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self createItemOfType:t forKey:key];
        }]];
    }
    [typeAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:typeAlert animated:YES completion:nil];
}

- (void)createItemOfType:(NSString *)type forKey:(id)key {
    id val = nil;
    if ([type isEqualToString:@"String"]) val = @"";
    else if ([type isEqualToString:@"Number"]) val = @0;
    else if ([type isEqualToString:@"Boolean"]) val = @NO;
    else if ([type isEqualToString:@"Date"]) val = [NSDate date];
    else if ([type isEqualToString:@"Data"]) val = [NSData data];
    else if ([type isEqualToString:@"Array"]) val = [NSMutableArray array];
    else if ([type isEqualToString:@"Dictionary"]) val = [NSMutableDictionary dictionary];

    if ([_currentObject isKindOfClass:[NSDictionary class]]) [self updateObject:_currentObject forKey:key newValue:val];
    else [(NSMutableArray *)_currentObject addObject:val];
    [self refreshKeys];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _keys.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"PlistCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    }
    id key = _keys[indexPath.row];
    id value = _currentObject[key];
    cell.textLabel.text = [NSString stringWithFormat:@"%@", key];
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%lu)", [value class], (unsigned long)[value count]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %@", [value class], value];
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id key = _keys[indexPath.row];
    id value = _currentObject[key];
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        PlistEditorViewController *vc = [[PlistEditorViewController alloc] initWithValue:value key:[NSString stringWithFormat:@"%@", key] root:_rootObject undo:_plistUndoManager];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        [self editValueForKey:key];
    }
}

- (void)editValueForKey:(id)key {
    id value = _currentObject[key];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Entry" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [NSString stringWithFormat:@"%@", value]; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self updateObject:self.currentObject forKey:key newValue:alert.textFields[0].text];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Change Type" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showTypeSelectionForKey:key];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self updateObject:self.currentObject forKey:key newValue:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
