// File: PlistCell.h
// Location: プロジェクト直下

#import <UIKit/UIKit.h>

@interface PlistCell : UITableViewCell
@property (nonatomic, strong) UILabel *keyLabel;
@property (nonatomic, strong) UITextField *valueField;
@property (nonatomic, strong) UISwitch *boolSwitch;
@end