#import "AppListViewController.h"
#import "JITEnableContext.h"
#import "ThemeEngine.h"

@interface AppListViewController ()
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSDictionary<NSString *, NSString *> *apps;
@property (strong, nonatomic) NSArray<NSString *> *bundleIDs;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation AppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Apps";
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

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.bundleIDs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AppCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    }

    NSString *bundleID = self.bundleIDs[indexPath.row];
    cell.textLabel.text = self.apps[bundleID];
    cell.detailTextLabel.text = bundleID;
    cell.imageView.image = [UIImage systemImageNamed:@"app.dashed"]; // Placeholder

    // Async icon load
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSError *err = nil;
        UIImage *icon = [[JITEnableContext shared] getAppIconWithBundleId:bundleID error:&err];
        if (icon) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UITableViewCell *updateCell = [tableView cellForRowAtIndexPath:indexPath];
                if (updateCell) {
                    updateCell.imageView.image = icon;
                    [updateCell setNeedsLayout];
                }
            });
        }
    });

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *bundleID = self.bundleIDs[indexPath.row];
    NSString *appName = self.apps[bundleID];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:appName message:bundleID preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Enable JIT" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self enableJITForBundleID:bundleID];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Launch Without Debug" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
            NSString *msg = success ? @"JIT enabled successfully!" : @"Failed to enable JIT.";
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"JIT" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:done animated:YES completion:nil];
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
            NSString *msg = success ? @"App launched successfully!" : @"Failed to launch app.";
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Launch" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:done animated:YES completion:nil];
        });
    });
}

@end
