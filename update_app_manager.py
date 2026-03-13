import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Replace the mcinstall connection logic with something simpler and more reliable like installation_proxy_connect
# mcinstall_connect seems to handle CoreDevice internally if possible according to its signature in idevice.h
# but we need to check if there is a core_device specific one that is better.

fetch_profiles_old = """- (void)fetchProfilesWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<ProfileInfo *> *profiles, NSString *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(NSArray *, NSString *) = ^(NSArray *p, NSString *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(p, e); });
        };

        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);
        if (err) {
            // Fallback to legacy
            struct McInstallClientHandle *mc = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_connect(provider, &mc);
            if (mcErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to connect to MCInstall: %s", mcErr->message];
                idevice_error_free(mcErr); idevice_error_free(err);
                safeCompletion(nil, msg); return;
            }
            idevice_error_free(err);

            plist_t profilesPlist = NULL;
            struct IdeviceFfiError *listErr = mcinstall_get_profile_list(mc, &profilesPlist);
            if (listErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to get profile list: %s", listErr->message];
                idevice_error_free(listErr); mcinstall_client_free(mc);
                safeCompletion(nil, msg); return;
            }

            NSArray *result = [self parseProfilesPlist:profilesPlist];
            plist_free(profilesPlist);
            mcinstall_client_free(mc);
            safeCompletion(result, nil);
        } else {
            // iOS 17+ path
            uint16_t rsdPort = 0;
            struct IdeviceFfiError *portErr = core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
            if (portErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to get RSD port: %s", portErr->message];
                idevice_error_free(portErr); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }

            struct AdapterHandle *adapter = NULL;
            struct IdeviceFfiError *adapterErr = core_device_proxy_create_tcp_adapter(proxy, &adapter);
            if (adapterErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to create adapter: %s", adapterErr->message];
                idevice_error_free(adapterErr); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }
            struct ReadWriteOpaque *rsdStream = NULL;
            struct IdeviceFfiError *streamErr = adapter_connect(adapter, rsdPort, &rsdStream);
            if (streamErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to connect to RSD stream: %s", streamErr->message];
                idevice_error_free(streamErr); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }

            struct McInstallCoreDeviceClientHandle *mcCore = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_core_device_client_new_from_stream(rsdStream, &mcCore);
            if (mcErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to create MCInstall CoreDevice client: %s", mcErr->message];
                idevice_error_free(mcErr); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }

            plist_t profilesPlist = NULL;
            struct IdeviceFfiError *listErr = mcinstall_core_device_get_profile_list(mcCore, &profilesPlist);
            if (listErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to get profile list (CoreDevice): %s", listErr->message];
                idevice_error_free(listErr); mcinstall_core_device_client_free(mcCore); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }

            NSArray *result = [self parseProfilesPlist:profilesPlist];
            plist_free(profilesPlist);
            mcinstall_core_device_client_free(mcCore);
            core_device_proxy_free(proxy);
            safeCompletion(result, nil);
        }
    });
}"""

fetch_profiles_new = """- (void)fetchProfilesWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<ProfileInfo *> *profiles, NSString *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(NSArray *, NSString *) = ^(NSArray *p, NSString *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(p, e); });
        };

        struct McInstallClientHandle *mc = NULL;
        struct IdeviceFfiError *err = mcinstall_connect(provider, &mc);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Failed to connect to MCInstall: %s", err->message];
            idevice_error_free(err);
            safeCompletion(nil, msg); return;
        }

        plist_t profilesPlist = NULL;
        struct IdeviceFfiError *listErr = mcinstall_get_profile_list(mc, &profilesPlist);
        if (listErr) {
            NSString *msg = [NSString stringWithFormat:@"Failed to get profile list: %s", listErr->message];
            idevice_error_free(listErr); mcinstall_client_free(mc);
            safeCompletion(nil, msg); return;
        }

        NSArray *result = [self parseProfilesPlist:profilesPlist];
        plist_free(profilesPlist);
        mcinstall_client_free(mc);
        safeCompletion(result, nil);
    });
}"""

# Actually, if mcinstall_connect doesn't work for iOS 17+, we SHOULD use the CoreDevice path but it might be stuck because of how we handle the provider/proxy.
# Let's check how other things (like launchApp) handle it.
# Wait, I found something in the memory:
# "JIT activation on iOS 17+ (CoreDevice) requires launching the app through the ProcessControl service via RemoteServer with DEBUG_AUTOMATION_SCRIPTS=1, followed by attaching via DebugProxy service using vAttach and vCont;c commands."
# But that's for JIT.

# Let's try to use mcinstall_connect first as it's the "newer" way to connect according to idevice.h (auto-detecting provider type).

content = content.replace(fetch_profiles_old, fetch_profiles_new)

