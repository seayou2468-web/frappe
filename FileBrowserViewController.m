#import "CustomMenuView.h"
#import "FileBrowserViewController.h"
#import "SQLiteViewerViewController.h"
#import "ExcelViewerViewController.h"
#import "SettingsViewController.h"
#import "PathBarView.h"
#import "BottomMenuView.h"
#import "FileManagerCore.h"
#import "ThemeEngine.h"
#import "TabManager.h"
#import "MainContainerViewController.h"
#import "BookmarksManager.h"
#import "ZipManager.h"
#import "PlistEditorViewController.h"
#import "TextEditorViewController.h"
#import "ImageViewerViewController.h"
#import "MediaPlayerViewController.h"
#import "PDFViewerViewController.h"
#import "HexEditorViewController.h"
#import "FileInfoViewController.h"
#import "LogViewerViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface FileBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIDocumentPickerDelegate, UIGestureRecognizerDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<FileItem *> *items;
@property (strong, nonatomic) PathBarView *pathBar;
@property (strong, nonatomic) BottomMenuView *bottomMenu;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) NSTimer *searchTimer;
@property (strong, nonatomic) UISegmentedControl *searchScope;
@property (strong, nonatomic) NSLayoutConstraint *searchBarTopConstraint;
@property (assign, nonatomic) BOOL isSearchRevealed;
- (void)createNewPDF;
- (void)createNewSpreadsheet;
@end

@implementation FileBrowserViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _currentPath = path ?: @"/"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBar.translucent = YES;
    [self setupUI];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:@"SettingsChanged" object:nil];
    [self reloadData];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    self.pathBar = [[PathBarView alloc] initWithFrame:CGRectZero];
    self.pathBar.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.pathBar.onPathSelected = ^(NSString *path) { [weakSelf navigateToPath:path]; };
    [self.view addSubview:self.pathBar];

    self.bottomMenu = [[BottomMenuView alloc] initWithMode:BottomMenuModeFiles];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomMenu.onAction = ^(BottomMenuAction action) { [weakSelf handleMenuAction:action]; };
    [self.view addSubview:self.bottomMenu];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"検索...";
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.hidden = YES;
    [self.view addSubview:self.searchBar];

    self.searchScope = [[UISegmentedControl alloc] initWithItems:@[@"名前", @"内容"]];
    self.searchScope.selectedSegmentIndex = 0;
    self.searchScope.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchScope.hidden = YES;
    [self.view addSubview:self.searchScope];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.searchBarTopConstraint = [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:-100];

    [NSLayoutConstraint activateConstraints:@[
        [self.pathBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.pathBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pathBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pathBar.heightAnchor constraintEqualToConstant:44],

        self.searchBarTopConstraint,
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.searchBar.heightAnchor constraintEqualToConstant:44],

        [self.searchScope.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.searchScope.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.searchScope.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],

        [self.tableView.topAnchor constraintEqualToAnchor:self.pathBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],

        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomMenu.heightAnchor constraintEqualToConstant:90]
    ]];

    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];
    UIBarButtonItem *selectBtn = [[UIBarButtonItem alloc] initWithTitle:@"選択" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectionMode)];
    UIBarButtonItem *searchBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(toggleSearch)];
    self.navigationItem.rightBarButtonItems = @[moreBtn, selectBtn, searchBtn];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:lp];
}

- (void)toggleSearch {
    self.isSearchRevealed = !self.isSearchRevealed;
    self.searchBar.hidden = NO;
    self.searchScope.hidden = NO;
    [UIView animateWithDuration:0.3 animations:^{
        self.searchBarTopConstraint.constant = self.isSearchRevealed ? 44 : -100;
        self.tableView.contentInset = UIEdgeInsetsMake(self.isSearchRevealed ? 88 : 0, 0, 0, 0);
        [self.view layoutIfNeeded];
    }];
    if (!self.isSearchRevealed) { [self.searchBar resignFirstResponder]; [self reloadData]; }
}

- (void)reloadData {
    self.items = [[FileManagerCore sharedManager] contentsOfDirectoryAtPath:self.currentPath error:nil];
    [self.pathBar setPath:self.currentPath];
    [self.tableView reloadData];
}

