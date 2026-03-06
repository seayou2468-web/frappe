#import "PDFViewerViewController.h"
#import "Logger.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import <PencilKit/PencilKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AdvancedAnnotation : PDFAnnotation
@property (nonatomic, strong) UIImage *overlayImage;
@property (nonatomic, assign) CGFloat rotationAngle;
@property (nonatomic, assign) BOOL isTable;
@property (nonatomic, assign) NSInteger rows;
@property (nonatomic, assign) NSInteger cols;
@end

@implementation AdvancedAnnotation
- (void)drawWithBox:(PDFDisplayBox)box inContext:(CGContextRef)context {
    // We don t call super here if we want total control, but for standard types it s okay.
    if (![self.type isEqualToString:PDFAnnotationSubtypeStamp] && !self.isTable) {
        [super drawWithBox:box inContext:context];
    }

    CGContextSaveGState(context);
    CGRect rect = self.bounds;

    // Apply rotation around the center of the annotation
    CGContextTranslateCTM(context, rect.origin.x + rect.size.width/2, rect.origin.y + rect.size.height/2);
    CGContextRotateCTM(context, self.rotationAngle * M_PI / 180.0);
    CGContextTranslateCTM(context, -rect.size.width/2, -rect.size.height/2);

    if (self.overlayImage) {
        UIGraphicsPushContext(context);
        [self.overlayImage drawInRect:CGRectMake(0, 0, rect.size.width, rect.size.height)];
        UIGraphicsPopContext();
    } else if (self.isTable) {
        CGContextSetStrokeColorWithColor(context, [UIColor blackColor].CGColor);
        CGContextSetLineWidth(context, 1.0);
        for (int i = 0; i <= self.rows; i++) {
            CGFloat y = i * (rect.size.height / self.rows);
            CGContextMoveToPoint(context, 0, y);
            CGContextAddLineToPoint(context, rect.size.width, y);
        }
        for (int j = 0; j <= self.cols; j++) {
            CGFloat x = j * (rect.size.width / self.cols);
            CGContextMoveToPoint(context, x, 0);
            CGContextAddLineToPoint(context, x, rect.size.height);
        }
        CGContextStrokePath(context);
    }

    CGContextRestoreGState(context);
}
@end

@interface PDFViewerViewController () <PKCanvasViewDelegate, PKToolPickerObserver, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIGestureRecognizerDelegate, UIDocumentPickerDelegate>
@property (strong, nonatomic) NSString *path;
@property (strong, nonatomic) PDFView *pdfView;
@property (strong, nonatomic) PKCanvasView *canvasView;
@property (strong, nonatomic) PKToolPicker *toolPicker;
@property (strong, nonatomic) PDFAnnotation *selectedAnnotation;
@property (strong, nonatomic) UIView *snapGuideH;
@property (strong, nonatomic) UIView *snapGuideV;
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
    [self loadDocument];
    [self.view addSubview:self.pdfView];

    [self setupSnapGuides];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(savePDF)];
    UIBarButtonItem *editBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(showEditMenu)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, editBtn];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.pdfView addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.pdfView addGestureRecognizer:pan];
}

- (void)setupSnapGuides {
    self.snapGuideH = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 1)];
    self.snapGuideH.backgroundColor = [UIColor systemCyanColor];
    self.snapGuideH.hidden = YES;
    [self.view addSubview:self.snapGuideH];

    self.snapGuideV = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, self.view.bounds.size.height)];
    self.snapGuideV.backgroundColor = [UIColor systemCyanColor];
    self.snapGuideV.hidden = YES;
    [self.view addSubview:self.snapGuideV];
}

- (void)loadDocument {
    if ([[NSFileManager defaultManager] fileExistsAtPath:_path]) { self.pdfView.document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:_path]]; }
    else { self.pdfView.document = [[PDFDocument alloc] init]; [self.pdfView.document insertPage:[[PDFPage alloc] init] atIndex:0]; }
}

