import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# Add property for custom gesture
if '@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *customSwipeGesture;' not in content:
    content = content.replace('@property (nonatomic, strong) UIActivityIndicatorView *spinner;',
                              '@property (nonatomic, strong) UIActivityIndicatorView *spinner;\n@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *customSwipeGesture;')

# Assign the gesture in setupUI
content = content.replace('UIScreenEdgePanGestureRecognizer *swipe = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeBack:)];',
                          'self.customSwipeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeBack:)];')
content = content.replace('swipe.edges = UIRectEdgeLeft; swipe.delegate = self;',
                          'self.customSwipeGesture.edges = UIRectEdgeLeft; self.customSwipeGesture.delegate = self;')
content = content.replace('[self.view addGestureRecognizer:swipe];',
                          '[self.view addGestureRecognizer:self.customSwipeGesture];')

# Update gestureRecognizerShouldBegin
old_should_begin = """- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        // Only trigger our custom back-navigation if NOT at root
        return ![self.currentPath isEqualToString:@"/"];
    }
    return YES;
}"""

new_should_begin = """- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.customSwipeGesture) {
        return ![self.currentPath isEqualToString:@"/"];
    }
    return YES;
}"""

content = content.replace(old_should_begin, new_should_begin)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
