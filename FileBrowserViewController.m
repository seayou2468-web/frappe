#import "FileBrowserViewController.h"
#import "FileManagerCore.h"
#import "ThemeEngine.h"
#import "PathBarView.h"
#import "BottomMenuView.h"
#import "MainContainerViewController.h"
#import "BookmarksManager.h"
#import "ZipManager.h"
#import "AppListViewController.h"
#import "ProcessListViewController.h"
#import "SyslogViewController.h"
#import "LocationSimulatorViewController.h"
#import "DeviceInfoViewController.h"
#import "SettingsViewController.h"
#import "AfcBrowserViewController.h"
#import "ImageViewerViewController.h"
#import "MediaPlayerViewController.h"
#import "PDFViewerViewController.h"
#import "PlistEditorViewController.h"
#import "TextEditorViewController.h"
#import "HexEditorViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface FileBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating, UIDocumentPickerDelegate>
@property (strong, nonatomic) NSArray<FileItem *> *allItems;
@property (strong, nonatomic) NSArray<FileItem *> *filteredItems;
@property (strong, nonatomic) PathBarView *pathBar;
@property (strong, nonatomic) UISearchController *searchController;
@end

@implementation FileBrowserViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _currentPath = path ?: @"/";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = [self.currentPath lastPathComponent];
    if ([self.currentPath isEqualToString:@"/"]) self.title = @"Root";

    [self setupTableView];
    [self setupNavigation];
    [self setupSearch];
    [self reloadData];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)setupNavigation {
    self.pathBar = [[PathBarView alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];
    [self.pathBar updatePath:self.currentPath];
    __weak typeof(self) weakSelf = self;
    self.pathBar.onPathChanged = ^(NSString *newPath) {
        [weakSelf navigateToPath:newPath];
    };
    self.navigationItem.titleView = self.pathBar;

    UIBarButtonItem *plusBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill"] style:UIBarButtonItemStylePlain target:self action:@selector(showNewItemMenu)];
    self.navigationItem.rightBarButtonItem = plusBtn;
}

- (void)setupSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search files...";
    self.searchController.searchBar.tintColor = [UIColor whiteColor];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)reloadData {
    if ([self.currentPath containsString:@".zip"]) {
        NSRange range = [self.currentPath rangeOfString:@".zip"];
        NSString *zipPath = [self.currentPath substringToIndex:range.location + 4];
        NSString *internalPath = [self.currentPath substringFromIndex:range.location + 4];
        if ([internalPath hasPrefix:@"/"]) internalPath = [internalPath substringFromIndex:1];
        self.allItems = [ZipManager listContentsOfZipAtPath:zipPath internalPath:internalPath];
    } else {
        NSError *error = nil;
        self.allItems = [[FileManagerCore sharedManager] contentsOfDirectoryAtPath:self.currentPath error:&error];
        if (error) {
            self.allItems = @[];
        }
    }
    self.filteredItems = self.allItems;
    [self.tableView reloadData];
}

- (void)navigateToPath:(NSString *)path {
    FileBrowserViewController *next = [[FileBrowserViewController alloc] initWithPath:path];
    [self.navigationController pushViewController:next animated:YES];
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"FileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UIView *bg = [[UIView alloc] init];
        [ThemeEngine applyLiquidGlassStyleToView:bg cornerRadius:12];
        bg.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView insertSubview:bg atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [bg.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
            [bg.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
            [bg.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [bg.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        ]];
    }

    FileItem *item = self.filteredItems[indexPath.row];
    cell.textLabel.text = item.name;

    NSString *imgName = item.isDirectory ? @"folder.fill" : @"doc.fill";
    if (item.isSymbolicLink) imgName = @"link";
    if ([ZipManager formatForPath:item.name] == ArchiveFormatZip) imgName = @"archivebox.fill";

    cell.imageView.image = [UIImage systemImageNamed:imgName];
    cell.imageView.tintColor = item.isDirectory ? [UIColor systemBlueColor] : [UIColor lightGrayColor];

    if (!item.isDirectory) {
        cell.detailTextLabel.text = [NSByteCountFormatter stringFromByteCount:[item.attributes[NSFileSize] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    } else {
        cell.detailTextLabel.text = nil;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    FileItem *item = self.filteredItems[indexPath.row];
    if (item.isDirectory || [ZipManager formatForPath:item.fullPath] == ArchiveFormatZip) {
        [self navigateToPath:item.fullPath];
    } else if (item.isSymbolicLink) {
        NSString *target = item.linkTarget;
        if (![target isAbsolutePath]) {
            target = [[item.fullPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:target];
        }
        [self navigateToPath:target];
    } else {
        [self openFile:item];
    }
}

- (void)openFile:(FileItem *)item {
    NSString *ext = [item.name pathExtension].lowercaseString;
    UIViewController *vc = nil;
    if ([@[@"png", @"jpg", @"jpeg", @"gif", @"heic"] containsObject:ext]) {
        vc = [[ImageViewerViewController alloc] initWithPath:item.fullPath];
    } else if ([@[@"mp4", @"mov", @"m4v", @"mp3", @"wav", @"aac"] containsObject:ext]) {
        vc = [[MediaPlayerViewController alloc] initWithPath:item.fullPath];
    } else if ([ext isEqualToString:@"pdf"]) {
        vc = [[PDFViewerViewController alloc] initWithPath:item.fullPath];
    } else if ([ext isEqualToString:@"plist"]) {
        vc = [[PlistEditorViewController alloc] initWithPath:item.fullPath];
    } else {
        vc = [[TextEditorViewController alloc] initWithPath:item.fullPath];
    }
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UISearchResultsUpdating
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *text = searchController.searchBar.text;
    if (text.length == 0) {
        self.filteredItems = self.allItems;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@", text];
        self.filteredItems = [self.allItems filteredArrayUsingPredicate:pred];
    }
    [self.tableView reloadData];
}

#pragma mark - Menu Actions
- (void)handleMenuAction:(NSNumber *)actionNum {
    BottomMenuAction action = [actionNum integerValue];
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
    [alert addAction:[UIAlertAction actionWithTitle:@"Installed Apps (JIT)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
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
    [alert addAction:[UIAlertAction actionWithTitle:@"Device Info" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[DeviceInfoViewController alloc] init] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"AFC Browser" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self.navigationController pushViewController:[[AfcBrowserViewController alloc] initWithPath:@"/"] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import from Files" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem]];
        dp.delegate = self;
        [self presentViewController:dp animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSettings {
    [self.navigationController pushViewController:[[SettingsViewController alloc] init] animated:YES];
}

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

#pragma mark - Long Press Menu
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [cell addGestureRecognizer:lp];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [lp locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:p];
    if (!indexPath) return;
    FileItem *item = self.filteredItems[indexPath.row];
    [self showContextMenuForItem:item];
}

- (void)showContextMenuForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showRenameForItem:item];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Compress" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *zipPath = [item.fullPath stringByAppendingPathExtension:@"zip"];
        [ZipManager compressFiles:@[item.fullPath] toPath:zipPath format:ArchiveFormatZip password:nil error:nil];
        [self reloadData];
    }]];
    if ([ZipManager formatForPath:item.name] == ArchiveFormatZip) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Extract Here" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [ZipManager extractArchiveAtPath:item.fullPath toDestination:[item.fullPath stringByDeletingLastPathComponent] password:nil error:nil];
            [self reloadData];
        }]];
    }
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

- (void)showRenameForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = item.name; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = alert.textFields[0].text;
        NSString *newPath = [[item.fullPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        [[NSFileManager defaultManager] moveItemAtPath:item.fullPath toPath:newPath error:nil];
        [self reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
