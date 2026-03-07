import re

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Import Syslog VC
content = content.replace('#import "IdeviceRsdViewController.h"', '#import "IdeviceRsdViewController.h"\n#import "IdeviceSyslogViewController.h"')

# Update row count for section 5
content = content.replace('if (section == 5) return 3;', 'if (section == 5) return 4;')

# Update cell for row logic for section 5
cell_logic_old = r"""    } else if (indexPath.section == 5) {
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

cell_logic_new = r"""    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Sysdiagnoseを取得";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"実行中プロセスを表示";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"スクリーンショットを撮る";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        } else {
            cell.textLabel.text = @"ライブシステムログを表示";
            cell.textLabel.textColor = (mgr.status == IdeviceStatusConnected) ? [ThemeEngine liquidColor] : [UIColor grayColor];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
    }"""

content = content.replace(cell_logic_old, cell_logic_new)

# Update didSelectRow for section 5
did_select_old = r'else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) { if (indexPath.row == 0) [self captureSysdiagnose]; else if (indexPath.row == 1) [self showProcessList]; else [self takeScreenshot]; } }'
did_select_new = r'else if (indexPath.section == 5) { if (mgr.status == IdeviceStatusConnected) { if (indexPath.row == 0) [self captureSysdiagnose]; else if (indexPath.row == 1) [self showProcessList]; else if (indexPath.row == 2) [self takeScreenshot]; else [self.navigationController pushViewController:[[IdeviceSyslogViewController alloc] init] animated:YES]; } }'

content = content.replace(did_select_old, did_select_new)

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
