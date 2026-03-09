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
        uint16_t port = 0;
        bool ssl = false;
        struct IdeviceFfiError *err = lockdownd_start_service(lockdown, "com.apple.mobile.mobile_image_mounter", &port, &ssl);
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

        // Check if Developer DDI is already mounted
        uint8_t *sig = NULL;
        size_t sig_len = 0;
        err = image_mounter_lookup_image(mounter, "Developer", &sig, &sig_len);
        if (!err && sig) {
            completion(YES, @"DDI already mounted");
            idevice_data_free(sig, sig_len);
            image_mounter_free(mounter);
            return;
        }
        if (err) idevice_error_free(err);

        // Check dev mode
        bool dev_mode = false;
        err = image_mounter_query_developer_mode_status(mounter, &dev_mode);
        if (err) {
            completion(NO, [NSString stringWithFormat:@"Dev mode check failed: %s", err->message]);
            idevice_error_free(err);
            image_mounter_free(mounter);
            return;
        }

        if (!dev_mode) {
            completion(NO, @"Developer Mode not enabled.");
            image_mounter_free(mounter);
            return;
        }

        completion(NO, @"DDI not mounted. Automated mount not available.");
        image_mounter_free(mounter);
    });
}

@end
