// File: PlistCell.m
// Location: プロジェクト直下

#import "PlistCell.h"

@implementation PlistCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _keyLabel = [[UILabel alloc] init];
        _keyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_keyLabel];

        _valueField = [[UITextField alloc] init];
        _valueField.translatesAutoresizingMaskIntoConstraints = NO;
        _valueField.borderStyle = UITextBorderStyleRoundedRect;
        [self.contentView addSubview:_valueField];

        _boolSwitch = [[UISwitch alloc] init];
        _boolSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_boolSwitch];

        [NSLayoutConstraint activateConstraints:@[
            [_keyLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
            [_keyLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_boolSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-15],
            [_boolSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueField.leadingAnchor constraintEqualToAnchor:_keyLabel.trailingAnchor constant:10],
            [_valueField.trailingAnchor constraintEqualToAnchor:_boolSwitch.leadingAnchor constant:-10],
            [_valueField.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueField.heightAnchor constraintEqualToConstant:30]
        ]];
    }
    return self;
}

@end