import sys

with open('FileBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Update Navigation Bar (setupUI)
old_nav_setup = """    // Right Bar Button (Search Toggle)
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(toggleSearch)];"""

new_nav_setup = """    // Right Bar Buttons
    UIBarButtonItem *searchBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleSearch)];
    UIBarButtonItem *selectBtn = [[UIBarButtonItem alloc] initWithTitle:@"選択" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelectionMode)];
    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];
    self.navigationItem.rightBarButtonItems = @[moreBtn, selectBtn, searchBtn];"""

if old_nav_setup in content:
    content = content.replace(old_nav_setup, new_nav_setup)

# 2. Add selection methods
selection_methods = """
- (void)toggleSelectionMode {
    [self.tableView setEditing:!self.tableView.isEditing animated:YES];
    UIBarButtonItem *selectBtn = self.navigationItem.rightBarButtonItems[1];
    selectBtn.title = self.tableView.isEditing ? @"キャンセル" : @"選択";

    if (self.tableView.isEditing) {
        self.tableView.allowsMultipleSelectionDuringEditing = YES;
        [self showSelectionActions];
    } else {
        [self hideSelectionActions];
    }
}

- (void)showSelectionActions {
    // Show a bottom action bar or update the bottom menu for selection actions
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

- (void)hideSelectionActions {
    // Implementation for hiding selection UI if any specific components were added
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
"""

# Append selection methods before the last end
if "@end" in content:
    content = content.replace("@end", selection_methods + "\n@end")

with open('FileBrowserViewController.m', 'w') as f:
    f.write(content)
