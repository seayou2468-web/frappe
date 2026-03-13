#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "idevice.h"

typedef NS_ENUM(NSInteger, JitMode) {
    JitModeNone,
    JitModeJS,
    JitModeNative
};

@interface AppInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, assign) BOOL isSystem;
@property (nonatomic, retain) UIImage *icon;
@end

@interface ProfileInfo : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *organization;
@property (nonatomic, copy) NSString *profileDescription;
@property (nonatomic, assign) BOOL isEncrypted;
@end

@interface AppManager : NSObject

+ (instancetype)sharedManager;
- (void)fetchAppsWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<AppInfo *> *apps, NSString *error))completion;
- (void)launchApp:(NSString *)bundleId jitMode:(JitMode)jitMode provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion;

- (void)fetchProfilesWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<ProfileInfo *> *profiles, NSString *error))completion;
- (void)installProfileData:(NSData *)profileData provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion;
- (void)removeProfileWithIdentifier:(NSString *)identifier provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion;

@end
