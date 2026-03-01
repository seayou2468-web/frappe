#import "CustomMenuView.h"
#import "FileBrowserViewController.h"
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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface FileBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIDocumentPickerDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<FileItem *> *items;
@property (strong, nonatomic) PathBarView *pathBar;
@property (strong, nonatomic) BottomMenuView *bottomMenu;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) NSTimer *searchTimer;
@property (strong, nonatomic) UISegmentedControl *searchScope;
@property (strong, nonatomic) NSLayoutConstraint *searchBarTopConstraint;
@property (assign, nonatomic) BOOL isSearchRevealed;
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
    __weak typeof(self) weakSelf = self;

    // Path Bar
    self.pathBar = [[PathBarView alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];
    [self.pathBar updatePath:self.currentPath];
    self.pathBar.onPathChanged = ^(NSString *newPath) { [weakSelf navigateToPath:newPath]; };
    self.navigationItem.titleView = self.pathBar;

    // Left Bar Button (Go Up)
    if (![self.currentPath isEqualToString:@"/"]) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(goUp)];
    }

    // Right Bar Buttons
    UIBarButtonItem *searchBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleSearch)];
    UIBarButtonItem *selectBtn = [[UIBarButtonItem alloc] initWithTitle:@"選択" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectionMode)];
    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];
    self.navigationItem.rightBarButtonItems = @[moreBtn, selectBtn, searchBtn];

    // Table View
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    // Bottom Menu
    self.bottomMenu = [[BottomMenuView alloc] init];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomMenu.onAction = ^(BottomMenuAction action) { [weakSelf handleMenuAction:action]; };
    [self.view addSubview:self.bottomMenu];

    // Search UI (Initially Hidden)
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"ファイルを検索...";
    self.searchBar.alpha = 0;
    self.searchBar.userInteractionEnabled = YES;
    [self.view addSubview:self.searchBar];

    self.searchScope = [[UISegmentedControl alloc] initWithItems:@[@"現在のフォルダ", @"全体検索"]];
    self.searchScope.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchScope.selectedSegmentIndex = 0;
    self.searchScope.alpha = 0;
    self.searchScope.userInteractionEnabled = YES;
    [self.view addSubview:self.searchScope];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    BOOL alwaysSearch = [[NSUserDefaults standardUserDefaults] boolForKey:@"AlwaysShowSearch"];
    self.searchBarTopConstraint = [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:alwaysSearch ? 0 : -100];
    self.searchBar.alpha = alwaysSearch ? 1.0 : 0;
    self.searchScope.alpha = alwaysSearch ? 1.0 : 0;
    if (alwaysSearch) self.tableView.contentInset = UIEdgeInsetsMake(100, 0, 0, 0);
    self.searchBarTopConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],

        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomMenu.heightAnchor constraintEqualToConstant:80],

        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.searchBar.heightAnchor constraintEqualToConstant:50],

        [self.searchScope.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:5],
        [self.searchScope.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.searchScope.heightAnchor constraintEqualToConstant:32],
    ]];

    [self.view bringSubviewToFront:self.searchBar];
    [self.view bringSubviewToFront:self.searchScope];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:lp];
}

- (void)reloadData {
    self.items = [[FileManagerCore sharedManager] contentsOfDirectoryAtPath:self.currentPath];
    [self.tableView reloadData];
    [self.pathBar updatePath:self.currentPath];
}

- (void)goUp {
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0) parent = @"/";
    [self navigateToPath:parent];
}

- (void)toggleSearch {
    if (self.isSearchRevealed) {
        self.isSearchRevealed = NO;
        [UIView animateWithDuration:0.3 animations:^{
            self.searchBarTopConstraint.constant = -100;
            self.searchBar.alpha = 0;
            self.searchScope.alpha = 0;
            self.tableView.contentInset = UIEdgeInsetsZero;
        }];
        [self.searchBar resignFirstResponder];
    } else {
        self.isSearchRevealed = YES;
        [UIView animateWithDuration:0.3 animations:^{
            self.searchBarTopConstraint.constant = 0;
            self.searchBar.alpha = 1.0;
            self.searchScope.alpha = 1.0;
            self.tableView.contentInset = UIEdgeInsetsMake(100, 0, 0, 0);
        }];
        [self.searchBar becomeFirstResponder];
    }
}