- (void)navigateToPath:(NSString *)path {
    self.currentPath = path;
    [self reloadData];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FileCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FileCell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        UIView *selectedBg = [[UIView alloc] init];
        UIView *selectedInner = [[UIView alloc] initWithFrame:CGRectMake(10, 5, self.view.bounds.size.width-20, 60)];
        selectedInner.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
        selectedInner.layer.cornerRadius = 15;
        selectedInner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [selectedBg addSubview:selectedInner];
        cell.selectedBackgroundView = selectedBg;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    FileItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.name;
    if (item.isDirectory) {
        cell.imageView.image = [UIImage systemImageNamed:item.isLocked ? @"lock.fill" : @"folder.fill"];
        cell.imageView.tintColor = [ThemeEngine liquidColor];
    } else {
        NSString *ext = item.name.pathExtension;
        cell.imageView.image = [UIImage systemImageNamed:[self iconNameForExtension:ext]];
        cell.imageView.tintColor = [self iconColorForExtension:ext];
    }
    cell.detailTextLabel.text = item.isSymbolicLink ? [NSString stringWithFormat:@" Alias ➜ %@", item.linkTarget] : nil;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 70; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.tableView.isEditing) return;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FileItem *item = self.items[indexPath.row];
    NSString *effectivePath = [item.fullPath stringByResolvingSymlinksInPath];
    if (!effectivePath) return;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:effectivePath error:nil];
    if ([[attrs fileType] isEqualToString:NSFileTypeDirectory]) { [self navigateToPath:effectivePath]; } else { [self openFile:item]; }
}

- (void)openFile:(FileItem *)item {
    NSString *targetPath = [item.fullPath stringByResolvingSymlinksInPath];
    if (!targetPath) return;
    NSString *ext = [targetPath pathExtension].lowercaseString;
    UIViewController *vc = nil;
    if ([ext isEqualToString:@"plist"]) vc = [[PlistEditorViewController alloc] initWithPath:targetPath];
    else if ([@[@"txt", @"xml", @"json", @"h", @"m", @"c", @"cpp"] containsObject:ext]) vc = [[TextEditorViewController alloc] initWithPath:targetPath];
    else if ([@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:ext]) vc = [[ImageViewerViewController alloc] initWithPath:targetPath];
    else if ([@[@"mp4", @"mov", @"mp3", @"wav"] containsObject:ext]) vc = [[MediaPlayerViewController alloc] initWithPath:targetPath];
    else if ([ext isEqualToString:@"pdf"]) vc = [[PDFViewerViewController alloc] initWithPath:targetPath];
    else if ([@[@"db", @"sqlite"] containsObject:ext]) vc = [[SQLiteViewerViewController alloc] initWithPath:targetPath];
    else if ([ext isEqualToString:@"sql"]) vc = [[TextEditorViewController alloc] initWithPath:targetPath];
    else if ([@[@"csv", @"tsv", @"xlsx"] containsObject:ext]) vc = [[ExcelViewerViewController alloc] initWithPath:targetPath];
    else if ([ZipManager formatForPath:targetPath] != ArchiveFormatUnknown) { [self showArchiveOptionsForItem:item]; return; }
    else vc = [[HexEditorViewController alloc] initWithPath:targetPath];
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionWeb: { MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController; if ([container isKindOfClass:[MainContainerViewController class]]) { [container handleMenuAction:action]; } break; }
        case BottomMenuActionTabs: { MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController; if ([container isKindOfClass:[MainContainerViewController class]]) [container showTabSwitcher]; break; }
        case BottomMenuActionFavorites: [self showFavoritesMenu]; break;
        case BottomMenuActionOthers: [self showOthersMenu]; break;
        case BottomMenuActionSettings: [self showSettings]; break;
        default: break;
    }
}

- (void)showFavoritesMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"お気に入り"];
    for (NSString *path in [BookmarksManager sharedManager].bookmarks) { [menu addAction:[CustomMenuAction actionWithTitle:[path lastPathComponent] systemImage:@"folder" style:CustomMenuActionStyleDefault handler:^{ [self navigateToPath:path]; }]]; }
    [menu showInView:self.view];
}

- (void)showOthersMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"その他"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規PDF作成" systemImage:@"doc.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self createNewPDF]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規スプレッドシート作成" systemImage:@"tablecells.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self createNewSpreadsheet]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ファイルから読み込む" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{ [self selectFile]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"システムログ" systemImage:@"terminal" style:CustomMenuActionStyleDefault handler:^{ [self showLogViewer]; }]];
    [menu showInView:self.view];
}

