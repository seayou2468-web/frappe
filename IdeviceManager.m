#import "IdeviceManager.h"
#import <arpa/inet.h>
#import "Logger.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

struct RsdSession {
    struct AdapterHandle *adapter;
    struct RsdHandshakeHandle *handshake;
    struct ReadWriteOpaque *stream;
    struct CoreDeviceProxyHandle *proxy;
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
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        _rsdLock = [[NSRecursiveLock alloc] init];
        _status = IdeviceStatusDisconnected;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _ipAddress = [defaults stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
        _port = (uint16_t)([defaults integerForKey:@"IdevicePort"] ?: 62078);
        _pairingFilePath = [defaults stringForKey:@"IdevicePairingPath"];
    }
    return self;
}

- (void)dealloc {
    [self disconnect];
}

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
    [_lock lock];
    if (self.status == IdeviceStatusConnected || self.status == IdeviceStatusConnecting) { [_lock unlock]; return; }
    self.status = IdeviceStatusConnecting; self.lastError = nil;
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self _performConnect]; });
}

- (void)_performConnect {
    NSString *ipStr = self.ipAddress; uint16_t portNum = self.port; NSString *pairingPath = self.pairingFilePath;
    struct sockaddr_in sa; memset(&sa, 0, sizeof(sa)); sa.sin_family = AF_INET; sa.sin_port = htons(portNum);
    if (!ipStr || ipStr.length == 0 || inet_pton(AF_INET, [ipStr UTF8String], &sa.sin_addr) <= 0) { [self _handleError:@"IPアドレスの形式が正しくありません"]; return; }
    struct IdeviceFfiError *err = NULL; struct IdeviceProviderHandle *localProvider = NULL;
    struct LockdowndClientHandle *localLockdown = NULL; struct HeartbeatClientHandle *localHb = NULL;
    struct IdevicePairingFile *pairingForProvider = NULL; struct IdevicePairingFile *pairingForSession = NULL;
    if (pairingPath && pairingPath.length > 0) {
        err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForProvider);
        if (!err) err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForSession);
        if (err || !pairingForProvider || !pairingForSession) {
            [self _handleFfiError:err fallback:@"ペアリングファイルの読み込みに失敗しました"];
            if (pairingForProvider) idevice_pairing_file_free(pairingForProvider);
            if (pairingForSession) idevice_pairing_file_free(pairingForSession);
            return;
        }
    } else {
        [self _handleError:@"ペアリングファイルが選択されていません。"];
        return;
    }
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingForProvider, "frappe-idevice", &localProvider);
    if (err || !localProvider) {
        [self _handleFfiError:err fallback:@"プロバイダーの作成に失敗しました"];
        if (pairingForProvider) idevice_pairing_file_free(pairingForProvider);
        if (pairingForSession) idevice_pairing_file_free(pairingForSession);
        return;
    }
    pairingForProvider = NULL; // Consumed
    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) {
        [self _handleFfiError:err fallback:@"Lockdownへの接続に失敗しました"];
        if (localProvider) idevice_provider_free(localProvider);
        if (pairingForSession) idevice_pairing_file_free(pairingForSession);
        return;
    }
    err = lockdownd_start_session(localLockdown, pairingForSession);
    if (err) {
        [self _handleFfiError:err fallback:@"セッションの開始に失敗しました"];
        if (pairingForSession) idevice_pairing_file_free(pairingForSession);
        if (localLockdown) lockdownd_client_free(localLockdown);
        if (localProvider) idevice_provider_free(localProvider);
        return;
    }
    pairingForSession = NULL; // Consumed
    heartbeat_connect(localProvider, &localHb);
    [_lock lock];
    _provider = localProvider; _lockdownClient = localLockdown; _heartbeatClient = localHb;
    _heartbeatActive = (localHb != NULL); _status = IdeviceStatusConnected;
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
    _status = IdeviceStatusDisconnected; _heartbeatActive = NO;
    [self stopSyslogCapture];
    [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });
}

- (void)_handleFfiError:(struct IdeviceFfiError *)err fallback:(NSString *)fallback {
    NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: [fallback UTF8String]] : fallback;
    if (err) idevice_error_free(err); [self _handleError:msg];
}

- (void)_handleError:(NSString *)msg {
    [_lock lock]; self.lastError = msg; self.status = IdeviceStatusError; [_lock unlock];
    [self disconnect];
}

- (void)_startHeartbeatTimer {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(_sendHeartbeat) userInfo:nil repeats:YES];
}

