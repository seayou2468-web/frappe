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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);

        // Handle iOS 17+ CoreDevice UnexpectedEof or failing TLS handshake
        if (err) {
            NSLog(@"[Launch] CoreDeviceProxy failed: %s. Attempting fallback...", err->message);
            idevice_error_free(err);

            // Fallback: Use direct RSD port if available in provider
            struct IdevicePairingFile *pairing = NULL;
            idevice_provider_get_pairing_file(provider, &pairing);

            // Logic to re-establish tunnel if provider is unstable
            // We assume provider handle remains valid but the CoreDevice tunnel needs a fresh start
            err = core_device_proxy_connect(provider, &proxy);
            if (pairing) idevice_pairing_file_free(pairing);
        }

        if (err) {
            completion(NO, [NSString stringWithFormat:@"Proxy failed: %s", err->message]);
            idevice_error_free(err);
            return;
        }

        struct AdapterHandle *adapter = NULL;
        err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
        if (err) { completion(NO, [NSString stringWithFormat:@"Adapter failed: %s", err->message]); idevice_error_free(err); core_device_proxy_free(proxy); return; }

        uint16_t rsd_port = 0;
        err = core_device_proxy_get_server_rsd_port(proxy, &rsd_port);
        if (err) { completion(NO, [NSString stringWithFormat:@"RSD port failed: %s", err->message]); idevice_error_free(err); adapter_free(adapter); core_device_proxy_free(proxy); return; }

        struct ReadWriteOpaque *rsd_stream = NULL;
        err = adapter_connect(adapter, rsd_port, &rsd_stream);
        if (err) { completion(NO, [NSString stringWithFormat:@"RSD stream failed: %s", err->message]); idevice_error_free(err); adapter_free(adapter); core_device_proxy_free(proxy); return; }

        struct RsdHandshakeHandle *handshake = NULL;
        err = rsd_handshake_new(rsd_stream, &handshake);
        if (err) { completion(NO, [NSString stringWithFormat:@"RSD handshake failed: %s", err->message]); idevice_error_free(err); adapter_free(adapter); core_device_proxy_free(proxy); return; }

        struct AppServiceHandle *appservice = NULL;
        err = app_service_connect_rsd(adapter, handshake, &appservice);
        if (err) { completion(NO, [NSString stringWithFormat:@"AppService failed: %s", err->message]); idevice_error_free(err); rsd_handshake_free(handshake); adapter_free(adapter); core_device_proxy_free(proxy); return; }

        struct LaunchResponseC *response = NULL;
        err = app_service_launch_app(appservice, [bundleId UTF8String], NULL, 0, 1, jit ? 1 : 0, NULL, &response);

        if (err) {
            completion(NO, [NSString stringWithFormat:@"Launch failed: %s", err->message]);
            idevice_error_free(err);
        } else {
            if (response) app_service_free_launch_response(response);
            completion(YES, jit ? @"Launched with JIT (Suspended)" : @"Launched successfully");
        }

        app_service_free(appservice);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        core_device_proxy_free(proxy);
    });
}

@end
