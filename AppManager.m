#import "AppManager.h"
#import <UIKit/UIKit.h>
#import "HeartbeatManager.h"

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
    NSString *bid = [bundleId copy];

    void (^safeCompletion)(BOOL, NSString *) = ^(BOOL success, NSString *msg) {
        [[HeartbeatManager sharedManager] resumeHeartbeat];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, msg);
            });
        }
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [[HeartbeatManager sharedManager] pauseHeartbeat];
        [NSThread sleepForTimeInterval:0.2];

        // 1. Warm-up
        struct LockdowndClientHandle *warmup = NULL;
        struct IdeviceFfiError *warmup_err = lockdownd_connect(provider, &warmup);
        if (!warmup_err) {
            plist_t udid = NULL;
            lockdownd_get_value(warmup, "UniqueDeviceID", NULL, &udid);
            if (udid) plist_free(udid);
            lockdownd_client_free(warmup);
        } else {
            NSLog(@"[Launch] Warmup error: %s", warmup_err->message);
            idevice_error_free(warmup_err);
        }

        // 2. Fresh CoreDeviceProxy with retries
        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = NULL;
        int max_retries = 8;
        NSTimeInterval delay = 1.0;

        for (int i = 0; i < max_retries; i++) {
            if (i > 0) {
                NSLog(@"[Launch] Tunnel attempt %d failed: %s. Retrying in %.1f s...", i, err->message, delay);
                idevice_error_free(err);
                [NSThread sleepForTimeInterval:delay];
                delay *= 1.5;
            }
            err = core_device_proxy_connect(provider, &proxy);
            if (!err) break;
        }

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Tunnel Error: %s", err->message]);
            idevice_error_free(err);
            return;
        }

        // 3. RSD Port
        uint16_t rsd_port = 0;
        err = core_device_proxy_get_server_rsd_port(proxy, &rsd_port);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"RSD Error: %s", err->message]);
            idevice_error_free(err);
            core_device_proxy_free(proxy);
            return;
        }

        // 4. Adapter (CONSUMES proxy)
        struct AdapterHandle *adapter = NULL;
        err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Adapter Error: %s", err->message]);
            idevice_error_free(err);
            return;
        }
        proxy = NULL;

        // 5. RSD Stream
        struct ReadWriteOpaque *rsd_stream = NULL;
        err = adapter_connect(adapter, rsd_port, &rsd_stream);
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
        rsd_stream = NULL;

        // 7. Bind RemoteServer
        struct RemoteServerHandle *remoteserver = NULL;
        err = remote_server_connect_rsd(adapter, handshake, &remoteserver);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"RemoteServer Error: %s", err->message]);
            idevice_error_free(err);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            return;
        }

        // 8. Bind ProcessControl
        struct ProcessControlHandle *proc_control = NULL;
        err = process_control_new(remoteserver, &proc_control);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"ProcessControl Error: %s", err->message]);
            idevice_error_free(err);
            remote_server_free(remoteserver);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            return;
        }

        // 9. Execute Launch with optional JIT setup
        uint64_t pid = 0;
        const char *const env[] = { "DEBUG_AUTOMATION_SCRIPTS=1", NULL };

        err = process_control_launch_app(proc_control, [bid UTF8String], jit ? env : NULL, jit ? 1 : 0, NULL, 0, NO, YES, &pid);

        if (!err && jit && pid > 0) {
            // Optional: memory limit adjustment for JIT stability
            process_control_disable_memory_limit(proc_control, pid);
        }

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Launch Error: %s", err->message]);
            idevice_error_free(err);
        } else {
            safeCompletion(YES, [NSString stringWithFormat:@"Target launched successfully (PID: %llu).", pid]);
        }

        process_control_free(proc_control);
        remote_server_free(remoteserver);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
    });
}

@end
