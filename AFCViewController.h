#import <UIKit/UIKit.h>

@interface AFCViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, copy) NSString *currentPath;
- (instancetype)initWithPath:(NSString *)path;
@end
