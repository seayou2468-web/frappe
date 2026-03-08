#import "IdeviceManager.h"
#import <arpa/inet.h>
#import "Logger.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

struct RsdSession {
    struct AdapterHandle *adapter;
    struct RsdHandshakeHandle *handshake;
};
typedef struct RsdSession RsdSession;

@interface IdeviceManager ()
@property (nonatomic, assign) IdeviceConnectionStatus status;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic, assign) struct IdeviceProviderHandle *provider;
@property (nonatomic, assign) struct LockdowndClientHandle *lockdownClient;
@property (nonatomic, assign) struct HeartbeatClientHandle *heartbeatClient;
@property (nonatomic, assign) struct IdevicePairingFile *pairingFile;
@property (nonatomic, assign) BOOL heartbeatActive;
@property (nonatomic, assign) BOOL ddiMounted;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, assign) struct SyslogRelayClientHandle *syslogClient;
@property (nonatomic, assign) BOOL syslogActive;

- (void)_performConnect;
- (void)_handleError:(NSString *)msg;
- (void)_handleFfiError:(struct IdeviceFfiError *)err fallback:(NSString *)fallback;
- (void)_startHeartbeatTimer;
- (void)_sendHeartbeat;
- (id)_convertPlistToObjC:(plist_t)node depth:(int)depth;
- (struct IdeviceFfiError *)_establishRsdSession:(RsdSession *)session;
- (void)_freeRsdSession:(RsdSession *)session;
@end

@implementation IdeviceManager {
    NSRecursiveLock *_lock;
    NSRecursiveLock *_rsdLock;
}

@synthesize status = _status;
@synthesize ipAddress = _ipAddress;
@synthesize port = _port;
@synthesize pairingFilePath = _pairingFilePath;
@synthesize lastError = _lastError;
@synthesize provider = _provider;
@synthesize lockdownClient = _lockdownClient;
@synthesize heartbeatClient = _heartbeatClient;
@synthesize pairingFile = _pairingFile;
@synthesize heartbeatActive = _heartbeatActive;
@synthesize ddiMounted = _ddiMounted;
@synthesize syslogClient = _syslogClient;
@synthesize syslogActive = _syslogActive;

+ (instancetype)sharedManager {
    static IdeviceManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init]; _rsdLock = [[NSRecursiveLock alloc] init];
        _status = IdeviceStatusDisconnected;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _ipAddress = [defaults stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
        _port = (uint16_t)([defaults integerForKey:@"IdevicePort"] ?: 62078);
        _pairingFilePath = [defaults stringForKey:@"IdevicePairingPath"];
    }
    return self;
}

- (void)dealloc { [self disconnect]; }

#pragma mark - Accessors

- (IdeviceConnectionStatus)status { [_lock lock]; IdeviceConnectionStatus s = _status; [_lock unlock]; return s; }
- (void)setStatus:(IdeviceConnectionStatus)status { [_lock lock]; _status = status; [_lock unlock]; }
- (NSString *)ipAddress { [_lock lock]; NSString *ip = [_ipAddress copy]; [_lock unlock]; return ip; }
- (void)setIpAddress:(NSString *)ipAddress { [_lock lock]; _ipAddress = [ipAddress copy]; [[NSUserDefaults standardUserDefaults] setObject:_ipAddress forKey:@"IdeviceIP"]; [_lock unlock]; }
- (uint16_t)port { [_lock lock]; uint16_t p = _port; [_lock unlock]; return p; }
- (void)setPort:(uint16_t)port { [_lock lock]; _port = port; [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)_port forKey:@"IdevicePort"]; [_lock unlock]; }
- (NSString *)pairingFilePath { [_lock lock]; NSString *path = [_pairingFilePath copy]; [_lock unlock]; return path; }
- (void)setPairingFilePath:(NSString *)pairingFilePath { [_lock lock]; _pairingFilePath = [pairingFilePath copy]; [[NSUserDefaults standardUserDefaults] setObject:_pairingFilePath forKey:@"IdevicePairingPath"]; [_lock unlock]; }
- (NSString *)lastError { [_lock lock]; NSString *err = [_lastError copy]; [_lock unlock]; return err; }
- (void)setLastError:(NSString *)lastError { [_lock lock]; _lastError = [lastError copy]; [_lock unlock]; }
- (BOOL)heartbeatActive { [_lock lock]; BOOL active = _heartbeatActive; [_lock unlock]; return active; }
- (void)setHeartbeatActive:(BOOL)heartbeatActive { [_lock lock]; _heartbeatActive = heartbeatActive; [_lock unlock]; }
- (BOOL)ddiMounted { [_lock lock]; BOOL mounted = _ddiMounted; [_lock unlock]; return mounted; }
- (void)setDdiMounted:(BOOL)ddiMounted { [_lock lock]; _ddiMounted = ddiMounted; [_lock unlock]; }

