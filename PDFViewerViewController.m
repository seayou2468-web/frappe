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
    if (![self.type isEqualToString:PDFAnnotationSubtypeStamp] && !self.isTable) {
        [super drawWithBox:box inContext:context];
    }
    CGContextSaveGState(context);
    CGRect rect = self.bounds;
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
@property (strong, nonatomic) UIView *selectionOverlay;
@property (strong, nonatomic) UIView *gridView;
@property (assign, nonatomic) BOOL gridEnabled;

- (void)setupSnapGuides;
- (void)setupSelectionOverlay;
- (void)updateSelectionUI;
- (void)setupGridView;
- (void)toggleGrid;
- (void)showEditMenu;
- (void)showShapeMenu;
- (void)showLinkFileMenu;
- (void)showAnnotationEditor;
- (void)showColorPicker;
- (void)showPageMenu;
- (void)showTemplateMenu;
- (void)showAdvancedProperties;
- (void)showAlignmentMenu;
- (void)showTextAlignmentMenu;
- (void)showImageFilters;
- (void)promptForText;
- (void)promptForFontSize;
- (void)promptForPosition;
- (void)promptForThickness;
- (void)promptForOpacity;
- (void)promptForTextContent;
- (void)selectImage;
- (void)selectFileToAttach;
- (void)togglePresenterMode;
- (void)savePDF;
@end

@implementation PDFViewerViewController


- (void)setupGridView {
    self.gridView = [[UIView alloc] initWithFrame:self.pdfView.bounds];
    self.gridView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.gridView.userInteractionEnabled = NO;
    self.gridView.hidden = YES;
    self.gridView.alpha = 0.2;
    [self.pdfView addSubview:self.gridView];

    // iOS 17+: UIGraphicsImageRenderer
    UIGraphicsImageRenderer *_gridRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)];
    UIImage *img = [_gridRenderer imageWithActions:^(UIGraphicsImageRendererContext *_rc) {
        CGContextRef ctx = _rc.CGContext;
        CGContextSetStrokeColorWithColor(ctx, [UIColor systemGrayColor].CGColor);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextMoveToPoint(ctx, 0, 0); CGContextAddLineToPoint(ctx, 40, 0);
        CGContextMoveToPoint(ctx, 0, 0); CGContextAddLineToPoint(ctx, 0, 40);
        CGContextStrokePath(ctx);
    }];
    self.gridView.backgroundColor = [UIColor colorWithPatternImage:img];
}

- (void)toggleGrid {
    self.gridEnabled = !self.gridEnabled;
    self.gridView.hidden = !self.gridEnabled;
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _path = path; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine bg];
    self.title = _path.lastPathComponent;

    self.pdfView = [[PDFView alloc] initWithFrame:self.view.bounds];
    self.pdfView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.pdfView.autoScales = YES;
    self.pdfView.displayMode = kPDFDisplaySinglePageContinuous;
    [self loadDocument];
    [self.view addSubview:self.pdfView];

    [self setupSnapGuides];
    [self setupSelectionOverlay];

    [self setupGridView];

    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(savePDF)];
    UIBarButtonItem *editBtn = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"pencil"] style:UIBarButtonItemStylePlain target:self action:@selector(showEditMenu)];


    self.navigationItem.rightBarButtonItems = @[saveBtn, editBtn];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.pdfView addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.pdfView addGestureRecognizer:pan];
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    pinch.delegate = self;
    [self.pdfView addGestureRecognizer:pinch];
    UIRotationGestureRecognizer *rotate = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotate:)];
    rotate.delegate = self;
    [self.pdfView addGestureRecognizer:rotate];
}





- (void)setupSelectionOverlay {
    self.selectionOverlay = [[UIView alloc] initWithFrame:CGRectZero];
    self.selectionOverlay.layer.borderColor = [UIColor systemBlueColor].CGColor;
    self.selectionOverlay.layer.borderWidth = 2.0;
    self.selectionOverlay.userInteractionEnabled = NO;
    self.selectionOverlay.hidden = YES;
    [self.pdfView addSubview:self.selectionOverlay];
}

