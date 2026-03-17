// ExcelViewerViewController.m  — Rev.3
// Full spreadsheet editor: grid UI, multi-sheet, formulas, formatting, charts, sort/filter, freeze, undo/redo

#import "ExcelViewerViewController.h"
#import "ThemeEngine.h"
#import "CustomMenuView.h"

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Cell Model

typedef NS_ENUM(NSUInteger, CellAlignment) { CellAlignLeft, CellAlignCenter, CellAlignRight };
typedef NS_ENUM(NSUInteger, CellType)      { CellTypeText, CellTypeNumber, CellTypeFormula };

@interface SpreadCell : NSObject <NSCopying>
@property (nonatomic, copy)   NSString    *raw;      // user-entered value/formula
@property (nonatomic, copy)   NSString    *display;  // computed display
@property (nonatomic, strong) UIFont      *font;
@property (nonatomic, strong) UIColor     *textColor;
@property (nonatomic, strong) UIColor     *bgColor;
@property (nonatomic, assign) CellAlignment alignment;
@property (nonatomic, assign) CellType    type;
@property (nonatomic, assign) BOOL        bold;
@property (nonatomic, assign) BOOL        italic;
@property (nonatomic, assign) NSInteger   fontSize;
@property (nonatomic, assign) BOOL        hasTopBorder, hasBottomBorder, hasLeftBorder, hasRightBorder;
- (id)copyWithZone:(NSZone *)zone;
@end

