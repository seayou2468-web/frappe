#import "SyslogViewController.h"
#import "extend/JITEnableContext.h"
#import "ThemeEngine.h"

@interface SyslogViewController ()
@property (strong, nonatomic) UITextView *textView;
@property (strong, nonatomic) NSMutableString *logBuffer;

@end

@implementation SyslogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"System Log";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.logBuffer = [NSMutableString string];

    UIView *container = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, 10, 80)];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [ThemeEngine applyLiquidGlassStyleToView:container cornerRadius:20];
    [self.view addSubview:container];

    self.textView = [[UITextView alloc] initWithFrame:CGRectInset(container.bounds, 10, 10)];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = [UIColor greenColor];
    self.textView.font = [UIFont fontWithName:@"Courier" size:11];
    self.textView.editable = NO;
    [container addSubview:self.textView];

    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearLog)];
    self.navigationItem.rightBarButtonItem = clearBtn;

    [self startLog];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[JITEnableContext shared] stopSyslogRelay];
}

- (void)startLog {
    [[JITEnableContext shared] startSyslogRelayWithHandler:^(NSString *line) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.logBuffer appendFormat:@"%@\n", line];
            if (self.logBuffer.length > 50000) [self.logBuffer deleteCharactersInRange:NSMakeRange(0, 5000)];
            self.textView.text = self.logBuffer;
            [self.textView scrollRangeToVisible:NSMakeRange(self.logBuffer.length - 1, 1)];
        });
    } onError:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Syslog Error: %@", error);
        });
    }];
}

- (void)clearLog {
    [self.logBuffer setString:@""];
    self.textView.text = @"";
}
@end