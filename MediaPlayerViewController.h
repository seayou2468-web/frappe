#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
@interface MediaPlayerViewController : AVPlayerViewController
- (instancetype)initWithPath:(NSString *)path;
@end
