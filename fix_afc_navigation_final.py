import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Update viewDidAppear and add viewWillDisappear
old_view_methods = """- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updatePopGestureState];
}

- (void)updatePopGestureState {
    BOOL isAtRoot = [self.currentPath isEqualToString:@"/"];
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = isAtRoot;
    }
}"""

new_view_methods = """- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updatePopGestureState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Always restore system pop gesture when leaving
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    }
}

- (void)updatePopGestureState {
    BOOL isAtRoot = [self.currentPath isEqualToString:@"/"];
    if (self.navigationController.interactivePopGestureRecognizer) {
        // Disable system back-pop gesture when deep in folders so our custom one can work
        self.navigationController.interactivePopGestureRecognizer.enabled = isAtRoot;
    }
}"""

content = content.replace(old_view_methods, new_view_methods)

# 2. Refine goBack to pop if at root (for the button)
old_goback = """- (void)goBack {
    if ([self.currentPath isEqualToString:@"/"]) return;
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:@"."]) parent = @"/";
    [self loadPath:parent];
}"""

new_goback = """- (void)goBack {
    if ([self.currentPath isEqualToString:@"/"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSString *parent = [self.currentPath stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:@"."]) parent = @"/";

    // Add a simple transition effect for "folder back" if desired,
    // but just loading the path is standard for this app.
    [self loadPath:parent];
}"""

content = content.replace(old_goback, new_goback)

# 3. Add haptic feedback to swipe back for better feel
old_swipe_handler = """- (void)handleSwipeBack:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self goBack];
    }
}"""

new_swipe_handler = """- (void)handleSwipeBack:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen impactOccurred];
        [self goBack];
    }
}"""

content = content.replace(old_swipe_handler, new_swipe_handler)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
