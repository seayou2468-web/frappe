#import "ExcelViewerViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"

@interface ExcelViewerViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) NSMutableArray<NSMutableArray<NSString *> *> *data;
@property (strong, nonatomic) NSMutableArray<NSMutableArray<NSString *> *> *filteredData;
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (assign, nonatomic) NSInteger columnCount;
@end

@implementation ExcelViewerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _path = path; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _path.lastPathComponent;
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"セル内容を検索...";
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveData)];
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(showAddMenu)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, addBtn];

    [self loadData];
}

- (void)showAddMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"データ操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"行を追加" systemImage:@"plus.rectangle" style:CustomMenuActionStyleDefault handler:^{ [self addRow]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"列を追加" systemImage:@"plus.rectangle.fill" style:CustomMenuActionStyleDefault handler:^{ [self addColumn]; }]];
    [menu showInView:self.view];
}

- (void)addColumn {
    self.columnCount++;
    for (NSMutableArray *row in self.data) [row addObject:@""];
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredData = self.data;
    } else {
        NSMutableArray *res = [NSMutableArray array];
        for (NSArray *row in self.data) {
            BOOL found = NO;
            for (NSString *cell in row) {
                if ([cell rangeOfString:searchText options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    found = YES; break;
                }
            }
            if (found) [res addObject:row];
        }
        self.filteredData = res;
    }
    [self.tableView reloadData];
}

- (void)loadData {
    NSString *content = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:nil];
    if (!content) return;

    self.data = [NSMutableArray array]; self.filteredData = self.data;
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    self.columnCount = 0;

    for (NSString *line in lines) {
        if (line.length == 0) continue;
        NSArray *parts = [line componentsSeparatedByString:@","]; // Default to CSV
        if (parts.count == 1 && [line containsString:@"\t"]) parts = [line componentsSeparatedByString:@"\t"];

        [self.data addObject:[parts mutableCopy]];
        if ((NSInteger)parts.count > self.columnCount) self.columnCount = parts.count;
    }
    [self.tableView reloadData];
}

- (void)addRow {
    NSMutableArray *newRow = [NSMutableArray array];
    for (int i=0; i<self.columnCount; i++) [newRow addObject:@""];
    [self.data addObject:newRow]; self.filteredData = self.data;
    [self.tableView reloadData];
}

- (void)saveData {
    NSMutableString *outStr = [NSMutableString string];
    for (NSArray *row in self.data) {
        [outStr appendString:[row componentsJoinedByString:@","]];
        [outStr appendString:@"\n"];
    }
    [outStr writeToFile:_path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filteredData.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ExcelCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ExcelCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:12];
    }
    NSArray *row = self.filteredData[indexPath.row];
    cell.textLabel.text = [row componentsJoinedByString:@" | "];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self editRow:indexPath.row];
}

- (void)editRow:(NSInteger)rowIdx {
    NSMutableArray *row = self.data[rowIdx];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"行編集" message:@"カンマ区切りで入力" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [row componentsJoinedByString:@","]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *val = alert.textFields[0].text;
        [self.data replaceObjectAtIndex:rowIdx withObject:[[val componentsSeparatedByString:@","] mutableCopy]]; self.filteredData = self.data;
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
