#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PathBarView : UIView <UITextFieldDelegate>

@property (strong, nonatomic) NSString *path;
@property (copy, nonatomic, _Nullable) void (^onPathChanged)(NSString *newPath);

- (void)updatePath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