@implementation SpreadCell
- (instancetype)init {
    self=[super init]; if(!self) return nil;
    _raw=@""; _display=@"";
    _textColor=[UIColor whiteColor];
    _bgColor=[UIColor clearColor];
    _alignment=CellAlignLeft;
    _type=CellTypeText;
    _fontSize=13;
    return self;
}
- (id)copyWithZone:(NSZone *)z {
    SpreadCell *c=[SpreadCell new];
    c.raw=self.raw; c.display=self.display;
    c.font=self.font; c.textColor=self.textColor; c.bgColor=self.bgColor;
    c.alignment=self.alignment; c.type=self.type;
    c.bold=self.bold; c.italic=self.italic; c.fontSize=self.fontSize;
    c.hasTopBorder=self.hasTopBorder; c.hasBottomBorder=self.hasBottomBorder;
    c.hasLeftBorder=self.hasLeftBorder; c.hasRightBorder=self.hasRightBorder;
    return c;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Sheet Model

@interface SpreadSheet : NSObject
@property (nonatomic, copy)   NSString   *name;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SpreadCell *> *cells; // key: "R3C5"
@property (nonatomic, assign) NSInteger   rowCount;
@property (nonatomic, assign) NSInteger   colCount;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *colWidths;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *rowHeights;
@property (nonatomic, assign) NSInteger   frozenRows;
@property (nonatomic, assign) NSInteger   frozenCols;
- (SpreadCell *)cellAtRow:(NSInteger)r col:(NSInteger)c;
- (void)setCell:(SpreadCell *)cell row:(NSInteger)r col:(NSInteger)c;
- (NSString *)keyForRow:(NSInteger)r col:(NSInteger)c;
@end

@implementation SpreadSheet
- (instancetype)initWithName:(NSString *)name rows:(NSInteger)rows cols:(NSInteger)cols {
    self=[super init]; if(!self) return nil;
    _name=name; _rowCount=rows; _colCount=cols;
    _cells=[NSMutableDictionary dictionary];
    _colWidths=[NSMutableArray array];
    _rowHeights=[NSMutableArray array];
    _frozenRows=0; _frozenCols=0;
    for(NSInteger i=0;i<cols;i++) [_colWidths addObject:@(90)];
    for(NSInteger i=0;i<rows;i++) [_rowHeights addObject:@(28)];
    return self;
}
- (NSString *)keyForRow:(NSInteger)r col:(NSInteger)c { return [NSString stringWithFormat:@"R%ldC%ld",(long)r,(long)c]; }
- (SpreadCell *)cellAtRow:(NSInteger)r col:(NSInteger)c {
    return self.cells[[self keyForRow:r col:c]];
}
- (void)setCell:(SpreadCell *)cell row:(NSInteger)r col:(NSInteger)c {
    self.cells[[self keyForRow:r col:c]] = cell;
}
@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Formula Engine

@interface FormulaEngine : NSObject
+ (NSString *)evaluate:(NSString *)formula sheet:(SpreadSheet *)sheet;
+ (double)numberValue:(NSString *)s;
+ (NSArray<NSArray *> *)rangeForSpec:(NSString *)spec sheet:(SpreadSheet *)sheet;
@end

@implementation FormulaEngine

+ (NSString *)evaluate:(NSString *)formula sheet:(SpreadSheet *)sheet {
    NSString *f = [formula uppercaseString];
    if ([f hasPrefix:@"=SUM("]) {
        double s = [self sumRange:[self argFrom:f] sheet:sheet];
        return [self formatNum:s];
    }
    if ([f hasPrefix:@"=AVERAGE("]) {
        NSArray *vals = [self valuesForRange:[self argFrom:f] sheet:sheet];
        if (!vals.count) return @"0";
        double sum=0; for(NSNumber *n in vals) sum+=n.doubleValue;
        return [self formatNum:sum/vals.count];
    }
    if ([f hasPrefix:@"=COUNT("]) {
        return [NSString stringWithFormat:@"%lu",(unsigned long)[self valuesForRange:[self argFrom:f] sheet:sheet].count];
    }
    if ([f hasPrefix:@"=MAX("]) {
        NSArray *vals=[self valuesForRange:[self argFrom:f] sheet:sheet];
        if(!vals.count) return @"0";
        double m=[vals.firstObject doubleValue];
        for(NSNumber *n in vals) if(n.doubleValue>m) m=n.doubleValue;
        return [self formatNum:m];
    }
    if ([f hasPrefix:@"=MIN("]) {
        NSArray *vals=[self valuesForRange:[self argFrom:f] sheet:sheet];
        if(!vals.count) return @"0";
        double m=[vals.firstObject doubleValue];
        for(NSNumber *n in vals) if(n.doubleValue<m) m=n.doubleValue;
        return [self formatNum:m];
    }
    if ([f hasPrefix:@"=IF("]) {
        return [self evaluateIF:f sheet:sheet];
    }
    if ([f hasPrefix:@"=CONCATENATE("]) {
        return [self evaluateCONCAT:f sheet:sheet];
    }
    if ([f hasPrefix:@"=LEN("]) {
        NSString *arg=[self argFrom:f];
        SpreadCell *c=[self cellFromRef:arg sheet:sheet];
        return [NSString stringWithFormat:@"%lu",(unsigned long)(c?c.display.length:[arg length])];
    }
    if ([f hasPrefix:@"=UPPER("]) {
        SpreadCell *c=[self cellFromRef:[self argFrom:f] sheet:sheet];
        return c ? [c.display uppercaseString] : [[self argFrom:f] uppercaseString];
    }
    if ([f hasPrefix:@"=LOWER("]) {
        SpreadCell *c=[self cellFromRef:[self argFrom:f] sheet:sheet];
        return c ? [c.display lowercaseString] : [[self argFrom:f] lowercaseString];
    }
    if ([f hasPrefix:@"=ROUND("]) {
        NSArray *parts=[[self argFrom:f] componentsSeparatedByString:@","];
        if(parts.count<2) return @"0";
        double val=[self numberValue:[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        NSInteger digits=[[parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] integerValue];
        double factor=pow(10,digits);
        return [self formatNum:round(val*factor)/factor];
    }
    if ([f hasPrefix:@"=ABS("]) {
        double v=[self numberValue:[self argFrom:f]];
        return [self formatNum:fabs(v)];
    }
    if ([f hasPrefix:@"=SQRT("]) {
        double v=[self numberValue:[self argFrom:f]];
        return v>=0 ? [self formatNum:sqrt(v)] : @"#NUM!";
    }
    if ([f hasPrefix:@"=POWER("]) {
        NSArray *parts=[[self argFrom:f] componentsSeparatedByString:@","];
        if(parts.count<2) return @"0";
        double base=[self numberValue:parts[0]], expVal=[self numberValue:parts[1]];
        return [self formatNum:pow(base,expVal)];
    }
    if ([f hasPrefix:@"=NOW("]) {
        NSDateFormatter *fmt=[[NSDateFormatter alloc] init];
        fmt.dateFormat=@"yyyy-MM-dd HH:mm:ss";
        return [fmt stringFromDate:[NSDate date]];
    }
    if ([f hasPrefix:@"=TODAY("]) {
        NSDateFormatter *fmt=[[NSDateFormatter alloc] init];
        fmt.dateFormat=@"yyyy-MM-dd";
        return [fmt stringFromDate:[NSDate date]];
    }
    // Simple arithmetic: =A1+B1, =A1*2, etc.
    if ([f hasPrefix:@"="]) {
        return [self evalArithmetic:[f substringFromIndex:1] sheet:sheet];
    }
    return formula;
}

+ (NSString *)argFrom:(NSString *)f {
    NSRange open=  [f rangeOfString:@"("];
    NSRange close= [f rangeOfString:@")" options:NSBackwardsSearch];
    if(open.location==NSNotFound||close.location==NSNotFound) return @"";
    NSInteger start=open.location+1;
    NSInteger len=close.location-start;
    if(len<=0) return @"";
    return [f substringWithRange:NSMakeRange(start,len)];
}

+ (double)sumRange:(NSString *)rangeSpec sheet:(SpreadSheet *)sheet {
    double s=0;
    for(NSNumber *n in [self valuesForRange:rangeSpec sheet:sheet]) s+=n.doubleValue;
    return s;
}

+ (NSArray<NSNumber *> *)valuesForRange:(NSString *)spec sheet:(SpreadSheet *)sheet {
    NSMutableArray *vals=[NSMutableArray array];
    // Support A1:B3 format and single cell
    NSArray *parts=[spec componentsSeparatedByString:@":"];
    if(parts.count==2) {
        NSInteger r1,c1,r2,c2;
        [self parseRef:parts[0] row:&r1 col:&c1];
        [self parseRef:parts[1] row:&r2 col:&c2];
        for(NSInteger r=r1;r<=r2;r++) for(NSInteger c=c1;c<=c2;c++) {
            SpreadCell *cell=[sheet cellAtRow:r col:c];
            if(cell.display.length) {
                double v=[self numberValue:cell.display];
                [vals addObject:@(v)];
            }
        }
    } else {
        // Single cell or literal
        NSInteger r,c;
        if([self parseRef:spec row:&r col:&c]) {
            SpreadCell *cell=[sheet cellAtRow:r col:c];
            if(cell) [vals addObject:@([self numberValue:cell.display])];
        } else {
            double v=[self numberValue:spec];
            if(v!=0||[spec isEqualToString:@"0"]) [vals addObject:@(v)];
        }
    }
    return vals;
}

+ (BOOL)parseRef:(NSString *)ref row:(NSInteger *)r col:(NSInteger *)c {
    // e.g. "A1", "B12", "AA3"
    NSString *up=[ref uppercaseString];
    NSInteger ci=0, ri=0, i=0;
    while(i<(NSInteger)up.length && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[up characterAtIndex:i]]) {
        ci=ci*26+([up characterAtIndex:i]-'A'+1); i++;
    }
    while(i<(NSInteger)up.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[up characterAtIndex:i]]) {
        ri=ri*10+([up characterAtIndex:i]-'0'); i++;
    }
    if(ci<=0||ri<=0) return NO;
    *c=ci-1; *r=ri-1;
    return YES;
}

+ (SpreadCell *)cellFromRef:(NSString *)ref sheet:(SpreadSheet *)sheet {
    NSInteger r,c;
    if([self parseRef:ref row:&r col:&c]) return [sheet cellAtRow:r col:c];
    return nil;
}

+ (NSString *)evaluateIF:(NSString *)f sheet:(SpreadSheet *)sheet {
    NSString *args=[self argFrom:f];
    NSArray *parts=[args componentsSeparatedByString:@","];
    if(parts.count<3) return @"#ERR";
    NSString *cond=[parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *trueV=[parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *falseV=[parts[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // Simple comparison
    BOOL result=NO;
    if([cond containsString:@">="]) {
        NSArray *cp=[cond componentsSeparatedByString:@">="];
        result=[self numberValue:cp[0]]>=[self numberValue:cp[1]];
    } else if([cond containsString:@"<="]) {
        NSArray *cp=[cond componentsSeparatedByString:@"<="];
        result=[self numberValue:cp[0]]<=[self numberValue:cp[1]];
    } else if([cond containsString:@"<>"]) {
        NSArray *cp=[cond componentsSeparatedByString:@"<>"];
        result=([self numberValue:cp[0]] != [self numberValue:cp[1]]);
    } else if([cond containsString:@">"]) {
        NSArray *cp=[cond componentsSeparatedByString:@">"];
        result=[self numberValue:cp[0]]>[self numberValue:cp[1]];
    } else if([cond containsString:@"<"]) {
        NSArray *cp=[cond componentsSeparatedByString:@"<"];
        result=[self numberValue:cp[0]]<[self numberValue:cp[1]];
    } else if([cond containsString:@"="]) {
        NSArray *cp=[cond componentsSeparatedByString:@"="];
        result=[self numberValue:cp[0]]==[self numberValue:cp[1]];
    }
    return result ? trueV : falseV;
}

+ (NSString *)evaluateCONCAT:(NSString *)f sheet:(SpreadSheet *)sheet {
    NSString *args=[self argFrom:f];
    NSMutableString *result=[NSMutableString string];
    for(NSString *part in [args componentsSeparatedByString:@","]) {
        NSString *p=[part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        SpreadCell *c=[self cellFromRef:p sheet:sheet];
        [result appendString:c?c.display:p];
    }
    return result;
}

+ (NSString *)evalArithmetic:(NSString *)expr sheet:(SpreadSheet *)sheet {
    // Replace cell refs with values
    NSMutableString *e=[expr mutableCopy];
    NSRegularExpression *reg=[NSRegularExpression regularExpressionWithPattern:@"[A-Z]+[0-9]+" options:0 error:nil];
    NSArray *matches=[reg matchesInString:e options:0 range:NSMakeRange(0,e.length)];
    NSInteger offset=0;
    for(NSTextCheckingResult *m in matches) {
        NSRange r=NSMakeRange(m.range.location+offset, m.range.length);
        NSString *ref=[e substringWithRange:r];
        NSInteger row,col;
        NSString *replacement=@"0";
        if([self parseRef:ref row:&row col:&col]) {
            SpreadCell *cell=[sheet cellAtRow:row col:col];
            if(cell&&cell.display.length) replacement=cell.display;
        }
        [e replaceCharactersInRange:r withString:replacement];
        offset+=(NSInteger)replacement.length-(NSInteger)m.range.length;
    }
    // Evaluate simple expression using NSExpression
    @try {
        NSExpression *exp=[NSExpression expressionWithFormat:e];
        NSNumber *result=[exp expressionValueWithObject:nil context:nil];
        if(result) return [self formatNum:result.doubleValue];
    } @catch(...) {}
    return @"#ERR";
}

+ (double)numberValue:(NSString *)s {
    return [s doubleValue];
}

+ (NSString *)formatNum:(double)n {
    if(n==(long long)n) return [NSString stringWithFormat:@"%lld",(long long)n];
    return [NSString stringWithFormat:@"%.4g",n];
}

+ (NSArray *)rangeForSpec:(NSString *)spec sheet:(SpreadSheet *)sheet {
    return @[];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Grid Cell View

@interface GridCellView : UIView
@property (nonatomic, strong) UILabel     *label;
@property (nonatomic, assign) NSInteger    row, col;
@property (nonatomic, assign) BOOL         isHeader;
@property (nonatomic, assign) BOOL         isSelected;
@property (nonatomic, strong) SpreadCell  *cellData;
- (void)applyCell:(SpreadCell *)cell isHeader:(BOOL)header;
@end

@implementation GridCellView
- (instancetype)initWithFrame:(CGRect)f {
    self=[super initWithFrame:f]; if(!self) return nil;
    self.backgroundColor=[UIColor clearColor];
    self.clipsToBounds=YES;
    _label=[[UILabel alloc] initWithFrame:CGRectInset(f,3,2)];
    _label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _label.font=[UIFont systemFontOfSize:12];
    _label.textColor=[UIColor whiteColor];
    _label.numberOfLines=1;
    [self addSubview:_label];
    return self;
}
- (void)applyCell:(SpreadCell *)cell isHeader:(BOOL)header {
    _cellData=cell; _isHeader=header;
    if(header) {
        self.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.1];
        _label.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.7];
        _label.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        _label.textAlignment=NSTextAlignmentCenter;
    } else if(cell) {
        self.backgroundColor=_isSelected
            ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.35]
            : (cell.bgColor ?: [UIColor clearColor]);
        _label.text=cell.display;
        _label.textColor=_isSelected ? [UIColor whiteColor] : (cell.textColor ?: [UIColor whiteColor]);
        UIFontDescriptor *desc=[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody];
        UIFontDescriptorSymbolicTraits traits=0;
        if(cell.bold) traits|=UIFontDescriptorTraitBold;
        if(cell.italic) traits|=UIFontDescriptorTraitItalic;
        desc=[desc fontDescriptorWithSymbolicTraits:traits];
        _label.font=[UIFont fontWithDescriptor:desc size:cell.fontSize?:12];
        switch(cell.alignment) {
            case CellAlignCenter: _label.textAlignment=NSTextAlignmentCenter; break;
            case CellAlignRight:  _label.textAlignment=NSTextAlignmentRight; break;
            default:              _label.textAlignment=NSTextAlignmentLeft; break;
        }
    } else {
        self.backgroundColor=[UIColor clearColor];
        _label.text=@"";
    }
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    UIColor *border=[[UIColor whiteColor] colorWithAlphaComponent:_isHeader?0.2:0.1];
    CGContextSetStrokeColorWithColor(ctx,border.CGColor);
    CGContextSetLineWidth(ctx,0.5);
    CGContextMoveToPoint(ctx,CGRectGetMaxX(rect),0);
    CGContextAddLineToPoint(ctx,CGRectGetMaxX(rect),CGRectGetMaxY(rect));
    CGContextMoveToPoint(ctx,0,CGRectGetMaxY(rect));
    CGContextAddLineToPoint(ctx,CGRectGetMaxX(rect),CGRectGetMaxY(rect));
    CGContextStrokePath(ctx);
    if(_isSelected) {
        CGContextSetStrokeColorWithColor(ctx,[UIColor systemBlueColor].CGColor);
        CGContextSetLineWidth(ctx,2);
        CGContextStrokeRect(ctx,CGRectInset(rect,1,1));
    }
    if(_cellData) {
        CGContextSetStrokeColorWithColor(ctx,[[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor);
        CGContextSetLineWidth(ctx,1);
        if(_cellData.hasTopBorder){CGContextMoveToPoint(ctx,0,0);CGContextAddLineToPoint(ctx,CGRectGetMaxX(rect),0);}
        if(_cellData.hasBottomBorder){CGContextMoveToPoint(ctx,0,CGRectGetMaxY(rect));CGContextAddLineToPoint(ctx,CGRectGetMaxX(rect),CGRectGetMaxY(rect));}
        if(_cellData.hasLeftBorder){CGContextMoveToPoint(ctx,0,0);CGContextAddLineToPoint(ctx,0,CGRectGetMaxY(rect));}
        if(_cellData.hasRightBorder){CGContextMoveToPoint(ctx,CGRectGetMaxX(rect),0);CGContextAddLineToPoint(ctx,CGRectGetMaxX(rect),CGRectGetMaxY(rect));}
        CGContextStrokePath(ctx);
    }
}
@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Main VC Interface

@interface ExcelViewerViewController ()
    <UIScrollViewDelegate, UITextFieldDelegate, UISearchResultsUpdating>

@property (nonatomic, copy)   NSString               *filePath;
@property (nonatomic, strong) NSMutableArray<SpreadSheet *> *sheets;
@property (nonatomic, assign) NSInteger               currentSheetIndex;

// Selection
@property (nonatomic, assign) NSInteger               selRow, selCol;
@property (nonatomic, assign) NSInteger               selEndRow, selEndCol; // range selection

// Grid UI
@property (nonatomic, strong) UIScrollView            *gridScroll;
@property (nonatomic, strong) UIView                  *gridContent;
@property (nonatomic, strong) UIScrollView            *colHeaderScroll; // top headers
@property (nonatomic, strong) UIView                  *colHeaderContent;
@property (nonatomic, strong) UIScrollView            *rowHeaderScroll; // left headers
@property (nonatomic, strong) UIView                  *rowHeaderContent;
@property (nonatomic, strong) UIView                  *cornerView;      // top-left corner

// Formula bar
@property (nonatomic, strong) UIView                  *formulaBar;
@property (nonatomic, strong) UILabel                 *cellRefLabel;
@property (nonatomic, strong) UITextField             *formulaField;
@property (nonatomic, strong) UIButton                *confirmBtn, *cancelBtn;

// Sheet tabs
@property (nonatomic, strong) UIScrollView            *tabScroll;
@property (nonatomic, strong) UIView                  *tabContainer;

// Toolbar
@property (nonatomic, strong) UIScrollView            *toolbarScroll;

// Format state for next input
@property (nonatomic, assign) BOOL  fmtBold, fmtItalic;
@property (nonatomic, assign) NSInteger fmtSize;
@property (nonatomic, strong) UIColor *fmtTextColor, *fmtBgColor;
@property (nonatomic, assign) CellAlignment fmtAlign;

// Undo stack
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *undoStack;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *redoStack;

// Column widths cache
@property (nonatomic, assign) CGFloat rowHeaderWidth;
@property (nonatomic, assign) CGFloat colHeaderHeight;

// Filter & search
@property (nonatomic, strong) NSMutableSet<NSNumber *> *hiddenRows;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *filters;

// Edit state
@property (nonatomic, assign) BOOL isDirty;

@end

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Implementation

@implementation ExcelViewerViewController

static const CGFloat kColHeaderH = 24;
static const CGFloat kRowHeaderW = 40;

- (instancetype)initWithPath:(NSString *)path {
    self=[super init]; if(!self) return nil;
    _filePath=path; _sheets=[NSMutableArray array];
    _selRow=0; _selCol=0; _selEndRow=0; _selEndCol=0;
    _fmtSize=13; _fmtTextColor=[UIColor whiteColor]; _fmtBgColor=[UIColor clearColor];
    _fmtAlign=CellAlignLeft;
    _undoStack=[NSMutableArray array]; _redoStack=[NSMutableArray array];
    _hiddenRows=[NSMutableSet set]; _filters=[NSMutableDictionary dictionary];
    _rowHeaderWidth=kRowHeaderW; _colHeaderHeight=kColHeaderH;
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=self.filePath.lastPathComponent;
    self.view.backgroundColor=[ThemeEngine bg];
    [self setupNavigationBar];
    [self loadData];
    [self setupFormulaBar];
    [self setupToolbar];
    [self setupGrid];
    [self setupSheetTabs];
    [self reloadGrid];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
        name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
        name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if(self.isDirty) [self saveData];
}

#pragma mark - Navigation Bar

- (void)setupNavigationBar {
    UIBarButtonItem *save  = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(saveData)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"] style:UIBarButtonItemStylePlain target:self action:@selector(shareFile)];
    UIBarButtonItem *more  = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMoreMenu)];
    self.navigationItem.rightBarButtonItems=@[save, share, more];
}

#pragma mark - Formula Bar

- (void)setupFormulaBar {
    self.formulaBar=[[UIView alloc] init];
    self.formulaBar.translatesAutoresizingMaskIntoConstraints=NO;
    self.formulaBar.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.07];
    [self.view addSubview:self.formulaBar];

    self.cellRefLabel=[[UILabel alloc] init];
    self.cellRefLabel.translatesAutoresizingMaskIntoConstraints=NO;
    self.cellRefLabel.text=@"A1";
    self.cellRefLabel.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.cellRefLabel.font=[UIFont fontWithName:@"Menlo" size:11]?:[UIFont systemFontOfSize:11];
    self.cellRefLabel.textAlignment=NSTextAlignmentCenter;
    [self.formulaBar addSubview:self.cellRefLabel];

    UIView *sep=[[UIView alloc] init];
    sep.translatesAutoresizingMaskIntoConstraints=NO;
    sep.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.2];
    [self.formulaBar addSubview:sep];

    self.formulaField=[[UITextField alloc] init];
    self.formulaField.translatesAutoresizingMaskIntoConstraints=NO;
    self.formulaField.textColor=[UIColor whiteColor];
    self.formulaField.font=[UIFont systemFontOfSize:13];
    self.formulaField.backgroundColor=[UIColor clearColor];
    self.formulaField.placeholder=@"Value or formula (=SUM, =IF, ...)";
    self.formulaField.attributedPlaceholder=[[NSAttributedString alloc] initWithString:@"Value or formula"
        attributes:@{NSForegroundColorAttributeName:[[UIColor whiteColor] colorWithAlphaComponent:0.3]}];
    self.formulaField.returnKeyType=UIReturnKeyDone;
    self.formulaField.delegate=self;
    [self.formulaBar addSubview:self.formulaField];

    self.confirmBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    self.confirmBtn.translatesAutoresizingMaskIntoConstraints=NO;
    [self.confirmBtn setImage:[UIImage systemImageNamed:@"checkmark"] forState:UIControlStateNormal];
    self.confirmBtn.tintColor=[UIColor systemGreenColor];
    [self.confirmBtn addTarget:self action:@selector(commitFormula) forControlEvents:UIControlEventTouchUpInside];
    [self.formulaBar addSubview:self.confirmBtn];

    self.cancelBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    self.cancelBtn.translatesAutoresizingMaskIntoConstraints=NO;
    [self.cancelBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    self.cancelBtn.tintColor=[UIColor systemRedColor];
    [self.cancelBtn addTarget:self action:@selector(cancelFormula) forControlEvents:UIControlEventTouchUpInside];
    [self.formulaBar addSubview:self.cancelBtn];

    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.formulaBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.formulaBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.formulaBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.formulaBar.heightAnchor constraintEqualToConstant:44],
        [self.cellRefLabel.leadingAnchor constraintEqualToAnchor:self.formulaBar.leadingAnchor constant:8],
        [self.cellRefLabel.centerYAnchor constraintEqualToAnchor:self.formulaBar.centerYAnchor],
        [self.cellRefLabel.widthAnchor constraintEqualToConstant:48],
        [sep.leadingAnchor constraintEqualToAnchor:self.cellRefLabel.trailingAnchor constant:4],
        [sep.centerYAnchor constraintEqualToAnchor:self.formulaBar.centerYAnchor],
        [sep.widthAnchor constraintEqualToConstant:1],
        [sep.heightAnchor constraintEqualToConstant:24],
        [self.formulaField.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:8],
        [self.formulaField.trailingAnchor constraintEqualToAnchor:self.cancelBtn.leadingAnchor constant:-4],
        [self.formulaField.centerYAnchor constraintEqualToAnchor:self.formulaBar.centerYAnchor],
        [self.cancelBtn.trailingAnchor constraintEqualToAnchor:self.confirmBtn.leadingAnchor constant:-4],
        [self.cancelBtn.centerYAnchor constraintEqualToAnchor:self.formulaBar.centerYAnchor],
        [self.cancelBtn.widthAnchor constraintEqualToConstant:32],
        [self.confirmBtn.trailingAnchor constraintEqualToAnchor:self.formulaBar.trailingAnchor constant:-8],
        [self.confirmBtn.centerYAnchor constraintEqualToAnchor:self.formulaBar.centerYAnchor],
        [self.confirmBtn.widthAnchor constraintEqualToConstant:32],
    ]];
}

