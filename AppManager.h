#import <Foundation/Foundation.h>
#import "idevice.h"

@interface AppInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, assign) BOOL isSystem;
@property (nonatomic, strong) UIImage *icon;
@end

@interface AppManager : NSObject

+ (instancetype)sharedManager;
- (void)fetchAppsWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<AppInfo *> *apps, NSString *error))completion;
- (void)launchApp:(NSString *)bundleId withJit:(BOOL)jit provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion;

@end
