import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# Apply Glass Style to TableView and Spinner
content = content.replace('[self.view addSubview:self.tableView];',
                          '[self.view addSubview:self.tableView];\n    [ThemeEngine applyGlassStyleToView:self.tableView cornerRadius:0];')

content = content.replace('self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];',
                          'self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];\n    self.spinner.color = [UIColor whiteColor];')

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