- (void)showEditMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"PowerPoint-like PDF編集"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"テキスト挿入" systemImage:@"text.cursor" style:CustomMenuActionStyleDefault handler:^{ [self promptForText]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"画像挿入" systemImage:@"photo" style:CustomMenuActionStyleDefault handler:^{ [self selectImage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"図形・表挿入" systemImage:@"square.on.circle" style:CustomMenuActionStyleDefault handler:^{ [self showShapeMenu]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"リンク・添付" systemImage:@"link" style:CustomMenuActionStyleDefault handler:^{ [self showLinkFileMenu]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"手書き" systemImage:@"pencil.tip" style:CustomMenuActionStyleDefault handler:^{ [self toggleDrawingMode]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページ操作" systemImage:@"doc.on.doc" style:CustomMenuActionStyleDefault handler:^{ [self showPageMenu]; }]];
    if (self.selectedAnnotation) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"選択中の編集" systemImage:@"slider.horizontal.3" style:CustomMenuActionStyleDefault handler:^{ [self showAnnotationEditor]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [self deleteSelectedAnnotation]; }]];
    }
    [menu showInView:self.view];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.pdfView];
    PDFPage *page = [self.pdfView pageForPoint:point nearest:YES];
    CGPoint pagePoint = [self.pdfView convertPoint:point toPage:page];
    self.selectedAnnotation = [page annotationAtPoint:pagePoint];
    if (self.selectedAnnotation) [[Logger sharedLogger] log:@"[PDF] Element selected"];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.pdfView];
    PDFPage *page = [self.pdfView pageForPoint:point nearest:YES];
    CGPoint pagePoint = [self.pdfView convertPoint:point toPage:page];
    static CGPoint startPagePoint; static CGRect startBounds;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.selectedAnnotation = [page annotationAtPoint:pagePoint];
        if (self.selectedAnnotation) { startPagePoint = pagePoint; startBounds = self.selectedAnnotation.bounds; }
    } else if (gesture.state == UIGestureRecognizerStateChanged && self.selectedAnnotation) {
        CGFloat dx = pagePoint.x - startPagePoint.x; CGFloat dy = pagePoint.y - startPagePoint.y;
        CGRect newBounds = startBounds; newBounds.origin.x += dx; newBounds.origin.y += dy;

        CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxMediaBox]; CGFloat threshold = 12.0;
        BOOL snappedH = NO; BOOL snappedV = NO;

        // Horizontal Center Snap
        if (fabs((newBounds.origin.x + newBounds.size.width/2) - pageBounds.size.width/2) < threshold) {
            newBounds.origin.x = pageBounds.size.width/2 - newBounds.size.width/2; snappedH = YES;
        }
        // Vertical Center Snap
        if (fabs((newBounds.origin.y + newBounds.size.height/2) - pageBounds.size.height/2) < threshold) {
            newBounds.origin.y = pageBounds.size.height/2 - newBounds.size.height/2; snappedV = YES;
        }

        self.snapGuideV.hidden = !snappedH;
        if (snappedH) {
            CGPoint viewCenter = [self.pdfView convertPoint:CGPointMake(pageBounds.size.width/2, pageBounds.size.height/2) fromPage:page];
            self.snapGuideV.frame = CGRectMake(viewCenter.x, 0, 1, self.view.bounds.size.height);
        }
        self.snapGuideH.hidden = !snappedV;
        if (snappedV) {
            CGPoint viewCenter = [self.pdfView convertPoint:CGPointMake(pageBounds.size.width/2, pageBounds.size.height/2) fromPage:page];
            self.snapGuideH.frame = CGRectMake(0, viewCenter.y, self.view.bounds.size.width, 1);
        }

        self.selectedAnnotation.bounds = newBounds; [self.pdfView setNeedsDisplay];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        self.snapGuideH.hidden = YES; self.snapGuideV.hidden = YES;
    }
}

- (void)showShapeMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"図形・表"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"長方形" systemImage:@"square" style:CustomMenuActionStyleDefault handler:^{ [self addShape:PDFAnnotationSubtypeSquare]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"円" systemImage:@"circle" style:CustomMenuActionStyleDefault handler:^{ [self addShape:PDFAnnotationSubtypeCircle]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"線" systemImage:@"line.diagonal" style:CustomMenuActionStyleDefault handler:^{ [self addShape:PDFAnnotationSubtypeLine]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"表 (3x3)" systemImage:@"tablecells" style:CustomMenuActionStyleDefault handler:^{ [self addTableWithRows:3 cols:3]; }]];
    [menu showInView:self.view];
}

