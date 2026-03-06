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

#pragma mark - Thread-safe Properties

- (IdeviceConnectionStatus)status {
    [_lock lock];
    IdeviceConnectionStatus s = _status;
    [_lock unlock];
    return s;
}

- (void)setStatus:(IdeviceConnectionStatus)status {
    [_lock lock];
    _status = status;
    [_lock unlock];
}

- (NSString *)ipAddress {
    [_lock lock];
    NSString *ip = [_ipAddress copy];
    [_lock unlock];
    return ip;
}

- (void)setIpAddress:(NSString *)ipAddress {
    [_lock lock];
    _ipAddress = [ipAddress copy];
    [[NSUserDefaults standardUserDefaults] setObject:ipAddress forKey:@"IdeviceIP"];
    [_lock unlock];
}

- (uint16_t)port {
    [_lock lock];
    uint16_t p = _port;
    [_lock unlock];
    return p;
}

- (void)setPort:(uint16_t)port {
    [_lock lock];
    _port = port;
    [[NSUserDefaults standardUserDefaults] setInteger:port forKey:@"IdevicePort"];
    [_lock unlock];
}

- (NSString *)pairingFilePath {
    [_lock lock];
    NSString *path = [_pairingFilePath copy];
    [_lock unlock];
    return path;
}

- (void)setPairingFilePath:(NSString *)pairingFilePath {
    [_lock lock];
    _pairingFilePath = [pairingFilePath copy];
    [[NSUserDefaults standardUserDefaults] setObject:pairingFilePath forKey:@"IdevicePairingPath"];
    [_lock unlock];
}

- (NSString *)lastError {
    [_lock lock];
    NSString *err = [_lastError copy];
    [_lock unlock];
    return err;
}

- (void)setLastError:(NSString *)lastError {
    [_lock lock];
    _lastError = [lastError copy];
    [_lock unlock];
}

- (BOOL)heartbeatActive {
    [_lock lock];
    BOOL active = _heartbeatActive;
    [_lock unlock];
    return active;
}

- (void)setHeartbeatActive:(BOOL)heartbeatActive {
    [_lock lock];
    _heartbeatActive = heartbeatActive;
    [_lock unlock];
}

- (BOOL)ddiMounted {
    [_lock lock];
    BOOL mounted = _ddiMounted;
    [_lock unlock];
    return mounted;
}

- (void)setDdiMounted:(BOOL)ddiMounted {
    [_lock lock];
    _ddiMounted = ddiMounted;
    [_lock unlock];
}

#pragma mark - Actions

- (void)selectPairingFile:(NSString *)path {
    self.pairingFilePath = path;
}

- (void)connect {
    [_lock lock];
    if (self.status == IdeviceStatusConnected || self.status == IdeviceStatusConnecting) {
        [[Logger sharedLogger] log:@"[Idevice] Already connected or connecting, ignoring request"];
        [_lock unlock];
        return;
    }
    self.status = IdeviceStatusConnecting;
    self.lastError = nil;
    [_lock unlock];

    [[Logger sharedLogger] log:@"[Idevice] Starting connection process..."];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [weakSelf _performConnect];
    });
}

