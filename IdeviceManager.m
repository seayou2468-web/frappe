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

#pragma mark - Thread-safe Accessors

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
        [self _handleError:@"ペアリングファイルが選択されていません。設定から選択してください。"];
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
        [self _handleFfiError:err fallback:@"Lockdownサービスへの接続に失敗しました"];
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
    err = heartbeat_connect(localProvider, &localHb); if (err) { idevice_error_free(err); }
    BOOL ddiFlag = NO; struct ImageMounterHandle *mounter = NULL;
    err = image_mounter_connect(localProvider, &mounter);
    if (!err && mounter) {
        plist_t *devices = NULL; size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) { ddiFlag = (count > 0); if (devices) idevice_plist_array_free(devices, (uintptr_t)count); }
        else { idevice_error_free(err); }
        image_mounter_free(mounter);
    } else if (err) { idevice_error_free(err); }
    [_lock lock];
    if (self.status == IdeviceStatusConnecting) {
        _provider = localProvider; _lockdownClient = localLockdown;
        _heartbeatClient = localHb; _heartbeatActive = (localHb != NULL); _ddiMounted = ddiFlag; _status = IdeviceStatusConnected;
        if (localHb) { dispatch_async(dispatch_get_main_queue(), ^{ [self _startHeartbeatTimer]; }); }
        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });
    } else {
        if (localHb) heartbeat_client_free(localHb);
        if (localLockdown) lockdownd_client_free(localLockdown);
        if (localProvider) idevice_provider_free(localProvider);
    }
    [_lock unlock];
}

- (void)disconnect {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil; });
    [_lock lock];
    if (self.heartbeatClient) { heartbeat_client_free(self.heartbeatClient); _heartbeatClient = NULL; }
    if (self.lockdownClient) { lockdownd_client_free(self.lockdownClient); _lockdownClient = NULL; }
    if (self.provider) { idevice_provider_free(self.provider); _provider = NULL; }
    if (self.pairingFile) { idevice_pairing_file_free(self.pairingFile); _pairingFile = NULL; }
    _status = IdeviceStatusDisconnected; _heartbeatActive = NO; _ddiMounted = NO;
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
        if (err) { idevice_error_free(err); [strongSelf disconnect]; strongSelf.lastError = @"ハートビートが途切れました"; }
    });
}

#pragma mark - RSD Management

- (struct IdeviceFfiError *)_establishRsdSession:(RsdSession *)session {
    memset(session, 0, sizeof(RsdSession));
    [_lock lock]; struct IdeviceProviderHandle *provider = self.provider; [_lock unlock];
    if (!provider) return NULL;

    [_rsdLock lock];
    struct IdeviceFfiError *err = NULL;
    struct CoreDeviceProxyHandle *proxy = NULL;

    err = core_device_proxy_connect(provider, &proxy);
    if (err || !proxy) {
        [_rsdLock unlock];
        return err;
    }
    session->proxy = proxy;

    uint16_t rsd_port = 0;
    err = core_device_proxy_get_server_rsd_port(proxy, &rsd_port);
    if (err || rsd_port == 0) {
        [self _freeRsdSession:session];
        [_rsdLock unlock];
        return err;
    }

    struct AdapterHandle *adapter = NULL;
    err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
    session->proxy = NULL; // Consumed
    if (err || !adapter) {
        [self _freeRsdSession:session];
        [_rsdLock unlock];
        return err;
    }
    session->adapter = adapter;

    struct ReadWriteOpaque *stream = NULL;
    err = adapter_connect(adapter, rsd_port, &stream);
    if (err || !stream) {
        [self _freeRsdSession:session];
        [_rsdLock unlock];
        return err;
    }
    session->stream = stream;

    struct RsdHandshakeHandle *handshake = NULL;
    err = rsd_handshake_new(stream, &handshake);
    session->stream = NULL; // Consumed
    if (err || !handshake) {
        [self _freeRsdSession:session];
        [_rsdLock unlock];
        return err;
    }
    session->handshake = handshake;

    [_rsdLock unlock];
    return NULL;
}

- (void)_freeRsdSession:(RsdSession *)session {
    [_rsdLock lock];
    if (session->handshake) {
        rsd_handshake_free(session->handshake);
        session->handshake = NULL;
    }
    if (session->stream) {
        idevice_stream_free(session->stream);
        session->stream = NULL;
    }
    if (session->adapter) {
        struct IdeviceFfiError *e = adapter_close(session->adapter);
        if (e) idevice_error_free(e);
        adapter_free(session->adapter);
        session->adapter = NULL;
    }
    if (session->proxy) {
        core_device_proxy_free(session->proxy);
        session->proxy = NULL;
    }
    [_rsdLock unlock];
}