- (void)createNewPDF {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新規PDF名" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = @"new_document.pdf"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"作成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text;
        if (![name hasSuffix:@".pdf"]) name = [name stringByAppendingPathExtension:@"pdf"];
        NSString *newPath = [self.currentPath stringByAppendingPathComponent:name];
        PDFViewerViewController *vc = [[PDFViewerViewController alloc] initWithPath:newPath];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createNewSpreadsheet {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新規ファイル名" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = @"new_sheet.csv"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"作成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text;
        if (![name hasSuffix:@".csv"] && ![name hasSuffix:@".tsv"]) name = [name stringByAppendingPathExtension:@"csv"];
        NSString *newPath = [self.currentPath stringByAppendingPathComponent:name];
        [@"\n" writeToFile:newPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        ExcelViewerViewController *vc = [[ExcelViewerViewController alloc] initWithPath:newPath];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showLogViewer {
    LogViewerViewController *vc = [[LogViewerViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)selectFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)showSettings { SettingsViewController *vc = [[SettingsViewController alloc] init]; [self.navigationController pushViewController:vc animated:YES]; }

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL access = [url startAccessingSecurityScopedResource];
    [[FileManagerCore sharedManager] moveItemAtURL:url toDirectory:self.currentPath uniqueName:nil error:nil];
    if (access) [url stopAccessingSecurityScopedResource];
    [self reloadData];
}

#pragma mark - Selection Mode

- (void)toggleSelectionMode {
    BOOL isEditing = !self.tableView.isEditing; [self.tableView setEditing:isEditing animated:YES];
    UIBarButtonItem *selectBtn = self.navigationItem.rightBarButtonItems[1]; selectBtn.title = isEditing ? @"キャンセル" : @"選択";
    self.navigationItem.leftBarButtonItem.enabled = !isEditing;
    UIBarButtonItem *searchBtn = self.navigationItem.rightBarButtonItems[2]; searchBtn.enabled = !isEditing;
    if (isEditing) { UIBarButtonItem *actionBtn = [[UIBarButtonItem alloc] initWithTitle:@"操作" style:UIBarButtonItemStylePlain target:self action:@selector(showSelectionActions)]; NSMutableArray *items = [self.navigationItem.rightBarButtonItems mutableCopy]; items[0] = actionBtn; self.navigationItem.rightBarButtonItems = items; }
    else { UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)]; NSMutableArray *items = [self.navigationItem.rightBarButtonItems mutableCopy]; items[0] = moreBtn; self.navigationItem.rightBarButtonItems = items; }
}

- (void)showSelectionActions {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [self performBulkAction:0]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"圧縮 (ZIP)" systemImage:@"archivebox" style:CustomMenuActionStyleDefault handler:^{ [self performBulkAction:1]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"コピー" systemImage:@"doc.on.doc" style:CustomMenuActionStyleDefault handler:^{ [self performBulkAction:3]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"移動" systemImage:@"arrow.right.doc.on.clipboard" style:CustomMenuActionStyleDefault handler:^{ [self performBulkAction:4]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{ [self performBulkAction:2]; }]];
    [menu showInView:self.view];
}

- (void)performBulkAction:(NSInteger)actionType {
    NSArray *indexPaths = [self.tableView indexPathsForSelectedRows]; if (indexPaths.count == 0) return;
    NSMutableArray *selectedPaths = [NSMutableArray array]; for (NSIndexPath *ip in indexPaths) { [selectedPaths addObject:self.items[ip.row].fullPath]; }
    if (actionType == 0) {
        BOOL shouldConfirm = [[NSUserDefaults standardUserDefaults] objectForKey:@"ConfirmDeletion"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"ConfirmDeletion"] : YES;
        if (shouldConfirm) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"削除の確認" message:[NSString stringWithFormat:@"%lu 個のアイテムを削除しますか？", (unsigned long)selectedPaths.count] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { for (NSString *path in selectedPaths) { [[FileManagerCore sharedManager] removeItemAtPath:path error:nil]; } [self toggleSelectionMode]; [self reloadData]; }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        } else { for (NSString *path in selectedPaths) { [[FileManagerCore sharedManager] removeItemAtPath:path error:nil]; } }
    } else if (actionType == 1) { NSString *zipName = [NSString stringWithFormat:@"archive_%ld.zip", (long)[[NSDate date] timeIntervalSince1970]]; NSString *dest = [self.currentPath stringByAppendingPathComponent:zipName]; [ZipManager compressFiles:selectedPaths toPath:dest format:ArchiveFormatZip password:nil error:nil]; }
    else if (actionType == 2) { NSMutableArray *urls = [NSMutableArray array]; for (NSString *path in selectedPaths) [urls addObject:[NSURL fileURLWithPath:path]]; UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil]; [self presentViewController:avc animated:YES completion:nil]; }
    else if (actionType == 3) { [FileManagerCore sharedManager].clipboardPaths = selectedPaths; [FileManagerCore sharedManager].isMoveOperation = NO; }
    else if (actionType == 4) { [FileManagerCore sharedManager].clipboardPaths = selectedPaths; [FileManagerCore sharedManager].isMoveOperation = YES; }
    [self toggleSelectionMode]; [self reloadData];
}

