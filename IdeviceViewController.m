#import "IdeviceViewController.h"
#import "ThemeEngine.h"
#import "idevice.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface IdeviceViewController ()

@property (nonatomic, strong) UIView *statusContainer;
@property (nonatomic, strong) UIView *statusIndicator;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) UIButton *selectPairingFileButton;
@property (nonatomic, strong) NSURL *selectedPairingFileURL;
@property (nonatomic, strong) UILabel *pairingFileLabel;
@property (nonatomic, strong) UILabel *deviceInfoLabel;

@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = @"iDevice Connection";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
    [self setupUI];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setupUI {
    // Status Container (Glass Style)
    self.statusContainer = [[UIView alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width - 40, 200)];
    [ThemeEngine applyGlassStyleToView:self.statusContainer cornerRadius:20];
    [self.view addSubview:self.statusContainer];

    // Status Indicator (Circle)
    self.statusIndicator = [[UIView alloc] initWithFrame:CGRectMake((self.statusContainer.bounds.size.width - 60) / 2, 40, 60, 60)];
    self.statusIndicator.layer.cornerRadius = 30;
    self.statusIndicator.backgroundColor = [UIColor systemGrayColor];
    [self.statusContainer addSubview:self.statusIndicator];

    // Status Label
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, self.statusContainer.bounds.size.width, 30)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:18];
    self.statusLabel.text = @"Disconnected";
    [self.statusContainer addSubview:self.statusLabel];

    // Device Info Label
    self.deviceInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 150, self.statusContainer.bounds.size.width - 20, 40)];
    self.deviceInfoLabel.textAlignment = NSTextAlignmentCenter;
    self.deviceInfoLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    self.deviceInfoLabel.font = [UIFont systemFontOfSize:14];
    self.deviceInfoLabel.numberOfLines = 2;
    [self.statusContainer addSubview:self.deviceInfoLabel];

    // Pairing File Label
    self.pairingFileLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 320, self.view.bounds.size.width - 40, 40)];
    self.pairingFileLabel.textColor = [UIColor lightGrayColor];
    self.pairingFileLabel.font = [UIFont systemFontOfSize:14];
    self.pairingFileLabel.numberOfLines = 2;
    self.pairingFileLabel.textAlignment = NSTextAlignmentCenter;
    self.pairingFileLabel.text = @"No pairing file selected";
    [self.view addSubview:self.pairingFileLabel];

    // Select Pairing File Button
    self.selectPairingFileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.selectPairingFileButton.frame = CGRectMake(40, 380, self.view.bounds.size.width - 80, 50);
    [self.selectPairingFileButton setTitle:@"Select Pairing File" forState:UIControlStateNormal];
    [ThemeEngine applyLiquidStyleToView:self.selectPairingFileButton cornerRadius:15];
    [self.selectPairingFileButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.selectPairingFileButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.selectPairingFileButton];

    // Connect Button
    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.connectButton.frame = CGRectMake(40, 450, self.view.bounds.size.width - 80, 50);
    [self.connectButton setTitle:@"Connect to 10.7.0.1:62078" forState:UIControlStateNormal];
    [ThemeEngine applyLiquidStyleToView:self.connectButton cornerRadius:15];
    [self.connectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.connectButton addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.connectButton];
}

- (void)updateStatus:(NSString *)status color:(UIColor *)color animating:(BOOL)animating {
    self.statusLabel.text = status;
    self.statusIndicator.backgroundColor = color;
    [self.statusIndicator.layer removeAllAnimations];

    if (animating) {
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.duration = 0.8;
        pulse.fromValue = @(1.0);
        pulse.toValue = @(0.3);
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        [self.statusIndicator.layer addAnimation:pulse forKey:@"pulse"];

        // Glow effect
        self.statusIndicator.layer.shadowColor = color.CGColor;
        self.statusIndicator.layer.shadowOffset = CGSizeZero;
        self.statusIndicator.layer.shadowOpacity = 1.0;
        self.statusIndicator.layer.shadowRadius = 15;
    } else {
        self.statusIndicator.layer.shadowOpacity = 0;
    }
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypePropertyList, UTTypeData]];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) {
        self.selectedPairingFileURL = url;
        self.pairingFileLabel.text = [NSString stringWithFormat:@"Selected: %@", url.lastPathComponent];
    }
}

