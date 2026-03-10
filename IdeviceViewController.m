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
@property (nonatomic, strong) UITextField *ipTextField;
@property (nonatomic, strong) UITextField *portTextField;
@property (nonatomic, strong) UILabel *pairingFileLabel;
@property (nonatomic, strong) UIButton *selectPairingFileButton;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *retryButton;

@property (nonatomic, strong) UIView *lockdownIndicator;
@property (nonatomic, strong) UILabel *lockdownLabel;
@property (nonatomic, strong) UILabel *lockdownDetail;

@property (nonatomic, strong) UIView *heartbeatIndicator;
@property (nonatomic, strong) UILabel *heartbeatLabel;

@property (nonatomic, strong) UIView *ddiIndicator;
@property (nonatomic, strong) UILabel *ddiLabel;

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
    self.title = @"iDevice Manager";
    [self setupUI];
    [self loadSettings];
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
    self.mainStack.spacing = 20;
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.mainStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20],
        [self.mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.mainStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20]
    ]];

    // Connection Settings
    UIView *configContainer = [[UIView alloc] init];
    [ThemeEngine applyGlassStyleToView:configContainer cornerRadius:20];
    [configContainer.heightAnchor constraintEqualToConstant:120].active = YES;
    [self.mainStack addArrangedSubview:configContainer];

    UILabel *cfgHeader = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 20)];
    cfgHeader.text = @"NETWORK CONFIGURATION"; cfgHeader.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6]; cfgHeader.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [configContainer addSubview:cfgHeader];

    self.ipTextField = [self createTextFieldWithPlaceholder:@"IP Address (e.g. 10.7.0.1)" frame:CGRectMake(15, 40, 200, 30)];
    [configContainer addSubview:self.ipTextField];

    self.portTextField = [self createTextFieldWithPlaceholder:@"Port" frame:CGRectMake(225, 40, 80, 30)];
    self.portTextField.keyboardType = UIKeyboardTypeNumberPad;
    [configContainer addSubview:self.portTextField];

    self.pairingFileLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 80, 290, 30)];
    self.pairingFileLabel.textColor = [UIColor lightGrayColor]; self.pairingFileLabel.font = [UIFont systemFontOfSize:12];
    self.pairingFileLabel.text = @"No pairing file selected";
    [configContainer addSubview:self.pairingFileLabel];

    self.selectPairingFileButton = [self createActionButtonWithTitle:@"Select Pairing File" action:@selector(selectPairingFile)];
    [self.mainStack addArrangedSubview:self.selectPairingFileButton];

    // Status Section
    UIView *li, *hi, *di;
    UILabel *ll, *ld, *hl, *dl;

    [self.mainStack addArrangedSubview:[self createStatusContainerWithTitle:@"LOCKDOWN SESSION" indicator:&li label:&ll detail:&ld]];
    self.lockdownIndicator = li; self.lockdownLabel = ll; self.lockdownDetail = ld;

    [self.mainStack addArrangedSubview:[self createStatusContainerWithTitle:@"HEARTBEAT RELAY" indicator:&hi label:&hl detail:nil]];
    self.heartbeatIndicator = hi; self.heartbeatLabel = hl;

    [self.mainStack addArrangedSubview:[self createStatusContainerWithTitle:@"DDI MOUNT STATUS" indicator:&di label:&dl detail:nil]];
    self.ddiIndicator = di; self.ddiLabel = dl;

    // Device Info Section (Initially Hidden)
    self.infoContainer = [[UIView alloc] init];
    [ThemeEngine applyGlassStyleToView:self.infoContainer cornerRadius:20];
    self.infoContainer.hidden = YES;
    [self.mainStack addArrangedSubview:self.infoContainer];

    self.infoStack = [[UIStackView alloc] init];
    self.infoStack.axis = UILayoutConstraintAxisVertical;
    self.infoStack.spacing = 10;
    self.infoStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.infoContainer addSubview:self.infoStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.infoStack.topAnchor constraintEqualToAnchor:self.infoContainer.topAnchor constant:15],
        [self.infoStack.leadingAnchor constraintEqualToAnchor:self.infoContainer.leadingAnchor constant:15],
        [self.infoStack.trailingAnchor constraintEqualToAnchor:self.infoContainer.trailingAnchor constant:-15],
        [self.infoStack.bottomAnchor constraintEqualToAnchor:self.infoContainer.bottomAnchor constant:-15]
    ]];

    self.connectButton = [self createActionButtonWithTitle:@"Establish Link" action:@selector(connectTapped)];
    [self.mainStack addArrangedSubview:self.connectButton];

    self.retryButton = [self createActionButtonWithTitle:@"Retry Connection" action:@selector(connectTapped)];
    self.retryButton.hidden = YES;
    [self.mainStack addArrangedSubview:self.retryButton];

    UIButton *appsButton = [self createActionButtonWithTitle:@"Application List" action:@selector(showAppList)];
    [self.mainStack addArrangedSubview:appsButton];
}

- (UITextField *)createTextFieldWithPlaceholder:(NSString *)placeholder frame:(CGRect)frame {
    UITextField *tf = [[UITextField alloc] initWithFrame:frame];
    tf.placeholder = placeholder;
    tf.textColor = [UIColor whiteColor];
    tf.font = [UIFont systemFontOfSize:14];
    tf.borderStyle = UITextBorderStyleNone;
    tf.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    tf.layer.cornerRadius = 8;
    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 20)];
    tf.leftView = paddingView; tf.leftViewMode = UITextFieldViewModeAlways;
    return tf;
}