#pragma mark - App Management

- (void)getAppListWithCompletion:(void (^)(NSArray *apps, NSError *error))completion {
    [_lock lock]; if (self.status != IdeviceStatusConnected || !self.provider) { [_lock unlock]; if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]); return; }
    struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct InstallationProxyClientHandle *client = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(p, &client);
        if (err || !client) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "InstProxyへの接続に失敗しました"] : @"InstProxyへの接続に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:2 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        void *out_result = NULL; size_t out_result_len = 0;
        err = installation_proxy_get_apps(client, "Any", NULL, 0, &out_result, &out_result_len);
        installation_proxy_client_free(client);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "アプリ一覧の取得に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:3 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        NSMutableArray *finalApps = [NSMutableArray array];
        if (out_result && out_result_len > 0) {
            plist_t *handles = (plist_t *)out_result;
            for (size_t i = 0; i < out_result_len; i++) { if (handles[i]) { id obj = [self _convertPlistToObjC:handles[i] depth:0]; if (obj) [finalApps addObject:obj]; } }
            idevice_plist_array_free(handles, (uintptr_t)out_result_len);
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(finalApps, nil); });
    });
}

- (void)launchAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    [_lock lock]; if (self.status != IdeviceStatusConnected || !self.provider) { [_lock unlock]; if (completion) completion([NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]); return; }
    struct IdeviceProviderHandle *p = self.provider; [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint16_t service_port = 0; bool ssl = false;
        [_lock lock]; struct LockdowndClientHandle *l = self.lockdownClient; [_lock unlock];
        struct IdeviceFfiError *err = lockdownd_start_service(l, "com.apple.mobile.installation_proxy", &service_port, &ssl);
        if (err) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:4 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:err->message ?: "サービスの開始に失敗しました"]}]); }); idevice_error_free(err); return; }
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"Launching %@...", bundleId]];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

#pragma mark - RSD Support

- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion {
    [_lock lock]; if (self.status != IdeviceStatusConnected || !self.provider) { [_lock unlock]; if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]); return; }
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err || !rsd.handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDセッションの確立に失敗しました"] : @"RSDセッションの確立に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        struct CRsdServiceArray *rawServices = NULL;
        err = rsd_get_services(rsd.handshake, &rawServices);
        if (err || !rawServices) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDサービスの取得に失敗しました"] : @"RSDサービスの取得に失敗しました";
            if (err) idevice_error_free(err); [self _freeRsdSession:&rsd];
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        NSMutableArray *results = [NSMutableArray array];
        for (size_t i = 0; i < rawServices->count; i++) {
            struct CRsdService *s = &rawServices->services[i]; NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            if (s->name && strlen(s->name) > 0) dict[@"name"] = [NSString stringWithUTF8String:s->name];
            dict[@"port"] = @(s->port); dict[@"uses_remote_xpc"] = @(s->uses_remote_xpc);
            if (s->features_count > 0 && s->features) {
                NSMutableArray *fs = [NSMutableArray array];
                for (size_t j = 0; j < s->features_count; j++) { if (s->features[j]) [fs addObject:[NSString stringWithUTF8String:s->features[j]]]; }
                dict[@"features"] = [fs componentsJoinedByString:@", "]; dict[@"entitlement"] = dict[@"features"];
            }
            [results addObject:dict];
        }
        rsd_free_services(rawServices); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(results, nil); });
    });
}

- (void)getProcessListWithCompletion:(void (^)(NSArray *processes, NSError *error))completion {
    [_lock lock]; if (self.status != IdeviceStatusConnected || !self.provider) { [_lock unlock]; if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]); return; }
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err || !rsd.handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDセッションの確立に失敗しました"] : @"RSDセッションの確立に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        struct AppServiceHandle *appSvc = NULL;
        err = app_service_connect_rsd(rsd.adapter, rsd.handshake, &appSvc);
        if (err || !appSvc) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "AppServiceへの接続に失敗しました"] : @"AppServiceへの接続に失敗しました";
            if (err) idevice_error_free(err); [self _freeRsdSession:&rsd];
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:14 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        struct ProcessTokenC *rawProcesses = NULL; uintptr_t count = 0;
        err = app_service_list_processes(appSvc, &rawProcesses, &count);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "プロセス一覧の取得に失敗しました"];
            idevice_error_free(err); app_service_free(appSvc); [self _freeRsdSession:&rsd];
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:15 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        NSMutableArray *results = [NSMutableArray array];
        for (uintptr_t i = 0; i < count; i++) {
            struct ProcessTokenC *p = &rawProcesses[i]; NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"pid"] = @(p->pid);
            if (p->executable_url && strlen(p->executable_url) > 0) dict[@"path"] = [NSString stringWithUTF8String:p->executable_url];
            [results addObject:dict];
        }
        app_service_free_process_list(rawProcesses, (uintptr_t)count); app_service_free(appSvc); [self _freeRsdSession:&rsd];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(results, nil); });
    });
}