- (void)navigateToPath:(NSString *)path {
    if (!path) return;
    FileBrowserViewController *vc = [[FileBrowserViewController alloc] initWithPath:path];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self.searchTimer invalidate];
    if (searchText.length == 0) { [self reloadData]; return; }

    __weak typeof(self) weakSelf = self;
    self.searchTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *searchPath = (strongSelf.searchScope.selectedSegmentIndex == 1) ? @"/" : strongSelf.currentPath;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray *results = [[FileManagerCore sharedManager] searchFilesWithQuery:searchText inPath:searchPath recursive:YES];
            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.items = results;
                [strongSelf.tableView reloadData];
            });
        });
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"LiquidGlassFileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        LiquidGlassView *liquidBg = [[LiquidGlassView alloc] initWithFrame:CGRectMake(10, 5, self.view.bounds.size.width-20, 60) cornerRadius:15];
        liquidBg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        cell.backgroundView = [[UIView alloc] init];
        [cell.backgroundView addSubview:liquidBg];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    FileItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.name;
    if (item.isDirectory) {
        cell.imageView.image = [UIImage systemImageNamed:item.isLocked ? @"lock.fill" : @"folder.fill"];
        cell.imageView.tintColor = [UIColor whiteColor];
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];
        cell.imageView.tintColor = [UIColor whiteColor];
    }
    cell.detailTextLabel.text = item.isSymbolicLink ? [NSString stringWithFormat:@" Alias ➜ %@", item.linkTarget] : nil;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 70; }

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FileItem *item = self.items[indexPath.row];

    NSString *effectivePath = item.isSymbolicLink ? item.linkTarget : item.fullPath;
    if (!effectivePath) return;

    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:effectivePath isDirectory:&isDir] && isDir) {
        [self navigateToPath:effectivePath];
    } else {
        [self openFile:item];
    }
}

- (void)openFile:(FileItem *)item {
    NSString *targetPath = item.isSymbolicLink ? item.linkTarget : item.fullPath;
    if (!targetPath) return;

    NSString *ext = [targetPath pathExtension].lowercaseString;
    UIViewController *vc = nil;
    if ([ext isEqualToString:@"plist"]) vc = [[PlistEditorViewController alloc] initWithPath:targetPath];
    else if ([@[@"txt", @"xml", @"json", @"h", @"m", @"c", @"cpp"] containsObject:ext]) vc = [[TextEditorViewController alloc] initWithPath:targetPath];
    else if ([@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:ext]) vc = [[ImageViewerViewController alloc] initWithPath:targetPath];
    else if ([@[@"mp4", @"mov", @"mp3", @"wav"] containsObject:ext]) vc = [[MediaPlayerViewController alloc] initWithPath:targetPath];
    else if ([ext isEqualToString:@"pdf"]) vc = [[PDFViewerViewController alloc] initWithPath:targetPath];
    else if ([ZipManager formatForPath:targetPath] != ArchiveFormatUnknown) { [self showArchiveOptionsForItem:item]; return; }
    else vc = [[HexEditorViewController alloc] initWithPath:targetPath];
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Archiving

- (void)showArchiveOptionsForItem:(FileItem *)item {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:item.name];
    [menu addAction:[CustomMenuAction actionWithTitle:@"展開" systemImage:@"arrow.up.bin" style:CustomMenuActionStyleDefault handler:^{
        [self promptForArchivePasswordForPath:item.fullPath isExtracting:YES];
    }]];
    [menu showInView:self.view];
}