- (void)_performConnect {
    NSString *ip = self.ipAddress;
    uint16_t port = self.port;
    NSString *pairingPath = self.pairingFilePath;

    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] Connecting to %s:%d", [ip UTF8String], port]];

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    if (inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr) <= 0) {
        [self _handleError:@"Invalid IP address"];
        return;
    }

    struct IdeviceFfiError *err = NULL;
    struct IdeviceProviderHandle *localProvider = NULL;
    struct IdevicePairingFile *localPairingFile = NULL;
    struct LockdowndClientHandle *localLockdown = NULL;
    struct HeartbeatClientHandle *localHb = NULL;

    // Phase 1: Read Pairing File
    if (pairingPath) {
        [[Logger sharedLogger] log:@"[Idevice] Reading pairing file..."];
        err = idevice_pairing_file_read([pairingPath UTF8String], &localPairingFile);
        if (err || !localPairingFile) {
            [self _handleFfiError:err fallback:@"Failed to read pairing file"];
            return;
        }
    } else {
        [self _handleError:@"Pairing file not selected"];
        return;
    }

    if (self.status != IdeviceStatusConnecting) { [self _cleanupLocalHandles:localProvider lockdown:localLockdown heartbeat:localHb pairingFile:localPairingFile]; return; }

    // Phase 2: Create Provider
    [[Logger sharedLogger] log:@"[Idevice] Creating TCP provider..."];
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, localPairingFile, "frappe-idevice", &localProvider);
    if (err || !localProvider) {
        [self _cleanupLocalHandles:NULL lockdown:NULL heartbeat:NULL pairingFile:localPairingFile];
        [self _handleFfiError:err fallback:@"Failed to create TCP provider"];
        return;
    }

    if (self.status != IdeviceStatusConnecting) { [self _cleanupLocalHandles:localProvider lockdown:localLockdown heartbeat:localHb pairingFile:localPairingFile]; return; }

    // Phase 3: Connect Lockdown
    [[Logger sharedLogger] log:@"[Idevice] Connecting to lockdown..."];
    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) {
        [self _cleanupLocalHandles:localProvider lockdown:NULL heartbeat:NULL pairingFile:localPairingFile];
        [self _handleFfiError:err fallback:@"Failed to connect to lockdown"];
        return;
    }

    if (self.status != IdeviceStatusConnecting) { [self _cleanupLocalHandles:localProvider lockdown:localLockdown heartbeat:localHb pairingFile:localPairingFile]; return; }

    // Phase 4: Start Lockdown Session
    [[Logger sharedLogger] log:@"[Idevice] Starting lockdown session..."];
    err = lockdownd_start_session(localLockdown, localPairingFile);
    if (err) {
        [self _cleanupLocalHandles:localProvider lockdown:localLockdown heartbeat:NULL pairingFile:localPairingFile];
        [self _handleFfiError:err fallback:@"Failed to start lockdown session"];
        return;
    }

    if (self.status != IdeviceStatusConnecting) { [self _cleanupLocalHandles:localProvider lockdown:localLockdown heartbeat:localHb pairingFile:localPairingFile]; return; }

    // Phase 5: Heartbeat
    [[Logger sharedLogger] log:@"[Idevice] Connecting heartbeat..."];
    err = heartbeat_connect(localProvider, &localHb);
    if (err || !localHb) {
        if (err) idevice_error_free(err);
        [[Logger sharedLogger] log:@"[Idevice] Heartbeat connection failed (non-fatal)"];
    }

    // Phase 6: DDI Check
    BOOL ddi = NO;
    struct ImageMounterHandle *mounter = NULL;
    err = image_mounter_connect(localProvider, &mounter);
    if (!err && mounter) {
        plist_t *devices = NULL;
        size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) ddi = (count > 0);
        else idevice_error_free(err);
        image_mounter_free(mounter);
    } else if (err) {
        idevice_error_free(err);
    }

    // Final Success: Assign to singleton state
    [_lock lock];
    if (self.status == IdeviceStatusConnecting) {
        self.pairingFile = localPairingFile;
        self.provider = localProvider;
        self.lockdownClient = localLockdown;
        self.heartbeatClient = localHb;
        self.heartbeatActive = (localHb != NULL);
        self.ddiMounted = ddi;
        self.status = IdeviceStatusConnected;

        if (localHb) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _startHeartbeatTimer];
            });
        }

        [[Logger sharedLogger] log:@"[Idevice] Successfully connected"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil];
        });
    } else {
        [[Logger sharedLogger] log:@"[Idevice] Connection cancelled during process"];
        [self _cleanupLocalHandles:localProvider lockdown:localLockdown heartbeat:localHb pairingFile:localPairingFile];
    }
    [_lock unlock];
}

- (void)_cleanupLocalHandles:(struct IdeviceProviderHandle *)p lockdown:(struct LockdowndClientHandle *)l heartbeat:(struct HeartbeatClientHandle *)h pairingFile:(struct IdevicePairingFile *)f {
    if (h) heartbeat_client_free(h);
    if (l) lockdownd_client_free(l);
    if (p) idevice_provider_free(p);
    if (f) idevice_pairing_file_free(f);
}

- (void)_startHeartbeatTimer {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(_sendHeartbeat) userInfo:nil repeats:YES];
}

- (void)_sendHeartbeat {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        struct IdeviceFfiError *err = NULL;
        [strongSelf->_lock lock];
        if (strongSelf.heartbeatClient) {
            err = heartbeat_send_polo(strongSelf.heartbeatClient);
        }
        [strongSelf->_lock unlock];

        if (err) {
            idevice_error_free(err);
            [[Logger sharedLogger] log:@"[Idevice] Heartbeat lost"];
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf disconnect];
                strongSelf.lastError = @"Heartbeat lost";
            });
        }
    });
}

- (void)disconnect {
    [[Logger sharedLogger] log:@"[Idevice] Disconnecting and cleaning up handles..."];

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

- (void)_handleFfiError:(struct IdeviceFfiError *)err fallback:(NSString *)fallback {
    NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: [fallback UTF8String]] : fallback;
    [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] FFI Error: %@", msg]];
    if (err) idevice_error_free(err);
    [self _handleError:msg];
}

- (void)_handleError:(NSString *)msg {
    [_lock lock];
    self.lastError = msg;
    self.status = IdeviceStatusError;
    [_lock unlock];

    [self disconnect];
}

- (void)dealloc {
    [self disconnect];
}

@end
