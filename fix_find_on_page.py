import os

file_path = 'WebBrowserViewController.m'
with open(file_path, 'r') as f:
    content = f.read()

# Add promptFindOnPage method
find_method = """
- (void)promptFindOnPage {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ページ内検索" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"検索ワード"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"検索" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *query = alert.textFields[0].text;
        if (query.length > 0) {
            [self.webView findString:query configuration:[[WKFindConfiguration alloc] init] completionHandler:^(WKFindResult *result) {
                if (!result.matchFound) {
                    [[Logger sharedLogger] log:@"[BROWSER] No matches found for search"];
                }
            }];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
"""
if '- (void)promptFindOnPage' not in content:
    content = content.replace('- (void)showUserAgentMenu {', f'{find_method}\n- (void)showUserAgentMenu {{')

# Add to menu
old_menu_item = """    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{ [self handleMenuAction:BottomMenuActionWebShare]; }]];"""
new_menu_item = """    [menu addAction:[CustomMenuAction actionWithTitle:@"ページ内検索" systemImage:@"magnifyingglass" style:CustomMenuActionStyleDefault handler:^{ [self promptFindOnPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを共有" systemImage:@"square.and.arrow.up" style:CustomMenuActionStyleDefault handler:^{ [self handleMenuAction:BottomMenuActionWebShare]; }]];"""
content = content.replace(old_menu_item, new_menu_item)

with open(file_path, 'w') as f:
    f.write(content)