- (void)updateSelectionUI {
    if (!self.selectedAnnotation) { self.selectionOverlay.hidden = YES; return; }
    PDFPage *page = self.selectedAnnotation.page;
    CGRect pageBounds = self.selectedAnnotation.bounds;
    CGRect viewRect = [self.pdfView convertRect:pageBounds fromPage:page];
    self.selectionOverlay.frame = viewRect;
    self.selectionOverlay.hidden = NO;
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
    [menu addAction:[CustomMenuAction actionWithTitle:@"グリッド表示切替" systemImage:@"grid" style:CustomMenuActionStyleDefault handler:^{ [self toggleGrid]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"プレゼンテーション開始" systemImage:@"play.tv" style:CustomMenuActionStyleDefault handler:^{ [self togglePresenterMode]; }]];
    if (self.selectedAnnotation) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"選択中の編集" systemImage:@"slider.horizontal.3" style:CustomMenuActionStyleDefault handler:^{ [self showAnnotationEditor]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"色変更" systemImage:@"paintpalette" style:CustomMenuActionStyleDefault handler:^{ [self showColorPicker]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"複製" systemImage:@"plus.square.on.square" style:CustomMenuActionStyleDefault handler:^{ [self duplicateSelectedAnnotation]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [self deleteSelectedAnnotation]; }]];
    }
    [menu showInView:self.view];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.pdfView];
    PDFPage *page = [self.pdfView pageForPoint:point nearest:YES];
    CGPoint pagePoint = [self.pdfView convertPoint:point toPage:page];
    self.selectedAnnotation = [page annotationAtPoint:pagePoint];
    [self updateSelectionUI];
    if (self.selectedAnnotation) [[Logger sharedLogger] log:@"[PDF] Element selected"];
}




- (void)handleRotate:(UIRotationGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.pdfView];
    PDFPage *page = [self.pdfView pageForPoint:point nearest:YES];
    CGPoint pagePoint = [self.pdfView convertPoint:point toPage:page];
    if (!self.selectedAnnotation) { self.selectedAnnotation = [page annotationAtPoint:pagePoint]; [self updateSelectionUI]; }
    if (!self.selectedAnnotation || ![self.selectedAnnotation isKindOfClass:[AdvancedAnnotation class]]) return;
    static CGFloat startRotation;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.selectionOverlay.layer.borderColor = [UIColor systemOrangeColor].CGColor;
        startRotation = ((AdvancedAnnotation *)self.selectedAnnotation).rotationAngle;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        ((AdvancedAnnotation *)self.selectedAnnotation).rotationAngle = startRotation + (gesture.rotation * 180.0 / M_PI);
        [self.pdfView setNeedsDisplay]; [self updateSelectionUI];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.selectionOverlay.layer.borderColor = [UIColor systemBlueColor].CGColor;
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.pdfView];
    PDFPage *page = [self.pdfView pageForPoint:point nearest:YES];
    CGPoint pagePoint = [self.pdfView convertPoint:point toPage:page];
    if (!self.selectedAnnotation) { self.selectedAnnotation = [page annotationAtPoint:pagePoint]; [self updateSelectionUI]; }
    if (!self.selectedAnnotation) return;
    static CGRect startBounds;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.selectionOverlay.layer.borderColor = [UIColor systemOrangeColor].CGColor;
        startBounds = self.selectedAnnotation.bounds;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat scale = gesture.scale;
        CGRect newBounds = startBounds;
        CGFloat newW = startBounds.size.width * scale;
        CGFloat newH = startBounds.size.height * scale;
        newBounds.origin.x = startBounds.origin.x + (startBounds.size.width - newW) / 2;
        newBounds.origin.y = startBounds.origin.y + (startBounds.size.height - newH) / 2;
        newBounds.size = CGSizeMake(newW, newH);
        self.selectedAnnotation.bounds = newBounds;
        [self.pdfView setNeedsDisplay]; [self updateSelectionUI];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.selectionOverlay.layer.borderColor = [UIColor systemBlueColor].CGColor;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}


- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.pdfView];
    PDFPage *page = [self.pdfView pageForPoint:point nearest:YES];
    CGPoint pagePoint = [self.pdfView convertPoint:point toPage:page];
    static CGPoint startPagePoint; static CGRect startBounds;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.selectionOverlay.layer.borderColor = [UIColor systemOrangeColor].CGColor;
        if (!self.selectedAnnotation) { self.selectedAnnotation = [page annotationAtPoint:pagePoint]; [self updateSelectionUI]; }
        if (self.selectedAnnotation) {
            for (UIView *v in self.pdfView.subviews) { if ([v isKindOfClass:[UIScrollView class]]) { ((UIScrollView *)v).scrollEnabled = NO; } }
            startPagePoint = pagePoint; startBounds = self.selectedAnnotation.bounds;
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged && self.selectedAnnotation) {
        CGFloat dx = pagePoint.x - startPagePoint.x; CGFloat dy = pagePoint.y - startPagePoint.y;
        CGRect newBounds = startBounds; newBounds.origin.x += dx; newBounds.origin.y += dy;
        CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxMediaBox]; CGFloat threshold = 12.0;
        BOOL snappedH = NO; BOOL snappedV = NO;
        if (fabs((newBounds.origin.x + newBounds.size.width/2) - pageBounds.size.width/2) < threshold) { newBounds.origin.x = pageBounds.size.width/2 - newBounds.size.width/2; snappedH = YES; }
        if (fabs((newBounds.origin.y + newBounds.size.height/2) - pageBounds.size.height/2) < threshold) { newBounds.origin.y = pageBounds.size.height/2 - newBounds.size.height/2; snappedV = YES; }
        if (fabs(newBounds.origin.x - 20) < threshold) { newBounds.origin.x = 20; snappedH = YES; }
        if (fabs(newBounds.origin.x + newBounds.size.width - (pageBounds.size.width - 20)) < threshold) { newBounds.origin.x = pageBounds.size.width - newBounds.size.width - 20; snappedH = YES; }
        if (fabs(newBounds.origin.y - 20) < threshold) { newBounds.origin.y = 20; snappedV = YES; }
        if (fabs(newBounds.origin.y + newBounds.size.height - (pageBounds.size.height - 20)) < threshold) { newBounds.origin.y = pageBounds.size.height - newBounds.size.height - 20; snappedV = YES; }
        self.snapGuideV.hidden = !snappedH;
        if (snappedH) { CGPoint viewCenter = [self.pdfView convertPoint:CGPointMake(pageBounds.size.width/2, pageBounds.size.height/2) fromPage:page]; self.snapGuideV.frame = CGRectMake(viewCenter.x, 0, 1, self.view.bounds.size.height); }
        if (fabs((newBounds.origin.x + newBounds.size.width/2) - pageBounds.size.width/4) < threshold) { newBounds.origin.x = pageBounds.size.width/4 - newBounds.size.width/2; snappedH = YES; }
        if (fabs((newBounds.origin.x + newBounds.size.width/2) - 3*pageBounds.size.width/4) < threshold) { newBounds.origin.x = 3*pageBounds.size.width/4 - newBounds.size.width/2; snappedH = YES; }
        if (fabs((newBounds.origin.y + newBounds.size.height/2) - pageBounds.size.height/4) < threshold) { newBounds.origin.y = pageBounds.size.height/4 - newBounds.size.height/2; snappedV = YES; }
        if (fabs((newBounds.origin.y + newBounds.size.height/2) - 3*pageBounds.size.height/4) < threshold) { newBounds.origin.y = 3*pageBounds.size.height/4 - newBounds.size.height/2; snappedV = YES; }
        for (PDFAnnotation *other in page.annotations) {
            if (other == self.selectedAnnotation) continue;
            CGRect ob = other.bounds;
            if (fabs(newBounds.origin.x - ob.origin.x) < threshold) { newBounds.origin.x = ob.origin.x; snappedH = YES; }
            if (fabs(newBounds.origin.x + newBounds.size.width - (ob.origin.x + ob.size.width)) < threshold) { newBounds.origin.x = ob.origin.x + ob.size.width - newBounds.size.width; snappedH = YES; }
            if (fabs(newBounds.origin.y - ob.origin.y) < threshold) { newBounds.origin.y = ob.origin.y; snappedV = YES; }
            if (fabs(newBounds.origin.y + newBounds.size.height - (ob.origin.y + ob.size.height)) < threshold) { newBounds.origin.y = ob.origin.y + ob.size.height - newBounds.size.height; snappedV = YES; }
            if (fabs((newBounds.origin.x + newBounds.size.width/2) - (ob.origin.x + ob.size.width/2)) < threshold) { newBounds.origin.x = (ob.origin.x + ob.size.width/2) - newBounds.size.width/2; snappedH = YES; }
            if (fabs((newBounds.origin.y + newBounds.size.height/2) - (ob.origin.y + ob.size.height/2)) < threshold) { newBounds.origin.y = (ob.origin.y + ob.size.height/2) - newBounds.size.height/2; snappedV = YES; }
        }
        self.snapGuideH.hidden = !snappedV;
        if (snappedV) { CGPoint viewCenter = [self.pdfView convertPoint:CGPointMake(pageBounds.size.width/2, pageBounds.size.height/2) fromPage:page]; self.snapGuideH.frame = CGRectMake(0, viewCenter.y, self.view.bounds.size.width, 1); }
        if (self.gridEnabled) { CGFloat gridX = round(newBounds.origin.x / 40.0) * 40.0; CGFloat gridY = round(newBounds.origin.y / 40.0) * 40.0; if (fabs(newBounds.origin.x - gridX) < threshold) newBounds.origin.x = gridX; if (fabs(newBounds.origin.y - gridY) < threshold) newBounds.origin.y = gridY; }
        self.selectedAnnotation.bounds = newBounds; [self.pdfView setNeedsDisplay]; [self updateSelectionUI];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.selectionOverlay.layer.borderColor = [UIColor systemBlueColor].CGColor;
        for (UIView *v in self.pdfView.subviews) { if ([v isKindOfClass:[UIScrollView class]]) { ((UIScrollView *)v).scrollEnabled = YES; } }
        self.snapGuideH.hidden = YES; self.snapGuideV.hidden = YES;
    }
}

