#import "AppListViewController.h"
#import "extend/JITEnableContext.h"
#import "ThemeEngine.h"

@interface AppListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSDictionary<NSString *, NSString *> *apps;
@property (strong, nonatomic) NSArray<NSString *> *bundleIDs;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation AppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Apps & JIT";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemImage:UIBarButtonSystemImageRefresh target:self action:@selector(fetchApps)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self fetchApps];
}

- (void)fetchApps {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSDictionary *fetchedApps = [[JITEnableContext shared] getAllAppsWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (error) {
                [self showError:error];
            } else {
                self.apps = fetchedApps;
                self.bundleIDs = [[fetchedApps allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.bundleIDs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"AppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *bg = [[UIView alloc] init];
        [ThemeEngine applyLiquidGlassStyleToView:bg cornerRadius:14];
        bg.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView insertSubview:bg atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [bg.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
            [bg.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
            [bg.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [bg.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        ]];
    }

    NSString *bundleID = self.bundleIDs[indexPath.row];
    cell.textLabel.text = self.apps[bundleID];
    cell.detailTextLabel.text = bundleID;
    cell.imageView.image = [UIImage systemImageNamed:@"app.dashed"];
    cell.imageView.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *err = nil;
        UIImage *icon = [[JITEnableContext shared] getAppIconWithBundleId:bundleID error:&err];
        if (icon) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UITableViewCell *updateCell = [tableView cellForRowAtIndexPath:indexPath];
                if (updateCell) {
                    updateCell.imageView.image = icon;
                    updateCell.imageView.layer.cornerRadius = 10;
                    updateCell.imageView.clipsToBounds = YES;
                    [updateCell setNeedsLayout];
                }
            });
        }
    });

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *bundleID = self.bundleIDs[indexPath.row];
    NSString *appName = self.apps[bundleID];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:appName message:bundleID preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Enable JIT & Launch" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self enableJITForBundleID:bundleID];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Launch Only" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launchAppForBundleID:bundleID];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)enableJITForBundleID:(NSString *)bundleID {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [[JITEnableContext shared] debugAppWithBundleID:bundleID logger:^(NSString *message) {
            NSLog(@"[JIT] %@", message);
        } jsCallback:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (!success) [self showError:[NSError errorWithDomain:@"JIT" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Failed to enable JIT"}]];
        });
    });
}

- (void)launchAppForBundleID:(NSString *)bundleID {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = [[JITEnableContext shared] launchAppWithoutDebug:bundleID logger:^(NSString *message) {
            NSLog(@"[Launch] %@", message);
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if (!success) [self showError:[NSError errorWithDomain:@"Launch" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Failed to launch app"}]];
        });
    });
}
@end

cat << 'EOF' > ProcessListViewController.m
#import "ProcessListViewController.h"
#import "extend/JITEnableContext.h"
#import "ThemeEngine.h"

@interface ProcessListViewController () <UITableViewDelegate, UITableViewDataSource>
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
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
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

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.processes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"ProcessCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *bg = [[UIView alloc] init];
        [ThemeEngine applyLiquidGlassStyleToView:bg cornerRadius:14];
        bg.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView insertSubview:bg atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [bg.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6],
            [bg.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6],
            [bg.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [bg.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        ]];
    }

    NSDictionary *proc = self.processes[indexPath.row];
    cell.textLabel.text = [proc[@"path"] lastPathComponent];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"PID: %@ - %@", proc[@"pid"], proc[@"path"]];
    cell.imageView.image = [UIImage systemImageNamed:@"cpu"];
    cell.imageView.tintColor = [UIColor systemGreenColor];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *proc = self.processes[indexPath.row];
    int pid = [proc[@"pid"] intValue];
    NSString *name = [proc[@"path"] lastPathComponent];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name message:[NSString stringWithFormat:@"PID: %d", pid] preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Kill" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
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
            if (success) [self fetchProcesses];
            else [self showError:error];
        });
    });
}
@end

cat << 'EOF' > SyslogViewController.m
#import "SyslogViewController.h"
#import "extend/JITEnableContext.h"
#import "ThemeEngine.h"

@interface SyslogViewController ()
@property (strong, nonatomic) UITextView *textView;
@property (strong, nonatomic) NSMutableString *logBuffer;
@end

@implementation SyslogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"System Log";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.logBuffer = [NSMutableString string];

    UIView *container = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, 10, 80)];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [ThemeEngine applyLiquidGlassStyleToView:container cornerRadius:20];
    [self.view addSubview:container];

    self.textView = [[UITextView alloc] initWithFrame:CGRectInset(container.bounds, 10, 10)];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = [UIColor greenColor];
    self.textView.font = [UIFont fontWithName:@"Courier" size:11];
    self.textView.editable = NO;
    [container addSubview:self.textView];

    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearLog)];
    self.navigationItem.rightBarButtonItem = clearBtn;

    [self startLog];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[JITEnableContext shared] stopSyslogRelay];
}

- (void)startLog {
    [[JITEnableContext shared] startSyslogRelayWithHandler:^(NSString *line) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.logBuffer appendFormat:@"%@\n", line];
            if (self.logBuffer.length > 50000) [self.logBuffer deleteCharactersInRange:NSMakeRange(0, 5000)];
            self.textView.text = self.logBuffer;
            [self.textView scrollRangeToVisible:NSMakeRange(self.logBuffer.length - 1, 1)];
        });
    } onError:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Syslog Error: %@", error);
        });
    }];
}

- (void)clearLog {
    [self.logBuffer setString:@""];
    self.textView.text = @"";
}
@end
