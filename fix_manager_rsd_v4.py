import re

with open('IdeviceManager.m', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if '- (void)getRsdServicesWithCompletion:' in line:
        skip = True
        new_lines.append(r"""- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct LockdowndClientHandle *lockdown = self.lockdownClient;
    NSString *ipStr = self.ipAddress;
    [_lock unlock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint16_t rsd_port = 0;
        bool ssl = false;
        struct IdeviceFfiError *err = lockdownd_start_service(lockdown, "com.apple.mobile.restored", &rsd_port, &ssl);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "RSDサービスの開始に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:6 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct TcpFeedObject *feeder = NULL;
        struct TcpEatObject *eater = NULL;
        struct AdapterHandle *adapter = NULL;
        err = idevice_tcp_stack_into_sync_objects("0.0.0.0", [ipStr UTF8String], &feeder, &eater, &adapter);
        if (err || !adapter) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "TCPスタックの初期化に失敗しました"] : @"TCPスタックの初期化に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:7 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct ReadWriteOpaque *stream = NULL;
        err = adapter_connect(adapter, rsd_port, &stream);
        if (err || !stream) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDストリームの接続に失敗しました"] : @"RSDストリーム de 接続に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:8 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct RsdHandshakeHandle *handshake = NULL;
        err = rsd_handshake_new(stream, &handshake);
        if (err || !handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDハンドシェイクに失敗しました"] : @"RSDハンドシェイクに失敗しました";
            if (err) idevice_error_free(err);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:9 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct CRsdServiceArray *rawServices = NULL;
        err = rsd_get_services(handshake, &rawServices);
        if (err || !rawServices) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDサービスの取得に失敗しました"] : @"RSDサービスの取得に失敗しました";
            if (err) idevice_error_free(err);
            rsd_handshake_free(handshake);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        NSMutableArray *results = [NSMutableArray array];
        for (size_t i = 0; i < rawServices->count; i++) {
            struct CRsdService *s = &rawServices->services[i];
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            if (s->name) dict[@"name"] = [NSString stringWithUTF8String:s->name];
            if (s->entitlement) dict[@"entitlement"] = [NSString stringWithUTF8String:s->entitlement];
            dict[@"port"] = @(s->port);
            [results addObject:dict];
        }

        rsd_free_services(rawServices);
        rsd_handshake_free(handshake);
        idevice_stream_free(stream);

        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(results, nil); });
    });
}
""")
    if skip:
        if line.startswith('}') and lines[lines.index(line)+1].startswith('- (void)dealloc'):
             skip = False
        continue
    new_lines.append(line)

with open('IdeviceManager.m', 'w') as f:
    f.writelines(new_lines)
