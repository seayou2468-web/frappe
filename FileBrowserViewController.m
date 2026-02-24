#import "FileBrowserViewController.h"
#import "FileManagerCore.h"
#import "PathBarView.h"
#import "BottomMenuView.h"
#import "ZipManager.h"
#import "PlistEditorViewController.h"
#import "TextEditorViewController.h"
#import "ImageViewerViewController.h"
#import "MediaPlayerViewController.h"
#import "PDFViewerViewController.h"
#import "HexEditorViewController.h"
#import "ProcessListViewController.h"
#import "extends/JITEnableContext.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface FileBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSArray<FileItem *> *items;
@property (strong, nonatomic) PathBarView *pathBar;
@property (strong, nonatomic) BottomMenuView *bottomMenu;
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
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.navigationController.navigationBarHidden = YES;

    [self setupUI];
    [self reloadData];
}

- (void)setupUI {
    self.pathBar = [[PathBarView alloc] init];
    self.pathBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pathBar updatePath:self.currentPath];
    __weak typeof(self) weakSelf = self;
    self.pathBar.onPathChanged = ^(NSString *newPath) {
        [weakSelf navigateToPath:newPath];
    };
    [self.view addSubview:self.pathBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.bottomMenu = [[BottomMenuView alloc] init];
    self.bottomMenu.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomMenu.onAction = ^(BottomMenuAction action) {
        [weakSelf handleMenuAction:action];
    };
    [self.view addSubview:self.bottomMenu];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.pathBar.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [self.pathBar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],
        [self.pathBar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10],
        [self.pathBar.heightAnchor constraintEqualToConstant:44],

        [self.bottomMenu.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomMenu.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomMenu.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomMenu.topAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-60],

        [self.tableView.topAnchor constraintEqualToAnchor:self.pathBar.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.bottomMenu.topAnchor],
    ]];

    // Long press for context menu
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:lp];
}

- (void)reloadData {
    self.items = [[FileManagerCore sharedManager] contentsOfDirectoryAtPath:self.currentPath];
    [self.tableView reloadData];
    [self.pathBar updatePath:self.currentPath];
}

- (void)navigateToPath:(NSString *)path {
    FileBrowserViewController *vc = [[FileBrowserViewController alloc] initWithPath:path];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"FileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }

    FileItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.name;

    if (item.isDirectory) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"doc.fill"];
        cell.accessoryType = UITableViewCellAccessoryDetailButton;
    }

    if (item.isSymbolicLink) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Alias -> %@", item.linkTarget];
        cell.detailTextLabel.textColor = [UIColor systemBlueColor];
    } else {
        cell.detailTextLabel.text = nil;
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FileItem *item = self.items[indexPath.row];

    if (item.isDirectory) {
        [self navigateToPath:item.fullPath];
    } else {
        [self openFile:item];
    }
}

- (void)openFile:(FileItem *)item {
    NSString *ext = [item.fullPath pathExtension].lowercaseString;
    UIViewController *vc = nil;

    if ([ext isEqualToString:@"plist"]) {
        vc = [[PlistEditorViewController alloc] initWithPath:item.fullPath];
    } else if ([@[@"txt", @"xml", @"json", @"h", @"m", @"c", @"cpp"] containsObject:ext]) {
        vc = [[TextEditorViewController alloc] initWithPath:item.fullPath];
    } else if ([@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:ext]) {
        vc = [[ImageViewerViewController alloc] initWithPath:item.fullPath];
    } else if ([@[@"mp4", @"mov", @"mp3", @"wav"] containsObject:ext]) {
        vc = [[MediaPlayerViewController alloc] initWithPath:item.fullPath];
    } else if ([ext isEqualToString:@"pdf"]) {
        vc = [[PDFViewerViewController alloc] initWithPath:item.fullPath];
    } else {
        vc = [[HexEditorViewController alloc] initWithPath:item.fullPath];
    }

    if (vc) {
        [self.navigationController pushViewController:vc animated:YES];
    }
}

#pragma mark - Context Menu

- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;

    CGPoint p = [lp locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:p];
    if (!indexPath) return;

    FileItem *item = self.items[indexPath.row];
    [self showContextMenuForItem:item];
}

- (void)showContextMenuForItem:(FileItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Share" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:item.fullPath]] applicationActivities:nil];
        [self presentViewController:avc animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[FileManagerCore sharedManager] removeItemAtPath:item.fullPath error:nil];
        [self reloadData];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Menu Actions

- (void)handleMenuAction:(BottomMenuAction)action {
    switch (action) {
        case BottomMenuActionFavorites:
            [self showFavoritesMenu];
            break;
        case BottomMenuActionOthers:
            [self showOthersMenu];
            break;
        case BottomMenuActionSettings:
            [self showSettings];
            break;
        case BottomMenuActionTabs:
            [self importFile];
            break;
        default:
            break;
    }
}

- (void)importFile {
    UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem]];
    dp.delegate = self;
    [self presentViewController:dp animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        NSString *dest = [self.currentPath stringByAppendingPathComponent:url.lastPathComponent];
        [[FileManagerCore sharedManager] copyItemAtPath:url.path toPath:dest error:nil];
    }
    [self reloadData];
}

- (void)showFavoritesMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Favorites" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add Current to Favorites" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showOthersMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Others" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Processes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.navigationController pushViewController:[[ProcessListViewController alloc] init] animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"App List" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"AFC Manager" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSettings {
    // Placeholder
}

@end