- (UIButton *)createActionButtonWithTitle:(NSString *)title action:(SEL)selector {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn.heightAnchor constraintEqualToConstant:50].active = YES;
    [ThemeEngine applyLiquidStyleToView:btn cornerRadius:15];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIView *)createStatusContainerWithTitle:(NSString *)title indicator:(UIView **)indicator label:(UILabel **)label detail:(UILabel **)detail {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [container.heightAnchor constraintEqualToConstant:detail ? 120 : 80].active = YES;
    [ThemeEngine applyGlassStyleToView:container cornerRadius:20];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 300, 20)];
    header.text = title; header.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6]; header.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [container addSubview:header];

    UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(15, 35, 30, 30)]; ind.layer.cornerRadius = 15; ind.backgroundColor = [UIColor systemGrayColor];
    [container addSubview:ind]; if (indicator) *indicator = ind;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(55, 35, 250, 30)]; lbl.textColor = [UIColor whiteColor]; lbl.font = [UIFont boldSystemFontOfSize:15]; lbl.text = @"Inactive";
    [container addSubview:lbl]; if (label) *label = lbl;

    if (detail) {
        UILabel *dtl = [[UILabel alloc] initWithFrame:CGRectMake(15, 75, 300, 35)]; dtl.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5]; dtl.font = [UIFont systemFontOfSize:12]; dtl.numberOfLines = 2;
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

- (void)loadSettings {
    self.ipTextField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
    self.portTextField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdevicePort"] ?: @"62078";
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairingPath = [docsDir stringByAppendingPathComponent:@"PairingFiles/pairfile.plist"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pairingPath]) {
        self.selectedPairingFilePath = pairingPath;
        self.pairingFileLabel.text = @"pairfile.plist";
    }
}

- (void)saveSettings {
    [[NSUserDefaults standardUserDefaults] setObject:self.ipTextField.text forKey:@"IdeviceIP"];
    [[NSUserDefaults standardUserDefaults] setObject:self.portTextField.text forKey:@"IdevicePort"];
    [[NSUserDefaults standardUserDefaults] synchronize];
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
        self.pairingFileLabel.text = filename;
    }
}

- (void)connectTapped {
    if (!self.selectedPairingFilePath) {
        self.lockdownLabel.text = @"Pairing File Required";
        self.lockdownIndicator.backgroundColor = [UIColor systemRedColor];
        return;
    }
    self.connectButton.hidden = YES;
    self.retryButton.hidden = YES;
    self.infoContainer.hidden = YES;
    [self cleanupHandles];
    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Connecting..." color:[UIColor systemOrangeColor] animating:YES];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{ [self performConnection]; });
}

- (void)performConnection {
    const char *ipStr = [self.ipTextField.text UTF8String];
    int port = [self.portTextField.text intValue];
    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET; addr.sin_port = htons(port);
    inet_pton(AF_INET, ipStr, &addr.sin_addr);

    struct IdevicePairingFile *pairing_file = NULL;
    struct IdeviceFfiError *err = idevice_pairing_file_read([self.selectedPairingFilePath UTF8String], &pairing_file);
    if (err) { [self handleError:err phase:@"Pairing"]; return; }
    self.currentPairingFile = pairing_file;

    struct IdeviceProviderHandle *provider = NULL;
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pairing_file, "IdeviceManager", &provider);
    if (err) { [self handleError:err phase:@"Provider"]; return; }
    self.currentProvider = provider;
    self.currentPairingFile = NULL; // Consumed

    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) { [self handleError:err phase:@"Lockdown"]; return; }
    self.currentLockdown = lockdown;

    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"Connected" color:[UIColor systemGreenColor] animating:NO];
    [self fetchDeviceInfo:lockdown];

    [[HeartbeatManager sharedManager] startHeartbeatWithProvider:provider];
    [self updateIndicator:self.heartbeatIndicator label:self.heartbeatLabel status:@"Active" color:[UIColor systemGreenColor] animating:YES];

    [[DdiManager sharedManager] checkAndMountDdiWithProvider:provider lockdown:lockdown completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) { [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"Mounted" color:[UIColor systemGreenColor] animating:NO]; }
            else { [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"Not Mounted" color:[UIColor systemRedColor] animating:NO]; }
        });
    }];

    dispatch_async(dispatch_get_main_queue(), ^{ self.connectButton.hidden = NO; });
}

- (void)handleError:(struct IdeviceFfiError *)err phase:(NSString *)phase {
    NSString *msg = [NSString stringWithUTF8String:err->message];
    idevice_error_free(err);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.lockdownLabel.text = [NSString stringWithFormat:@"%@ Error", phase];
        self.lockdownDetail.text = msg;
        self.lockdownIndicator.backgroundColor = [UIColor systemRedColor];
        [self.lockdownIndicator.layer removeAllAnimations];
        self.retryButton.hidden = NO;
        self.connectButton.hidden = YES;
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
                if ([key isEqualToString:@"DeviceName"]) {
                    dispatch_async(dispatch_get_main_queue(), ^{ self.lockdownDetail.text = [NSString stringWithFormat:@"Verified with %@", nsVal]; });
                }
                plist_mem_free(val);
            }
            plist_free(val_plist);
        }
    }
}

- (void)addInfoRow:(NSString *)key value:(NSString *)value {
    UILabel *row = [[UILabel alloc] init];
    row.numberOfLines = 0;
    NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: ", key] attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:12], NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.6]}];
    [str appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor whiteColor]}]];
    row.attributedText = str;
    [self.infoStack addArrangedSubview:row];
}

- (void)showAppList {
    if (!self.currentProvider) return;
    AppListViewController *vc = [[AppListViewController alloc] initWithProvider:self.currentProvider];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
