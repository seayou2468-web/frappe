#import "IdeviceViewController.h"
#import "ThemeEngine.h"
#import "idevice.h"
#import "FileManagerCore.h"
#import "HeartbeatManager.h"
#import "DdiManager.h"
#import "AppListViewController.h"
#import "LocationSimulationViewController.h"
#import "MobileConfigService.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <arpa/inet.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IdeviceViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) UITextField *ipTextField;
@property (nonatomic, strong) UITextField *portTextField;
@property (nonatomic, strong) UILabel *pairingFileLabel;
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

@property (nonatomic, strong) UITextView *activityLog;

@property (nonatomic, strong) NSString *selectedPairingFilePath;
@property (nonatomic, assign) struct IdevicePairingFile *currentPairingFile;
@property (nonatomic, assign) struct IdeviceProviderHandle *currentProvider;
@property (nonatomic, assign) struct LockdowndClientHandle *currentLockdown;
@property (nonatomic, strong) MobileConfigService *mobileConfig;

@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"iDevice Controller";
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
    self.mobileConfig = nil;
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

    // Network Config Card
    UIView *configCard = [[UIView alloc] init];
    [ThemeEngine applyGlassStyleToView:configCard cornerRadius:25];
    [configCard.heightAnchor constraintEqualToConstant:140].active = YES;
    [self.mainStack addArrangedSubview:configCard];

    UILabel *cfgHeader = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 200, 20)];
    cfgHeader.text = @"REMOTE_TARGET"; cfgHeader.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5]; cfgHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [configCard addSubview:cfgHeader];

    self.ipTextField = [self createStyledTextFieldWithFrame:CGRectMake(20, 45, 180, 35) placeholder:@"IP_ADDRESS"];
    [configCard addSubview:self.ipTextField];

    self.portTextField = [self createStyledTextFieldWithFrame:CGRectMake(210, 45, 80, 35) placeholder:@"PORT"];
    self.portTextField.keyboardType = UIKeyboardTypeNumberPad;
    [configCard addSubview:self.portTextField];

    self.pairingFileLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 95, 270, 30)];
    self.pairingFileLabel.textColor = [UIColor systemYellowColor]; self.pairingFileLabel.font = [UIFont systemFontOfSize:12];
    self.pairingFileLabel.text = @"NO_PAIRING_FILE_LOADED";
    [configCard addSubview:self.pairingFileLabel];

    [self.mainStack addArrangedSubview:[self createActionButtonWithTitle:@"LOAD PAIRING FILE" action:@selector(selectPairingFile)]];

    // Status Section
    UIView *li, *hi, *di;
    UILabel *ll, *ld, *hl, *dl;
    [self.mainStack addArrangedSubview:[self createStatusIndicatorWithTitle:@"LOCKDOWN_SESSION" indicator:&li label:&ll detail:&ld]];
    self.lockdownIndicator = li; self.lockdownLabel = ll; self.lockdownDetail = ld;

    [self.mainStack addArrangedSubview:[self createStatusIndicatorWithTitle:@"HEARTBEAT_RELAY" indicator:&hi label:&hl detail:nil]];
    self.heartbeatIndicator = hi; self.heartbeatLabel = hl;

    [self.mainStack addArrangedSubview:[self createStatusIndicatorWithTitle:@"DDI_IMAGE_MOUNT" indicator:&di label:&dl detail:nil]];
    self.ddiIndicator = di; self.ddiLabel = dl;

    // Device Info Card
    self.infoContainer = [[UIView alloc] init];
    [ThemeEngine applyGlassStyleToView:self.infoContainer cornerRadius:25];
    self.infoContainer.hidden = YES;
    [self.mainStack addArrangedSubview:self.infoContainer];

    self.infoStack = [[UIStackView alloc] init];
    self.infoStack.axis = UILayoutConstraintAxisVertical;
    self.infoStack.spacing = 8;
    self.infoStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.infoContainer addSubview:self.infoStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.infoStack.topAnchor constraintEqualToAnchor:self.infoContainer.topAnchor constant:20],
        [self.infoStack.leadingAnchor constraintEqualToAnchor:self.infoContainer.leadingAnchor constant:20],
        [self.infoStack.trailingAnchor constraintEqualToAnchor:self.infoContainer.trailingAnchor constant:-20],
        [self.infoStack.bottomAnchor constraintEqualToAnchor:self.infoContainer.bottomAnchor constant:-20]
    ]];

    // Activity Log Card
    UIView *logCard = [[UIView alloc] init];
    [ThemeEngine applyGlassStyleToView:logCard cornerRadius:20];
    [logCard.heightAnchor constraintEqualToConstant:120].active = YES;
    [self.mainStack addArrangedSubview:logCard];

    self.activityLog = [[UITextView alloc] initWithFrame:CGRectMake(15, 15, 290, 90)];
    self.activityLog.backgroundColor = [UIColor clearColor];
    self.activityLog.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    self.activityLog.font = [UIFont systemFontOfSize:10];
    self.activityLog.editable = NO;
    self.activityLog.text = @"LOG_IDLE";
    [logCard addSubview:self.activityLog];

    self.connectButton = [self createActionButtonWithTitle:@"ESTABLISH LINK" action:@selector(connectTapped)];
    [self.mainStack addArrangedSubview:self.connectButton];

    self.retryButton = [self createActionButtonWithTitle:@"RETRY HANDSHAKE" action:@selector(connectTapped)];
    self.retryButton.hidden = YES;
    [self.mainStack addArrangedSubview:self.retryButton];
    [self setupMobileConfigUI];

    UIButton *appsButton = [self createActionButtonWithTitle:@"BROWSE APPLICATIONS" action:@selector(showAppList)];
    UIButton *simButton = [self createActionButtonWithTitle:@"LOCATION SIMULATION" action:@selector(showLocationSim)];
    [self.mainStack addArrangedSubview:appsButton];
    [self.mainStack addArrangedSubview:simButton];
}

