#import "SQLiteViewerViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import <sqlite3.h>

@interface SQLiteViewerViewController ()
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSString *> *tables;
@property (strong, nonatomic) NSString *currentTable;
@property (strong, nonatomic) NSArray<NSArray<NSString *> *> *rows;
@property (strong, nonatomic) NSArray<NSString *> *columnNames;
@end

@implementation SQLiteViewerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = path;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.path lastPathComponent];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    UIBarButtonItem *tableBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"list.bullet"] style:UIBarButtonItemStylePlain target:self action:@selector(showTablePicker)];
    self.navigationItem.rightBarButtonItem = tableBtn;

    [self loadTables];
}

- (void)loadTables {
    sqlite3 *db;
    if (sqlite3_open([self.path UTF8String], &db) == SQLITE_OK) {
        NSMutableArray *mut = [NSMutableArray array];
        const char *sql = "SELECT name FROM sqlite_master WHERE type='table';";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *name = (const char *)sqlite3_column_text(stmt, 0);
                if (name) [mut addObject:[NSString stringWithUTF8String:name]];
            }
            sqlite3_finalize(stmt);
        }
        self.tables = mut;
        sqlite3_close(db);

        if (self.tables.count > 0) [self loadTable:self.tables[0]];
    }
}

- (void)loadTable:(NSString *)tableName {
    self.currentTable = tableName;
    self.title = tableName;

    sqlite3 *db;
    if (sqlite3_open([self.path UTF8String], &db) == SQLITE_OK) {
        NSMutableArray *mutRows = [NSMutableArray array];
        NSMutableArray *mutCols = [NSMutableArray array];

        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM \"%@\" LIMIT 500;", tableName];
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            int colCount = sqlite3_column_count(stmt);
            for (int i=0; i<colCount; i++) {
                [mutCols addObject:[NSString stringWithUTF8String:sqlite3_column_name(stmt, i)]];
            }

            while (sqlite3_step(stmt) == SQLITE_ROW) {
                NSMutableArray *row = [NSMutableArray array];
                for (int i=0; i<colCount; i++) {
                    const char *val = (const char *)sqlite3_column_text(stmt, i);
                    [row addObject:val ? [NSString stringWithUTF8String:val] : @"NULL"];
                }
                [mutRows addObject:row];
            }
            sqlite3_finalize(stmt);
        }
        self.columnNames = mutCols;
        self.rows = mutRows;
        sqlite3_close(db);
        [self.tableView reloadData];
    }
}

- (void)showTablePicker {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"テーブル選択"];
    for (NSString *t in self.tables) {
        [menu addAction:[CustomMenuAction actionWithTitle:t systemImage:@"tablecells" style:CustomMenuActionStyleDefault handler:^{
            [self loadTable:t];
        }]];
    }
    [menu showInView:self.view];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SqlCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SqlCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor grayColor];
        cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10];
        cell.detailTextLabel.numberOfLines = 2;
    }

    NSArray *row = self.rows[indexPath.row];
    cell.textLabel.text = row.count > 0 ? row[0] : @"";

    NSMutableString *details = [NSMutableString string];
    for (int i=0; i<row.count; i++) {
        [details appendFormat:@"%@: %@ | ", self.columnNames[i], row[i]];
    }
    cell.detailTextLabel.text = details;

    return cell;
}

@end
