// PowerPointViewerViewController.m
// PPTX ビューア＋エディタ
// 機能: スライド一覧・ナビ, テキスト/図形/画像編集, アニメーション, テーマ, プレゼンモード,
//       エクスポート(PDF/画像), スピーカーノート, ズーム, スライドショー

#import "PowerPointViewerViewController.h"
#import <objc/runtime.h>
#import "ThemeEngine.h"
#import "CustomMenuView.h"
#import <PDFKit/PDFKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Models

typedef NS_ENUM(NSUInteger, SlideElementType) {
    SlideElementText, SlideElementImage, SlideElementShape,
    SlideElementTable, SlideElementChart
};

typedef NS_ENUM(NSUInteger, ShapeType) {
    ShapeRect, ShapeRoundRect, ShapeEllipse, ShapeArrow,
    ShapeTriangle, ShapeStar, ShapeLine
};

@interface SlideElement : NSObject
@property (nonatomic, assign) SlideElementType type;
@property (nonatomic, assign) CGRect     frame;     // normalized 0-1
@property (nonatomic, copy)   NSString  *text;
@property (nonatomic, strong) UIFont    *font;
@property (nonatomic, strong) UIColor   *textColor;
@property (nonatomic, strong) UIColor   *fillColor;
@property (nonatomic, strong) UIColor   *strokeColor;
@property (nonatomic, assign) CGFloat    strokeWidth;
@property (nonatomic, assign) ShapeType  shapeType;
@property (nonatomic, strong) UIImage   *image;
@property (nonatomic, assign) CGFloat    rotation; // degrees
@property (nonatomic, assign) CGFloat    opacity;
@property (nonatomic, assign) NSTextAlignment textAlignment;
@property (nonatomic, assign) BOOL       bold, italic, underline;
@property (nonatomic, assign) BOOL       selected;
@property (nonatomic, assign) NSInteger  zIndex;
- (id)mutableCopy;

@end

// Gesture handlers (defined outside @interface)
@interface PowerPointViewerViewController (GestureHandlers)
- (void)presentationTapNext:(UIGestureRecognizer *)g;
- (void)presentationSwipeLeft:(UIGestureRecognizer *)g;
- (void)presentationSwipeRight:(UIGestureRecognizer *)g;
@end

@implementation PowerPointViewerViewController (GestureHandlers)
- (void)presentationTapNext:(UIGestureRecognizer *)g {
    void (^adv)(BOOL) = objc_getAssociatedObject(g.view, "advance");
    if (adv) adv(YES);
}
- (void)presentationSwipeLeft:(UIGestureRecognizer *)g {
    void (^adv)(BOOL) = objc_getAssociatedObject(g.view, "advance");
    if (adv) adv(YES);
}
- (void)presentationSwipeRight:(UIGestureRecognizer *)g {
    void (^adv)(BOOL) = objc_getAssociatedObject(g.view, "advance");
    if (adv) adv(NO);
}
@end


@implementation SlideElement
- (instancetype)init {
    self=[super init]; if(!self) return nil;
    _frame=CGRectMake(0.1,0.3,0.8,0.2);
    _textColor=[UIColor whiteColor]; _fillColor=[[UIColor whiteColor] colorWithAlphaComponent:0.15];
    _strokeColor=[[UIColor whiteColor] colorWithAlphaComponent:0.3]; _strokeWidth=1;
    _opacity=1.0; _rotation=0; _textAlignment=NSTextAlignmentLeft;
    return self;
}
- (id)mutableCopy {
    SlideElement *e=[SlideElement new];
    e.type=self.type; e.frame=self.frame; e.text=self.text;
    e.font=self.font; e.textColor=self.textColor; e.fillColor=self.fillColor;
    e.strokeColor=self.strokeColor; e.strokeWidth=self.strokeWidth;
    e.shapeType=self.shapeType; e.image=self.image;
    e.rotation=self.rotation; e.opacity=self.opacity;
    e.textAlignment=self.textAlignment; e.bold=self.bold; e.italic=self.italic;
    e.underline=self.underline; e.zIndex=self.zIndex;
    return e;
}
@end

@interface Slide : NSObject
@property (nonatomic, strong) UIColor  *backgroundColor;
@property (nonatomic, strong) UIImage  *backgroundImage;
@property (nonatomic, strong) NSMutableArray<SlideElement *> *elements;
@property (nonatomic, copy)   NSString *speakerNotes;
@property (nonatomic, copy)   NSString *layoutName;
@property (nonatomic, assign) NSTimeInterval transitionDuration;
@property (nonatomic, assign) NSInteger transitionType; // 0=none,1=fade,2=slide,3=zoom
- (NSString *)titleText;
@end
@implementation Slide
- (instancetype)init {
    self=[super init]; if(!self) return nil;
    _backgroundColor=[UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1];
    _elements=[NSMutableArray array]; _speakerNotes=@"";
    _transitionDuration=0.4; _transitionType=1; _layoutName=@"Blank";
    return self;
}
- (NSString *)titleText {
    for(SlideElement *e in self.elements) if(e.type==SlideElementText&&e.frame.origin.y<0.3) return e.text;
    return @"(タイトルなし)";
}
@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Slide Canvas View

@interface SlideShapeView : UIView
@property (nonatomic, strong) SlideElement *element;
@end
@implementation SlideShapeView
- (instancetype)initWithFrame:(CGRect)f element:(SlideElement *)el {
    self=[super initWithFrame:f]; if(!self) return nil;
    _element=el; self.backgroundColor=[UIColor clearColor];
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx,self.element.fillColor.CGColor);
    CGContextSetStrokeColorWithColor(ctx,self.element.strokeColor.CGColor);
    CGContextSetLineWidth(ctx,self.element.strokeWidth);
    UIBezierPath *path;
    switch(self.element.shapeType) {
        case ShapeRoundRect: path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect,2,2) cornerRadius:12]; break;
        case ShapeEllipse:   path=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(rect,2,2)]; break;
        case ShapeTriangle: {
            path=[UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(CGRectGetMidX(rect),CGRectGetMinY(rect)+2)];
            [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect)-2,CGRectGetMaxY(rect)-2)];
            [path addLineToPoint:CGPointMake(CGRectGetMinX(rect)+2,CGRectGetMaxY(rect)-2)];
            [path closePath]; break;
        }
        case ShapeLine: {
            path=[UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(CGRectGetMinX(rect),CGRectGetMidY(rect))];
            [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect),CGRectGetMidY(rect))];
            break;
        }
        case ShapeStar: {
            path=[self starPathInRect:rect points:5];
            break;
        }
        default: path=[UIBezierPath bezierPathWithRect:CGRectInset(rect,2,2)]; break;
    }
    if(self.element.shapeType!=ShapeLine) [path fill];
    [path stroke];

    // Text label inside shape
    if(self.element.text.length) {
        NSMutableParagraphStyle *ps=[[NSMutableParagraphStyle alloc] init];
        ps.alignment=NSTextAlignmentCenter;
        NSDictionary *attrs=@{
            NSFontAttributeName:self.element.font?:[UIFont systemFontOfSize:14],
            NSForegroundColorAttributeName:self.element.textColor?:[UIColor whiteColor],
            NSParagraphStyleAttributeName:ps
        };
        [self.element.text drawInRect:CGRectInset(rect,8,8) withAttributes:attrs];
    }
}
- (UIBezierPath *)starPathInRect:(CGRect)rect points:(NSInteger)n {
    CGFloat cx=CGRectGetMidX(rect), cy=CGRectGetMidY(rect);
    CGFloat r1=MIN(rect.size.width,rect.size.height)/2-2;
    CGFloat r2=r1*0.4;
    UIBezierPath *path=[UIBezierPath bezierPath];
    for(NSInteger i=0;i<n*2;i++) {
        CGFloat angle=(i*M_PI/n)-(M_PI/2);
        CGFloat r=(i%2==0)?r1:r2;
        CGPoint p=CGPointMake(cx+r*cos(angle), cy+r*sin(angle));
        if(i==0) [path moveToPoint:p]; else [path addLineToPoint:p];
    }
    [path closePath]; return path;
}
@end


