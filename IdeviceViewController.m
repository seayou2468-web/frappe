#import "IdeviceViewController.h"
#import "ThemeEngine.h"
#import "idevice.h"
#import "FileManagerCore.h"
#import "HeartbeatManager.h"
#import "DdiManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface IdeviceViewController () <UIDocumentPickerDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Lockdown Status
@property (nonatomic, strong) UIView *lockdownContainer;
@property (nonatomic, strong) UIView *lockdownIndicator;
@property (nonatomic, strong) UILabel *lockdownLabel;
@property (nonatomic, strong) UILabel *lockdownDetail;

// Heartbeat Status
@property (nonatomic, strong) UIView *heartbeatContainer;
@property (nonatomic, strong) UIView *heartbeatIndicator;
@property (nonatomic, strong) UILabel *heartbeatLabel;

// DDI Status
@property (nonatomic, strong) UIView *ddiContainer;
@property (nonatomic, strong) UIView *ddiIndicator;
@property (nonatomic, strong) UILabel *ddiLabel;

@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *selectPairingFileButton;
@property (nonatomic, strong) NSString *selectedPairingFilePath;
@property (nonatomic, strong) UILabel *pairingFileLabel;

@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = @"iDevice Manager";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
    [self setupUI];
    idevice_init_logger(Debug, Debug, NULL);
}

- (void)closeTapped {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[HeartbeatManager sharedManager] stopHeartbeat];
        [self dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 1000)];
    [self.scrollView addSubview:self.contentView];

    CGFloat y = 20;
    CGFloat width = self.view.bounds.size.width - 40;

    UIView *li, *hi, *di;
    UILabel *ll, *hl, *dl, *ldt;

    self.lockdownContainer = [self createStatusContainerAtY:y title:@"Lockdown Connection" indicator:&li label:&ll detail:&ldt];
    self.lockdownIndicator = li; self.lockdownLabel = ll; self.lockdownDetail = ldt;
    [self.contentView addSubview:self.lockdownContainer];
    y += 160;

    self.heartbeatContainer = [self createStatusContainerAtY:y title:@"Heartbeat Status" indicator:&hi label:&hl detail:NULL];
    self.heartbeatIndicator = hi; self.heartbeatLabel = hl;
    [self.contentView addSubview:self.heartbeatContainer];
    y += 130;

    self.ddiContainer = [self createStatusContainerAtY:y title:@"DDI Image Status" indicator:&di label:&dl detail:NULL];
    self.ddiIndicator = di; self.ddiLabel = dl;
    [self.contentView addSubview:self.ddiContainer];
    y += 140;

    self.pairingFileLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, width, 40)];
    self.pairingFileLabel.textColor = [UIColor lightGrayColor];
    self.pairingFileLabel.font = [UIFont systemFontOfSize:14];
    self.pairingFileLabel.numberOfLines = 2;
    self.pairingFileLabel.textAlignment = NSTextAlignmentCenter;
    self.pairingFileLabel.text = @"No pairing file selected";
    [self.contentView addSubview:self.pairingFileLabel];
    y += 50;

    self.selectPairingFileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.selectPairingFileButton.frame = CGRectMake(40, y, width - 40, 50);
    [self.selectPairingFileButton setTitle:@"Select Pairing File" forState:UIControlStateNormal];
    [ThemeEngine applyLiquidStyleToView:self.selectPairingFileButton cornerRadius:15];
    [self.selectPairingFileButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.selectPairingFileButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.selectPairingFileButton];
    y += 70;

    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.connectButton.frame = CGRectMake(40, y, width - 40, 50);
    [self.connectButton setTitle:@"Start Global Connection" forState:UIControlStateNormal];
    [ThemeEngine applyLiquidStyleToView:self.connectButton cornerRadius:15];
    [self.connectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.connectButton addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.connectButton];

    self.contentView.frame = CGRectMake(0, 0, self.view.bounds.size.width, y + 100);
}

- (UIView *)createStatusContainerAtY:(CGFloat)y title:(NSString *)title indicator:(UIView **)indicator label:(UILabel **)label detail:(UILabel **)detail {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(20, y, self.view.bounds.size.width - 40, detail ? 140 : 110)];
    [ThemeEngine applyGlassStyleToView:container cornerRadius:20];
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, container.bounds.size.width - 30, 20)];
    header.text = title; header.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6]; header.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [container addSubview:header];
    UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(15, 40, 40, 40)];
    ind.layer.cornerRadius = 20; ind.backgroundColor = [UIColor systemGrayColor];
    [container addSubview:ind]; if (indicator) *indicator = ind;
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(70, 40, container.bounds.size.width - 85, 40)];
    lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont boldSystemFontOfSize:16]; lbl.text = @"Inactive";
    [container addSubview:lbl]; if (label) *label = lbl;
    if (detail) {
        UILabel *dtl = [[UILabel alloc] initWithFrame:CGRectMake(15, 90, container.bounds.size.width - 30, 40)];
        dtl.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5]; dtl.font = [UIFont systemFontOfSize:13]; dtl.numberOfLines = 2;
        [container addSubview:dtl]; if (detail) *detail = dtl;
    }
    return container;
}