# Update install and remove too to use mcinstall_connect
install_old = """- (void)installProfileData:(NSData *)profileData provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(BOOL, NSString *) = ^(BOOL s, NSString *m) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(s, m); });
        };

        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);
        if (err) {
            struct McInstallClientHandle *mc = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_connect(provider, &mc);
            if (mcErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to connect to MCInstall: %s", mcErr->message];
                idevice_error_free(mcErr); idevice_error_free(err);
                safeCompletion(NO, msg); return;
            }
            idevice_error_free(err);
            struct IdeviceFfiError *instErr = mcinstall_install_profile(mc, [profileData bytes], [profileData length]);
            if (instErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to install profile: %s", instErr->message];
                idevice_error_free(instErr); mcinstall_client_free(mc);
                safeCompletion(NO, msg); return;
            }
            mcinstall_client_free(mc);
            safeCompletion(YES, @"Profile installed successfully.");
        } else {
            uint16_t rsdPort = 0;
            core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
            struct AdapterHandle *adapter = NULL;
            core_device_proxy_create_tcp_adapter(proxy, &adapter);
            struct ReadWriteOpaque *rsdStream = NULL;
            adapter_connect(adapter, rsdPort, &rsdStream);
            struct McInstallCoreDeviceClientHandle *mcCore = NULL;
            mcinstall_core_device_client_new_from_stream(rsdStream, &mcCore);

            struct IdeviceFfiError *instErr = mcinstall_core_device_install_profile(mcCore, [profileData bytes], [profileData length]);
            if (instErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to install profile (CoreDevice): %s", instErr->message];
                idevice_error_free(instErr); mcinstall_core_device_client_free(mcCore); core_device_proxy_free(proxy);
                safeCompletion(NO, msg); return;
            }
            mcinstall_core_device_client_free(mcCore); core_device_proxy_free(proxy);
            safeCompletion(YES, @"Profile installed successfully (CoreDevice).");
        }
    });
}"""

install_new = """- (void)installProfileData:(NSData *)profileData provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(BOOL, NSString *) = ^(BOOL s, NSString *m) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(s, m); });
        };

        struct McInstallClientHandle *mc = NULL;
        struct IdeviceFfiError *err = mcinstall_connect(provider, &mc);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Failed to connect to MCInstall: %s", err->message];
            idevice_error_free(err);
            safeCompletion(NO, msg); return;
        }

        struct IdeviceFfiError *instErr = mcinstall_install_profile(mc, [profileData bytes], [profileData length]);
        if (instErr) {
            NSString *msg = [NSString stringWithFormat:@"Failed to install profile: %s", instErr->message];
            idevice_error_free(instErr); mcinstall_client_free(mc);
            safeCompletion(NO, msg); return;
        }
        mcinstall_client_free(mc);
        safeCompletion(YES, @"Profile installed successfully.");
    });
}"""

content = content.replace(install_old, install_new)

remove_old = """- (void)removeProfileWithIdentifier:(NSString *)identifier provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(BOOL, NSString *) = ^(BOOL s, NSString *m) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(s, m); });
        };

        const char *cid = [identifier UTF8String];
        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);
        if (err) {
            struct McInstallClientHandle *mc = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_connect(provider, &mc);
            if (mcErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to connect to MCInstall: %s", mcErr->message];
                idevice_error_free(mcErr); idevice_error_free(err);
                safeCompletion(NO, msg); return;
            }
            idevice_error_free(err);
            struct IdeviceFfiError *remErr = mcinstall_remove_profile(mc, cid);
            if (remErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to remove profile: %s", remErr->message];
                idevice_error_free(remErr); mcinstall_client_free(mc);
                safeCompletion(NO, msg); return;
            }
            mcinstall_client_free(mc);
            safeCompletion(YES, @"Profile removed successfully.");
        } else {
            uint16_t rsdPort = 0;
            core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
            struct AdapterHandle *adapter = NULL;
            core_device_proxy_create_tcp_adapter(proxy, &adapter);
            struct ReadWriteOpaque *rsdStream = NULL;
            adapter_connect(adapter, rsdPort, &rsdStream);
            struct McInstallCoreDeviceClientHandle *mcCore = NULL;
            mcinstall_core_device_client_new_from_stream(rsdStream, &mcCore);

            struct IdeviceFfiError *remErr = mcinstall_core_device_remove_profile(mcCore, cid);
            if (remErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to remove profile (CoreDevice): %s", remErr->message];
                idevice_error_free(remErr); mcinstall_core_device_client_free(mcCore); core_device_proxy_free(proxy);
                safeCompletion(NO, msg); return;
            }
            mcinstall_core_device_client_free(mcCore); core_device_proxy_free(proxy);
            safeCompletion(YES, @"Profile removed successfully (CoreDevice).");
        }
    });
}"""

remove_new = """- (void)removeProfileWithIdentifier:(NSString *)identifier provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(BOOL, NSString *) = ^(BOOL s, NSString *m) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(s, m); });
        };

        const char *cid = [identifier UTF8String];
        struct McInstallClientHandle *mc = NULL;
        struct IdeviceFfiError *err = mcinstall_connect(provider, &mc);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Failed to connect to MCInstall: %s", err->message];
            idevice_error_free(err);
            safeCompletion(NO, msg); return;
        }

        struct IdeviceFfiError *remErr = mcinstall_remove_profile(mc, cid);
        if (remErr) {
            NSString *msg = [NSString stringWithFormat:@"Failed to remove profile: %s", remErr->message];
            idevice_error_free(remErr); mcinstall_client_free(mc);
            safeCompletion(NO, msg); return;
        }
        mcinstall_client_free(mc);
        safeCompletion(YES, @"Profile removed successfully.");
    });
}"""

content = content.replace(remove_old, remove_new)

with open("AppManager.m", "w") as f:
    f.write(content)