@interface SlideCanvasView : UIView
@property (nonatomic, strong) Slide *slide;
@property (nonatomic, assign) BOOL   isEditing;
@property (nonatomic, assign) NSInteger selectedElementIndex;
@property (nonatomic, copy) void (^onElementSelected)(NSInteger);
@property (nonatomic, copy) void (^onElementMoved)(NSInteger, CGRect);
- (void)reloadSlide;
- (void)deselectAll;
@end

@implementation SlideCanvasView {
    NSMutableArray<UIView *> *_elementViews;
    UIView *_selectionHandle;
    NSInteger _dragElemIdx;
    CGPoint _dragStart, _dragOrigin;
}

- (instancetype)initWithFrame:(CGRect)f {
    self=[super initWithFrame:f]; if(!self) return nil;
    _elementViews=[NSMutableArray array];
    _selectedElementIndex=-1; _dragElemIdx=-1;
    self.clipsToBounds=YES;
    self.layer.cornerRadius=4;
    return self;
}

- (void)reloadSlide {
    for(UIView *v in _elementViews) [v removeFromSuperview];
    [_elementViews removeAllObjects];
    [_selectionHandle removeFromSuperview];

    if(!self.slide) return;
    self.backgroundColor=self.slide.backgroundColor;
    if(self.slide.backgroundImage) {
        UIImageView *bg=[[UIImageView alloc] initWithFrame:self.bounds];
        bg.contentMode=UIViewContentModeScaleAspectFill;
        bg.image=self.slide.backgroundImage;
        bg.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:bg];
    }

    NSArray *sorted=[self.slide.elements sortedArrayUsingDescriptors:
        @[[NSSortDescriptor sortDescriptorWithKey:@"zIndex" ascending:YES]]];

    for(NSInteger i=0;i<(NSInteger)sorted.count;i++) {
        SlideElement *el=sorted[i];
        CGRect actualFrame=CGRectMake(el.frame.origin.x*self.bounds.size.width,
                                      el.frame.origin.y*self.bounds.size.height,
                                      el.frame.size.width*self.bounds.size.width,
                                      el.frame.size.height*self.bounds.size.height);
        UIView *ev=[self viewForElement:el frame:actualFrame];
        ev.tag=i;
        ev.alpha=el.opacity;
        ev.transform=CGAffineTransformMakeRotation(el.rotation*M_PI/180.0);
        if(self.isEditing) {
            UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(elementTapped:)];
            [ev addGestureRecognizer:tap];
            UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(elementPanned:)];
            [ev addGestureRecognizer:pan];
        }
        [self addSubview:ev];
        [_elementViews addObject:ev];

        if(i==self.selectedElementIndex && self.isEditing) {
            [self drawSelectionHandlesFor:ev];
        }
    }
}

- (UIView *)viewForElement:(SlideElement *)el frame:(CGRect)frame {
    switch(el.type) {
    case SlideElementText: {
        UILabel *lbl=[[UILabel alloc] initWithFrame:frame];
        lbl.text=el.text?:@"";
        lbl.textColor=el.textColor?:[UIColor whiteColor];
        lbl.numberOfLines=0;
        lbl.textAlignment=el.textAlignment;
        UIFontDescriptor *desc=[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
        UIFontDescriptorSymbolicTraits traits=0;
        if(el.bold) traits|=UIFontDescriptorTraitBold;
        if(el.italic) traits|=UIFontDescriptorTraitItalic;
        if(traits) desc=[desc fontDescriptorWithSymbolicTraits:traits];
        CGFloat sz=el.font?el.font.pointSize:18;
        lbl.font=[UIFont fontWithDescriptor:desc size:sz];
        if(el.underline) {
            NSMutableAttributedString *as=[[NSMutableAttributedString alloc] initWithString:lbl.text];
            [as addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle)
                       range:NSMakeRange(0,as.length)];
            lbl.attributedText=as;
        }
        return lbl;
    }
    case SlideElementShape: {
        SlideShapeView *sv=[[SlideShapeView alloc] initWithFrame:frame element:el];
        return sv;
    }
    case SlideElementImage: {
        UIImageView *iv=[[UIImageView alloc] initWithFrame:frame];
        iv.contentMode=UIViewContentModeScaleAspectFit;
        iv.image=el.image;
        return iv;
    }
    default: {
        UIView *v=[[UIView alloc] initWithFrame:frame];
        v.backgroundColor=el.fillColor;
        v.layer.borderColor=el.strokeColor.CGColor;
        v.layer.borderWidth=el.strokeWidth;
        return v;
    }
    }
}

- (void)drawSelectionHandlesFor:(UIView *)ev {
    _selectionHandle=[[UIView alloc] initWithFrame:CGRectInset(ev.frame,-4,-4)];
    _selectionHandle.layer.borderColor=[UIColor systemBlueColor].CGColor;
    _selectionHandle.layer.borderWidth=1.5;
    _selectionHandle.backgroundColor=[UIColor clearColor];
    _selectionHandle.userInteractionEnabled=NO;
    [self addSubview:_selectionHandle];
    // Corner handles
    for(NSInteger ci=0;ci<4;ci++) {
        CGFloat hx=(ci%2==0)?-4:_selectionHandle.bounds.size.width-4;
        CGFloat hy=(ci<2)?-4:_selectionHandle.bounds.size.height-4;
        UIView *h=[[UIView alloc] initWithFrame:CGRectMake(hx,hy,8,8)];
        h.backgroundColor=[UIColor systemBlueColor];
        h.layer.cornerRadius=4;
        [_selectionHandle addSubview:h];
    }
}

- (void)elementTapped:(UITapGestureRecognizer *)tap {
    NSInteger idx=tap.view.tag;
    self.selectedElementIndex=idx;
    [self reloadSlide];
    if(self.onElementSelected) self.onElementSelected(idx);
}

- (void)elementPanned:(UIPanGestureRecognizer *)pan {
    NSInteger idx=pan.view.tag;
    if(pan.state==UIGestureRecognizerStateBegan) {
        _dragElemIdx=idx;
        _dragStart=[pan locationInView:self];
        _dragOrigin=pan.view.frame.origin;
    } else if(pan.state==UIGestureRecognizerStateChanged) {
        CGPoint cur=[pan locationInView:self];
        CGFloat dx=cur.x-_dragStart.x, dy=cur.y-_dragStart.y;
        CGRect newFrame=pan.view.frame;
        newFrame.origin=CGPointMake(_dragOrigin.x+dx, _dragOrigin.y+dy);
        pan.view.frame=newFrame;
        if(_selectionHandle) {
            _selectionHandle.frame=CGRectInset(newFrame,-4,-4);
        }
    } else if(pan.state==UIGestureRecognizerStateEnded) {
        CGRect nf=pan.view.frame;
        CGRect normalized=CGRectMake(nf.origin.x/self.bounds.size.width,
                                     nf.origin.y/self.bounds.size.height,
                                     nf.size.width/self.bounds.size.width,
                                     nf.size.height/self.bounds.size.height);
        if(self.onElementMoved) self.onElementMoved(idx, normalized);
    }
}

- (void)deselectAll {
    self.selectedElementIndex=-1;
    [_selectionHandle removeFromSuperview];
    for(UIView *v in _elementViews) {
        v.layer.borderWidth=0;
    }
}

@end

// Shape drawing view


// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Thumbnail Cell

