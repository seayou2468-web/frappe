#import <UIKit/UIKit.h>

@interface ExcelViewerViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
- (instancetype)initWithPath:(NSString *)path;
@end
