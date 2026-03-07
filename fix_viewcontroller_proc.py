import re

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Update row count for section 5
content = content.replace('if (section == 5) return 1;', 'if (section == 5) return 2;')

# Update cell for row logic for section 5
cell_logic_old = r"""    } else if (indexPath.section == 5) {
        cell.textLabel.text = @"Sysdiagnoseを取得";
        cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }"""

cell_logic_new = r"""    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Sysdiagnoseを取得";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else {
            cell.textLabel.text = @"実行中プロセスを表示";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
    }"""

content = content.replace(cell_logic_old, cell_logic_new)

# Update didSelectRow for section 5
did_select_old = r'else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) [self captureSysdiagnose]; }'
did_select_new = r'else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) { if (indexPath.row == 0) [self captureSysdiagnose]; else [self showProcessList]; } }'

content = content.replace(did_select_old, did_select_new)

# Add showProcessList method
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
                for (NSDictionary *p in processes) {
                    [msg appendFormat:@"PID: %@ - %@\n", p[@"pid"], [p[@"path"] lastPathComponent] ?: @"Unknown"];
                }
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"実行中プロセス" message:msg preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}
"""

if 'showProcessList' not in content:
    content = content.replace('@end', process_method + '\n@end')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