- (void)showMoreMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"操作"];
    if ([FileManagerCore sharedManager].clipboardPaths.count > 0) { NSString *title = [FileManagerCore sharedManager].isMoveOperation ? @"ここに移動" : @"ここに貼り付け"; [menu addAction:[CustomMenuAction actionWithTitle:title systemImage:@"doc.on.clipboard.fill" style:CustomMenuActionStyleDefault handler:^{ [self performPaste]; }]]; }
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規フォルダ" systemImage:@"folder.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self promptForNewItem:YES]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規ファイル" systemImage:@"doc.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self promptForNewItem:NO]; }]];
    [menu showInView:self.view];
}

- (void)performPaste {
    FileManagerCore *fmc = [FileManagerCore sharedManager]; for (NSString *src in fmc.clipboardPaths) { NSString *dest = [self.currentPath stringByAppendingPathComponent:[src lastPathComponent]]; if (fmc.isMoveOperation) { [fmc moveItemAtPath:src toPath:dest error:nil]; } else { [fmc copyItemAtPath:src toPath:dest error:nil]; } }
    if (fmc.isMoveOperation) fmc.clipboardPaths = nil; [self reloadData];
}

- (void)promptForNewItem:(BOOL)isDir {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isDir ? @"新規フォルダ" : @"新規ファイル" message:@"名前を入力してください" preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"作成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { NSString *name = alert.textFields[0].text; if (name.length == 0) return; NSString *path = [self.currentPath stringByAppendingPathComponent:name]; if (isDir) { [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]; } else { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]; } [self reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:[lp locationInView:self.tableView]];
    if (indexPath) [self showContextMenuForItem:self.items[indexPath.row]];
}

- (void)showContextMenuForItem:(FileItem *)item {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:item.name];
    [menu addAction:[CustomMenuAction actionWithTitle:@"お気に入りに追加" systemImage:@"star" style:CustomMenuActionStyleDefault handler:^{ [[BookmarksManager sharedManager] addBookmark:item.fullPath]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"詳細情報" systemImage:@"info.circle" style:CustomMenuActionStyleDefault handler:^{ [self showInfoForItem:item]; }]];
    if (item.isSymbolicLink) { [menu addAction:[CustomMenuAction actionWithTitle:@"リンクを編集" systemImage:@"link" style:CustomMenuActionStyleDefault handler:^{ [self showEditLinkForItem:item]; }]]; }
    [menu addAction:[CustomMenuAction actionWithTitle:@"圧縮" systemImage:@"archivebox" style:CustomMenuActionStyleDefault handler:^{ [self showCompressionOptionsForItem:item]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"コピー" systemImage:@"doc.on.doc" style:CustomMenuActionStyleDefault handler:^{ [FileManagerCore sharedManager].clipboardPaths = @[item.fullPath]; [FileManagerCore sharedManager].isMoveOperation = NO; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"移動" systemImage:@"arrow.right.doc.on.clipboard" style:CustomMenuActionStyleDefault handler:^{ [FileManagerCore sharedManager].clipboardPaths = @[item.fullPath]; [FileManagerCore sharedManager].isMoveOperation = YES; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{ UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:item.fullPath]] applicationActivities:nil]; [self presentViewController:avc animated:YES completion:nil]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [self removeItemAtPath:item.fullPath]; }]];
    [menu showInView:self.view];
}

