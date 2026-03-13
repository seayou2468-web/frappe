import sys

with open("AppManager.m", "r") as f:
    lines = f.readlines()

# Find start of fetchProfiles
start = -1
for i, line in enumerate(lines):
    if "- (void)fetchProfilesWithProvider:" in line:
        start = i
        break

# Find last @end
end = -1
for i in range(len(lines)-1, -1, -1):
    if lines[i].strip() == "@end":
        end = i
        break

if start != -1 and end != -1:
    new_methods = """
- (void)fetchProfilesWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<ProfileInfo *> *profiles, NSString *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(NSArray *, NSString *) = ^(NSArray *p, NSString *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(p, e); });
        };

        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = core_device_proxy_connect(provider, &proxy);
        if (!err && proxy) {
            uint16_t rsdPort = 0;
            core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
            struct AdapterHandle *adapter = NULL;
            core_device_proxy_create_tcp_adapter(proxy, &adapter);
            struct ReadWriteOpaque *rsdStream = NULL;
            adapter_connect(adapter, rsdPort, &rsdStream);

            struct McInstallCoreDeviceClientHandle *mcCore = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_core_device_client_new_from_stream(rsdStream, &mcCore);
            if (mcErr) {
                idevice_error_free(mcErr); adapter_free(adapter);
                safeCompletion(nil, @"Modern MCInstall connection failed."); return;
            }

            plist_t profilesPlist = NULL;
            struct IdeviceFfiError *listErr = mcinstall_core_device_get_profile_list(mcCore, &profilesPlist);
            if (listErr) {
                NSString *msg = [NSString stringWithFormat:@"Modern List Error: %s", listErr->message];
                idevice_error_free(listErr); mcinstall_core_device_client_free(mcCore); adapter_free(adapter);
                safeCompletion(nil, msg); return;
            }

            NSArray *result = [self parseProfilesPlist:profilesPlist];
            plist_free(profilesPlist);
            mcinstall_core_device_client_free(mcCore);
            adapter_free(adapter);
            safeCompletion(result, nil);
        } else {
            if (err) idevice_error_free(err);
            if (proxy) core_device_proxy_free(proxy);

            struct McInstallClientHandle *mc = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_connect(provider, &mc);
            if (mcErr) {
                safeCompletion(nil, [NSString stringWithFormat:@"Legacy Connection Error: %s", mcErr->message]);
                idevice_error_free(mcErr); return;
            }

            plist_t profilesPlist = NULL;
            struct IdeviceFfiError *listErr = mcinstall_get_profile_list(mc, &profilesPlist);
            if (listErr) {
                safeCompletion(nil, [NSString stringWithFormat:@"Legacy List Error: %s", listErr->message]);
                idevice_error_free(listErr); mcinstall_client_free(mc); return;
            }

            NSArray *result = [self parseProfilesPlist:profilesPlist];
            plist_free(profilesPlist);
            mcinstall_client_free(mc);
            safeCompletion(result, nil);
        }
    });
}

- (NSArray<ProfileInfo *> *)parseProfilesPlist:(plist_t)plist {
    if (!plist) return @[];
    plist_t arrayNode = plist;
    if (plist_get_node_type(plist) == PLIST_DICT) {
        arrayNode = plist_dict_get_item(plist, "ProfileList");
        if (!arrayNode || plist_get_node_type(arrayNode) != PLIST_ARRAY) {
             arrayNode = plist_dict_get_item(plist, "OrderedIdentifiers");
        }
    }
    if (!arrayNode || plist_get_node_type(arrayNode) != PLIST_ARRAY) {
        if (plist_get_node_type(plist) == PLIST_ARRAY) arrayNode = plist;
        else return @[];
    }

    uint32_t size = plist_array_get_size(arrayNode);
    NSMutableArray *profiles = [NSMutableArray arrayWithCapacity:size];
    for (uint32_t i = 0; i < size; i++) {
        plist_t item = plist_array_get_item(arrayNode, i);
        if (plist_get_node_type(item) != PLIST_DICT) continue;

        ProfileInfo *info = [[ProfileInfo alloc] init];

        plist_t val = plist_dict_get_item(item, "PayloadDisplayName");
        if (val) { char *s = NULL; plist_get_string_val(val, &s); if (s) { info.displayName = [NSString stringWithUTF8String:s]; free(s); } }

        val = plist_dict_get_item(item, "PayloadIdentifier");
        if (val) { char *s = NULL; plist_get_string_val(val, &s); if (s) { info.identifier = [NSString stringWithUTF8String:s]; free(s); } }

        val = plist_dict_get_item(item, "PayloadOrganization");
        if (val) { char *s = NULL; plist_get_string_val(val, &s); if (s) { info.organization = [NSString stringWithUTF8String:s]; free(s); } }

        val = plist_dict_get_item(item, "PayloadDescription");
        if (val) { char *s = NULL; plist_get_string_val(val, &s); if (s) { info.profileDescription = [NSString stringWithUTF8String:s]; free(s); } }

        val = plist_dict_get_item(item, "IsEncrypted");
        if (val) { uint8_t b = 0; plist_get_bool_val(val, &b); info.isEncrypted = (b != 0); }

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
        if (!err && proxy) {
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
                NSString *msg = [NSString stringWithFormat:@"Modern Install Error: %s", instErr->message];
                idevice_error_free(instErr); mcinstall_core_device_client_free(mcCore); adapter_free(adapter);
                safeCompletion(NO, msg); return;
            }
            mcinstall_core_device_client_free(mcCore); adapter_free(adapter);
            safeCompletion(YES, @"Profile installed (Modern).");
        } else {
            if (err) idevice_error_free(err);
            if (proxy) core_device_proxy_free(proxy);

            struct McInstallClientHandle *mc = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_connect(provider, &mc);
            if (mcErr) {
                safeCompletion(NO, [NSString stringWithFormat:@"Legacy Connection Error: %s", mcErr->message]);
                idevice_error_free(mcErr); return;
            }

            struct IdeviceFfiError *instErr = mcinstall_install_profile(mc, [profileData bytes], [profileData length]);
            if (instErr) {
                safeCompletion(NO, [NSString stringWithFormat:@"Legacy Install Error: %s", instErr->message]);
                idevice_error_free(instErr); mcinstall_client_free(mc); return;
            }
            mcinstall_client_free(mc);
            safeCompletion(YES, @"Profile installed.");
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
        if (!err && proxy) {
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
                NSString *msg = [NSString stringWithFormat:@"Modern Remove Error: %s", remErr->message];
                idevice_error_free(remErr); mcinstall_core_device_client_free(mcCore); adapter_free(adapter);
                safeCompletion(NO, msg); return;
            }
            mcinstall_core_device_client_free(mcCore); adapter_free(adapter);
            safeCompletion(YES, @"Profile removed (Modern).");
        } else {
            if (err) idevice_error_free(err);
            if (proxy) core_device_proxy_free(proxy);

            struct McInstallClientHandle *mc = NULL;
            struct IdeviceFfiError *mcErr = mcinstall_connect(provider, &mc);
            if (mcErr) {
                safeCompletion(NO, [NSString stringWithFormat:@"Legacy Connection Error: %s", mcErr->message]);
                idevice_error_free(mcErr); return;
            }

            struct IdeviceFfiError *remErr = mcinstall_remove_profile(mc, cid);
            if (remErr) {
                safeCompletion(NO, [NSString stringWithFormat:@"Legacy Remove Error: %s", remErr->message]);
                idevice_error_free(remErr); mcinstall_client_free(mc); return;
            }
            mcinstall_client_free(mc);
            safeCompletion(YES, @"Profile removed.");
        }
    });
}
"""

    final_lines = lines[:start] + [new_methods] + lines[end:]
    with open("AppManager.m", "w") as f:
        f.writelines(final_lines)
