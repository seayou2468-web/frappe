#import "WebHistoryViewController.h"
#import "WebHistoryManager.h"
#import "ThemeEngine.h"

@interface WebHistoryViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation WebHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"履歴";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"消去" style:UIBarButtonItemStylePlain target:self action:@selector(clearHistory)];
    self.navigationItem.rightBarButtonItem = clearBtn;
}

- (void)clearHistory {
    [[WebHistoryManager sharedManager] clearHistory];
    [self.tableView reloadData];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [WebHistoryManager sharedManager].history.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    }
    NSDictionary *entry = [WebHistoryManager sharedManager].history[indexPath.row];
    cell.textLabel.text = entry[@"title"];
    cell.detailTextLabel.text = entry[@"url"];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = [WebHistoryManager sharedManager].history[indexPath.row];
    if (self.onUrlSelected) self.onUrlSelected(entry[@"url"]);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
