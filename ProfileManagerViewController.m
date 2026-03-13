#import "ProfileManagerViewController.h"
#import "AppManager.h"
#import "ThemeEngine.h"

@interface ProfileManagerViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<ProfileInfo *> *profiles;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@end

@implementation ProfileManagerViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider {
    self = [super init];
    if (self) { _provider = provider; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Configuration Profiles";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self refreshProfiles];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.loadingIndicator.color = [UIColor whiteColor];
    self.loadingIndicator.center = self.view.center;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshProfiles)];
    self.navigationItem.rightBarButtonItem = refreshBtn;
}

- (void)refreshProfiles {
    [self.loadingIndicator startAnimating];
    [[AppManager sharedManager] fetchProfilesWithProvider:self.provider completion:^(NSArray<ProfileInfo *> *profiles, NSString *error) {
        [self.loadingIndicator stopAnimating];
        if (error) {
            [self showErrorMessage:error];
        } else {
            self.profiles = profiles;
            [self.tableView reloadData];
        }
    }];
}

- (void)showErrorMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.profiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"ProfileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [ThemeEngine applyGlassStyleToView:cell.contentView cornerRadius:15];
    }

    ProfileInfo *profile = self.profiles[indexPath.row];
    cell.textLabel.text = profile.displayName ?: @"(No Name)";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", profile.identifier, profile.organization ?: @""];
    cell.detailTextLabel.numberOfLines = 0;

    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 80;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        ProfileInfo *profile = self.profiles[indexPath.row];
        [self deleteProfile:profile];
    }
}

- (void)deleteProfile:(ProfileInfo *)profile {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Remove Profile" message:[NSString stringWithFormat:@"Are you sure you want to remove '%@'?", profile.displayName] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *  action) {
        [self.loadingIndicator startAnimating];
        [[AppManager sharedManager] removeProfileWithIdentifier:profile.identifier provider:self.provider completion:^(BOOL success, NSString *message) {
            [self.loadingIndicator stopAnimating];
            if (success) {
                [self refreshProfiles];
            } else {
                [self showErrorMessage:message];
            }
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

@end
