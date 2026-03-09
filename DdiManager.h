#import <Foundation/Foundation.h>
#import "idevice.h"

@interface DdiManager : NSObject

+ (instancetype)sharedManager;
- (void)checkAndMountDdiWithLockdown:(struct LockdowndClientHandle *)lockdown ip:(NSString *)ip completion:(void (^)(BOOL success, NSString *message))completion;

@end
