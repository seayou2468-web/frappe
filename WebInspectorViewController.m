#import "WebInspectorViewController.h"
#import "ThemeEngine.h"

@interface WebInspectorViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextView *sourceView;
@property (nonatomic, strong) UITextField *consoleInput;
@end

@implementation WebInspectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PCインスペクタ";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"要素", @"コンソール", @"ネット", @"保持データ"]];
    self.segmentedControl.selectedSegmentIndex = 1;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentedControl;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    [self.view addSubview:self.tableView];

    self.sourceView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.sourceView.editable = NO;
    self.sourceView.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1.0];
    self.sourceView.textColor = [UIColor whiteColor];
    self.sourceView.font = [UIFont fontWithName:@"Menlo" size:10];
    self.sourceView.hidden = YES;
    [self.view addSubview:self.sourceView];

    self.consoleInput = [[UITextField alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height-50, self.view.bounds.size.width, 50)];
    self.consoleInput.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.consoleInput.textColor = [UIColor cyanColor];
    self.consoleInput.font = [UIFont fontWithName:@"Menlo" size:13];
    self.consoleInput.placeholder = @"> JS実行";
    self.consoleInput.delegate = self;
    self.consoleInput.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 10)];
    self.consoleInput.leftViewMode = UITextFieldViewModeAlways;
    self.consoleInput.autocorrectionType = UITextAutocorrectionTypeNo;
    self.consoleInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:self.consoleInput];

    [self updateView];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self updateView];
}

- (void)updateView {
    self.tableView.hidden = NO;
    self.sourceView.hidden = YES;
    self.consoleInput.hidden = (self.segmentedControl.selectedSegmentIndex != 1);

    if (self.segmentedControl.selectedSegmentIndex == 0) {
        self.sourceView.hidden = NO;
        self.tableView.hidden = YES;
        self.sourceView.text = self.htmlSource;
    }

    [self.tableView reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.onCommand) self.onCommand(textField.text);
    textField.text = @"";
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.segmentedControl.selectedSegmentIndex == 3) return 3; // Cookies, Local, Session
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.segmentedControl.selectedSegmentIndex) {
        case 1: return self.consoleLogs.count;
        case 2: return self.networkLogs.count;
        case 3: {
            if (section == 0) return self.cookies.count;
            if (section == 1) return [self.storageData[@"local"] count];
            return [self.storageData[@"session"] count];
        }
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.segmentedControl.selectedSegmentIndex == 3) {
        if (section == 0) return @"Cookies";
        if (section == 1) return @"LocalStorage";
        return @"SessionStorage";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PCInspectorCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"PCInspectorCell"];
        cell.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:11];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:9];
    }

    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor grayColor];

    switch (self.segmentedControl.selectedSegmentIndex) {
        case 1:
            cell.textLabel.text = self.consoleLogs[indexPath.row];
            cell.textLabel.textColor = [cell.textLabel.text containsString:@"ERROR"] ? [UIColor systemRedColor] : [UIColor systemGreenColor];
            break;
        case 2: {
            NSDictionary *net = self.networkLogs[indexPath.row];
            cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", net[@"method"], net[@"url"]];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Status: %@ | Time: %@", net[@"status"], net[@"time"]];
            break;
        }
        case 3: {
            if (indexPath.section == 0) {
                NSHTTPCookie *cookie = self.cookies[indexPath.row];
                cell.textLabel.text = cookie.name;
                cell.detailTextLabel.text = cookie.value;
            } else {
                NSString *key = indexPath.section == 1 ? [self.storageData[@"local"] allKeys][indexPath.row] : [self.storageData[@"session"] allKeys][indexPath.row];
                NSString *val = indexPath.section == 1 ? self.storageData[@"local"][key] : self.storageData[@"session"][key];
                cell.textLabel.text = key;
                cell.detailTextLabel.text = val;
            }
            break;
        }
    }

    return cell;
}

@end
