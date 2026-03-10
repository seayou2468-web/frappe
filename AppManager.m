#import "AppManager.h"
#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "HeartbeatManager.h"
#import "JITScripts.h"

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

        uint16_t rsd_port = 0;
        err = core_device_proxy_get_server_rsd_port(proxy, &rsd_port);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"RSD Error: %s", err->message]);
            idevice_error_free(err);
            core_device_proxy_free(proxy);
            return;
        }

        struct AdapterHandle *adapter = NULL;
        err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Adapter Error: %s", err->message]);
            idevice_error_free(err);
            return;
        }
        proxy = NULL;

        struct ReadWriteOpaque *rsd_stream = NULL;
        err = adapter_connect(adapter, rsd_port, &rsd_stream);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Stream Error: %s", err->message]);
            idevice_error_free(err);
            adapter_free(adapter);
            return;
        }

        struct RsdHandshakeHandle *handshake = NULL;
        err = rsd_handshake_new(rsd_stream, &handshake);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Handshake Error: %s", err->message]);
            idevice_error_free(err);
            adapter_free(adapter);
            return;
        }
        rsd_stream = NULL;

        struct RemoteServerHandle *remoteserver = NULL;
        err = remote_server_connect_rsd(adapter, handshake, &remoteserver);
        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"RemoteServer Error: %s", err->message]);
            idevice_error_free(err);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            return;
        }

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

        uint64_t pid = 0;
        NSMutableArray *envArray = [NSMutableArray array];
        if (jit) [envArray addObject:@"DEBUG_AUTOMATION_SCRIPTS=1"];

        const char **env = NULL;
        if (envArray.count > 0) {
            env = (const char **)malloc((envArray.count + 1) * sizeof(char *));
            for (NSUInteger i = 0; i < envArray.count; i++) env[i] = strdup([envArray[i] UTF8String]);
            env[envArray.count] = NULL;
        }

        err = process_control_launch_app(proc_control, [bid UTF8String], env, envArray.count, NULL, 0, NO, YES, &pid);

        if (env) {
            for (NSUInteger i = 0; i < envArray.count; i++) free((void *)env[i]);
            free(env);
        }

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Launch Error: %s", err->message]);
            idevice_error_free(err);
            process_control_free(proc_control);
            remote_server_free(remoteserver);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            return;
        }

        if (jit && pid > 0) {
            process_control_disable_memory_limit(proc_control, pid);
            [self activateUniversalJitSyncForPid:pid adapter:adapter handshake:handshake];
            safeCompletion(YES, [NSString stringWithFormat:@"Launched with Universal JIT (PID: %llu).", pid]);
        } else {
            safeCompletion(YES, [NSString stringWithFormat:@"Launched successfully (PID: %llu).", pid]);
        }

        process_control_free(proc_control);
        remote_server_free(remoteserver);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
    });
}

// 0 <= val <= 15
static char u8toHexChar(uint8_t val) {
    if(val < 10) return val + '0';
    else return val + 87;
}

static void calcAndWriteCheckSum(char* commandStart) {
    uint8_t sum = 0;
    char* cur = commandStart;
    for(; *cur != '#'; ++cur) sum += *cur;
    cur[1] = u8toHexChar((sum & 0xf0) >> 4);
    cur[2] = u8toHexChar(sum & 0xf);
}

static void writeAddress(char* writeStart, uint64_t addr) {
    writeStart[0] = u8toHexChar((addr & 0xf00000000) >> 32);
    writeStart[1] = u8toHexChar((addr & 0xf0000000) >> 28);
    writeStart[2] = u8toHexChar((addr & 0xf000000) >> 24);
    writeStart[3] = u8toHexChar((addr & 0xf00000) >> 20);
    writeStart[4] = u8toHexChar((addr & 0xf0000) >> 16);
    writeStart[5] = u8toHexChar((addr & 0xf000) >> 12);
    writeStart[6] = u8toHexChar((addr & 0xf00) >> 8);
    writeStart[7] = u8toHexChar((addr & 0xf0) >> 4);
    writeStart[8] = u8toHexChar((addr & 0xf));
}

