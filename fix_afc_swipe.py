import sys

with open('AfcBrowserViewController.m', 'r') as f:
    content = f.read()

# 1. Update setupUI to add the gesture recognizer
old_setup_ui_end = """        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}"""

new_setup_ui_end = """        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    UIScreenEdgePanGestureRecognizer *swipe = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeBack:)];
    swipe.edges = UIRectEdgeLeft;
    [self.view addGestureRecognizer:swipe];
}"""

content = content.replace(old_setup_ui_end, new_setup_ui_end)

# 2. Add handleSwipeBack method
method_to_add = """- (void)handleSwipeBack:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [self goBack];
    }
}

- (void)goBack {"""

content = content.replace('- (void)goBack {', method_to_add)

with open('AfcBrowserViewController.m', 'w') as f:
    f.write(content)