- (void)connectTapped {
    if (!self.selectedPairingFileURL) {
        [self showAlertWithTitle:@"Error" message:@"Please select a pairing file first."];
        return;
    }

    [self updateStatus:@"Connecting..." color:[UIColor systemOrangeColor] animating:YES];
    self.deviceInfoLabel.text = @"";
    self.connectButton.enabled = NO;

    [self performConnection];
}

- (void)performConnection {
    const char *ip = "10.7.0.1";
    int port = 62078;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, ip, &addr.sin_addr) <= 0) {
        [self updateStatus:@"Invalid IP Address" color:[UIColor systemRedColor] animating:NO];
        [self showAlertWithTitle:@"Error" message:@"Invalid IP Address configuration."];
        [self reenableConnectButton];
        return;
    }

    struct IdeviceHandle *device = NULL;
    struct IdeviceFfiError *err = idevice_new_tcp_socket((const idevice_sockaddr *)&addr, sizeof(addr), "IdeviceManager", &device);
    if (err) {
        NSString *msg = [NSString stringWithUTF8String:err->message];
        idevice_error_free(err);
        [self updateStatus:@"Connection Failed" color:[UIColor systemRedColor] animating:NO];
        [self showAlertWithTitle:@"Connection Error" message:msg];
        [self reenableConnectButton];
        return;
    }

    struct IdevicePairingFile *pairing_file = NULL;
    BOOL access = [self.selectedPairingFileURL startAccessingSecurityScopedResource];
    err = idevice_pairing_file_read([self.selectedPairingFileURL.path UTF8String], &pairing_file);
    if (access) [self.selectedPairingFileURL stopAccessingSecurityScopedResource];

    if (err) {
        NSString *msg = [NSString stringWithUTF8String:err->message];
        idevice_error_free(err);
        idevice_free(device);
        [self updateStatus:@"Pairing File Error" color:[UIColor systemRedColor] animating:NO];
        [self showAlertWithTitle:@"Pairing Error" message:msg];
        [self reenableConnectButton];
        return;
    }

    // Start TLS Session
    err = idevice_start_session(device, pairing_file, NO);
    if (err) {
        NSString *msg = [NSString stringWithUTF8String:err->message];
        idevice_error_free(err);
        idevice_pairing_file_free(pairing_file);
        idevice_free(device);
        [self updateStatus:@"Session Error" color:[UIColor systemRedColor] animating:NO];
        [self showAlertWithTitle:@"Session Error" message:msg];
        [self reenableConnectButton];
        return;
    }

    // Connect to lockdownd
    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_new(device, &lockdown);
    if (err) {
        NSString *msg = [NSString stringWithUTF8String:err->message];
        idevice_error_free(err);
        idevice_pairing_file_free(pairing_file);
        idevice_free(device);
        [self updateStatus:@"Lockdownd Error" color:[UIColor systemRedColor] animating:NO];
        [self showAlertWithTitle:@"Lockdownd Error" message:msg];
        [self reenableConnectButton];
        return;
    }

    // Start Lockdownd Session
    err = lockdownd_start_session(lockdown, pairing_file);
    if (err) {
        NSString *msg = [NSString stringWithUTF8String:err->message];
        idevice_error_free(err);
        lockdownd_client_free(lockdown);
        idevice_pairing_file_free(pairing_file);
        idevice_free(device);
        [self updateStatus:@"Lockdown Session Error" color:[UIColor systemRedColor] animating:NO];
        [self showAlertWithTitle:@"Lockdown Session Error" message:msg];
        [self reenableConnectButton];
        return;
    }

    // Get Device Name to verify
    plist_t name_plist = NULL;
    err = lockdownd_get_value(lockdown, "DeviceName", NULL, &name_plist);
    NSString *deviceName = @"Connected Device";
    if (!err && name_plist) {
        char *val = NULL;
        plist_get_string_val(name_plist, &val);
        if (val) {
            deviceName = [NSString stringWithUTF8String:val];
            plist_mem_free(val);
        }
        plist_free(name_plist);
    } else if (err) {
        idevice_error_free(err);
    }

    // If we reached here, we are fully connected and verified
    [self updateStatus:@"Connected" color:[UIColor systemGreenColor] animating:YES];
    self.deviceInfoLabel.text = deviceName;
    [self showAlertWithTitle:@"Success" message:[NSString stringWithFormat:@"Successfully connected and verified with %@!", deviceName]];

    // Clean up
    lockdownd_client_free(lockdown);
    idevice_pairing_file_free(pairing_file);
    idevice_free(device);
    [self reenableConnectButton];
}

- (void)reenableConnectButton {
    self.connectButton.enabled = YES;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
