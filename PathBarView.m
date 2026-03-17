#import "PathBarView.h"
#import "ThemeEngine.h"

@interface PathCrumb : UIControl
@property (nonatomic, copy) NSString *segment;
@property (nonatomic, copy) NSString *fullPath;
@end
@implementation PathCrumb
- (instancetype)initWithSegment:(NSString *)seg fullPath:(NSString *)fp {
    self = [super init];
    if (!self) return nil;
    _segment = seg; _fullPath = fp;
    UILabel *lbl = [[UILabel alloc] init];
    lbl.text = seg;
    lbl.font = [ThemeEngine fontSubhead];
    lbl.textColor = [ThemeEngine textSecondary];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:lbl];
    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
        [lbl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
        [lbl.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    [self.widthAnchor constraintGreaterThanOrEqualToConstant:28].active = YES;
    [self addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)pressed {
    [UIView animateWithDuration:0.12 animations:^{ self.alpha = 0.4; }
                     completion:^(BOOL f){ [UIView animateWithDuration:0.15 animations:^{ self.alpha=1; }]; }];
}
- (void)setIsLast:(BOOL)last {
    UILabel *lbl = (UILabel *)self.subviews.firstObject;
    lbl.textColor = last ? [ThemeEngine textPrimary] : [ThemeEngine textSecondary];
    lbl.font = last ? [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold] : [ThemeEngine fontSubhead];
}
@end

@interface PathBarView () <UIScrollViewDelegate, UITextFieldDelegate>
@property (strong) UIScrollView *scroll;
@property (strong) UIStackView *crumbStack;
@property (strong) UITextField *textField;
@property (strong) UIView *blurContainer;
@property (strong) UIButton *editBtn;
@property (assign) BOOL isEditing;
@end

@implementation PathBarView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) [self buildUI];
    return self;
}