- (void)_sendHeartbeat {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf; if (!strongSelf) return;
        struct IdeviceFfiError *err = NULL;
        [strongSelf->_lock lock]; if (strongSelf.heartbeatClient) err = heartbeat_send_polo(strongSelf.heartbeatClient); [strongSelf->_lock unlock];
        if (err) { idevice_error_free(err); [strongSelf disconnect]; }
    });
}

#pragma mark - RSD Management

- (struct IdeviceFfiError *)_establishRsdSession:(RsdSession *)session {
    memset(session, 0, sizeof(RsdSession));
    [_lock lock]; struct IdeviceProviderHandle *provider = self.provider; [_lock unlock];
    if (!provider) return NULL;
    [_rsdLock lock];
    struct IdeviceFfiError *err = core_device_proxy_connect(provider, &session->proxy);
    if (!err && session->proxy) {
        uint16_t rsd_port = 0;
        err = core_device_proxy_get_server_rsd_port(session->proxy, &rsd_port);
        if (!err && rsd_port > 0) {
            err = core_device_proxy_create_tcp_adapter(session->proxy, &session->adapter);
            session->proxy = NULL; // Consumed
            if (!err && session->adapter) {
                err = adapter_connect(session->adapter, rsd_port, &session->stream);
                if (!err && session->stream) {
                    err = rsd_handshake_new(session->stream, &session->handshake);
                    session->stream = NULL; // Consumed
                    if (!err && session->handshake) { [_rsdLock unlock]; return NULL; }
                }
            }
        }
    }
    [self _freeRsdSession:session]; [_rsdLock unlock]; return err;
}

- (void)_freeRsdSession:(RsdSession *)session {
    [_rsdLock lock];
    if (session->handshake) rsd_handshake_free(session->handshake);
    if (session->stream) idevice_stream_free(session->stream);
    if (session->adapter) { adapter_close(session->adapter); adapter_free(session->adapter); }
    if (session->proxy) core_device_proxy_free(session->proxy);
    memset(session, 0, sizeof(RsdSession));
    [_rsdLock unlock];
}

#pragma mark - App Management

- (void)getAppListWithCompletion:(void (^)(NSArray *apps, NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct InstallationProxyClientHandle *client = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(p, &client);
        if (err || !client) { if (err) idevice_error_free(err); if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:2 userInfo:nil]); }); return; }
        void *out_res = NULL; size_t out_len = 0;
        err = installation_proxy_get_apps(client, "Any", NULL, 0, &out_res, &out_len);
        installation_proxy_client_free(client);
        if (err) { idevice_error_free(err); if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:3 userInfo:nil]); }); return; }
        NSMutableArray *apps = [NSMutableArray array];
        if (out_res && out_len > 0) {
            plist_t *handles = (plist_t *)out_res;
            for (size_t i = 0; i < out_len; i++) { id obj = [self _convertPlistToObjC:handles[i] depth:0]; if (obj) [apps addObject:obj]; }
            idevice_plist_array_free(handles, (uintptr_t)out_len);
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(apps, nil); });
    });
}

- (void)launchAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    [self launchAppWithBundleId:bundleId arguments:nil environment:nil useJIT:NO completion:completion];
}

- (void)launchAppWithBundleId:(NSString *)bundleId arguments:(NSArray *)args environment:(NSDictionary *)env useJIT:(BOOL)useJIT completion:(void (^)(NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *provider = self.provider; [_lock unlock];
    if (!provider) { if (completion) completion([NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:20 userInfo:nil]); }); return; }
        struct RemoteServerHandle *rs = NULL;
        err = remote_server_connect_rsd(rsd.adapter, rsd.handshake, &rs);
        if (err || !rs) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:23 userInfo:nil]); }); return; }
        struct ProcessControlHandle *pc = NULL;
        err = process_control_new(rs, &pc);
        if (err || !pc) { if (err) idevice_error_free(err); remote_server_free(rs); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:24 userInfo:nil]); }); return; }
        uintptr_t argc = args.count; const char **argv = NULL;
        if (argc > 0) { argv = (const char **)calloc(argc, sizeof(char *)); for (uintptr_t i = 0; i < argc; i++) argv[i] = [args[i] UTF8String]; }
        uintptr_t envc = env.count; const char **envv = NULL;
        if (envc > 0) {
            envv = (const char **)calloc(envc, sizeof(char *));
            NSArray *keys = [env allKeys];
            for (uintptr_t i = 0; i < envc; i++) { NSString *kv = [NSString stringWithFormat:@"%@=%@", keys[i], env[keys[i]]]; envv[i] = strdup([kv UTF8String]); }
        }
        uint64_t pid = 0;
        err = process_control_launch_app(pc, [bundleId UTF8String], envv, envc, argv, argc, useJIT, true, &pid);
        if (argv) free(argv); if (envv) { for (uintptr_t i = 0; i < envc; i++) free((void *)envv[i]); free(envv); }
        if (err) { idevice_error_free(err); process_control_free(pc); remote_server_free(rs); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:22 userInfo:nil]); }); return; }
        if (useJIT && pid > 0) {
            struct DebugProxyHandle *dp = NULL;
            err = debug_proxy_connect_rsd(rsd.adapter, rsd.handshake, &dp);
            if (!err && dp) {
                debug_proxy_set_ack_mode(dp, 0);
                char attach[64]; snprintf(attach, 64, "vAttach;%llx", pid);
                struct DebugserverCommandHandle *cmd = debugserver_command_new(attach, NULL, 0);
                char *resp = NULL; debug_proxy_send_command(dp, cmd, &resp); if (resp) rsd_free_string(resp); debugserver_command_free(cmd);
                struct DebugserverCommandHandle *cont = debugserver_command_new("c", NULL, 0);
                debug_proxy_send_command(dp, cont, &resp); if (resp) rsd_free_string(resp); debugserver_command_free(cont);
                debug_proxy_free(dp);
            } else if (err) idevice_error_free(err);
        }
        process_control_free(pc); remote_server_free(rs); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

