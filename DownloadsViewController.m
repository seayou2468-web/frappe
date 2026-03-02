#import "DownloadsViewController.h"
#import "DownloadManager.h"
#import "ThemeEngine.h"

@interface DownloadsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation DownloadsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ダウンロード";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"すべて消去" style:UIBarButtonItemStylePlain target:self action:@selector(clearAll)];

    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData) name:@"DownloadUpdated" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData) name:@"DownloadStarted" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData) name:@"DownloadFinished" object:nil];
}

- (void)clearAll {
    [[DownloadManager sharedManager] clearCompletedTasks];
    [self.tableView reloadData];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [DownloadManager sharedManager].tasks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"DownloadCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];

        UIProgressView *pv = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        pv.tag = 100;
        pv.translatesAutoresizingMaskIntoConstraints = NO;
        pv.progressTintColor = [ThemeEngine liquidColor];
        [cell.contentView addSubview:pv];

        [NSLayoutConstraint activateConstraints:@[
            [pv.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
            [pv.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
            [pv.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-5],
            [pv.heightAnchor constraintEqualToConstant:2]
        ]];
    }

    DownloadTask *task = [DownloadManager sharedManager].tasks[indexPath.row];
    cell.textLabel.text = task.filename;

    if (task.isDownloading) {
        NSString *received = [NSByteCountFormatter stringFromByteCount:task.receivedBytes countStyle:NSByteCountFormatterCountStyleFile];
        NSString *total = [NSByteCountFormatter stringFromByteCount:task.totalBytes countStyle:NSByteCountFormatterCountStyleFile];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ / %@ (%.0f%%)", received, total, task.progress * 100];
    } else {
        cell.detailTextLabel.text = @"完了";
    }

    UIProgressView *pv = (UIProgressView *)[cell.contentView viewWithTag:100];
    pv.progress = task.progress;
    pv.hidden = !task.isDownloading;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
