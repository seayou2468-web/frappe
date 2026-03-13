import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Implement the robust connection loop for fetchProfiles, install, and remove
# Memory says: Establishing CoreDeviceProxy tunnels over wireless on iOS 26.x requires a warm-up query, pausing HeartbeatManager (with a 0.5s sleep), and an 8-attempt retry loop with exponential backoff.

robust_connect_code = """        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = NULL;

        // Robust connection loop for iOS 17+ (CoreDevice)
        [[HeartbeatManager sharedManager] pause];
        [NSThread sleepForTimeInterval:0.5];

        NSTimeInterval delay = 1.0;
        for (int i = 0; i < 8; i++) {
            err = core_device_proxy_connect(provider, &proxy);
            if (!err) break;

            if (i < 7) {
                idevice_error_free(err);
                [NSThread sleepForTimeInterval:delay];
                delay *= 1.5;
            }
        }
        [[HeartbeatManager sharedManager] resume];

        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"CoreDevice Connection Error: %s", err->message]);
            idevice_error_free(err); return;
        }"""

# Replace in fetchProfiles (first occurrence after the completion block)
# I'll use a more precise replacement for fetchProfiles specifically

fetch_profiles_old_block = """        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);
        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"CoreDevice Connection Error: %s", err->message]);
            idevice_error_free(err); return;
        }"""

content = content.replace(fetch_profiles_old_block, robust_connect_code)

# For install and remove, we need a slightly different version (safeCompletion returns NO/message)
robust_connect_code_bool = robust_connect_code.replace("safeCompletion(nil,", "safeCompletion(NO,")

content = content.replace('        struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);\n        if (err) {\n            safeCompletion(NO, [NSString stringWithFormat:@"CoreDevice Connection Error: %s", err->message]);\n            idevice_error_free(err); return;\n        }', robust_connect_code_bool)

with open("AppManager.m", "w") as f:
    f.write(content)
