import os

file_path = 'FileBrowserViewController.m'
with open(file_path, 'r') as f:
    content = f.read()

# Add import
if '#import "LogViewerViewController.h"' not in content:
    content = content.replace('#import "FileInfoViewController.h"', '#import "FileInfoViewController.h"\n#import "LogViewerViewController.h"')

# Add menu item to showOthersMenu
old_menu = """- (void)showOthersMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"その他"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ファイルから読み込む" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{ [self selectFile]; }]];
    [menu showInView:self.view];
}"""

new_menu = """- (void)showOthersMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"その他"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ファイルから読み込む" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{ [self selectFile]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"システムログ" systemImage:@"terminal" style:CustomMenuActionStyleDefault handler:^{ [self showLogViewer]; }]];
    [menu showInView:self.view];
}

- (void)showLogViewer {
    LogViewerViewController *vc = [[LogViewerViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}"""

content = content.replace(old_menu, new_menu)

with open(file_path, 'w') as f:
    f.write(content)
