#import "ThemeEngine.h"
#import "PDFViewerViewController.h"

@implementation PDFViewerViewController {
    NSString *_path;
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _path = path; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor mainBackgroundColor];
    self.title = _path.lastPathComponent;

    PDFView *pdfView = [[PDFView alloc] initWithFrame:self.view.bounds];
    pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    pdfView.document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:_path]];
    pdfView.autoScales = YES;
    [self.view addSubview:pdfView];
}

@end
