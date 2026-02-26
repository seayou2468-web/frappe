#import "PathBarView.h"
#import "ThemeEngine.h"

@interface PathBarView ()
@property (strong, nonatomic) UITextField *textField;

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
    [ThemeEngine applyLiquidGlassStyleToView:self cornerRadius:18];

    self.textField = [[UITextField alloc] init];
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    self.textField.delegate = self;
    self.textField.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.textField.textColor = [UIColor whiteColor];
    self.textField.textAlignment = NSTextAlignmentLeft;
    self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textField.placeholder = @"Enter path...";
    self.textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Enter path..." attributes:@{NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.3]}];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder"]];
    iconView.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.textField.leftView = iconView;
    self.textField.leftViewMode = UITextFieldViewModeAlways;

    [self addSubview:self.textField];

    [NSLayoutConstraint activateConstraints:@[
        [self.textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [self.textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [self.textField.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.textField.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)updatePath:(NSString *)path {
    self.path = path;
    self.textField.text = path;
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