#pragma mark - RSD Support

- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion {
    [_lock lock]; struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    if (!p) { if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:nil]); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:nil]); }); return; }
        struct CRsdServiceArray *raw = NULL;
        err = rsd_get_services(rsd.handshake, &raw);
        if (err || !raw) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:11 userInfo:nil]); }); return; }
        NSMutableArray *res = [NSMutableArray array];
        for (size_t i = 0; i < raw->count; i++) {
            struct CRsdService *s = &raw->services[i]; NSMutableDictionary *d = [NSMutableDictionary dictionary];
            if (s->name) d[@"name"] = [NSString stringWithUTF8String:s->name];
            d[@"port"] = @(s->port); d[@"uses_remote_xpc"] = @(s->uses_remote_xpc);
            [res addObject:d];
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
        struct AppServiceHandle *app = NULL;
        err = app_service_connect_rsd(rsd.adapter, rsd.handshake, &app);
        if (err || !app) { if (err) idevice_error_free(err); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:14 userInfo:nil]); }); return; }
        struct ProcessTokenC *raw = NULL; uintptr_t count = 0;
        err = app_service_list_processes(app, &raw, &count);
        if (err) { idevice_error_free(err); app_service_free(app); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:15 userInfo:nil]); }); return; }
        NSMutableArray *res = [NSMutableArray array];
        for (uintptr_t i = 0; i < count; i++) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            d[@"pid"] = @(raw[i].pid);
            if (raw[i].executable_url) d[@"path"] = [NSString stringWithUTF8String:raw[i].executable_url];
            [res addObject:d];
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
        struct DiagnosticsServiceHandle *diag = NULL;
        err = diagnostics_service_connect_rsd(rsd.adapter, rsd.handshake, &diag);
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
            struct RemoteServerHandle *rs = NULL;
            if (remote_server_connect_rsd(rsd.adapter, rsd.handshake, &rs) == NULL && rs) {
                struct ScreenshotClientHandle *sc = NULL;
                if (screenshot_client_new(rs, &sc) == NULL && sc) {
                    uint8_t *data = NULL; uintptr_t len = 0;
                    if (screenshot_client_take_screenshot(sc, &data, &len) == NULL && data && len > 0) {
                        UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:data length:len]];
                        idevice_data_free(data, len); screenshot_client_free(sc); remote_server_free(rs); [self _freeRsdSession:&rsd];
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
                UIImage *img = [UIImage imageWithData:[NSData dataWithBytes:sd.data length:sd.length]];
                screenshotr_screenshot_free(sd); screenshotr_client_free(src);
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
        struct SyslogRelayClientHandle *c = NULL;
        if (syslog_relay_connect_tcp(p, &c) == NULL && c) {
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

- (void)stopSyslogCapture {
    [_lock lock]; self.syslogActive = NO; if (self.syslogClient) { syslog_relay_client_free(self.syslogClient); self.syslogClient = NULL; } [_lock unlock];
}

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
        for (uint32_t i = 0; i < sz && i < 1000; i++) { id o = [self _convertPlistToObjC:plist_array_get_item(node, i) depth:depth+1]; if (o) [a addObject:o]; }
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

@end
