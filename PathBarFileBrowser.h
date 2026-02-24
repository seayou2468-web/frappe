// PathBarFileBrowser.h
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PathBarFileBrowser : UIView
@property (nonatomic, copy) void (^onPathEntered)(NSString *path);
- (void)setPathText:(NSString *)path;
@end

NS_ASSUME_NONNULL_END