#pragma mark - Actions

- (void)selectPairingFile:(NSString *)path { self.pairingFilePath = path; }

- (void)connect {
    [_lock lock]; if (self.status == IdeviceStatusConnected || self.status == IdeviceStatusConnecting) { [_lock unlock]; return; }
    self.status = IdeviceStatusConnecting; self.lastError = nil; [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self _performConnect]; });
}

- (void)_performConnect {
    NSString *ipStr = self.ipAddress; uint16_t portNum = self.port; NSString *pairingPath = self.pairingFilePath;
    struct sockaddr_in sa; memset(&sa, 0, sizeof(sa)); sa.sin_family = AF_INET; sa.sin_port = htons(portNum);
    if (!ipStr || ipStr.length == 0 || inet_pton(AF_INET, [ipStr UTF8String], &sa.sin_addr) <= 0) { [self _handleError:@"IP形式不正"]; return; }
    struct IdeviceFfiError *err = NULL; struct IdeviceProviderHandle *localProvider = NULL;
    struct LockdowndClientHandle *localLockdown = NULL; struct HeartbeatClientHandle *localHb = NULL;
    struct IdevicePairingFile *pForProvider = NULL; struct IdevicePairingFile *pForSession = NULL;
    if (pairingPath && pairingPath.length > 0) {
        err = idevice_pairing_file_read([pairingPath UTF8String], &pForProvider);
        if (!err) err = idevice_pairing_file_read([pairingPath UTF8String], &pForSession);
        if (err || !pForProvider || !pForSession) {
            [self _handleFfiError:err fallback:@"ペアリングファイル読み込み失敗"];
            if (pForProvider) idevice_pairing_file_free(pForProvider); if (pForSession) idevice_pairing_file_free(pForSession); return;
        }
    } else { [self _handleError:@"ペアリングファイル未選択"]; return; }
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pForProvider, "frappe-idevice", &localProvider);
    if (err || !localProvider) { [self _handleFfiError:err fallback:@"プロバイダー作成失敗"]; if (pForProvider) idevice_pairing_file_free(pForProvider); if (pForSession) idevice_pairing_file_free(pForSession); return; }
    pForProvider = NULL; // Consumed
    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) { [self _handleFfiError:err fallback:@"Lockdown接続失敗"]; if (localProvider) idevice_provider_free(localProvider); if (pForSession) idevice_pairing_file_free(pForSession); return; }
    err = lockdownd_start_session(localLockdown, pForSession);
    if (err) { [self _handleFfiError:err fallback:@"セッション開始失敗"]; if (pForSession) idevice_pairing_file_free(pForSession); if (localLockdown) lockdownd_client_free(localLockdown); if (localProvider) idevice_provider_free(localProvider); return; }
    pForSession = NULL; // Consumed
    heartbeat_connect(localProvider, &localHb);
    BOOL ddiFlag = NO; struct ImageMounterHandle *mounter = NULL;
    if (image_mounter_connect(localProvider, &mounter) == NULL && mounter) {
        plist_t *devices = NULL; size_t count = 0;
        if (image_mounter_copy_devices(mounter, &devices, &count) == NULL && count > 0) { ddiFlag = YES; }
        if (devices) idevice_plist_array_free(devices, (uintptr_t)count);
        image_mounter_free(mounter);
    }
    [_lock lock]; _provider = localProvider; _lockdownClient = localLockdown; _heartbeatClient = localHb; _heartbeatActive = (localHb != NULL); _ddiMounted = ddiFlag; _status = IdeviceStatusConnected;
    if (localHb) { dispatch_async(dispatch_get_main_queue(), ^{ [self _startHeartbeatTimer]; }); }
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });
    [_lock unlock];
}

