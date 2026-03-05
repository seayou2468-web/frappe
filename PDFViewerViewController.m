#import "PDFViewerViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"

@interface PDFViewerViewController ()
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) PDFView *pdfView;
@end

@implementation PDFViewerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _path = path; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine mainBackgroundColor];
    self.title = _path.lastPathComponent;

    self.pdfView = [[PDFView alloc] initWithFrame:self.view.bounds];
    self.pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.pdfView.autoScales = YES;
    self.pdfView.displayMode = kPDFDisplaySinglePageContinuous;
    self.pdfView.displayDirection = kPDFDisplayDirectionVertical;

    if ([[NSFileManager defaultManager] fileExistsAtPath:_path]) {
        self.pdfView.document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:_path]];
    } else {
        // Create an empty PDF if file does not exist
        self.pdfView.document = [[PDFDocument alloc] init];
        [self.pdfView.document insertPage:[[PDFPage alloc] init] atIndex:0];
    }

    [self.view addSubview:self.pdfView];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(savePDF)];
    UIBarButtonItem *editBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(showEditMenu)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, editBtn];
}

- (void)showEditMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"PDF編集"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"テキストを追加" systemImage:@"text.cursor" style:CustomMenuActionStyleDefault handler:^{
        [self promptForTextAnnotation];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを追加" systemImage:@"plus.circle" style:CustomMenuActionStyleDefault handler:^{
        [self.pdfView.document insertPage:[[PDFPage alloc] init] atIndex:self.pdfView.document.pageCount];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを削除" systemImage:@"minus.circle" style:CustomMenuActionStyleDestructive handler:^{
        if (self.pdfView.document.pageCount > 1) {
            NSInteger idx = [self.pdfView.document indexForPage:self.pdfView.currentPage];
            [self.pdfView.document removePageAtIndex:idx];
        }
    }]];
    [menu showInView:self.view];
}

- (void)promptForTextAnnotation {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"テキスト入力" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields[0].text;
        if (text.length > 0) [self addTextAnnotation:text];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addTextAnnotation:(NSString *)text {
    PDFPage *page = self.pdfView.currentPage;
    if (!page) return;

    CGRect bounds = CGRectMake(50, [page boundsForBox:kPDFDisplayBoxMediaBox].size.height - 100, 200, 50);
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:bounds forType:kPDFAnnotationTypeFreeText withProperties:nil];
    annot.contents = text;
    annot.font = [UIFont systemFontOfSize:18];
    annot.fontColor = [UIColor redColor];
    [page addAnnotation:annot];
}

- (void)savePDF {
    if ([self.pdfView.document writeToFile:_path]) {
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
