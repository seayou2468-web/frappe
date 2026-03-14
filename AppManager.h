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
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *signer;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *container;
@property (nonatomic, copy) NSString *diskUsage;
@property (nonatomic, assign) BOOL isSystem;
@property (nonatomic, retain) UIImage *icon;
@end

@interface AppManager : NSObject

+ (instancetype)sharedManager;
- (void)fetchAppsWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<AppInfo *> *apps, NSString *error))completion;
- (void)installAppWithURL:(NSURL *)url provider:(struct IdeviceProviderHandle *)provider progress:(void (^)(double progress, NSString *status))progress completion:(void (^)(BOOL success, NSString *error))completion;
- (void)launchApp:(NSString *)bundleId jitMode:(JitMode)jitMode provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion;

@end
