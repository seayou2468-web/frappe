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
    self.view.backgroundColor = [ThemeEngine bg];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor = [ThemeEngine border];
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
        cell.textLabel.textColor = [ThemeEngine textPrimary];
        cell.textLabel.font = [ThemeEngine fontBody];
        cell.detailTextLabel.textColor = [ThemeEngine textSecondary];
        cell.detailTextLabel.font = [ThemeEngine fontCaption];
        UIView *_selBg = [[UIView alloc] init];
        _selBg.backgroundColor = [[ThemeEngine accent] colorWithAlphaComponent:0.12];
        cell.selectedBackgroundView = _selBg;

        UIProgressView *pv = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        pv.tag = 100;
        pv.translatesAutoresizingMaskIntoConstraints = NO;
        pv.progressTintColor = [ThemeEngine accent];
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

    if (!task.isDownloading && task.resumeData) {
        UIButton *resumeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [resumeBtn setTitle:@"再開" forState:UIControlStateNormal];
        resumeBtn.tag = indexPath.row;
        [resumeBtn addTarget:self action:@selector(resumeTapped:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = resumeBtn;
    } else {
        cell.accessoryView = nil;
    }

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

- (void)resumeTapped:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row < [DownloadManager sharedManager].tasks.count) {
        DownloadTask *task = [DownloadManager sharedManager].tasks[row];
        [[DownloadManager sharedManager] resumeTask:task];
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