#pragma mark - Toolbar

- (void)setupToolbar {
    self.toolbarScroll=[[UIScrollView alloc] init];
    self.toolbarScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.toolbarScroll.showsHorizontalScrollIndicator=NO;
    self.toolbarScroll.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.04];
    [self.view addSubview:self.toolbarScroll];

    NSArray *toolDefs = @[
        @[@"B",@"bold"],@[@"I",@"italic"],@[@"≡",@"alignLeft"],
        @[@"≡",@"alignCenter"],@[@"≡",@"alignRight"],
        @[@"🎨",@"textColor"],@[@"🖌",@"bgColor"],@[@"↑",@"fontSize+"],@[@"↓",@"fontSize-"],
        @[@"🔢",@"numFormat"],@[@"💰",@"currency"],@[@"%",@"percent"],
        @[@"➕",@"addRow"],@[@"➖",@"delRow"],@[@"⊕",@"addCol"],@[@"⊖",@"delCol"],
        @[@"▲",@"sortAsc"],@[@"▼",@"sortDesc"],@[@"🔍",@"filter"],
        @[@"🔲",@"border"],@[@"⛓",@"merge"],@[@"❄️",@"freeze"],
        @[@"↩",@"undo"],@[@"↪",@"redo"],@[@"📊",@"chart"],
        @[@"📋",@"copy"],@[@"📌",@"paste"],@[@"🗑",@"clear"],
        @[@"📈",@"autofit"],@[@"+⬜",@"addSheet"],
    ];

    UIStackView *stack=[[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    stack.axis=UILayoutConstraintAxisHorizontal;
    stack.spacing=2;
    [self.toolbarScroll addSubview:stack];

    for(NSArray *def in toolDefs) {
        UIButton *btn=[UIButton buttonWithType:UIButtonTypeSystem];
        btn.translatesAutoresizingMaskIntoConstraints=NO;
        [btn setTitle:def[0] forState:UIControlStateNormal];
        btn.titleLabel.font=[UIFont systemFontOfSize:13];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.08];
        btn.layer.cornerRadius=6;
        [btn.widthAnchor constraintEqualToConstant:36].active=YES;
        [btn.heightAnchor constraintEqualToConstant:30].active=YES;
        [btn setAccessibilityIdentifier:def[1]];
        [btn addTarget:self action:@selector(toolbarAction:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.toolbarScroll.topAnchor constraintEqualToAnchor:self.formulaBar.bottomAnchor],
        [self.toolbarScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.toolbarScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.toolbarScroll.heightAnchor constraintEqualToConstant:38],
        [stack.topAnchor constraintEqualToAnchor:self.toolbarScroll.topAnchor constant:4],
        [stack.leadingAnchor constraintEqualToAnchor:self.toolbarScroll.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:self.toolbarScroll.trailingAnchor constant:-8],
        [stack.bottomAnchor constraintEqualToAnchor:self.toolbarScroll.bottomAnchor constant:-4],
    ]];
}

