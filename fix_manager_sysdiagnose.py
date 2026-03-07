import re

with open('IdeviceManager.h', 'r') as f:
    h_content = f.read()

if 'captureSysdiagnoseWithCompletion' not in h_content:
    h_content = h_content.replace('// RSD Support',
        '// RSD Support\n- (void)captureSysdiagnoseWithCompletion:(void (^)(NSString *path, NSError *error))completion;')
    with open('IdeviceManager.h', 'w') as f:
        f.write(h_content)

with open('IdeviceManager.m', 'r') as f:
    m_content = f.read()

sysdiagnose_method = r"""
- (void)captureSysdiagnoseWithCompletion:(void (^)(NSString *path, NSError *error))completion {
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

        struct DiagnosticsServiceHandle *diag = NULL;
        err = diagnostics_service_connect_rsd(adapter, handshake, &diag);
        if (err || !diag) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Diagnosticsへの接続に失敗しました"] : @"Diagnosticsへの接続に失敗しました";
            if (err) idevice_error_free(err);
            rsd_handshake_free(handshake);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:11 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        char *filename = NULL;
        uintptr_t expected = 0;
        struct SysdiagnoseStreamHandle *stream_h = NULL;
        err = diagnostics_service_capture_sysdiagnose(diag, false, &filename, &expected, &stream_h);
        if (err || !stream_h) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Sysdiagnoseの開始に失敗しました"] : @"Sysdiagnoseの開始に失敗しました";
            if (err) idevice_error_free(err);
            if (filename) rsd_free_string(filename);
            diagnostics_service_free(diag);
            rsd_handshake_free(handshake);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:12 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        NSString *destName = filename ? [NSString stringWithUTF8String:filename] : [NSString stringWithFormat:@"sysdiagnose_%ld.tar.gz", (long)[[NSDate date] timeIntervalSince1970]];
        if (filename) rsd_free_string(filename);

        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *finalPath = [docPath stringByAppendingPathComponent:destName];

        [[NSFileManager defaultManager] createFileAtPath:finalPath contents:nil attributes:nil];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:finalPath];

        if (!file) {
             sysdiagnose_stream_free(stream_h);
             diagnostics_service_free(diag);
             rsd_handshake_free(handshake);
             idevice_stream_free(stream);
             if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:13 userInfo:@{NSLocalizedDescriptionKey: @"ファイルの作成に失敗しました"}]); });
             return;
        }

        uint8_t *data = NULL;
        uintptr_t len = 0;
        while (true) {
            err = sysdiagnose_stream_next(stream_h, &data, &len);
            if (err) {
                idevice_error_free(err);
                break;
            }
            if (!data || len == 0) break;
            [file writeData:[NSData dataWithBytes:data length:len]];
            idevice_data_free(data, len);
        }

        [file closeFile];
        sysdiagnose_stream_free(stream_h);
        diagnostics_service_free(diag);
        rsd_handshake_free(handshake);
        idevice_stream_free(stream);

        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(finalPath, nil); });
    });
}
"""

if 'captureSysdiagnoseWithCompletion' not in m_content:
    m_content = m_content.replace('@end', sysdiagnose_method + '\n@end')
    with open('IdeviceManager.m', 'w') as f:
        f.write(m_content)
