#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MediaPlayerViewController : AVPlayerViewController
- (instancetype)initWithPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
