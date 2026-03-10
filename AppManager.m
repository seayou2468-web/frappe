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
    plist_t options = plist_new_dict();
    plist_dict_set_item(options, "ApplicationType", plist_new_string(type));

    plist_t *result_array = NULL;
    size_t result_count = 0;
    struct IdeviceFfiError *err = installation_proxy_browse(client, options, &result_array, &result_count);

    if (!err && result_array) {
        for (size_t i = 0; i < result_count; i++) {
            plist_t item = result_array[i];
            if (!item) continue;

            AppInfo *info = [AppInfo new];
            info.isSystem = strcmp(type, "System") == 0;

            plist_t bid_node = plist_dict_get_item(item, "CFBundleIdentifier");
            if (bid_node) {
                char *val = NULL; plist_get_string_val(bid_node, &val);
                if (val) { info.bundleId = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
            }

            plist_t name_node = plist_dict_get_item(item, "CFBundleDisplayName");
            if (!name_node) name_node = plist_dict_get_item(item, "CFBundleName");
            if (name_node) {
                char *val = NULL; plist_get_string_val(name_node, &val);
                if (val) { info.name = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
            }

            if (info.bundleId) {
                if (!info.name) info.name = info.bundleId;
                [list addObject:info];
            }
        }
        idevice_plist_array_free(result_array, result_count);
    }

    if (err) {
        NSLog(@"[Apps] Browse error for %s: %s", type, err->message);
        idevice_error_free(err);
    }
    plist_free(options);
}

- (void)launchApp:(NSString *)bundleId withJit:(BOOL)jit provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    // 1. Immutable copy for block capture safety
    NSString *bundleIdFixed = [bundleId copy];

    // 2. Safe completion wrapper ensuring main-thread execution for UI-bound responses
    void (^safeCompletion)(BOOL, NSString *) = ^(BOOL success, NSString *msg) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, msg);
            });
        }
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // 1. Warm-up connection check
        struct LockdowndClientHandle *warmup = NULL;
        struct IdeviceFfiError *warmup_err = lockdownd_connect(provider, &warmup);
        if (!warmup_err) {
            lockdownd_client_free(warmup);
        } else {
            NSLog(@"[Launch] Warmup error: %s", warmup_err->message);
            idevice_error_free(warmup_err);
        }

        // 2. Fresh CoreDeviceProxy with retries
        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = NULL;
        int retries = 5;
        for (int i = 0; i < retries; i++) {
            if (i > 0) [NSThread sleepForTimeInterval:0.5 + (i * 0.2)];
            err = core_device_proxy_connect(provider, &proxy);
            if (!err) break;
            if (i < retries - 1) idevice_error_free(err);
        }

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Tunnel Error: %s", err->message]);
            idevice_error_free(err);
            return;
        }

        // 3. Negotiate RSD port BEFORE consuming proxy
        uint16_t port = 0;
        err = core_device_proxy_get_server_rsd_port(proxy, &port);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"RSD Port Error: %s", err->message]);
            idevice_error_free(err);
            core_device_proxy_free(proxy);
            return;
        }

        // 4. Create Adapter (CONSUMES proxy)
        struct AdapterHandle *adapter = NULL;
        err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Adapter Error: %s", err->message]);
            idevice_error_free(err);
            return;
        }
        proxy = NULL; // Do not use or free proxy again

        // 5. Connect to RSD stream via adapter
        struct ReadWriteOpaque *rsd_stream = NULL;
        err = adapter_connect(adapter, port, &rsd_stream);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Stream Error: %s", err->message]);
            idevice_error_free(err);
            adapter_free(adapter);
            return;
        }

        // 6. RSD Handshake (CONSUMES rsd_stream)
        struct RsdHandshakeHandle *handshake = NULL;
        err = rsd_handshake_new(rsd_stream, &handshake);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Handshake Error: %s", err->message]);
            idevice_error_free(err);
            adapter_free(adapter);
            return;
        }
        rsd_stream = NULL; // Do not use or free stream again

        // 7. Bind AppService
        struct AppServiceHandle *app_service = NULL;
        err = app_service_connect_rsd(adapter, handshake, &app_service);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Service Error: %s", err->message]);
            idevice_error_free(err);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            return;
        }

        // 8. Launch App
        struct LaunchResponseC *resp = NULL;
        err = app_service_launch_app(app_service, [bundleIdFixed UTF8String], NULL, 0, 1, jit ? 1 : 0, NULL, &resp);

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Launch Error: %s", err->message]);
            idevice_error_free(err);
        } else {
            if (resp) app_service_free_launch_response(resp);
            safeCompletion(YES, @"Target launched successfully.");
        }

        // Final Cleanup
        app_service_free(app_service);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
    });
}

@end
