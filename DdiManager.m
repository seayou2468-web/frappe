#import "DdiManager.h"

@implementation DdiManager

+ (instancetype)sharedManager {
    static DdiManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[DdiManager alloc] init]; });
    return shared;
}

- (void)checkAndMountDdiWithProvider:(struct IdeviceProviderHandle *)provider lockdown:(struct LockdowndClientHandle *)lockdown completion:(void (^)(BOOL success, NSString *message))completion {
    plist_t version_plist = NULL;
    lockdownd_get_value(lockdown, "ProductVersion", NULL, &version_plist);
    NSString *version = @"Unknown";
    if (version_plist) { char *val = NULL; plist_get_string_val(version_plist, &val); if (val) { version = [NSString stringWithUTF8String:val]; plist_mem_free(val); } plist_free(version_plist); }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct ImageMounterHandle *mounter = NULL;
        struct IdeviceFfiError *err = image_mounter_connect(provider, &mounter);
        if (err) { completion(NO, [NSString stringWithFormat:@"Connect failed: %s", err->message]); idevice_error_free(err); return; }

        uint8_t *sig = NULL; size_t sig_len = 0;
        err = image_mounter_lookup_image(mounter, "Developer", &sig, &sig_len);
        if (!err && sig) { completion(YES, @"DDI already mounted"); idevice_data_free(sig, sig_len); image_mounter_free(mounter); return; }
        if (err) idevice_error_free(err);

        int dev_mode = 0;
        err = image_mounter_query_developer_mode_status(mounter, &dev_mode);
        if (err) { completion(NO, [NSString stringWithFormat:@"Dev mode check failed: %s", err->message]); idevice_error_free(err); image_mounter_free(mounter); return; }

        if (dev_mode == 0) { completion(NO, @"Developer Mode disabled."); image_mounter_free(mounter); return; }

        completion(NO, [NSString stringWithFormat:@"DDI for iOS %@ needed.", version]);
        image_mounter_free(mounter);
    });
}
@end
