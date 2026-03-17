#import "SQLiteViewerViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import <sqlite3.h>

@interface SQLiteViewerViewController ()
<UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (strong) NSString  *path;
@property (strong) UITableView *tableView;
@property (strong) UITableView *schemaTable;   // top list of tables
@property (strong) UITextField *sqlField;
@property (strong) NSArray<NSString *>  *tableNames;
@property (strong) NSString             *currentTable;
@property (strong) NSArray<NSArray *>   *rows;
@property (strong) NSArray<NSString *>  *colNames;
@property (strong) UILabel              *statusLabel;
@end

@implementation SQLiteViewerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init]; if (self) { _path = path; } return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.path.lastPathComponent;
    self.view.backgroundColor = [ThemeEngine bg];
    [self setupUI];
    [self loadTables];
}

- (void)setupUI {
    // SQL input bar at top
    UIView *sqlBar = [[UIView alloc] init];
    sqlBar.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassToView:sqlBar radius:0];
    [self.view addSubview:sqlBar];

    _sqlField = [[UITextField alloc] init];
    _sqlField.translatesAutoresizingMaskIntoConstraints = NO;
    _sqlField.placeholder = @"SELECT * FROM table WHERE ...";
    _sqlField.textColor = [ThemeEngine textPrimary];
    _sqlField.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _sqlField.autocorrectionType = UITextAutocorrectionTypeNo;
    _sqlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _sqlField.returnKeyType = UIReturnKeyGo;
    _sqlField.delegate = self;
    _sqlField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"SELECT * FROM ..."
        attributes:@{NSForegroundColorAttributeName:[ThemeEngine textTertiary]}];
    [sqlBar addSubview:_sqlField];

    UIButton *runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    runBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    [runBtn setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    runBtn.tintColor = [ThemeEngine accent];
    [runBtn addTarget:self action:@selector(executeSQL) forControlEvents:UIControlEventTouchUpInside];
    [sqlBar addSubview:runBtn];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [ThemeEngine fontCaption];
    _statusLabel.textColor = [ThemeEngine textTertiary];
    _statusLabel.text = @"テーブルを読み込み中...";
    [self.view addSubview:_statusLabel];

    // Table list (left sidebar on wide, or top bar)
    _schemaTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _schemaTable.translatesAutoresizingMaskIntoConstraints = NO;
    _schemaTable.delegate = self;
    _schemaTable.dataSource = self;
    _schemaTable.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.04];
    _schemaTable.separatorColor = [ThemeEngine border];
    _schemaTable.tag = 100; // schema table tag
    [self.view addSubview:_schemaTable];

    // Data table
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorColor = [ThemeEngine border];
    _tableView.tag = 200;
    [self.view addSubview:_tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [sqlBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [sqlBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sqlBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [sqlBar.heightAnchor constraintEqualToConstant:48],

        [_sqlField.leadingAnchor constraintEqualToAnchor:sqlBar.leadingAnchor constant:12],
        [_sqlField.trailingAnchor constraintEqualToAnchor:runBtn.leadingAnchor constant:-8],
        [_sqlField.centerYAnchor constraintEqualToAnchor:sqlBar.centerYAnchor],
        [runBtn.trailingAnchor constraintEqualToAnchor:sqlBar.trailingAnchor constant:-12],
        [runBtn.centerYAnchor constraintEqualToAnchor:sqlBar.centerYAnchor],
        [runBtn.widthAnchor constraintEqualToConstant:36],

        [_statusLabel.topAnchor constraintEqualToAnchor:sqlBar.bottomAnchor constant:4],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],

        [_schemaTable.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:4],
        [_schemaTable.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_schemaTable.widthAnchor constraintEqualToConstant:130],
        [_schemaTable.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_tableView.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:4],
        [_tableView.leadingAnchor constraintEqualToAnchor:_schemaTable.trailingAnchor constant:1],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Nav bar buttons
    UIBarButtonItem *exportBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                style:UIBarButtonItemStylePlain target:self action:@selector(exportCSV)];
    UIBarButtonItem *insertBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus"]
                style:UIBarButtonItemStylePlain target:self action:@selector(insertRow)];
    self.navigationItem.rightBarButtonItems = @[exportBtn, insertBtn];
}

#pragma mark - Data Loading

- (void)loadTables {
    sqlite3 *db;
    if (sqlite3_open([self.path UTF8String], &db) != SQLITE_OK) {
        _statusLabel.text = @"DB を開けません";
        return;
    }
    NSMutableArray *tables = [NSMutableArray array];
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;", -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *n = (const char *)sqlite3_column_text(stmt, 0);
            if (n) [tables addObject:[NSString stringWithUTF8String:n]];
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    _tableNames = tables;
    [_schemaTable reloadData];
    if (tables.count > 0) [self loadTable:tables[0]];
    else _statusLabel.text = @"テーブルなし";
}

- (void)loadTable:(NSString *)name {
    _currentTable = name;
    [self executeQuery:[NSString stringWithFormat:@"SELECT * FROM \"%@\" LIMIT 1000;", name]];
}

- (void)executeSQL {
    NSString *sql = [_sqlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (sql.length == 0) return;
    [_sqlField resignFirstResponder];
    [self executeQuery:sql];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self executeSQL]; return YES; }

