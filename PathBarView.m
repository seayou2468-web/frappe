#import "PathBarView.h"
#import "ThemeEngine.h"

@interface PathBarView ()
@property (strong, nonatomic) UITextField *textField;
@property (strong, nonatomic) UIVisualEffectView *glassView;
@end

@implementation PathBarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.glassView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    self.glassView.translatesAutoresizingMaskIntoConstraints = NO;
    self.glassView.layer.cornerRadius = 14;
    self.glassView.clipsToBounds = YES;
    self.glassView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
    self.glassView.layer.borderWidth = 1.0;
    [self addSubview:self.glassView];

    self.textField = [[UITextField alloc] init];
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    self.textField.delegate = self;
    self.textField.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.textField.textColor = [UIColor whiteColor];
    self.textField.textAlignment = NSTextAlignmentLeft;
    self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textField.placeholder = @"パスを入力...";
    self.textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"パスを入力..." attributes:@{NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.3]}];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder.fill"]];
    icon.tintColor = [ThemeEngine liquidColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    UIView *leftPadding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 20)];
    icon.frame = CGRectMake(10, 0, 18, 20);
    [leftPadding addSubview:icon];
    self.textField.leftView = leftPadding;
    self.textField.leftViewMode = UITextFieldViewModeAlways;

    [self.glassView.contentView addSubview:self.textField];

    [NSLayoutConstraint activateConstraints:@[
        [self.glassView.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [self.glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        [self.glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [self.glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],

        [self.textField.leadingAnchor constraintEqualToAnchor:self.glassView.contentView.leadingAnchor],
        [self.textField.trailingAnchor constraintEqualToAnchor:self.glassView.contentView.trailingAnchor constant:-8],
        [self.textField.centerYAnchor constraintEqualToAnchor:self.glassView.contentView.centerYAnchor],
        [self.textField.heightAnchor constraintEqualToAnchor:self.glassView.contentView.heightAnchor]
    ]];
}

- (void)setPath:(NSString *)path {
    _path = path;
    self.textField.text = path;
}

- (void)updatePath:(NSString *)path {
    [self setPath:path];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    if (self.onPathChanged) {
        self.onPathChanged(textField.text);
    }
    return YES;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, 44);
}

@end