- (void)updateIndicator:(UIView *)indicator label:(UILabel *)label status:(NSString *)status color:(UIColor *)color animating:(BOOL)animating {
    dispatch_async(dispatch_get_main_queue(), ^{
        label.text = status; indicator.backgroundColor = color;
        [indicator.layer removeAllAnimations];
        if (animating) {
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
            pulse.duration = 1.0; pulse.fromValue = @(1.0); pulse.toValue = @(0.3);
            pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
            [indicator.layer addAnimation:pulse forKey:@"pulse"];
            indicator.layer.shadowColor = color.CGColor; indicator.layer.shadowOffset = CGSizeZero; indicator.layer.shadowOpacity = 1.0; indicator.layer.shadowRadius = 10;
        } else { indicator.layer.shadowOpacity = 0; }
    });
}

- (void)selectPairingFile {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
        picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
    });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
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
        self.pairingFileLabel.text = [NSString stringWithFormat:@"Selected: %@", filename];
    } else if (error) { [self showAlertWithTitle:@"Import Error" message:error.localizedDescription]; }
}

- (void)connectTapped {
    if (!self.selectedPairingFilePath) { [self showAlertWithTitle:@"Error" message:@"Please select a pairing file first."]; return; }
    self.connectButton.enabled = NO;
    // CONNECTION MUST RUN IN BACKGROUND TO AVOID FREEZING AND HANDLE RACE CONDITIONS
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self performConnection];
    });
}

- (void)performConnection {
    const char *ip = "10.7.0.1"; int port = 62078;
    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET; addr.sin_port = htons(port);
    if (inet_pton(AF_INET, ip, &addr.sin_addr) <= 0) {
        [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Invalid IP" color:[UIColor systemRedColor] animating:NO];
        [self reenableConnectButton]; return;
    }

    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Connecting..." color:[UIColor systemOrangeColor] animating:YES];
    struct IdeviceHandle *device = NULL;
    struct IdeviceFfiError *err = idevice_new_tcp_socket((const idevice_sockaddr *)&addr, sizeof(addr), "IdeviceManager", &device);
    if (err) {
        [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Socket Failed" color:[UIColor systemRedColor] animating:NO];
        [self showAlertWithTitle:@"Error" message:[NSString stringWithUTF8String:err->message]];
        idevice_error_free(err); [self reenableConnectButton]; return;
    }

    struct IdevicePairingFile *pairing_file = NULL;
    err = idevice_pairing_file_read([self.selectedPairingFilePath UTF8String], &pairing_file);
    if (err) {
        [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Pairing Error" color:[UIColor systemRedColor] animating:NO];
        idevice_error_free(err); idevice_free(device); [self reenableConnectButton]; return;
    }

    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_new(device, &lockdown); // device is consumed by lockdownd_new
    if (err) {
        [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Lockdown New Failed" color:[UIColor systemRedColor] animating:NO];
        idevice_error_free(err); idevice_pairing_file_free(pairing_file); idevice_free(device);
        [self reenableConnectButton]; return;
    }

    err = lockdownd_start_session(lockdown, pairing_file);
    if (err) {
        [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Session Failed" color:[UIColor systemRedColor] animating:NO];
        idevice_error_free(err); lockdownd_client_free(lockdown); idevice_pairing_file_free(pairing_file);
        [self reenableConnectButton]; return;
    }

    // Success Lockdown
    plist_t name_plist = NULL;
    lockdownd_get_value(lockdown, "DeviceName", NULL, &name_plist);
    NSString *deviceName = @"iOS Device";
    if (name_plist) { char *val = NULL; plist_get_string_val(name_plist, &val); if (val) { deviceName = [NSString stringWithUTF8String:val]; plist_mem_free(val); } plist_free(name_plist); }
    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Connected" color:[UIColor systemGreenColor] animating:YES];
    dispatch_async(dispatch_get_main_queue(), ^{ self.lockdownDetail.text = [NSString stringWithFormat:@"Verified with %@", deviceName]; });

    // Start Heartbeat and DDI - these take ownership of their own service start now or use cloned lockdown if possible.
    // To avoid crash, we start them and WAIT for them to initiate their connection before freeing lockdown.

    [self updateIndicator:self.heartbeatIndicator label:self.heartbeatLabel status:@"Starting..." color:[UIColor systemOrangeColor] animating:YES];
    [[HeartbeatManager sharedManager] startHeartbeatWithLockdown:lockdown ip:@"10.7.0.1"];
    [self updateIndicator:self.heartbeatIndicator label:self.heartbeatLabel status:@"Active" color:[UIColor systemGreenColor] animating:YES];

    [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"Checking..." color:[UIColor systemOrangeColor] animating:YES];
    [[DdiManager sharedManager] checkAndMountDdiWithLockdown:lockdown ip:@"10.7.0.1" completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) { [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"Mounted" color:[UIColor systemGreenColor] animating:NO]; }
            else { [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"Not Mounted" color:[UIColor systemRedColor] animating:NO]; }
        });
    }];

    // GIVE SERVICES SOME TIME TO INITIATE (Short delay to avoid immediate free of lockdown handle used in background blocks)
    [NSThread sleepForTimeInterval:1.0];

    lockdownd_client_free(lockdown);
    idevice_pairing_file_free(pairing_file);
    [self reenableConnectButton];
}

- (void)reenableConnectButton { dispatch_async(dispatch_get_main_queue(), ^{ self.connectButton.enabled = YES; }); }

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