- (void)disconnect {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil; });
    [_lock lock];
    if (self.heartbeatClient) { heartbeat_client_free(self.heartbeatClient); _heartbeatClient = NULL; }
    if (self.lockdownClient) { lockdownd_client_free(self.lockdownClient); _lockdownClient = NULL; }
    if (self.provider) { idevice_provider_free(self.provider); _provider = NULL; }
    _status = IdeviceStatusDisconnected; _heartbeatActive = NO; _ddiMounted = NO; [self stopSyslogCapture]; [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });
}

- (void)_handleFfiError:(struct IdeviceFfiError *)err fallback:(NSString *)fallback {
    NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: [fallback UTF8String]] : fallback;
    if (err) idevice_error_free(err); [self _handleError:msg];
}

- (void)_handleError:(NSString *)msg { [_lock lock]; self.lastError = msg; self.status = IdeviceStatusError; [_lock unlock]; [self disconnect]; }

- (void)_startHeartbeatTimer { [self.heartbeatTimer invalidate]; self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(_sendHeartbeat) userInfo:nil repeats:YES]; }
- (void)_sendHeartbeat {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) ss = weakSelf; if (!ss) return; struct IdeviceFfiError *err = NULL;
        [ss->_lock lock]; if (ss.heartbeatClient) err = heartbeat_send_polo(ss.heartbeatClient); [ss->_lock unlock];
        if (err) { idevice_error_free(err); [ss disconnect]; }
    });
}

#pragma mark - RSD Management

- (struct IdeviceFfiError *)_establishRsdSession:(RsdSession *)session {
    memset(session, 0, sizeof(RsdSession)); [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) return NULL; [_rsdLock lock];
    struct CoreDeviceProxyHandle *proxy = NULL; struct IdeviceFfiError *err = core_device_proxy_connect(p, &proxy);
    if (!err && proxy) {
        uint16_t port = 0; err = core_device_proxy_get_server_rsd_port(proxy, &port);
        if (!err && port > 0) {
            err = core_device_proxy_create_tcp_adapter(proxy, &session->adapter);
            if (!err && session->adapter) {
                struct ReadWriteOpaque *stream = NULL; err = adapter_connect(session->adapter, port, &stream);
                if (!err && stream) { err = rsd_handshake_new(stream, &session->handshake); }
            }
        }
        core_device_proxy_free(proxy);
    }
    if (err) { [self _freeRsdSession:session]; } [_rsdLock unlock]; return err;
}

- (void)_freeRsdSession:(RsdSession *)session {
    [_rsdLock lock];
    if (session->handshake) { rsd_handshake_free(session->handshake); session->handshake = NULL; }
    if (session->adapter) { adapter_close(session->adapter); adapter_free(session->adapter); session->adapter = NULL; }
    [_rsdLock unlock];
}

#pragma mark - App Management

