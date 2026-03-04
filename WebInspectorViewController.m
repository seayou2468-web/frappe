#import "WebInspectorViewController.h"
#import "ThemeEngine.h"

@interface WebInspectorViewController ()
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation WebInspectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Webインスペクタ";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Console", @"Source"]];
    self.segmentedControl.selectedSegmentIndex = 1;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segmentedControl;

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11];
    [self.view addSubview:self.textView];

    [self updateView];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    [self updateView];
}

- (void)updateView {
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        self.textView.text = [self.consoleLogs componentsJoinedByString:@"\n\n"];
        self.textView.textColor = [UIColor greenColor];
    } else {
        self.textView.text = self.htmlSource;
        self.textView.textColor = [UIColor whiteColor];
    }
}

@end
