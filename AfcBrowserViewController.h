#import <UIKit/UIKit.h>

@interface AfcBrowserViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) NSString *currentPath;
- (instancetype)initWithPath:(NSString *)path;
@end
