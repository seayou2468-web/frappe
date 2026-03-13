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
        struct IdeviceFfiError *err = NULL;

        [[HeartbeatManager sharedManager] pauseHeartbeat];
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
        [[HeartbeatManager sharedManager] resumeHeartbeat];

        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"CoreDevice Connection Error: %s", err->message]);
            idevice_error_free(err); return;
        }

        uint16_t rsdPort = 0;
        err = core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"RSD Port Error: %s", err->message]);
            idevice_error_free(err); core_device_proxy_free(proxy); return;
        }

        struct AdapterHandle *adapter = NULL;
        err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"Adapter Error: %s", err->message]);
            idevice_error_free(err); return;
        }

        struct ReadWriteOpaque *rsdStream = NULL;
        err = adapter_connect(adapter, rsdPort, &rsdStream);
        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"Stream Error: %s", err->message]);
            idevice_error_free(err); adapter_free(adapter); return;
        }

        // RSD Handshake is required before service client creation
        struct RsdHandshakeHandle *handshake = NULL;
        err = rsd_handshake_new(rsdStream, &handshake);
        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"RSD Handshake Error: %s", err->message]);
            idevice_error_free(err); adapter_free(adapter); return;
        }

        struct McInstallCoreDeviceClientHandle *mcCore = NULL;
        err = mcinstall_core_device_client_new_from_stream(rsdStream, &mcCore);
        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"MCInstall CoreDevice Error: %s", err->message]);
            idevice_error_free(err); rsd_handshake_free(handshake); adapter_free(adapter); return;
        }

        plist_t profilesPlist = NULL;
        err = mcinstall_core_device_get_profile_list(mcCore, &profilesPlist);
        if (err) {
            safeCompletion(nil, [NSString stringWithFormat:@"Profile List Error: %s", err->message]);
            idevice_error_free(err); mcinstall_core_device_client_free(mcCore); rsd_handshake_free(handshake); adapter_free(adapter); return;
        }

        NSArray *result = [self parseProfilesPlist:profilesPlist];
        plist_free(profilesPlist);
        mcinstall_core_device_client_free(mcCore);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        safeCompletion(result, nil);
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
        struct IdeviceFfiError *err = NULL;

        [[HeartbeatManager sharedManager] pauseHeartbeat];
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
        [[HeartbeatManager sharedManager] resumeHeartbeat];

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"CoreDevice Connection Error: %s", err->message]);
            idevice_error_free(err); return;
        }

        uint16_t rsdPort = 0;
        core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
        struct AdapterHandle *adapter = NULL;
        core_device_proxy_create_tcp_adapter(proxy, &adapter);
        struct ReadWriteOpaque *rsdStream = NULL;
        adapter_connect(adapter, rsdPort, &rsdStream);

        struct RsdHandshakeHandle *handshake = NULL;
        rsd_handshake_new(rsdStream, &handshake);

        struct McInstallCoreDeviceClientHandle *mcCore = NULL;
        mcinstall_core_device_client_new_from_stream(rsdStream, &mcCore);

        struct IdeviceFfiError *instErr = mcinstall_core_device_install_profile(mcCore, [profileData bytes], [profileData length]);
        if (instErr) {
            NSString *msg = [NSString stringWithFormat:@"Install Error: %s", instErr->message];
            idevice_error_free(instErr); mcinstall_core_device_client_free(mcCore); rsd_handshake_free(handshake); adapter_free(adapter);
            safeCompletion(NO, msg); return;
        }
        mcinstall_core_device_client_free(mcCore); rsd_handshake_free(handshake); adapter_free(adapter);
        safeCompletion(YES, @"Profile installed successfully (RSD).");
    });
}

- (void)removeProfileWithIdentifier:(NSString *)identifier provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void (^safeCompletion)(BOOL, NSString *) = ^(BOOL s, NSString *m) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(s, m); });
        };

        const char *cid = [identifier UTF8String];
        struct CoreDeviceProxyHandle *proxy = NULL;
        struct IdeviceFfiError *err = NULL;

        [[HeartbeatManager sharedManager] pauseHeartbeat];
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
        [[HeartbeatManager sharedManager] resumeHeartbeat];

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"CoreDevice Connection Error: %s", err->message]);
            idevice_error_free(err); return;
        }

        uint16_t rsdPort = 0;
        core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
        struct AdapterHandle *adapter = NULL;
        core_device_proxy_create_tcp_adapter(proxy, &adapter);
        struct ReadWriteOpaque *rsdStream = NULL;
        adapter_connect(adapter, rsdPort, &rsdStream);

        struct RsdHandshakeHandle *handshake = NULL;
        rsd_handshake_new(rsdStream, &handshake);

        struct McInstallCoreDeviceClientHandle *mcCore = NULL;
        mcinstall_core_device_client_new_from_stream(rsdStream, &mcCore);

        struct IdeviceFfiError *remErr = mcinstall_core_device_remove_profile(mcCore, cid);
        if (remErr) {
            NSString *msg = [NSString stringWithFormat:@"Remove Error: %s", remErr->message];
            idevice_error_free(remErr); mcinstall_core_device_client_free(mcCore); rsd_handshake_free(handshake); adapter_free(adapter);
            safeCompletion(NO, msg); return;
        }
        mcinstall_core_device_client_free(mcCore); rsd_handshake_free(handshake); adapter_free(adapter);
        safeCompletion(YES, @"Profile removed successfully (RSD).");
    });
}
"""

    final_lines = lines[:start] + [new_methods] + lines[end:]
    with open("AppManager.m", "w") as f:
        f.writelines(final_lines)
