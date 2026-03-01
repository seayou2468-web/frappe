#import "PathBarView.h"



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
    self.glassView.layer.cornerRadius = 10;
    self.glassView.clipsToBounds = YES;
    self.glassView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1].CGColor;
    self.glassView.layer.borderWidth = 0.5;
    [self addSubview:self.glassView];

    self.textField = [[UITextField alloc] init];
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    self.textField.delegate = self;
    self.textField.font = [UIFont systemFontOfSize:13];
    self.textField.textColor = [UIColor whiteColor];
    self.textField.textAlignment = NSTextAlignmentCenter;
    self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textField.placeholder = @"Enter path...";
    self.textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Enter path..." attributes:@{NSForegroundColorAttributeName: [[UIColor whiteColor] colorWithAlphaComponent:0.4]}];
    [self.glassView.contentView addSubview:self.textField];

    [NSLayoutConstraint activateConstraints:@[
        [self.glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [self.textField.leadingAnchor constraintEqualToAnchor:self.glassView.contentView.leadingAnchor constant:8],
        [self.textField.trailingAnchor constraintEqualToAnchor:self.glassView.contentView.trailingAnchor constant:-8],
        [self.textField.centerYAnchor constraintEqualToAnchor:self.glassView.contentView.centerYAnchor],
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
    return CGSizeMake(UIViewNoIntrinsicMetric, 36);
}

@end

