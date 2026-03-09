#import "DdiManager.h"
#import <netinet/in.h>
#import <arpa/inet.h>

@implementation DdiManager

+ (instancetype)sharedManager {
    static DdiManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DdiManager alloc] init];
    });
    return shared;
}

- (void)checkAndMountDdiWithLockdown:(struct LockdowndClientHandle *)lockdown ip:(NSString *)ip completion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 1. Get Device Info
        plist_t version_plist = NULL;
        struct IdeviceFfiError *err = lockdownd_get_value(lockdown, "ProductVersion", NULL, &version_plist);
        NSString *version = @"Unknown";
        if (!err && version_plist) {
            char *val = NULL;
            plist_get_string_val(version_plist, &val);
            if (val) { version = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
            plist_free(version_plist);
        } else if (err) {
            idevice_error_free(err);
        }

        plist_t build_plist = NULL;
        err = lockdownd_get_value(lockdown, "BuildVersion", NULL, &build_plist);
        NSString *build = @"Unknown";
        if (!err && build_plist) {
            char *val = NULL;
            plist_get_string_val(build_plist, &val);
            if (val) { build = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
            plist_free(build_plist);
        } else if (err) {
            idevice_error_free(err);
        }

        NSLog(@"[DDI] Device Version: %@ (%@)", version, build);

        // 2. Start Mounter Service
        uint16_t port = 0;
        bool ssl = false;
        err = lockdownd_start_service(lockdown, "com.apple.mobile.mobile_image_mounter", &port, &ssl);
        if (err) {
            completion(NO, [NSString stringWithFormat:@"Service failed: %s", err->message]);
            idevice_error_free(err);
            return;
        }

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port);
        inet_pton(AF_INET, [ip UTF8String], &addr.sin_addr);

        struct IdeviceHandle *device = NULL;
        err = idevice_new_tcp_socket((const idevice_sockaddr *)&addr, sizeof(addr), "Mounter", &device);
        if (err) {
            completion(NO, [NSString stringWithFormat:@"Socket failed: %s", err->message]);
            idevice_error_free(err);
            return;
        }

        struct ImageMounterHandle *mounter = NULL;
        err = image_mounter_new(device, &mounter);
        if (err) {
            completion(NO, [NSString stringWithFormat:@"Mounter failed: %s", err->message]);
            idevice_error_free(err);
            idevice_free(device);
            return;
        }

        // 3. Check if Developer DDI is already mounted
        uint8_t *sig = NULL;
        size_t sig_len = 0;
        err = image_mounter_lookup_image(mounter, "Developer", &sig, &sig_len);
        if (!err && sig) {
            completion(YES, [NSString stringWithFormat:@"DDI already mounted for iOS %@", version]);
            idevice_data_free(sig, sig_len);
            image_mounter_free(mounter);
            return;
        }
        if (err) idevice_error_free(err);

        // 4. Check Developer Mode
        int dev_mode = 0;
        err = image_mounter_query_developer_mode_status(mounter, &dev_mode);
        if (err) {
            completion(NO, [NSString stringWithFormat:@"Dev mode check failed: %s", err->message]);
            idevice_error_free(err);
            image_mounter_free(mounter);
            return;
        }

        if (dev_mode == 0) {
            completion(NO, @"Developer Mode is disabled. Please enable it in Settings.");
            image_mounter_free(mounter);
            return;
        }

        // 5. Placeholder for actual image data acquisition
        // To implement real mounting, we would need to download the DDI from a source or use a local cache.
        // For now, we report what is needed.

        completion(NO, [NSString stringWithFormat:@"DDI image for iOS %@ (%@) needed.", version, build]);
        image_mounter_free(mounter);
    });
}

@end
