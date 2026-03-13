import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Update viewDidLoad to manage navigation controller pop gesture
old_view_did_load = """- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"Root" : @"Media";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}"""

new_view_did_load = """- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"Root" : @"Media";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Disable system pop gesture while in subdirectories so our custom swipe works
    [self updatePopGestureState];
}

- (void)updatePopGestureState {
    BOOL isAtRoot = [self.currentPath isEqualToString:@"/"];
    self.navigationController.interactivePopGestureRecognizer.enabled = isAtRoot;
}"""

content = content.replace(old_view_did_load, new_view_did_load)

# 2. Update loadPath to call updatePopGestureState
content = content.replace('self.pathLabel.text = path;\n                [self.tableView reloadData]; [self.spinner stopAnimating];',
                          'self.pathLabel.text = path;\n                [self.tableView reloadData]; [self.spinner stopAnimating];\n                [self updatePopGestureState];')

# 3. Simplify gestureRecognizerShouldBegin
old_should_begin = """- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        // If we are at root, let the navigation controller handle the pop
        if ([self.currentPath isEqualToString:@"/"]) return NO;
        return YES;
    }
    return YES;
}"""

new_should_begin = """- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        // Only trigger our custom back-navigation if NOT at root
        return ![self.currentPath isEqualToString:@"/"];
    }
    return YES;
}"""

content = content.replace(old_should_begin, new_should_begin)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