- (UITextField *)createStyledTextFieldWithFrame:(CGRect)frame placeholder:(NSString *)placeholder {
    UITextField *tf = [[UITextField alloc] initWithFrame:frame];
    tf.placeholder = placeholder;
    tf.textColor = [UIColor whiteColor];
    tf.font = [UIFont systemFontOfSize:14];
    tf.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    tf.layer.cornerRadius = 10;
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)]; tf.leftView = p; tf.leftViewMode = UITextFieldViewModeAlways;
    return tf;
}

- (UIButton *)createActionButtonWithTitle:(NSString *)title action:(SEL)selector {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn.heightAnchor constraintEqualToConstant:55].active = YES;
    [ThemeEngine applyLiquidStyleToView:btn cornerRadius:18];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [btn addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (UIView *)createStatusIndicatorWithTitle:(NSString *)title indicator:(UIView **)indicator label:(UILabel **)label detail:(UILabel **)detail {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card.heightAnchor constraintEqualToConstant:detail ? 110 : 85].active = YES;
    [ThemeEngine applyGlassStyleToView:card cornerRadius:22];

    UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 200, 15)];
    h.text = title; h.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4]; h.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBlack];
    [card addSubview:h];

    UIView *ind = [[UIView alloc] initWithFrame:CGRectMake(20, 40, 32, 32)]; ind.layer.cornerRadius = 16; ind.backgroundColor = [UIColor systemGrayColor];
    [card addSubview:ind]; if (indicator) *indicator = ind;

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(65, 40, 230, 32)]; l.textColor = [UIColor whiteColor]; l.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium]; l.text = @"INACTIVE";
    [card addSubview:l]; if (label) *label = l;

    if (detail) {
        UILabel *d = [[UILabel alloc] initWithFrame:CGRectMake(20, 80, 275, 20)]; d.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5]; d.font = [UIFont systemFontOfSize:12];
        [card addSubview:d]; if (detail) *detail = d;
    }
    return card;
}

- (void)log:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.activityLog.text = [self.activityLog.text stringByAppendingFormat:@"\n> %@", msg];
        [self.activityLog scrollRangeToVisible:NSMakeRange(self.activityLog.text.length - 1, 1)];
    });
}

