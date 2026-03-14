import sys

file_path = 'AppManager.m'
with open(file_path, 'r') as f:
    content = f.read()

# Restore static callback and installAppWithURL before launchApp
callback_and_method = """
static void instproxy_callback(uint64_t progress, void *user_data) {
    void (^progressBlock)(double, NSString *) = (__bridge void (^)(double, NSString *))user_data;
    if (progressBlock) {
        double val = 0.5 + (0.5 * ((double)progress / 100.0));
        dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(val, [NSString stringWithFormat:@"Installing (%llu%%)...", progress]);
        });
    }
}

- (void)installAppWithURL:(NSURL *)url
                 provider:(struct IdeviceProviderHandle *)provider
                 progress:(void (^)(double progress, NSString *status))progress
               completion:(void (^)(BOOL success, NSString *error))completion
{
    if (!url || !provider) {
        if (completion) completion(NO, @"Missing URL or provider");
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        struct AfcClientHandle *afc = NULL;
        struct IdeviceFfiError *err = afc_client_connect(provider, &afc);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"AFC connect failed: %s", err->message];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }

        afc_make_directory(afc, "/PublicStaging");
        NSString *fileName = [url lastPathComponent];
        NSString *remotePath = [NSString stringWithFormat:@"/PublicStaging/%@", fileName];
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(0.1, @"Uploading IPA..."); });

        NSData *data = [NSData dataWithContentsOfURL:url];
        if (!data) {
            afc_client_free(afc);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"Failed to read IPA data"); });
            return;
        }

        struct AfcFileHandle *file = NULL;
        err = afc_file_open(afc, [remotePath UTF8String], AfcWrOnly, &file);
        if (err) {
            afc_client_free(afc);
            NSString *msg = [NSString stringWithFormat:@"AFC open failed: %s", err->message];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }

        const uint8_t *bytes = (const uint8_t *)[data bytes];
        size_t total = data.length;
        size_t uploaded = 0;
        size_t chunkSize = 1024 * 64;
        while (uploaded < total) {
            size_t toWrite = MIN(chunkSize, total - uploaded);
            err = afc_file_write(file, bytes + uploaded, toWrite);
            if (err) break;
            uploaded += toWrite;
            if (progress) {
                double p = 0.1 + (0.4 * ((double)uploaded / total));
                dispatch_async(dispatch_get_main_queue(), ^{ progress(p, [NSString stringWithFormat:@"Uploading (%.0f%%)...", p*100]); });
            }
        }
        afc_file_close(file);

        if (err) {
            afc_client_free(afc);
            NSString *msg = [NSString stringWithFormat:@"Upload failed: %s", err->message];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }
        afc_client_free(afc);

        if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(0.5, @"Starting Installation..."); });

        struct InstallationProxyClientHandle *inst = NULL;
        err = installation_proxy_connect(provider, &inst);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"InstProxy connect failed: %s", err->message];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }

        void (^progressCopy)(double, NSString *) = [progress copy];
        err = installation_proxy_install_with_callback(inst, [remotePath UTF8String], NULL, instproxy_callback, (__bridge void *)progressCopy);
        installation_proxy_client_free(inst);

        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Install failed: %s", err->message];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
        } else {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, nil); });
        }
    });
}
"""

marker = '- (void)launchApp:(NSString *)bundleId'
content = content.replace(marker, callback_and_method + "\n" + marker)

with open(file_path, 'w') as f:
    f.write(content)
