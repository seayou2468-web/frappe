#import "DeviceInfoViewController.h"
#import "extend/JITEnableContext.h"
#import "ThemeEngine.h"

@interface DeviceInfoViewController () <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<NSDictionary *> *entries;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@end

@implementation DeviceInfoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Device Info";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.center = self.view.center;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemImage:UIBarButtonSystemImageRefresh target:self action:@selector(loadInfo)];
    UIBarButtonItem *ddiBtn = [[UIBarButtonItem alloc] initWithTitle:@"Mount DDI" style:UIBarButtonItemStylePlain target:self action:@selector(mountDDI)];
    self.navigationItem.rightBarButtonItems = @[refreshBtn, ddiBtn];

    [self loadInfo];
}

- (void)loadInfo {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        LockdowndClientHandle *client = [[JITEnableContext shared] ideviceInfoInit:&error];
        if (client) {
            char *xml = [[JITEnableContext shared] ideviceInfoGetXMLWithLockdownClient:client error:&error];
            if (xml) {
                NSData *data = [NSData dataWithBytes:xml length:strlen(xml)];
                free(xml);
                NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
                if (dict) {
                    NSMutableArray *newEntries = [NSMutableArray array];
                    for (NSString *key in [[dict allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
                        [newEntries addObject:@{@"key": key, @"value": [NSString stringWithFormat:@"%@", dict[key]]}];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.entries = newEntries;
                        [self.tableView reloadData];
                        [self.spinner stopAnimating];
                    });
                }
            }
            lockdownd_client_free(client);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showError:error];
                [self.spinner stopAnimating];
            });
        }
    });
}

- (void)mountDDI {
    [self performMount];
}

- (void)performMount {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURL *doc = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSString *image = [doc URLByAppendingPathComponent:@"DeveloperDiskImage.dmg"].path;
        NSString *tc = [doc URLByAppendingPathComponent:@"DeveloperDiskImage.dmg.trustcache"].path;
        NSString *manifest = [doc URLByAppendingPathComponent:@"BuildManifest.plist"].path;
        NSError *error = nil;
        NSInteger res = [[JITEnableContext shared] mountPersonalDDIWithImagePath:image trustcachePath:tc manifestPath:manifest error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            NSString *msg = (res == 0) ? @"DDI Mounted!" : [NSString stringWithFormat:@"Failed: %ld", (long)res];
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"DDI Mount" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:done animated:YES completion:nil];
        });
    });
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.entries.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"InfoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *bg = [[UIView alloc] init];
        [ThemeEngine applyLiquidGlassStyleToView:bg cornerRadius:10];
        bg.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView insertSubview:bg atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [bg.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
            [bg.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
            [bg.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [bg.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        ]];
    }
    NSDictionary *entry = self.entries[indexPath.row];
    cell.textLabel.text = entry[@"key"];
    cell.detailTextLabel.text = entry[@"value"];
    return cell;
}
@end