- (void)updateIndicator:(UIView *)indicator label:(UILabel *)label status:(NSString *)status color:(UIColor *)color animating:(BOOL)animating {
    dispatch_async(dispatch_get_main_queue(), ^{
        label.text = status; indicator.backgroundColor = color; [indicator.layer removeAllAnimations];
        if (animating) {
            CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"]; pulse.duration = 1.2; pulse.fromValue = @(1.0); pulse.toValue = @(0.2); pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF; [indicator.layer addAnimation:pulse forKey:@"pulse"];
            indicator.layer.shadowColor = color.CGColor; indicator.layer.shadowOffset = CGSizeZero; indicator.layer.shadowOpacity = 1.0; indicator.layer.shadowRadius = 12;
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
        self.pairingFileLabel.text = @"CONFIGURED: pairfile.plist";
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
    }
}

- (void)saveSettings {
    [[NSUserDefaults standardUserDefaults] setObject:self.ipTextField.text forKey:@"IdeviceIP"];
    [[NSUserDefaults standardUserDefaults] setObject:self.portTextField.text forKey:@"IdevicePort"];
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    p.delegate = self; [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;

    // Check if it's a P12 or a Plist
    NSString *ext = [url pathExtension].lowercaseString;
    if ([ext isEqualToString:@"p12"] || [ext isEqualToString:@"pfx"]) {
        [self handleSupervisorCertPick:url];
    } else {
        [self handlePairingFilePick:url];
    }
}

- (void)handlePairingFilePick:(NSURL *)url {
    [self log:@"Importing device identity..."];
    BOOL access = [url startAccessingSecurityScopedResource];
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *pairingDir = [docsDir stringByAppendingPathComponent:@"PairingFiles"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pairingDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *targetFilename = @"pairfile.plist";
    NSString *destPath = [pairingDir stringByAppendingPathComponent:targetFilename];
    if ([[NSFileManager defaultManager] fileExistsAtPath:destPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
    }
    NSError *error = nil;
    if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destPath] error:&error]) {
        self.selectedPairingFilePath = destPath;
        self.pairingFileLabel.text = @"CONFIGURED: pairfile.plist";
        self.pairingFileLabel.textColor = [UIColor systemGreenColor];
        [self log:@"Identity imported successfully."];
    } else {
        [self log:[NSString stringWithFormat:@"Import failed: %@", error.localizedDescription]];
    }
    if (access) [url stopAccessingSecurityScopedResource];
}

- (void)handleSupervisorCertPick:(NSURL *)url {
    NSData *p12Data = [NSData dataWithContentsOfURL:url];
    if (!p12Data) { [self log:@"Failed to read certificate"]; return; }

    [self ensureMobileConfig:^(BOOL success) {
        if (!success) return;

        NSDictionary *options = @{(__bridge id)kSecImportExportPassphrase: @""};
        CFArrayRef items = NULL;
        OSStatus status = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);

        if (status == errSecSuccess && CFArrayGetCount(items) > 0) {
            NSDictionary *identityDict = (__bridge NSDictionary *)CFArrayGetValueAtIndex(items, 0);
            SecIdentityRef identity = (__bridge SecIdentityRef)identityDict[(__bridge id)kSecImportItemIdentity];
            SecCertificateRef cert = NULL;
            SecKeyRef key = NULL;
            SecIdentityCopyCertificate(identity, &cert);
            SecIdentityCopyPrivateKey(identity, &key);

            [self.mobileConfig escalateWithCertificate:cert privateKey:key completion:^(BOOL s, id res, NSString *err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (s) [self log:@"Escalation successful!"];
                    else [self log:[NSString stringWithFormat:@"Escalation failed: %@", err]];
                    if (cert) CFRelease(cert);
                    if (key) CFRelease(key);
                });
            }];
            CFRelease(items);
        } else {
            [self log:[NSString stringWithFormat:@"P12 Import failed: %d", (int)status]];
        }
    }];
}

