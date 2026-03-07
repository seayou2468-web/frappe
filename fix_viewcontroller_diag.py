import re

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Increase sections to 6
content = content.replace('return 5; }', 'return 6; }')

# Update row count for new section
content = content.replace('if (section == 4) return 1;', 'if (section == 4) return 1; if (section == 5) return 1;')

# Update section titles
content = content.replace('if (section == 4) return @"システム";', 'if (section == 4) return @"システム"; if (section == 5) return @"RSDサービス利用";')

# Update cell for row
cell_logic = r"""    } else if (indexPath.section == 4) {
        cell.textLabel.text = @"システムログを表示"; cell.textLabel.textColor = [UIColor whiteColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 5) {
        cell.textLabel.text = @"Sysdiagnoseを取得";
        cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;"""

content = content.replace('    } else if (indexPath.section == 4) {\n        cell.textLabel.text = @"システムログを表示"; cell.textLabel.textColor = [UIColor whiteColor];\n        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;\n    }\n    return cell;', cell_logic)

# Update didSelectRow
did_select_logic = r"""    else if (indexPath.section == 4) [self.navigationController pushViewController:[[LogViewerViewController alloc] init] animated:YES];
    else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) [self captureSysdiagnose]; }
}"""

content = content.replace('    else if (indexPath.section == 4) [self.navigationController pushViewController:[[LogViewerViewController alloc] init] animated:YES];\n}', did_select_logic)

# Add captureSysdiagnose method
capture_method = r"""
- (void)captureSysdiagnose {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[IdeviceManager sharedManager] captureSysdiagnoseWithCompletion:^(NSString *path, NSError *error) {
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
    }];
}
"""

if 'captureSysdiagnose' not in content:
    content = content.replace('@end', capture_method + '\n@end')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
