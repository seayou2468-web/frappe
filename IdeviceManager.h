#import <Foundation/Foundation.h>
#import "extend/idevice.h"

typedef NS_ENUM(NSInteger, IdeviceConnectionStatus) {
    IdeviceStatusDisconnected,
    IdeviceStatusConnecting,
    IdeviceStatusConnected,
    IdeviceStatusError
};

@interface IdeviceManager : NSObject

@property (nonatomic, readonly) IdeviceConnectionStatus status;
@property (nonatomic, copy) NSString *ipAddress;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, copy) NSString *pairingFilePath;
@property (nonatomic, readonly) NSString *lastError;
@property (nonatomic, readonly) BOOL heartbeatActive;
@property (nonatomic, readonly) BOOL ddiMounted;

+ (instancetype)sharedManager;

- (void)connect;
- (void)disconnect;
- (void)selectPairingFile:(NSString *)path;

@end
