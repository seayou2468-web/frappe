import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Update viewDidLoad to include viewDidAppear and updatePopGestureState
old_view_did_load = """- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"System Root" : @"Media Staging";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}"""

new_view_methods = """- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isAfc2 ? @"System Root" : @"Media Staging";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self connectAfc];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updatePopGestureState];
}

- (void)updatePopGestureState {
    BOOL isAtRoot = [self.currentPath isEqualToString:@"/"];
    if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = isAtRoot;
    }
}"""

content = content.replace(old_view_did_load, new_view_methods)

# 2. Add updatePopGestureState call to loadPath dispatch block
content = content.replace('self.pathLabel.text = path;\n                [self.tableView reloadData]; [self.spinner stopAnimating];',
                          'self.pathLabel.text = path;\n                [self.tableView reloadData]; [self.spinner stopAnimating];\n                [self updatePopGestureState];')

# 3. Fix gestureRecognizerShouldBegin logic
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
        // If we are at root, let the system handle it (return NO here so gesture doesn't start)
        return ![self.currentPath isEqualToString:@"/"];
    }
    return YES;
}"""

content = content.replace(old_should_begin, new_should_begin)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
