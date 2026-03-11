#import "HeartbeatManager.h"

static inline const char *heartbeatSafeErrCString(const struct IdeviceFfiError *err) {
    if (!err || !err->message || err->message[0] == '\0') return "(no detail)";
    return err->message;
}

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
        if (err) {
            NSLog(@"[Heartbeat] Connect failed: %s", heartbeatSafeErrCString(err));
            idevice_error_free(err);
            return;
        }

        @synchronized (self) {
            self.heartbeatClient = hb;
            self.running = YES;
            self.paused = NO;
        }
        NSLog(@"[Heartbeat] Started via provider");
        [self heartbeatLoop];
    });
}

- (void)heartbeatLoop {
    uint64_t interval = 10;

    while (YES) {
        struct HeartbeatClientHandle *hb = NULL;
        BOOL shouldRun = NO;
        BOOL isPaused = NO;

        @synchronized (self) {
            hb = self.heartbeatClient;
            shouldRun = self.running;
            isPaused = self.paused;
        }

        if (!shouldRun || !hb) break;

        if (isPaused) {
            [NSThread sleepForTimeInterval:1.0];
            continue;
        }

        uint64_t next_interval = 0;
        struct IdeviceFfiError *err = heartbeat_get_marco(hb, interval, &next_interval);
        if (err) {
            NSLog(@"[Heartbeat] Error: %s", heartbeatSafeErrCString(err));
            idevice_error_free(err);
            break;
        }
        if (next_interval > 0) interval = next_interval;

        err = heartbeat_send_polo(hb);
        if (err) {
            NSLog(@"[Heartbeat] Polo error: %s", heartbeatSafeErrCString(err));
            idevice_error_free(err);
            break;
        }

        [NSThread sleepForTimeInterval:1.0];
    }

    [self stopHeartbeat];
}

- (void)stopHeartbeat {
    struct HeartbeatClientHandle *hb = NULL;
    @synchronized (self) {
        self.running = NO;
        hb = self.heartbeatClient;
        self.heartbeatClient = NULL;
        self.paused = NO;
    }

    if (hb) {
        heartbeat_client_free(hb);
        NSLog(@"[Heartbeat] Stopped");
    }
}

- (void)pauseHeartbeat {
    @synchronized (self) {
        self.paused = YES;
    }
    NSLog(@"[Heartbeat] Paused");
}

- (void)resumeHeartbeat {
    @synchronized (self) {
        self.paused = NO;
    }
    NSLog(@"[Heartbeat] Resumed");
}

@end