- (void)captureSysdiagnoseWithCompletion:(void (^)(NSString *path, NSError *error))completion {
    [_lock lock]; if (self.status != IdeviceStatusConnected || !self.provider) { [_lock unlock]; if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]); return; }
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err || !rsd.handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDセッションの確立に失敗しました"] : @"RSDセッションの確立に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        struct DiagnosticsServiceHandle *diag = NULL;
        err = diagnostics_service_connect_rsd(rsd.adapter, rsd.handshake, &diag);
        if (err || !diag) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Diagnosticsへの接続に失敗しました"] : @"Diagnosticsへの接続に失敗しました";
            if (err) idevice_error_free(err); [self _freeRsdSession:&rsd];
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:11 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        char *filename = NULL; uintptr_t expected = 0; struct SysdiagnoseStreamHandle *stream_h = NULL;
        err = diagnostics_service_capture_sysdiagnose(diag, false, &filename, &expected, &stream_h);
        if (err || !stream_h) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Sysdiagnoseの開始に失敗しました"] : @"Sysdiagnoseの開始に失敗しました";
            if (err) idevice_error_free(err); if (filename) rsd_free_string(filename); diagnostics_service_free(diag); [self _freeRsdSession:&rsd];
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:12 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        NSString *destName = filename ? [NSString stringWithUTF8String:filename] : [NSString stringWithFormat:@"sysdiagnose_%ld.tar.gz", (long)[[NSDate date] timeIntervalSince1970]];
        if (filename) rsd_free_string(filename);
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *finalPath = [docPath stringByAppendingPathComponent:destName];
        [[NSFileManager defaultManager] createFileAtPath:finalPath contents:nil attributes:nil];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:finalPath];
        if (!file) { sysdiagnose_stream_free(stream_h); diagnostics_service_free(diag); [self _freeRsdSession:&rsd]; if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:13 userInfo:@{NSLocalizedDescriptionKey: @"ファイルの作成に失敗しました"}]); }); return; }
        uint8_t *data = NULL; uintptr_t len = 0; BOOL loopSuccess = YES; NSError *loopErr = nil;
        while (true) {
            err = sysdiagnose_stream_next(stream_h, &data, &len);
            if (err) { loopErr = [NSError errorWithDomain:@"Idevice" code:16 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:err->message ?: "ストリーム取得エラー"]}]; idevice_error_free(err); loopSuccess = NO; break; }
            if (!data || len == 0) break;
            [file writeData:[NSData dataWithBytes:data length:len]]; idevice_data_free(data, (uintptr_t)len);
        }
        [file closeFile]; sysdiagnose_stream_free(stream_h); diagnostics_service_free(diag); [self _freeRsdSession:&rsd];
        if (loopSuccess) { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(finalPath, nil); }); }
        else { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, loopErr); }); }
    });
}

- (void)takeScreenshotWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    [_lock lock]; if (self.status != IdeviceStatusConnected || !self.provider) { [_lock unlock]; if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]); return; }
    struct IdeviceProviderHandle *p_outer = self.provider; [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd; struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (!err && rsd.handshake) {
            struct RemoteServerHandle *rs_handle = NULL;
            err = remote_server_connect_rsd(rsd.adapter, rsd.handshake, &rs_handle);
            if (!err && rs_handle) {
                struct ScreenshotClientHandle *client = NULL;
                err = screenshot_client_new(rs_handle, &client);
                if (!err && client) {
                    uint8_t *data = NULL; uintptr_t len = 0;
                    err = screenshot_client_take_screenshot(client, &data, &len);
                    screenshot_client_free(client);
                    if (!err && data && len > 0) {
                        NSData *pngData = [NSData dataWithBytes:data length:len];
                        UIImage *img = [UIImage imageWithData:pngData];
                        idevice_data_free(data, (uintptr_t)len);
                        remote_server_free(rs_handle); [self _freeRsdSession:&rsd];
                        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); });
                        return;
                    }
                    if (data) idevice_data_free(data, (uintptr_t)len);
                }
                remote_server_free(rs_handle);
            }
            if (err) idevice_error_free(err); [self _freeRsdSession:&rsd];
        } else if (err) {
            idevice_error_free(err);
        }
        struct ScreenshotrClientHandle *client = NULL;
        err = screenshotr_connect(p_outer, &client);
        if (err || !client) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Screenshotrへの接続に失敗しました"] : @"Screenshotrへの接続に失敗しました";
            if (err) idevice_error_free(err); if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:17 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        struct ScreenshotData data; memset(&data, 0, sizeof(data));
        err = screenshotr_take_screenshot(client, &data);
        screenshotr_client_free(client);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "スクリーンショットの取得に失敗しました"];
            if (err) idevice_error_free(err); if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:18 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        if (data.data && data.length > 0) {
            NSData *pngData = [NSData dataWithBytes:data.data length:data.length];
            UIImage *img = [UIImage imageWithData:pngData];
            screenshotr_screenshot_free(data); if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); });
        } else { if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:19 userInfo:@{NSLocalizedDescriptionKey: @"データが空です"}]); }); }
    });
}