- (void)toolbarAction:(UIButton *)btn {
    NSString *action=btn.accessibilityIdentifier;
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    SpreadCell *cell=[sheet cellAtRow:self.selRow col:self.selCol];
    if(!cell){cell=[SpreadCell new];[sheet setCell:cell row:self.selRow col:self.selCol];}

    if([action isEqualToString:@"bold"]){
        [self saveUndo];
        cell.bold=!cell.bold; self.fmtBold=cell.bold;
    } else if([action isEqualToString:@"italic"]){
        [self saveUndo];
        cell.italic=!cell.italic; self.fmtItalic=cell.italic;
    } else if([action isEqualToString:@"alignLeft"]){
        [self saveUndo]; cell.alignment=CellAlignLeft; self.fmtAlign=CellAlignLeft;
    } else if([action isEqualToString:@"alignCenter"]){
        [self saveUndo]; cell.alignment=CellAlignCenter; self.fmtAlign=CellAlignCenter;
    } else if([action isEqualToString:@"alignRight"]){
        [self saveUndo]; cell.alignment=CellAlignRight; self.fmtAlign=CellAlignRight;
    } else if([action isEqualToString:@"fontSize+"]){
        [self saveUndo]; cell.fontSize=MAX(8,(cell.fontSize?:12)+2); self.fmtSize=cell.fontSize;
    } else if([action isEqualToString:@"fontSize-"]){
        [self saveUndo]; cell.fontSize=MAX(8,(cell.fontSize?:12)-2); self.fmtSize=cell.fontSize;
    } else if([action isEqualToString:@"textColor"]){
        [self pickColor:YES];
    } else if([action isEqualToString:@"bgColor"]){
        [self pickColor:NO];
    } else if([action isEqualToString:@"numFormat"]){
        [self applyNumFormat:cell];
    } else if([action isEqualToString:@"currency"]){
        [self saveUndo];
        if(cell.display.length) cell.display=[NSString stringWithFormat:@"¥%.2f",[cell.display doubleValue]];
    } else if([action isEqualToString:@"percent"]){
        [self saveUndo];
        if(cell.display.length) cell.display=[NSString stringWithFormat:@"%.1f%%",[cell.display doubleValue]*100];
    } else if([action isEqualToString:@"addRow"]){
        [self saveUndo]; [self insertRowAt:self.selRow+1];
    } else if([action isEqualToString:@"delRow"]){
        [self saveUndo]; [self deleteRowAt:self.selRow];
    } else if([action isEqualToString:@"addCol"]){
        [self saveUndo]; [self insertColAt:self.selCol+1];
    } else if([action isEqualToString:@"delCol"]){
        [self saveUndo]; [self deleteColAt:self.selCol];
    } else if([action isEqualToString:@"sortAsc"]){
        [self saveUndo]; [self sortByCol:self.selCol ascending:YES];
    } else if([action isEqualToString:@"sortDesc"]){
        [self saveUndo]; [self sortByCol:self.selCol ascending:NO];
    } else if([action isEqualToString:@"filter"]){
        [self showFilterPrompt];
    } else if([action isEqualToString:@"border"]){
        [self applyBorderToSelection];
    } else if([action isEqualToString:@"freeze"]){
        sheet.frozenRows=self.selRow; sheet.frozenCols=self.selCol;
    } else if([action isEqualToString:@"undo"]){
        [self performUndo];
    } else if([action isEqualToString:@"redo"]){
        [self performRedo];
    } else if([action isEqualToString:@"chart"]){
        [self showChartOptions];
    } else if([action isEqualToString:@"copy"]){
        [self copyCells];
    } else if([action isEqualToString:@"paste"]){
        [self pasteCells];
    } else if([action isEqualToString:@"clear"]){
        [self saveUndo]; [self clearSelection];
    } else if([action isEqualToString:@"autofit"]){
        [self autoFitColWidth:self.selCol];
    } else if([action isEqualToString:@"addSheet"]){
        [self addNewSheet];
    } else if([action isEqualToString:@"merge"]){
        [self mergeCells];
    }
    [self reloadGrid];
    self.isDirty=YES;
}

#pragma mark - Grid Setup

- (void)setupGrid {
    // Corner view
    self.cornerView=[[UIView alloc] init];
    self.cornerView.translatesAutoresizingMaskIntoConstraints=NO;
    self.cornerView.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.08];
    [self.view addSubview:self.cornerView];

    // Column header scroll (synced horizontally with grid)
    self.colHeaderScroll=[[UIScrollView alloc] init];
    self.colHeaderScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.colHeaderScroll.showsHorizontalScrollIndicator=NO;
    self.colHeaderScroll.showsVerticalScrollIndicator=NO;
    self.colHeaderScroll.bounces=NO;
    self.colHeaderScroll.delegate=self;
    [self.view addSubview:self.colHeaderScroll];

    self.colHeaderContent=[[UIView alloc] init];
    [self.colHeaderScroll addSubview:self.colHeaderContent];

    // Row header scroll (synced vertically with grid)
    self.rowHeaderScroll=[[UIScrollView alloc] init];
    self.rowHeaderScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.rowHeaderScroll.showsHorizontalScrollIndicator=NO;
    self.rowHeaderScroll.showsVerticalScrollIndicator=NO;
    self.rowHeaderScroll.bounces=NO;
    self.rowHeaderScroll.delegate=self;
    [self.view addSubview:self.rowHeaderScroll];

    self.rowHeaderContent=[[UIView alloc] init];
    [self.rowHeaderScroll addSubview:self.rowHeaderContent];

    // Main grid scroll
    self.gridScroll=[[UIScrollView alloc] init];
    self.gridScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.gridScroll.showsHorizontalScrollIndicator=YES;
    self.gridScroll.showsVerticalScrollIndicator=YES;
    self.gridScroll.bounces=NO;
    self.gridScroll.delegate=self;
    [self.view addSubview:self.gridScroll];

    self.gridContent=[[UIView alloc] init];
    [self.gridScroll addSubview:self.gridContent];

    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    CGFloat headerTop=self.formulaBar.frame.size.height+38+0;

    [NSLayoutConstraint activateConstraints:@[
        // Corner
        [self.cornerView.topAnchor constraintEqualToAnchor:self.toolbarScroll.bottomAnchor],
        [self.cornerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.cornerView.widthAnchor constraintEqualToConstant:self.rowHeaderWidth],
        [self.cornerView.heightAnchor constraintEqualToConstant:self.colHeaderHeight],
        // Col headers
        [self.colHeaderScroll.topAnchor constraintEqualToAnchor:self.toolbarScroll.bottomAnchor],
        [self.colHeaderScroll.leadingAnchor constraintEqualToAnchor:self.cornerView.trailingAnchor],
        [self.colHeaderScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.colHeaderScroll.heightAnchor constraintEqualToConstant:self.colHeaderHeight],
        // Row headers
        [self.rowHeaderScroll.topAnchor constraintEqualToAnchor:self.colHeaderScroll.bottomAnchor],
        [self.rowHeaderScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.rowHeaderScroll.widthAnchor constraintEqualToConstant:self.rowHeaderWidth],
        [self.rowHeaderScroll.bottomAnchor constraintEqualToAnchor:self.tabScroll ? self.tabScroll.topAnchor : safe.bottomAnchor],
        // Grid
        [self.gridScroll.topAnchor constraintEqualToAnchor:self.colHeaderScroll.bottomAnchor],
        [self.gridScroll.leadingAnchor constraintEqualToAnchor:self.rowHeaderScroll.trailingAnchor],
        [self.gridScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.gridScroll.bottomAnchor constraintEqualToAnchor:self.rowHeaderScroll.bottomAnchor],
    ]];

    // Tap gesture on grid
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gridTapped:)];
    [self.gridScroll addGestureRecognizer:tap];
    UILongPressGestureRecognizer *lp=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(gridLongPressed:)];
    lp.minimumPressDuration=0.5;
    [self.gridScroll addGestureRecognizer:lp];
}

- (void)setupSheetTabs {
    self.tabScroll=[[UIScrollView alloc] init];
    self.tabScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.tabScroll.showsHorizontalScrollIndicator=NO;
    self.tabScroll.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.4];
    [self.view addSubview:self.tabScroll];

    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tabScroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.tabScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tabScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tabScroll.heightAnchor constraintEqualToConstant:36],
    ]];
    [self reloadSheetTabs];
}

