// HouseArrestBrowserViewController.m
// App container/documents browser using House Arrest service

#import "HouseArrestBrowserViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import "PlistEditorViewController.h"
#import "TextEditorViewController.h"
#import "ImageViewerViewController.h"
#import "MediaPlayerViewController.h"
#import "PDFViewerViewController.h"
#import "SQLiteViewerViewController.h"
#import "ExcelViewerViewController.h"
#import "HexEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface HAAppEntry : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, assign) BOOL isRemovable;
@end
@implementation HAAppEntry @end

@interface HouseArrestBrowserViewController ()
    <UITableViewDelegate, UITableViewDataSource,
     UISearchResultsUpdating, UIDocumentPickerDelegate>

@property (nonatomic, assign) struct IdeviceProviderHandle  *provider;
@property (nonatomic, assign) struct HouseArrestClientHandle *haClient;
@property (nonatomic, assign) struct AfcClientHandle        *afcClient;

// App selection
@property (nonatomic, strong) NSMutableArray<HAAppEntry *>  *apps;
@property (nonatomic, strong) NSMutableArray<HAAppEntry *>  *filteredApps;
@property (nonatomic, strong) HAAppEntry                    *selectedApp;

// File browser
@property (nonatomic, strong) NSString                      *currentPath;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *fileItems;
@property (nonatomic, assign) BOOL                           isBrowsingFiles;
@property (nonatomic, assign) BOOL                           vendDocuments; // YES=Documents, NO=Container

// UI
@property (nonatomic, strong) UITableView                   *tableView;
@property (nonatomic, strong) UISearchController            *searchController;
@property (nonatomic, strong) UIActivityIndicatorView       *spinner;
@property (nonatomic, strong) UILabel                       *pathLabel;
@property (nonatomic, strong) UISegmentedControl            *modeControl;

// Clipboard
@property (nonatomic, strong) NSArray<NSString *>           *clipboardPaths;
@property (nonatomic, assign) BOOL                           isMoveOp;
@property (nonatomic, strong) NSMutableArray<NSString *>    *pathHistory;
@end

@implementation HouseArrestBrowserViewController

- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider {
    self = [super init];
    if (self) {
        _provider     = provider;
        _apps         = [NSMutableArray array];
        _filteredApps = [NSMutableArray array];
        _fileItems    = [NSMutableArray array];
        _pathHistory  = [NSMutableArray array];
        _currentPath  = @"/";
        _vendDocuments = YES;
    }
    return self;
}

- (void)dealloc {
    if (_afcClient) { afc_client_free(_afcClient);           _afcClient = NULL; }
    if (_haClient)  { house_arrest_client_free(_haClient);   _haClient  = NULL; }
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"House Arrest";
    self.view.backgroundColor = [ThemeEngine bg];
    [self setupNavBar];
    [self setupHeader];
    [self setupTableView];
    [self setupSearch];
    [self loadAppList];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isBrowsingFiles) [self syncModifiedFiles];
}

#pragma mark - Setup

- (void)setupNavBar {
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus"]
                style:UIBarButtonItemStylePlain
               target:self action:@selector(showAddMenu)];
    UIBarButtonItem *uploadBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.up.doc"]
                style:UIBarButtonItemStylePlain target:self action:@selector(uploadFile)];
    self.navigationItem.rightBarButtonItems = @[addBtn, uploadBtn];
    addBtn.enabled = NO; uploadBtn.enabled = NO;
}

- (void)setupHeader {
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.04];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"📦 Container", @"📄 Documents"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = 1;
    self.modeControl.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.05];
    self.modeControl.selectedSegmentTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}
                                    forState:UIControlStateNormal];
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.modeControl];

    self.pathLabel = [[UILabel alloc] init];
    self.pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pathLabel.text = @"Select an application below";
    self.pathLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    self.pathLabel.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    [header addSubview:self.pathLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.modeControl.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.pathLabel.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:6],
        [self.pathLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.pathLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [header.bottomAnchor constraintEqualToAnchor:self.pathLabel.bottomAnchor constant:10],
    ]];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate   = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorColor  = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    [self.view addSubview:header];
    [self.view addSubview:self.tableView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)setupTableView {
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [ThemeEngine accent];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}