- (void)connectTapped {
    if (!self.selectedPairingFilePath) { [self log:@"ABORT: Identity missing."]; return; }
    self.connectButton.hidden = YES; self.retryButton.hidden = YES; self.infoContainer.hidden = YES;
    [self cleanupHandles];
    [self log:@"Initiating handshake..."];
    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"CONNECTING" color:[UIColor systemOrangeColor] animating:YES];
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
    if (err) { [self handleError:err phase:@"IDENTITY_READ"]; return; }
    self.currentPairingFile = pairing_file;

    struct IdeviceProviderHandle *provider = NULL;
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&addr, pairing_file, "FrappeController", &provider);
    if (err) { [self handleError:err phase:@"PROVIDER_INIT"]; return; }
    self.currentProvider = provider;
    self.currentPairingFile = NULL;

    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) { [self handleError:err phase:@"LOCKDOWN_CONNECT"]; return; }
    self.currentLockdown = lockdown;

    [self log:@"Handshake complete. Session established."];
    [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"VERIFIED" color:[UIColor systemGreenColor] animating:NO];
    [self fetchDeviceInfo:lockdown];

    [self log:@"Activating Heartbeat..."];
    [[HeartbeatManager sharedManager] startHeartbeatWithProvider:provider];
    [self updateIndicator:self.heartbeatIndicator label:self.heartbeatLabel status:@"STABLE" color:[UIColor systemGreenColor] animating:YES];

    [self log:@"Analyzing disk images..."];
    [[DdiManager sharedManager] checkAndMountDdiWithProvider:provider lockdown:lockdown completion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self log:message];
                [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"MOUNTED" color:[UIColor systemGreenColor] animating:NO];
            } else {
                [self log:message];
                [self updateIndicator:self.ddiIndicator label:self.ddiLabel status:@"NOT_FOUND" color:[UIColor systemRedColor] animating:NO];
            }
        });
    }];

    dispatch_async(dispatch_get_main_queue(), ^{ self.connectButton.hidden = NO; });
}

- (void)handleError:(struct IdeviceFfiError *)err phase:(NSString *)phase {
    NSString *msg = (err && err->message && err->message[0] != '\0') ? [NSString stringWithUTF8String:err->message] : @"(no detail)";
    [self log:[NSString stringWithFormat:@"FAIL [%@]: %@", phase, msg]];
    idevice_error_free(err);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateIndicator:self.lockdownIndicator label:self.lockdownLabel status:@"ERROR" color:[UIColor systemRedColor] animating:NO];
        self.lockdownDetail.text = msg;
        self.retryButton.hidden = NO; self.connectButton.hidden = YES;
    });
}

- (void)fetchDeviceInfo:(struct LockdowndClientHandle *)lockdown {
    NSArray *keys = @[@"DeviceName", @"ProductType", @"ProductVersion", @"UniqueDeviceID"];
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
                    dispatch_async(dispatch_get_main_queue(), ^{ self.lockdownDetail.text = nsVal; });
                }
                plist_mem_free(val);
            }
            plist_free(val_plist);
        }
    }
}

- (void)addInfoRow:(NSString *)key value:(NSString *)value {
    UILabel *row = [[UILabel alloc] init];
    row.textColor = [UIColor whiteColor]; row.font = [UIFont systemFontOfSize:13 weight:UIFontWeightLight];
    row.text = [NSString stringWithFormat:@"%@: %@", key, value];
    [self.infoStack addArrangedSubview:row];
}

- (void)showLocationSim {
    if (!self.currentProvider) { [self log:@"Link required."]; return; }
    LocationSimulationViewController *vc = [[LocationSimulationViewController alloc] initWithProvider:self.currentProvider lockdown:self.currentLockdown];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAppList {
    if (!self.currentProvider) { [self log:@"Link required."]; return; }
    AppListViewController *vc = [[AppListViewController alloc] initWithProvider:self.currentProvider];
    [self.navigationController pushViewController:vc animated:YES];
}


- (void)setupMobileConfigUI {
    UIView *mcCard = [[UIView alloc] init];
    [ThemeEngine applyGlassStyleToView:mcCard cornerRadius:25];
    [self.mainStack addArrangedSubview:mcCard];

    UILabel *mcHeader = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 200, 20)];
    mcHeader.text = @"MOBILE_CONFIG"; mcHeader.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5]; mcHeader.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [mcCard addSubview:mcHeader];

    UIButton *listBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [listBtn setTitle:@"LIST PROFILES" forState:UIControlStateNormal];
    listBtn.frame = CGRectMake(20, 45, 120, 35);
    [listBtn addTarget:self action:@selector(listProfiles) forControlEvents:UIControlEventTouchUpInside];
    [mcCard addSubview:listBtn];

    UIButton *restrBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [restrBtn setTitle:@"RESTRICTIONS" forState:UIControlStateNormal];
    restrBtn.frame = CGRectMake(150, 45, 120, 35);
    [restrBtn addTarget:self action:@selector(installRestrictions) forControlEvents:UIControlEventTouchUpInside];
    [mcCard addSubview:restrBtn];

    UIButton *escBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [escBtn setTitle:@"ESCALATE" forState:UIControlStateNormal];
    escBtn.frame = CGRectMake(20, 85, 120, 35);
    [escBtn addTarget:self action:@selector(escalateSupervisor) forControlEvents:UIControlEventTouchUpInside];
    [mcCard addSubview:escBtn];

    UIButton *eraseBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [eraseBtn setTitle:@"ERASE DEVICE" forState:UIControlStateNormal];
    eraseBtn.frame = CGRectMake(150, 85, 120, 35);
    [eraseBtn addTarget:self action:@selector(eraseDevice) forControlEvents:UIControlEventTouchUpInside];
    [mcCard addSubview:eraseBtn];

    [mcCard.heightAnchor constraintEqualToConstant:130].active = YES;
}

