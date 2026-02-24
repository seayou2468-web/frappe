#import "TextEditorViewController.h"

@interface TextEditorViewController ()
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) UITextView *textView;
@end

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
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = self.path.lastPathComponent;

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.font = [UIFont fontWithName:@"Menlo" size:12];
    [self.view addSubview:self.textView];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveFile)];
    self.navigationItem.rightBarButtonItem = saveBtn;

    [self loadFile];
}

- (void)loadFile {
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:self.path encoding:NSUTF8StringEncoding error:&error];
    if (content) {
        self.textView.text = content;
    } else {
        self.textView.text = @"Error loading file or binary content.";
    }
}

- (void)saveFile {
    NSError *error;
    [self.textView.text writeToFile:self.path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!error) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
