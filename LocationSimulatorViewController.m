#import "LocationSimulatorViewController.h"
#import "extend/location_simulation.h"
#import "ThemeEngine.h"

@interface LocationSimulatorViewController ()
@property (strong, nonatomic) UITextField *latField;
@property (strong, nonatomic) UITextField *longField;
@end

@implementation LocationSimulatorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Location Sim";
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 20;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8]
    ]];

    self.latField = [self createTextFieldWithPlaceholder:@"Latitude (e.g. 35.6895)"];
    self.longField = [self createTextFieldWithPlaceholder:@"Longitude (e.g. 139.6917)"];

    [stack addArrangedSubview:self.latField];
    [stack addArrangedSubview:self.longField];

    UIButton *simBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [simBtn setTitle:@"Simulate Location" forState:UIControlStateNormal];
    [simBtn addTarget:self action:@selector(simulateTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:simBtn];

    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearBtn setTitle:@"Clear Simulation" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [clearBtn addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:clearBtn];
}

- (UITextField *)createTextFieldWithPlaceholder:(NSString *)ph {
    UITextField *tf = [[UITextField alloc] init];
    tf.placeholder = ph;
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.keyboardType = UIKeyboardTypeDecimalPad;
    tf.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    tf.textColor = [UIColor whiteColor];
    return tf;
}

- (void)simulateTapped {
    double lat = [self.latField.text doubleValue];
    double lon = [self.longField.text doubleValue];

    NSString* deviceIP = [[NSUserDefaults standardUserDefaults] stringForKey:@"customTargetIP"];
    if (!deviceIP || deviceIP.length == 0) deviceIP = @"10.7.0.1";

    NSURL* docPathUrl = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString* pairingPath = [docPathUrl URLByAppendingPathComponent:@"pairingFile.plist"].path;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int res = simulate_location([deviceIP UTF8String], lat, lon, [pairingPath UTF8String]);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = (res == IPA_OK) ? @"Location simulation started!" : [NSString stringWithFormat:@"Error: %d", res];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Location Sim" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)clearTapped {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int res = clear_simulated_location();
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *msg = (res == IPA_OK) ? @"Location simulation cleared!" : @"Failed to clear location.";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Location Sim" message:msg preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

@end