- (void)promptForArchivePasswordForPath:(NSString *)path isExtracting:(BOOL)isExtracting {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"パスワード" message:@"パスワードを入力してください" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.secureTextEntry = YES; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self processArchiveAtPath:path password:alert.textFields[0].text isExtracting:isExtracting];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)processArchiveAtPath:(NSString *)path password:(NSString *)password isExtracting:(BOOL)isExtracting {
    if (isExtracting) {
        NSString *dest = [path stringByDeletingPathExtension];
        [[NSFileManager defaultManager] createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
        [ZipManager extractArchiveAtPath:path toDestination:dest password:password error:nil];
        [self reloadData];
    }
}

#pragma mark - Context Menu

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:[lp locationInView:self.tableView]];
    if (indexPath) [self showContextMenuForItem:self.items[indexPath.row]];
}

- (void)showContextMenuForItem:(FileItem *)item {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:item.name];
    [menu addAction:[CustomMenuAction actionWithTitle:@"お気に入りに追加" systemImage:@"star" style:CustomMenuActionStyleDefault handler:^{
        [[BookmarksManager sharedManager] addBookmark:item.fullPath];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"詳細情報" systemImage:@"info.circle" style:CustomMenuActionStyleDefault handler:^{
        [self showInfoForItem:item];
    }]];
    if (item.isSymbolicLink) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"リンクを編集" systemImage:@"link" style:CustomMenuActionStyleDefault handler:^{
            [self showEditLinkForItem:item];
        }]];
    }
    [menu addAction:[CustomMenuAction actionWithTitle:@"圧縮" systemImage:@"archivebox" style:CustomMenuActionStyleDefault handler:^{
        [self showCompressionOptionsForItem:item];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:item.fullPath]] applicationActivities:nil];
        [self presentViewController:avc animated:YES completion:nil];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{
        [[FileManagerCore sharedManager] removeItemAtPath:item.fullPath error:nil];
        [self reloadData];
    }]];
    [menu showInView:self.view];
}

- (void)showInfoForItem:(FileItem *)item {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"Path: %@\nSize: %@ bytes\nModified: %@\nType: %@", item.fullPath, item.attributes[NSFileSize], item.attributes[NSFileModificationDate], item.attributes[NSFileType]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ファイル情報" message:info preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showEditLinkForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"リンクを編集" message:@"Enter new destination path" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = item.linkTarget; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[FileManagerCore sharedManager] createSymbolicLinkAtPath:item.fullPath withDestinationPath:alert.textFields[0].text error:nil];
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCompressionOptionsForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Compress As..." message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"ZIP" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [ZipManager compressFiles:@[item.fullPath] toPath:[item.fullPath stringByAppendingPathExtension:@"zip"] format:ArchiveFormatZip password:nil error:nil];
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Menu Actions

- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionTabs: {
            MainContainerViewController *container = (MainContainerViewController *)self.view.window.rootViewController;
            if ([container isKindOfClass:[MainContainerViewController class]]) [container showTabSwitcher];
            break;
        }
        case BottomMenuActionFavorites: [self showFavoritesMenu]; break;
        case BottomMenuActionOthers: [self showOthersMenu]; break;
        case BottomMenuActionSettings: [self showSettings]; break;
    }
}

- (void)showFavoritesMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"お気に入り"];
    for (NSString *path in [BookmarksManager sharedManager].bookmarks) {
        [menu addAction:[CustomMenuAction actionWithTitle:[path lastPathComponent] systemImage:@"folder" style:CustomMenuActionStyleDefault handler:^{
            [self navigateToPath:path];
        }]];
    }
    [menu showInView:self.view];
}

- (void)showOthersMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"その他"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ファイルから読み込む" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{
        UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem]];
        dp.delegate = self;
        [self presentViewController:dp animated:YES completion:nil];
    }]];
    [menu showInView:self.view];
}

