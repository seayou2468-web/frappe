#import <UIKit/UIKit.h>



@interface PathBarView : UIView <UITextFieldDelegate>

@property (strong, nonatomic) NSString *path;
@property (copy, nonatomic) void (^onPathChanged)(NSString *newPath);

- (void)updatePath:(NSString *)path;

@end

