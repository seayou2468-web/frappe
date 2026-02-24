// PathBarFileBrowser.m
#import "PathBarFileBrowser.h"

@interface PathBarFileBrowser ()
@property (nonatomic, strong) UILabel *pathLabel;
@end

@implementation PathBarFileBrowser

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor systemGray6Color] colorWithAlphaComponent:0.8];
        self.layer.cornerRadius = 12;
        self.layer.masksToBounds = YES;

        self.pathLabel = [[UILabel alloc] initWithFrame:self.bounds];
        self.pathLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.pathLabel.textAlignment = NSTextAlignmentCenter;
        self.pathLabel.userInteractionEnabled = YES;
        self.pathLabel.textColor = [UIColor labelColor];
        [self addSubview:self.pathLabel];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(promptPath)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)setPathText:(NSString *)path {
    self.pathLabel.text = path;
}

- (void)promptPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"移動先パス"
                                                                   message:@"絶対パスを入力してください"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull tf) {
        tf.text = self.pathLabel.text;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"移動" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *tf = alert.textFields.firstObject;
        if (self.onPathEntered && tf.text.length > 0) {
            self.onPathEntered(tf.text);
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    [vc presentViewController:alert animated:YES completion:nil];
}

@end