import sys

with open('WebBrowserViewController.m', 'r') as f:
    content = f.read()

# Add handleLongPress if missing (it was missing from last check)
handle_lp = """
- (void)handleLongPress:(UILongPressGestureRecognizer *)lp {
    if (lp.state != UIGestureRecognizerStateBegan) return;

    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"ダウンロード"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"現在のページを保存" systemImage:@"arrow.down.doc" style:CustomMenuActionStyleDefault handler:^{
        NSString *downloadsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Downloads"];
        [[NSFileManager defaultManager] createDirectoryAtPath:downloadsPath withIntermediateDirectories:YES attributes:nil error:nil];
        [[DownloadManager sharedManager] downloadFileAtURL:self.webView.URL toPath:downloadsPath];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ダウンロード一覧を表示" systemImage:@"list.bullet" style:CustomMenuActionStyleDefault handler:^{
        DownloadsViewController *vc = [[DownloadsViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [menu showInView:self.view];
}
"""

if 'handleLongPress' not in content:
    content = content.replace('@end', handle_lp + '\n@end')

with open('WebBrowserViewController.m', 'w') as f:
    f.write(content)
