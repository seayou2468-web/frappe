#import <UIKit/UIKit.h>

@interface FileBrowserViewController : UIViewController

@property (strong, nonatomic) NSString *currentPath;
@property (nonatomic, assign) BOOL isPickingFile;
@property (nonatomic, copy) void (^onFilePicked)(NSString *path);

- (instancetype)initWithPath:(NSString *)path;

@end
