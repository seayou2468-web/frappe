import re

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

process_method = r"""
- (void)showProcessList {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[IdeviceManager sharedManager] getProcessListWithCompletion:^(NSArray *processes, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
            self.view.userInteractionEnabled = YES;

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                NSMutableString *msg = [NSMutableString string];
                // Limit to first 20 processes for display in alert
                NSInteger count = MIN(processes.count, 20);
                for (NSInteger i = 0; i < count; i++) {
                    NSDictionary *p = processes[i];
                    [msg appendFormat:@"PID: %@ - %@\n", p[@"pid"], [p[@"path"] lastPathComponent] ?: @"Unknown"];
                }
                if (processes.count > 20) [msg appendString:@"... 他多数"];

                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"実行中プロセス" message:msg preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}
"""

if 'showProcessList {' not in content:
    content = content.replace('@end', process_method + '\n@end')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