- (void)addShape:(PDFAnnotationSubtype)subtype {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    CGRect bounds = CGRectMake(100, 100, 150, 100);
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:bounds forType:subtype withProperties:nil];
    annot.color = [UIColor blueColor]; [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)addTableWithRows:(NSInteger)rows cols:(NSInteger)cols {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    AdvancedAnnotation *annot = [[AdvancedAnnotation alloc] initWithBounds:CGRectMake(100, 100, 300, 200) forType:PDFAnnotationSubtypeStamp withProperties:nil];
    annot.isTable = YES; annot.rows = rows; annot.cols = cols;
    [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)showLinkFileMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"リンク・添付"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"Webリンク" systemImage:@"link" style:CustomMenuActionStyleDefault handler:^{ [self promptForLink]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ファイル添付" systemImage:@"paperclip" style:CustomMenuActionStyleDefault handler:^{ [self selectFileToAttach]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"動画リンク" systemImage:@"video" style:CustomMenuActionStyleDefault handler:^{ [self promptForMovie]; }]];
    [menu showInView:self.view];
}

- (void)promptForText {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"テキスト挿入" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"追加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self addText:alert.textFields[0].text]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addText:(NSString *)text {
    PDFPage *page = self.pdfView.currentPage; if (!page || text.length == 0) return;
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:CGRectMake(100, 100, 200, 50) forType:PDFAnnotationSubtypeFreeText withProperties:nil];
    annot.contents = text; annot.font = [UIFont systemFontOfSize:20]; annot.fontColor = [UIColor blackColor];
    [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)promptForLink {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"リンク挿入" message:@"URLを入力" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = @"https://"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"追加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self addLink:alert.textFields[0].text]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addLink:(NSString *)urlStr {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:CGRectMake(100, 100, 100, 30) forType:PDFAnnotationSubtypeLink withProperties:nil];
    annot.URL = [NSURL URLWithString:urlStr]; [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)selectFileToAttach {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (url) [self addFileAttachment:url];
}

- (void)addFileAttachment:(NSURL *)fileURL {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:CGRectMake(150, 150, 32, 32) forType:PDFAnnotationSubtypeFileAttachment withProperties:nil];
    annot.contents = [fileURL lastPathComponent]; [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)promptForMovie {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"動画埋め込み" message:@"動画URLを入力" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"追加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self addMovie:alert.textFields[0].text]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addMovie:(NSString *)path {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:CGRectMake(100, 100, 200, 150) forType:PDFAnnotationSubtypeLink withProperties:nil];
    annot.contents = [NSString stringWithFormat:@"Video: %@", path]; [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)selectImage {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init]; picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage]; if (img) [self addImage:img]; [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)addImage:(UIImage *)image {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    AdvancedAnnotation *annot = [[AdvancedAnnotation alloc] initWithBounds:CGRectMake(100, 100, 200, 200) forType:PDFAnnotationSubtypeStamp withProperties:nil];
    annot.overlayImage = image; [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)showAnnotationEditor {
    if (!self.selectedAnnotation) return;
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"プロパティ編集"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"回転 (+45°)" systemImage:@"rotate.right" style:CustomMenuActionStyleDefault handler:^{
        if ([self.selectedAnnotation isKindOfClass:[AdvancedAnnotation class]]) {
            ((AdvancedAnnotation *)self.selectedAnnotation).rotationAngle += 45;
            [self.pdfView setNeedsDisplay];
        }
    }]];
    if ([self.selectedAnnotation.type isEqualToString:PDFAnnotationSubtypeFreeText]) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"文字サイズ変更" systemImage:@"textformat.size" style:CustomMenuActionStyleDefault handler:^{ [self promptForFontSize]; }]];
    }
    [menu addAction:[CustomMenuAction actionWithTitle:@"位置指定" systemImage:@"arrow.up.and.down.and.arrow.left.and.right" style:CustomMenuActionStyleDefault handler:^{ [self promptForPosition]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"最前面へ" systemImage:@"arrow.up.square" style:CustomMenuActionStyleDefault handler:^{
        PDFPage *p = self.selectedAnnotation.page; [p removeAnnotation:self.selectedAnnotation]; [p addAnnotation:self.selectedAnnotation]; [self.pdfView setNeedsDisplay];
    }]];
    [menu showInView:self.view];
}

