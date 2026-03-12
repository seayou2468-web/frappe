#import <Foundation/Foundation.h>
#import "idevice.h"

typedef void (^MobileConfigCompletion)(BOOL success, id _Nullable result, NSString * _Nullable error);

@interface MobileConfigService : NSObject

@property (nonatomic, assign, readonly) struct ReadWriteOpaque *stream;

- (instancetype)initWithStream:(struct ReadWriteOpaque *)stream;

/// Sends a request and waits for a response (Plist Service Protocol)
- (void)sendRequest:(NSDictionary *)request completion:(MobileConfigCompletion)completion;

/// HelloHostIdentifier
- (void)helloWithCompletion:(MobileConfigCompletion)completion;

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