@interface SlideThumbnailCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *numberLabel;
@property (nonatomic, strong) UIView  *thumbnailView;
@property (nonatomic, strong) UILabel *titleLabel;
- (void)configureWithSlide:(Slide *)slide index:(NSInteger)idx isSelected:(BOOL)sel;
@end
@implementation SlideThumbnailCell
- (instancetype)initWithFrame:(CGRect)f {
    self=[super initWithFrame:f]; if(!self) return nil;
    self.contentView.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.05];
    self.contentView.layer.cornerRadius=8; self.contentView.clipsToBounds=YES;

    _thumbnailView=[[UIView alloc] init];
    _thumbnailView.translatesAutoresizingMaskIntoConstraints=NO;
    _thumbnailView.layer.cornerRadius=4; _thumbnailView.clipsToBounds=YES;
    [self.contentView addSubview:_thumbnailView];

    _numberLabel=[[UILabel alloc] init];
    _numberLabel.translatesAutoresizingMaskIntoConstraints=NO;
    _numberLabel.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.5];
    _numberLabel.font=[UIFont systemFontOfSize:10];
    _numberLabel.textAlignment=NSTextAlignmentCenter;
    [self.contentView addSubview:_numberLabel];

    _titleLabel=[[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints=NO;
    _titleLabel.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.7];
    _titleLabel.font=[UIFont systemFontOfSize:9];
    _titleLabel.textAlignment=NSTextAlignmentCenter;
    [self.contentView addSubview:_titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_thumbnailView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [_thumbnailView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4],
        [_thumbnailView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
        [_thumbnailView.heightAnchor constraintEqualToAnchor:_thumbnailView.widthAnchor multiplier:0.5625],
        [_numberLabel.topAnchor constraintEqualToAnchor:_thumbnailView.bottomAnchor constant:2],
        [_numberLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_numberLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:_numberLabel.bottomAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2],
    ]];
    return self;
}
- (void)configureWithSlide:(Slide *)slide index:(NSInteger)idx isSelected:(BOOL)sel {
    _thumbnailView.backgroundColor=slide.backgroundColor;
    _numberLabel.text=[NSString stringWithFormat:@"%ld",(long)(idx+1)];
    _titleLabel.text=slide.titleText;
    self.contentView.layer.borderWidth=sel?2:0;
    self.contentView.layer.borderColor=[UIColor systemBlueColor].CGColor;
    // Render mini elements
    for(UIView *v in _thumbnailView.subviews) [v removeFromSuperview];
    for(SlideElement *el in slide.elements) {
        if(el.type==SlideElementText && el.text.length) {
            UILabel *lbl=[[UILabel alloc] initWithFrame:CGRectMake(
                el.frame.origin.x*_thumbnailView.bounds.size.width,
                el.frame.origin.y*_thumbnailView.bounds.size.height,
                el.frame.size.width*_thumbnailView.bounds.size.width,
                el.frame.size.height*_thumbnailView.bounds.size.height)];
            lbl.text=el.text; lbl.textColor=el.textColor;
            lbl.font=[UIFont systemFontOfSize:4]; lbl.numberOfLines=2;
            [_thumbnailView addSubview:lbl];
        }
    }
}
@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Main VC

@interface PowerPointViewerViewController ()
    <UICollectionViewDelegate, UICollectionViewDataSource,
     UIDocumentPickerDelegate, UITextFieldDelegate>

@property (nonatomic, copy)   NSString *filePath;
@property (nonatomic, strong) NSMutableArray<Slide *> *slides;
@property (nonatomic, assign) NSInteger currentSlideIndex;

// Layout
@property (nonatomic, strong) UISplitViewController *splitVC; // conceptual — we use manual layout
@property (nonatomic, strong) UIView        *sidePanel;
@property (nonatomic, strong) UIView        *mainPanel;
@property (nonatomic, strong) UIView        *bottomPanel;

// Thumbnail strip
@property (nonatomic, strong) UICollectionView *thumbnailCollection;

// Canvas
@property (nonatomic, strong) UIScrollView  *canvasScroll;
@property (nonatomic, strong) SlideCanvasView *canvas;
@property (nonatomic, assign) CGFloat        zoomLevel;

// Toolbar
@property (nonatomic, strong) UIScrollView  *toolbarScroll;

// Properties panel (right side, hidden by default)
@property (nonatomic, strong) UIView        *propsPanel;
@property (nonatomic, assign) BOOL           showPropsPanel;

// Notes
@property (nonatomic, strong) UITextView    *notesView;
@property (nonatomic, assign) BOOL           showNotes;

// Selected element
@property (nonatomic, assign) NSInteger      selectedElementIndex;

// Undo/redo
@property (nonatomic, strong) NSMutableArray *undoStack;
@property (nonatomic, strong) NSMutableArray *redoStack;

// Presentation mode
@property (nonatomic, assign) BOOL isPresentingFullscreen;
@property (nonatomic, strong) UIWindow *presentationWindow;

// Constraints for dynamic layout
@property (nonatomic, strong) NSLayoutConstraint *sidePanelWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bottomPanelHeightConstraint;

@end

@implementation PowerPointViewerViewController

- (instancetype)initWithPath:(NSString *)path {
    self=[super init]; if(!self) return nil;
    _filePath=path; _slides=[NSMutableArray array];
    _currentSlideIndex=0; _zoomLevel=1.0; _selectedElementIndex=-1;
    _undoStack=[NSMutableArray array]; _redoStack=[NSMutableArray array];
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=self.filePath.lastPathComponent;
    self.view.backgroundColor=[ThemeEngine bg];
    [self loadPresentation];
    [self setupNavigationBar];
    [self setupLayout];
    [self setupThumbnailPanel];
    [self setupCanvas];
    [self setupToolbar];
    [self setupNotesPanel];
    [self selectSlide:0];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self savePresentation];
}

#pragma mark - Navigation Bar

- (void)setupNavigationBar {
    UIBarButtonItem *present = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"play.fill"]
                style:UIBarButtonItemStylePlain target:self action:@selector(startPresentation)];
    UIBarButtonItem *addSlide = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus.rectangle.on.rectangle"]
                style:UIBarButtonItemStylePlain target:self action:@selector(addSlide)];
    UIBarButtonItem *more = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];
    UIBarButtonItem *save = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
                style:UIBarButtonItemStylePlain target:self action:@selector(savePresentation)];
    self.navigationItem.rightBarButtonItems = @[present, save, addSlide, more];
}

#pragma mark - Layout