- (void)getAppListWithCompletion:(void (^)(NSArray *apps, NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:nil]); }); return; }
        struct AppServiceHandle *app = NULL; err = app_service_connect_rsd(rsd.adapter, rsd.handshake, &app);
        if (err || !app) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:14 userInfo:nil]); }); return; }
        struct AppListEntryC *raw = NULL; uintptr_t count = 0;
        err = app_service_list_apps(app, 1, 1, 1, 1, 1, &raw, &count);
        if (err) { idevice_error_free(err); app_service_free(app); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:3 userInfo:nil]); }); return; }
        NSMutableArray *apps = [NSMutableArray array];
        for (uintptr_t i = 0; i < count; i++) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            if (raw[i].name) d[@"CFBundleDisplayName"] = [NSString stringWithUTF8String:raw[i].name];
            if (raw[i].bundle_identifier) d[@"CFBundleIdentifier"] = [NSString stringWithUTF8String:raw[i].bundle_identifier];
            if (raw[i].version) d[@"CFBundleShortVersionString"] = [NSString stringWithUTF8String:raw[i].version];
            if (raw[i].path) d[@"Path"] = [NSString stringWithUTF8String:raw[i].path];
            d[@"ApplicationType"] = raw[i].is_first_party ? @"System" : @"User"; [apps addObject:d];
        }
        app_service_free_app_list(raw, count); app_service_free(app); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(apps, nil); });
    });
}

- (void)launchAppWithBundleId:(NSString *)bundleId arguments:(NSArray *)args environment:(NSDictionary *)env useJIT:(BOOL)useJIT completion:(void (^)(NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion([NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:20 userInfo:nil]); }); return; }
        struct AppServiceHandle *app = NULL; err = app_service_connect_rsd(rsd.adapter, rsd.handshake, &app);
        if (err || !app) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:14 userInfo:nil]); }); return; }
        uintptr_t argc = args.count; const char **argv = NULL;
        if (argc > 0) { argv = (const char **)calloc(argc, sizeof(char *)); for (uintptr_t i = 0; i < argc; i++) argv[i] = [args[i] UTF8String]; }
        struct LaunchResponseC *res = NULL;
        err = app_service_launch_app(app, [bundleId UTF8String], argv, argc, 1, useJIT ? 1 : 0, NULL, &res);
        if (argv) free(argv);
        if (err) { idevice_error_free(err); app_service_free(app); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:22 userInfo:nil]); }); return; }
        uint32_t pid = res ? res->pid : 0; if (res) app_service_free_launch_response(res);
        if (useJIT && pid > 0) {
            struct DebugProxyHandle *dp = NULL; err = debug_proxy_connect_rsd(rsd.adapter, rsd.handshake, &dp);
            if (!err && dp) {
                debug_proxy_set_ack_mode(dp, 0); char cmd[64]; snprintf(cmd, 64, "vAttach;%x", pid);
                struct DebugserverCommandHandle *c = debugserver_command_new(cmd, NULL, 0); char *r = NULL;
                debug_proxy_send_command(dp, c, &r); if (r) rsd_free_string(r); debugserver_command_free(c);
                struct DebugserverCommandHandle *cnt = debugserver_command_new("c", NULL, 0);
                debug_proxy_send_command(dp, cnt, &r); if (r) rsd_free_string(r); debugserver_command_free(cnt);
                debug_proxy_free(dp);
            } else if (err) idevice_error_free(err);
        }
        app_service_free(app); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)uninstallAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion([NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:20 userInfo:nil]); }); return; }
        struct AppServiceHandle *app = NULL; err = app_service_connect_rsd(rsd.adapter, rsd.handshake, &app);
        if (err || !app) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:14 userInfo:nil]); }); return; }
        err = app_service_uninstall_app(app, [bundleId UTF8String]);
        app_service_free(app); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { completion([NSError errorWithDomain:@"Idevice" code:25 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:err->message ?: "削除失敗"]}]); idevice_error_free(err); }
            else completion(nil);
        });
    });
}

#pragma mark - RSD Support

- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:nil]); }); return; }
        struct CRsdServiceArray *raw = NULL; err = rsd_get_services(rsd.handshake, &raw);
        if (err || !raw) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:11 userInfo:nil]); }); return; }
        NSMutableArray *res = [NSMutableArray array];
        for (size_t i = 0; i < raw->count; i++) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary]; if (raw->services[i].name) d[@"name"] = [NSString stringWithUTF8String:raw->services[i].name];
            d[@"port"] = @(raw->services[i].port); d[@"uses_remote_xpc"] = @(raw->services[i].uses_remote_xpc); [res addObject:d];
        }
        rsd_free_services(raw); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(res, nil); });
    });
}

- (void)getProcessListWithCompletion:(void (^)(NSArray *processes, NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:nil]); }); return; }
        struct AppServiceHandle *app = NULL; err = app_service_connect_rsd(rsd.adapter, rsd.handshake, &app);
        if (err || !app) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:14 userInfo:nil]); }); return; }
        struct ProcessTokenC *raw = NULL; uintptr_t count = 0; err = app_service_list_processes(app, &raw, &count);
        if (err) { idevice_error_free(err); app_service_free(app); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:15 userInfo:nil]); }); return; }
        NSMutableArray *res = [NSMutableArray array];
        for (uintptr_t i = 0; i < count; i++) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary]; d[@"pid"] = @(raw[i].pid);
            if (raw[i].executable_url) d[@"path"] = [NSString stringWithUTF8String:raw[i].executable_url]; [res addObject:d];
        }
        app_service_free_process_list(raw, count); app_service_free(app); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(res, nil); });
    });
}

- (void)captureSysdiagnoseWithCompletion:(void (^)(NSString *path, NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:nil]); }); return; }
        struct DiagnosticsServiceHandle *diag = NULL; err = diagnostics_service_connect_rsd(rsd.adapter, rsd.handshake, &diag);
        if (err || !diag) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:11 userInfo:nil]); }); return; }
        char *file_c = NULL; uintptr_t exp = 0; struct SysdiagnoseStreamHandle *ssh = NULL;
        err = diagnostics_service_capture_sysdiagnose(diag, false, &file_c, &exp, &ssh);
        if (err || !ssh) { if (err) idevice_error_free(err); diagnostics_service_free(diag); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:12 userInfo:nil]); }); return; }
        NSString *name = file_c ? [NSString stringWithUTF8String:file_c] : @"sysdiagnose.tar.gz"; if (file_c) rsd_free_string(file_c);
        NSString *path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:name];
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) { sysdiagnose_stream_free(ssh); diagnostics_service_free(diag); [self _freeRsdSession:&rsd]; return; }
        uint8_t *buf = NULL; uintptr_t blen = 0;
        while (sysdiagnose_stream_next(ssh, &buf, &blen) == NULL && buf && blen > 0) { [fh writeData:[NSData dataWithBytes:buf length:blen]]; idevice_data_free(buf, blen); }
        [fh closeFile]; sysdiagnose_stream_free(ssh); diagnostics_service_free(diag); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(path, nil); });
    });
}

- (void)takeScreenshotWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (!err) {
            struct RemoteServerHandle *rs = NULL; if (remote_server_connect_rsd(rsd.adapter, rsd.handshake, &rs) == NULL && rs) {
                struct ScreenshotClientHandle *sc = NULL; if (screenshot_client_new(rs, &sc) == NULL && sc) {
                    uint8_t *data = NULL; uintptr_t len = 0;
                    if (screenshot_client_take_screenshot(sc, &data, &len) == NULL && data && len > 0) {
                        UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:data length:len]]; idevice_data_free(data, len); screenshot_client_free(sc); remote_server_free(rs); [self _freeRsdSession:&rsd];
                        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); }); return;
                    }
                    if (data) idevice_data_free(data, len); screenshot_client_free(sc);
                }
                remote_server_free(rs);
            }
            [self _freeRsdSession:&rsd];
        } else if (err) idevice_error_free(err);
        struct ScreenshotrClientHandle *src = NULL;
        if (screenshotr_connect(p, &src) == NULL && src) {
            struct ScreenshotData sd; memset(&sd, 0, sizeof(sd));
            if (screenshotr_take_screenshot(src, &sd) == NULL && sd.data && sd.length > 0) {
                UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:sd.data length:sd.length]]; screenshotr_screenshot_free(sd); screenshotr_client_free(src);
                if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); }); return;
            }
            screenshotr_client_free(src);
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:18 userInfo:nil]); });
    });
}

