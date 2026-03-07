import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# Refine launchAppWithBundleId to return error instead of just starting service
launch_method = r"""- (void)launchAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider || !self.lockdownClient) {
        [_lock unlock];
        if (completion) completion([NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct LockdowndClientHandle *l = self.lockdownClient;
    [_lock unlock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint16_t service_port = 0;
        bool ssl = false;
        // Launching usually requires starting debugserver or similar,
        // for now we just verify we can start a service associated with app management
        struct IdeviceFfiError *err = lockdownd_start_service(l, "com.apple.mobile.installation_proxy", &service_port, &ssl);

        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "アプリ起動サービスの開始に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:4 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] Successfully verified service for launch attempt of %@", bundleId]];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}"""

content = re.sub(r'- \(void\)launchAppWithBundleId:.*?\}\n\}', launch_method, content, flags=re.DOTALL)

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
