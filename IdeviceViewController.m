#import "IdeviceViewController.h"
#import "ThemeEngine.h"
#import "L.h"
#import "extend/idevice.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <arpa/inet.h>

typedef NS_ENUM(NSInteger, DeviceConnectionStatus) {
    DeviceConnectionStatusDisconnected,
    DeviceConnectionStatusConnecting,
    DeviceConnectionStatusConnected,
    DeviceConnectionStatusError
};

@interface IdeviceViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *statusIndicator;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *pairingFileButton;
@property (nonatomic, strong) UIButton *connectButton;
@property (nonatomic, strong) NSString *selectedPairingPath;
@property (nonatomic, assign) DeviceConnectionStatus status;
@property (nonatomic, strong) UILabel *infoLabel;
@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = [L s:@"iDevice管理" en:@"iDevice Manager"];

    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self autoConnectIfPossible];
}

- (void)setupUI {
    self.statusIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
    self.statusIndicator.center = CGPointMake(self.view.bounds.size.width / 2, 200);
    self.statusIndicator.layer.cornerRadius = 50;
    self.statusIndicator.backgroundColor = [UIColor grayColor];
    [self.view addSubview:self.statusIndicator];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 260, self.view.bounds.size.width, 30)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.view addSubview:self.statusLabel];

    self.infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 300, self.view.bounds.size.width - 40, 60)];
    self.infoLabel.numberOfLines = 0;
    self.infoLabel.textAlignment = NSTextAlignmentCenter;
    self.infoLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    self.infoLabel.font = [UIFont systemFontOfSize:14];
    [self.view addSubview:self.infoLabel];

    self.pairingFileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pairingFileButton.frame = CGRectMake(40, 380, self.view.bounds.size.width - 80, 50);
    [ThemeEngine applyGlassStyleToView:self.pairingFileButton cornerRadius:12];
    [self.pairingFileButton setTitle:[L s:@"ペアリングファイルを選択" en:@"Select Pairing File"] forState:UIControlStateNormal];
    [self.pairingFileButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.pairingFileButton addTarget:self action:@selector(selectPairingFile) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pairingFileButton];

    self.connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.connectButton.frame = CGRectMake(40, 450, self.view.bounds.size.width - 80, 50);
    [ThemeEngine applyLiquidStyleToView:self.connectButton cornerRadius:12];
    [self.connectButton setTitle:[L s:@"接続" en:@"Connect"] forState:UIControlStateNormal];
    [self.connectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.connectButton addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.connectButton];

    [self updateStatus:DeviceConnectionStatusDisconnected message:@""];
}

- (void)updateStatus:(DeviceConnectionStatus)status message:(NSString *)msg {
    self.status = status;
    UIColor *baseColor;
    NSString *statusText;

    switch (status) {
        case DeviceConnectionStatusDisconnected:
            baseColor = [UIColor grayColor];
            statusText = [L s:@"未接続" en:@"Disconnected"];
            break;
        case DeviceConnectionStatusConnecting:
            baseColor = [UIColor orangeColor];
            statusText = [L s:@"接続中..." en:@"Connecting..."];
            break;
        case DeviceConnectionStatusConnected:
            baseColor = [UIColor systemGreenColor];
            statusText = [L s:@"接続済み" en:@"Connected"];
            break;
        case DeviceConnectionStatusError:
            baseColor = [UIColor systemRedColor];
            statusText = [L s:@"エラー" en:@"Error"];
            break;
    }

    self.statusIndicator.backgroundColor = baseColor;
    self.statusLabel.text = statusText;
    if (msg.length > 0) {
        self.infoLabel.text = msg;
    } else {
        NSString *ip = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
        NSString *port = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdevicePort"] ?: @"62078";
        self.infoLabel.text = [NSString stringWithFormat:@"Target: %@:%@", ip, port];
    }

    [self applyGlowAnimation:baseColor];
}

- (void)applyGlowAnimation:(UIColor *)color {
    [self.statusIndicator.layer removeAnimationForKey:@"glow"];

    self.statusIndicator.layer.shadowColor = color.CGColor;
    self.statusIndicator.layer.shadowOffset = CGSizeZero;
    self.statusIndicator.layer.shadowOpacity = 0.8;
    self.statusIndicator.layer.shadowRadius = 15;

    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    anim.fromValue = @(5);
    anim.toValue = @(25);
    anim.duration = 1.0;
    anim.repeatCount = HUGE_VALF;
    anim.autoreverses = YES;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.statusIndicator.layer addAnimation:anim forKey:@"glow"];
}

- (void)selectPairingFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"plist"], UTTypeData]];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) {
        [url startAccessingSecurityScopedResource];
        self.selectedPairingPath = url.path;
        [[NSUserDefaults standardUserDefaults] setObject:self.selectedPairingPath forKey:@"LastPairingPath"];
        [self.pairingFileButton setTitle:url.lastPathComponent forState:UIControlStateNormal];
        [url stopAccessingSecurityScopedResource];
    }
}

- (void)connectTapped {
    [self performConnection];
}

- (void)autoConnectIfPossible {
    self.selectedPairingPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastPairingPath"];
    if (self.selectedPairingPath) {
        [self.pairingFileButton setTitle:[self.selectedPairingPath lastPathComponent] forState:UIControlStateNormal];
        [self performConnection];
    }
}

- (void)performConnection {
    if (!self.selectedPairingPath) {
        [self updateStatus:DeviceConnectionStatusError message:[L s:@"ペアリングファイルを選択してください" en:@"Please select a pairing file"]];
        return;
    }

    [self updateStatus:DeviceConnectionStatusConnecting message:@""];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *ip = [[NSUserDefaults standardUserDefaults] stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
        int port = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"IdevicePort"];
        if (port == 0) port = 62078;

        struct IdevicePairingFile *pairing = NULL;
        struct IdeviceFfiError *err = idevice_pairing_file_read([self.selectedPairingPath UTF8String], &pairing);
        if (err) {
            NSString *errMsg = [NSString stringWithFormat:@"%s", err->message];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateStatus:DeviceConnectionStatusError message:[NSString stringWithFormat:@"Pairing Load Error: %@", errMsg]];
            });
            return;
        }

        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_port = htons(port);
        inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr);

        struct IdeviceHandle *device = NULL;
        err = idevice_new_tcp_socket((const idevice_sockaddr *)&sa, sizeof(sa), "IdeviceManager", &device);
        if (err) {
            NSString *errMsg = [NSString stringWithFormat:@"%s", err->message];
            idevice_error_free(err);
            idevice_pairing_file_free(pairing);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateStatus:DeviceConnectionStatusError message:[NSString stringWithFormat:@"Connection Error: %@", errMsg]];
            });
            return;
        }

        err = idevice_start_session(device, pairing, false);
        if (err) {
            NSString *errMsg = [NSString stringWithFormat:@"%s", err->message];
            idevice_error_free(err);
            idevice_free(device);
            idevice_pairing_file_free(pairing);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateStatus:DeviceConnectionStatusError message:[NSString stringWithFormat:@"Session Error: %@", errMsg]];
            });
            return;
        }

        // Success!
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateStatus:DeviceConnectionStatusConnected message:@""];
            idevice_free(device);
            idevice_pairing_file_free(pairing);
        });
    });
}

@end
