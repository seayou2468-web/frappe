#import "SyslogViewController.h"
#import "JITEnableContext.h"
#import "ThemeEngine.h"

@interface SyslogViewController ()
@property (strong, nonatomic) UITextView *textView;
@property (strong, nonatomic) NSMutableString *logBuffer;
@end

@implementation SyslogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Syslog";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.logBuffer = [NSMutableString string];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.backgroundColor = [UIColor blackColor];
    self.textView.textColor = [UIColor greenColor];
    self.textView.font = [UIFont fontWithName:@"Courier" size:12];
    self.textView.editable = NO;
    [self.view addSubview:self.textView];

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
            if (self.logBuffer.length > 100000) { // Prune buffer if too large
                [self.logBuffer deleteCharactersInRange:NSMakeRange(0, 10000)];
            }
            self.textView.text = self.logBuffer;
            [self.textView scrollRangeToVisible:NSMakeRange(self.logBuffer.length - 1, 1)];
        });
    } onError:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showError:error];
        });
    }];
}

- (void)clearLog {
    self.logBuffer = [NSMutableString string];
    self.textView.text = @"";
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Syslog Error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
