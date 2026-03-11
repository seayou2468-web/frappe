#import "DdiManager.h"

static inline const char *ddiSafeErrCString(const struct IdeviceFfiError *err) {
    if (!err || !err->message || err->message[0] == '\0') return "(no detail)";
    return err->message;
}

@implementation DdiManager

+ (instancetype)sharedManager {
    static DdiManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[DdiManager alloc] init]; });
    return shared;
}

- (void)checkAndMountDdiWithLockdown:(struct LockdowndClientHandle *)lockdown ip:(NSString *)ip completion:(void (^)(BOOL success, NSString *message))completion {
}

- (void)checkAndMountDdiWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown completion:(void (^)(BOOL success, NSString *message))completion {
    if (!provider || !lockdown) { completion(NO, @"Missing provider or lockdown handle"); return; }

    plist_t version_plist = NULL;
    lockdownd_get_value(lockdown, "ProductVersion", NULL, &version_plist);
    NSString *version = @"Unknown";
    if (version_plist) { char *val = NULL; plist_get_string_val(version_plist, &val); if (val) { version = [NSString stringWithUTF8String:val]; plist_mem_free(val); } plist_free(version_plist); }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct ImageMounterHandle *mounter = NULL;
        struct IdeviceFfiError *err = image_mounter_connect(provider, &mounter);
        if (err) { completion(NO, [NSString stringWithFormat:@"DDI Service Connect failed: %s", ddiSafeErrCString(err)]); idevice_error_free(err); return; }

        BOOL alreadyMounted = NO;

        // 1. Check mounted devices list
        plist_t *devices = NULL; size_t devices_len = 0;
        err = image_mounter_copy_devices(mounter, &devices, &devices_len);
        if (!err && devices) {
            if (devices_len > 0) alreadyMounted = YES;
            idevice_plist_array_free(devices, devices_len);
        }
        if (err) { NSLog(@"[DDI] copy_devices error: %s", ddiSafeErrCString(err)); idevice_error_free(err); }

        // 2. Double-check with image lookup if list was empty but service says otherwise
        if (!alreadyMounted) {
            uint8_t *sig = NULL; size_t sig_len = 0;
            err = image_mounter_lookup_image(mounter, "Developer", &sig, &sig_len);
            if (!err && sig) { alreadyMounted = YES; idevice_data_free(sig, sig_len); }
            if (err) idevice_error_free(err);
        }

        if (alreadyMounted) {
            // Verify developer mode status even if already mounted
            int dev_mode = 0;
            err = image_mounter_query_developer_mode_status(mounter, &dev_mode);
            if (!err && dev_mode == 1) {
                completion(YES, [NSString stringWithFormat:@"DDI Active (iOS %@)", version]);
            } else {
                if (err) idevice_error_free(err);
                completion(NO, [NSString stringWithFormat:@"DDI state inconsistent (Mode: %d)", dev_mode]);
            }
            image_mounter_free(mounter);
            return;
        }

        int dev_mode = 0;
        err = image_mounter_query_developer_mode_status(mounter, &dev_mode);
        if (err) { completion(NO, [NSString stringWithFormat:@"Dev mode check failed: %s", ddiSafeErrCString(err)]); idevice_error_free(err); image_mounter_free(mounter); return; }

        if (dev_mode == 0) { completion(NO, @"Developer Mode is disabled."); image_mounter_free(mounter); return; }

        completion(NO, [NSString stringWithFormat:@"DDI image for iOS %@ needed.", version]);
        image_mounter_free(mounter);
    });
}
@end