- (void)setupSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.tintColor = [UIColor systemBlueColor];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

#pragma mark - App List

- (void)loadAppList {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct InstallationProxyClientHandle *ip = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(self.provider, &ip);

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.filteredApps = [self.apps mutableCopy];
            [self.tableView reloadData];
        });
    });
}

#pragma mark - House Arrest

- (void)vendAndConnect:(HAAppEntry *)app {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        if (self.afcClient) { afc_client_free(self.afcClient);           self.afcClient = NULL; }
        if (self.haClient)  { house_arrest_client_free(self.haClient);   self.haClient  = NULL; }

        struct HouseArrestClientHandle *ha = NULL;
        struct IdeviceFfiError *err = house_arrest_client_connect(self.provider, &ha);
        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                [self alert:[NSString stringWithFormat:@"Connect failed: %@", m]];
            });
            return;
        }
        self.haClient = ha;

        struct AfcClientHandle *afc = NULL;
        const char *bid = [app.bundleId UTF8String];
        if (self.vendDocuments) {
            err = house_arrest_vend_documents(ha, bid, &afc);
        } else {
            err = house_arrest_vend_container(ha, bid, &afc);
        }

        if (err) {
            NSString *m = err->message ? [NSString stringWithUTF8String:err->message] : @"?";
            idevice_error_free(err);
            house_arrest_client_free(ha); self.haClient = NULL;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                [self alert:[NSString stringWithFormat:@"Vend failed: %@", m]];
            });
            return;
        }
        self.afcClient = afc;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            NSString *mode = self.vendDocuments ? @"Documents" : @"Container";
            self.pathLabel.text = [NSString stringWithFormat:@"[%@] %@", mode, app.displayName];
            [self loadDir:@"/"];
        });
    });
}

- (void)modeChanged:(UISegmentedControl *)seg {
    self.vendDocuments = (seg.selectedSegmentIndex == 1);
    if (self.isBrowsingFiles && self.selectedApp) {
        [self vendAndConnect:self.selectedApp];
    }
}

#pragma mark - Directory