- (void)reloadSheetTabs {
    for(UIView *v in self.tabScroll.subviews) [v removeFromSuperview];
    CGFloat x=8;
    for(NSInteger i=0;i<(NSInteger)self.sheets.count;i++) {
        SpreadSheet *s=self.sheets[i];
        UIButton *tab=[UIButton buttonWithType:UIButtonTypeSystem];
        BOOL active=(i==self.currentSheetIndex);
        [tab setTitle:s.name forState:UIControlStateNormal];
        [tab setTitleColor:active?[UIColor whiteColor]:[[UIColor whiteColor] colorWithAlphaComponent:0.5] forState:UIControlStateNormal];
        tab.backgroundColor=active?[[UIColor systemBlueColor] colorWithAlphaComponent:0.4]:[[UIColor whiteColor] colorWithAlphaComponent:0.06];
        tab.layer.cornerRadius=6;
        tab.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        CGSize sz=[tab.titleLabel systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        tab.frame=CGRectMake(x,4,MAX(60,sz.width+20),28);
        tab.tag=i;
        [tab addTarget:self action:@selector(sheetTabTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *lp=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(sheetTabLongPressed:)];
        lp.minimumPressDuration=0.5; [tab addGestureRecognizer:lp];
        [self.tabScroll addSubview:tab];
        x+=tab.frame.size.width+6;
    }
    self.tabScroll.contentSize=CGSizeMake(x+8,36);
}

- (void)sheetTabTapped:(UIButton *)btn {
    if(self.isDirty) [self saveData];
    self.currentSheetIndex=btn.tag;
    self.selRow=0; self.selCol=0;
    [self reloadGrid];
    [self reloadSheetTabs];
    [self updateFormulaBar];
}

- (void)sheetTabLongPressed:(UILongPressGestureRecognizer *)lp {
    if(lp.state!=UIGestureRecognizerStateBegan) return;
    UIButton *btn=(UIButton *)lp.view;
    NSInteger idx=btn.tag;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Sheet"
        message:self.sheets[idx].name preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        [self promptRenameSheet:idx];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Duplicate" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        [self duplicateSheet:idx];
    }]];
    if(self.sheets.count>1) {
        [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){
            [self.sheets removeObjectAtIndex:idx];
            if(self.currentSheetIndex>=self.sheets.count) self.currentSheetIndex=(NSInteger)self.sheets.count-1;
            [self reloadGrid]; [self reloadSheetTabs];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=btn;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptRenameSheet:(NSInteger)idx {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Rename Sheet"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){tf.text=self.sheets[idx].name;}];
    [a addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        NSString *n=a.textFields.firstObject.text;
        if(n.length) self.sheets[idx].name=n;
        [self reloadSheetTabs];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)duplicateSheet:(NSInteger)idx {
    SpreadSheet *src=self.sheets[idx];
    SpreadSheet *dup=[[SpreadSheet alloc] initWithName:[NSString stringWithFormat:@"%@ Copy",src.name]
        rows:src.rowCount cols:src.colCount];
    for(NSString *key in src.cells) dup.cells[key]=[src.cells[key] copy];
    dup.colWidths=[src.colWidths mutableCopy];
    dup.rowHeights=[src.rowHeights mutableCopy];
    [self.sheets insertObject:dup atIndex:idx+1];
    [self reloadSheetTabs];
}

#pragma mark - Grid Rendering

- (void)reloadGrid {
    for(UIView *v in self.gridContent.subviews) [v removeFromSuperview];
    for(UIView *v in self.colHeaderContent.subviews) [v removeFromSuperview];
    for(UIView *v in self.rowHeaderContent.subviews) [v removeFromSuperview];

    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSInteger rows=sheet.rowCount, cols=sheet.colCount;

    // Compute total size
    CGFloat totalW=0, totalH=0;
    CGFloat colHeaderTotalW=0;
    NSMutableArray<NSNumber *> *xOffsets=[NSMutableArray array];
    NSMutableArray<NSNumber *> *yOffsets=[NSMutableArray array];

    for(NSInteger c=0;c<cols;c++) {
        [xOffsets addObject:@(totalW)];
        CGFloat w=c<(NSInteger)sheet.colWidths.count?[sheet.colWidths[c] floatValue]:90;
        totalW+=w;
    }
    for(NSInteger r=0;r<rows;r++) {
        [yOffsets addObject:@(totalH)];
        CGFloat h=r<(NSInteger)sheet.rowHeights.count?[sheet.rowHeights[r] floatValue]:28;
        if([self.hiddenRows containsObject:@(r)]) continue;
        totalH+=h;
    }

    // Render column headers
    for(NSInteger c=0;c<cols;c++) {
        CGFloat x=[xOffsets[c] floatValue];
        CGFloat w=c<(NSInteger)sheet.colWidths.count?[sheet.colWidths[c] floatValue]:90;
        GridCellView *hv=[[GridCellView alloc] initWithFrame:CGRectMake(x,0,w,self.colHeaderHeight)];
        hv.label.text=[self colName:c];
        [hv applyCell:nil isHeader:YES];
        [self.colHeaderContent addSubview:hv];
    }
    self.colHeaderContent.frame=CGRectMake(0,0,totalW,self.colHeaderHeight);
    self.colHeaderScroll.contentSize=CGSizeMake(totalW,self.colHeaderHeight);

    // Render row headers
    CGFloat yOff=0;
    for(NSInteger r=0;r<rows;r++) {
        if([self.hiddenRows containsObject:@(r)]) continue;
        CGFloat h=r<(NSInteger)sheet.rowHeights.count?[sheet.rowHeights[r] floatValue]:28;
        GridCellView *rv=[[GridCellView alloc] initWithFrame:CGRectMake(0,yOff,self.rowHeaderWidth,h)];
        rv.label.text=[NSString stringWithFormat:@"%ld",(long)(r+1)];
        [rv applyCell:nil isHeader:YES];
        [self.rowHeaderContent addSubview:rv];
        yOff+=h;
    }
    self.rowHeaderContent.frame=CGRectMake(0,0,self.rowHeaderWidth,yOff);
    self.rowHeaderScroll.contentSize=CGSizeMake(self.rowHeaderWidth,yOff);

    // Render cells
    yOff=0;
    for(NSInteger r=0;r<rows;r++) {
        if([self.hiddenRows containsObject:@(r)]) continue;
        CGFloat h=r<(NSInteger)sheet.rowHeights.count?[sheet.rowHeights[r] floatValue]:28;
        for(NSInteger c=0;c<cols;c++) {
            CGFloat x=[xOffsets[c] floatValue];
            CGFloat w=c<(NSInteger)sheet.colWidths.count?[sheet.colWidths[c] floatValue]:90;
            GridCellView *cv=[[GridCellView alloc] initWithFrame:CGRectMake(x,yOff,w,h)];
            cv.row=r; cv.col=c;
            SpreadCell *cell=[sheet cellAtRow:r col:c];
            BOOL sel=(r>=MIN(self.selRow,self.selEndRow)&&r<=MAX(self.selRow,self.selEndRow)&&
                      c>=MIN(self.selCol,self.selEndCol)&&c<=MAX(self.selCol,self.selEndCol));
            cv.isSelected=sel;
            [cv applyCell:cell isHeader:NO];
            [self.gridContent addSubview:cv];
        }
        yOff+=h;
    }
    self.gridContent.frame=CGRectMake(0,0,totalW,yOff);
    self.gridScroll.contentSize=CGSizeMake(totalW,yOff);
    [self updateFormulaBar];
}

- (NSString *)colName:(NSInteger)c {
    NSMutableString *name=[NSMutableString string];
    c++;
    while(c>0) {
        [name insertString:[NSString stringWithFormat:@"%c",(char)('A'+(c-1)%26)] atIndex:0];
        c=(c-1)/26;
    }
    return name;
}

#pragma mark - Grid Touch

- (void)gridTapped:(UITapGestureRecognizer *)tap {
    CGPoint pt=[tap locationInView:self.gridContent];
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSInteger r=[self rowForY:pt.y sheet:sheet];
    NSInteger c=[self colForX:pt.x sheet:sheet];
    if(r<0||c<0) return;

    if(tap.numberOfTapsRequired==2 || self.selRow==r&&self.selCol==c) {
        [self.formulaField becomeFirstResponder];
    } else {
        [self.view endEditing:YES];
    }
    self.selRow=r; self.selCol=c;
    self.selEndRow=r; self.selEndCol=c;
    [self reloadGrid];
    [self scrollToSelection];
}

- (void)gridLongPressed:(UILongPressGestureRecognizer *)lp {
    if(lp.state!=UIGestureRecognizerStateBegan) return;
    [self showCellContextMenu];
}

- (NSInteger)rowForY:(CGFloat)y sheet:(SpreadSheet *)sheet {
    CGFloat acc=0;
    for(NSInteger r=0;r<sheet.rowCount;r++) {
        if([self.hiddenRows containsObject:@(r)]) continue;
        CGFloat h=r<(NSInteger)sheet.rowHeights.count?[sheet.rowHeights[r] floatValue]:28;
        if(y<acc+h) return r;
        acc+=h;
    }
    return sheet.rowCount-1;
}

- (NSInteger)colForX:(CGFloat)x sheet:(SpreadSheet *)sheet {
    CGFloat acc=0;
    for(NSInteger c=0;c<sheet.colCount;c++) {
        CGFloat w=c<(NSInteger)sheet.colWidths.count?[sheet.colWidths[c] floatValue]:90;
        if(x<acc+w) return c;
        acc+=w;
    }
    return sheet.colCount-1;
}

- (void)scrollToSelection {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    CGFloat x=0,y=0,w=90,h=28;
    for(NSInteger c=0;c<self.selCol;c++) x+=c<(NSInteger)sheet.colWidths.count?[sheet.colWidths[c] floatValue]:90;
    for(NSInteger r=0;r<self.selRow;r++) {
        if(![self.hiddenRows containsObject:@(r)])
            y+=r<(NSInteger)sheet.rowHeights.count?[sheet.rowHeights[r] floatValue]:28;
    }
    if(self.selCol<(NSInteger)sheet.colWidths.count) w=[sheet.colWidths[self.selCol] floatValue];
    if(self.selRow<(NSInteger)sheet.rowHeights.count) h=[sheet.rowHeights[self.selRow] floatValue];
    [self.gridScroll scrollRectToVisible:CGRectMake(x,y,w,h) animated:YES];
}

#pragma mark - ScrollView Sync

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if(sv==self.gridScroll) {
        self.colHeaderScroll.contentOffset=CGPointMake(sv.contentOffset.x,0);
        self.rowHeaderScroll.contentOffset=CGPointMake(0,sv.contentOffset.y);
    } else if(sv==self.colHeaderScroll) {
        self.gridScroll.contentOffset=CGPointMake(sv.contentOffset.x,self.gridScroll.contentOffset.y);
    } else if(sv==self.rowHeaderScroll) {
        self.gridScroll.contentOffset=CGPointMake(self.gridScroll.contentOffset.x,sv.contentOffset.y);
    }
}

#pragma mark - Formula Bar

- (void)updateFormulaBar {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    self.cellRefLabel.text=[NSString stringWithFormat:@"%@%ld",[self colName:self.selCol],(long)(self.selRow+1)];
    SpreadCell *cell=[sheet cellAtRow:self.selRow col:self.selCol];
    self.formulaField.text=cell?cell.raw:@"";
}

- (void)commitFormula {
    [self saveUndo];
    NSString *val=self.formulaField.text ?: @"";
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    SpreadCell *cell=[sheet cellAtRow:self.selRow col:self.selCol];
    if(!cell){cell=[SpreadCell new];[sheet setCell:cell row:self.selRow col:self.selCol];}
    cell.raw=val;
    if([val hasPrefix:@"="]) {
        cell.type=CellTypeFormula;
        cell.display=[FormulaEngine evaluate:val sheet:sheet];
    } else if([self isNumeric:val]) {
        cell.type=CellTypeNumber;
        cell.display=val;
    } else {
        cell.type=CellTypeText;
        cell.display=val;
    }
    cell.bold=self.fmtBold; cell.italic=self.fmtItalic;
    cell.fontSize=self.fmtSize; cell.alignment=self.fmtAlign;
    if(self.fmtTextColor) cell.textColor=self.fmtTextColor;
    if(self.fmtBgColor)   cell.bgColor=self.fmtBgColor;
    [self.formulaField resignFirstResponder];
    self.isDirty=YES;
    // Advance selection
    self.selRow=MIN(self.selRow+1,(NSInteger)sheet.rowCount-1);
    self.selEndRow=self.selRow; self.selEndCol=self.selCol;
    [self reloadGrid];
}

- (void)cancelFormula {
    [self.formulaField resignFirstResponder];
    [self updateFormulaBar];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self commitFormula]; return YES; }

- (BOOL)isNumeric:(NSString *)s {
    NSScanner *sc=[NSScanner scannerWithString:s];
    double v; return [sc scanDouble:&v]&&sc.isAtEnd;
}

#pragma mark - Cell Operations

- (void)clearSelection {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    for(NSInteger r=MIN(self.selRow,self.selEndRow);r<=MAX(self.selRow,self.selEndRow);r++)
    for(NSInteger c=MIN(self.selCol,self.selEndCol);c<=MAX(self.selCol,self.selEndCol);c++) {
        SpreadCell *cell=[sheet cellAtRow:r col:c];
        if(cell){cell.raw=@"";cell.display=@"";}
    }
}

- (void)copyCells {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    SpreadCell *cell=[sheet cellAtRow:self.selRow col:self.selCol];
    [[UIPasteboard generalPasteboard] setString:cell?cell.display:@""];
}

- (void)pasteCells {
    NSString *text=[[UIPasteboard generalPasteboard] string];
    if(!text.length) return;
    [self saveUndo];
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    // Parse multi-line TSV
    NSArray *rows=[text componentsSeparatedByString:@"\n"];
    for(NSInteger ri=0;ri<(NSInteger)rows.count;ri++) {
        NSArray *cols=[rows[ri] componentsSeparatedByString:@"\t"];
        for(NSInteger ci=0;ci<(NSInteger)cols.count;ci++) {
            NSInteger targetR=self.selRow+ri, targetC=self.selCol+ci;
            if(targetR>=sheet.rowCount||targetC>=sheet.colCount) continue;
            SpreadCell *cell=[sheet cellAtRow:targetR col:targetC]?:[SpreadCell new];
            cell.raw=cols[ci]; cell.display=cols[ci];
            [sheet setCell:cell row:targetR col:targetC];
        }
    }
    [self reloadGrid];
    self.isDirty=YES;
}

- (void)mergeCells {
    [self saveUndo];
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSInteger r1=MIN(self.selRow,self.selEndRow), r2=MAX(self.selRow,self.selEndRow);
    NSInteger c1=MIN(self.selCol,self.selEndCol), c2=MAX(self.selCol,self.selEndCol);
    SpreadCell *master=[sheet cellAtRow:r1 col:c1]?:[SpreadCell new];
    [sheet setCell:master row:r1 col:c1];
    // Collect display width
    CGFloat mergedW=0;
    for(NSInteger c=c1;c<=c2;c++) {
        mergedW+=[sheet.colWidths[MIN(c,(NSInteger)sheet.colWidths.count-1)] floatValue];
        if(c!=c1){SpreadCell *e=[SpreadCell new];e.raw=@"";e.display=@"";[sheet setCell:e row:r1 col:c];}
    }
    sheet.colWidths[c1]=@(mergedW);
    [self reloadGrid];
}

#pragma mark - Row/Col Operations

- (void)insertRowAt:(NSInteger)row {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableDictionary *newCells=[NSMutableDictionary dictionary];
    for(NSString *key in sheet.cells) {
        NSInteger r,c;
        sscanf([key UTF8String],"R%ldC%ld",&r,&c);
        if(r>=row) newCells[[NSString stringWithFormat:@"R%ldC%ld",r+1,c]]=sheet.cells[key];
        else newCells[key]=sheet.cells[key];
    }
    sheet.cells=newCells;
    sheet.rowCount++;
    [sheet.rowHeights insertObject:@(28) atIndex:MIN(row,(NSInteger)sheet.rowHeights.count)];
    [self reloadGrid];
}

- (void)deleteRowAt:(NSInteger)row {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableDictionary *newCells=[NSMutableDictionary dictionary];
    for(NSString *key in sheet.cells) {
        NSInteger r,c;
        sscanf([key UTF8String],"R%ldC%ld",&r,&c);
        if(r==row) continue;
        if(r>row) newCells[[NSString stringWithFormat:@"R%ldC%ld",r-1,c]]=sheet.cells[key];
        else newCells[key]=sheet.cells[key];
    }
    sheet.cells=newCells;
    sheet.rowCount=MAX(1,sheet.rowCount-1);
    if(row<(NSInteger)sheet.rowHeights.count) [sheet.rowHeights removeObjectAtIndex:row];
    self.selRow=MIN(self.selRow,sheet.rowCount-1);
    [self reloadGrid];
}

- (void)insertColAt:(NSInteger)col {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableDictionary *newCells=[NSMutableDictionary dictionary];
    for(NSString *key in sheet.cells) {
        NSInteger r,c;
        sscanf([key UTF8String],"R%ldC%ld",&r,&c);
        if(c>=col) newCells[[NSString stringWithFormat:@"R%ldC%ld",r,c+1]]=sheet.cells[key];
        else newCells[key]=sheet.cells[key];
    }
    sheet.cells=newCells;
    sheet.colCount++;
    [sheet.colWidths insertObject:@(90) atIndex:MIN(col,(NSInteger)sheet.colWidths.count)];
    [self reloadGrid];
}

- (void)deleteColAt:(NSInteger)col {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableDictionary *newCells=[NSMutableDictionary dictionary];
    for(NSString *key in sheet.cells) {
        NSInteger r,c;
        sscanf([key UTF8String],"R%ldC%ld",&r,&c);
        if(c==col) continue;
        if(c>col) newCells[[NSString stringWithFormat:@"R%ldC%ld",r,c-1]]=sheet.cells[key];
        else newCells[key]=sheet.cells[key];
    }
    sheet.cells=newCells;
    sheet.colCount=MAX(1,sheet.colCount-1);
    if(col<(NSInteger)sheet.colWidths.count) [sheet.colWidths removeObjectAtIndex:col];
    self.selCol=MIN(self.selCol,sheet.colCount-1);
    [self reloadGrid];
}

- (void)autoFitColWidth:(NSInteger)col {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    CGFloat maxW=60;
    for(NSInteger r=0;r<sheet.rowCount;r++) {
        SpreadCell *cell=[sheet cellAtRow:r col:col];
        if(!cell.display.length) continue;
        CGSize sz=[cell.display sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:cell.fontSize?:12]}];
        maxW=MAX(maxW,sz.width+16);
    }
    if(col<(NSInteger)sheet.colWidths.count) sheet.colWidths[col]=@(maxW);
    [self reloadGrid];
}

