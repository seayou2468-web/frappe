#import "AfcBrowserViewController.h"
#import "ThemeEngine.h"
#import "DdiManager.h"
#import "BottomMenuView.h"
#import "CustomMenuView.h"
#import "PlistEditorViewController.h"
#import "TextEditorViewController.h"
#import "ImageViewerViewController.h"
#import "MediaPlayerViewController.h"
#import "PDFViewerViewController.h"
#import "SQLiteViewerViewController.h"
#import "ExcelViewerViewController.h"
#import "HexEditorViewController.h"
#import <CoreLocation/CoreLocation.h>

@interface AfcBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct AfcClientHandle *afc;
@property (nonatomic, assign) BOOL isAfc2;
@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *pathLabel;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) BottomMenuView *bottomMenu;
@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *customSwipeGesture;

@property (nonatomic, strong) NSArray<NSString *> *clipboardPaths;
@property (nonatomic, assign) BOOL isMoveOperation;
@property (nonatomic, strong) NSMutableDictionary *openFiles;
@end

@implementation AfcBrowserViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider isAfc2:(BOOL)isAfc2 {
    self = [super init];
    if (self) {
        _provider = provider; _isAfc2 = isAfc2;
        _currentPath = @"/"; _items = [[NSMutableArray alloc] init];
        _openFiles = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"System Root" : @"Media Staging";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self checkAndUploadModifiedFiles];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updatePopGestureState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
}

- (void)updatePopGestureState {
    BOOL isAtRoot = [self.currentPath isEqualToString:@"/"];
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = isAtRoot;
    }
}

- (void)setupUI {
    self.headerView = [[UIView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerView];
    [ThemeEngine applyGlassStyleToView:self.headerView cornerRadius:0];

    self.pathLabel = [[UILabel alloc] init];
    self.pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pathLabel.textColor = [UIColor systemBlueColor];
    self.pathLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBlack];
    self.pathLabel.text = @"/";
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    [self.headerView addSubview:self.pathLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self; self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];

    self.bottomMenu = [[BottomMenuView alloc] initWithMode:BottomMenuModeFiles];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.bottomMenu.onAction = ^(BottomMenuAction action) { [weakSelf handleMenuAction:action]; };
    [self.view addSubview:self.bottomMenu];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UIBarButtonItem *selectBtn = [[UIBarButtonItem alloc] initWithTitle:@"選択" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectionMode)];
    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showTopActionsMenu)];
    self.navigationItem.rightBarButtonItems = @[moreBtn, selectBtn];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerView.heightAnchor constraintEqualToConstant:40],

        [self.pathLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor constant:15],
        [self.pathLabel.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-15],
        [self.pathLabel.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomMenu.heightAnchor constraintEqualToConstant:90],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    self.customSwipeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeBack:)];
    self.customSwipeGesture.edges = UIRectEdgeLeft; self.customSwipeGesture.delegate = self;
    [self.view addGestureRecognizer:self.customSwipeGesture];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:lp];
}

- (void)showLoading:(BOOL)loading {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (loading) [self.spinner startAnimating];
        else [self.spinner stopAnimating];
    });
}

- (void)connectAfc {
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        struct AfcClientHandle *client = NULL;
        struct IdeviceFfiError *err = self.isAfc2 ? afc2_client_connect(self.provider, &client) : afc_client_connect(self.provider, &client);
        if (!err) {
            self.afc = client;
            [self loadPath:@"/"];
        } else {
            idevice_error_free(err);
            [self showLoading:NO];
        }
    });
}

- (void)loadPath:(NSString *)path {
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char **entries = NULL; size_t count = 0;
        struct IdeviceFfiError *err = afc_list_directory(self.afc, [path UTF8String], &entries, &count);
        if (!err) {
            NSMutableArray *newList = [NSMutableArray array];
            for (size_t i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:entries[i]];
                if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;

                NSString *full = [path isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [path stringByAppendingPathComponent:name];
                struct AfcFileInfo info = {0};
                struct IdeviceFfiError *e2 = afc_get_file_info(self.afc, [full UTF8String], &info);

                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && (strstr(info.st_ifmt, "DIR") || strstr(info.st_ifmt, "directory"))) isDir = YES;
                    afc_file_info_free(&info);
                } else { idevice_error_free(e2); if (![name containsString:@"."]) isDir = YES; }
                [newList addObject:@{@"name": name, @"isDir": @(isDir)}];
            }
            [newList sortUsingComparator:^NSComparisonResult(id o1, id o2) {
                if ([o1[@"isDir"] boolValue] != [o2[@"isDir"] boolValue]) return [o1[@"isDir"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
                return [o1[@"name"] localizedCaseInsensitiveCompare:o2[@"name"]];
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.items removeAllObjects]; [self.items addObjectsFromArray:newList];
                self.currentPath = path; self.pathLabel.text = path;
                [self.tableView reloadData]; [self.spinner stopAnimating];
                [self updatePopGestureState];
            });
        } else {
            idevice_error_free(err);
            [self showLoading:NO];
        }
    });
}