- (void)setupLayout {
    // Side thumbnail panel (left 110pt)
    self.sidePanel = [[UIView alloc] init];
    self.sidePanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidePanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    [self.view addSubview:self.sidePanel];

    // Main canvas panel
    self.mainPanel = [[UIView alloc] init];
    self.mainPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.mainPanel.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1];
    [self.view addSubview:self.mainPanel];

    // Bottom notes panel (80pt)
    self.bottomPanel = [[UIView alloc] init];
    self.bottomPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    [self.view addSubview:self.bottomPanel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.sidePanelWidthConstraint = [self.sidePanel.widthAnchor constraintEqualToConstant:110];
    self.bottomPanelHeightConstraint = [self.bottomPanel.heightAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        // Side panel
        self.sidePanelWidthConstraint,
        [self.sidePanel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:38+44],
        [self.sidePanel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.sidePanel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        // Main panel
        [self.mainPanel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:38+44],
        [self.mainPanel.leadingAnchor constraintEqualToAnchor:self.sidePanel.trailingAnchor],
        [self.mainPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mainPanel.bottomAnchor constraintEqualToAnchor:self.bottomPanel.topAnchor],
        // Bottom notes panel
        self.bottomPanelHeightConstraint,
        [self.bottomPanel.leadingAnchor constraintEqualToAnchor:self.sidePanel.trailingAnchor],
        [self.bottomPanel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomPanel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
}

#pragma mark - Thumbnail Panel

- (void)setupThumbnailPanel {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(98, 78);
    layout.minimumLineSpacing = 6;
    layout.sectionInset = UIEdgeInsetsMake(8, 6, 8, 6);
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;

    self.thumbnailCollection = [[UICollectionView alloc] initWithFrame:CGRectZero
                                                  collectionViewLayout:layout];
    self.thumbnailCollection.translatesAutoresizingMaskIntoConstraints = NO;
    self.thumbnailCollection.backgroundColor = [UIColor clearColor];
    self.thumbnailCollection.delegate = self;
    self.thumbnailCollection.dataSource = self;
    [self.thumbnailCollection registerClass:[SlideThumbnailCell class] forCellWithReuseIdentifier:@"Thumb"];
    [self.sidePanel addSubview:self.thumbnailCollection];

    [NSLayoutConstraint activateConstraints:@[
        [self.thumbnailCollection.topAnchor constraintEqualToAnchor:self.sidePanel.topAnchor],
        [self.thumbnailCollection.leadingAnchor constraintEqualToAnchor:self.sidePanel.leadingAnchor],
        [self.thumbnailCollection.trailingAnchor constraintEqualToAnchor:self.sidePanel.trailingAnchor],
        [self.thumbnailCollection.bottomAnchor constraintEqualToAnchor:self.sidePanel.bottomAnchor],
    ]];
}

#pragma mark - Canvas

- (void)setupCanvas {
    self.canvasScroll = [[UIScrollView alloc] init];
    self.canvasScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.canvasScroll.minimumZoomScale = 0.3;
    self.canvasScroll.maximumZoomScale = 4.0;
    self.canvasScroll.delegate = (id)self;
    self.canvasScroll.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1];
    [self.mainPanel addSubview:self.canvasScroll];

    [NSLayoutConstraint activateConstraints:@[
        [self.canvasScroll.topAnchor constraintEqualToAnchor:self.mainPanel.topAnchor constant:42],
        [self.canvasScroll.leadingAnchor constraintEqualToAnchor:self.mainPanel.leadingAnchor],
        [self.canvasScroll.trailingAnchor constraintEqualToAnchor:self.mainPanel.trailingAnchor],
        [self.canvasScroll.bottomAnchor constraintEqualToAnchor:self.mainPanel.bottomAnchor],
    ]];

    CGFloat canvasW = CGRectGetWidth(self.mainPanel.bounds) > 0 ? CGRectGetWidth(self.mainPanel.bounds) : (CGRectGetWidth(self.view.bounds) - 110);
    CGFloat canvasH = canvasW * (9.0/16.0);
    self.canvas = [[SlideCanvasView alloc] initWithFrame:CGRectMake(0,0,canvasW,canvasH)];
    self.canvas.isEditing = YES;
    [self.canvasScroll addSubview:self.canvas];
    self.canvasScroll.contentSize = CGSizeMake(canvasW, canvasH + 40);
    self.canvas.center = CGPointMake(self.canvasScroll.contentSize.width/2, canvasH/2 + 20);

    __weak typeof(self) wSelf = self;
    self.canvas.onElementSelected = ^(NSInteger idx) {
        wSelf.selectedElementIndex = idx;
        [wSelf showPropertiesPanelForElement:idx];
    };
    self.canvas.onElementMoved = ^(NSInteger idx, CGRect newFrame) {
        [wSelf saveUndo];
        wSelf.slides[wSelf.currentSlideIndex].elements[idx].frame = newFrame;
    };

    // Slide navigation swipe
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc]
        initWithTarget:self action:@selector(nextSlide)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc]
        initWithTarget:self action:@selector(prevSlide)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.canvas addGestureRecognizer:swipeLeft];
    [self.canvas addGestureRecognizer:swipeRight];

    // Tap on empty area = deselect
    UITapGestureRecognizer *tapBg = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(canvasTapped:)];
    tapBg.cancelsTouchesInView = NO;
    [self.canvas addGestureRecognizer:tapBg];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv { return self.canvas; }

- (void)canvasTapped:(UITapGestureRecognizer *)tap {
    [self.canvas deselectAll];
    self.selectedElementIndex = -1;
    [self hidePropertiesPanel];
}

#pragma mark - Toolbar

- (void)setupToolbar {
    UIView *tbBg = [[UIView alloc] init];
    tbBg.translatesAutoresizingMaskIntoConstraints = NO;
    tbBg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    [self.mainPanel addSubview:tbBg];
    [NSLayoutConstraint activateConstraints:@[
        [tbBg.topAnchor constraintEqualToAnchor:self.mainPanel.topAnchor],
        [tbBg.leadingAnchor constraintEqualToAnchor:self.mainPanel.leadingAnchor],
        [tbBg.trailingAnchor constraintEqualToAnchor:self.mainPanel.trailingAnchor],
        [tbBg.heightAnchor constraintEqualToConstant:40],
    ]];

    self.toolbarScroll = [[UIScrollView alloc] init];
    self.toolbarScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolbarScroll.showsHorizontalScrollIndicator = NO;
    [tbBg addSubview:self.toolbarScroll];
    [NSLayoutConstraint activateConstraints:@[
        [self.toolbarScroll.topAnchor constraintEqualToAnchor:tbBg.topAnchor constant:4],
        [self.toolbarScroll.leadingAnchor constraintEqualToAnchor:tbBg.leadingAnchor constant:8],
        [self.toolbarScroll.trailingAnchor constraintEqualToAnchor:tbBg.trailingAnchor constant:-8],
        [self.toolbarScroll.bottomAnchor constraintEqualToAnchor:tbBg.bottomAnchor constant:-4],
    ]];

    NSArray *tools = @[
        @[@"T+",@"addText"],@[@"□",@"addShape"],@[@"⬭",@"addEllipse"],@[@"📷",@"addImage"],
        @[@"B",@"bold"],@[@"I",@"italic"],@[@"U",@"underline"],
        @[@"🎨",@"textColor"],@[@"🖌",@"fillColor"],
        @[@"◀",@"alignLeft"],@[@"◈",@"alignCenter"],@[@"▶",@"alignRight"],
        @[@"A+",@"fontSize+"],@[@"A-",@"fontSize-"],
        @[@"↑",@"bringForward"],@[@"↓",@"sendBack"],
        @[@"🗑",@"deleteElement"],
        @[@"⬛",@"bgColor"],@[@"🌅",@"bgImage"],
        @[@"↩",@"undo"],@[@"↪",@"redo"],
        @[@"⌫",@"deleteSlide"],@[@"📋",@"dupSlide"],
        @[@"🔀",@"transition"],@[@"📝",@"notes"],
        @[@"🔍+",@"zoomIn"],@[@"🔍-",@"zoomOut"],
        @[@"⛶",@"fitScreen"],
    ];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 2;
    [self.toolbarScroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.toolbarScroll.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.toolbarScroll.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.toolbarScroll.trailingAnchor],
        [stack.heightAnchor constraintEqualToAnchor:self.toolbarScroll.heightAnchor],
    ]];

    for (NSArray *t in tools) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [btn setTitle:t[0] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:12];
        btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
        btn.layer.cornerRadius = 5;
        [btn.widthAnchor constraintEqualToConstant:34].active = YES;
        [btn setAccessibilityIdentifier:t[1]];
        [btn addTarget:self action:@selector(toolTapped:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
    }
}