#pragma mark - Syslog

- (void)startSyslogCaptureWithCallback:(void (^)(NSString *line))callback {
    [_lock lock]; if (!self.provider || self.syslogActive) { [_lock unlock]; return; }
    struct IdeviceProviderHandle *p = self.provider; self.syslogActive = YES; [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct SyslogRelayClientHandle *c = NULL; if (syslog_relay_connect_tcp(p, &c) == NULL && c) {
            [self->_lock lock]; self.syslogClient = c; [_lock unlock];
            while (true) {
                [_lock lock]; BOOL act = self.syslogActive; struct SyslogRelayClientHandle *cur = self.syslogClient; [_lock unlock];
                if (!act || !cur) break;
                char *line = NULL; if (syslog_relay_next(cur, &line) != NULL) break;
                if (line) { NSString *nl = [NSString stringWithUTF8String:line]; if (callback) dispatch_async(dispatch_get_main_queue(), ^{ callback(nl); }); rsd_free_string(line); }
            }
        }
        [self stopSyslogCapture];
    });
}

- (void)stopSyslogCapture { [_lock lock]; self.syslogActive = NO; if (self.syslogClient) { syslog_relay_client_free(self.syslogClient); self.syslogClient = NULL; } [_lock unlock]; }

#pragma mark - Plist Utils

- (id)_convertPlistToObjC:(plist_t)node depth:(int)depth {
    if (!node || depth > 20) return nil;
    plist_type t = plist_get_node_type(node);
    if (t == PLIST_BOOLEAN) { uint8_t v = 0; plist_get_bool_val(node, &v); return @((BOOL)v); }
    if (t == PLIST_INT) { uint64_t v = 0; plist_get_uint_val(node, &v); return @(v); }
    if (t == PLIST_REAL) { double v = 0; plist_get_real_val(node, &v); return @(v); }
    if (t == PLIST_STRING || t == PLIST_KEY) { char *v = NULL; (t == PLIST_STRING) ? plist_get_string_val(node, &v) : plist_get_key_val(node, &v); NSString *s = v ? [NSString stringWithUTF8String:v] : @""; if (v) plist_mem_free(v); return s; }
    if (t == PLIST_ARRAY) {
        uint32_t sz = plist_array_get_size(node); NSMutableArray *a = [NSMutableArray arrayWithCapacity:sz];
        for (uint32_t i = 0; i < sz && i < 1000; i++) { id o = [self _convertPlistToObjC:[self plist_array_get_item:node index:i] depth:depth+1]; if (o) [a addObject:o]; }
        return a;
    }
    if (t == PLIST_DICT) {
        uint32_t sz = plist_dict_get_size(node); NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:sz];
        plist_dict_iter it = NULL; plist_dict_new_iter(node, &it);
        if (it) { char *k = NULL; plist_t sub = NULL; while (true) { plist_dict_next_item(node, it, &k, &sub); if (!k) break; NSString *nk = [NSString stringWithUTF8String:k]; id o = [self _convertPlistToObjC:sub depth:depth+1]; if (nk && o) d[nk] = o; plist_mem_free(k); } free(it); }
        return d;
    }
    if (t == PLIST_DATA) { uint64_t l = 0; const char *p = plist_get_data_ptr(node, &l); return (p && l > 0 && l < 5000000) ? [NSData dataWithBytes:p length:(NSUInteger)l] : [NSData data]; }
    return nil;
}

- (plist_t)plist_array_get_item:(plist_t)node index:(uint32_t)i { return plist_array_get_item(node, i); }

@end
