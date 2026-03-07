import re

with open('IdeviceViewController.m', 'r') as f:
    content = f.read()

# Add viewWillAppear for automatic connection
if '- (void)viewWillAppear:(BOOL)animated {' not in content:
    view_did_load_end = re.search(r'\[self statusChanged\];\n\s+\[\[NSNotificationCenter defaultCenter\] addObserver:self selector:@selector\(statusChanged\) name:@"IdeviceStatusChanged" object:nil\];\n\}', content)
    if not view_did_load_end:
        # Try another pattern
        view_did_load_end = re.search(r'\[self setupUI\];\n\s+\[\[NSNotificationCenter defaultCenter\] addObserver:self selector:@selector\(statusChanged\) name:@"IdeviceStatusChanged" object:nil\];\n\}', content)

    if view_did_load_end:
        insertion_point = view_did_load_end.end()
        new_method = """

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    IdeviceManager *mgr = [IdeviceManager sharedManager];
    if (mgr.status == IdeviceStatusDisconnected && mgr.pairingFilePath.length > 0) {
        [mgr connect];
    }
}"""
        content = content[:insertion_point] + new_method + content[insertion_point:]

with open('IdeviceViewController.m', 'w') as f:
    f.write(content)