- (void)loadDir:(NSString *)path {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSMutableArray *items = [NSMutableArray array];
        char **names = NULL; uintptr_t cnt = 0;
        struct IdeviceFfiError *err = afc_list_directory(self.afcClient, [path UTF8String], &names, &cnt);
        if (!err && names) {
            for (uintptr_t i = 0; i < cnt; i++) {
                if (!names[i]) continue;
                NSString *name = [NSString stringWithUTF8String:names[i]];
                if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;
                NSString *fp = [path isEqualToString:@"/"]
                    ? [@"/" stringByAppendingString:name]
                    : [path stringByAppendingFormat:@"/%@", name];
                struct AfcFileInfo info; memset(&info, 0, sizeof(info));
                BOOL isDir = NO; uint64_t sz = 0;
                struct IdeviceFfiError *ie = afc_get_file_info(self.afcClient, [fp UTF8String], &info);
                if (!ie) {
                    isDir = (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0);
                    sz = (uint64_t)info.size;
                    if (info.st_nlink)       free(info.st_nlink);
                    if (info.st_ifmt)        free(info.st_ifmt);
                    if (info.st_link_target) free(info.st_link_target);
                } else { idevice_error_free(ie); }
                [items addObject:@{@"name":name, @"path":fp, @"isDir":@(isDir), @"size":@(sz)}];
            }
            idevice_outer_slice_free((void *)names, cnt);
            [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                BOOL ad = [a[@"isDir"] boolValue], bd = [b[@"isDir"] boolValue];
                if (ad != bd) return ad ? NSOrderedAscending : NSOrderedDescending;
                return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
            }];
        }
        if (err) idevice_error_free(err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.currentPath = path;
            self.fileItems   = items;
            NSString *mode = self.vendDocuments ? @"📄" : @"📦";
            self.pathLabel.text = [NSString stringWithFormat:@"%@ %@:%@", mode,
                self.selectedApp.displayName, path];
            [self.tableView reloadData];
        });
    });
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.isBrowsingFiles ? self.fileItems.count : self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (!self.isBrowsingFiles) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"A"] ?:
            [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"A"];
        c.backgroundColor = [UIColor clearColor];
        c.textLabel.textColor = [UIColor whiteColor];
        c.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        HAAppEntry *app = self.filteredApps[ip.row];
        c.textLabel.text       = app.displayName;
        c.detailTextLabel.text = [NSString stringWithFormat:@"%@ v%@", app.bundleId, app.version];
        c.imageView.image      = [UIImage systemImageNamed:@"app.fill"];
        c.imageView.tintColor  = [UIColor systemBlueColor];
        return c;
    }

    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"F"] ?:
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"F"];
    c.backgroundColor = [UIColor clearColor];
    c.textLabel.textColor = [UIColor whiteColor];
    c.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    NSDictionary *item = self.fileItems[ip.row];
    BOOL isDir = [item[@"isDir"] boolValue];
    c.textLabel.text       = item[@"name"];
    c.accessoryType        = isDir ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    c.imageView.tintColor  = isDir ? [UIColor systemYellowColor] : [UIColor systemGrayColor];
    if (isDir) {
        c.imageView.image     = [UIImage systemImageNamed:@"folder.fill"];
        c.detailTextLabel.text = @"";
    } else {
        c.imageView.image     = [self iconFor:item[@"name"]];
        c.detailTextLabel.text = [self sizeStr:[item[@"size"] unsignedLongLongValue]];
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (!self.isBrowsingFiles) {
        self.selectedApp       = self.filteredApps[ip.row];
        self.isBrowsingFiles   = YES;
        self.vendDocuments     = (self.modeControl.selectedSegmentIndex == 1);
        self.navigationItem.rightBarButtonItems.firstObject.enabled = YES;
        self.navigationItem.rightBarButtonItems.lastObject.enabled  = YES;
        UIBarButtonItem *backBtn = [[UIBarButtonItem alloc] initWithTitle:@"Apps"
            style:UIBarButtonItemStylePlain target:self action:@selector(backToApps)];
        self.navigationItem.leftBarButtonItem = backBtn;
        [self vendAndConnect:self.selectedApp];
        return;
    }
    NSDictionary *item = self.fileItems[ip.row];
    if ([item[@"isDir"] boolValue]) {
        [self.pathHistory addObject:self.currentPath];
        [self loadDir:item[@"path"]];
    } else {
        [self openFile:item];
    }
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv
contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)pt {
    if (!self.isBrowsingFiles) return nil;
    NSDictionary *item = self.fileItems[ip.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray *_) {
            NSMutableArray *acts = [NSMutableArray array];
            if (![item[@"isDir"] boolValue]) {
                [acts addObject:[UIAction actionWithTitle:@"Download"
                    image:[UIImage systemImageNamed:@"arrow.down.circle"] identifier:nil
                    handler:^(UIAction *__) { [self downloadFile:item]; }]];
            }
            [acts addObject:[UIAction actionWithTitle:@"Rename"
                image:[UIImage systemImageNamed:@"pencil"] identifier:nil
                handler:^(UIAction *__) { [self promptRename:item]; }]];
            [acts addObject:[UIAction actionWithTitle:@"Copy"
                image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil
                handler:^(UIAction *__) { self.clipboardPaths=@[item[@"path"]]; self.isMoveOp=NO; }]];
            UIAction *del = [UIAction actionWithTitle:@"Delete"
                image:[UIImage systemImageNamed:@"trash"] identifier:nil
                handler:^(UIAction *__) { [self confirmDelete:item]; }];
            del.attributes = UIMenuElementAttributesDestructive;
            [acts addObject:del];
            return [UIMenu menuWithTitle:item[@"name"] children:acts];
        }];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return self.isBrowsingFiles; }
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)s forRowAtIndexPath:(NSIndexPath *)ip {
    if (s == UITableViewCellEditingStyleDelete) [self confirmDelete:self.fileItems[ip.row]];
}

