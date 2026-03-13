import sys
import re

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Fix setupUI to use constraints and avoid overlap
old_setup_ui = re.search(r'- \(void\)setupUI \{.*?\}', content, re.DOTALL).group(0)
new_setup_ui = """- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self; self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [self.view addSubview:self.tableView];
    [ThemeEngine applyGlassStyleToView:self.tableView cornerRadius:0];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.spinner.color = [UIColor whiteColor];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}"""
content = content.replace(old_setup_ui, new_setup_ui)

# 2. Fix isDir check logic in loadPath
old_is_dir_logic = """                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && strcmp(info.st_ifmt, "S_IFDIR") == 0) isDir = YES;
                    afc_file_info_free(&info);
                } else { idevice_error_free(e2); }"""

new_is_dir_logic = """                BOOL isDir = NO;
                if (!e2) {
                    if (info.st_ifmt && (strcmp(info.st_ifmt, "S_IFDIR") == 0 || strcmp(info.st_ifmt, "directory") == 0)) isDir = YES;
                    afc_file_info_free(&info);
                } else {
                    idevice_error_free(e2);
                    // Heuristic: if no extension, might be a dir
                    if (![name containsString:@"."]) isDir = YES;
                }"""
content = content.replace(old_is_dir_logic, new_is_dir_logic)

# 3. Ensure navigation updates currentPath properly in didSelectRowAtIndexPath
old_did_select = re.search(r'- \(void\)tableView:\(UITableView \*\)tableView didSelectRowAtIndexPath:\(NSIndexPath \*\)indexPath \{.*?\}', content, re.DOTALL).group(0)
new_did_select = """- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    if ([item[@"isDir"] boolValue]) {
        NSString *name = item[@"name"];
        NSString *newPath;
        if ([self.currentPath isEqualToString:@"/"]) {
            newPath = [@"/" stringByAppendingString:name];
        } else {
            newPath = [self.currentPath stringByAppendingPathComponent:name];
        }
        [self loadPath:newPath];
    }
}"""
content = content.replace(old_did_select, new_did_select)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
