#import <Foundation/Foundation.h>
#import "idevice.h"

@interface HeartbeatManager : NSObject

+ (instancetype)sharedManager;
- (void)startHeartbeatWithLockdown:(struct LockdowndClientHandle *)lockdown ip:(NSString *)ip;
- (void)stopHeartbeat;

@end