- (void)toolTapped:(UIButton *)btn {
    NSString *action = btn.accessibilityIdentifier;
    if ([action isEqualToString:@"addText"]) [self addTextElement];
    else if ([action isEqualToString:@"addShape"]) [self addShapeElement:ShapeRect];
    else if ([action isEqualToString:@"addEllipse"]) [self addShapeElement:ShapeEllipse];
    else if ([action isEqualToString:@"addImage"]) [self pickImageForElement];
    else if ([action isEqualToString:@"bold"]) [self toggleBold];
    else if ([action isEqualToString:@"italic"]) [self toggleItalic];
    else if ([action isEqualToString:@"underline"]) [self toggleUnderline];
    else if ([action isEqualToString:@"textColor"]) [self pickColorForKey:@"text"];
    else if ([action isEqualToString:@"fillColor"]) [self pickColorForKey:@"fill"];
    else if ([action isEqualToString:@"alignLeft"]) [self setAlignment:NSTextAlignmentLeft];
    else if ([action isEqualToString:@"alignCenter"]) [self setAlignment:NSTextAlignmentCenter];
    else if ([action isEqualToString:@"alignRight"]) [self setAlignment:NSTextAlignmentRight];
    else if ([action isEqualToString:@"fontSize+"]) [self adjustFontSize:2];
    else if ([action isEqualToString:@"fontSize-"]) [self adjustFontSize:-2];
    else if ([action isEqualToString:@"bringForward"]) [self changeZIndex:1];
    else if ([action isEqualToString:@"sendBack"]) [self changeZIndex:-1];
    else if ([action isEqualToString:@"deleteElement"]) [self deleteSelectedElement];
    else if ([action isEqualToString:@"bgColor"]) [self pickSlideBackground];
    else if ([action isEqualToString:@"bgImage"]) [self pickBackgroundImage];
    else if ([action isEqualToString:@"undo"]) [self performUndo];
    else if ([action isEqualToString:@"redo"]) [self performRedo];
    else if ([action isEqualToString:@"deleteSlide"]) [self deleteCurrentSlide];
    else if ([action isEqualToString:@"dupSlide"]) [self duplicateCurrentSlide];
    else if ([action isEqualToString:@"transition"]) [self showTransitionPicker];
    else if ([action isEqualToString:@"notes"]) [self toggleNotes];
    else if ([action isEqualToString:@"zoomIn"]) [self zoom:1.2];
    else if ([action isEqualToString:@"zoomOut"]) [self zoom:1.0/1.2];
    else if ([action isEqualToString:@"fitScreen"]) [self fitToScreen];
}

#pragma mark - Notes Panel

- (void)setupNotesPanel {
    UILabel *notesHeader = [[UILabel alloc] init];
    notesHeader.translatesAutoresizingMaskIntoConstraints = NO;
    notesHeader.text = @"📝 スピーカーノート";
    notesHeader.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    notesHeader.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    [self.bottomPanel addSubview:notesHeader];

    self.notesView = [[UITextView alloc] init];
    self.notesView.translatesAutoresizingMaskIntoConstraints = NO;
    self.notesView.backgroundColor = [UIColor clearColor];
    self.notesView.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.notesView.font = [UIFont systemFontOfSize:12];
    [self.bottomPanel addSubview:self.notesView];

    [NSLayoutConstraint activateConstraints:@[
        [notesHeader.topAnchor constraintEqualToAnchor:self.bottomPanel.topAnchor constant:4],
        [notesHeader.leadingAnchor constraintEqualToAnchor:self.bottomPanel.leadingAnchor constant:12],
        [self.notesView.topAnchor constraintEqualToAnchor:notesHeader.bottomAnchor constant:2],
        [self.notesView.leadingAnchor constraintEqualToAnchor:self.bottomPanel.leadingAnchor constant:8],
        [self.notesView.trailingAnchor constraintEqualToAnchor:self.bottomPanel.trailingAnchor constant:-8],
        [self.notesView.bottomAnchor constraintEqualToAnchor:self.bottomPanel.bottomAnchor constant:-4],
    ]];
}

- (void)toggleNotes {
    self.showNotes = !self.showNotes;
    [UIView animateWithDuration:0.3 animations:^{
        self.bottomPanelHeightConstraint.constant = self.showNotes ? 120 : 0;
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - Slide Management

- (void)selectSlide:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)self.slides.count) return;
    // Save notes for current slide
    if (self.currentSlideIndex < (NSInteger)self.slides.count) {
        self.slides[self.currentSlideIndex].speakerNotes = self.notesView.text ?: @"";
    }
    self.currentSlideIndex = idx;
    Slide *slide = self.slides[idx];
    self.canvas.slide = slide;
    [self.canvas reloadSlide];
    self.notesView.text = slide.speakerNotes;
    [self.thumbnailCollection reloadData];
    [self.thumbnailCollection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:idx inSection:0]
        atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
}

- (void)addSlide {
    [self saveUndo];
    Slide *s = [[Slide alloc] init];
    // Add default title + body
    SlideElement *title = [[SlideElement alloc] init];
    title.type = SlideElementText;
    title.text = @"スライドタイトル";
    title.frame = CGRectMake(0.05, 0.1, 0.9, 0.15);
    title.bold = YES;
    UIFontDescriptor *d = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleTitle1] fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    title.font = [UIFont fontWithDescriptor:d size:28];
    title.textAlignment = NSTextAlignmentCenter;
    [s.elements addObject:title];

    SlideElement *body = [[SlideElement alloc] init];
    body.type = SlideElementText;
    body.text = @"• ここに内容を入力してください\n• ポイント2\n• ポイント3";
    body.frame = CGRectMake(0.05, 0.3, 0.9, 0.6);
    body.font = [UIFont systemFontOfSize:18];
    body.zIndex = 1;
    [s.elements addObject:body];

    NSInteger insertIdx = self.currentSlideIndex + 1;
    [self.slides insertObject:s atIndex:insertIdx];
    [self selectSlide:insertIdx];
}

