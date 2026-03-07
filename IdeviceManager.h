#import <Foundation/Foundation.h>
#import "extend/idevice.h"

typedef NS_ENUM(NSInteger, IdeviceConnectionStatus) {
    IdeviceStatusDisconnected,
    IdeviceStatusConnecting,
    IdeviceStatusConnected,
    IdeviceStatusError
};

@interface IdeviceManager : NSObject

@property (nonatomic, assign, readonly) IdeviceConnectionStatus status;
@property (nonatomic, copy) NSString *ipAddress;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, copy) NSString *pairingFilePath;
@property (nonatomic, copy, readonly) NSString *lastError;
@property (nonatomic, assign, readonly) BOOL heartbeatActive;
@property (nonatomic, assign, readonly) BOOL ddiMounted;

+ (instancetype)sharedManager;

- (void)connect;
- (void)disconnect;
- (void)selectPairingFile:(NSString *)path;

- (void)getAppListWithCompletion:(void (^)(NSArray *apps, NSError *error))completion;
- (void)launchAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion;

// RSD Support
- (void)getProcessListWithCompletion:(void (^)(NSArray *processes, NSError *error))completion;
- (void)captureSysdiagnoseWithCompletion:(void (^)(NSString *path, NSError *error))completion;
- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion;

@end
