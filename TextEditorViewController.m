#import "TextEditorViewController.h"
#import "ThemeEngine.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TextEditorViewController () <UITextViewDelegate, UISearchBarDelegate>
@property (strong) NSString      *path;
@property (strong) UITextView    *textView;
@property (strong) UIView        *toolbar;
@property (strong) UILabel       *statusLabel;
@property (strong) UIView        *findBar;
@property (strong) UITextField   *findField;
@property (strong) UITextField   *replaceField;
@property (assign) BOOL           isModified;
@property (assign) NSInteger      fontSize;
@property (assign) NSStringEncoding currentEncoding;
@end

@implementation TextEditorViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) { _path = path; _fontSize = 14; _currentEncoding = NSUTF8StringEncoding; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ThemeEngine bg];
    self.title = self.path.lastPathComponent;
    [self setupTextView];
    [self setupToolbar];
    [self setupNavBar];
    [self setupFindBar];
    [self loadFile];
}

- (void)setupNavBar {
    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
                style:UIBarButtonItemStylePlain target:self action:@selector(saveText)];
    UIBarButtonItem *moreBtn = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                style:UIBarButtonItemStylePlain target:self action:@selector(showMore)];
    self.navigationItem.rightBarButtonItems = @[saveBtn, moreBtn];
    saveBtn.tintColor = [ThemeEngine accent];
}

- (void)setupTextView {
    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = [ThemeEngine textPrimary];
    self.textView.font = [UIFont fontWithName:@"Menlo-Regular" size:_fontSize] ?: [UIFont monospacedSystemFontOfSize:_fontSize weight:UIFontWeightRegular];
    self.textView.tintColor = [ThemeEngine accent];
    self.textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.smartDashesType = UITextSmartDashesTypeNo;
    self.textView.smartQuotesType = UITextSmartQuotesTypeNo;
    self.textView.delegate = self;
    [self.view addSubview:self.textView];
}

- (void)setupToolbar {
    self.toolbar = [[UIView alloc] init];
    self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassToView:self.toolbar radius:0];

    NSArray *toolItems = @[
        @[@"magnifyingglass", @"toggleFind"],
        @[@"arrow.uturn.left", @"undoAction"],
        @[@"arrow.uturn.right", @"redoAction"],
        @[@"textformat.size.smaller", @"decreaseFontSize"],
        @[@"textformat.size.larger", @"increaseFontSize"],
        @[@"keyboard.chevron.compact.down", @"dismissKeyboard"],
    ];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    [self.toolbar addSubview:stack];

    for (NSArray *item in toolItems) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
            configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
        [btn setImage:[UIImage systemImageNamed:item[0] withConfiguration:cfg] forState:UIControlStateNormal];
        btn.tintColor = [ThemeEngine textSecondary];
        [btn addTarget:self action:NSSelectorFromString(item[1]) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:btn];
    }

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.statusLabel.textColor = [ThemeEngine textTertiary];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.toolbar addSubview:self.statusLabel];

    [self.view addSubview:self.toolbar];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.toolbar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.toolbar.heightAnchor constraintEqualToConstant:44],

        [stack.topAnchor constraintEqualToAnchor:self.toolbar.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.toolbar.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.toolbar.leadingAnchor constant:8],
        [stack.widthAnchor constraintEqualToConstant:240],

        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.toolbar.centerYAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.toolbar.trailingAnchor constant:-12],

        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-4],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.toolbar.topAnchor],
    ]];
}