#pragma mark - Gestures

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.customSwipeGesture) {
        return ![self.currentPath isEqualToString:@"/"];
    }
    return YES;
}

- (void)handleSwipeBack:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        [self goBack];
    }
}

- (void)goBack {
    if ([self.currentPath isEqualToString:@"/"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:@"."]) parent = @"/";
    [self loadPath:parent];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [lp locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (ip) [self showContextMenuForItem:self.items[ip.row]];
}

#pragma mark - Menu Actions

- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionOthers: [self showOthersMenu]; break;
        case BottomMenuActionSettings: [self.navigationController popToRootViewControllerAnimated:YES]; break;
        default: break;
    }
}

- (void)showTopActionsMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"操作"];
    if (self.clipboardPaths.count > 0) {
        NSString *title = self.isMoveOperation ? @"ここに移動" : @"ここに貼り付け (Renamed)";
        [menu addAction:[CustomMenuAction actionWithTitle:title systemImage:@"doc.on.clipboard" style:CustomMenuActionStyleDefault handler:^{ [self performPaste]; }]];
    }
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規フォルダ" systemImage:@"folder.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self promptForNewItem:YES]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規ファイル" systemImage:@"doc.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self promptForNewItem:NO]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"インポート" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{ [self selectLocalFile]; }]];
    [menu showInView:self.view];
}

- (void)showOthersMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"その他"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規PDF" systemImage:@"doc.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self createSpecialFile:@"pdf"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規スプレッドシート" systemImage:@"tablecells.fill.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self createSpecialFile:@"csv"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"インポート" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{ [self selectLocalFile]; }]];
    [menu showInView:self.view];
}

- (void)createSpecialFile:(NSString *)ext {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新規作成" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = [NSString stringWithFormat:@"new_file.%@", ext]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"作成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text; if (name.length == 0) return;
        NSString *full = [self.currentPath stringByAppendingPathComponent:name];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            struct AfcFileHandle *h = NULL;
            afc_file_open(self.afc, [full UTF8String], AfcWr, &h);
            if (h) { afc_file_write(h, (const uint8_t *)"\n", 1); afc_file_close(h); }
            [self loadPath:self.currentPath];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForNewItem:(BOOL)isDir {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isDir ? @"新規フォルダ" : @"新規ファイル" message:@"名前を入力" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"作成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text; if (name.length == 0) return;
        NSString *full = [self.currentPath stringByAppendingPathComponent:name];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            if (isDir) afc_make_directory(self.afc, [full UTF8String]);
            else { struct AfcFileHandle *h = NULL; afc_file_open(self.afc, [full UTF8String], AfcWr, &h); if (h) afc_file_close(h); }
            [self loadPath:self.currentPath];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectLocalFile {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    p.delegate = self; [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:url];
        NSString *dest = [self.currentPath stringByAppendingPathComponent:url.lastPathComponent];
        struct AfcFileHandle *h = NULL;
        if (!afc_file_open(self.afc, [dest UTF8String], AfcWr, &h) && h) {
            afc_file_write(h, data.bytes, data.length); afc_file_close(h);
        }
        [self loadPath:self.currentPath];
    });
}

- (void)showContextMenuForItem:(NSDictionary *)item {
    NSString *name = item[@"name"];
    NSString *full = [self.currentPath isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [self.currentPath stringByAppendingPathComponent:name];
    CustomMenuView *menu = [CustomMenuView menuWithTitle:name];
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{
        [self showLoading:YES];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            afc_remove_path(self.afc, [full UTF8String]);
            [self loadPath:self.currentPath];
        });
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"名前変更" systemImage:@"pencil" style:CustomMenuActionStyleDefault handler:^{ [self promptRename:full]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"コピー" systemImage:@"doc.on.doc" style:CustomMenuActionStyleDefault handler:^{ self.clipboardPaths = @[full]; self.isMoveOperation = NO; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"移動" systemImage:@"arrow.right.doc.on.clipboard" style:CustomMenuActionStyleDefault handler:^{ self.clipboardPaths = @[full]; self.isMoveOperation = YES; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{ [self shareFile:name]; }]];
    [menu showInView:self.view];
}

- (void)promptRename:(NSString *)oldPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"リネーム" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = oldPath.lastPathComponent; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *nn = alert.textFields[0].text; if (nn.length == 0) return;
        NSString *np = [[oldPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:nn];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{ afc_rename_path(self.afc, [oldPath UTF8String], [np UTF8String]); [self loadPath:self.currentPath]; });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performPaste {
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (NSString *src in self.clipboardPaths) {
            NSString *dest = [self.currentPath stringByAppendingPathComponent:src.lastPathComponent];
            afc_rename_path(self.afc, [src UTF8String], [dest UTF8String]);
        }
        if (self.isMoveOperation) self.clipboardPaths = nil;
        [self loadPath:self.currentPath];
    });
}