- (void)deleteCurrentSlide {
    if (self.slides.count <= 1) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"スライドを削除"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [self saveUndo];
        [self.slides removeObjectAtIndex:self.currentSlideIndex];
        NSInteger newIdx = MAX(0, self.currentSlideIndex - 1);
        [self selectSlide:newIdx];
        [self.thumbnailCollection reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)duplicateCurrentSlide {
    [self saveUndo];
    Slide *src = self.slides[self.currentSlideIndex];
    Slide *dup = [[Slide alloc] init];
    dup.backgroundColor = src.backgroundColor;
    dup.backgroundImage = src.backgroundImage;
    dup.speakerNotes = src.speakerNotes;
    dup.transitionType = src.transitionType;
    dup.transitionDuration = src.transitionDuration;
    for (SlideElement *el in src.elements) [dup.elements addObject:[el mutableCopy]];
    [self.slides insertObject:dup atIndex:self.currentSlideIndex + 1];
    [self selectSlide:self.currentSlideIndex + 1];
    [self.thumbnailCollection reloadData];
}

- (void)nextSlide {
    if (self.currentSlideIndex + 1 < (NSInteger)self.slides.count)
        [self selectSlide:self.currentSlideIndex + 1];
}

- (void)prevSlide {
    if (self.currentSlideIndex > 0)
        [self selectSlide:self.currentSlideIndex - 1];
}

#pragma mark - Element Operations

- (void)addTextElement {
    [self saveUndo];
    SlideElement *el = [[SlideElement alloc] init];
    el.type = SlideElementText;
    el.text = @"テキストを入力";
    el.frame = CGRectMake(0.1, 0.4, 0.8, 0.2);
    el.font = [UIFont systemFontOfSize:18];
    el.zIndex = (NSInteger)self.slides[self.currentSlideIndex].elements.count;
    [self.slides[self.currentSlideIndex].elements addObject:el];
    self.selectedElementIndex = (NSInteger)self.slides[self.currentSlideIndex].elements.count - 1;
    [self.canvas reloadSlide];
    [self editTextElement:el];
}

- (void)editTextElement:(SlideElement *)el {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"テキストを編集"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = el.text;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"確定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self saveUndo];
        el.text = a.textFields.firstObject.text ?: @"";
        [self.canvas reloadSlide];
        [self.thumbnailCollection reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)addShapeElement:(ShapeType)shape {
    [self saveUndo];
    SlideElement *el = [[SlideElement alloc] init];
    el.type = SlideElementShape;
    el.shapeType = shape;
    el.frame = CGRectMake(0.2, 0.2, 0.3, 0.3);
    el.fillColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.5];
    el.strokeColor = [UIColor systemBlueColor];
    el.strokeWidth = 2;
    el.zIndex = (NSInteger)self.slides[self.currentSlideIndex].elements.count;
    [self.slides[self.currentSlideIndex].elements addObject:el];
    self.selectedElementIndex = (NSInteger)self.slides[self.currentSlideIndex].elements.count - 1;
    [self.canvas reloadSlide];
}

- (void)pickImageForElement {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    BOOL acc = [url startAccessingSecurityScopedResource];
    UIImage *img = [UIImage imageWithContentsOfFile:url.path];
    if (acc) [url stopAccessingSecurityScopedResource];
    if (!img) return;

    [self saveUndo];
    SlideElement *el = [[SlideElement alloc] init];
    el.type = SlideElementImage;
    el.image = img;
    el.frame = CGRectMake(0.1, 0.2, 0.5, 0.5 * (img.size.height / img.size.width));
    el.zIndex = (NSInteger)self.slides[self.currentSlideIndex].elements.count;
    [self.slides[self.currentSlideIndex].elements addObject:el];
    self.selectedElementIndex = (NSInteger)self.slides[self.currentSlideIndex].elements.count - 1;
    [self.canvas reloadSlide];
    [self.thumbnailCollection reloadData];
}

- (SlideElement *)selectedElement {
    Slide *slide = self.slides[self.currentSlideIndex];
    if (self.selectedElementIndex < 0 || self.selectedElementIndex >= (NSInteger)slide.elements.count) return nil;
    return slide.elements[self.selectedElementIndex];
}

- (void)toggleBold {
    SlideElement *el = [self selectedElement]; if (!el) return;
    [self saveUndo]; el.bold = !el.bold; [self.canvas reloadSlide];
}
- (void)toggleItalic {
    SlideElement *el = [self selectedElement]; if (!el) return;
    [self saveUndo]; el.italic = !el.italic; [self.canvas reloadSlide];
}
- (void)toggleUnderline {
    SlideElement *el = [self selectedElement]; if (!el) return;
    [self saveUndo]; el.underline = !el.underline; [self.canvas reloadSlide];
}
- (void)setAlignment:(NSTextAlignment)align {
    SlideElement *el = [self selectedElement]; if (!el) return;
    [self saveUndo]; el.textAlignment = align; [self.canvas reloadSlide];
}
- (void)adjustFontSize:(CGFloat)delta {
    SlideElement *el = [self selectedElement]; if (!el) return;
    [self saveUndo];
    CGFloat cur = el.font ? el.font.pointSize : 18;
    el.font = [UIFont systemFontOfSize:MAX(8, cur + delta)];
    [self.canvas reloadSlide];
}
- (void)changeZIndex:(NSInteger)delta {
    SlideElement *el = [self selectedElement]; if (!el) return;
    [self saveUndo]; el.zIndex += delta; [self.canvas reloadSlide];
}
- (void)deleteSelectedElement {
    if (self.selectedElementIndex < 0) return;
    [self saveUndo];
    [self.slides[self.currentSlideIndex].elements removeObjectAtIndex:self.selectedElementIndex];
    self.selectedElementIndex = -1;
    [self.canvas reloadSlide];
    [self.thumbnailCollection reloadData];
}

- (void)pickColorForKey:(NSString *)key {
    SlideElement *el = [self selectedElement];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:
        [key isEqualToString:@"text"] ? @"テキストカラー" : @"塗りつぶし"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *colors = @{@"白":[UIColor whiteColor],@"黒":[UIColor blackColor],
        @"赤":[UIColor systemRedColor],@"緑":[UIColor systemGreenColor],
        @"青":[UIColor systemBlueColor],@"黄":[UIColor systemYellowColor],
        @"オレンジ":[UIColor systemOrangeColor],@"紫":[UIColor systemPurpleColor],
        @"透明":[UIColor clearColor]};
    for (NSString *name in colors) {
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            if (!el) return;
            [self saveUndo];
            if ([key isEqualToString:@"text"]) el.textColor = colors[name];
            else el.fillColor = colors[name];
            [self.canvas reloadSlide];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickSlideBackground {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"スライド背景" message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *colors = @{
        @"ダーク": [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1],
        @"黒": [UIColor blackColor], @"白": [UIColor whiteColor],
        @"ネイビー": [UIColor colorWithRed:0.05 green:0.1 blue:0.3 alpha:1],
        @"グレー": [UIColor darkGrayColor],
        @"深緑": [UIColor colorWithRed:0.0 green:0.2 blue:0.1 alpha:1],
    };
    for (NSString *name in colors) {
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            [self saveUndo];
            self.slides[self.currentSlideIndex].backgroundColor = colors[name];
            [self.canvas reloadSlide];
            [self.thumbnailCollection reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickBackgroundImage {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self;
    objc_setAssociatedObject(picker, "bgMode", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - Zoom

- (void)zoom:(CGFloat)factor {
    CGFloat newZoom = MAX(0.3, MIN(4.0, self.canvasScroll.zoomScale * factor));
    [self.canvasScroll setZoomScale:newZoom animated:YES];
}

- (void)fitToScreen {
    CGFloat availW = CGRectGetWidth(self.mainPanel.bounds) > 0 ? CGRectGetWidth(self.mainPanel.bounds) : (CGRectGetWidth(self.view.bounds) - 110);
    CGFloat scaleW = availW / self.canvas.bounds.size.width;
    CGFloat scaleH = (CGRectGetHeight(self.view.bounds) - 200) / self.canvas.bounds.size.height;
    [self.canvasScroll setZoomScale:MIN(scaleW, scaleH) animated:YES];
}

#pragma mark - Transition

- (void)showTransitionPicker {
    Slide *slide = self.slides[self.currentSlideIndex];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"スライドのトランジション"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *trans = @[@"なし", @"フェード", @"スライド", @"ズーム", @"フリップ", @"ワイプ"];
    for (NSInteger i = 0; i < (NSInteger)trans.count; i++) {
        [a addAction:[UIAlertAction actionWithTitle:trans[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            slide.transitionType = i;
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Properties Panel

- (void)showPropertiesPanelForElement:(NSInteger)idx {
    // Simple inline approach — show a floating panel at bottom
}

- (void)hidePropertiesPanel {}

#pragma mark - Presentation Mode

- (void)startPresentation {
    if (self.slides.count == 0) return;

    UIViewController *presenter = [[UIViewController alloc] init];
    presenter.view.backgroundColor = [UIColor blackColor];
    presenter.modalPresentationStyle = UIModalPresentationFullScreen;

    __block NSInteger currentIdx = self.currentSlideIndex;
    NSArray *slides = [self.slides copy];

    SlideCanvasView *canvas = [[SlideCanvasView alloc] initWithFrame:self.view.bounds];
    canvas.isEditing = NO;
    canvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    canvas.slide = slides[currentIdx];
    [canvas reloadSlide];
    [presenter.view addSubview:canvas];

    // Slide counter
    UILabel *counter = [[UILabel alloc] init];
    counter.translatesAutoresizingMaskIntoConstraints = NO;
    counter.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    counter.font = [UIFont systemFontOfSize:13];
    counter.text = [NSString stringWithFormat:@"%ld / %ld", (long)(currentIdx+1), (long)slides.count];
    [presenter.view addSubview:counter];
    [NSLayoutConstraint activateConstraints:@[
        [counter.bottomAnchor constraintEqualToAnchor:presenter.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [counter.centerXAnchor constraintEqualToAnchor:presenter.view.centerXAnchor],
    ]];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeBtn.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    [closeBtn addTarget:self action:@selector(endPresentation) forControlEvents:UIControlEventTouchUpInside];
    [presenter.view addSubview:closeBtn];
    [NSLayoutConstraint activateConstraints:@[
        [closeBtn.topAnchor constraintEqualToAnchor:presenter.view.safeAreaLayoutGuide.topAnchor constant:8],
        [closeBtn.trailingAnchor constraintEqualToAnchor:presenter.view.trailingAnchor constant:-16],
        [closeBtn.widthAnchor constraintEqualToConstant:44],
        [closeBtn.heightAnchor constraintEqualToConstant:44],
    ]];

    // Tap = next, swipe left = next, swipe right = prev
    void (^advance)(BOOL) = ^(BOOL forward) {
        NSInteger next = currentIdx + (forward ? 1 : -1);
        if (next < 0 || next >= (NSInteger)slides.count) {
            if (!forward) return;
            [presenter dismissViewControllerAnimated:YES completion:nil]; return;
        }
        Slide *nextSlide = slides[next];
        UIViewAnimationOptions opts;
        switch (nextSlide.transitionType) {
            case 1: opts = UIViewAnimationOptionTransitionCrossDissolve; break;
            case 2: opts = forward ? UIViewAnimationOptionTransitionFlipFromRight : UIViewAnimationOptionTransitionFlipFromLeft; break;
            default: opts = UIViewAnimationOptionTransitionCrossDissolve; break;
        }
        [UIView transitionWithView:canvas duration:nextSlide.transitionDuration
            options:opts animations:^{
                canvas.slide = nextSlide;
                [canvas reloadSlide];
            } completion:nil];
        currentIdx = next;
        counter.text = [NSString stringWithFormat:@"%ld / %ld", (long)(currentIdx+1), (long)slides.count];
    };

    // Gesture target using block stored via associated objects
    NSObject *tapHandler  = [[NSObject alloc] init];
    objc_setAssociatedObject(presenter.view, "advance", [advance copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(presenter.view, "canvas", canvas, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(presentationTapNext:)];
    tap.numberOfTapsRequired = 1;
    [presenter.view addGestureRecognizer:tap];
    UISwipeGestureRecognizer *sl = [[UISwipeGestureRecognizer alloc]
        initWithTarget:self action:@selector(presentationSwipeLeft:)];
    sl.direction = UISwipeGestureRecognizerDirectionLeft;
    UISwipeGestureRecognizer *sr = [[UISwipeGestureRecognizer alloc]
        initWithTarget:self action:@selector(presentationSwipeRight:)];
    sr.direction = UISwipeGestureRecognizerDirectionRight;
    [presenter.view addGestureRecognizer:sl];
    [presenter.view addGestureRecognizer:sr];
    (void)tapHandler;

    self.isPresentingFullscreen = YES;
    [self presentViewController:presenter animated:YES completion:nil];
}

- (void)endPresentation {
    self.isPresentingFullscreen = NO;
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - CollectionView

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)sec {
    return self.slides.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SlideThumbnailCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"Thumb" forIndexPath:ip];
    [cell configureWithSlide:self.slides[ip.item]
                       index:ip.item
                  isSelected:(ip.item == self.currentSlideIndex)];
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [self selectSlide:ip.item];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv
contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)pt {
    NSInteger idx = ip.item;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil
        actionProvider:^UIMenu *(NSArray *_) {
            UIAction *dup = [UIAction actionWithTitle:@"複製" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *__) {
                [self selectSlide:idx]; [self duplicateCurrentSlide];
            }];
            UIAction *del = [UIAction actionWithTitle:@"削除" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *__) {
                [self selectSlide:idx]; [self deleteCurrentSlide];
            }];
            del.attributes = UIMenuElementAttributesDestructive;
            return [UIMenu menuWithTitle:@"" children:@[dup, del]];
        }];
}

#pragma mark - More Menu

- (void)showMoreMenu {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"📤 PDF でエクスポート" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self exportAsPDF]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"🖼 画像としてエクスポート" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self exportAsImages]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"📋 全スライドをテキストコピー" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self copyAllText]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"🔄 スライドを並べ替え" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { /* reorder UI */ }]];
    [a addAction:[UIAlertAction actionWithTitle:@"🎭 テーマを適用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { [self applyTheme]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)exportAsPDF {
    NSMutableData *pdfData = [NSMutableData data];
    CGFloat W = 1280, H = 720;
    UIGraphicsBeginPDFContextToData(pdfData, CGRectMake(0,0,W,H), nil);
    for (Slide *slide in self.slides) {
        UIGraphicsBeginPDFPageWithInfo(CGRectMake(0,0,W,H), nil);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        // Background
        CGContextSetFillColorWithColor(ctx, slide.backgroundColor.CGColor);
        CGContextFillRect(ctx, CGRectMake(0,0,W,H));
        // Elements
        for (SlideElement *el in slide.elements) {
            CGRect r = CGRectMake(el.frame.origin.x*W, el.frame.origin.y*H,
                                  el.frame.size.width*W, el.frame.size.height*H);
            if (el.type == SlideElementText && el.text.length) {
                NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
                ps.alignment = el.textAlignment;
                NSDictionary *attrs = @{NSFontAttributeName: el.font?:[UIFont systemFontOfSize:18],
                    NSForegroundColorAttributeName: el.textColor?:[UIColor whiteColor],
                    NSParagraphStyleAttributeName: ps};
                [el.text drawInRect:r withAttributes:attrs];
            }
        }
    }
    UIGraphicsEndPDFContext();

    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[self.filePath.lastPathComponent stringByDeletingPathExtension] stringByAppendingString:@".pdf"]];
    [pdfData writeToFile:tmp atomically:YES];
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)exportAsImages {
    NSMutableArray *images = [NSMutableArray array];
    CGFloat W = 1280, H = 720;
    for (Slide *slide in self.slides) {
        // iOS 17+: UIGraphicsImageRenderer
        UIGraphicsImageRenderer *_slideRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(W, H)];
        UIImage *img = [_slideRenderer imageWithActions:^(UIGraphicsImageRendererContext *_rc) {
            CGContextRef ctx = _rc.CGContext;
            CGContextSetFillColorWithColor(ctx, slide.backgroundColor.CGColor);
            CGContextFillRect(ctx, CGRectMake(0,0,W,H));
            for (SlideElement *el in slide.elements) {
                if (el.type == SlideElementText && el.text.length) {
                    CGRect r = CGRectMake(el.frame.origin.x*W, el.frame.origin.y*H,
                                          el.frame.size.width*W, el.frame.size.height*H);
                    [el.text drawInRect:r withAttributes:@{NSFontAttributeName:el.font?:[UIFont systemFontOfSize:18],
                        NSForegroundColorAttributeName:el.textColor?:[UIColor whiteColor]}];
                }
            }
        }];
        if (img) [images addObject:img];
    }
    UIActivityViewController *avc = [[UIActivityViewController alloc]
        initWithActivityItems:images applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)copyAllText {
    NSMutableString *out = [NSMutableString string];
    for (NSInteger i = 0; i < (NSInteger)self.slides.count; i++) {
        [out appendFormat:@"=== スライド %ld ===\n", (long)(i+1)];
        for (SlideElement *el in self.slides[i].elements) {
            if (el.type == SlideElementText && el.text.length)
                [out appendFormat:@"%@\n", el.text];
        }
        if (self.slides[i].speakerNotes.length)
            [out appendFormat:@"[ノート] %@\n", self.slides[i].speakerNotes];
        [out appendString:@"\n"];
    }
    [[UIPasteboard generalPasteboard] setString:out];
}

- (void)applyTheme {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"テーマを適用"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *themes = @{
        @"🌑 ダーク": @{@"bg":[UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1],@"text":[UIColor whiteColor]},
        @"🌕 ライト": @{@"bg":[UIColor whiteColor],@"text":[UIColor blackColor]},
        @"🌊 オーシャン": @{@"bg":[UIColor colorWithRed:0.02 green:0.1 blue:0.25 alpha:1],@"text":[UIColor cyanColor]},
        @"🌲 フォレスト": @{@"bg":[UIColor colorWithRed:0.02 green:0.15 blue:0.05 alpha:1],@"text":[UIColor greenColor]},
        @"🔥 サンセット": @{@"bg":[UIColor colorWithRed:0.2 green:0.05 blue:0.0 alpha:1],@"text":[UIColor orangeColor]},
    };
    for (NSString *name in themes) {
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            NSDictionary *t = themes[name];
            [self saveUndo];
            for (Slide *s in self.slides) {
                s.backgroundColor = t[@"bg"];
                for (SlideElement *el in s.elements) {
                    if (el.type == SlideElementText) el.textColor = t[@"text"];
                }
            }
            [self selectSlide:self.currentSlideIndex];
            [self.thumbnailCollection reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Undo/Redo

- (void)saveUndo {
    NSMutableArray *snapshot = [NSMutableArray array];
    for (Slide *s in self.slides) {
        Slide *dup = [[Slide alloc] init];
        dup.backgroundColor = s.backgroundColor;
        dup.speakerNotes = s.speakerNotes;
        dup.transitionType = s.transitionType;
        for (SlideElement *el in s.elements) [dup.elements addObject:[el mutableCopy]];
        [snapshot addObject:dup];
    }
    [self.undoStack addObject:snapshot];
    [self.redoStack removeAllObjects];
    if (self.undoStack.count > 30) [self.undoStack removeObjectAtIndex:0];
}

- (void)performUndo {
    if (!self.undoStack.count) return;
    // Save redo
    [self.redoStack addObject:[self.slides mutableCopy]];
    self.slides = [self.undoStack.lastObject mutableCopy];
    [self.undoStack removeLastObject];
    self.currentSlideIndex = MIN(self.currentSlideIndex, (NSInteger)self.slides.count - 1);
    [self selectSlide:self.currentSlideIndex];
    [self.thumbnailCollection reloadData];
}

- (void)performRedo {
    if (!self.redoStack.count) return;
    [self.undoStack addObject:[self.slides mutableCopy]];
    self.slides = [self.redoStack.lastObject mutableCopy];
    [self.redoStack removeLastObject];
    [self selectSlide:self.currentSlideIndex];
    [self.thumbnailCollection reloadData];
}

#pragma mark - Load / Save

- (void)loadPresentation {
    // Try to load JSON-based PPTX-like format; fall back to default
    NSData *data = [NSData dataWithContentsOfFile:self.filePath];
    if (data) {
        NSError *err;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (!err && [obj isKindOfClass:[NSArray class]]) {
            [self deserializeSlides:obj];
            return;
        }
    }
    // Default: 3 sample slides
    [self createDefaultPresentation];
}

- (void)createDefaultPresentation {
    [self.slides removeAllObjects];
    NSArray *titles = @[@"プレゼンテーション", @"内容", @"まとめ"];
    NSArray *bodies = @[@"サブタイトルを入力してください", @"• ポイント1\n• ポイント2\n• ポイント3", @"• 結論\n• 次のステップ"];
    NSArray *bgColors = @[
        [UIColor colorWithRed:0.08 green:0.08 blue:0.18 alpha:1],
        [UIColor colorWithRed:0.05 green:0.12 blue:0.08 alpha:1],
        [UIColor colorWithRed:0.15 green:0.05 blue:0.05 alpha:1],
    ];
    for (NSInteger i = 0; i < 3; i++) {
        Slide *s = [[Slide alloc] init];
        s.backgroundColor = bgColors[i];
        // Title
        SlideElement *t = [[SlideElement alloc] init];
        t.type = SlideElementText; t.text = titles[i];
        t.frame = CGRectMake(0.05,0.12,0.9,0.18);
        t.bold = YES; t.textAlignment = NSTextAlignmentCenter;
        t.font = [UIFont boldSystemFontOfSize:28]; t.zIndex = 1;
        // Body
        SlideElement *b = [[SlideElement alloc] init];
        b.type = SlideElementText; b.text = bodies[i];
        b.frame = CGRectMake(0.05,0.35,0.9,0.55);
        b.font = [UIFont systemFontOfSize:16]; b.zIndex = 2;
        [s.elements addObject:t]; [s.elements addObject:b];
        [self.slides addObject:s];
    }
}

- (void)savePresentation {
    NSMutableArray *data = [NSMutableArray array];
    for (Slide *s in self.slides) {
        NSMutableDictionary *sd = [NSMutableDictionary dictionary];
        // Serialize bg color
        CGFloat r,g,b,a;
        [s.backgroundColor getRed:&r green:&g blue:&b alpha:&a];
        sd[@"bg"] = @[@(r),@(g),@(b),@(a)];
        sd[@"notes"] = s.speakerNotes ?: @"";
        sd[@"transition"] = @(s.transitionType);
        NSMutableArray *els = [NSMutableArray array];
        for (SlideElement *el in s.elements) {
            NSMutableDictionary *ed = [NSMutableDictionary dictionary];
            ed[@"type"] = @(el.type); ed[@"text"] = el.text ?: @"";
            ed[@"frame"] = @[@(el.frame.origin.x),@(el.frame.origin.y),@(el.frame.size.width),@(el.frame.size.height)];
            ed[@"bold"] = @(el.bold); ed[@"italic"] = @(el.italic); ed[@"underline"] = @(el.underline);
            ed[@"align"] = @(el.textAlignment); ed[@"zIndex"] = @(el.zIndex);
            ed[@"shape"] = @(el.shapeType); ed[@"rotation"] = @(el.rotation);
            if (el.font) ed[@"fontSize"] = @(el.font.pointSize);
            if (el.textColor) {
                [el.textColor getRed:&r green:&g blue:&b alpha:&a];
                ed[@"textColor"] = @[@(r),@(g),@(b),@(a)];
            }
            [els addObject:ed];
        }
        sd[@"elements"] = els;
        [data addObject:sd];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:self.filePath atomically:YES];
}

- (void)deserializeSlides:(NSArray *)raw {
    for (NSDictionary *sd in raw) {
        Slide *s = [[Slide alloc] init];
        NSArray *bg = sd[@"bg"];
        if (bg.count >= 4) s.backgroundColor = [UIColor colorWithRed:[bg[0] floatValue] green:[bg[1] floatValue] blue:[bg[2] floatValue] alpha:[bg[3] floatValue]];
        s.speakerNotes = sd[@"notes"] ?: @"";
        s.transitionType = [sd[@"transition"] integerValue];
        for (NSDictionary *ed in sd[@"elements"]) {
            SlideElement *el = [[SlideElement alloc] init];
            el.type = [ed[@"type"] unsignedIntegerValue];
            el.text = ed[@"text"] ?: @"";
            NSArray *f = ed[@"frame"];
            if (f.count >= 4) el.frame = CGRectMake([f[0] floatValue],[f[1] floatValue],[f[2] floatValue],[f[3] floatValue]);
            el.bold = [ed[@"bold"] boolValue]; el.italic = [ed[@"italic"] boolValue];
            el.underline = [ed[@"underline"] boolValue];
            el.textAlignment = [ed[@"align"] integerValue];
            el.zIndex = [ed[@"zIndex"] integerValue];
            el.shapeType = [ed[@"shape"] unsignedIntegerValue];
            el.rotation = [ed[@"rotation"] floatValue];
            if (ed[@"fontSize"]) el.font = [UIFont systemFontOfSize:[ed[@"fontSize"] floatValue]];
            NSArray *tc = ed[@"textColor"];
            if (tc.count >= 4) el.textColor = [UIColor colorWithRed:[tc[0] floatValue] green:[tc[1] floatValue] blue:[tc[2] floatValue] alpha:[tc[3] floatValue]];
            [s.elements addObject:el];
        }
        [self.slides addObject:s];
    }
    if (self.slides.count == 0) [self createDefaultPresentation];
}

@end
