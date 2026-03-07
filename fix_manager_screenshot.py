import re

with open('IdeviceManager.h', 'r') as f:
    h_content = f.read()

if 'takeScreenshotWithCompletion' not in h_content:
    h_content = h_content.replace('// RSD Support',
        '// RSD Support\n- (void)takeScreenshotWithCompletion:(void (^)(UIImage *image, NSError *error))completion;')
    with open('IdeviceManager.h', 'w') as f:
        f.write(h_content)

with open('IdeviceManager.m', 'r') as f:
    m_content = f.read()

screenshot_method = r"""
- (void)takeScreenshotWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct IdeviceProviderHandle *p = self.provider;
    [_lock unlock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct ScreenshotrClientHandle *client = NULL;
        struct IdeviceFfiError *err = screenshotr_connect(p, &client);
        if (err || !client) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Screenshotrへの接続に失敗しました"] : @"Screenshotrへの接続に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:17 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct ScreenshotData data;
        memset(&data, 0, sizeof(data));
        err = screenshotr_take_screenshot(client, &data);
        screenshotr_client_free(client);

        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "スクリーンショットの取得に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:18 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        if (data.data && data.length > 0) {
            NSData *pngData = [NSData dataWithBytes:data.data length:data.length];
            UIImage *img = [UIImage imageWithData:pngData];
            screenshotr_screenshot_free(data);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); });
        } else {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:19 userInfo:@{NSLocalizedDescriptionKey: @"データが空です"}]); });
        }
    });
}
"""

if 'takeScreenshotWithCompletion' not in m_content:
    # Insert before the last @end
    m_content = m_content.replace('@end\n', screenshot_method + '\n@end\n')
    with open('IdeviceManager.m', 'w') as f:
        f.write(m_content)
