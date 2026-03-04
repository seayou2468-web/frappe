#import "WebInspectorViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"

@interface WebInspectorViewController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, assign) NSInteger activeTabIndex;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *consoleInput;
@property (nonatomic, strong) UIView *inputContainer;
@property (nonatomic, strong) NSArray<NSDictionary *> *elementsTree;
@property (nonatomic, strong) NSMutableArray<NSString *> *commandHistory;
@end

@implementation WebInspectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"デベロッパーツール";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.commandHistory = [NSMutableArray array];

    [self setupHeader];
    [self setupTableView];
    [self setupConsoleInput];

    [self parseElements];
    [self selectTab:1];
}

- (void)setupHeader {
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    [ThemeEngine applyGlassStyleToView:self.headerView cornerRadius:0];
    [self.view addSubview:self.headerView];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:self.headerView.bounds];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    [self.headerView addSubview:stack];

    self.tabButtons = [NSMutableArray array];
    NSArray *titles = @[@"要素", @"ログ", @"通信", @"保存"];
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:titles[i] forState:UIControlStateNormal];
        btn.tintColor = [UIColor grayColor];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        btn.tag = i;
        [btn addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
        [self.tabButtons addObject:btn];
    }
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)setupConsoleInput {
    self.inputContainer = [[UIView alloc] init];
    self.inputContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassStyleToView:self.inputContainer cornerRadius:0];
    [self.view addSubview:self.inputContainer];

    self.consoleInput = [[UITextField alloc] init];
    self.consoleInput.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleInput.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    self.consoleInput.textColor = [UIColor cyanColor];
    self.consoleInput.font = [UIFont fontWithName:@"Menlo" size:14];
    self.consoleInput.placeholder = @"> JS実行...";
    self.consoleInput.delegate = self;
    self.consoleInput.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    self.consoleInput.leftViewMode = UITextFieldViewModeAlways;
    self.consoleInput.layer.cornerRadius = 8;
    self.consoleInput.autocorrectionType = UITextAutocorrectionTypeNo;
    self.consoleInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.inputContainer addSubview:self.consoleInput];

    [NSLayoutConstraint activateConstraints:@[
        [self.inputContainer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.inputContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.inputContainer.heightAnchor constraintEqualToConstant:60],
        [self.consoleInput.topAnchor constraintEqualToAnchor:self.inputContainer.topAnchor constant:10],
        [self.consoleInput.leadingAnchor constraintEqualToAnchor:self.inputContainer.leadingAnchor constant:15],
        [self.consoleInput.trailingAnchor constraintEqualToAnchor:self.inputContainer.trailingAnchor constant:-15],
        [self.consoleInput.bottomAnchor constraintEqualToAnchor:self.inputContainer.bottomAnchor constant:-10],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputContainer.topAnchor],
    ]];
}

- (void)tabTapped:(UIButton *)sender { [self selectTab:sender.tag]; }
- (void)selectTab:(NSInteger)index {
    self.activeTabIndex = index;
    for (UIButton *btn in self.tabButtons) btn.tintColor = (btn.tag == index) ? [ThemeEngine liquidColor] : [UIColor grayColor];
    self.inputContainer.hidden = (index != 1);
    [self.tableView reloadData];
}

- (void)parseElements {
    NSMutableArray *tree = [NSMutableArray array];
    NSArray *lines = [self.htmlSource componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length > 0) {
            NSInteger indent = line.length - [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length;
            [tree addObject:@{@"tag": trimmed, @"indent": @(indent / 2)}];
        }
    }
    self.elementsTree = tree;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.onCommand && textField.text.length > 0) {
        [self.commandHistory addObject:textField.text];
        self.onCommand(textField.text);
        [self.consoleLogs addObject:[NSString stringWithFormat:@"JS> %@", textField.text]];
        [self.tableView reloadData];
        if (self.consoleLogs.count > 0) [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.consoleLogs.count-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    }
    textField.text = @"";
    return YES;
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.activeTabIndex == 3) return 3; // Cookies, Local, Session
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.activeTabIndex) {
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InspectorCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"InspectorCell"];
        cell.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
        cell.textLabel.font = [UIFont fontWithName:@"Menlo" size:11];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo" size:9];
    }
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor grayColor];

    switch (self.activeTabIndex) {
        case 0: {
            NSDictionary *el = self.elementsTree[indexPath.row];
            NSMutableString *str = [NSMutableString string];
            for(int i=0; i<[el[@"indent"] intValue]; i++) [str appendString:@"  "];
            [str appendFormat:@"%@", el[@"tag"]];
            cell.textLabel.text = str;
            cell.textLabel.textColor = [UIColor systemPurpleColor];
            break;
        }
        case 1:
            cell.textLabel.text = self.consoleLogs[indexPath.row];
            if ([cell.textLabel.text hasPrefix:@"JS>"]) cell.textLabel.textColor = [UIColor cyanColor];
            else if ([cell.textLabel.text containsString:@"ERROR"] || [cell.textLabel.text hasPrefix:@"ERR>"]) cell.textLabel.textColor = [UIColor systemRedColor];
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
                NSHTTPCookie *c = self.cookies[indexPath.row];
                cell.textLabel.text = c.name;
                cell.detailTextLabel.text = c.value;
            } else {
                NSDictionary *data = (indexPath.section == 1) ? self.storageData[@"local"] : self.storageData[@"session"];
                NSString *key = [data allKeys][indexPath.row];
                cell.textLabel.text = key;
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", data[key]];
            }
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.activeTabIndex == 2) [self showNetworkDetail:self.networkLogs[indexPath.row]];
    else if (self.activeTabIndex == 0) [self showElementOptions:self.elementsTree[indexPath.row]];
}

- (void)showNetworkDetail:(NSDictionary *)net {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"通信詳細"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"URLをコピー" systemImage:@"doc.on.doc" style:CustomMenuActionStyleDefault handler:^{ [[UIPasteboard generalPasteboard] setString:net[@"url"]]; }]];
    [menu showInView:self.view];
}

- (void)showElementOptions:(NSDictionary *)el {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"要素の操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"内容をコピー" systemImage:@"doc.on.doc" style:CustomMenuActionStyleDefault handler:^{ [[UIPasteboard generalPasteboard] setString:el[@"tag"]]; }]];
    [menu showInView:self.view];
}

@end
