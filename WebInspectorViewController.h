#import <UIKit/UIKit.h>

@interface WebInspectorViewController : UIViewController
@property (nonatomic, copy) NSString *htmlSource;
@property (nonatomic, strong) NSMutableArray<NSString *> *consoleLogs;
@end
