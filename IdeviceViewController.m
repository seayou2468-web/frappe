#import "IdeviceViewController.h"
#import "ThemeEngine.h"
#import "idevice.h"
#import "FileManagerCore.h"
#import "HeartbeatManager.h"
#import "DdiManager.h"
#import "AppListViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface IdeviceViewController () <UIDocumentPickerDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;

// Status Containers
@property (nonatomic, strong) UIView *lockdownIndicator;
@property (nonatomic, strong) UILabel *lockdownLabel;
@property (nonatomic, strong) UILabel *lockdownDetail;

@property (nonatomic, strong) UIView *heartbeatIndicator;
@property (nonatomic, strong) UILabel *heartbeatLabel;

@property (nonatomic, strong) UIView *ddiIndicator;
@property (nonatomic, strong) UILabel *ddiLabel;

@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *selectPairingFileButton;
@property (nonatomic, strong) NSString *selectedPairingFilePath;
@property (nonatomic, strong) UILabel *pairingFileLabel;

@property (nonatomic, assign) struct LockdowndClientHandle *currentLockdown;
@property (nonatomic, assign) struct IdeviceProviderHandle *currentProvider;
@property (nonatomic, assign) struct IdevicePairingFile *currentPairingFile;

@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = @"iDevice Manager";
    [self setupUI];
    idevice_init_logger(Debug, Debug, NULL);
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
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.mainStack = [[UIStackView alloc] init];
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.mainStack.axis = UILayoutConstraintAxisVertical;
    self.mainStack.spacing = 20;
    self.mainStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.mainStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20],
        [self.mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.mainStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20]
    ]];

    UIView *li, *hi, *di; UILabel *ll, *hl, *dl, *ldt;

    [self.mainStack addArrangedSubview:[self createStatusContainerWithTitle:@"Lockdown Connection" indicator:&li label:&ll detail:&ldt]];
    self.lockdownIndicator = li; self.lockdownLabel = ll; self.lockdownDetail = ldt;

    [self.mainStack addArrangedSubview:[self createStatusContainerWithTitle:@"Heartbeat Status" indicator:&hi label:&hl detail:NULL]];
    self.heartbeatIndicator = hi; self.heartbeatLabel = hl;

    [self.mainStack addArrangedSubview:[self createStatusContainerWithTitle:@"DDI Image Status" indicator:&di label:&dl detail:NULL]];
    self.ddiIndicator = di; self.ddiLabel = dl;

    self.pairingFileLabel = [[UILabel alloc] init];
    self.pairingFileLabel.textColor = [UIColor lightGrayColor]; self.pairingFileLabel.font = [UIFont systemFontOfSize:14]; self.pairingFileLabel.numberOfLines = 2; self.pairingFileLabel.textAlignment = NSTextAlignmentCenter; self.pairingFileLabel.text = @"No pairing file selected";
    [self.mainStack addArrangedSubview:self.pairingFileLabel];

    self.selectPairingFileButton = [self createActionButtonWithTitle:@"Select Pairing File" action:@selector(selectPairingFile)];
    [self.mainStack addArrangedSubview:self.selectPairingFileButton];

    self.connectButton = [self createActionButtonWithTitle:@"Establish Link" action:@selector(connectTapped)];
    [self.mainStack addArrangedSubview:self.connectButton];

    UIButton *appsButton = [self createActionButtonWithTitle:@"Application List" action:@selector(showAppList)];
    [self.mainStack addArrangedSubview:appsButton];
}

- (UIButton *)createActionButtonWithTitle:(NSString *)title action:(SEL)selector {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setHeightAnchor:[btn.heightAnchor constraintEqualToConstant:50]];
    [ThemeEngine applyLiquidStyleToView:btn cornerRadius:15];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIView *)createStatusContainerWithTitle:(NSString *)title indicator:(UIView **)indicator label:(UILabel **)label detail:(UILabel **)detail {
    UIView *container = [[UIView alloc] init];
    [container.heightAnchor constraintEqualToConstant:detail ? 140 : 100].active = YES;
    [ThemeEngine applyGlassStyleToView:container cornerRadius:20];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 300, 20)];
    header.text = title; header.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6]; header.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [container addSubview:header];

    UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(15, 40, 40, 40)]; ind.layer.cornerRadius = 20; ind.backgroundColor = [UIColor systemGrayColor];
    [container addSubview:ind]; if (indicator) *indicator = ind;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(70, 40, 250, 40)]; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont boldSystemFontOfSize:16]; lbl.text = @"Inactive";
    [container addSubview:lbl]; if (label) *label = lbl;

    if (detail) {
        UILabel *dtl = [[UILabel alloc] initWithFrame:CGRectMake(15, 90, 300, 40)]; dtl.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5]; dtl.font = [UIFont systemFontOfSize:13]; dtl.numberOfLines = 2;
        [container addSubview:dtl]; if (detail) *detail = dtl;
    }
    return container;
}