- (void)executeQuery:(NSString *)sql {
    sqlite3 *db;
    if (sqlite3_open([self.path UTF8String], &db) != SQLITE_OK) {
        _statusLabel.text = @"DB エラー";
        return;
    }
    sqlite3_stmt *stmt;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *cols = [NSMutableArray array];

    if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        int colCount = sqlite3_column_count(stmt);
        for (int i = 0; i < colCount; i++) {
            const char *n = sqlite3_column_name(stmt, i);
            [cols addObject:n ? [NSString stringWithUTF8String:n] : @"?"];
        }
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableArray *row = [NSMutableArray array];
            for (int i = 0; i < colCount; i++) {
                const char *v = (const char *)sqlite3_column_text(stmt, i);
                [row addObject:v ? [NSString stringWithUTF8String:v] : @"NULL"];
            }
            [rows addObject:row];
        }
        sqlite3_finalize(stmt);
        _colNames = cols;
        _rows = rows;
        _statusLabel.text = [NSString stringWithFormat:@"%lu 行 / %lu 列", (unsigned long)rows.count, (unsigned long)cols.count];
    } else {
        const char *errMsg = sqlite3_errmsg(db);
        _statusLabel.text = [NSString stringWithFormat:@"エラー: %s", errMsg];
    }
    sqlite3_close(db);
    [_tableView reloadData];
}

#pragma mark - TableView DataSource

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (tv.tag == 100) return (NSInteger)_tableNames.count;
    return (NSInteger)(_rows.count + 1); // +1 for header
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return tv.tag == 100 ? 44 : 36;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (tv.tag == 100) {
        // Schema table
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"Schema"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Schema"];
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.textColor = [ThemeEngine textPrimary];
            cell.textLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            cell.textLabel.numberOfLines = 2;
            UIView *sel = [[UIView alloc] init];
            sel.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.15];
            cell.selectedBackgroundView = sel;
        }
        NSString *name = _tableNames[ip.row];
        cell.textLabel.text = name;
        cell.textLabel.textColor = [name isEqualToString:_currentTable]
            ? [ThemeEngine accent] : [ThemeEngine textPrimary];
        return cell;
    }
    // Data table
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"DataCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DataCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        cell.textLabel.numberOfLines = 1;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    if (ip.row == 0) {
        // Header row
        cell.textLabel.text = [_colNames componentsJoinedByString:@"  |  "];
        cell.textLabel.textColor = [ThemeEngine accent];
        cell.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.08];
    } else {
        NSArray *row = _rows[ip.row - 1];
        cell.textLabel.text = [row componentsJoinedByString:@"  |  "];
        cell.textLabel.textColor = [ThemeEngine textPrimary];
        cell.backgroundColor = (ip.row % 2 == 0)
            ? [UIColor colorWithWhite:1 alpha:0.02] : [UIColor clearColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (tv.tag == 100) {
        [self loadTable:_tableNames[ip.row]];
    } else if (ip.row > 0) {
        [self showRowActions:_rows[ip.row - 1] atIndex:ip.row - 1];
    }
}

- (void)showRowActions:(NSArray *)row atIndex:(NSInteger)idx {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"行の操作"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"内容をコピー" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        UIPasteboard.generalPasteboard.string = [row componentsJoinedByString:@"\t"];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"この行を削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [self deleteRowAtIndex:idx];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _tableView;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)deleteRowAtIndex:(NSInteger)idx {
    if (!_currentTable || idx >= (NSInteger)_rows.count) return;
    NSArray *row = _rows[idx];
    if (_colNames.count == 0) return;
    // Build WHERE using first column
    NSString *firstCol = _colNames[0];
    NSString *firstVal = row[0];
    NSString *sql = [NSString stringWithFormat:@"DELETE FROM \"%@\" WHERE \"%@\" = '%@' LIMIT 1;",
                     _currentTable, firstCol, firstVal];
    sqlite3 *db;
    if (sqlite3_open([self.path UTF8String], &db) == SQLITE_OK) {
        sqlite3_exec(db, [sql UTF8String], NULL, NULL, NULL);
        sqlite3_close(db);
    }
    [self loadTable:_currentTable];
}

- (void)insertRow {
    if (!_currentTable) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"行を挿入"
        message:@"列の値をタブ区切りで入力 (列順に合わせて)"
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = [_colNames componentsJoinedByString:@"\t"];
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"挿入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSArray *vals = [a.textFields.firstObject.text componentsSeparatedByString:@"\t"];
        if (vals.count == 0) return;
        NSMutableArray *escaped = [NSMutableArray array];
        for (NSString *v in vals) [escaped addObject:[NSString stringWithFormat:@"'%@'", v]];
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO \"%@\" VALUES (%@);",
                         _currentTable, [escaped componentsJoinedByString:@", "]];
        sqlite3 *db;
        if (sqlite3_open([self.path UTF8String], &db) == SQLITE_OK) {
            char *errMsg;
            if (sqlite3_exec(db, [sql UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
                NSString *errStr = [NSString stringWithUTF8String:errMsg];
                sqlite3_free(errMsg);
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"エラー"
                        message:errStr preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:err animated:YES completion:nil];
                });
            }
            sqlite3_close(db);
        }
        [self loadTable:_currentTable];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)exportCSV {
    if (_rows.count == 0 || _colNames.count == 0) return;
    NSMutableString *csv = [NSMutableString string];
    [csv appendFormat:@"%@\n", [_colNames componentsJoinedByString:@","]];
    for (NSArray *row in _rows) {
        NSMutableArray *escaped = [NSMutableArray array];
        for (NSString *v in row) {
            NSString *val = [v containsString:@","] ? [NSString stringWithFormat:@"\"%@\"", v] : v;
            [escaped addObject:val];
        }
        [csv appendFormat:@"%@\n", [escaped componentsJoinedByString:@","]];
    }
    NSString *outPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [_currentTable stringByAppendingPathExtension:@"csv"]];
    [csv writeToFile:outPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:outPath]] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:avc animated:YES completion:nil];
}
@end
