#import "IdeviceManager.h"
#import <arpa/inet.h>
#import "Logger.h"

@interface IdeviceManager () {
    NSRecursiveLock *_lock;
}
@property (nonatomic, assign) IdeviceConnectionStatus status;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct LockdowndClientHandle *lockdownClient;
@property (nonatomic, assign) struct HeartbeatClientHandle *heartbeatClient;
@property (nonatomic, assign) struct IdevicePairingFile *pairingFile;
@property (nonatomic, assign) BOOL heartbeatActive;
@property (nonatomic, assign) BOOL ddiMounted;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@end

@implementation IdeviceManager

+ (instancetype)sharedManager {
    static IdeviceManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[IdeviceManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _ipAddress = [defaults stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
        _port = [defaults integerForKey:@"IdevicePort"] ?: 62078;
        _pairingFilePath = [defaults stringForKey:@"IdevicePairingPath"];
        _status = IdeviceStatusDisconnected;

        idevice_init_logger(Debug, Disabled, NULL);
    }
    return self;
}

- (void)setIpAddress:(NSString *)ipAddress {
    [_lock lock];
    _ipAddress = ipAddress;
    [[NSUserDefaults standardUserDefaults] setObject:ipAddress forKey:@"IdeviceIP"];
    [_lock unlock];
}

- (void)setPort:(uint16_t)port {
    [_lock lock];
    _port = port;
    [[NSUserDefaults standardUserDefaults] setInteger:port forKey:@"IdevicePort"];
    [_lock unlock];
}

- (void)selectPairingFile:(NSString *)path {
    [_lock lock];
    _pairingFilePath = path;
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:@"IdevicePairingPath"];
    [_lock unlock];
}

- (void)connect {
    [_lock lock];
    if (self.status == IdeviceStatusConnected || self.status == IdeviceStatusConnecting) {
        [_lock unlock];
        return;
    }
    self.status = IdeviceStatusConnecting;
    [_lock unlock];

    self.lastError = nil;
    [[Logger sharedLogger] log:@"[Idevice] Starting connection process..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self _performConnect];
    });
}

- (void)_performConnect {
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] Connecting to %@:%d", self.ipAddress, self.port]];

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(self.port);
    if (inet_pton(AF_INET, [self.ipAddress UTF8String], &sa.sin_addr) <= 0) {
        [self _handleError:@"Invalid IP address"];
        return;
    }

    struct IdeviceFfiError *err = NULL;
    struct IdeviceProviderHandle *provider = NULL;
    struct IdevicePairingFile *pairingFile = NULL;

    if (self.pairingFilePath) {
        [[Logger sharedLogger] log:@"[Idevice] Reading pairing file..."];
        err = idevice_pairing_file_read([self.pairingFilePath UTF8String], &pairingFile);
        if (err) {
            [self _handleFfiError:err];
            return;
        }
    } else {
        [self _handleError:@"Pairing file not selected"];
        return;
    }

    if (!pairingFile) {
        [self _handleError:@"Failed to load pairing file (null handle)"];
        return;
    }

    [_lock lock];
    self.pairingFile = pairingFile;
    [_lock unlock];

    [[Logger sharedLogger] log:@"[Idevice] Creating TCP provider..."];
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingFile, "frappe-idevice", &provider);
    if (err) {
        [self _handleFfiError:err];
        return;
    }

    if (!provider) {
        [self _handleError:@"Failed to create provider (null handle)"];
        return;
    }

    [_lock lock];
    self.provider = provider;
    [_lock unlock];

    [[Logger sharedLogger] log:@"[Idevice] Connecting to lockdown..."];
    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) {
        [self _handleFfiError:err];
        return;
    }

    if (!lockdown) {
        [self _handleError:@"Failed to connect to lockdown (null handle)"];
        return;
    }

    [_lock lock];
    self.lockdownClient = lockdown;
    [_lock unlock];

    [[Logger sharedLogger] log:@"[Idevice] Starting lockdown session..."];
    err = lockdownd_start_session(lockdown, pairingFile);
    if (err) {
        [self _handleFfiError:err];
        return;
    }

    [[Logger sharedLogger] log:@"[Idevice] Connecting heartbeat..."];
    struct HeartbeatClientHandle *hb = NULL;
    err = heartbeat_connect(provider, &hb);
    if (!err && hb) {
        [_lock lock];
        self.heartbeatClient = hb;
        self.heartbeatActive = YES;
        [_lock unlock];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _startHeartbeatTimer];
        });
    } else if (err) {
        idevice_error_free(err);
    }

    [[Logger sharedLogger] log:@"[Idevice] Checking DDI status..."];
    [self _checkAndMountDDI];

    dispatch_async(dispatch_get_main_queue(), ^{
        [_lock lock];
        self.status = IdeviceStatusConnected;
        [_lock unlock];
        [[Logger sharedLogger] log:@"[Idevice] Successfully connected"];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil];
    });
}

