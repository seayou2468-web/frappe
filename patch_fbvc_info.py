import sys

with open('FileBrowserViewController.m', 'r') as f:
    content = f.read()

if '#import "FileInfoViewController.h"' not in content:
    content = content.replace('#import "HexEditorViewController.h"', '#import "HexEditorViewController.h"\n#import "FileInfoViewController.h"')

old_show_info = """- (void)showInfoForItem:(FileItem *)item {
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"Path: %@\nSize: %@ bytes\nModified: %@\nType: %@", item.fullPath, item.attributes[NSFileSize], item.attributes[NSFileModificationDate], item.attributes[NSFileType]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ファイル情報" message:info preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}"""

new_show_info = """- (void)showInfoForItem:(FileItem *)item {
    FileInfoViewController *vc = [[FileInfoViewController alloc] initWithItem:item];
    [self.navigationController pushViewController:vc animated:YES];
}"""

if old_show_info in content:
    content = content.replace(old_show_info, new_show_info)
    print("Fixed showInfoForItem.")

with open('FileBrowserViewController.m', 'w') as f:
    f.write(content)
