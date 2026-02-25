#import <UIKit/UIKit.h>

@interface FileBrowserViewController : UIViewController

@property (strong, nonatomic) NSString *currentPath;

- (instancetype)initWithPath:(NSString *)path;

@end
