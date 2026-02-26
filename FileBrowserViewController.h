#import <UIKit/UIKit.h>

@interface FileBrowserViewController : UIViewController

@property (strong, nonatomic) NSString *currentPath;
@property (strong, nonatomic) UITableView *tableView;

- (instancetype)initWithPath:(NSString *)path;
- (void)handleMenuAction:(NSNumber *)action;

@end