- (void)buildUI {
    // Glass container
    _blurContainer = [[UIView alloc] init];
    _blurContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassToView:_blurContainer radius:kCornerM];
    [self addSubview:_blurContainer];

    // Scroll for breadcrumb
    _scroll = [[UIScrollView alloc] init];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    [_blurContainer addSubview:_scroll];

    _crumbStack = [[UIStackView alloc] init];
    _crumbStack.translatesAutoresizingMaskIntoConstraints = NO;
    _crumbStack.axis = UILayoutConstraintAxisHorizontal;
    _crumbStack.spacing = 2;
    _crumbStack.alignment = UIStackViewAlignmentCenter;
    [_scroll addSubview:_crumbStack];

    // Edit field (hidden by default)
    _textField = [[UITextField alloc] init];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;
    _textField.delegate = self;
    _textField.font = [ThemeEngine fontSubhead];
    _textField.textColor = [ThemeEngine textPrimary];
    _textField.autocorrectionType = UITextAutocorrectionTypeNo;
    _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textField.returnKeyType = UIReturnKeyGo;
    _textField.hidden = YES;
    _textField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"/" attributes:@{NSForegroundColorAttributeName:[ThemeEngine textTertiary]}];
    [_blurContainer addSubview:_textField];

    // Edit/Done button
    _editBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _editBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    [_editBtn setImage:[UIImage systemImageNamed:@"pencil" withConfiguration:cfg]
              forState:UIControlStateNormal];
    _editBtn.tintColor = [ThemeEngine textTertiary];
    [_editBtn addTarget:self action:@selector(toggleEdit) forControlEvents:UIControlEventTouchUpInside];
    [_blurContainer addSubview:_editBtn];

    // Folder icon
    UIImageView *folderIcon = [[UIImageView alloc] init];
    folderIcon.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *folderCfg = [UIImageSymbolConfiguration
        configurationWithPointSize:13 weight:UIImageSymbolWeightMedium];
    folderIcon.image = [UIImage systemImageNamed:@"folder.fill" withConfiguration:folderCfg];
    folderIcon.tintColor = [ThemeEngine accent];
    folderIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_blurContainer addSubview:folderIcon];

    [NSLayoutConstraint activateConstraints:@[
        [_blurContainer.topAnchor constraintEqualToAnchor:self.topAnchor constant:5],
        [_blurContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-5],
        [_blurContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_blurContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],

        [folderIcon.leadingAnchor constraintEqualToAnchor:_blurContainer.leadingAnchor constant:10],
        [folderIcon.centerYAnchor constraintEqualToAnchor:_blurContainer.centerYAnchor],
        [folderIcon.widthAnchor constraintEqualToConstant:18],
        [folderIcon.heightAnchor constraintEqualToConstant:18],

        [_scroll.leadingAnchor constraintEqualToAnchor:folderIcon.trailingAnchor constant:6],
        [_scroll.trailingAnchor constraintEqualToAnchor:_editBtn.leadingAnchor constant:-4],
        [_scroll.topAnchor constraintEqualToAnchor:_blurContainer.topAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:_blurContainer.bottomAnchor],

        [_crumbStack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [_crumbStack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [_crumbStack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
        [_crumbStack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
        [_crumbStack.heightAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.heightAnchor],

        [_textField.leadingAnchor constraintEqualToAnchor:folderIcon.trailingAnchor constant:6],
        [_textField.trailingAnchor constraintEqualToAnchor:_editBtn.leadingAnchor constant:-4],
        [_textField.centerYAnchor constraintEqualToAnchor:_blurContainer.centerYAnchor],

        [_editBtn.trailingAnchor constraintEqualToAnchor:_blurContainer.trailingAnchor constant:-10],
        [_editBtn.centerYAnchor constraintEqualToAnchor:_blurContainer.centerYAnchor],
        [_editBtn.widthAnchor constraintEqualToConstant:30],
        [_editBtn.heightAnchor constraintEqualToConstant:30],
    ]];
}

- (void)updatePath:(NSString *)path {
    _path = path;
    [self rebuildCrumbs:path];
}

- (void)setPath:(NSString *)path { [self updatePath:path]; }

- (void)rebuildCrumbs:(NSString *)path {
    for (UIView *v in _crumbStack.arrangedSubviews) [_crumbStack removeArrangedSubview:v];
    [_crumbStack.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSArray *components = path.pathComponents;
    NSMutableString *built = [NSMutableString string];

    for (NSUInteger i = 0; i < components.count; i++) {
        NSString *seg = components[i];
        [built appendString:(built.length == 0 ? seg : [@"/" stringByAppendingString:seg])];
        if ([seg isEqualToString:@"/"]) { built = [@"/" mutableCopy]; }

        NSString *fp = [built copy];
        PathCrumb *crumb = [[PathCrumb alloc] initWithSegment:([seg isEqualToString:@"/"] ? @"/" : seg)
                                                     fullPath:fp];
        [crumb setIsLast:(i == components.count - 1)];
        __weak typeof(self) ws = self;
        [crumb addTarget:ws action:@selector(crumbTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_crumbStack addArrangedSubview:crumb];

        // Separator
        if (i < components.count - 1) {
            UIImageView *sep = [[UIImageView alloc] init];
            UIImageSymbolConfiguration *cfg2 = [UIImageSymbolConfiguration
                configurationWithPointSize:9 weight:UIImageSymbolWeightLight];
            sep.image = [UIImage systemImageNamed:@"chevron.right" withConfiguration:cfg2];
            sep.tintColor = [ThemeEngine textTertiary];
            sep.contentMode = UIViewContentModeScaleAspectFit;
            [sep setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [sep setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [_crumbStack addArrangedSubview:sep];
        }
    }

    // Scroll to end
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_scroll setContentOffset:CGPointMake(
            MAX(0, self->_scroll.contentSize.width - self->_scroll.bounds.size.width), 0)
                               animated:NO];
    });
}

- (void)crumbTapped:(PathCrumb *)crumb {
    if (self.onPathChanged) self.onPathChanged(crumb.fullPath);
}

- (void)toggleEdit {
    _isEditing = !_isEditing;
    _textField.text = _path;
    _scroll.hidden = _isEditing;
    _textField.hidden = !_isEditing;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    NSString *sym = _isEditing ? @"xmark" : @"pencil";
    [_editBtn setImage:[UIImage systemImageNamed:sym withConfiguration:cfg]
              forState:UIControlStateNormal];

    [UIView animateWithDuration:0.25 animations:^{
        self->_editBtn.tintColor = self->_isEditing ? [ThemeEngine accent] : [ThemeEngine textTertiary];
    }];

    if (_isEditing) {
        [_textField becomeFirstResponder];
        [_textField selectAll:nil];
    } else {
        [_textField resignFirstResponder];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    NSString *p = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (p.length > 0 && self.onPathChanged) self.onPathChanged(p);
    [self toggleEdit];
    return YES;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 52); }
@end
