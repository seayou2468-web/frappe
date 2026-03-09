#import <Foundation/Foundation.h>
#import "idevice.h"

@interface DdiManager : NSObject
+ (instancetype)sharedManager;
- (void)checkAndMountDdiWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown completion:(void (^)(BOOL success, NSString *message))completion;
@end
