import os

file_path = 'WebBrowserViewController.m'
with open(file_path, 'r') as f:
    content = f.read()

# Add notification observer
old_vdl_end = """    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
}"""

new_vdl_end = """    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshUI) name:@"SettingsChanged" object:nil];
}"""
content = content.replace(old_vdl_end, new_vdl_end)

# Add refreshUI method
refresh_method = """
- (void)refreshUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
        self.startPage.backgroundColor = [ThemeEngine mainBackgroundColor];
        [self.bottomMenu setupUI];
        // Other UI updates if needed
    });
}
"""
if '- (void)refreshUI' not in content:
    content = content.replace('- (void)bookmarkCurrentPage', f'{refresh_method}\n- (void)bookmarkCurrentPage')

with open(file_path, 'w') as f:
    f.write(content)
