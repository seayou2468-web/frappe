#import "LogViewerViewController.h"
#import "ThemeEngine.h"
#import "Logger.h"

@interface LogViewerViewController ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation LogViewerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"システムログ";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.backgroundColor = [UIColor blackColor];
    self.textView.textColor = [UIColor greenColor];
    self.textView.font = [UIFont fontWithName:@"Courier" size:12];
    self.textView.editable = NO;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];

    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadLogs)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadLogs) name:@"NewLogAdded" object:nil];

    [self loadLogs];
}

- (void)loadLogs {
    NSMutableString *logs = [NSMutableString string];
    [logs appendString:@"--- SYSTEM PATHS ---\n"];
    [logs appendFormat:@"Home: %@\n", NSHomeDirectory()];
    [logs appendFormat:@"Docs: %@\n", [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]];
    [logs appendString:@"\n--- APPLICATION LOGS ---\n"];

    for (NSString *log in [Logger sharedLogger].logs) {
        [logs appendFormat:@"%@\n", log];
    }

    self.textView.text = logs;
    [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length - 1, 1)];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
