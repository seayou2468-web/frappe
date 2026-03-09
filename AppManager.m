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
        [self fetchAppsWithType:"User" client:instproxy list:allApps];
        [self fetchAppsWithType:"System" client:instproxy list:allApps];

        installation_proxy_client_free(instproxy);
        completion(allApps, nil);
    });
}

- (void)fetchAppsWithType:(const char *)type client:(struct InstallationProxyClientHandle *)client list:(NSMutableArray *)list {
    void *result_data = NULL;
    size_t result_len = 0;
    struct IdeviceFfiError *err = installation_proxy_get_apps(client, type, NULL, 0, &result_data, &result_len);
    if (!err && result_data) {
        plist_t root = NULL;
        // Parse the binary plist data returned by installation_proxy
        plist_from_memory((const char *)result_data, (uint32_t)result_len, &root, NULL);

        if (root && plist_get_node_type(root) == PLIST_ARRAY) {
            uint32_t size = plist_array_get_size(root);
            for (uint32_t i = 0; i < size; i++) {
                plist_t item = plist_array_get_item(root, i);
                if (!item) continue;
                AppInfo *info = [AppInfo new];
                info.isSystem = strcmp(type, "System") == 0;

                plist_t name_node = plist_dict_get_item(item, "CFBundleDisplayName");
                if (!name_node) name_node = plist_dict_get_item(item, "CFBundleName");
                if (name_node) {
                    char *val = NULL; plist_get_string_val(name_node, &val);
                    if (val) { info.name = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
                }

                plist_t bid_node = plist_dict_get_item(item, "CFBundleIdentifier");
                if (bid_node) {
                    char *val = NULL; plist_get_string_val(bid_node, &val);
                    if (val) { info.bundleId = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
                }

                if (info.bundleId) {
                    if (!info.name) info.name = info.bundleId;
                    [list addObject:info];
                }
            }
        }
        if (root) plist_free(root);
        idevice_data_free(result_data, result_len);
    } else if (err) {
        idevice_error_free(err);
    }
}

- (void)launchApp:(NSString *)bundleId withJit:(BOOL)jit provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // App launching requires app_service which is usually discoverable via RSD
        // For simplicity in this FFI version, we report current support status
        completion(NO, @"Launch functionality (Normal/JIT) requires further service discovery integration.");
    });
}

@end
