import sys

with open("AppManager.m", "r") as f:
    lines = f.readlines()

new_lines = []
inserted = False

# We will insert the new classes and implementation at the end before the last @end
# But first we need the ProfileInfo implementation

profile_info_impl = """
@implementation ProfileInfo
@end

"""

app_manager_methods = """
- (void)fetchProfilesWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<ProfileInfo *> *profiles, NSString *error))completion {
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
            idevice_plist_free(profilesPlist);
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

            struct ReadWriteOpaque *rsdStream = NULL;
            struct IdeviceFfiError *streamErr = core_device_proxy_connect_tcp_stream(proxy, rsdPort, &rsdStream);
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
            idevice_plist_free(profilesPlist);
            mcinstall_core_device_client_free(mcCore);
            core_device_proxy_free(proxy);
            safeCompletion(result, nil);
        }
    });
}

- (NSArray<ProfileInfo *> *)parseProfilesPlist:(plist_t)plist {
    if (!plist || idevice_plist_get_node_type(plist) != PLIST_ARRAY) return @[];
    uint32_t size = idevice_plist_array_get_size(plist);
    NSMutableArray *profiles = [NSMutableArray arrayWithCapacity:size];
    for (uint32_t i = 0; i < size; i++) {
        plist_t item = idevice_plist_array_get_item(plist, i);
        if (idevice_plist_get_node_type(item) != PLIST_DICT) continue;

        ProfileInfo *info = [[ProfileInfo alloc] init];

        plist_t val = idevice_plist_dict_get_item(item, "PayloadDisplayName");
        if (val) { char *s = NULL; idevice_plist_get_string_val(val, &s); if (s) { info.displayName = [NSString stringWithUTF8String:s]; free(s); } }

        val = idevice_plist_dict_get_item(item, "PayloadIdentifier");
        if (val) { char *s = NULL; idevice_plist_get_string_val(val, &s); if (s) { info.identifier = [NSString stringWithUTF8String:s]; free(s); } }

        val = idevice_plist_dict_get_item(item, "PayloadOrganization");
        if (val) { char *s = NULL; idevice_plist_get_string_val(val, &s); if (s) { info.organization = [NSString stringWithUTF8String:s]; free(s); } }

        val = idevice_plist_dict_get_item(item, "PayloadDescription");
        if (val) { char *s = NULL; idevice_plist_get_string_val(val, &s); if (s) { info.profileDescription = [NSString stringWithUTF8String:s]; free(s); } }

        val = idevice_plist_dict_get_item(item, "IsEncrypted");
        if (val) { uint8_t b = 0; idevice_plist_get_bool_val(val, &b); info.isEncrypted = (b != 0); }

        [profiles addObject:info];
    }
    return profiles;
}

- (void)installProfileData:(NSData *)profileData provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
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
            struct ReadWriteOpaque *rsdStream = NULL;
            core_device_proxy_connect_tcp_stream(proxy, rsdPort, &rsdStream);
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
}

- (void)removeProfileWithIdentifier:(NSString *)identifier provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
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
            struct ReadWriteOpaque *rsdStream = NULL;
            core_device_proxy_connect_tcp_stream(proxy, rsdPort, &rsdStream);
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
}
"""

# Insert ProfileInfo implementation at the top (after imports)
for i in range(len(lines)):
    if lines[i].startswith("@implementation AppInfo"):
        lines.insert(i, profile_info_impl)
        break

# Find the last @end to insert methods
for i in range(len(lines)-1, -1, -1):
    if lines[i].strip() == "@end":
        lines.insert(i, app_manager_methods)
        break

with open("AppManager.m", "w") as f:
    f.writelines(lines)
