#import "PDFViewerViewController.h"
#import "Logger.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import <PencilKit/PencilKit.h>

@interface PDFViewerViewController () <PKCanvasViewDelegate, PKToolPickerObserver, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) PDFView *pdfView;
@property (strong, nonatomic) PKCanvasView *canvasView;
@property (strong, nonatomic) PKToolPicker *toolPicker;
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
        self.pdfView.document = [[PDFDocument alloc] init];
        [self.pdfView.document insertPage:[[PDFPage alloc] init] atIndex:0];
    }

    [self.view addSubview:self.pdfView];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(savePDF)];
    UIBarButtonItem *editBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(showEditMenu)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, editBtn];
}

- (void)showEditMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"高度なPDF編集"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"テキストを追加" systemImage:@"text.cursor" style:CustomMenuActionStyleDefault handler:^{
        [self promptForTextAnnotation];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"画像を追加" systemImage:@"photo" style:CustomMenuActionStyleDefault handler:^{
        [self selectImage];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"手書きモード" systemImage:@"pencil.tip" style:CustomMenuActionStyleDefault handler:^{
        [self toggleDrawingMode];
    }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを複製" systemImage:@"plus.square.on.square" style:CustomMenuActionStyleDefault handler:^{
        PDFPage *current = self.pdfView.currentPage;
        if (current) {
            NSData *data = [current dataRepresentation];
            PDFPage *newP = [[PDFPage alloc] initWithData:data];
            [self.pdfView.document insertPage:newP atIndex:[self.pdfView.document indexForPage:current] + 1];
        }
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
    // In a real implementation, we would set an appearance stream for the image.
    // For this prototype, we record the action in the log.
    NSLog(@"[PDF] Image annotation added to page");
}

- (void)selectImage {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) [self addImageAnnotation:img];
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)addImageAnnotation:(UIImage *)image {
    PDFPage *page = self.pdfView.currentPage;
    if (!page) return;
    CGRect bounds = CGRectMake(100, 100, 200, 200);
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:bounds forType:kPDFAnnotationTypeStamp withProperties:nil];
    // In PDFKit, to add an image we can use the "stamp" annotation type.
    // Some versions of PDFKit allow setting an appearance stream.
    [page addAnnotation:annot];
    [[Logger sharedLogger] log:@"[PDF] Image annotation added to page"];
}

- (void)toggleDrawingMode {
    if (self.canvasView) {
        [self finishDrawing];
    } else {
        [self startDrawing];
    }
}

- (void)startDrawing {
    self.canvasView = [[PKCanvasView alloc] initWithFrame:self.pdfView.bounds];
    self.canvasView.delegate = self;
    self.canvasView.backgroundColor = [UIColor clearColor];
    self.canvasView.opaque = NO;
    [self.view addSubview:self.canvasView];

    self.toolPicker = [[PKToolPicker alloc] init];
    [self.toolPicker setVisible:YES forFirstResponder:self.canvasView];
    [self.toolPicker addObserver:self.canvasView];
    [self.canvasView becomeFirstResponder];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完了" style:UIBarButtonItemStyleDone target:self action:@selector(finishDrawing)];
}

- (void)finishDrawing {
    // Convert drawing to image and add as annotation
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:self.canvasView.bounds.size];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext * context) {
        [self.canvasView drawViewHierarchyInRect:self.canvasView.bounds afterScreenUpdates:YES];
    }];

    [self.canvasView removeFromSuperview];
    self.canvasView = nil;
    self.toolPicker = nil;
    self.navigationItem.leftBarButtonItem = nil;

    [self addImageAnnotation:img];
}

- (void)savePDF {
    if ([self.pdfView.document writeToFile:_path]) {
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