- (void)showSettings {
    SettingsViewController *vc = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        [[FileManagerCore sharedManager] copyItemAtPath:url.path toPath:[self.currentPath stringByAppendingPathComponent:url.lastPathComponent] error:nil];
    }
    [self reloadData];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat y = scrollView.contentOffset.y;
    if (y < -80) {
        if (!self.isSearchRevealed) {
            self.isSearchRevealed = YES;
            [UIView animateWithDuration:0.3 animations:^{
                self.searchBarTopConstraint.constant = 0;
                self.searchBar.alpha = 1.0;
                self.searchScope.alpha = 1.0;
                self.tableView.contentInset = UIEdgeInsetsMake(100, 0, 0, 0);
            }];
        }
    } else if (y > 50 && self.isSearchRevealed) {
        self.isSearchRevealed = NO;
        [UIView animateWithDuration:0.3 animations:^{
            self.searchBarTopConstraint.constant = -100;
            self.searchBar.alpha = 0;
            self.searchScope.alpha = 0;
            self.tableView.contentInset = UIEdgeInsetsZero;
        }];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Selection Mode

- (void)toggleSelectionMode {
    [self.tableView setEditing:!self.tableView.isEditing animated:YES];
    UIBarButtonItem *selectBtn = self.navigationItem.rightBarButtonItems[1];
    selectBtn.title = self.tableView.isEditing ? @"キャンセル" : @"選択";

    if (self.tableView.isEditing) {
        self.tableView.allowsMultipleSelectionDuringEditing = YES;
        // Update 'More' button to 'Actions' button
        UIBarButtonItem *actionBtn = [[UIBarButtonItem alloc] initWithTitle:@"操作" style:UIBarButtonItemStyleDone target:self action:@selector(showSelectionActions)];
        NSMutableArray *items = [self.navigationItem.rightBarButtonItems mutableCopy];
        items[0] = actionBtn;
        self.navigationItem.rightBarButtonItems = items;
    } else {
        // Restore 'More' button
        UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];
        NSMutableArray *items = [self.navigationItem.rightBarButtonItems mutableCopy];
        items[0] = moreBtn;
        self.navigationItem.rightBarButtonItems = items;
    }
}

- (void)showSelectionActions {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"選択したアイテムを操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{
        [self performBulkAction:0];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"圧縮 (ZIP)" systemImage:@"archivebox" style:CustomMenuActionStyleDefault handler:^{
        [self performBulkAction:1];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{
        [self performBulkAction:2];
    }]];
    [menu showInView:self.view];
}

- (void)performBulkAction:(NSInteger)actionType {
    NSArray *indexPaths = [self.tableView indexPathsForSelectedRows];
    if (indexPaths.count == 0) return;

    NSMutableArray *selectedPaths = [NSMutableArray array];
    for (NSIndexPath *ip in indexPaths) {
        [selectedPaths addObject:self.items[ip.row].fullPath];
    }

    if (actionType == 0) { // Delete
        for (NSString *path in selectedPaths) {
            [[FileManagerCore sharedManager] removeItemAtPath:path error:nil];
        }
    } else if (actionType == 1) { // ZIP
        NSString *zipName = [NSString stringWithFormat:@"archive_%ld.zip", (long)[[NSDate date] timeIntervalSince1970]];
        NSString *dest = [self.currentPath stringByAppendingPathComponent:zipName];
        [ZipManager compressFiles:selectedPaths toPath:dest format:ArchiveFormatZip password:nil error:nil];
    } else if (actionType == 2) { // Share
        NSMutableArray *urls = [NSMutableArray array];
        for (NSString *path in selectedPaths) [urls addObject:[NSURL fileURLWithPath:path]];
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
        [self presentViewController:avc animated:YES completion:nil];
    }

    [self toggleSelectionMode];
    [self reloadData];
}

- (void)showMoreMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規フォルダ" systemImage:@"folder.badge.plus" style:CustomMenuActionStyleDefault handler:^{
        [self promptForNewItem:YES];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規ファイル" systemImage:@"doc.badge.plus" style:CustomMenuActionStyleDefault handler:^{
        [self promptForNewItem:NO];
    }]];
    [menu showInView:self.view];
}

- (void)promptForNewItem:(BOOL)isDir {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isDir ? @"新規フォルダ" : @"新規ファイル" message:@"名前を入力してください" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"作成" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text;
        if (name.length == 0) return;
        NSString *path = [self.currentPath stringByAppendingPathComponent:name];
        if (isDir) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        } else {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
