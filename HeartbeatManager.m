#import "HeartbeatManager.h"

@interface HeartbeatManager ()
@property (nonatomic, assign) struct HeartbeatClientHandle *heartbeatClient;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL paused;
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
    if (!provider) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct HeartbeatClientHandle *hb = NULL;
        struct IdeviceFfiError *err = heartbeat_connect(provider, &hb);
        if (err) { NSLog(@"[Heartbeat] Connect failed: %s", err->message); idevice_error_free(err); return; }

        self.heartbeatClient = hb;
        self.running = YES;
        self.paused = NO;
        NSLog(@"[Heartbeat] Started via provider");
        [self heartbeatLoop];
    });
}

- (void)heartbeatLoop {
    uint64_t interval = 10;
    while (self.running && self.heartbeatClient) {
        if (self.paused) {
            [NSThread sleepForTimeInterval:1.0];
            continue;
        }

        uint64_t next_interval = 0;
        struct IdeviceFfiError *err = heartbeat_get_marco(self.heartbeatClient, interval, &next_interval);
        if (err) { NSLog(@"[Heartbeat] Error: %s", err->message); idevice_error_free(err); break; }
        if (next_interval > 0) interval = next_interval;

        err = heartbeat_send_polo(self.heartbeatClient);
        if (err) { NSLog(@"[Heartbeat] Polo error: %s", err->message); idevice_error_free(err); break; }

        // Sleep a bit to prevent tight loop if paused changes
        [NSThread sleepForTimeInterval:1.0];
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

- (void)pauseHeartbeat {
    self.paused = YES;
    NSLog(@"[Heartbeat] Paused");
}

- (void)resumeHeartbeat {
    self.paused = NO;
    NSLog(@"[Heartbeat] Resumed");
}

@end
