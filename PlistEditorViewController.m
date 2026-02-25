#import "PlistEditorViewController.h"
#import "ThemeEngine.h"

@interface PlistEditorViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) id rootObject;
@property (nonatomic, strong) id currentObject;
@property (nonatomic, strong) NSMutableArray *keys;
@property (nonatomic, assign) NSPropertyListFormat format;
@property (nonatomic, strong) NSUndoManager *plistUndoManager;
@property (nonatomic, strong) NSString *currentKey;
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
        _path = nil;
    }
    return self;
}

- (void)loadPlist {
    if (!_path) return;
    NSData *data = [NSData dataWithContentsOfFile:_path];
    if (!data) return;

    NSError *error;
    NSPropertyListFormat format;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:&format error:&error];
    if (plist) {
        _rootObject = plist;
        _currentObject = plist;
        _format = format;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = _currentKey ?: [_path lastPathComponent];

    [self setupUI];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.tableView];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(savePlist)];
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addItem)];
    UIBarButtonItem *undoBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemUndo target:self action:@selector(undoAction)];
    UIBarButtonItem *redoBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRedo target:self action:@selector(redoAction)];

    UIBarButtonItem *resetBtn = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(resetPlist)];

    if (_path) {
        self.navigationItem.rightBarButtonItems = @[saveBtn, addBtn, resetBtn];
    } else {
        self.navigationItem.rightBarButtonItems = @[addBtn];
    }
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
    if (!_path) return;
    NSError *error;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:_rootObject format:_format options:0 error:&error];
    if (data) {
        [data writeToFile:_path atomically:YES];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)updateObject:(id)obj forKey:(id)key newValue:(id)newVal {
    if ([obj isKindOfClass:[NSMutableDictionary class]]) {
        id oldVal = obj[key];
        [[_plistUndoManager prepareWithInvocationTarget:self] updateObject:obj forKey:key newValue:oldVal];
        if (newVal) obj[key] = newVal;
        else [obj removeObjectForKey:key];
    } else if ([obj isKindOfClass:[NSMutableArray class]]) {
        NSInteger index = [key integerValue];
        id oldVal = (index < [obj count]) ? obj[index] : nil;
        [[_plistUndoManager prepareWithInvocationTarget:self] updateObject:obj forKey:key newValue:oldVal];
        if (newVal) {
            if (index < [obj count]) obj[index] = newVal;
            else [obj addObject:newVal];
        } else {
            if (index < [obj count]) [obj removeObjectAtIndex:index];
        }
    }
    [self refreshKeys];
}

- (void)addItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Entry" message:nil preferredStyle:UIAlertControllerStyleAlert];
    if ([_currentObject isKindOfClass:[NSDictionary class]]) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Key"; }];
    }

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
    if ([type isEqualToString:@"String"]) val = [NSMutableString stringWithString:@""];
    else if ([type isEqualToString:@"Number"]) val = @0;
    else if ([type isEqualToString:@"Boolean"]) val = @NO;
    else if ([type isEqualToString:@"Date"]) val = [NSDate date];
    else if ([type isEqualToString:@"Data"]) val = [NSMutableData data];
    else if ([type isEqualToString:@"Array"]) val = [NSMutableArray array];
    else if ([type isEqualToString:@"Dictionary"]) val = [NSMutableDictionary dictionary];

    if ([_currentObject isKindOfClass:[NSDictionary class]]) {
        if (key) [self updateObject:_currentObject forKey:key newValue:val];
    } else {
        [self updateObject:_currentObject forKey:@([_currentObject count]) newValue:val];
    }
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
    id value = ([_currentObject isKindOfClass:[NSDictionary class]]) ? _currentObject[key] : _currentObject[[key integerValue]];
    cell.textLabel.text = [NSString stringWithFormat:@"%@", key];

    NSString *typeStr = NSStringFromClass([value class]);
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%lu items)", typeStr, (unsigned long)[value count]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %@", typeStr, value];
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id key = _keys[indexPath.row];
    id value = ([_currentObject isKindOfClass:[NSDictionary class]]) ? _currentObject[key] : _currentObject[[key integerValue]];
    if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        PlistEditorViewController *vc = [[PlistEditorViewController alloc] initWithValue:value key:[NSString stringWithFormat:@"%@", key] root:_rootObject undo:_plistUndoManager];
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        [self editValueForKey:key];
    }
}

- (void)editValueForKey:(id)key {
    id value = ([_currentObject isKindOfClass:[NSDictionary class]]) ? _currentObject[key] : _currentObject[[key integerValue]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Entry" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [NSString stringWithFormat:@"%@", value]; }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields[0].text;
        id newValue = text;

        if ([value isKindOfClass:[NSNumber class]]) {
            const char *objCType = [value objCType];
            if (strcmp(objCType, "c") == 0 || strcmp(objCType, "b") == 0) { // Boolean
                newValue = @([text boolValue]);
            } else {
                newValue = @([text doubleValue]);
            }
        } else if ([value isKindOfClass:[NSDate class]]) {
             NSDateFormatter *df = [[NSDateFormatter alloc] init];
             df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
             newValue = [df dateFromString:text] ?: value;
        } else if ([value isKindOfClass:[NSData class]]) {
            // Very simple hex string to data conversion or keep original if failed
        }

        [self updateObject:self.currentObject forKey:key newValue:newValue];
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

- (void)resetPlist {
    if (!_path) return;
    [self loadPlist];
    [_plistUndoManager removeAllActions];
    [self refreshKeys];
}

@end
