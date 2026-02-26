#import "AppListViewController.h"
#import "ProcessListViewController.h"
#import "SyslogViewController.h"
#import "LocationSimulatorViewController.h"
#import "AfcBrowserViewController.h"
#import "FileBrowserViewController.h"
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
    [self reloadData];
}

- (void)setupUI {

    self.pathBar = [[PathBarView alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];
    [self.pathBar updatePath:self.currentPath];
    __weak typeof(self) weakSelf = self;
    self.pathBar.onPathChanged = ^(NSString *newPath) { [weakSelf navigateToPath:newPath]; };
    self.navigationItem.titleView = self.pathBar;

    UIBarButtonItem *newBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemImage:UIBarButtonSystemImageAdd target:self action:@selector(showNewItemMenu)];
    UIBarButtonItem *searchToggleBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemImage:UIBarButtonSystemImageSearch target:self action:@selector(toggleSearchBar)];
    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemImage:UIBarButtonSystemImageAction target:self action:@selector(showOthersMenu)];
    self.navigationItem.rightBarButtonItems = @[moreBtn, searchToggleBtn, newBtn];

    UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
    sc.searchBar.delegate = self;
    sc.obscuresBackgroundDuringPresentation = NO;
    sc.searchBar.placeholder = @"Search files...";
    sc.searchBar.scopeButtonTitles = @[@"Current", @"Global"];
    self.navigationItem.searchController = sc;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;






    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:self.tableView];

    self.bottomMenu = [[BottomMenuView alloc] init];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomMenu.onAction = ^(BottomMenuAction action) { [weakSelf handleMenuAction:action]; };
    [self.view addSubview:self.bottomMenu];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[




        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],

        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomMenu.heightAnchor constraintEqualToConstant:80],
    ]];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:lp];
}

- (void)reloadData {
    self.items = [[FileManagerCore sharedManager] contentsOfDirectoryAtPath:self.currentPath];
    [self.tableView reloadData];
    [self.pathBar updatePath:self.currentPath];
    TabInfo *at = [TabManager sharedManager].activeTab;
    if (at && at.type == TabTypeFileBrowser) { at.currentPath = self.currentPath; at.title = [self.currentPath lastPathComponent] ?: @"/"; }
}

- (void)navigateToPath:(NSString *)path {
    if (!path) return;
    FileBrowserViewController *vc = [[FileBrowserViewController alloc] initWithPath:path];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Search
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        [self reloadData];
        return;
    }
    BOOL global = (searchBar.selectedScopeButtonIndex == 1);
    NSString *searchPath = global ? @"/" : self.currentPath;
    self.items = [[FileManagerCore sharedManager] searchFilesWithQuery:searchText inPath:searchPath recursive:global];
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [self searchBar:searchBar textDidChange:searchBar.text];
}

#pragma mark - TableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"ClayFileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        ClayView *clayBg = [[ClayView alloc] initWithFrame:CGRectMake(10, 5, self.view.bounds.size.width-20, 60) cornerRadius:15];
        clayBg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        cell.backgroundView = [[UIView alloc] init];
        [cell.backgroundView addSubview:clayBg];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    FileItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.name;
    if (item.isDirectory) {
        if (item.isLocked) { cell.imageView.image = [UIImage systemImageNamed:@"lock.fill"]; cell.imageView.tintColor = [UIColor systemRedColor]; }
        else { cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"]; cell.imageView.tintColor = [UIColor systemYellowColor]; }
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
    }
    if (item.isSymbolicLink) cell.detailTextLabel.text = [NSString stringWithFormat:@" Alias ➜ %@", item.linkTarget];
    else cell.detailTextLabel.text = nil;
    return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 70; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FileItem *item = self.items[indexPath.row];
    if (item.isSymbolicLink) {
        [self navigateToPath:item.linkTarget];
        return;
    }
    if (item.isDirectory) [self navigateToPath:item.fullPath];
    else [self openFile:item];
}

