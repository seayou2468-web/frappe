#import "IdeviceViewController.h"
#import "ThemeEngine.h"
#import "idevice.h"
#import "FileManagerCore.h"
#import "HeartbeatManager.h"
#import "DdiManager.h"
#import "AppListViewController.h"
#import <arpa/inet.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IdeviceViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) UITextView *consoleView;
@property (nonatomic, strong) UITextField *ipTextField;
@property (nonatomic, strong) UITextField *portTextField;
@property (nonatomic, strong) UILabel *pairingFileLabel;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *retryButton;

@property (nonatomic, strong) UILabel *lockdownStatus;
@property (nonatomic, strong) UILabel *heartbeatStatus;
@property (nonatomic, strong) UILabel *ddiStatus;

@property (nonatomic, strong) UIView *infoContainer;
@property (nonatomic, strong) UIStackView *infoStack;

@property (nonatomic, strong) NSString *selectedPairingFilePath;
@property (nonatomic, assign) struct IdevicePairingFile *currentPairingFile;
@property (nonatomic, assign) struct IdeviceProviderHandle *currentProvider;
@property (nonatomic, assign) struct LockdowndClientHandle *currentLockdown;

@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"TERMINAL@IDEVICE";
    [self setupUI];
    [self loadSettings];
    [self logToConsole:@"SYSTEM_BOOT: Initializing idevice subsystem..."];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveSettings];
}

- (void)dealloc {
    [self cleanupHandles];
}

