import sys
import re

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Update setupUI to add Delegate and set edges
old_gesture = 'UIScreenEdgePanGestureRecognizer *swipe = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeBack:)];\n    swipe.edges = UIRectEdgeLeft;\n    [self.view addGestureRecognizer:swipe];'
new_gesture = 'UIScreenEdgePanGestureRecognizer *swipe = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeBack:)];\n    swipe.edges = UIRectEdgeLeft; swipe.delegate = self;\n    [self.view addGestureRecognizer:swipe];'

content = content.replace(old_gesture, new_gesture)

# 2. Add Delegate to interface
content = content.replace('@interface AfcBrowserViewController () <UITableViewDelegate, UITableViewDataSource>',
                          '@interface AfcBrowserViewController () <UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate>')

# 3. Add gestureRecognizerShouldBegin to prioritize directory back over pop
should_begin = """- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        return ![self.currentPath isEqualToString:@"/"];
    }
    return YES;
}

- (void)handleSwipeBack:"""

content = content.replace('- (void)handleSwipeBack:', should_begin)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
