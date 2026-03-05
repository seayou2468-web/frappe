#import <UIKit/UIKit.h>

@interface WebStartPageView : UIView
@property (nonatomic, copy) void (^onSearch)(NSString *query);
@property (nonatomic, copy) void (^onBookmarkSelect)(NSString *url);
- (void)reloadBookmarks;
@end