- (void)cleanupHandles {
    if (self.currentLockdown) { lockdownd_client_free(self.currentLockdown); self.currentLockdown = NULL; }
    if (self.currentProvider) { idevice_provider_free(self.currentProvider); self.currentProvider = NULL; }
    if (self.currentPairingFile) { idevice_pairing_file_free(self.currentPairingFile); self.currentPairingFile = NULL; }
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    self.mainStack = [[UIStackView alloc] init];
    self.mainStack.axis = UILayoutConstraintAxisVertical;
    self.mainStack.spacing = 15;
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.mainStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20],
        [self.mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.mainStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20]
    ]];

    UILabel *header = [[UILabel alloc] init];
    header.text = @"[ IDEVICE INTEGRATED TERMINAL ]";
    header.textColor = [UIColor systemGreenColor];
    header.font = [UIFont fontWithName:@"Courier-Bold" size:16];
    header.textAlignment = NSTextAlignmentCenter;
    [self.mainStack addArrangedSubview:header];

    self.consoleView = [[UITextView alloc] init];
    self.consoleView.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.05];
    self.consoleView.layer.borderColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.3].CGColor;
    self.consoleView.layer.borderWidth = 1;
    self.consoleView.textColor = [UIColor systemGreenColor];
    self.consoleView.font = [UIFont fontWithName:@"Courier" size:12];
    self.consoleView.editable = NO;
    [self.consoleView.heightAnchor constraintEqualToConstant:150].active = YES;
    [self.mainStack addArrangedSubview:self.consoleView];

    UIView *configView = [[UIView alloc] init];
    configView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    configView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    configView.layer.borderWidth = 1;
    [configView.heightAnchor constraintEqualToConstant:100].active = YES;
    [self.mainStack addArrangedSubview:configView];

    UILabel *ipLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 100, 30)];
    ipLabel.text = @"HOST_ADDR:"; ipLabel.textColor = [UIColor lightGrayColor]; ipLabel.font = [UIFont fontWithName:@"Courier-Bold" size:12];
    [configView addSubview:ipLabel];

    self.ipTextField = [[UITextField alloc] initWithFrame:CGRectMake(110, 10, 150, 30)];
    self.ipTextField.textColor = [UIColor whiteColor]; self.ipTextField.font = [UIFont fontWithName:@"Courier" size:14];
    self.ipTextField.backgroundColor = [UIColor clearColor];
    [configView addSubview:self.ipTextField];

    UILabel *portLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 50, 100, 30)];
    portLabel.text = @"HOST_PORT:"; portLabel.textColor = [UIColor lightGrayColor]; portLabel.font = [UIFont fontWithName:@"Courier-Bold" size:12];
    [configView addSubview:portLabel];

    self.portTextField = [[UITextField alloc] initWithFrame:CGRectMake(110, 50, 80, 30)];
    self.portTextField.textColor = [UIColor whiteColor]; self.portTextField.font = [UIFont fontWithName:@"Courier" size:14];
    self.portTextField.backgroundColor = [UIColor clearColor]; self.portTextField.keyboardType = UIKeyboardTypeNumberPad;
    [configView addSubview:self.portTextField];

    self.pairingFileLabel = [[UILabel alloc] init];
    self.pairingFileLabel.textColor = [UIColor yellowColor]; self.pairingFileLabel.font = [UIFont fontWithName:@"Courier" size:12];
    self.pairingFileLabel.text = @"STATUS: PAIR_FILE_MISSING";
    [self.mainStack addArrangedSubview:self.pairingFileLabel];

    [self.mainStack addArrangedSubview:[self createTerminalButtonWithTitle:@"EXEC SELECT_PAIR_FILE" action:@selector(selectPairingFile)]];

    UIStackView *statusStack = [[UIStackView alloc] init];
    statusStack.axis = UILayoutConstraintAxisHorizontal;
    statusStack.distribution = UIStackViewDistributionFillEqually;
    statusStack.spacing = 10;
    [self.mainStack addArrangedSubview:statusStack];

    self.lockdownStatus = [self createStatusLabelWithTitle:@"LOCKDOWN"]; [statusStack addArrangedSubview:self.lockdownStatus];
    self.heartbeatStatus = [self createStatusLabelWithTitle:@"HEARTBEAT"]; [statusStack addArrangedSubview:self.heartbeatStatus];
    self.ddiStatus = [self createStatusLabelWithTitle:@"DDI_IMAGE"]; [statusStack addArrangedSubview:self.ddiStatus];

    self.infoContainer = [[UIView alloc] init];
    self.infoContainer.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.05];
    self.infoContainer.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.3].CGColor;
    self.infoContainer.layer.borderWidth = 1;
    self.infoContainer.hidden = YES;
    [self.mainStack addArrangedSubview:self.infoContainer];

    self.infoStack = [[UIStackView alloc] init];
    self.infoStack.axis = UILayoutConstraintAxisVertical;
    self.infoStack.spacing = 5;
    self.infoStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.infoContainer addSubview:self.infoStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.infoStack.topAnchor constraintEqualToAnchor:self.infoContainer.topAnchor constant:10],
        [self.infoStack.leadingAnchor constraintEqualToAnchor:self.infoContainer.leadingAnchor constant:10],
        [self.infoStack.trailingAnchor constraintEqualToAnchor:self.infoContainer.trailingAnchor constant:-10],
        [self.infoStack.bottomAnchor constraintEqualToAnchor:self.infoContainer.bottomAnchor constant:-10]
    ]];

    self.connectButton = [self createTerminalButtonWithTitle:@"INITIATE_CONNECTION" action:@selector(connectTapped)];
    [self.mainStack addArrangedSubview:self.connectButton];

    self.retryButton = [self createTerminalButtonWithTitle:@"RETRY_HANDSHAKE" action:@selector(connectTapped)];
    self.retryButton.hidden = YES;
    [self.mainStack addArrangedSubview:self.retryButton];

    [self.mainStack addArrangedSubview:[self createTerminalButtonWithTitle:@"BROWSE_APPLICATIONS" action:@selector(showAppList)]];
}

- (UILabel *)createStatusLabelWithTitle:(NSString *)title {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = [NSString stringWithFormat:@"%@: [---]", title];
    lbl.textColor = [UIColor grayColor];
    lbl.font = [UIFont fontWithName:@"Courier-Bold" size:10];
    lbl.textAlignment = NSTextAlignmentCenter;
    return lbl;
}

