#import "IdeviceViewController.h"
#import "IdeviceManager.h"
#import "ThemeEngine.h"
#import "FileBrowserViewController.h"
#import "LogViewerViewController.h"
#import "IdeviceAppListViewController.h"
#import "IdeviceRsdViewController.h"
#import "IdeviceSyslogViewController.h"
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
@property (nonatomic, assign) IdeviceConnectionStatus lastReportedStatus;

- (void)captureSysdiagnose;
- (void)showProcessList;
- (void)editIP;
- (void)editPort;
- (void)openSystemFilePicker;
- (void)openInternalFileBrowser;
- (void)closeTapped;
- (void)statusChanged;
- (void)setupUI;



@end

@implementation IdeviceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"iDevice Tools";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.lastReportedStatus = IdeviceStatusDisconnected;
    UIBarButtonItem *backToFmBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder"] style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
    self.navigationItem.leftBarButtonItem = backToFmBtn;
    [self setupUI];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusChanged) name:@"IdeviceStatusChanged" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    IdeviceManager *mgr = [IdeviceManager sharedManager];
    if (mgr.status == IdeviceStatusDisconnected && mgr.pairingFilePath.length > 0) {
        [mgr connect];
    }
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
        NSString *statusStr = @"切断済み";
        switch (mgr.status) {
            case IdeviceStatusConnecting: statusStr = @"接続中..."; statusColor = [UIColor orangeColor]; break;
            case IdeviceStatusConnected: statusStr = @"接続完了"; statusColor = [UIColor greenColor]; break;
            case IdeviceStatusError: statusStr = [NSString stringWithFormat:@"エラー: %@", mgr.lastError]; statusColor = [UIColor redColor]; break;
            default: break;
        }
        if (mgr.status == IdeviceStatusError && self.lastReportedStatus != IdeviceStatusError) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"接続失敗" message:mgr.lastError preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        self.lastReportedStatus = mgr.status;
        [UIView animateWithDuration:0.3 animations:^{
            self.statusIndicator.layer.borderColor = statusColor.CGColor;
            self.deviceImageView.tintColor = statusColor;
            self.statusIndicator.layer.shadowColor = statusColor.CGColor;
            self.statusIndicator.layer.shadowOffset = CGSizeZero;
            self.statusIndicator.layer.shadowRadius = (mgr.status == IdeviceStatusConnected) ? 10.0 : 0.0;
            self.statusIndicator.layer.shadowOpacity = (mgr.status == IdeviceStatusConnected) ? 0.8 : 0.0;
        }];
        self.statusLabel.text = [NSString stringWithFormat:@"%@\nIP: %@:%d", statusStr, mgr.ipAddress, (int)mgr.port];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 6; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2;
    if (section == 1) return 2;
    if (section == 2) return 2;
    if (section == 3) return 1;
    if (section == 4) return 1;
    if (section == 5) return 4;
    return 0;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"接続設定";
    if (section == 1) return @"ペアリング";
    if (section == 2) return @"機能";
    if (section == 3) return @"アクション";
    if (section == 4) return @"システム";
    if (section == 5) return @"RSDサービス利用";
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
        if (indexPath.row == 0) { cell.textLabel.text = @"IPアドレス"; cell.detailTextLabel.text = mgr.ipAddress; }
        else { cell.textLabel.text = @"ポート"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)mgr.port]; }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) { cell.textLabel.text = @"ファイルピッカー (iOS Files)"; cell.detailTextLabel.text = mgr.pairingFilePath ? [mgr.pairingFilePath lastPathComponent] : @"未選択"; }
        else { cell.textLabel.text = @"内部ブラウザで選択"; cell.detailTextLabel.text = nil; }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"インストール済みアプリ";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [UIColor whiteColor] : [UIColor grayColor];
        } else {
            cell.textLabel.text = @"RSD サービスブラウザ";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [UIColor whiteColor] : [UIColor grayColor];
        }
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 3) {
        cell.textLabel.text = (mgr.status == IdeviceStatusConnected) ? @"切断" : @"接続";
        cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [UIColor redColor] : [ThemeEngine liquidColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (indexPath.section == 4) {
        cell.textLabel.text = @"システムログを表示"; cell.textLabel.textColor = [UIColor whiteColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Sysdiagnoseを取得";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"実行中プロセスを表示";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"スクリーンショットを撮る";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else {
            cell.textLabel.text = @"ライブシステムログを表示";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IdeviceManager *mgr = [IdeviceManager sharedManager];
    if (indexPath.section == 0) { if (indexPath.row == 0) [self editIP]; else [self editPort]; }
    else if (indexPath.section == 1) { if (indexPath.row == 0) [self openSystemFilePicker]; else [self openInternalFileBrowser]; }
    else if (indexPath.section == 2) {
        if (mgr.status == IdeviceStatusConnected) {
            if (indexPath.row == 0) [self.navigationController pushViewController:[[IdeviceAppListViewController alloc] init] animated:YES];
            else [self.navigationController pushViewController:[[IdeviceRsdViewController alloc] init] animated:YES];
        }
    }
    else if (indexPath.section == 3) { if (mgr.status == IdeviceStatusConnected) [mgr disconnect]; else [mgr connect]; }
    else if (indexPath.section == 4) [self.navigationController pushViewController:[[LogViewerViewController alloc] init] animated:YES];
    else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) { if (indexPath.row == 0) [self captureSysdiagnose]; else if (indexPath.row == 1) [self showProcessList]; else if (indexPath.row == 2) [self takeScreenshot]; else [self.navigationController pushViewController:[[IdeviceSyslogViewController alloc] init] animated:YES]; } }
}

- (void)editIP {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"IPアドレス編集" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [IdeviceManager sharedManager].ipAddress; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [IdeviceManager sharedManager].ipAddress = alert.textFields.firstObject.text; [self statusChanged]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)editPort {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ポート編集" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [NSString stringWithFormat:@"%d", (int)[IdeviceManager sharedManager].port]; tf.keyboardType = UIKeyboardTypeNumberPad; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [IdeviceManager sharedManager].port = (uint16_t)[alert.textFields.firstObject.text integerValue]; [self statusChanged]; }]];
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

- (void)captureSysdiagnose {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[IdeviceManager sharedManager] captureSysdiagnoseWithCompletion:^(NSString *path, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
            self.view.userInteractionEnabled = YES;

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"完了" message:[NSString stringWithFormat:@"Sysdiagnoseを保存しました:\n%@", [path lastPathComponent]] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

- (void)showProcessList {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[IdeviceManager sharedManager] getProcessListWithCompletion:^(NSArray *processes, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
            self.view.userInteractionEnabled = YES;

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                NSMutableString *msg = [NSMutableString string];
                NSInteger countNum = MIN(processes.count, 20);
                for (NSInteger i = 0; i < countNum; i++) {
                    NSDictionary *p = processes[i];
                    [msg appendFormat:@"PID: %@ - %@\n", p[@"pid"], [p[@"path"] lastPathComponent] ?: @"Unknown"];
                }
                if (processes.count > 20) [msg appendString:@"... 他多数"];

                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"実行中プロセス" message:msg preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}


- (void)takeScreenshot {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[IdeviceManager sharedManager] takeScreenshotWithCompletion:^(UIImage *image, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
            self.view.userInteractionEnabled = YES;

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                UIViewController *vc = [[UIViewController alloc] init];
                vc.title = @"Screenshot";
                UIImageView *iv = [[UIImageView alloc] initWithFrame:vc.view.bounds];
                iv.contentMode = UIViewContentModeScaleAspectFit;
                iv.image = image;
                iv.backgroundColor = [UIColor blackColor];
                iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [vc.view addSubview:iv];
                UIBarButtonItem *shareBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareImage:)];
                objc_set_associated_object(shareBtn, "img", image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                vc.navigationItem.rightBarButtonItem = shareBtn;
                [self.navigationController pushViewController:vc animated:YES];
            }
        });
    }];
}

- (void)shareImage:(UIBarButtonItem *)sender {
    UIImage *img = objc_get_associated_object(sender, "img");
    if (!img) return;
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[img] applicationActivities:nil];
    [self presentViewController:avc animated:YES completion:nil];
}

@end
