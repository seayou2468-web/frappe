#import <Foundation/Foundation.h>
#import "idevice.h"

typedef void (^MobileConfigCompletion)(BOOL success, id _Nullable result, NSString * _Nullable error);

@interface MobileConfigService : NSObject

@property (nonatomic, copy) void (^logger)(NSString *msg);

/// Connection state
@property (nonatomic, assign, readonly) BOOL connected;

/// Initialize with core handles. Ownership is transferred to the service.
- (instancetype)initWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown;

/// Performs the connection sequence (RSD/Lockdown) and Hello handshake.
- (void)connectWithCompletion:(MobileConfigCompletion)completion;

/// Sends a request and waits for a response (Plist Service Protocol)
- (void)sendRequest:(NSDictionary *)request completion:(MobileConfigCompletion)completion;

/// GetProfileList
- (void)getProfileListWithCompletion:(MobileConfigCompletion)completion;

/// InstallProfile
- (void)installProfileWithData:(NSData *)profileData completion:(MobileConfigCompletion)completion;

/// RemoveProfile
- (void)removeProfileWithIdentifier:(NSString *)identifier completion:(MobileConfigCompletion)completion;

/// GetCloudConfiguration
- (void)getCloudConfigurationWithCompletion:(MobileConfigCompletion)completion;

/// SetWiFiPowerState
- (void)setWiFiPowerState:(BOOL)state completion:(MobileConfigCompletion)completion;

/// EraseDevice
- (void)eraseDeviceWithPreserveDataPlan:(BOOL)preserve disallowProximity:(BOOL)disallow completion:(MobileConfigCompletion)completion;

/// Escalate (Supervisor authentication)
- (void)escalateWithCertificate:(SecCertificateRef)cert privateKey:(SecKeyRef)key completion:(MobileConfigCompletion)completion;

/// Convenience method to install the restrictions profile from pymobiledevice3
- (void)installRestrictionsProfileWithCompletion:(MobileConfigCompletion)completion;

@end