- (void)shareFile:(NSString *)name {
    NSString *full = [self.currentPath stringByAppendingPathComponent:name];
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        struct AfcFileHandle *h = NULL;
        afc_file_open(self.afc, [full UTF8String], AfcRdOnly, &h);
        if (h) {
            uint8_t *data = NULL; size_t len = 0;
            afc_file_read_entire(h, &data, &len); afc_file_close(h);
            if (data) {
                NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
                [[NSData dataWithBytes:data length:len] writeToFile:temp atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showLoading:NO];
                    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:temp]] applicationActivities:nil];
                    [self presentViewController:avc animated:YES completion:nil];
                });
                return;
            }
        }
        [self showLoading:NO];
    });
}

- (void)checkAndUploadModifiedFiles {
    for (NSString *name in [self.openFiles allKeys]) {
        NSDictionary *f = self.openFiles[name];
        NSString *lp = f[@"local"], *rp = f[@"remote"]; NSDate *od = f[@"date"];
        NSDate *md = [[[NSFileManager defaultManager] attributesOfItemAtPath:lp error:nil] fileModificationDate];
        if ([md compare:od] == NSOrderedDescending) {
            [self showLoading:YES];
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                NSData *d = [NSData dataWithContentsOfFile:lp];
                struct AfcFileHandle *h = NULL;
                if (!afc_file_open(self.afc, [rp UTF8String], AfcWr, &h) && h) { afc_file_write(h, d.bytes, d.length); afc_file_close(h); }
                self.openFiles[name] = @{@"local": lp, @"remote": rp, @"date": [NSDate date]};
                [self showLoading:NO];
            });
        }
    }
}

- (void)toggleSelectionMode {
    BOOL isEditing = !self.tableView.isEditing; [self.tableView setEditing:isEditing animated:YES];
    UIBarButtonItem *selectBtn = self.navigationItem.rightBarButtonItems[1]; selectBtn.title = isEditing ? @"キャンセル" : @"選択";
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    NSDictionary *item = self.items[indexPath.row];
    cell.backgroundColor = [UIColor clearColor]; cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    cell.textLabel.text = item[@"name"];
    BOOL isDir = [item[@"isDir"] boolValue];
    cell.imageView.image = [UIImage systemImageNamed:isDir ? @"folder.fill" : @"doc"];
    cell.imageView.tintColor = isDir ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    cell.selectedBackgroundView = [[UIView alloc] init]; cell.selectedBackgroundView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView.isEditing) return;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    NSString *name = item[@"name"];
    if ([item[@"isDir"] boolValue]) {
        NSString *newPath = [self.currentPath isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [self.currentPath stringByAppendingPathComponent:name];
        [self loadPath:newPath];
    } else {
        [self openFile:name];
    }
}

- (void)openFile:(NSString *)name {
    NSString *full = [self.currentPath isEqualToString:@"/"] ? [@"/" stringByAppendingString:name] : [self.currentPath stringByAppendingPathComponent:name];
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        struct AfcFileHandle *h = NULL;
        if (!afc_file_open(self.afc, [full UTF8String], AfcRdOnly, &h) && h) {
            uint8_t *data = NULL; size_t len = 0;
            afc_file_read_entire(h, &data, &len); afc_file_close(h);
            if (data) {
                NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
                [[NSData dataWithBytes:data length:len] writeToFile:temp atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showLoading:NO];
                    self.openFiles[name] = @{@"local": temp, @"remote": full, @"date": [NSDate date]};
                    [self showEditorForPath:temp];
                });
                return;
            }
        }
        [self showLoading:NO];
    });
}

- (void)showEditorForPath:(NSString *)path {
    NSString *ext = [path pathExtension].lowercaseString;
    UIViewController *vc = nil;
    if ([ext isEqualToString:@"plist"]) vc = [[PlistEditorViewController alloc] initWithPath:path];
    else if ([@[@"txt", @"xml", @"json", @"h", @"m", @"c", @"cpp", @"js", @"css"] containsObject:ext]) vc = [[TextEditorViewController alloc] initWithPath:path];
    else if ([@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:ext]) vc = [[ImageViewerViewController alloc] initWithPath:path];
    else if ([@[@"mp4", @"mov", @"mp3", @"wav"] containsObject:ext]) vc = [[MediaPlayerViewController alloc] initWithPath:path];
    else if ([ext isEqualToString:@"pdf"]) vc = [[PDFViewerViewController alloc] initWithPath:path];
    else if ([@[@"db", @"sqlite"] containsObject:ext]) vc = [[SQLiteViewerViewController alloc] initWithPath:path];
    else if ([@[@"csv", @"tsv", @"xlsx"] containsObject:ext]) vc = [[ExcelViewerViewController alloc] initWithPath:path];
    else vc = [[HexEditorViewController alloc] initWithPath:path];
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

- (void)dealloc { if (self.afc) afc_client_free(self.afc); }

@end
