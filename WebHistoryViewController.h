#import <UIKit/UIKit.h>

@interface WebHistoryViewController : UIViewController
@property (nonatomic, copy) void (^onUrlSelected)(NSString *url);
@end
