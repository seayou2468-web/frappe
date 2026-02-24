// ViewController.h
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong, readonly) NSString *currentPath;
- (instancetype)initWithPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END