- (void)updateIndicator:(UIView *)indicator label:(UILabel *)label status:(NSString *)status color:(UIColor *)color animating:(BOOL)animating {
    dispatch_async(dispatch_get_main_queue(), ^{
        label.text = status; indicator.backgroundColor = color; [indicator.layer removeAllAnimations];
        if (animating) {
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"]; pulse.duration = 1.0; pulse.fromValue = @(1.0); pulse.toValue = @(0.3); pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF; [indicator.layer addAnimation:pulse forKey:@"pulse"];
            indicator.layer.shadowColor = color.CGColor; indicator.layer.shadowOffset = CGSizeZero; indicator.layer.shadowOpacity = 1.0; indicator.layer.shadowRadius = 10;
        } else { indicator.layer.shadowOpacity = 0; }
    });
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
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
    self.connectButton.enabled = NO; [self cleanupHandles];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{ [self performConnection]; });
}

- (void)performConnection {
    const char *ip = "10.7.0.1"; int port = 62078;
    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET; addr.sin_port = htons(port);
    inet_pton(AF_INET, ip, &addr.sin_addr);

    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Starting Provider..." color:[UIColor systemOrangeColor] animating:YES];
    struct IdevicePairingFile *pairing_file = NULL;
    struct IdeviceFfiError *err = idevice_pairing_file_read([self.selectedPairingFilePath UTF8String], &pairing_file);
    if (err) { [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Pairing Error" color:[UIColor systemRedColor] animating:NO]; idevice_error_free(err); [self reenableConnectButton]; return; }
    self.currentPairingFile = pairing_file;

    struct IdeviceProviderHandle *provider = NULL;
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pairing_file, "IdeviceManager", &provider);
    if (err) { [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Provider Failed" color:[UIColor systemRedColor] animating:NO]; [self showAlertWithTitle:@"Error" message:[NSString stringWithUTF8String:err->message]]; idevice_error_free(err); [self reenableConnectButton]; return; }
    self.currentProvider = provider;

    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) { [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Lockdown Failed" color:[UIColor systemRedColor] animating:NO]; [self showAlertWithTitle:@"Error" message:[NSString stringWithUTF8String:err->message]]; idevice_error_free(err); [self reenableConnectButton]; return; }
    self.currentLockdown = lockdown;

    plist_t name_plist = NULL;
    lockdownd_get_value(lockdown, "DeviceName", NULL, &name_plist);
    NSString *deviceName = @"iOS Device";
    if (name_plist) { char *val = NULL; plist_get_string_val(name_plist, &val); if (val) { deviceName = [NSString stringWithUTF8String:val]; plist_mem_free(val); } plist_free(name_plist); }
    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Connected" color:[UIColor systemGreenColor] animating:YES];
    dispatch_async(dispatch_get_main_queue(), ^{ self.lockdownDetail.text = [NSString stringWithFormat:@"Verified with %@", deviceName]; });

    [[HeartbeatManager sharedManager] startHeartbeatWithProvider:provider];
    [self updateIndicator:self.heartbeatIndicator label:self.heartbeatLabel status:@"Active" color:[UIColor systemGreenColor] animating:YES];

    [[DdiManager sharedManager] checkAndMountDdiWithProvider:provider lockdown:lockdown completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) { [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"Mounted" color:[UIColor systemGreenColor] animating:NO]; }
            else { [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"Not Mounted" color:[UIColor systemRedColor] animating:NO]; }
        });
    }];
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

- (void)showAppList {
    if (!self.currentProvider) { [self showAlertWithTitle:@"Error" message:@"Please connect to a device first."]; return; }
    AppListViewController *vc = [[AppListViewController alloc] initWithProvider:self.currentProvider];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
