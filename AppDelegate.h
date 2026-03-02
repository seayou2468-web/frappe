#import <UIKit/UIKit.h>



@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (nonatomic, copy) void (^backgroundSessionCompletionHandler)(void);
@end

