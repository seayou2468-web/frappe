#import "IdeviceSyslogViewController.h"
#import "IdeviceManager.h"
#import "ThemeEngine.h"

@interface IdeviceSyslogViewController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSMutableArray *logLines;
@end

@implementation IdeviceSyslogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Live Syslog";
    self.view.backgroundColor = [UIColor blackColor];
    self.logLines = [NSMutableArray array];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.backgroundColor = [UIColor blackColor];
    self.textView.textColor = [UIColor greenColor];
    self.textView.font = [UIFont fontWithName:@"Courier" size:12];
    self.textView.editable = NO;
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearLogs)];
    self.navigationItem.rightBarButtonItem = clearBtn;

    __weak typeof(self) weakSelf = self;
    [[IdeviceManager sharedManager] startSyslogCaptureWithCallback:^(NSString *line) {
        [weakSelf appendLogLine:line];
    }];
}

- (void)clearLogs {
    [self.logLines removeAllObjects];
    self.textView.text = @"";
}

- (void)appendLogLine:(NSString *)line {
    [self.logLines addObject:line];
    if (self.logLines.count > 500) [self.logLines removeObjectAtIndex:0];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.textView.text = [self.logLines componentsJoinedByString:@"\n"];
        [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length, 0)];
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[IdeviceManager sharedManager] stopSyslogCapture];
}

@end
