#import "ProcessListViewController.h"
#import "JITEnableContext.h"
#import "ThemeEngine.h"

@interface ProcessListViewController ()
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSDictionary *> *processes;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation ProcessListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Processes";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemImage:UIBarButtonSystemImageRefresh target:self action:@selector(fetchProcesses)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self fetchProcesses];
}

- (void)fetchProcesses {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSArray *fetched = [[JITEnableContext shared] fetchProcessListWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (error) {
                [self showError:error];
            } else {
                self.processes = fetched;
                [self.tableView reloadData];
            }
        });
    });
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.processes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProcessCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ProcessCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }

    NSDictionary *proc = self.processes[indexPath.row];
    cell.textLabel.text = [proc[@"path"] lastPathComponent];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"PID: %@ - %@", proc[@"pid"], proc[@"path"]];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *proc = self.processes[indexPath.row];
    int pid = [proc[@"pid"] intValue];
    NSString *name = [proc[@"path"] lastPathComponent];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name message:[NSString stringWithFormat:@"PID: %d", pid] preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Kill" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self killProcess:pid];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)killProcess:(int)pid {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        BOOL success = [[JITEnableContext shared] killProcessWithPID:pid error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (success) {
                [self fetchProcesses];
            } else {
                [self showError:error];
            }
        });
    });
}

@end