- (void)setupFindBar {
    self.findBar = [[UIView alloc] init];
    self.findBar.translatesAutoresizingMaskIntoConstraints = NO;
    [ThemeEngine applyGlassToView:self.findBar radius:0];
    self.findBar.hidden = YES;

    self.findField = [[UITextField alloc] init];
    self.findField.translatesAutoresizingMaskIntoConstraints = NO;
    self.findField.placeholder = @"検索";
    self.findField.textColor = [ThemeEngine textPrimary];
    self.findField.font = [UIFont systemFontOfSize:14];
    self.findField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    self.findField.layer.cornerRadius = 8;
    [self.findBar addSubview:self.findField];

    self.replaceField = [[UITextField alloc] init];
    self.replaceField.translatesAutoresizingMaskIntoConstraints = NO;
    self.replaceField.placeholder = @"置換";
    self.replaceField.textColor = [ThemeEngine textPrimary];
    self.replaceField.font = [UIFont systemFontOfSize:14];
    self.replaceField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
    self.replaceField.layer.cornerRadius = 8;
    [self.findBar addSubview:self.replaceField];

    UIButton *findNextBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    findNextBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [findNextBtn setTitle:@"次を検索" forState:UIControlStateNormal];
    findNextBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    findNextBtn.tintColor = [ThemeEngine accent];
    [findNextBtn addTarget:self action:@selector(findNext) forControlEvents:UIControlEventTouchUpInside];
    [self.findBar addSubview:findNextBtn];

    UIButton *replaceBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    replaceBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [replaceBtn setTitle:@"すべて置換" forState:UIControlStateNormal];
    replaceBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    replaceBtn.tintColor = [UIColor systemOrangeColor];
    [replaceBtn addTarget:self action:@selector(replaceAll) forControlEvents:UIControlEventTouchUpInside];
    [self.findBar addSubview:replaceBtn];

    [self.view addSubview:self.findBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.findBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.findBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.findBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.findBar.heightAnchor constraintEqualToConstant:88],

        [self.findField.topAnchor constraintEqualToAnchor:self.findBar.topAnchor constant:8],
        [self.findField.leadingAnchor constraintEqualToAnchor:self.findBar.leadingAnchor constant:8],
        [self.findField.heightAnchor constraintEqualToConstant:32],
        [self.findField.widthAnchor constraintEqualToConstant:180],
        [findNextBtn.centerYAnchor constraintEqualToAnchor:self.findField.centerYAnchor],
        [findNextBtn.leadingAnchor constraintEqualToAnchor:self.findField.trailingAnchor constant:8],

        [self.replaceField.topAnchor constraintEqualToAnchor:self.findField.bottomAnchor constant:6],
        [self.replaceField.leadingAnchor constraintEqualToAnchor:self.findBar.leadingAnchor constant:8],
        [self.replaceField.heightAnchor constraintEqualToConstant:32],
        [self.replaceField.widthAnchor constraintEqualToConstant:180],
        [replaceBtn.centerYAnchor constraintEqualToAnchor:self.replaceField.centerYAnchor],
        [replaceBtn.leadingAnchor constraintEqualToAnchor:self.replaceField.trailingAnchor constant:8],
    ]];
}

- (void)loadFile {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.path]) {
        // New file
        [[NSFileManager defaultManager] createFileAtPath:self.path contents:[NSData data] attributes:nil];
        [self updateStatus];
        return;
    }
    // Try UTF-8 first, then fallback encodings
    NSError *err;
    NSString *content = [NSString stringWithContentsOfFile:self.path encoding:NSUTF8StringEncoding error:&err];
    if (!content) {
        NSStringEncoding enc;
        content = [NSString stringWithContentsOfFile:self.path usedEncoding:&enc error:&err];
        if (content) _currentEncoding = enc;
    }
    self.textView.text = content ?: @"";
    [self updateStatus];
}

- (void)updateStatus {
    NSString *text = self.textView.text ?: @"";
    NSInteger lines = [[text componentsSeparatedByString:@"\n"] count];
    NSInteger chars = (NSInteger)text.length;
    self.statusLabel.text = [NSString stringWithFormat:@"%ld行 / %ld文字%@",
        (long)lines, (long)chars, _isModified ? @" ●" : @""];
}

- (void)textViewDidChange:(UITextView *)tv { _isModified = YES; [self updateStatus]; }

