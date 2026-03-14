import sys

file_path = 'AppListViewController.m'
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if '#import "DdiManager.h"' in line:
        new_lines.append(line)
        new_lines.append('#import "AppDetailViewController.h"\n')
        new_lines.append('#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>\n')
        continue
    if '@interface AppListViewController () <UITableViewDelegate, UITableViewDataSource>' in line:
        new_lines.append('@interface AppListViewController () <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>\n')
        continue
    if 'self.title = @"Applications";' in line:
        new_lines.append(line)
        new_lines.append('    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(installTapped)];\n')
        continue
    new_lines.append(line)

content = "".join(new_lines)

# Replace didSelectRow
old_ds = """- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppInfo *app = [self filteredApps][indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:app.name message:@"Select launch mode" preferredStyle:UIAlertControllerStyleActionSheet];
    [ThemeEngine applyGlassStyleToView:alert.view cornerRadius:20];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch Normal" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jitMode:JitModeNone];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch with JIT (God-Speed)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jitMode:JitModeNative];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch with JIT (JavaScript)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jitMode:JitModeJS];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    [self presentViewController:alert animated:YES completion:nil];
}"""

new_ds = """- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    AppInfo *app = [self filteredApps][indexPath.row];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:app.name message:@"Select action" preferredStyle:UIAlertControllerStyleActionSheet];
    [ThemeEngine applyGlassStyleToView:alert.view cornerRadius:20];

    [alert addAction:[UIAlertAction actionWithTitle:@"Show Details" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        AppDetailViewController *vc = [[AppDetailViewController alloc] initWithAppInfo:app provider:self.provider];
        [self.navigationController pushViewController:vc animated:YES];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch Normal" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jitMode:JitModeNone];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch with JIT (God-Speed)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jitMode:JitModeNative];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Launch with JIT (JavaScript)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self launch:app.bundleId jitMode:JitModeJS];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    [self presentViewController:alert animated:YES completion:nil];
}"""

content = content.replace(old_ds, new_ds)

# Add methods at the end
content = content.replace('@end', """
- (void)installTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithFilenameExtension:@"ipa"]]];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"Installing" message:@"Preparing..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];

    [[AppManager sharedManager] installAppWithURL:url provider:self.provider progress:^(double progress, NSString *status) {
        progressAlert.message = status;
    } completion:^(BOOL success, NSString *error) {
        [progressAlert dismissViewControllerAnimated:YES completion:^{
            if (success) {
                UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Success" message:@"Application installed successfully." preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self refreshApps]; }]];
                [self presentViewController:done animated:YES completion:nil];
            } else {
                UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Error" message:error preferredStyle:UIAlertControllerStyleAlert];
                [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:err animated:YES completion:nil];
            }
        }];
    }];
}
@end
""")

with open(file_path, 'w') as f:
    f.write(content)