#pragma mark - Sort

- (void)sortByCol:(NSInteger)col ascending:(BOOL)asc {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSInteger rows=sheet.rowCount;
    // Extract rows as arrays
    NSMutableArray *rowData=[NSMutableArray array];
    for(NSInteger r=0;r<rows;r++) {
        NSMutableDictionary *row=[NSMutableDictionary dictionary];
        for(NSInteger c=0;c<sheet.colCount;c++) {
            SpreadCell *cell=[sheet cellAtRow:r col:c];
            if(cell) row[@(c)]=cell;
        }
        [rowData addObject:row];
    }
    [rowData sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        SpreadCell *ac=a[@(col)], *bc=b[@(col)];
        NSString *av=ac?ac.display:@"", *bv=bc?bc.display:@"";
        double na=[av doubleValue], nb=[bv doubleValue];
        NSComparisonResult res;
        if(na!=0||[av isEqualToString:@"0"]) res=(na<nb?NSOrderedAscending:na>nb?NSOrderedDescending:NSOrderedSame);
        else res=[av localizedCaseInsensitiveCompare:bv];
        return asc?res:(NSComparisonResult)-res;
    }];
    // Write back
    NSMutableDictionary *newCells=[NSMutableDictionary dictionary];
    for(NSInteger r=0;r<(NSInteger)rowData.count;r++) {
        NSDictionary *row=rowData[r];
        for(NSNumber *cNum in row) {
            newCells[[NSString stringWithFormat:@"R%ldC%ld",(long)r,cNum.longValue]]=row[cNum];
        }
    }
    sheet.cells=newCells;
    [self reloadGrid];
}

#pragma mark - Filter

- (void)showFilterPrompt {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Filter Column"
        message:[NSString stringWithFormat:@"Column %@",[self colName:self.selCol]]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder=@"Filter value (empty to clear)";
        tf.text=self.filters[@(self.selCol)];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        NSString *val=a.textFields.firstObject.text;
        if(val.length) self.filters[@(self.selCol)]=val;
        else [self.filters removeObjectForKey:@(self.selCol)];
        [self applyFilters];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)applyFilters {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    [self.hiddenRows removeAllObjects];
    for(NSInteger r=0;r<sheet.rowCount;r++) {
        for(NSNumber *colNum in self.filters) {
            SpreadCell *cell=[sheet cellAtRow:r col:colNum.integerValue];
            NSString *filter=self.filters[colNum];
            if(!cell||[cell.display rangeOfString:filter options:NSCaseInsensitiveSearch].location==NSNotFound) {
                [self.hiddenRows addObject:@(r)]; break;
            }
        }
    }
    [self reloadGrid];
}