- (void)listProfiles {
    [self ensureMobileConfig:^(BOOL success) {
        if (!success) return;
        [self.mobileConfig getProfileListWithCompletion:^(BOOL s, id res, NSString *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (s) {
                    [self log:[NSString stringWithFormat:@"Profiles: %@", res]];
                } else {
                    [self log:[NSString stringWithFormat:@"List failed: %@", err]];
                }
            });
        }];
    }];
}

- (void)installRestrictions {
    [self ensureMobileConfig:^(BOOL success) {
        if (!success) return;
        [self.mobileConfig installRestrictionsProfileWithCompletion:^(BOOL s, id res, NSString *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (s) {
                    [self log:@"Restrictions profile installed"];
                } else {
                    [self log:[NSString stringWithFormat:@"Failed: %@", err]];
                }
            });
        }];
    }];
}

- (void)ensureMobileConfig:(void(^)(BOOL))completion {
    if (self.mobileConfig) { completion(YES); return; }
    if (!self.currentProvider) { [self log:@"No device connected"]; completion(NO); return; }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint16_t rsdPort = 0;
        struct ReadWriteOpaque *stream = NULL;
        struct IdeviceFfiError *err = NULL;

        // Try RSD port lookup if we could, but we need CoreDeviceProxy for that.
        // For now, let's stick to legacy or try to guess RSD port if it's constant,
        // OR better, use the Lockdown client to get it if possible.

        // Let's use the provided Lockdown client to start service
        if (self.currentLockdown) {
            uint16_t port = 0;
            err = lockdownd_start_service(self.currentLockdown, "com.apple.mobile.MCInstall", &port, NULL);
            if (!err) {
                err = adapter_connect(self.currentProvider, port, &stream);
            }
        }

        if (err || !stream) {
            if (err) idevice_error_free(err);
            // Fallback or retry
            if (self.currentLockdown && !stream) {
                uint16_t port2 = 0;
                err = lockdownd_start_service(self.currentLockdown, "com.apple.mobile.MCInstall", &port2, NULL);
                if (!err) {
                    err = adapter_connect(self.currentProvider, port2, &stream);
                }
                if (err) idevice_error_free(err);
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (stream) {
                self.mobileConfig = [[MobileConfigService alloc] initWithStream:stream];
                completion(YES);
            } else {
                [self log:@"Failed to connect to MobileConfig service"];
                completion(NO);
            }
        });
    });
}


- (void)escalateSupervisor {

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.rsa.pkcs-12", @"public.item"] inMode:UIDocumentPickerModeImport];

    picker.delegate = (id<UIDocumentPickerDelegate>)self;

    picker.allowsMultipleSelection = NO;

    [self presentViewController:picker animated:YES completion:nil];

}







- (void)eraseDevice {

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Erase Device" message:@"Are you sure? This will wipe the device." preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [alert addAction:[UIAlertAction actionWithTitle:@"ERASE" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {

        [self ensureMobileConfig:^(BOOL success) {

            if (!success) return;

            [self.mobileConfig eraseDeviceWithPreserveDataPlan:NO disallowProximity:NO completion:^(BOOL s, id res, NSString *err) {

                dispatch_async(dispatch_get_main_queue(), ^{

                    if (s) [self log:@"Erase command sent"];

                    else [self log:[NSString stringWithFormat:@"Erase failed: %@", err]];

                });

            }];

        }];

    }]];

    [self presentViewController:alert animated:YES completion:nil];

}

@end
