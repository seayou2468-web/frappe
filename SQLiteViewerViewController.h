#import <UIKit/UIKit.h>

@interface SQLiteViewerViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
- (instancetype)initWithPath:(NSString *)path;
@end
