import os

file_path = 'WebBrowserViewController.m'
with open(file_path, 'r') as f:
    content = f.read()

# Add imports
imports = '#import "WebHistoryManager.h"\n#import "WebHistoryViewController.h"'
if '#import "WebHistoryManager.h"' not in content:
    content = content.replace('#import "CookieEditorViewController.h"', f'#import "CookieEditorViewController.h"\n{imports}')

# Record history in didFinishNavigation
old_history_logic = """    self.urlField.text = webView.URL.absoluteString;
    self.startPage.hidden = (webView.URL != nil && ![webView.URL.absoluteString isEqualToString:@"about:blank"]);
}"""

new_history_logic = """    self.urlField.text = webView.URL.absoluteString;
    self.startPage.hidden = (webView.URL != nil && ![webView.URL.absoluteString isEqualToString:@"about:blank"]);
    if (webView.URL && ![webView.URL.absoluteString isEqualToString:@"about:blank"]) {
        [[WebHistoryManager sharedManager] addHistoryEntryWithTitle:webView.title url:webView.URL.absoluteString];
    }
}"""
content = content.replace(old_history_logic, new_history_logic)

# Add showHistory method
history_method = """
- (void)showHistory {
    WebHistoryViewController *vc = [[WebHistoryViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    vc.onUrlSelected = ^(NSString *url) {
        [weakSelf.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
    };
    [self.navigationController pushViewController:vc animated:YES];
}
"""
if '- (void)showHistory' not in content:
    content = content.replace('- (void)showBrowserOthersMenu {', f'{history_method}\n- (void)showBrowserOthersMenu {{')

# Add to menu
old_menu_item = """    [menu addAction:[CustomMenuAction actionWithTitle:@"Cookieの管理" systemImage:@"lock.shield" style:CustomMenuActionStyleDefault handler:^{ [self showCookieEditor]; }]];"""
new_menu_item = """    [menu addAction:[CustomMenuAction actionWithTitle:@"履歴" systemImage:@"clock" style:CustomMenuActionStyleDefault handler:^{ [self showHistory]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"Cookieの管理" systemImage:@"lock.shield" style:CustomMenuActionStyleDefault handler:^{ [self showCookieEditor]; }]];"""
content = content.replace(old_menu_item, new_menu_item)

with open(file_path, 'w') as f:
    f.write(content)