- (void)openFile:(FileItem *)item {
    NSString *ext = [item.fullPath pathExtension].lowercaseString;
    UIViewController *vc = nil;
    if ([ext isEqualToString:@"plist"]) vc = [[PlistEditorViewController alloc] initWithPath:item.fullPath];
    else if ([@[@"txt", @"xml", @"json", @"h", @"m", @"c", @"cpp"] containsObject:ext]) vc = [[TextEditorViewController alloc] initWithPath:item.fullPath];
    else if ([@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:ext]) vc = [[ImageViewerViewController alloc] initWithPath:item.fullPath];
    else if ([@[@"mp4", @"mov", @"mp3", @"wav"] containsObject:ext]) vc = [[MediaPlayerViewController alloc] initWithPath:item.fullPath];
    else if ([ext isEqualToString:@"pdf"]) vc = [[PDFViewerViewController alloc] initWithPath:item.fullPath];
    else if ([ZipManager formatForPath:item.fullPath] != ArchiveFormatUnknown) { [self showArchiveOptionsForItem:item]; return; }
    else vc = [[HexEditorViewController alloc] initWithPath:item.fullPath];
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Archiving
- (void)showArchiveOptionsForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Extract" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptForArchivePasswordForPath:item.fullPath isExtracting:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForArchivePasswordForPath:(NSString *)path isExtracting:(BOOL)isExtracting {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Password" message:@"Enter password" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.secureTextEntry = YES; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *pwd = alert.textFields[0].text;
        [self processArchiveAtPath:path password:pwd.length > 0 ? pwd : nil isExtracting:isExtracting];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
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
    CGPoint p = [lp locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:p];
    if (!indexPath) return;
    [self showContextMenuForItem:self.items[indexPath.row]];
}

- (void)showContextMenuForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Favorite" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[BookmarksManager sharedManager] addBookmark:item.fullPath];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Info" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showInfoForItem:item];
    }]];
    if (item.isSymbolicLink) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Edit Link" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self showEditLinkForItem:item];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Compress" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showCompressionOptionsForItem:item];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Share" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:item.fullPath]] applicationActivities:nil];
        [self presentViewController:avc animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[FileManagerCore sharedManager] removeItemAtPath:item.fullPath error:nil];
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showInfoForItem:(FileItem *)item {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"Path: %@\n", item.fullPath];
    [info appendFormat:@"Size: %@ bytes\n", item.attributes[NSFileSize]];
    [info appendFormat:@"Modified: %@\n", item.attributes[NSFileModificationDate]];
    [info appendFormat:@"Type: %@\n", item.attributes[NSFileType]];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"File Info" message:info preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showEditLinkForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Link" message:@"Enter new destination path" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = item.linkTarget; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[FileManagerCore sharedManager] createSymbolicLinkAtPath:item.fullPath withDestinationPath:alert.textFields[0].text error:nil];
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCompressionOptionsForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Compress As..." message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *formats = @{@"ZIP": @(ArchiveFormatZip)};
    for (NSString *name in formats) {
        [alert addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            ArchiveFormat f = [formats[name] integerValue];
            NSString *ext = [name lowercaseString];
            NSString *zipPath = [item.fullPath stringByAppendingPathExtension:ext];
            [ZipManager compressFiles:@[item.fullPath] toPath:zipPath format:f password:nil error:nil];
            [self reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Favorites" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *path in [BookmarksManager sharedManager].bookmarks) {
        [alert addAction:[UIAlertAction actionWithTitle:[path lastPathComponent] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self navigateToPath:path];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showOthersMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Others" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Installed Apps" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[AppListViewController alloc] init] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Process List" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[ProcessListViewController alloc] init] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Syslog" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[SyslogViewController alloc] init] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Location Simulator" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[LocationSimulatorViewController alloc] init] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Connect to AFC" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[AfcBrowserViewController alloc] initWithPath:@"/"] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import from Files" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem]];
        dp.delegate = self;
        [self presentViewController:dp animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showSettings {}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        NSString *dest = [self.currentPath stringByAppendingPathComponent:url.lastPathComponent];
        [[FileManagerCore sharedManager] copyItemAtPath:url.path toPath:dest error:nil];
    }
    [self reloadData];
}

- (void)showNewItemMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"New File" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptForNewItem:NO];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"New Directory" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptForNewItem:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForNewItem:(BOOL)isDir {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isDir ? @"New Directory" : @"New File" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text;
        NSString *path = [self.currentPath stringByAppendingPathComponent:name];
        if (isDir) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        } else {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleSearchBar {
    [self.navigationItem.searchController setActive:YES];
    [self.navigationItem.searchController.searchBar becomeFirstResponder];
}
@end
