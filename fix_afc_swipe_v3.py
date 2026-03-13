import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# Make sure we don't interfere with the system navigation controller pop if at root
# Use interactivePopGestureRecognizer check

new_methods = """- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        // If we are at root, let the navigation controller handle the pop
        if ([self.currentPath isEqualToString:@"/"]) return NO;
        return YES;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]] &&
        [otherGestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

- (void)handleSwipeBack:"""

content = content.replace('- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {\n    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {\n        return ![self.currentPath isEqualToString:@"/"];\n    }\n    return YES;\n}\n\n- (void)handleSwipeBack:', new_methods)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
