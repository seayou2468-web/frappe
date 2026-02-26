#import "TextEditorViewController.h"
#import "ThemeEngine.h"

@interface TextEditorViewController ()
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) UITextView *textView;

@implementation TextEditorViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = path;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.path.lastPathComponent;
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = [UIColor whiteColor];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:12];
    [self.view addSubview:self.textView];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveText)];
    self.navigationItem.rightBarButtonItem = saveBtn;

    [self loadText];
}

- (void)loadText {
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:self.path encoding:NSUTF8StringEncoding error:&error];
    if (content) self.textView.text = content;
}

- (void)saveText {
    NSError *error;
    [self.textView.text writeToFile:self.path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!error) [self.navigationController popViewControllerAnimated:YES];
}

@end