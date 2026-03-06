#import "IdeviceViewController.h"
#import "IdeviceManager.h"
#import "ThemeEngine.h"
#import "FileBrowserViewController.h"

@interface IdeviceViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iDevice Tools";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

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

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    self.statusLabel = [[UILabel alloc] initWithFrame:header.bounds];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = [ThemeEngine liquidColor];
    [header addSubview:self.statusLabel];
    self.tableView.tableHeaderView = header;

    [self statusChanged];
}

- (void)statusChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        IdeviceManager *mgr = [IdeviceManager sharedManager];
        NSString *statusStr = @"Disconnected";
        switch (mgr.status) {
            case IdeviceStatusConnecting: statusStr = @"Connecting..."; break;
            case IdeviceStatusConnected: statusStr = @"Connected"; break;
            case IdeviceStatusError: statusStr = [NSString stringWithFormat:@"Error: %@", mgr.lastError]; break;
            default: break;
        }

        NSMutableString *fullStatus = [NSMutableString stringWithFormat:@"Status: %@\n", statusStr];
        [fullStatus appendFormat:@"IP: %@:%d\n", mgr.ipAddress, mgr.port];
        if (mgr.status == IdeviceStatusConnected) {
            [fullStatus appendFormat:@"Heartbeat: %@\n", mgr.heartbeatActive ? @"Active" : @"Inactive"];
            [fullStatus appendFormat:@"DDI: %@", mgr.ddiMounted ? @"Mounted" : @"Not Mounted"];
        }

        self.statusLabel.text = fullStatus;
        [self.tableView reloadData];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // Connection
    if (section == 1) return 1; // Pairing File
    if (section == 2) return 1; // Actions
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Connection Settings";
    if (section == 1) return @"Pairing";
    if (section == 2) return @"Actions";
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
        if (indexPath.row == 0) {
            cell.textLabel.text = @"IP Address";
            cell.detailTextLabel.text = mgr.ipAddress;
        } else {
            cell.textLabel.text = @"Port";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", mgr.port];
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"Pairing File";
        cell.detailTextLabel.text = mgr.pairingFilePath ? [mgr.pairingFilePath lastPathComponent] : @"None";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = (mgr.status == IdeviceStatusConnected) ? @"Disconnect" : @"Connect";
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IdeviceManager *mgr = [IdeviceManager sharedManager];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            [self editIP];
        } else {
            [self editPort];
        }
    } else if (indexPath.section == 1) {
        [self selectPairingFile];
    } else if (indexPath.section == 2) {
        if (mgr.status == IdeviceStatusConnected) {
            [mgr disconnect];
        } else {
            [mgr connect];
        }
    }
}

- (void)editIP {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit IP" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [IdeviceManager sharedManager].ipAddress;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [IdeviceManager sharedManager].ipAddress = alert.textFields.firstObject.text;
        [self statusChanged];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)editPort {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Port" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [NSString stringWithFormat:@"%d", [IdeviceManager sharedManager].port];
        textField.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [IdeviceManager sharedManager].port = (uint16_t)[alert.textFields.firstObject.text integerValue];
        [self statusChanged];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectPairingFile {
    FileBrowserViewController *fb = [[FileBrowserViewController alloc] initWithPath:@"/"];
    // In a real app, we'd need a way to pick a file from FileBrowserViewController
    // and return it. For now, let's assume we can navigate and select.
    // This is a placeholder for the integration.
    [self.navigationController pushViewController:fb animated:YES];
}

@end