- (void)_checkAndMountDDI {
    struct ImageMounterHandle *mounter = NULL;
    struct IdeviceProviderHandle *currentProvider = NULL;
    [_lock lock];
    currentProvider = self.provider;
    [_lock unlock];
    if (!currentProvider) return;

    struct IdeviceFfiError *err = image_mounter_connect(currentProvider, &mounter);
    if (!err && mounter) {
        plist_t *devices = NULL;
        size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) {
            [_lock lock];
            self.ddiMounted = (count > 0);
            [_lock unlock];
            [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] DDI status checked: %@", (count > 0) ? @"Mounted" : @"Not Mounted"]];
        } else {
            idevice_error_free(err);
        }
        image_mounter_free(mounter);
    } else if (err) {
        idevice_error_free(err);
    }
}

- (void)_startHeartbeatTimer {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(_sendHeartbeat) userInfo:nil repeats:YES];
}

- (void)_sendHeartbeat {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct IdeviceFfiError *err = NULL;
        [_lock lock];
        if (!self.heartbeatClient) {
            [_lock unlock];
            return;
        }
        err = heartbeat_send_polo(self.heartbeatClient);
        [_lock unlock];

        if (err) {
            idevice_error_free(err);
            [[Logger sharedLogger] log:@"[Idevice] Heartbeat lost"];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self disconnect];
                [_lock lock];
                self.lastError = @"Heartbeat lost";
                [_lock unlock];
            });
        }
    });
}

- (void)disconnect {
    [[Logger sharedLogger] log:@"[Idevice] Disconnecting and cleaning up handles..."];

    // We invalidate the timer first, outside the lock to avoid timer-related deadlock
    // Although NSTimer is safe to invalidate from any thread if correctly managed,
    // the main loop might be involved.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    });

    [_lock lock];
    if (self.heartbeatClient) {
        heartbeat_client_free(self.heartbeatClient);
        self.heartbeatClient = NULL;
    }
    if (self.lockdownClient) {
        lockdownd_client_free(self.lockdownClient);
        self.lockdownClient = NULL;
    }
    if (self.provider) {
        idevice_provider_free(self.provider);
        self.provider = NULL;
    }
    if (self.pairingFile) {
        idevice_pairing_file_free(self.pairingFile);
        self.pairingFile = NULL;
    }

    self.status = IdeviceStatusDisconnected;
    self.heartbeatActive = NO;
    self.ddiMounted = NO;
    [_lock unlock];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil];
    });
}

- (void)_handleFfiError:(struct IdeviceFfiError *)err {
    NSString *msg = [NSString stringWithUTF8String:err->message ?: "Unknown error"];
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] FFI Error: %@", msg]];
    idevice_error_free(err);
    [self _handleError:msg];
}

- (void)_handleError:(NSString *)msg {
    [_lock lock];
    self.lastError = msg;
    self.status = IdeviceStatusError;
    [_lock unlock];

    [self disconnect];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil];
    });
}

@end
