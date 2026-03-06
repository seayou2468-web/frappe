#import "IdeviceViewController.h"
#import "IdeviceManager.h"
#import "ThemeEngine.h"
#import "FileBrowserViewController.h"
#import "LogViewerViewController.h"
#import "IdeviceAppListViewController.h"
#import "BottomMenuView.h"
#import "MainContainerViewController.h"
#import "TabManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IdeviceViewController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusIndicator;
@property (nonatomic, strong) UIImageView *deviceImageView;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iDevice Tools";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    UIBarButtonItem *backToFmBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
    self.navigationItem.leftBarButtonItem = backToFmBtn;

    [self setupUI];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged) name:@"IdeviceStatusChanged" object:nil];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.bottomMenu = [[BottomMenuView alloc] initWithMode:BottomMenuModeFiles];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.bottomMenu.onAction = ^(BottomMenuAction action) { [weakSelf handleMenuAction:action]; };
    [self.view addSubview:self.bottomMenu];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomMenu.heightAnchor constraintEqualToConstant:60 + [UIApplication sharedApplication].keyWindow.safeAreaInsets.bottom]
    ]];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 180)];
    self.statusIndicator = [[UIView alloc] initWithFrame:CGRectMake((header.frame.size.width - 100) / 2, 20, 100, 100)];
    self.statusIndicator.layer.cornerRadius = 50;
    self.statusIndicator.layer.borderWidth = 4.0;
    self.statusIndicator.layer.borderColor = [UIColor grayColor].CGColor;
    self.statusIndicator.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    [header addSubview:self.statusIndicator];

    self.deviceImageView = [[UIImageView alloc] initWithFrame:CGRectMake(25, 25, 50, 50)];
    self.deviceImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.deviceImageView.image = [UIImage systemImageNamed:@"iphone"];
    self.deviceImageView.tintColor = [UIColor whiteColor];
    [self.statusIndicator addSubview:self.deviceImageView];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 130, header.frame.size.width, 50)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [header addSubview:self.statusLabel];

    self.tableView.tableHeaderView = header;
    [self statusChanged];
}

- (void)statusChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        IdeviceManager *mgr = [IdeviceManager sharedManager];
        UIColor *statusColor = [UIColor grayColor];
        NSString *statusStr = @"Disconnected";
        switch (mgr.status) {
            case IdeviceStatusConnecting: statusStr = @"Connecting..."; statusColor = [UIColor orangeColor]; break;
            case IdeviceStatusConnected: statusStr = @"Connected"; statusColor = [UIColor greenColor]; break;
            case IdeviceStatusError: statusStr = [NSString stringWithFormat:@"Error: %@", mgr.lastError]; statusColor = [UIColor redColor]; break;
            default: break;
        }
        [UIView animateWithDuration:0.3 animations:^{
            self.statusIndicator.layer.borderColor = statusColor.CGColor;
            self.deviceImageView.tintColor = statusColor;
            self.statusIndicator.layer.shadowColor = statusColor.CGColor;
            self.statusIndicator.layer.shadowOffset = CGSizeZero;
            self.statusIndicator.layer.shadowRadius = (mgr.status == IdeviceStatusConnected) ? 10.0 : 0.0;
            self.statusIndicator.layer.shadowOpacity = (mgr.status == IdeviceStatusConnected) ? 0.8 : 0.0;
        }];
        self.statusLabel.text = [NSString stringWithFormat:@"%@\nIP: %@:%d", statusStr, mgr.ipAddress, mgr.port];
        [self.tableView reloadData];
    });
}

#pragma mark - Navigation

- (void)closeTapped {
    [TabManager sharedManager].activeTabIndex = 0;
    MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController;
    if ([container isKindOfClass:[MainContainerViewController class]]) [container displayActiveTab];
}

- (void)handleMenuAction:(BottomMenuAction)action {
    MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController;
    if ([container isKindOfClass:[MainContainerViewController class]]) [container handleMenuAction:action];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // Connection Settings
    if (section == 1) return 2; // Pairing
    if (section == 2) return 1; // Features (Apps)
    if (section == 3) return 1; // Actions
    if (section == 4) return 1; // System (Logs)
    return 0;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Connection Settings";
    if (section == 1) return @"Pairing";
    if (section == 2) return @"Features";
    if (section == 3) return @"Actions";
    if (section == 4) return @"System";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"Cell"];
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [ThemeEngine liquidColor];
    }
    IdeviceManager *mgr = [IdeviceManager sharedManager];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) { cell.textLabel.text = @"IP Address"; cell.detailTextLabel.text = mgr.ipAddress; }
        else { cell.textLabel.text = @"Port"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", mgr.port]; }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) { cell.textLabel.text = @"File Picker (iOS Files)"; cell.detailTextLabel.text = mgr.pairingFilePath ? [mgr.pairingFilePath lastPathComponent] : @"None"; }
        else { cell.textLabel.text = @"Internal File Browser"; cell.detailTextLabel.text = nil; }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"Installed Applications";
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [UIColor whiteColor] : [UIColor grayColor];
    } else if (indexPath.section == 3) {
        cell.textLabel.text = (mgr.status == IdeviceStatusConnected) ? @"Disconnect" : @"Connect";
        cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [UIColor redColor] : [ThemeEngine liquidColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (indexPath.section == 4) {
        cell.textLabel.text = @"View System Logs"; cell.textLabel.textColor = [UIColor whiteColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IdeviceManager *mgr = [IdeviceManager sharedManager];
    if (indexPath.section == 0) { if (indexPath.row == 0) [self editIP]; else [self editPort]; }
    else if (indexPath.section == 1) { if (indexPath.row == 0) [self openSystemFilePicker]; else [self openInternalFileBrowser]; }
    else if (indexPath.section == 2) { if (mgr.status == IdeviceStatusConnected) [self.navigationController pushViewController:[[IdeviceAppListViewController alloc] init] animated:YES]; }
    else if (indexPath.section == 3) { if (mgr.status == IdeviceStatusConnected) [mgr disconnect]; else [mgr connect]; }
    else if (indexPath.section == 4) [self.navigationController pushViewController:[[LogViewerViewController alloc] init] animated:YES];
}

- (void)editIP {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit IP" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [IdeviceManager sharedManager].ipAddress; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [IdeviceManager sharedManager].ipAddress = alert.textFields.firstObject.text; [self statusChanged]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)editPort {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Port" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [NSString stringWithFormat:@"%d", [IdeviceManager sharedManager].port]; tf.keyboardType = UIKeyboardTypeNumberPad; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [IdeviceManager sharedManager].port = (uint16_t)[alert.textFields.firstObject.text integerValue]; [self statusChanged]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openSystemFilePicker {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (url) { [[IdeviceManager sharedManager] selectPairingFile:url.path]; [self statusChanged]; }
}
- (void)openInternalFileBrowser {
    FileBrowserViewController *fb = [[FileBrowserViewController alloc] initWithPath:@"/"]; fb.isPickingFile = YES;
    __weak typeof(self) weakSelf = self;
    fb.onFilePicked = ^(NSString *path) { [[IdeviceManager sharedManager] selectPairingFile:path]; [weakSelf.navigationController popViewControllerAnimated:YES]; [weakSelf statusChanged]; };
    [self.navigationController pushViewController:fb animated:YES];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
