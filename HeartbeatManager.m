#import "HeartbeatManager.h"

@interface HeartbeatManager ()
@property (nonatomic, assign) struct HeartbeatClientHandle *heartbeatClient;
@property (nonatomic, assign) BOOL running;
@end

@implementation HeartbeatManager

+ (instancetype)sharedManager {
    static HeartbeatManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[HeartbeatManager alloc] init]; });
    return shared;
}

- (void)startHeartbeatWithProvider:(struct IdeviceProviderHandle *)provider {
    [self stopHeartbeat];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct HeartbeatClientHandle *hb = NULL;
        struct IdeviceFfiError *err = heartbeat_connect(provider, &hb);
        if (err) { NSLog(@"[Heartbeat] Connect failed: %s", err->message); idevice_error_free(err); return; }
        self.heartbeatClient = hb; self.running = YES;
        [self heartbeatLoop];
    });
}

- (void)heartbeatLoop {
    uint64_t interval = 10;
    while (self.running && self.heartbeatClient) {
        uint64_t next_interval = 0;
        struct IdeviceFfiError *err = heartbeat_get_marco(self.heartbeatClient, interval, &next_interval);
        if (err) { NSLog(@"[Heartbeat] Error: %s", err->message); idevice_error_free(err); break; }
        if (next_interval > 0) interval = next_interval;
        err = heartbeat_send_polo(self.heartbeatClient);
        if (err) { NSLog(@"[Heartbeat] Polo error: %s", err->message); idevice_error_free(err); break; }
    }
    [self stopHeartbeat];
}

- (void)stopHeartbeat {
    self.running = NO;
    if (self.heartbeatClient) { heartbeat_client_free(self.heartbeatClient); self.heartbeatClient = NULL; }
}
@end