#pragma mark - File Operations

- (void)showAddMenu {
    if (!self.isBrowsingFiles) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Add" message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"📁 New Folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self promptName:@"New Folder" defaultValue:@"" completion:^(NSString *name) {
            NSString *p = [self.currentPath stringByAppendingFormat:@"/%@", name];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                struct IdeviceFfiError *e = afc_make_directory(self.afcClient, [p UTF8String]);
                if (e) idevice_error_free(e);
                dispatch_async(dispatch_get_main_queue(), ^{ [self loadDir:self.currentPath]; });
            });
        }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"📄 New Text File" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self promptName:@"New File" defaultValue:@"file.txt" completion:^(NSString *name) {
            NSString *p = [self.currentPath stringByAppendingFormat:@"/%@", name];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                struct AfcFileHandle *fh = NULL;
                struct IdeviceFfiError *e = afc_file_open(self.afcClient, [p UTF8String], AfcWrOnly, &fh);
                if (!e && fh) afc_file_close(fh);
                if (e) idevice_error_free(e);
                dispatch_async(dispatch_get_main_queue(), ^{ [self loadDir:self.currentPath]; });
            });
        }];
    }]];
    if (self.clipboardPaths.count) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📋 Paste (%@)",
            self.isMoveOp?@"Move":@"Copy"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [self performPaste];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)uploadFile {
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    p.delegate = self; p.allowsMultipleSelection = YES;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        BOOL acc = [url startAccessingSecurityScopedResource];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (acc) [url stopAccessingSecurityScopedResource];
        if (!data) continue;
        NSString *dst = [self.currentPath stringByAppendingFormat:@"/%@", url.lastPathComponent];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            struct AfcFileHandle *fh = NULL;
            struct IdeviceFfiError *e = afc_file_open(self.afcClient,[dst UTF8String],AfcWrOnly,&fh);
            if (!e && fh) {
                uint64_t w=0;
                afc_file_write(fh, data.bytes, data.length);
                afc_file_close(fh);
            }
            if (e) idevice_error_free(e);
            dispatch_async(dispatch_get_main_queue(),^{[self loadDir:self.currentPath];});
        });
    }
}

- (void)downloadFile:(NSDictionary *)item {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        uint8_t *data=NULL; uintptr_t len=0;
        struct AfcFileHandle *_rfh=NULL;
        struct IdeviceFfiError *e=afc_file_open(self.afcClient,[item[@"path"] UTF8String],AfcRdOnly,&_rfh);
        if(!e&&_rfh) e=afc_file_read_entire(_rfh,&data,&len);
        if(_rfh) afc_file_close(_rfh);
        if (e||!data) { if(e) idevice_error_free(e);
            dispatch_async(dispatch_get_main_queue(),^{[self.spinner stopAnimating];}); return; }
        NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:item[@"name"]];
        [[NSData dataWithBytes:data length:len] writeToFile:tmp atomically:YES];
        afc_file_read_data_free(data,len);
        dispatch_async(dispatch_get_main_queue(),^{
            [self.spinner stopAnimating];
            UIActivityViewController *avc=[[UIActivityViewController alloc]
                initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
            avc.popoverPresentationController.sourceView=self.view;
            [self presentViewController:avc animated:YES completion:nil];
        });
    });
}

