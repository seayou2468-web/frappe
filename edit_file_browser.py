import sys

with open("FileBrowserViewController.m", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if '#import "ZipManager.h"' in line:
        new_lines.append('#import "AppManager.h"\n')
        new_lines.append('#import "IdeviceViewController.h"\n')

# Modify openFile:
found_open_file = False
for i in range(len(new_lines)):
    if '- (void)openFile:(FileItem *)item {' in new_lines[i]:
        found_open_file = True
    if found_open_file and 'NSString *ext = [targetPath pathExtension].lowercaseString;' in new_lines[i]:
        new_lines.insert(i+1, '    if ([ext isEqualToString:@"mobileconfig"]) { [self showProfileInstallOption:targetPath]; return; }\n')
        break

# Add showProfileInstallOption method
for i in range(len(new_lines)-1, -1, -1):
    if new_lines[i].strip() == '@end':
        new_lines.insert(i, """
- (void)showProfileInstallOption:(NSString *)path {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Install Profile" message:@"Do you want to install this configuration profile on the connected iDevice?" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Install" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self installProfile:path];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"View as Text" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        TextEditorViewController *vc = [[TextEditorViewController alloc] initWithPath:path];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)installProfile:(NSString *)path {
    // Find active provider from IdeviceViewController (singleton or stored state would be better, but let's try to find it)
    // For now, we assume there might be a better way, but we'll try to get it from a known place if possible.
    // In this app, IdeviceViewController seems to hold the provider.

    // Let's look for the IdeviceViewController in the navigation stack or similar.
    // However, AppManager doesn't store the provider.
    // For this implementation, we might need a way to access the current provider globally.

    // A quick hack for this specific project structure:
    // We can try to find the IdeviceViewController instance.

    IdeviceViewController *deviceVC = nil;
    for (UIViewController *vc in self.navigationController.viewControllers) {
        if ([vc isKindOfClass:[IdeviceViewController class]]) {
            deviceVC = (IdeviceViewController *)vc;
            break;
        }
    }

    if (!deviceVC || !deviceVC.currentProvider) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Error" message:@"No active iDevice connection found. Please connect to a device in the iDevice tab first." preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];

    [[AppManager sharedManager] installProfileData:data provider:deviceVC.currentProvider completion:^(BOOL success, NSString *message) {
        [spinner stopAnimating];
        [spinner removeFromSuperview];
        UIAlertController *res = [UIAlertController alertControllerWithTitle:success ? @"Success" : @"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
        [res addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:res animated:YES completion:nil];
    }];
}
""")
        break

with open("FileBrowserViewController.m", "w") as f:
    f.writelines(new_lines)