- (UIButton *)createTerminalButtonWithTitle:(NSString *)title action:(SEL)selector {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:[NSString stringWithFormat:@"> %@", title] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont fontWithName:@"Courier-Bold" size:14];
    btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    btn.layer.borderWidth = 1; btn.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
    [btn.heightAnchor constraintEqualToConstant:44].active = YES;
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)logToConsole:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.consoleView.text = [self.consoleView.text stringByAppendingFormat:@"\n[%@] %@", [[NSDate date] descriptionWithLocale:nil], message];
        [self.consoleView scrollRangeToVisible:NSMakeRange(self.consoleView.text.length - 1, 1)];
    });
}

- (void)updateStatus:(UILabel *)label title:(NSString *)title status:(NSString *)status color:(UIColor *)color {
    dispatch_async(dispatch_get_main_queue(), ^{
        label.text = [NSString stringWithFormat:@"%@: [%@]", title, status];
        label.textColor = color;
    });
}

- (void)loadSettings {
    self.ipTextField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
    self.portTextField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdevicePort"] ?: @"62078";
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairingPath = [docsDir stringByAppendingPathComponent:@"PairingFiles/pairfile.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pairingPath]) {
        self.selectedPairingFilePath = pairingPath;
        self.pairingFileLabel.text = @"STATUS: PAIR_FILE_LOADED";
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
    }
}

- (void)saveSettings {
    [[NSUserDefaults standardUserDefaults] setObject:self.ipTextField.text forKey:@"IdeviceIP"];
    [[NSUserDefaults standardUserDefaults] setObject:self.portTextField.text forKey:@"IdevicePort"];
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    [self logToConsole:@"FS_EVENT: Importing pairing file..."];
    BOOL access = [url startAccessingSecurityScopedResource];
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairingDir = [docsDir stringByAppendingPathComponent:@"PairingFiles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pairingDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *targetFilename = @"pairfile.plist";
    [[NSFileManager defaultManager] removeItemAtPath:[pairingDir stringByAppendingPathComponent:targetFilename] error:nil];
    NSError *error = nil;
    NSString *filename = [[FileManagerCore sharedManager] moveItemAtURL:url toDirectory:pairingDir uniqueName:targetFilename error:&error];
    if (access) [url stopAccessingSecurityScopedResource];
    if (filename) {
        self.selectedPairingFilePath = [pairingDir stringByAppendingPathComponent:filename];
        self.pairingFileLabel.text = @"STATUS: PAIR_FILE_UPDATED";
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
        [self logToConsole:@"FS_EVENT: pairfile.plist successfully registered."];
    }
}

- (void)connectTapped {
    if (!self.selectedPairingFilePath) {
        [self logToConsole:@"ERR: Cannot initiate link without PAIR_FILE."];
        return;
    }
    self.connectButton.hidden = YES; self.retryButton.hidden = YES; self.infoContainer.hidden = YES;
    [self cleanupHandles];
    [self logToConsole:@"NET_INIT: Connecting to remote target..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{ [self performConnection]; });
}

- (void)performConnection {
    const char *ipStr = [self.ipTextField.text UTF8String];
    int port = [self.portTextField.text intValue];
    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET; addr.sin_port = htons(port);
    inet_pton(AF_INET, ipStr, &addr.sin_addr);

    [self logToConsole:@"FFI_CALL: idevice_pairing_file_read..."];
    struct IdevicePairingFile *pairing_file = NULL;
    struct IdeviceFfiError *err = idevice_pairing_file_read([self.selectedPairingFilePath UTF8String], &pairing_file);
    if (err) { [self handleError:err phase:@"PAIRING"]; return; }
    self.currentPairingFile = pairing_file;

    [self logToConsole:@"FFI_CALL: idevice_tcp_provider_new..."];
    struct IdeviceProviderHandle *provider = NULL;
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pairing_file, "TERMINAL", &provider);
    if (err) { [self handleError:err phase:@"PROVIDER"]; return; }
    self.currentProvider = provider;
    self.currentPairingFile = NULL;

    [self logToConsole:@"FFI_CALL: lockdownd_connect..."];
    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) { [self handleError:err phase:@"LOCKDOWN"]; return; }
    self.currentLockdown = lockdown;

    [self logToConsole:@"LINK_ESTABLISHED: Session verified."];
    [self updateStatus:self.lockdownStatus title:@"LOCKDOWN" status:@"ACTIVE" color:[UIColor systemGreenColor]];
    [self fetchDeviceInfo:lockdown];

    [self logToConsole:@"HB_INIT: Starting heartbeat relay..."];
    [[HeartbeatManager sharedManager] startHeartbeatWithProvider:provider];
    [self updateStatus:self.heartbeatStatus title:@"HEARTBEAT" status:@"ACTIVE" color:[UIColor systemGreenColor]];

    [self logToConsole:@"DDI_SCAN: Checking developer disk image..."];
    [[DdiManager sharedManager] checkAndMountDdiWithProvider:provider lockdown:lockdown completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self logToConsole:[NSString stringWithFormat:@"DDI_SUCCESS: %@", message]];
                [self updateStatus:self.ddiStatus title:@"DDI_IMAGE" status:@"MOUNTED" color:[UIColor systemGreenColor]];
            } else {
                [self logToConsole:[NSString stringWithFormat:@"DDI_WARN: %@", message]];
                [self updateStatus:self.ddiStatus title:@"DDI_IMAGE" status:@"FAILED" color:[UIColor systemRedColor]];
            }
        });
    }];

    dispatch_async(dispatch_get_main_queue(), ^{ self.connectButton.hidden = NO; });
}