- (void)promptRename:(NSDictionary *)item {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Rename"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){tf.text=item[@"name"];}];
    [a addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        NSString *n=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if(!n.length||[n isEqualToString:item[@"name"]]) return;
        NSString *dst=[[item[@"path"] stringByDeletingLastPathComponent] stringByAppendingPathComponent:n];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),^{
            struct IdeviceFfiError *e=afc_rename_path(self.afcClient,[item[@"path"] UTF8String],[dst UTF8String]);
            if(e) idevice_error_free(e);
            dispatch_async(dispatch_get_main_queue(),^{[self loadDir:self.currentPath];});
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmDelete:(NSDictionary *)item {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Delete"
        message:[NSString stringWithFormat:@"Delete \"%@\"?",item[@"name"]]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){
        BOOL isDir=[item[@"isDir"] boolValue];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),^{
            struct IdeviceFfiError *e = isDir
                ? afc_remove_path_and_contents(self.afcClient,[item[@"path"] UTF8String])
                : afc_remove_path(self.afcClient,[item[@"path"] UTF8String]);
            if(e) idevice_error_free(e);
            dispatch_async(dispatch_get_main_queue(),^{[self loadDir:self.currentPath];});
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)performPaste {
    for (NSString *src in self.clipboardPaths) {
        NSString *dst=[self.currentPath stringByAppendingFormat:@"/%@",src.lastPathComponent];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),^{
            uint8_t *data=NULL; uintptr_t len=0;
            struct AfcFileHandle *_pfh = NULL;
            struct IdeviceFfiError *e = afc_file_open(self.afcClient,[src UTF8String],AfcRdOnly,&_pfh);
            if (!e && _pfh) e = afc_file_read_entire(_pfh, &data, &len);
            if (_pfh) afc_file_close(_pfh);
            if(e||!data){if(e)idevice_error_free(e);return;}
            struct AfcFileHandle *fh=NULL;
            e=afc_file_open(self.afcClient,[dst UTF8String],AfcWrOnly,&fh);
            if(!e&&fh){uint64_t w=0;afc_file_write(fh, data, len);afc_file_close(fh);}
            afc_file_read_data_free(data,len);if(e)idevice_error_free(e);
            if(self.isMoveOp) afc_remove_path(self.afcClient,[src UTF8String]);
            dispatch_async(dispatch_get_main_queue(),^{[self loadDir:self.currentPath];});
        });
    }
    if(self.isMoveOp) self.clipboardPaths=nil;
}

#pragma mark - File Open

- (void)openFile:(NSDictionary *)item {
    [self.spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),^{
        uint8_t *data=NULL; uintptr_t len=0;
        struct AfcFileHandle *_rfh = NULL;
        struct IdeviceFfiError *e = afc_file_open(self.afcClient,[item[@"path"] UTF8String],AfcRdOnly,&_rfh);
        if (!e && _rfh) e = afc_file_read_entire(_rfh, &data, &len);
        if (_rfh) afc_file_close(_rfh);
        if(e||!data){if(e)idevice_error_free(e);
            dispatch_async(dispatch_get_main_queue(),^{[self.spinner stopAnimating];}); return;}
        NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:item[@"name"]];
        [[NSData dataWithBytes:data length:len] writeToFile:tmp atomically:YES];
        afc_file_read_data_free(data,len);
        dispatch_async(dispatch_get_main_queue(),^{
            [self.spinner stopAnimating];
            [self openLocal:tmp];
        });
    });
}

- (void)openLocal:(NSString *)path {
    NSString *ext=[path.pathExtension lowercaseString];
    UIViewController *vc=nil;
    if([ext isEqualToString:@"plist"]) vc=[[PlistEditorViewController alloc] initWithPath:path];
    else if([@[@"txt",@"xml",@"json",@"h",@"m",@"c",@"js",@"css",@"md",@"log"] containsObject:ext])
        vc=[[TextEditorViewController alloc] initWithPath:path];
    else if([@[@"png",@"jpg",@"jpeg",@"gif",@"heic",@"webp"] containsObject:ext])
        vc=[[ImageViewerViewController alloc] initWithPath:path];
    else if([@[@"mp4",@"mov",@"mp3",@"wav",@"m4a"] containsObject:ext])
        vc=[[MediaPlayerViewController alloc] initWithPath:path];
    else if([ext isEqualToString:@"pdf"]) vc=[[PDFViewerViewController alloc] initWithPath:path];
    else if([@[@"db",@"sqlite",@"sqlite3"] containsObject:ext])
        vc=[[SQLiteViewerViewController alloc] initWithPath:path];
    else if([@[@"csv",@"tsv",@"xlsx"] containsObject:ext])
        vc=[[ExcelViewerViewController alloc] initWithPath:path];
    else vc=[[HexEditorViewController alloc] initWithPath:path];
    if(vc) [self.navigationController pushViewController:vc animated:YES];
}

