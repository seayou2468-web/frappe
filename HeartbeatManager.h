#import <Foundation/Foundation.h>
#import "idevice.h"

@interface HeartbeatManager : NSObject
+ (instancetype)sharedManager;
- (void)startHeartbeatWithProvider:(struct IdeviceProviderHandle *)provider;
- (void)stopHeartbeat;
@end