- (void)handleError:(struct IdeviceFfiError *)err phase:(NSString *)phase {
    NSString *msg = [NSString stringWithUTF8String:err->message];
    [self logToConsole:[NSString stringWithFormat:@"FFI_ERR: [%@] %@", phase, msg]];
    idevice_error_free(err);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateStatus:self.lockdownStatus title:@"LOCKDOWN" status:@"ERR" color:[UIColor systemRedColor]];
        self.retryButton.hidden = NO; self.connectButton.hidden = YES;
    });
}

- (void)fetchDeviceInfo:(struct LockdowndClientHandle *)lockdown {
    NSArray *keys = @[@"DeviceName", @"ProductType", @"ProductVersion", @"UniqueDeviceID", @"SerialNumber"];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *v in self.infoStack.arrangedSubviews) [v removeFromSuperview];
        self.infoContainer.hidden = NO;
    });

    for (NSString *key in keys) {
        plist_t val_plist = NULL;
        lockdownd_get_value(lockdown, [key UTF8String], NULL, &val_plist);
        if (val_plist) {
            char *val = NULL; plist_get_string_val(val_plist, &val);
            if (val) {
                NSString *nsVal = [NSString stringWithUTF8String:val];
                dispatch_async(dispatch_get_main_queue(), ^{ [self addInfoRow:key value:nsVal]; });
                plist_mem_free(val);
            }
            plist_free(val_plist);
        }
    }
}

- (void)addInfoRow:(NSString *)key value:(NSString *)value {
    UILabel *row = [[UILabel alloc] init];
    row.textColor = [UIColor whiteColor]; row.font = [UIFont fontWithName:@"Courier" size:11];
    row.text = [NSString stringWithFormat:@"%-15s: %s", [key UTF8String], [value UTF8String]];
    [self.infoStack addArrangedSubview:row];
}

- (void)showAppList {
    if (!self.currentProvider) { [self logToConsole:@"ERR: No active link to target."]; return; }
    AppListViewController *vc = [[AppListViewController alloc] initWithProvider:self.currentProvider];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
