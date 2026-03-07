import re

with open('IdeviceManager.h', 'r') as f:
    h_content = f.read()

if 'getProcessListWithCompletion' not in h_content:
    h_content = h_content.replace('// RSD Support',
        '// RSD Support\n- (void)getProcessListWithCompletion:(void (^)(NSArray *processes, NSError *error))completion;')
    with open('IdeviceManager.h', 'w') as f:
        f.write(h_content)

with open('IdeviceManager.m', 'r') as f:
    m_content = f.read()

process_method = r"""
- (void)getProcessListWithCompletion:(void (^)(NSArray *processes, NSError *error))completion {
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
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDストリームの接続に失敗しました"] : @"RSDストリームの接続に失敗しました";
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

        struct AppServiceHandle *appSvc = NULL;
        err = app_service_connect_rsd(adapter, handshake, &appSvc);
        if (err || !appSvc) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "AppServiceへの接続に失敗しました"] : @"AppServiceへの接続に失敗しました";
            if (err) idevice_error_free(err);
            rsd_handshake_free(handshake);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:14 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct ProcessTokenC *rawProcesses = NULL;
        uintptr_t count = 0;
        err = app_service_list_processes(appSvc, &rawProcesses, &count);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "プロセス一覧の取得に失敗しました"];
            if (err) idevice_error_free(err);
            app_service_free(appSvc);
            rsd_handshake_free(handshake);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:15 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        NSMutableArray *results = [NSMutableArray array];
        for (uintptr_t i = 0; i < count; i++) {
            struct ProcessTokenC *p = &rawProcesses[i];
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"pid"] = @(p->pid);
            if (p->executable_url) dict[@"path"] = [NSString stringWithUTF8String:p->executable_url];
            [results addObject:dict];
        }

        app_service_free_process_list(rawProcesses, count);
        app_service_free(appSvc);
        rsd_handshake_free(handshake);
        idevice_stream_free(stream);

        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(results, nil); });
    });
}
"""

if 'getProcessListWithCompletion' not in m_content:
    m_content = m_content.replace('@end', process_method + '\n@end')
    with open('IdeviceManager.m', 'w') as f:
        f.write(m_content)
