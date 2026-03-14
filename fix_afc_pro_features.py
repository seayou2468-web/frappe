import sys
import re

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Add CustomMenuView.h import
if '#import "CustomMenuView.h"' not in content:
    content = '#import "CustomMenuView.h"\n' + content

# 2. Add properties for selection mode and editing tracking
if '@property (nonatomic, assign) BOOL isSelecting;' not in content:
    content = content.replace('@property (nonatomic, assign) BOOL isMoveOperation;',
                              '@property (nonatomic, assign) BOOL isMoveOperation;\n@property (nonatomic, strong) NSMutableDictionary *openFiles;')

# 3. Update init to initialize openFiles
content = content.replace('_favorites = [NSMutableArray array];',
                          '_favorites = [NSMutableArray array]; _openFiles = [NSMutableDictionary dictionary];')

# 4. Update setupUI to use CustomMenuView style buttons in Nav bar
old_nav_buttons = 'UIBarButtonItem *backBtn = [[UIBarButtonItem alloc] initWithTitle:@"Parent" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];\n    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];\n    self.navigationItem.rightBarButtonItems = @[moreBtn, backBtn];'

new_nav_buttons = """UIBarButtonItem *backBtn = [[UIBarButtonItem alloc] initWithTitle:@"戻る" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];
    UIBarButtonItem *selectBtn = [[UIBarButtonItem alloc] initWithTitle:@"選択" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectionMode)];
    self.navigationItem.rightBarButtonItems = @[moreBtn, selectBtn, backBtn];"""

content = content.replace(old_nav_buttons, new_nav_buttons)

# 5. Add toggleSelectionMode and bulk actions
bulk_methods = """
- (void)toggleSelectionMode {
    BOOL isEditing = !self.tableView.isEditing;
    [self.tableView setEditing:isEditing animated:YES];
    UIBarButtonItem *selectBtn = self.navigationItem.rightBarButtonItems[1];
    selectBtn.title = isEditing ? @"キャンセル" : @"選択";
}

- (void)showMoreMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規フォルダ" systemImage:@"folder.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self promptForNewItem:YES]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"新規ファイル" systemImage:@"doc.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self promptForNewItem:NO]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"インポート" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{ [self selectLocalFile]; }]];
    if (self.clipboardPaths.count > 0) {
        NSString *title = self.isMoveOperation ? @"ここに移動" : @"ここに貼り付け";
        [menu addAction:[CustomMenuAction actionWithTitle:title systemImage:@"doc.on.clipboard" style:CustomMenuActionStyleDefault handler:^{ [self performPaste]; }]];
    }
    if (self.tableView.isEditing) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [self performBulkDelete]; }]];
    }
    [menu showInView:self.view];
}

- (void)performBulkDelete {
    NSArray *ips = [self.tableView indexPathsForSelectedRows];
    if (ips.count == 0) return;
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (NSIndexPath *ip in ips) {
            NSString *name = self.items[ip.row][@"name"];
            NSString *full = [self.currentPath stringByAppendingPathComponent:name];
            afc_remove_path(self.afc, [full UTF8String]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [self toggleSelectionMode]; [self loadPath:self.currentPath]; });
    });
}
"""

content = re.sub(r'- \(void\)showMoreMenu \{.*?\}', bulk_methods, content, flags=re.DOTALL)

# 6. Update showContextMenuForItem to use CustomMenuView
context_menu_method = """
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

- (void)shareFile:(NSString *)name {
    NSString *full = [self.currentPath stringByAppendingPathComponent:name];
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        struct AfcFileHandle *h = NULL;
        afc_file_open(self.afc, [full UTF8String], AfcRdOnly, &h);
        if (h) {
            uint8_t *data = NULL; size_t len = 0;
            afc_file_read_entire(h, &data, &len);
            afc_file_close(h);
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
        dispatch_async(dispatch_get_main_queue(), ^{ [self showLoading:NO]; });
    });
}
"""

content = re.sub(r'- \(void\)showContextMenuForItem:\(NSDictionary \*\)item \{.*?\}', context_menu_method, content, flags=re.DOTALL)

# 7. Add auto-upload logic in viewWillAppear
content = content.replace('- (void)viewDidLoad {', """- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self checkAndUploadModifiedFiles];
}

- (void)checkAndUploadModifiedFiles {
    for (NSString *name in [self.openFiles allKeys]) {
        NSString *localPath = self.openFiles[name][@"local"];
        NSString *remotePath = self.openFiles[name][@"remote"];
        NSDate *openDate = self.openFiles[name][@"date"];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:localPath error:nil];
        if (attrs && [attrs.fileModificationDate compare:openDate] == NSOrderedDescending) {
            [self uploadFile:localPath toRemotePath:remotePath];
            // Update the date so we don't upload again unless modified further
            self.openFiles[name] = @{@"local": localPath, @"remote": remotePath, @"date": [NSDate date]};
        }
    }
}

- (void)uploadFile:(NSString *)local toRemotePath:(NSString *)remote {
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSData *data = [NSData dataWithContentsOfFile:local];
        struct AfcFileHandle *h = NULL;
        struct IdeviceFfiError *err = afc_file_open(self.afc, [remote UTF8String], AfcWr, &h);
        if (!err && h) {
            afc_file_write(h, data.bytes, data.length);
            afc_file_close(h);
        }
        if (err) idevice_error_free(err);
        dispatch_async(dispatch_get_main_queue(), ^{ [self showLoading:NO]; });
    });
}

- (void)viewDidLoad {""")

# 8. Update openFile to track opened files
content = content.replace('[self showEditorForPath:temp];',
                          'self.openFiles[name] = @{@"local": temp, @"remote": full, @"date": [NSDate date]};\n                    [self showEditorForPath:temp];')

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
