import re

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Update row count for section 5
content = content.replace('if (section == 5) return 2;', 'if (section == 5) return 3;')

# Update cell for row logic for section 5
cell_logic_old = r"""    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Sysdiagnoseを取得";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else {
            cell.textLabel.text = @"実行中プロセスを表示";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
    }"""

cell_logic_new = r"""    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Sysdiagnoseを取得";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"実行中プロセスを表示";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else {
            cell.textLabel.text = @"スクリーンショットを撮る";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
    }"""

content = content.replace(cell_logic_old, cell_logic_new)

# Update didSelectRow for section 5
did_select_old = r'else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) { if (indexPath.row == 0) [self captureSysdiagnose]; else [self showProcessList]; } }'
did_select_new = r'else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) { if (indexPath.row == 0) [self captureSysdiagnose]; else if (indexPath.row == 1) [self showProcessList]; else [self takeScreenshot]; } }'

content = content.replace(did_select_old, did_select_new)

# Add takeScreenshot method
screenshot_method = r"""
- (void)takeScreenshot {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.center = self.view.center;
    [self.view addSubview:spinner];
    [spinner startAnimating];
    self.view.userInteractionEnabled = NO;

    [[IdeviceManager sharedManager] takeScreenshotWithCompletion:^(UIImage *image, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [spinner removeFromSuperview];
            self.view.userInteractionEnabled = YES;

            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"エラー" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                UIViewController *vc = [[UIViewController alloc] init];
                vc.title = @"Screenshot";
                UIImageView *iv = [[UIImageView alloc] initWithFrame:vc.view.bounds];
                iv.contentMode = UIViewContentModeScaleAspectFit;
                iv.image = image;
                iv.backgroundColor = [UIColor blackColor];
                iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [vc.view addSubview:iv];
                UIBarButtonItem *shareBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareImage:)];
                objc_setAssociatedObject(shareBtn, "img", image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                vc.navigationItem.rightBarButtonItem = shareBtn;
                [self.navigationController pushViewController:vc animated:YES];
            }
        });
    }];
}

- (void)shareImage:(UIBarButtonItem *)sender {
    UIImage *img = objc_getAssociatedObject(sender, "img");
    if (!img) return;
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[img] applicationActivities:nil];
    [self presentViewController:avc animated:YES completion:nil];
}
"""

if 'takeScreenshot {' not in content:
    content = content.replace('@end', screenshot_method + '\n@end')

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
