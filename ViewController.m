// File: ViewController.m
#import "ViewController.h"
#import "PlistViewer.h"
#import "PathBarFileBrowser.h"
#import "BottomMenuView.h"
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>

@interface ViewController () <UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) NSMutableArray<NSString *> *items;
@property (strong, nonatomic) NSMutableArray<NSString *> *paths;
@property (strong, nonatomic, readwrite) NSString *currentPath;

@property (strong, nonatomic) PathBarFileBrowser *pathBar;
@property (strong, nonatomic) BottomMenuView *bottomMenu;
@end

@implementation ViewController

#pragma mark - 初期化

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _currentPath = path;
        _items = [NSMutableArray array];
        _paths = [NSMutableArray array];
    }
    return self;
}

#pragma mark - View

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // UITableView
    CGFloat topMargin = 60; // PathBar の高さ
    CGFloat bottomMargin = 80; // BottomMenu の高さ
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, topMargin, self.view.bounds.size.width, self.view.bounds.size.height - topMargin - bottomMargin) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];

    // PathBarFileBrowser
    self.pathBar = [[PathBarFileBrowser alloc] initWithFrame:CGRectMake(10, 10, self.view.bounds.size.width - 20, 40)];
    self.pathBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    __weak typeof(self) weakSelf = self;
    self.pathBar.onPathEntered = ^(NSString *enteredPath) {
        [weakSelf navigateToPath:enteredPath];
    };
    [self.view addSubview:self.pathBar];
    [self.pathBar setPathText:self.currentPath];

    // BottomMenuView
    self.bottomMenu = [[BottomMenuView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - bottomMargin, self.view.bounds.size.width, bottomMargin)];
    self.bottomMenu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.bottomMenu];

    // 画面端スワイプで戻る
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;

    [self listDirectory:self.currentPath];
}

#pragma mark - 画面端スワイプ対応

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        return YES;
    }
    return NO;
}

#pragma mark - ディレクトリ列挙（シンボリックリンク対応）

- (void)listDirectory:(NSString *)path {
    NSMutableArray *list = [NSMutableArray array];
    NSMutableArray *paths = [NSMutableArray array];

    if (![path isEqualToString:@"/"]) {
        [list addObject:@"../"];
        [paths addObject:[path stringByDeletingLastPathComponent]];
    }

    DIR *dir = opendir([path UTF8String]);
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.') continue;

            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            NSString *fullPath = [path stringByAppendingPathComponent:name];
            struct stat st;

            if (lstat([fullPath UTF8String], &st) == 0 && S_ISLNK(st.st_mode)) {
                char buf[PATH_MAX];
                ssize_t len = readlink([fullPath UTF8String], buf, sizeof(buf)-1);
                if (len > 0) {
                    buf[len] = '\0';
                    NSString *linkPath = [NSString stringWithUTF8String:buf];
                    if (![linkPath hasPrefix:@"/"]) {
                        linkPath = [[fullPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:linkPath];
                        linkPath = [linkPath stringByStandardizingPath];
                    }
                    struct stat linkSt;
                    if (stat([linkPath UTF8String], &linkSt) != 0 || !S_ISDIR(linkSt.st_mode)) {
                        name = [name stringByAppendingString:@" (リンク切れ)"];
                    }
                } else {
                    name = [name stringByAppendingString:@" (リンク切れ)"];
                }
            }

            [list addObject:name];
            [paths addObject:fullPath];
        }
        closedir(dir);
    }

    _items = list;
    _paths = paths;
    [self.tableView reloadData];

    // PathBar に現在のパスを反映
    [self.pathBar setPathText:path];
}

#pragma mark - パス移動

- (void)navigateToPath:(NSString *)path {
    struct stat st;
    if (stat([path UTF8String], &st) == 0 && S_ISDIR(st.st_mode)) {
        self.currentPath = path;
        [self listDirectory:path];
    }
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];

    cell.textLabel.text = _items[indexPath.row];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *fullPath = _paths[indexPath.row];
    NSString *name = _items[indexPath.row];

    if ([name isEqualToString:@"../"]) {
        // 上の階層に移動
        [self navigateToPath:[fullPath stringByStandardizingPath]];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    struct stat st;
    BOOL isDir = NO;
    if (lstat([fullPath UTF8String], &st) == 0) {
        if (S_ISLNK(st.st_mode)) {
            char buf[PATH_MAX];
            ssize_t len = readlink([fullPath UTF8String], buf, sizeof(buf)-1);
            if (len > 0) {
                buf[len] = '\0';
                NSString *linkPath = [NSString stringWithUTF8String:buf];
                if (![linkPath hasPrefix:@"/"]) {
                    linkPath = [[fullPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:linkPath];
                    linkPath = [linkPath stringByStandardizingPath];
                }
                struct stat linkSt;
                if (stat([linkPath UTF8String], &linkSt) == 0 && S_ISDIR(linkSt.st_mode)) {
                    isDir = YES;
                    fullPath = linkPath;
                }
            }
        } else if (S_ISDIR(st.st_mode)) {
            isDir = YES;
        }
    }

    if (isDir) {
        ViewController *vc = [[ViewController alloc] initWithPath:fullPath];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([[fullPath pathExtension] isEqualToString:@"plist"]) {
        PlistViewer *plistVC = [[PlistViewer alloc] initWithPlistPath:fullPath];
        [self.navigationController pushViewController:plistVC animated:YES];
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end