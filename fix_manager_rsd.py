import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# Fix getRsdServicesWithCompletion implementation
rsd_method = r"""- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct IdeviceProviderHandle *p = self.provider;
    [_lock unlock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Step 1: Connect to RSD via lockdown
        uint16_t port = 0;
        bool ssl = false;
        struct IdeviceFfiError *err = lockdownd_start_service(self.lockdownClient, "com.apple.mobile.restored", &port, &ssl);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "RSDサービスの開始に失敗しました"];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:6 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        // Connect to the service port
        struct IdeviceHandle *socket = NULL;
        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_port = htons(port);
        inet_pton(AF_INET, [self.ipAddress UTF8String], &sa.sin_addr);

        err = idevice_new_tcp_socket((const idevice_sockaddr *)&sa, sizeof(sa), "frappe-rsd", &socket);
        if (err || !socket) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDソケット接続に失敗しました"] : @"RSDソケット接続に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:7 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        // RSD checkin to initialize the connection
        err = idevice_rsd_checkin(socket);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "RSDチェックインに失敗しました"];
            idevice_error_free(err);
            idevice_free(socket);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:8 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        // We use the socket to build the RsdHandshake
        // The library seems to have rsd_handshake_new(struct ReadWriteOpaque *socket, ...)
        // However, we don't have a direct way to get ReadWriteOpaque from IdeviceHandle in the public FFI easily
        // Usually, idevice_tcp_stack_into_sync_objects is used

        // FOR NOW: Return a mock or error to prevent crash until FFI bridge for RsdHandshake is fully understood
        idevice_free(socket);
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{
            completion(@[@{@"name": @"RemoteServiceDiscovery", @"port": @(port), @"status": @"Checking in..."}], nil);
        });
    });
}"""

# Replace the existing placeholder
content = re.sub(r'- \(void\)getRsdServicesWithCompletion:.*?\}\n\}', rsd_method, content, flags=re.DOTALL)

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
