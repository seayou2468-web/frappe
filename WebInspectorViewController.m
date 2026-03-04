#import "WebInspectorViewController.h"
#import "ThemeEngine.h"

@interface WebInspectorViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *consoleInput;
@property (nonatomic, strong) NSArray<NSDictionary *> *elementsTree;
@end

@implementation WebInspectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"開発者ツール";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"要素", @"コンソール", @"ネットワーク", @"ストレージ"]];
    self.segmentedControl.selectedSegmentIndex = 1;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentedControl;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.02 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 60, 0);
    [self.view addSubview:self.tableView];

    self.consoleInput = [[UITextField alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height-60, self.view.bounds.size.width, 60)];
    self.consoleInput.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.consoleInput.textColor = [UIColor cyanColor];
    self.consoleInput.font = [UIFont fontWithName:@"Menlo-Bold" size:14];
    self.consoleInput.placeholder = @"> JavaScriptを実行";
    self.consoleInput.delegate = self;
    self.consoleInput.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 15, 10)];
    self.consoleInput.leftViewMode = UITextFieldViewModeAlways;
    self.consoleInput.autocorrectionType = UITextAutocorrectionTypeNo;
    self.consoleInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:self.consoleInput];

    [self parseElements];
    [self updateView];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self updateView];
}

- (void)updateView {
    self.consoleInput.hidden = (self.segmentedControl.selectedSegmentIndex != 1);
    [self.tableView reloadData];
}

- (void)parseElements {
    // Basic element extraction logic could go here
    _elementsTree = @[@{@"tag": @"html", @"indent": @0}, @{@"tag": @"head", @"indent": @1}, @{@"tag": @"body", @"indent": @1}];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.onCommand && textField.text.length > 0) {
        self.onCommand(textField.text);
        [self.consoleLogs addObject:[NSString stringWithFormat:@"JS> %@", textField.text]];
        [self.tableView reloadData];
    }
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
        case 0: return self.elementsTree.count;
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DevToolCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DevToolCell"];
        cell.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:12];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:10];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];

    switch (self.segmentedControl.selectedSegmentIndex) {
        case 0: {
            NSDictionary *el = self.elementsTree[indexPath.row];
            NSString *tag = el[@"tag"];
            NSInteger indent = [el[@"indent"] integerValue];
            NSMutableString *str = [NSMutableString string];
            for(int i=0; i<indent; i++) [str appendString:@"  "];
            [str appendFormat:@"<%@>", tag];
            cell.textLabel.text = str;
            cell.textLabel.textColor = [UIColor systemPurpleColor];
            break;
        }
        case 1:
            cell.textLabel.text = self.consoleLogs[indexPath.row];
            if ([cell.textLabel.text hasPrefix:@"JS>"]) cell.textLabel.textColor = [UIColor cyanColor];
            else if ([cell.textLabel.text containsString:@"ERROR"]) cell.textLabel.textColor = [UIColor systemRedColor];
            else cell.textLabel.textColor = [UIColor systemGreenColor];
            break;
        case 2: {
            NSDictionary *net = self.networkLogs[indexPath.row];
            cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", net[@"method"], net[@"url"]];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Status: %@ | %@", net[@"status"], net[@"time"]];
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.segmentedControl.selectedSegmentIndex == 2) {
        [self showNetworkDetail:self.networkLogs[indexPath.row]];
    }
}

- (void)showNetworkDetail:(NSDictionary *)net {
    NSMutableString *str = [NSMutableString string];
    [str appendFormat:@"URL: %@\n", net[@"url"]];
    [str appendFormat:@"Method: %@\n", net[@"method"]];
    [str appendFormat:@"Status: %@\n", net[@"status"]];
    [str appendFormat:@"Time: %@\n", net[@"time"]];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ネットワーク詳細" message:str preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