- (void)saveText {
    NSError *err;
    if ([self.textView.text writeToFile:self.path atomically:YES encoding:_currentEncoding error:&err]) {
        _isModified = NO;
        [self updateStatus];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    } else {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"保存エラー"
            message:err.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

- (void)showMore {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"共有" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        UIActivityViewController *avc = [[UIActivityViewController alloc]
            initWithActivityItems:@[[NSURL fileURLWithPath:self.path]] applicationActivities:nil];
        avc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
        [self presentViewController:avc animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"行番号へ移動" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self gotoLine];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"文字コード変更" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self selectEncoding];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"すべて選択" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self.textView selectAll:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toggleFind {
    self.findBar.hidden = !self.findBar.hidden;
    if (!self.findBar.hidden) {
        UIEdgeInsets insets = self.textView.contentInset;
        insets.top = 88;
        self.textView.contentInset = insets;
        [self.findField becomeFirstResponder];
    } else {
        UIEdgeInsets insets = self.textView.contentInset;
        insets.top = 0;
        self.textView.contentInset = insets;
        [self.textView becomeFirstResponder];
    }
}

- (void)findNext {
    NSString *query = self.findField.text;
    if (query.length == 0) return;
    NSString *text = self.textView.text;
    NSRange searchFrom = NSMakeRange(0, text.length);
    if (self.textView.selectedRange.location != NSNotFound) {
        NSRange sel = self.textView.selectedRange;
        NSUInteger start = sel.location + MAX(sel.length, 1);
        if (start < text.length) searchFrom = NSMakeRange(start, text.length - start);
    }
    NSRange found = [text rangeOfString:query options:NSCaseInsensitiveSearch range:searchFrom];
    if (found.location == NSNotFound) {
        // Wrap around
        found = [text rangeOfString:query options:NSCaseInsensitiveSearch];
    }
    if (found.location != NSNotFound) {
        self.textView.selectedRange = found;
        [self.textView scrollRangeToVisible:found];
    }
}

- (void)replaceAll {
    NSString *find = self.findField.text;
    NSString *repl = self.replaceField.text ?: @"";
    if (find.length == 0) return;
    NSString *newText = [self.textView.text stringByReplacingOccurrencesOfString:find
        withString:repl options:NSCaseInsensitiveSearch range:NSMakeRange(0, self.textView.text.length)];
    self.textView.text = newText;
    _isModified = YES;
    [self updateStatus];
}

- (void)gotoLine {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"行番号へ移動"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"行番号";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"移動" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSInteger target = [a.textFields.firstObject.text integerValue];
        if (target <= 0) return;
        NSArray *lines = [self.textView.text componentsSeparatedByString:@"\n"];
        if (target > (NSInteger)lines.count) target = (NSInteger)lines.count;
        NSUInteger offset = 0;
        for (NSInteger i = 0; i < target - 1; i++) offset += [(NSString *)lines[i] length] + 1;
        NSRange r = NSMakeRange(MIN(offset, self.textView.text.length), 0);
        self.textView.selectedRange = r;
        [self.textView scrollRangeToVisible:r];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)selectEncoding {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"文字コード"
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *encodings = @{
        @"UTF-8": @(NSUTF8StringEncoding),
        @"UTF-16": @(NSUTF16StringEncoding),
        @"Shift_JIS": @(NSShiftJISStringEncoding),
        @"EUC-JP": @(NSJapaneseEUCStringEncoding),
        @"ISO-8859-1": @(NSISOLatin1StringEncoding),
    };
    for (NSString *name in encodings) {
        NSStringEncoding enc = [encodings[name] unsignedIntegerValue];
        BOOL isCurrent = (enc == _currentEncoding);
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", isCurrent?@"✓":@"", name]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                _currentEncoding = enc;
            }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)undoAction    { [self.textView.undoManager undo]; }
- (void)redoAction    { [self.textView.undoManager redo]; }
- (void)decreaseFontSize { _fontSize = MAX(8, _fontSize - 2); [self applyFont]; }
- (void)increaseFontSize { _fontSize = MIN(32, _fontSize + 2); [self applyFont]; }
- (void)applyFont {
    self.textView.font = [UIFont fontWithName:@"Menlo-Regular" size:_fontSize]
        ?: [UIFont monospacedSystemFontOfSize:_fontSize weight:UIFontWeightRegular];
}
- (void)dismissKeyboard { [self.textView resignFirstResponder]; }

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_isModified) [self saveText];
}
@end
