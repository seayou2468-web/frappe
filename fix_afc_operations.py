import sys
import re

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Add UIDocumentPickerDelegate and clipboard property
content = content.replace('@interface AfcBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate>',
                          '@interface AfcBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate, UIDocumentPickerDelegate>')

if '@property (nonatomic, strong) NSArray<NSString *> *clipboardPaths;' not in content:
    content = content.replace('@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;',
                              '@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;\n@property (nonatomic, strong) NSArray<NSString *> *clipboardPaths;\n@property (nonatomic, assign) BOOL isMoveOperation;')

# 2. Add showMoreMenu and associated methods
more_methods = """
- (void)showMoreMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Operations" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"New Folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self promptForNewItem:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"New File" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self promptForNewItem:NO]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Import from Device" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self selectLocalFile]; }]];
    if (self.clipboardPaths.count > 0) {
        NSString *title = self.isMoveOperation ? @"Move Here" : @"Paste Here";
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self performPaste]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptForNewItem:(BOOL)isDir {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isDir ? @"New Folder" : @"New File" message:@"Enter name" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) return;
        NSString *full = [self.currentPath stringByAppendingPathComponent:name];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            struct IdeviceFfiError *err;
            if (isDir) {
                err = afc_make_directory(self.afc, [full UTF8String]);
            } else {
                struct AfcFileHandle *h = NULL;
                err = afc_file_open(self.afc, [full UTF8String], AfcWr, &h);
                if (!err && h) afc_file_close(h);
            }
            if (err) { NSLog(@"[AFC] Create error: %s", err->message); idevice_error_free(err); }
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
        struct IdeviceFfiError *err = afc_file_open(self.afc, [dest UTF8String], AfcWr, &h);
        if (!err && h) {
            err = afc_file_write(h, data.bytes, data.length);
            afc_file_close(h);
        }
        if (err) { NSLog(@"[AFC] Import error: %s", err->message); idevice_error_free(err); }
        [self loadPath:self.currentPath];
    });
}

- (void)performPaste {
    [self showLoading:YES];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (NSString *src in self.clipboardPaths) {
            NSString *dest = [self.currentPath stringByAppendingPathComponent:src.lastPathComponent];
            struct IdeviceFfiError *err = afc_rename_path(self.afc, [src UTF8String], [dest UTF8String]);
            if (err) { NSLog(@"[AFC] Rename/Move error: %s", err->message); idevice_error_free(err); }
        }
        if (self.isMoveOperation) self.clipboardPaths = nil;
        [self loadPath:self.currentPath];
    });
}
"""

content = content.replace('- (void)handleSwipeBack:', more_methods + "\n- (void)handleSwipeBack:")

# 3. Add long press gesture for context menu
content = content.replace('[self.view addGestureRecognizer:self.customSwipeGesture];',
                          '[self.view addGestureRecognizer:self.customSwipeGesture];\n\n    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];\n    [self.tableView addGestureRecognizer:lp];')

long_press_method = """
- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [lp locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (ip) [self showContextMenuForItem:self.items[ip.row]];
}

- (void)showContextMenuForItem:(NSDictionary *)item {
    NSString *name = item[@"name"];
    NSString *full = [self.currentPath stringByAppendingPathComponent:name];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            struct IdeviceFfiError *err = afc_remove_path(self.afc, [full UTF8String]);
            if (err) { idevice_error_free(err); }
            [self loadPath:self.currentPath];
        });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self promptRename:full]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { self.clipboardPaths = @[full]; self.isMoveOperation = NO; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Move" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { self.clipboardPaths = @[full]; self.isMoveOperation = YES; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptRename:(NSString *)oldPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = oldPath.lastPathComponent; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = alert.textFields[0].text;
        if (newName.length == 0) return;
        NSString *newPath = [[oldPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            struct IdeviceFfiError *err = afc_rename_path(self.afc, [oldPath UTF8String], [newPath UTF8String]);
            if (err) { idevice_error_free(err); }
            [self loadPath:self.currentPath];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
"""
content = content.replace('- (void)showLoading:', long_press_method + "\n- (void)showLoading:")

# 4. Add "More" button to navigation bar
content = content.replace('self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Parent" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];',
                          'UIBarButtonItem *backBtn = [[UIBarButtonItem alloc] initWithTitle:@"Parent" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];\n    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];\n    self.navigationItem.rightBarButtonItems = @[moreBtn, backBtn];')

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
