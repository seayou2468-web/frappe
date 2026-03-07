import re

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Add captureSysdiagnose method
capture_method = r"""
- (void)captureSysdiagnose {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[IdeviceManager sharedManager] captureSysdiagnoseWithCompletion:^(NSString *path, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
            self.view.userInteractionEnabled = YES;

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"完了" message:[NSString stringWithFormat:@"Sysdiagnoseを保存しました:\n%@", [path lastPathComponent]] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}
"""

if 'captureSysdiagnose {' not in content:
    content = content.replace('@end', capture_method + '\n@end')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