- (void)syncModifiedFiles {
    // Re-upload any temp files that may have been edited
    if(!self.afcClient) return;
    NSString *tmp=NSTemporaryDirectory();
    for(NSDictionary *item in self.fileItems){
        NSString *local=[tmp stringByAppendingPathComponent:item[@"name"]];
        if(![[NSFileManager defaultManager] fileExistsAtPath:local]) continue;
        NSData *data=[NSData dataWithContentsOfFile:local];
        if(!data) continue;
        NSString *remote=item[@"path"];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),^{
            struct AfcFileHandle *fh=NULL;
            struct IdeviceFfiError *e=afc_file_open(self.afcClient,[remote UTF8String],AfcWrOnly,&fh);
            if(!e&&fh){uint64_t w=0;afc_file_write(fh, data.bytes, data.length);afc_file_close(fh);}
            if(e) idevice_error_free(e);
        });
    }
}

- (void)backToApps {
    if(self.afcClient){afc_client_free(self.afcClient);self.afcClient=NULL;}
    if(self.haClient){house_arrest_client_free(self.haClient);self.haClient=NULL;}
    self.isBrowsingFiles=NO;
    self.selectedApp=nil;
    self.title=@"House Arrest";
    self.navigationItem.leftBarButtonItem=nil;
    self.navigationItem.rightBarButtonItems.firstObject.enabled=NO;
    self.navigationItem.rightBarButtonItems.lastObject.enabled=NO;
    self.pathLabel.text=@"Select an application below";
    [self.tableView reloadData];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    NSString *q=[sc.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if(q.length==0||self.isBrowsingFiles){self.filteredApps=[self.apps mutableCopy];}
    else{self.filteredApps=[[self.apps filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"displayName CONTAINS[cd] %@ OR bundleId CONTAINS[cd] %@",q,q]] mutableCopy];}
    [self.tableView reloadData];
}

#pragma mark - Helpers

- (void)promptName:(NSString *)title defaultValue:(NSString *)def completion:(void(^)(NSString *))cb {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){tf.text=def;}];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        NSString *n=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if(n.length>0&&cb) cb(n);
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (UIImage *)iconFor:(NSString *)name {
    NSString *e=[name.pathExtension lowercaseString];
    if([@[@"png",@"jpg",@"jpeg",@"gif",@"heic",@"webp"] containsObject:e]) return [UIImage systemImageNamed:@"photo"];
    if([@[@"mp4",@"mov"] containsObject:e]) return [UIImage systemImageNamed:@"film"];
    if([@[@"mp3",@"wav",@"m4a",@"aac"] containsObject:e]) return [UIImage systemImageNamed:@"music.note"];
    if([e isEqualToString:@"pdf"]) return [UIImage systemImageNamed:@"doc.richtext"];
    if([e isEqualToString:@"plist"]) return [UIImage systemImageNamed:@"list.bullet.rectangle"];
    if([@[@"db",@"sqlite",@"sqlite3"] containsObject:e]) return [UIImage systemImageNamed:@"cylinder.split.1x2"];
    if([@[@"csv",@"xlsx",@"tsv"] containsObject:e]) return [UIImage systemImageNamed:@"tablecells"];
    return [UIImage systemImageNamed:@"doc"];
}

- (NSString *)sizeStr:(uint64_t)b {
    if(b<1024) return [NSString stringWithFormat:@"%llu B",b];
    if(b<1048576) return [NSString stringWithFormat:@"%.1f KB",b/1024.0];
    if(b<1073741824) return [NSString stringWithFormat:@"%.1f MB",b/1048576.0];
    return [NSString stringWithFormat:@"%.2f GB",b/1073741824.0];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Error" message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
