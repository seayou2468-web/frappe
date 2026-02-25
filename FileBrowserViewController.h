#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FileBrowserViewController : UIViewController

@property (strong, nonatomic) NSString *currentPath;

- (instancetype)initWithPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