#pragma mark - Syslog

- (void)startSyslogCaptureWithCallback:(void (^)(NSString *line))callback {
    [_lock lock]; if (self.status != IdeviceStatusConnected || !self.provider) { [_lock unlock]; return; }
    if (self.syslogActive) { [_lock unlock]; return; }
    struct IdeviceProviderHandle *p = self.provider; self.syslogActive = YES; [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct SyslogRelayClientHandle *client = NULL;
        struct IdeviceFfiError *err = syslog_relay_connect_tcp(p, &client);
        if (err || !client) { if (err) idevice_error_free(err); [self stopSyslogCapture]; return; }
        [self->_lock lock]; self.syslogClient = client; [_lock unlock];
        while (true) {
            [_lock lock]; BOOL active = self.syslogActive; struct SyslogRelayClientHandle *c = self.syslogClient; [_lock unlock];
            if (!active || !c) break;
            char *line = NULL; err = syslog_relay_next(c, &line);
            if (err) { idevice_error_free(err); break; }
            if (line) { NSString *nsLine = [NSString stringWithUTF8String:line]; if (callback) dispatch_async(dispatch_get_main_queue(), ^{ callback(nsLine); }); rsd_free_string(line); }
        }
        [self stopSyslogCapture];
    });
}

- (void)stopSyslogCapture {
    [_lock lock]; self.syslogActive = NO;
    if (self.syslogClient) { syslog_relay_client_free(self.syslogClient); self.syslogClient = NULL; }
    [_lock unlock];
}

#pragma mark - Plist Utils

- (id)_convertPlistToObjC:(plist_t)node depth:(int)depth {
    if (!node || depth > 20) return nil;
    plist_type typeNum = plist_get_node_type(node);
    switch (typeNum) {
        case PLIST_BOOLEAN: { uint8_t val = 0; plist_get_bool_val(node, &val); return @((BOOL)val); }
        case PLIST_INT: { uint64_t val = 0; plist_get_uint_val(node, &val); return @(val); }
        case PLIST_REAL: { double val = 0; plist_get_real_val(node, &val); return @(val); }
        case PLIST_STRING: { char *val = NULL; plist_get_string_val(node, &val); NSString *s = (val) ? [NSString stringWithUTF8String:val] : @""; if (val) plist_mem_free(val); return s; }
        case PLIST_KEY: { char *val = NULL; plist_get_key_val(node, &val); NSString *s = (val) ? [NSString stringWithUTF8String:val] : @""; if (val) plist_mem_free(val); return s; }
        case PLIST_ARRAY: {
            uint32_t size = plist_array_get_size(node); if (size > 1000) size = 1000;
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:size];
            for (uint32_t i = 0; i < size; i++) { id obj = [self _convertPlistToObjC:plist_array_get_item(node, i) depth:depth + 1]; if (obj) [arr addObject:obj]; }
            return arr;
        }
        case PLIST_DICT: {
            uint32_t size = plist_dict_get_size(node); if (size > 1000) size = 1000;
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:size];
            plist_dict_iter iter = NULL; plist_dict_new_iter(node, &iter);
            if (iter) {
                char *key = NULL; plist_t subnode = NULL;
                for (uint32_t i = 0; i < size; i++) {
                    plist_dict_next_item(node, iter, &key, &subnode);
                    if (key) { NSString *nsKey = [NSString stringWithUTF8String:key]; id obj = [self _convertPlistToObjC:subnode depth:depth + 1]; if (nsKey && obj) dict[nsKey] = obj; plist_mem_free(key); key = NULL; }
                    else break;
                }
                free(iter);
            }
            return dict;
        }
        case PLIST_DATA: { uint64_t len = 0; const char *ptr = plist_get_data_ptr(node, &len); return (ptr && len > 0 && len < 5*1024*1024) ? [NSData dataWithBytes:ptr length:(NSUInteger)len] : [NSData data]; }
        default: return nil;
    }
}

@end