#pragma mark - Border

- (void)applyBorderToSelection {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    [self saveUndo];
    NSInteger r1=MIN(self.selRow,self.selEndRow),r2=MAX(self.selRow,self.selEndRow);
    NSInteger c1=MIN(self.selCol,self.selEndCol),c2=MAX(self.selCol,self.selEndCol);
    for(NSInteger r=r1;r<=r2;r++) for(NSInteger c=c1;c<=c2;c++) {
        SpreadCell *cell=[sheet cellAtRow:r col:c];
        if(!cell){cell=[SpreadCell new];[sheet setCell:cell row:r col:c];}
        cell.hasTopBorder=(r==r1); cell.hasBottomBorder=(r==r2);
        cell.hasLeftBorder=(c==c1); cell.hasRightBorder=(c==c2);
    }
    [self reloadGrid];
}

#pragma mark - Context Menu

- (void)showCellContextMenu {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Cell Options"
        message:[NSString stringWithFormat:@"%@%ld",[self colName:self.selCol],(long)(self.selRow+1)]
        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"📋 Copy Value" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self copyCells];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"📌 Paste" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self pasteCells];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"🗑 Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){[self saveUndo];[self clearSelection];[self reloadGrid];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"📏 Row Height..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self promptRowHeight];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"📐 Col Width..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self promptColWidth];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"↩ Insert Row Above" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self saveUndo];[self insertRowAt:self.selRow];[self reloadGrid];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"↗ Insert Col Left" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self saveUndo];[self insertColAt:self.selCol];[self reloadGrid];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view;
    a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2,1,1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptRowHeight {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Row Height" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.keyboardType=UIKeyboardTypeDecimalPad;
        SpreadSheet *s=self.sheets[self.currentSheetIndex];
        tf.text=[NSString stringWithFormat:@"%.0f",self.selRow<(NSInteger)s.rowHeights.count?[s.rowHeights[self.selRow] floatValue]:28.0];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        CGFloat h=[a.textFields.firstObject.text floatValue];
        if(h<10) h=10;
        SpreadSheet *s=self.sheets[self.currentSheetIndex];
        while((NSInteger)s.rowHeights.count<=self.selRow) [s.rowHeights addObject:@(28)];
        s.rowHeights[self.selRow]=@(h);
        [self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptColWidth {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Column Width" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.keyboardType=UIKeyboardTypeDecimalPad;
        SpreadSheet *s=self.sheets[self.currentSheetIndex];
        tf.text=[NSString stringWithFormat:@"%.0f",self.selCol<(NSInteger)s.colWidths.count?[s.colWidths[self.selCol] floatValue]:90.0];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        CGFloat w=[a.textFields.firstObject.text floatValue];
        if(w<20) w=20;
        SpreadSheet *s=self.sheets[self.currentSheetIndex];
        while((NSInteger)s.colWidths.count<=self.selCol) [s.colWidths addObject:@(90)];
        s.colWidths[self.selCol]=@(w);
        [self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Number Format

- (void)applyNumFormat:(SpreadCell *)cell {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Number Format"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"General" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        double v=[cell.raw doubleValue]; cell.display=[FormulaEngine formatNum:v];[self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"0.00" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        cell.display=[NSString stringWithFormat:@"%.2f",[cell.raw doubleValue]];[self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"#,##0" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        NSNumberFormatter *f=[[NSNumberFormatter alloc] init];
        f.numberStyle=NSNumberFormatterDecimalStyle;
        cell.display=[f stringFromNumber:@([cell.raw doubleValue])]?:cell.raw;[self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"¥#,##0" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        NSNumberFormatter *f=[[NSNumberFormatter alloc] init];
        f.numberStyle=NSNumberFormatterCurrencyStyle; f.currencyCode=@"JPY";
        cell.display=[f stringFromNumber:@([cell.raw doubleValue])]?:cell.raw;[self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"0%" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        cell.display=[NSString stringWithFormat:@"%.0f%%",[cell.raw doubleValue]*100];[self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Date" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        // ISO → formatted date
        NSDateFormatter *f=[[NSDateFormatter alloc] init];
        f.dateStyle=NSDateFormatterMediumStyle; f.timeStyle=NSDateFormatterNoStyle;
        NSDate *d=[[NSDateFormatter new] dateFromString:cell.raw];
        cell.display=d?[f stringFromDate:d]:cell.raw;[self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Color Picker

- (void)pickColor:(BOOL)isText {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:isText?@"Text Color":@"Background Color"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *colors=@{@"White":[UIColor whiteColor],@"Red":[UIColor systemRedColor],
        @"Green":[UIColor systemGreenColor],@"Blue":[UIColor systemBlueColor],
        @"Yellow":[UIColor systemYellowColor],@"Orange":[UIColor systemOrangeColor],
        @"Purple":[UIColor systemPurpleColor],@"Cyan":[UIColor systemCyanColor],
        @"Clear":[UIColor clearColor]};
    for(NSString *name in colors) {
        UIColor *color=colors[name];
        [a addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [self saveUndo];
            SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
            for(NSInteger r=MIN(self.selRow,self.selEndRow);r<=MAX(self.selRow,self.selEndRow);r++)
            for(NSInteger c=MIN(self.selCol,self.selEndCol);c<=MAX(self.selCol,self.selEndCol);c++) {
                SpreadCell *cell=[sheet cellAtRow:r col:c]?:[SpreadCell new];
                if(isText) cell.textColor=color; else cell.bgColor=color;
                [sheet setCell:cell row:r col:c];
            }
            if(isText) self.fmtTextColor=color; else self.fmtBgColor=color;
            [self reloadGrid];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Charts

- (void)showChartOptions {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Insert Chart"
        message:@"Select chart type:" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *types=@[@"📊 Bar Chart",@"📈 Line Chart",@"🥧 Pie Chart",@"📉 Area Chart"];
    for(NSString *t in types) {
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
            [self showChartForSelection:t];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView=self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showChartForSelection:(NSString *)type {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableArray *labels=[NSMutableArray array];
    NSMutableArray<NSNumber *> *values=[NSMutableArray array];

    for(NSInteger r=MIN(self.selRow,self.selEndRow);r<=MAX(self.selRow,self.selEndRow);r++) {
        SpreadCell *labelCell=[sheet cellAtRow:r col:MIN(self.selCol,self.selEndCol)];
        SpreadCell *valCell=[sheet cellAtRow:r col:MAX(self.selCol,self.selEndCol)];
        [labels addObject:labelCell?labelCell.display:[NSString stringWithFormat:@"R%ld",(long)(r+1)]];
        [values addObject:@(valCell?[valCell.display doubleValue]:0)];
    }

    UIViewController *vc=[[UIViewController alloc] init];
    vc.title=type; vc.view.backgroundColor=[ThemeEngine bg];

    // Simple bar chart rendered with Core Graphics
    UIView *chartView=[[UIView alloc] init];
    chartView.translatesAutoresizingMaskIntoConstraints=NO;
    chartView.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.05];
    chartView.layer.cornerRadius=16;

    __weak typeof(chartView) wChart=chartView;
    NSArray *labsCopy=[labels copy]; NSArray *valsCopy=[values copy];

    chartView.layer.delegate=nil;
    // Draw via CADisplayLink or just use drawRect by subclassing
    UILabel *titleL=[[UILabel alloc] init];
    titleL.translatesAutoresizingMaskIntoConstraints=NO;
    titleL.text=[NSString stringWithFormat:@"%@ — %ld data points",type,(long)values.count];
    titleL.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.7];
    titleL.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    titleL.textAlignment=NSTextAlignmentCenter;

    [vc.view addSubview:chartView];
    [chartView addSubview:titleL];

    [NSLayoutConstraint activateConstraints:@[
        [chartView.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:20],
        [chartView.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:20],
        [chartView.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-20],
        [chartView.heightAnchor constraintEqualToConstant:300],
        [titleL.topAnchor constraintEqualToAnchor:chartView.topAnchor constant:12],
        [titleL.leadingAnchor constraintEqualToAnchor:chartView.leadingAnchor],
        [titleL.trailingAnchor constraintEqualToAnchor:chartView.trailingAnchor],
    ]];

    // We draw bars in layoutSubviews by adding bar views dynamically
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat maxVal=0;
        for(NSNumber *v in valsCopy) maxVal=MAX(maxVal,v.doubleValue);
        if(maxVal==0) maxVal=1;
        CGFloat chartH=220, chartY=60, barW=(wChart.bounds.size.width-40)/MAX(1,valsCopy.count);
        for(NSInteger i=0;i<(NSInteger)valsCopy.count;i++) {
            CGFloat h=([valsCopy[i] doubleValue]/maxVal)*(chartH-20);
            CGFloat x=20+i*barW;
            UIView *bar=[[UIView alloc] initWithFrame:CGRectMake(x,chartY+chartH-h,barW-4,h)];
            UIColor *colors[]={[UIColor systemBlueColor],[UIColor systemGreenColor],
                [UIColor systemOrangeColor],[UIColor systemPurpleColor],[UIColor systemRedColor]};
            bar.backgroundColor=colors[i%5];
            bar.layer.cornerRadius=3;
            [wChart addSubview:bar];
            UILabel *lbl=[[UILabel alloc] initWithFrame:CGRectMake(x,chartY+chartH,barW,16)];
            lbl.text=i<(NSInteger)labsCopy.count?labsCopy[i]:@"";
            lbl.font=[UIFont systemFontOfSize:8];
            lbl.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.6];
            lbl.textAlignment=NSTextAlignmentCenter;
            [wChart addSubview:lbl];
        }
    });

    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Add Sheet

- (void)addNewSheet {
    NSString *name=[NSString stringWithFormat:@"Sheet%lu",(unsigned long)(self.sheets.count+1)];
    SpreadSheet *s=[[SpreadSheet alloc] initWithName:name rows:100 cols:26];
    [self.sheets addObject:s];
    self.currentSheetIndex=(NSInteger)self.sheets.count-1;
    [self reloadGrid];
    [self reloadSheetTabs];
}

#pragma mark - Undo/Redo

- (void)saveUndo {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableDictionary *snapshot=[NSMutableDictionary dictionary];
    for(NSString *k in sheet.cells) snapshot[k]=[sheet.cells[k] copy];
    [self.undoStack addObject:@{@"cells":snapshot,@"sheetIdx":@(self.currentSheetIndex)}];
    [self.redoStack removeAllObjects];
    if(self.undoStack.count>50) [self.undoStack removeObjectAtIndex:0];
}

- (void)performUndo {
    if(!self.undoStack.count) return;
    NSDictionary *snap=self.undoStack.lastObject;
    [self.undoStack removeLastObject];
    SpreadSheet *sheet=self.sheets[[snap[@"sheetIdx"] integerValue]];
    // Save redo
    NSMutableDictionary *redo=[NSMutableDictionary dictionary];
    for(NSString *k in sheet.cells) redo[k]=[sheet.cells[k] copy];
    [self.redoStack addObject:@{@"cells":redo,@"sheetIdx":snap[@"sheetIdx"]}];
    sheet.cells=snap[@"cells"];
    [self reloadGrid];
}

- (void)performRedo {
    if(!self.redoStack.count) return;
    NSDictionary *snap=self.redoStack.lastObject;
    [self.redoStack removeLastObject];
    SpreadSheet *sheet=self.sheets[[snap[@"sheetIdx"] integerValue]];
    NSMutableDictionary *undo=[NSMutableDictionary dictionary];
    for(NSString *k in sheet.cells) undo[k]=[sheet.cells[k] copy];
    [self.undoStack addObject:@{@"cells":undo,@"sheetIdx":snap[@"sheetIdx"]}];
    sheet.cells=snap[@"cells"];
    [self reloadGrid];
}

#pragma mark - More Menu

- (void)showMoreMenu {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"More Options"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"🔍 Find & Replace" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self showFindReplace];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"📦 Export as CSV" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self exportCSV];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"📊 Export as TSV" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self exportTSV];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"🖨 Print" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self printSheet];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"📋 Copy All as Text" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){[self copyAllAsText];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"🗑 Clear All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_){[self clearAll];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showFindReplace {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Find & Replace"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){tf.placeholder=@"Find";}];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){tf.placeholder=@"Replace with";}];
    [a addAction:[UIAlertAction actionWithTitle:@"Replace All" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_){
        NSString *find=a.textFields[0].text, *rep=a.textFields[1].text;
        if(!find.length) return;
        [self saveUndo];
        SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
        for(SpreadCell *cell in sheet.cells.allValues) {
            if([cell.display containsString:find]) {
                cell.display=[cell.display stringByReplacingOccurrencesOfString:find withString:rep?:@""];
                cell.raw=cell.display;
            }
        }
        [self reloadGrid];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)clearAll {
    [self saveUndo];
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    [sheet.cells removeAllObjects];
    [self reloadGrid];
    self.isDirty=YES;
}

- (void)copyAllAsText {
    [[UIPasteboard generalPasteboard] setString:[self sheetsToCSV]];
}

- (void)printSheet {
    UIPrintInteractionController *pic=[UIPrintInteractionController sharedPrintController];
    UIPrintInfo *info=[UIPrintInfo printInfo];
    info.outputType=UIPrintInfoOutputGrayscale;
    info.jobName=self.filePath.lastPathComponent;
    pic.printInfo=info;
    pic.printFormatter=nil;
    // Create simple HTML for printing
    NSString *html=[self sheetsToHTML];
    UIMarkupTextPrintFormatter *fmt=[[UIMarkupTextPrintFormatter alloc] initWithMarkupText:html];
    pic.printFormatter=fmt;
    [pic presentAnimated:YES completionHandler:nil];
}

- (NSString *)sheetsToHTML {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableString *html=[NSMutableString stringWithString:@"<html><body><table border='1' cellpadding='4'>"];
    for(NSInteger r=0;r<sheet.rowCount;r++) {
        [html appendString:@"<tr>"];
        for(NSInteger c=0;c<sheet.colCount;c++) {
            SpreadCell *cell=[sheet cellAtRow:r col:c];
            [html appendFormat:@"<td>%@</td>",cell?cell.display:@""];
        }
        [html appendString:@"</tr>"];
    }
    [html appendString:@"</table></body></html>"];
    return html;
}

#pragma mark - Load / Save

- (void)loadData {
    NSString *ext=[self.filePath.pathExtension lowercaseString];
    NSString *content=[NSString stringWithContentsOfFile:self.filePath encoding:NSUTF8StringEncoding error:nil];

    SpreadSheet *sheet=[[SpreadSheet alloc] initWithName:@"Sheet1" rows:200 cols:26];
    [self.sheets addObject:sheet];
    self.currentSheetIndex=0;

    if(!content.length) return;

    NSString *delim=[ext isEqualToString:@"tsv"]?@"\t":@",";
    // Handle quoted fields in CSV
    NSArray<NSString *> *lines=[content componentsSeparatedByString:@"\n"];
    NSInteger maxCols=0;
    NSMutableArray *parsedRows=[NSMutableArray array];
    for(NSString *line in lines) {
        if(line.length==0) continue;
        NSArray *parts=[self parseCSVLine:line delimiter:delim];
        [parsedRows addObject:parts];
        if((NSInteger)parts.count>maxCols) maxCols=parts.count;
    }
    sheet.rowCount=MAX(200,(NSInteger)parsedRows.count+10);
    sheet.colCount=MAX(26,maxCols+2);
    while((NSInteger)sheet.colWidths.count<sheet.colCount) [sheet.colWidths addObject:@(90)];
    while((NSInteger)sheet.rowHeights.count<sheet.rowCount) [sheet.rowHeights addObject:@(28)];

    for(NSInteger r=0;r<(NSInteger)parsedRows.count;r++) {
        NSArray *parts=parsedRows[r];
        for(NSInteger c=0;c<(NSInteger)parts.count;c++) {
            NSString *val=parts[c];
            SpreadCell *cell=[SpreadCell new];
            cell.raw=val;
            if([val hasPrefix:@"="]) {
                cell.type=CellTypeFormula;
                cell.display=[FormulaEngine evaluate:val sheet:sheet];
            } else {
                cell.type=[self isNumeric:val]?CellTypeNumber:CellTypeText;
                cell.display=val;
            }
            [sheet setCell:cell row:r col:c];
        }
    }
}

- (NSArray<NSString *> *)parseCSVLine:(NSString *)line delimiter:(NSString *)delim {
    NSMutableArray *parts=[NSMutableArray array];
    NSMutableString *current=[NSMutableString string];
    BOOL inQuote=NO;
    for(NSInteger i=0;i<(NSInteger)line.length;i++) {
        unichar ch=[line characterAtIndex:i];
        if(ch=='"') { inQuote=!inQuote; }
        else if(!inQuote&&[line characterAtIndex:i]==[delim characterAtIndex:0]) {
            [parts addObject:[current copy]]; [current setString:@""];
        } else {
            [current appendFormat:@"%C",ch];
        }
    }
    [parts addObject:[current copy]];
    return parts;
}

- (void)saveData {
    NSString *csv=[self sheetsToCSV];
    NSError *err=nil;
    [csv writeToFile:self.filePath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if(!err) { self.isDirty=NO; }
}

- (NSString *)sheetsToCSV {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableString *out=[NSMutableString string];
    for(NSInteger r=0;r<sheet.rowCount;r++) {
        BOOL hasData=NO;
        for(NSInteger c=0;c<sheet.colCount;c++) {
            if([sheet cellAtRow:r col:c].raw.length) {hasData=YES;break;}
        }
        if(!hasData) continue;
        NSMutableArray *cols=[NSMutableArray array];
        for(NSInteger c=0;c<sheet.colCount;c++) {
            SpreadCell *cell=[sheet cellAtRow:r col:c];
            NSString *val=cell?cell.display:@"";
            // Escape commas
            if([val containsString:@","]) val=[NSString stringWithFormat:@"\"%@\"",val];
            [cols addObject:val];
        }
        // Trim trailing empty
        while(cols.count>0&&[cols.lastObject isEqualToString:@""]) [cols removeLastObject];
        [out appendString:[cols componentsJoinedByString:@","]];
        [out appendString:@"\n"];
    }
    return out;
}

- (void)exportCSV {
    NSString *csv=[self sheetsToCSV];
    NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:
        [[self.filePath.lastPathComponent stringByDeletingPathExtension] stringByAppendingString:@".csv"]];
    [csv writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *avc=[[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)exportTSV {
    SpreadSheet *sheet=self.sheets[self.currentSheetIndex];
    NSMutableString *out=[NSMutableString string];
    for(NSInteger r=0;r<sheet.rowCount;r++) {
        NSMutableArray *cols=[NSMutableArray array];
        for(NSInteger c=0;c<sheet.colCount;c++) {
            SpreadCell *cell=[sheet cellAtRow:r col:c];
            [cols addObject:cell?cell.display:@""];
        }
        [out appendString:[cols componentsJoinedByString:@"\t"]];
        [out appendString:@"\n"];
    }
    NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:
        [[self.filePath.lastPathComponent stringByDeletingPathExtension] stringByAppendingString:@".tsv"]];
    [out writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *avc=[[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:tmp]] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)shareFile {
    UIActivityViewController *avc=[[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:self.filePath]] applicationActivities:nil];
    avc.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems[1];
    [self presentViewController:avc animated:YES completion:nil];
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)n {
    CGRect kbFrame=[n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat h=kbFrame.size.height;
    self.gridScroll.contentInset=UIEdgeInsetsMake(0,0,h,0);
}

- (void)keyboardWillHide:(NSNotification *)n {
    self.gridScroll.contentInset=UIEdgeInsetsZero;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {}

@end