- (void)promptForFontSize {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"フォントサイズ" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.keyboardType = UIKeyboardTypeNumberPad; tf.text = @"20"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"適用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CGFloat size = [alert.textFields[0].text floatValue];
        if (size > 0) { self.selectedAnnotation.font = [UIFont systemFontOfSize:size]; [self.pdfView setNeedsDisplay]; }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForPosition {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"位置設定 (x,y)" message:@"コンマ区切り" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { CGRect b = self.selectedAnnotation.bounds; tf.text = [NSString stringWithFormat:@"%.0f,%.0f", b.origin.x, b.origin.y]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"移動" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *parts = [alert.textFields[0].text componentsSeparatedByString:@","];
        if (parts.count == 2) { CGRect b = self.selectedAnnotation.bounds; b.origin.x = [parts[0] floatValue]; b.origin.y = [parts[1] floatValue]; self.selectedAnnotation.bounds = b; [self.pdfView setNeedsDisplay]; }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteSelectedAnnotation { if (self.selectedAnnotation) { [self.selectedAnnotation.page removeAnnotation:self.selectedAnnotation]; self.selectedAnnotation = nil; [self.pdfView setNeedsDisplay]; } }

- (void)showPageMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"ページ操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを複製" systemImage:@"plus.square.on.square" style:CustomMenuActionStyleDefault handler:^{ [self duplicateCurrentPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [self deleteCurrentPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページ回転 (+90°)" systemImage:@"rotate.right" style:CustomMenuActionStyleDefault handler:^{ [self rotateCurrentPage]; }]];
    [menu showInView:self.view];
}

- (void)duplicateCurrentPage {
    PDFPage *current = self.pdfView.currentPage; if (current) {
        NSData *data = [current dataRepresentation]; PDFDocument *tempDoc = [[PDFDocument alloc] initWithData:data];
        if (tempDoc.pageCount > 0) { [self.pdfView.document insertPage:[tempDoc pageAtIndex:0] atIndex:[self.pdfView.document indexForPage:current] + 1]; [self.pdfView setNeedsDisplay]; }
    }
}

- (void)deleteCurrentPage { if (self.pdfView.document.pageCount > 1) { [self.pdfView.document removePageAtIndex:[self.pdfView.document indexForPage:self.pdfView.currentPage]]; [self.pdfView setNeedsDisplay]; } }

- (void)rotateCurrentPage { PDFPage *page = self.pdfView.currentPage; if (page) { page.rotation = (page.rotation + 90) % 360; [self.pdfView setNeedsDisplay]; } }

- (void)toggleDrawingMode { if (self.canvasView) [self finishDrawing]; else [self startDrawing]; }

- (void)startDrawing {
    self.canvasView = [[PKCanvasView alloc] initWithFrame:self.pdfView.bounds]; self.canvasView.delegate = self; self.canvasView.backgroundColor = [UIColor clearColor]; self.canvasView.opaque = NO; [self.view addSubview:self.canvasView];
    if (@available(iOS 13.0, *)) { self.toolPicker = [[PKToolPicker alloc] init]; [self.toolPicker setVisible:YES forFirstResponder:self.canvasView]; [self.toolPicker addObserver:self.canvasView]; [self.canvasView becomeFirstResponder]; }
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完了" style:UIBarButtonItemStylePlain target:self action:@selector(finishDrawing)];
}

- (void)finishDrawing {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:self.canvasView.bounds.size];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext * context) { [self.canvasView drawViewHierarchyInRect:self.canvasView.bounds afterScreenUpdates:YES]; }];
    [self.canvasView removeFromSuperview]; self.canvasView = nil; self.toolPicker = nil; self.navigationItem.leftBarButtonItem = nil; [self addImage:img];
}

- (void)savePDF { if ([self.pdfView.document writeToFile:_path]) { [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess]; [self.navigationController popViewControllerAnimated:YES]; } }

@end