- (void)activateUniversalJitSyncForPid:(uint64_t)pid adapter:(struct AdapterHandle *)adapter handshake:(struct RsdHandshakeHandle *)handshake {
    struct DebugProxyHandle *debug_proxy = NULL;
    struct IdeviceFfiError *err = debug_proxy_connect_rsd(adapter, handshake, &debug_proxy);
    if (err || !debug_proxy) {
        NSLog(@"[JIT] DebugProxy connect failed: %s", err ? err->message : "unknown");
        if (err) idevice_error_free(err);
        return;
    }

    JSContext *context = [[JSContext alloc] init];

    // Core Bridge Logic
    context[@"get_pid"] = ^uint64_t { return pid; };

    context[@"send_command"] = ^NSString *(NSString *cmdStr) {
        struct DebugserverCommandHandle *cmd = debugserver_command_new([cmdStr UTF8String], NULL, 0);
        char *resp_raw = NULL;
        struct IdeviceFfiError *e = debug_proxy_send_command(debug_proxy, cmd, &resp_raw);
        debugserver_command_free(cmd);
        if (e) {
            NSLog(@"[JIT Bridge] cmd '%@' failed: %s", cmdStr, e->message);
            idevice_error_free(e);
            return nil;
        }
        NSString *resp = resp_raw ? [NSString stringWithUTF8String:resp_raw] : nil;
        if (resp_raw) free(resp_raw);
        return resp;
    };

    // Script Import Logic
    context[@"import_script"] = ^(NSString *filename) {
        NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [docsDir stringByAppendingPathComponent:filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            path = [[NSBundle mainBundle] pathForResource:[filename stringByDeletingPathExtension] ofType:[filename pathExtension]];
        }

        NSError *e = nil;
        NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];
        if (content) {
            [JSContext currentContext].exception = nil;
            [[JSContext currentContext] evaluateScript:content];
            return @"OK";
        } else {
            return [NSString stringWithFormat:@"ERROR: %@", e.localizedDescription];
        }
    };

    context[@"prepare_memory_region"] = ^NSString *(uint64_t startAddr, uint64_t JITPagesSize) {
        uint32_t commandCount = (uint32_t)(JITPagesSize >> 14);
        uint32_t commandBufferSize = commandCount * 19;
        char* commandBuffer = malloc(commandBufferSize + 1);
        commandBuffer[commandBufferSize] = 0;

        uint64_t curAddr = startAddr;
        for(uint32_t i = 0; i < commandCount; i++) {
            char *cur = commandBuffer + i * 19;
            cur[0] = '$'; cur[1] = 'M';
            cur[11] = ','; cur[12] = '1'; cur[13] = ':';
            cur[14] = '6'; cur[15] = '9'; cur[16] = '#';
            writeAddress(cur + 2, curAddr);
            calcAndWriteCheckSum(cur + 1);
            curAddr += 16384;
        }

        for(uint32_t cur = 0; cur < commandCount; cur += 1024) {
            uint32_t toSend = (commandCount - cur > 1024) ? 1024 : (commandCount - cur);
            struct IdeviceFfiError *e = debug_proxy_send_raw(debug_proxy, (const uint8_t *)commandBuffer + cur * 19, toSend * 19);
            if (e) { idevice_error_free(e); free(commandBuffer); return @"ERROR_SEND"; }

            for(uint32_t j = 0; j < toSend; j++) {
                char *r = NULL;
                struct IdeviceFfiError *e2 = debug_proxy_read_response(debug_proxy, &r);
                if (r) free(r);
                if (e2) { idevice_error_free(e2); free(commandBuffer); return @"ERROR_READ"; }
            }
        }
        free(commandBuffer);
        return @"OK";
    };

    context[@"log"] = ^(NSString *msg) { NSLog(@"[JIT Script] %@", msg); };

    // Primary execution with embedded fallback
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *scriptPath = [docsDir stringByAppendingPathComponent:@"universal.js"];
    NSString *script = nil;

    if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil];
    }

    if (!script) {
        scriptPath = [[NSBundle mainBundle] pathForResource:@"universal" ofType:@"js"];
        if (scriptPath) script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil];
    }

    if (!script) {
        NSLog(@"[JIT] Using embedded universal script fallback.");
        script = kUniversalJitScript;
    }

    [context evaluateScript:script];
    debug_proxy_free(debug_proxy);
}

@end
