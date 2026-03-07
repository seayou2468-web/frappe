import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# Fix captureSysdiagnoseWithCompletion error handling in the loop
old_loop = r"""        uint8_t *data = NULL; uintptr_t len = 0;
        while (true) {
            err = sysdiagnose_stream_next(stream_h, &data, &len);
            if (err) { if (err) idevice_error_free(err); break; }
            if (!data || len == 0) break;
            [file writeData:[NSData dataWithBytes:data length:len]];
            idevice_data_free(data, len);
        }
        [file closeFile];"""

new_loop = r"""        uint8_t *data = NULL; uintptr_t len = 0;
        BOOL success = YES;
        NSError *loopErr = nil;
        while (true) {
            err = sysdiagnose_stream_next(stream_h, &data, &len);
            if (err) {
                NSString *msg = [NSString stringWithUTF8String:err->message ?: "ストリーム取得エラー"];
                loopErr = [NSError errorWithDomain:@"Idevice" code:16 userInfo:@{NSLocalizedDescriptionKey: msg}];
                idevice_error_free(err);
                success = NO;
                break;
            }
            if (!data || len == 0) break;
            [file writeData:[NSData dataWithBytes:data length:len]];
            idevice_data_free(data, len);
        }
        [file closeFile];
        if (!success) {
             if (stream_h) sysdiagnose_stream_free(stream_h);
             if (diag) diagnostics_service_free(diag);
             if (handshake) rsd_handshake_free(handshake);
             if (stream) idevice_stream_free(stream);
             if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, loopErr); });
             return;
        }"""

content = content.replace(old_loop, new_loop)

# Fix potential duplicate free in getProcessListWithCompletion or captureSysdiagnose
# (Actually I already added checks in the last overwrite, let's just make sure)

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
