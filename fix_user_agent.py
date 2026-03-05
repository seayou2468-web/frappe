import os

file_path = 'WebBrowserViewController.m'
with open(file_path, 'r') as f:
    content = f.read()

# Add showUserAgentMenu method
ua_method = """
- (void)showUserAgentMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"User-Agent設定"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"モバイル (デフォルト)" systemImage:@"iphone" style:CustomMenuActionStyleDefault handler:^{
        [self applyUserAgent:NO];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"デスクトップ" systemImage:@"desktopcomputer" style:CustomMenuActionStyleDefault handler:^{
        [self applyUserAgent:YES];
    }]];
    [menu showInView:self.view];
}

- (void)applyUserAgent:(BOOL)desktop {
    NSString *ua = desktop ? @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15" : nil;
    self.webView.customUserAgent = ua;
    [self.webView reload];
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[BROWSER] User-Agent changed to: %@", desktop ? @"Desktop" : @"Mobile"]];
}
"""
if '- (void)showUserAgentMenu' not in content:
    content = content.replace('- (void)showHistory {', f'{ua_method}\n- (void)showHistory {{')

# Add to menu
old_menu_item = """    [menu addAction:[CustomMenuAction actionWithTitle:@"履歴" systemImage:@"clock" style:CustomMenuActionStyleDefault handler:^{ [self showHistory]; }]];"""
new_menu_item = """    [menu addAction:[CustomMenuAction actionWithTitle:@"履歴" systemImage:@"clock" style:CustomMenuActionStyleDefault handler:^{ [self showHistory]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"User-Agent切替" systemImage:@"person.crop.circle.badge.questionmark" style:CustomMenuActionStyleDefault handler:^{ [self showUserAgentMenu]; }]];"""
content = content.replace(old_menu_item, new_menu_item)

with open(file_path, 'w') as f:
    f.write(content)
