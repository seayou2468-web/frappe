#import "HeartbeatManager.h"
#import <netinet/in.h>
#import <arpa/inet.h>

@interface HeartbeatManager ()
@property (nonatomic, assign) struct HeartbeatClientHandle *heartbeatClient;
@property (nonatomic, assign) BOOL running;
@end

@implementation HeartbeatManager

+ (instancetype)sharedManager {
    static HeartbeatManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HeartbeatManager alloc] init];
    });
    return shared;
}

- (void)startHeartbeatWithLockdown:(struct LockdowndClientHandle *)lockdown ip:(NSString *)ip {
    [self stopHeartbeat];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint16_t port = 0;
        bool ssl = false;
        struct IdeviceFfiError *err = lockdownd_start_service(lockdown, "com.apple.mobile.heartbeat", &port, &ssl);
        if (err) {
            NSLog(@"[Heartbeat] Failed to start service: %s", err->message);
            idevice_error_free(err);
            return;
        }

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port);
        inet_pton(AF_INET, [ip UTF8String], &addr.sin_addr);

        struct IdeviceHandle *device = NULL;
        err = idevice_new_tcp_socket((const idevice_sockaddr *)&addr, sizeof(addr), "Heartbeat", &device);
        if (err) {
            NSLog(@"[Heartbeat] Failed to connect to port %d: %s", port, err->message);
            idevice_error_free(err);
            return;
        }

        struct HeartbeatClientHandle *hb = NULL;
        err = heartbeat_new(device, &hb);
        if (err) {
            NSLog(@"[Heartbeat] Failed to create client: %s", err->message);
            idevice_error_free(err);
            idevice_free(device);
            return;
        }

        self.heartbeatClient = hb;
        self.running = YES;
        NSLog(@"[Heartbeat] Started on port %d", port);

        [self heartbeatLoop];
    });
}

- (void)heartbeatLoop {
    while (self.running && self.heartbeatClient) {
        plist_t marco = NULL;
        struct IdeviceFfiError *err = heartbeat_get_marco(self.heartbeatClient, &marco);
        if (err) {
            NSLog(@"[Heartbeat] Error getting marco: %s", err->message);
            idevice_error_free(err);
            break;
        }

        if (marco) {
            plist_free(marco);
            err = heartbeat_send_polo(self.heartbeatClient);
            if (err) {
                NSLog(@"[Heartbeat] Error sending polo: %s", err->message);
                idevice_error_free(err);
                break;
            }
            NSLog(@"[Heartbeat] Marco? Polo!");
        }
    }
    [self stopHeartbeat];
}

- (void)stopHeartbeat {
    self.running = NO;
    if (self.heartbeatClient) {
        heartbeat_client_free(self.heartbeatClient);
        self.heartbeatClient = NULL;
        NSLog(@"[Heartbeat] Stopped");
    }
}

@end
