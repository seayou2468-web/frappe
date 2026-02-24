#import "ProcessListViewController.h"
#import "JITEnableContext.h"
#import "ThemeEngine.h"

@interface ProcessListViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSDictionary *> *allProcesses;
@property (strong, nonatomic) NSArray<NSDictionary *> *filteredProcesses;
@property (strong, nonatomic) UISearchBar *searchBar;
@end

@implementation ProcessListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = @"Processes";

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadProcesses)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self setupUI];
    [self loadProcesses];
}

- (void)setupUI {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.delegate = self;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)loadProcesses {
    NSError *error;
    self.allProcesses = [[JITEnableContext shared] fetchProcessListWithError:&error];
    if (error) {
        NSLog(@"Process list error: %@", error);
    }
    [self filterProcesses];
}

- (void)filterProcesses {
    if (self.searchBar.text.length == 0) {
        self.filteredProcesses = self.allProcesses;
    } else {
        NSString *query = self.searchBar.text.lowercaseString;
        NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *proc, NSDictionary *bindings) {
            NSString *name = [proc[@"path"] lastPathComponent].lowercaseString;
            NSString *pid = [proc[@"pid"] stringValue];
            return [name containsString:query] || [pid containsString:query];
        }];
        self.filteredProcesses = [self.allProcesses filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterProcesses];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredProcesses.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"ProcessCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    }

    NSDictionary *proc = self.filteredProcesses[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"PID: %@ - %@", proc[@"pid"], [proc[@"path"] lastPathComponent]];
    cell.detailTextLabel.text = proc[@"path"];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *proc = self.filteredProcesses[indexPath.row];
    [self showProcessActions:proc];
}

- (void)showProcessActions:(NSDictionary *)proc {
    int pid = [proc[@"pid"] intValue];
    NSString *name = [proc[@"path"] lastPathComponent];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name message:[NSString stringWithFormat:@"PID: %d\nPath: %@", pid, proc[@"path"]] preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Force Kill (SIGKILL)" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *err;
        [[JITEnableContext shared] killProcessWithPID:pid signal:9 error:&err];
        [self loadProcesses];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Refresh" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self loadProcesses];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