- (void)showShapeMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"図形・表"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"長方形" systemImage:@"square" style:CustomMenuActionStyleDefault handler:^{ [self addShape:PDFAnnotationSubtypeSquare]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"円" systemImage:@"circle" style:CustomMenuActionStyleDefault handler:^{ [self addShape:PDFAnnotationSubtypeCircle]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"線" systemImage:@"line.diagonal" style:CustomMenuActionStyleDefault handler:^{ [self addShape:PDFAnnotationSubtypeLine]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"矢印" systemImage:@"arrow.up.right" style:CustomMenuActionStyleDefault handler:^{ [self addShape:PDFAnnotationSubtypeLink]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"星形" systemImage:@"star" style:CustomMenuActionStyleDefault handler:^{ [self addStarShape]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"吹き出し" systemImage:@"bubble.left" style:CustomMenuActionStyleDefault handler:^{ [self addCalloutShape]; }]];
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
    PDFAnnotation *annot = [[PDFAnnotation alloc] initWithBounds:CGRectMake(150, 150, 32, 32) forType:PDFAnnotationSubtypeStamp withProperties:nil];
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
        [menu addAction:[CustomMenuAction actionWithTitle:@"画像フィルタ" systemImage:@"wand.and.stars" style:CustomMenuActionStyleDefault handler:^{ [self showImageFilters]; }]];
            ((AdvancedAnnotation *)self.selectedAnnotation).rotationAngle += 45;
            [self.pdfView setNeedsDisplay];
        }
    }]];
    if ([self.selectedAnnotation.type isEqualToString:PDFAnnotationSubtypeFreeText]) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"テキスト編集" systemImage:@"pencil" style:CustomMenuActionStyleDefault handler:^{ [self promptForTextContent]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"文字サイズ変更" systemImage:@"textformat.size" style:CustomMenuActionStyleDefault handler:^{ [self promptForFontSize]; }]];
    }
    [menu addAction:[CustomMenuAction actionWithTitle:@"位置指定" systemImage:@"arrow.up.and.down.and.arrow.left.and.right" style:CustomMenuActionStyleDefault handler:^{ [self promptForPosition]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"配置・整列" systemImage:@"align.horizontal.center.fill" style:CustomMenuActionStyleDefault handler:^{ [self showAlignmentMenu]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"詳細プロパティ" systemImage:@"gearshape" style:CustomMenuActionStyleDefault handler:^{ [self showAdvancedProperties]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"最前面へ" systemImage:@"arrow.up.square" style:CustomMenuActionStyleDefault handler:^{ [self moveAnnotationToFront]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"最背面へ" systemImage:@"arrow.down.square" style:CustomMenuActionStyleDefault handler:^{ [self moveAnnotationToBack]; }]];
    [menu showInView:self.view];
}


- (void)promptForTextContent {
    if (!self.selectedAnnotation) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"テキスト編集" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = self.selectedAnnotation.contents; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"更新" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedAnnotation.contents = alert.textFields[0].text; [self.pdfView setNeedsDisplay];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showImageFilters {
    if (![self.selectedAnnotation isKindOfClass:[AdvancedAnnotation class]]) return;
    AdvancedAnnotation *adv = (AdvancedAnnotation *)self.selectedAnnotation;
    if (!adv.overlayImage) return;

    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"画像フィルタ"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"モノクロ" systemImage:@"circle.lefthalf.filled" style:CustomMenuActionStyleDefault handler:^{ [self applyFilter:@"CIPhotoEffectMono"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"セピア" systemImage:@"ant" style:CustomMenuActionStyleDefault handler:^{ [self applyFilter:@"CISepiaTone"]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"色反転" systemImage:@"circle.grid.cross" style:CustomMenuActionStyleDefault handler:^{ [self applyFilter:@"CIColorInvert"]; }]];
    [menu showInView:self.view];
}

- (void)applyFilter:(NSString *)filterName {
    AdvancedAnnotation *adv = (AdvancedAnnotation *)self.selectedAnnotation;
    CIImage *ci = [[CIImage alloc] initWithImage:adv.overlayImage];
    CIFilter *f = [CIFilter filterWithName:filterName];
    [f setValue:ci forKey:kCIInputImageKey];
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef cg = [ctx createCGImage:f.outputImage fromRect:f.outputImage.extent];
    adv.overlayImage = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    [self.pdfView setNeedsDisplay];
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





- (void)moveAnnotationToBack {
    if (!self.selectedAnnotation) return;
    PDFPage *p = self.selectedAnnotation.page;
    if (!p) return;
    NSArray *annots = [p.annotations copy];
    for (PDFAnnotation *a in annots) { [p removeAnnotation:a]; }
    [p addAnnotation:self.selectedAnnotation];
    for (PDFAnnotation *a in annots) { if (a != self.selectedAnnotation) [p addAnnotation:a]; }
    [self.pdfView setNeedsDisplay];
}

- (void)moveAnnotationToFront {
    if (!self.selectedAnnotation) return;
    PDFPage *p = self.selectedAnnotation.page;
    if (!p) return;
    [p removeAnnotation:self.selectedAnnotation];
    [p addAnnotation:self.selectedAnnotation];
    [self.pdfView setNeedsDisplay];
}




- (void)showColorPicker {
    if (!self.selectedAnnotation) return;
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"カラー選択"];
    NSArray *colors = @[[UIColor blackColor], [UIColor redColor], [UIColor blueColor], [UIColor greenColor], [UIColor yellowColor], [UIColor whiteColor]];
    NSArray *names = @[@"ブラック", @"レッド", @"ブルー", @"グリーン", @"イエロー", @"ホワイト"];
    for (int i=0; i<colors.count; i++) {
        [menu addAction:[CustomMenuAction actionWithTitle:names[i] systemImage:@"paintpalette" style:CustomMenuActionStyleDefault handler:^{
            self.selectedAnnotation.color = colors[i];
            if ([self.selectedAnnotation.type isEqualToString:PDFAnnotationSubtypeFreeText]) {
                self.selectedAnnotation.fontColor = colors[i];
            }
            [self.pdfView setNeedsDisplay];
        }]];
    }
    [menu showInView:self.view];
}

- (void)duplicateSelectedAnnotation {
    if (!self.selectedAnnotation) return;
    PDFPage *page = self.selectedAnnotation.page;
    CGRect b = self.selectedAnnotation.bounds;
    b.origin.x += 20; b.origin.y -= 20;

    PDFAnnotation *newAnnot;
    if ([self.selectedAnnotation isKindOfClass:[AdvancedAnnotation class]]) {
        AdvancedAnnotation *old = (AdvancedAnnotation *)self.selectedAnnotation;
        AdvancedAnnotation *adv = [[AdvancedAnnotation alloc] initWithBounds:b forType:old.type withProperties:nil];
        adv.overlayImage = old.overlayImage;
        adv.rotationAngle = old.rotationAngle;
        adv.isTable = old.isTable;
        adv.rows = old.rows;
        adv.cols = old.cols;
        newAnnot = adv;
    } else {
        newAnnot = [[PDFAnnotation alloc] initWithBounds:b forType:self.selectedAnnotation.type withProperties:nil];
        newAnnot.contents = self.selectedAnnotation.contents;
        newAnnot.font = self.selectedAnnotation.font;
        newAnnot.fontColor = self.selectedAnnotation.fontColor;
    }
    newAnnot.color = self.selectedAnnotation.color;
    [page addAnnotation:newAnnot];
    self.selectedAnnotation = newAnnot;
    [self.pdfView setNeedsDisplay]; [self updateSelectionUI];
}

- (void)deleteSelectedAnnotation { if (self.selectedAnnotation) { [self.selectedAnnotation.page removeAnnotation:self.selectedAnnotation]; self.selectedAnnotation = nil; [self.pdfView setNeedsDisplay];
    [self updateSelectionUI]; } }




- (void)showTextAlignmentMenu {
    if (!self.selectedAnnotation || ![self.selectedAnnotation.type isEqualToString:PDFAnnotationSubtypeFreeText]) return;
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"テキスト揃え"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"左揃え" systemImage:@"text.alignleft" style:CustomMenuActionStyleDefault handler:^{ self.selectedAnnotation.alignment = NSTextAlignmentLeft; [self.pdfView setNeedsDisplay]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"中央揃え" systemImage:@"text.aligncenter" style:CustomMenuActionStyleDefault handler:^{ self.selectedAnnotation.alignment = NSTextAlignmentCenter; [self.pdfView setNeedsDisplay]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"右揃え" systemImage:@"text.alignright" style:CustomMenuActionStyleDefault handler:^{ self.selectedAnnotation.alignment = NSTextAlignmentRight; [self.pdfView setNeedsDisplay]; }]];
    [menu showInView:self.view];
}

- (void)showAdvancedProperties {
    if (!self.selectedAnnotation) return;
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"詳細プロパティ"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"枠線の太さ" systemImage:@"line.3.horizontal" style:CustomMenuActionStyleDefault handler:^{ [self promptForThickness]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"不透明度" systemImage:@"circle.dotted" style:CustomMenuActionStyleDefault handler:^{ [self promptForOpacity]; }]];
    if ([self.selectedAnnotation.type isEqualToString:PDFAnnotationSubtypeFreeText]) {
        [menu addAction:[CustomMenuAction actionWithTitle:@"フォント切り替え" systemImage:@"textformat" style:CustomMenuActionStyleDefault handler:^{ [self toggleFontStyle]; }]];
        [menu addAction:[CustomMenuAction actionWithTitle:@"テキスト揃え" systemImage:@"text.aligncenter" style:CustomMenuActionStyleDefault handler:^{ [self showTextAlignmentMenu]; }]];
    }
    [menu showInView:self.view];
}

- (void)promptForThickness {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"枠線の太さ" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.keyboardType = UIKeyboardTypeDecimalPad; tf.text = @"2.0"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"適用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        PDFBorder *border = [[PDFBorder alloc] init]; border.lineWidth = [alert.textFields[0].text floatValue];
        self.selectedAnnotation.border = border; [self.pdfView setNeedsDisplay];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForOpacity {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"不透明度 (0.0 - 1.0)" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.keyboardType = UIKeyboardTypeDecimalPad; tf.text = @"1.0"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"適用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self.selectedAnnotation.color = [self.selectedAnnotation.color colorWithAlphaComponent:[alert.textFields[0].text floatValue]]; [self.pdfView setNeedsDisplay];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleFontStyle {
    UIFont *current = self.selectedAnnotation.font;
    BOOL isBold = [current.fontName containsString:@"Bold"];
    UIFont *newFont = isBold ? [UIFont systemFontOfSize:current.pointSize] : [UIFont boldSystemFontOfSize:current.pointSize];
    self.selectedAnnotation.font = newFont; [self.pdfView setNeedsDisplay];
}

- (void)showAlignmentMenu {
    if (!self.selectedAnnotation) return;
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"配置・整列"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"左右中央揃え" systemImage:@"align.horizontal.center" style:CustomMenuActionStyleDefault handler:^{ [self alignAnnotation:0]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"上下中央揃え" systemImage:@"align.vertical.center" style:CustomMenuActionStyleDefault handler:^{ [self alignAnnotation:1]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"左端揃え" systemImage:@"align.horizontal.left" style:CustomMenuActionStyleDefault handler:^{ [self alignAnnotation:2]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"右端揃え" systemImage:@"align.horizontal.right" style:CustomMenuActionStyleDefault handler:^{ [self alignAnnotation:3]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"上端揃え" systemImage:@"align.vertical.top" style:CustomMenuActionStyleDefault handler:^{ [self alignAnnotation:4]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"下端揃え" systemImage:@"align.vertical.bottom" style:CustomMenuActionStyleDefault handler:^{ [self alignAnnotation:5]; }]];
    [menu showInView:self.view];
}

- (void)alignAnnotation:(NSInteger)mode {
    PDFPage *page = self.selectedAnnotation.page;
    CGRect pageBounds = [page boundsForBox:kPDFDisplayBoxMediaBox];
    CGRect b = self.selectedAnnotation.bounds;
    switch (mode) {
        case 0: b.origin.x = (pageBounds.size.width - b.size.width) / 2; break;
        case 1: b.origin.y = (pageBounds.size.height - b.size.height) / 2; break;
        case 2: b.origin.x = 20; break;
        case 3: b.origin.x = pageBounds.size.width - b.size.width - 20; break;
        case 4: b.origin.y = pageBounds.size.height - b.size.height - 20; break;
        case 5: b.origin.y = 20; break;
    }
    self.selectedAnnotation.bounds = b;
    [self.pdfView setNeedsDisplay]; [self updateSelectionUI];
}

- (void)showPageMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"ページ操作"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"白紙ページを追加" systemImage:@"doc.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self addBlankPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを複製" systemImage:@"plus.square.on.square" style:CustomMenuActionStyleDefault handler:^{ [self duplicateCurrentPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページを削除" systemImage:@"trash" style:CustomMenuActionStyleDestructive handler:^{ [self deleteCurrentPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"ページ回転 (+90°)" systemImage:@"rotate.right" style:CustomMenuActionStyleDefault handler:^{ [self rotateCurrentPage]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"上へ移動" systemImage:@"arrow.up" style:CustomMenuActionStyleDefault handler:^{ [self movePageUp]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"下へ移動" systemImage:@"arrow.down" style:CustomMenuActionStyleDefault handler:^{ [self movePageDown]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"テンプレート挿入" systemImage:@"rectangle.stack.badge.plus" style:CustomMenuActionStyleDefault handler:^{ [self showTemplateMenu]; }]];
    [menu showInView:self.view];
}

- (void)addBlankPage {
    PDFDocument *doc = self.pdfView.document;
    PDFPage *blank = [[PDFPage alloc] init];
    [blank setBounds:CGRectMake(0, 0, 612, 792) forBox:kPDFDisplayBoxMediaBox];
    NSInteger idx = doc ? ([doc indexForPage:self.pdfView.currentPage] + 1) : 0;
    if (!doc) { doc = [[PDFDocument alloc] init]; self.pdfView.document = doc; idx = 0; }
    [doc insertPage:blank atIndex:idx];
    [self.pdfView goToPage:[doc pageAtIndex:idx]];
    [self.pdfView setNeedsDisplay];
}

- (void)duplicateCurrentPage {
    PDFPage *current = self.pdfView.currentPage; if (current) {
        NSData *data = [current dataRepresentation]; PDFDocument *tempDoc = [[PDFDocument alloc] initWithData:data];
        if (tempDoc.pageCount > 0) { [self.pdfView.document insertPage:[tempDoc pageAtIndex:0] atIndex:[self.pdfView.document indexForPage:current] + 1]; [self.pdfView setNeedsDisplay]; }
    }
}

- (void)deleteCurrentPage { if (self.pdfView.document.pageCount > 1) { [self.pdfView.document removePageAtIndex:[self.pdfView.document indexForPage:self.pdfView.currentPage]]; [self.pdfView setNeedsDisplay]; } }


- (void)movePageUp {
    PDFDocument *doc = self.pdfView.document;
    NSInteger idx = [doc indexForPage:self.pdfView.currentPage];
    if (idx > 0) {
        PDFPage *page = [doc pageAtIndex:idx];
        [doc removePageAtIndex:idx];
        [doc insertPage:page atIndex:idx-1];
        [self.pdfView goToPage:[doc pageAtIndex:idx-1]];
    }
}

- (void)movePageDown {
    PDFDocument *doc = self.pdfView.document;
    NSInteger idx = [doc indexForPage:self.pdfView.currentPage];
    if (idx < doc.pageCount - 1) {
        PDFPage *page = [doc pageAtIndex:idx];
        [doc removePageAtIndex:idx];
        [doc insertPage:page atIndex:idx+1];
        [self.pdfView goToPage:[doc pageAtIndex:idx+1]];
    }
}

- (void)addTemplatePage:(NSInteger)type {
    PDFPage *page = [[PDFPage alloc] init];
    CGRect pageBounds = CGRectMake(0, 0, 612, 792);
    [page setBounds:pageBounds forBox:kPDFDisplayBoxMediaBox];

    if (type == 0) { // Title Page
        PDFAnnotation *title = [[PDFAnnotation alloc] initWithBounds:CGRectMake(50, 500, 512, 100) forType:PDFAnnotationSubtypeFreeText withProperties:nil];
        title.contents = @"タイトルを入力"; title.font = [UIFont boldSystemFontOfSize:40]; title.alignment = NSTextAlignmentCenter;
        [page addAnnotation:title];
    } else { // Content Page
        PDFAnnotation *header = [[PDFAnnotation alloc] initWithBounds:CGRectMake(50, 700, 512, 50) forType:PDFAnnotationSubtypeFreeText withProperties:nil];
        header.contents = @"見出し"; header.font = [UIFont boldSystemFontOfSize:24];
        [page addAnnotation:header];
        PDFAnnotation *body = [[PDFAnnotation alloc] initWithBounds:CGRectMake(50, 100, 512, 550) forType:PDFAnnotationSubtypeFreeText withProperties:nil];
        body.contents = @"内容を入力..."; body.font = [UIFont systemFontOfSize:16];
        [page addAnnotation:body];
    }

    [self.pdfView.document insertPage:page atIndex:[self.pdfView.document indexForPage:self.pdfView.currentPage] + 1];
    [self.pdfView setNeedsDisplay];
}



- (void)addStarShape {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    AdvancedAnnotation *annot = [[AdvancedAnnotation alloc] initWithBounds:CGRectMake(100, 100, 150, 150) forType:PDFAnnotationSubtypeStamp withProperties:nil];

    // iOS 17+: UIGraphicsImageRenderer
    UIGraphicsImageRenderer *_starRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(150, 150)];
    annot.overlayImage = [_starRenderer imageWithActions:^(UIGraphicsImageRendererContext *_rc) {
        CGContextRef ctx = _rc.CGContext;
        CGContextSetFillColorWithColor(ctx, [UIColor yellowColor].CGColor);
        CGFloat centerX = 75, centerY = 75, r = 70;
        CGContextMoveToPoint(ctx, centerX, centerY - r);
        for (int i=1; i<5; i++) {
            CGFloat x = centerX + r * sin(i * 4 * M_PI / 5);
            CGFloat y = centerY - r * cos(i * 4 * M_PI / 5);
            CGContextAddLineToPoint(ctx, x, y);
        }
        CGContextClosePath(ctx); CGContextFillPath(ctx);
    }];

    [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)addCalloutShape {
    PDFPage *page = self.pdfView.currentPage; if (!page) return;
    AdvancedAnnotation *annot = [[AdvancedAnnotation alloc] initWithBounds:CGRectMake(100, 100, 200, 100) forType:PDFAnnotationSubtypeStamp withProperties:nil];

    // iOS 17+: UIGraphicsImageRenderer
    UIGraphicsImageRenderer *_calloutRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(200, 100)];
    annot.overlayImage = [_calloutRenderer imageWithActions:^(UIGraphicsImageRendererContext *_rc) {
        CGContextRef ctx = _rc.CGContext;
        CGContextSetStrokeColorWithColor(ctx, [UIColor blackColor].CGColor);
        CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        CGRect rect = CGRectMake(5, 5, 190, 70);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:10];
        [path moveToPoint:CGPointMake(100, 75)]; [path addLineToPoint:CGPointMake(90, 95)]; [path addLineToPoint:CGPointMake(110, 75)];
        [path fill]; [path stroke];
    }];

    [page addAnnotation:annot]; [self.pdfView setNeedsDisplay];
}

- (void)showTemplateMenu {
    CustomMenuView *menu = [CustomMenuView menuWithTitle:@"テンプレート選択"];
    [menu addAction:[CustomMenuAction actionWithTitle:@"タイトルページ" systemImage:@"text.justify" style:CustomMenuActionStyleDefault handler:^{ [self addTemplatePage:0]; }]];
    [menu addAction:[CustomMenuAction actionWithTitle:@"コンテンツページ" systemImage:@"list.bullet.rectangle" style:CustomMenuActionStyleDefault handler:^{ [self addTemplatePage:1]; }]];
    [menu showInView:self.view];
}

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


- (void)togglePresenterMode {
    BOOL isHidden = self.navigationController.navigationBarHidden;
    [self.navigationController setNavigationBarHidden:!isHidden animated:YES];
    self.pdfView.autoScales = YES;
}

- (void)savePDF { if ([self.pdfView.document writeToFile:_path]) { [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess]; [self.navigationController popViewControllerAnimated:YES]; } }

@end