- (void)showInfoForItem:(FileItem *)item { FileInfoViewController *vc = [[FileInfoViewController alloc] initWithItem:item]; [self.navigationController pushViewController:vc animated:YES]; }
- (void)showEditLinkForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"リンクを編集" message:@"Enter new destination path" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = item.linkTarget; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [[FileManagerCore sharedManager] createSymbolicLinkAtPath:item.fullPath withDestinationPath:alert.textFields[0].text error:nil]; [self reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)removeItemAtPath:(NSString *)path {
    BOOL shouldConfirm = [[NSUserDefaults standardUserDefaults] objectForKey:@"ConfirmDeletion"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"ConfirmDeletion"] : YES;
    if (shouldConfirm) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"削除の確認" message:[NSString stringWithFormat:@"@"%@" を削除してもよろしいですか？", [path lastPathComponent]] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [[FileManagerCore sharedManager] removeItemAtPath:path error:nil]; [self reloadData]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else { [[FileManagerCore sharedManager] removeItemAtPath:path error:nil]; [self reloadData]; }
}

- (void)showCompressionOptionsForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Compress As..." message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"ZIP" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [ZipManager compressFiles:@[item.fullPath] toPath:[item.fullPath stringByAppendingPathExtension:@"zip"] format:ArchiveFormatZip password:nil error:nil]; [self reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showArchiveOptionsForItem:(FileItem *)item {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:item.name];
    [menu addAction:[CustomMenuAction actionWithTitle:@"展開" systemImage:@"arrow.up.bin" style:CustomMenuActionStyleDefault handler:^{ [self promptForArchivePasswordForPath:item.fullPath isExtracting:YES]; }]];
    [menu showInView:self.view];
}

- (void)promptForArchivePasswordForPath:(NSString *)path isExtracting:(BOOL)extracting {
    if ([ZipManager isEncrypted:path]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"パスワード入力" message:@"このアーカイブは暗号化されています" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.secureTextEntry = YES; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self performArchiveAction:path password:alert.textFields[0].text isExtracting:extracting]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else { [self performArchiveAction:path password:nil isExtracting:extracting]; }
}

- (void)performArchiveAction:(NSString *)path password:(NSString *)pw isExtracting:(BOOL)extract {
    NSError *error;
    if (extract) { [ZipManager extractArchive:path toPath:[path stringByDeletingPathExtension] password:pw error:&error]; }
    if (error) { UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; }
    [self reloadData];
}

- (NSString *)iconNameForExtension:(NSString *)ext {
    ext = ext.lowercaseString;
    if ([@[@"png", @"jpg", @"jpeg", @"gif", @"bmp", @"heic"] containsObject:ext]) return @"photo";
    if ([@[@"mp4", @"mov", @"avi", @"mkv"] containsObject:ext]) return @"video";
    if ([@[@"mp3", @"wav", @"m4a", @"flac"] containsObject:ext]) return @"music.note";
    if ([@[@"zip", @"rar", @"7z", @"tar", @"gz"] containsObject:ext]) return @"archivebox";
    if ([@[@"plist", @"xml", @"json", @"html", @"js", @"css", @"csv", @"tsv", @"xlsx"] containsObject:ext]) return @"tablecells";
    if ([@[@"c", @"cpp", @"h", @"m", @"mm", @"py", @"sh"] containsObject:ext]) return @"doc.text.fill";
    if ([ext isEqualToString:@"pdf"]) return @"doc.richtext";
    if ([@[@"db", @"sqlite", @"sql"] containsObject:ext]) return @"terminal.fill";
    return @"doc";
}

- (UIColor *)iconColorForExtension:(NSString *)ext {
    ext = ext.lowercaseString;
    if ([@[@"png", @"jpg", @"jpeg", @"gif", @"bmp", @"heic"] containsObject:ext]) return [UIColor systemOrangeColor];
    if ([@[@"mp4", @"mov", @"avi", @"mkv"] containsObject:ext]) return [UIColor systemPurpleColor];
    if ([@[@"mp3", @"wav", @"m4a", @"flac"] containsObject:ext]) return [UIColor systemPinkColor];
    if ([@[@"zip", @"rar", @"7z", @"tar", @"gz"] containsObject:ext]) return [UIColor systemYellowColor];
    if ([ext isEqualToString:@"pdf"]) return [UIColor systemRedColor];
    if ([@[@"db", @"sqlite", @"sql"] containsObject:ext]) return [UIColor systemCyanColor];
    return [UIColor whiteColor];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end