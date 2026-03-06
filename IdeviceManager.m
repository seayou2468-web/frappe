#import "IdeviceManager.h"
#import <arpa/inet.h>
#import "Logger.h"

@interface IdeviceManager ()
@property (nonatomic, assign) IdeviceConnectionStatus status;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct LockdowndClientHandle *lockdownClient;
@property (nonatomic, assign) struct HeartbeatClientHandle *heartbeatClient;
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
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _ipAddress = [defaults stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
        _port = [defaults integerForKey:@"IdevicePort"] ?: 62078;
        _pairingFilePath = [defaults stringForKey:@"IdevicePairingPath"];
        _status = IdeviceStatusDisconnected;
    }
    return self;
}

- (void)setIpAddress:(NSString *)ipAddress {
    _ipAddress = ipAddress;
    [[NSUserDefaults standardUserDefaults] setObject:ipAddress forKey:@"IdeviceIP"];
}

- (void)setPort:(uint16_t)port {
    _port = port;
    [[NSUserDefaults standardUserDefaults] setInteger:port forKey:@"IdevicePort"];
}

- (void)selectPairingFile:(NSString *)path {
    _pairingFilePath = path;
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:@"IdevicePairingPath"];
}

- (void)connect {
    if (self.status == IdeviceStatusConnected || self.status == IdeviceStatusConnecting) return;

    self.status = IdeviceStatusConnecting;
    self.lastError = nil;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self _performConnect];
    });
}

- (void)_performConnect {
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
        err = idevice_pairing_file_read([self.pairingFilePath UTF8String], &pairingFile);
        if (err) {
            [self _handleFfiError:err];
            return;
        }
    } else {
        [self _handleError:@"Pairing file not selected"];
        return;
    }

    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingFile, "frappe-idevice", &provider);
    if (err) {
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        [self _handleFfiError:err];
        return;
    }
    self.provider = provider;

    struct LockdowndClientHandle *lockdown = NULL;
    err = lockdownd_connect(provider, &lockdown);
    if (err) {
        if (pairingFile) idevice_pairing_file_free(pairingFile);
        [self _handleFfiError:err];
        return;
    }
    self.lockdownClient = lockdown;

    err = lockdownd_start_session(lockdown, pairingFile);
    if (pairingFile) idevice_pairing_file_free(pairingFile);
    if (err) {
        [self _handleFfiError:err];
        return;
    }

    // Connect Heartbeat
    struct HeartbeatClientHandle *hb = NULL;
    err = heartbeat_connect(provider, &hb);
    if (!err) {
        self.heartbeatClient = hb;
        self.heartbeatActive = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _startHeartbeatTimer];
        });
    }

    // Try to mount DDI if needed
    [self _checkAndMountDDI];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.status = IdeviceStatusConnected;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil];
    });
}

- (void)_checkAndMountDDI {
    // Basic implementation to check if DDI is mounted
    struct ImageMounterHandle *mounter = NULL;
    struct IdeviceFfiError *err = image_mounter_connect(self.provider, &mounter);
    if (!err) {
        plist_t *devices = NULL;
        size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err && count > 0) {
            self.ddiMounted = YES;
        } else {
            self.ddiMounted = NO;
        }
        image_mounter_free(mounter);
    }
}

- (void)_startHeartbeatTimer {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(_sendHeartbeat) userInfo:nil repeats:YES];
}

- (void)_sendHeartbeat {
    if (!self.heartbeatClient) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct IdeviceFfiError *err = heartbeat_send_polo(self.heartbeatClient);
        if (err) {
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self disconnect];
                self.lastError = @"Heartbeat lost";
            });
        }
    });
}

- (void)disconnect {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = nil;

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

    self.status = IdeviceStatusDisconnected;
    self.heartbeatActive = NO;
    self.ddiMounted = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil];
    });
}

- (void)_handleFfiError:(struct IdeviceFfiError *)err {
    NSString *msg = [NSString stringWithUTF8String:err->message ?: "Unknown error"];
    idevice_error_free(err);
    [self _handleError:msg];
}

- (void)_handleError:(NSString *)msg {
    self.lastError = msg;
    self.status = IdeviceStatusError;
    [self disconnect];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil];
    });
}

@end
