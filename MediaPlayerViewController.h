#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>



@interface MediaPlayerViewController : AVPlayerViewController
- (instancetype)initWithPath:(NSString *)path;
@end

