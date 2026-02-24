#import "HexEditorViewController.h"

@interface HexEditorViewController ()
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) UITextView *textView;
@end

@implementation HexEditorViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _path = path; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = [NSString stringWithFormat:@"Hex: %@", self.path.lastPathComponent];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.font = [UIFont fontWithName:@"Courier" size:12];
    self.textView.editable = NO;
    [self.view addSubview:self.textView];

    [self loadHex];
}

- (void)loadHex {
    NSData *data = [NSData dataWithContentsOfFile:self.path];
    if (!data) return;

    NSMutableString *hexString = [NSMutableString string];
    const unsigned char *bytes = [data bytes];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hexString appendFormat:@"%02X ", bytes[i]];
        if ((i + 1) % 16 == 0) [hexString appendString:@"\n"];
    }
    self.textView.text = hexString;
}

@end
