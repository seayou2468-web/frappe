#import <UIKit/UIKit.h>
#import "FileManagerCore.h"

@interface FileInfoViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
- (instancetype)initWithItem:(FileItem *)item;
@end
