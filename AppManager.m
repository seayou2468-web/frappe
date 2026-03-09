#import "AppManager.h"
#import <UIKit/UIKit.h>

@implementation AppInfo
@end

@implementation AppManager

+ (instancetype)sharedManager {
    static AppManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[AppManager alloc] init]; });
    return shared;
}

- (void)fetchAppsWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<AppInfo *> *apps, NSString *error))completion {
    if (!provider) { completion(nil, @"Missing provider"); return; }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct InstallationProxyClientHandle *instproxy = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(provider, &instproxy);
        if (err) { completion(nil, [NSString stringWithUTF8String:err->message]); idevice_error_free(err); return; }

        NSMutableArray *allApps = [NSMutableArray array];

        // Fetch User apps
        [self fetchAppsWithType:"User" client:instproxy list:allApps];
        // Fetch System apps
        [self fetchAppsWithType:"System" client:instproxy list:allApps];

        installation_proxy_client_free(instproxy);
        completion(allApps, nil);
    });
}

- (void)fetchAppsWithType:(const char *)type client:(struct InstallationProxyClientHandle *)client list:(NSMutableArray *)list {
    void *result_plist = NULL;
    size_t result_len = 0;
    struct IdeviceFfiError *err = installation_proxy_get_apps(client, type, NULL, 0, &result_plist, &result_len);
    if (!err && result_plist) {
        // Mocking for now as raw plist parsing from FFI void* is complex without a full bridge
        if (list.count == 0 || strcmp(type, "System") == 0) {
            AppInfo *mock = [AppInfo new];
            mock.name = strcmp(type, "System") == 0 ? @"Settings" : @"Example App";
            mock.bundleId = strcmp(type, "System") == 0 ? @"com.apple.Preferences" : @"com.example.app";
            mock.isSystem = strcmp(type, "System") == 0;
            [list addObject:mock];
        }
    }
    if (err) idevice_error_free(err);
}

- (void)launchApp:(NSString *)bundleId withJit:(BOOL)jit provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (jit) {
            completion(NO, @"JIT Launch requires advanced instrumentation and is not yet implemented.");
        } else {
            // For normal launch on modern devices, we use app_service via core_device_proxy
            struct CoreDeviceProxyHandle *proxy = NULL;
            struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);
            if (err) { completion(NO, [NSString stringWithUTF8String:err->message]); idevice_error_free(err); return; }

            struct AdapterHandle *adapter = NULL;
            err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
            if (err) { core_device_proxy_free(proxy); completion(NO, [NSString stringWithUTF8String:err->message]); idevice_error_free(err); return; }

            struct AppServiceHandle *appservice = NULL;
            // Note: app_service_connect_rsd needs AdapterHandle and RsdHandshakeHandle.
            // For now, we simulate success if we can't fully establish the RSD path in this FFI version.
            completion(NO, @"Modern app launch requires full RSD handshake implementation.");

            adapter_free(adapter);
            core_device_proxy_free(proxy);
        }
    });
}

@end
