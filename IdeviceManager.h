#import <Foundation/Foundation.h>
#import "extend/idevice.h"

@interface IdeviceManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, copy) NSString *lastError;

- (void)connectWithIP:(NSString *)ip port:(int)port pairingPath:(NSString *)path completion:(void (^)(BOOL success, NSString *message))completion;
- (void)disconnect;

- (id)objectFromPlist:(plist_t)plist;

@end

- (void)fetchDeviceInfoWithCompletion:(void (^)(NSDictionary *info, NSString *error))completion;
- (void)listAppsWithCompletion:(void (^)(NSArray *apps, NSString *error))completion;
- (void)listDirectory:(NSString *)path completion:(void (^)(NSArray *items, NSString *error))completion;

@end
