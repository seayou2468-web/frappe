#import "IdeviceManager.h"
#import <arpa/inet.h>
#import "Logger.h"

struct RsdSession {
    struct AdapterHandle *adapter;
    struct RsdHandshakeHandle *handshake;
    struct ReadWriteOpaque *stream;
    struct CoreDeviceProxyHandle *proxy;
    struct TcpFeedObject *feeder;
    struct TcpEatObject *eater;
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
- (void)_bridgeTcpForSession:(RsdSession *)session ip:(NSString *)ip port:(uint16_t)port;
- (struct IdeviceFfiError *)_establishRsdSession:(RsdSession *)session;
- (void)_freeRsdSession:(RsdSession *)session;
@end

@implementation IdeviceManager {
    NSRecursiveLock *_lock;
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

- (BOOL)ddiMounted { [_lock lock]; BOOL mounted = _ddiMounted; [_lock unlock]; return mounted; }


- (BOOL)heartbeatActive { [_lock lock]; BOOL active = _heartbeatActive; [_lock unlock]; return active; }


- (IdeviceConnectionStatus)status { [_lock lock]; IdeviceConnectionStatus s = _status; [_lock unlock]; return s; }


- (NSString *)ipAddress { [_lock lock]; NSString *ip = [_ipAddress copy]; [_lock unlock]; return ip; }


- (NSString *)lastError { [_lock lock]; NSString *err = [_lastError copy]; [_lock unlock]; return err; }


- (NSString *)pairingFilePath { [_lock lock]; NSString *path = [_pairingFilePath copy]; [_lock unlock]; return path; }


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
            uint32_t size = plist_array_get_size(node);
            if (size > 1000) size = 1000;
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:size];
            for (uint32_t i = 0; i < size; i++) {
                id obj = [self _convertPlistToObjC:plist_array_get_item(node, i) depth:depth + 1];
                if (obj) [arr addObject:obj];
            }
            return arr;
        }
        case PLIST_DICT: {
            uint32_t size = plist_dict_get_size(node);
            if (size > 1000) size = 1000;
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:size];
            plist_dict_iter iter = NULL;
            plist_dict_new_iter(node, &iter);
            if (iter) {
                char *key = NULL; plist_t subnode = NULL;
                for (uint32_t i = 0; i < size; i++) {
                    plist_dict_next_item(node, iter, &key, &subnode);
                    if (key) {
                        NSString *nsKey = [NSString stringWithUTF8String:key];
                        id obj = [self _convertPlistToObjC:subnode depth:depth + 1];
                        if (nsKey && obj) dict[nsKey] = obj;
                        plist_mem_free(key);
                        key = NULL;
                    } else {
                        break;
                    }
                }
                free(iter);
            }
            return dict;
        }
        case PLIST_DATA: { uint64_t len = 0; const char *ptr = plist_get_data_ptr(node, &len); return (ptr && len > 0 && len < 5*1024*1024) ? [NSData dataWithBytes:ptr length:(NSUInteger)len] : [NSData data]; }
        default: return nil;
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        _status = IdeviceStatusDisconnected;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _ipAddress = [defaults stringForKey:@"IdeviceIP"] ?: @"10.7.0.1";
        _port = (uint16_t)([defaults integerForKey:@"IdevicePort"] ?: 62078);
        _pairingFilePath = [defaults stringForKey:@"IdevicePairingPath"];
    }
    return self;
}

- (struct IdeviceFfiError *)_establishRsdSession:(RsdSession *)session {
    memset(session, 0, sizeof(RsdSession));
    [_lock lock];
    struct LockdowndClientHandle *lockdown = self.lockdownClient;
    struct IdeviceProviderHandle *provider = self.provider;
    NSString *ipStr = [self.ipAddress copy];
    [_lock unlock];
    if (!lockdown || !provider || !ipStr) return NULL;

    struct IdeviceFfiError *err = NULL;
    struct IdeviceFfiError *last_err = NULL;

    // Method 1: CoreDeviceProxy (Modern iOS 17+)
    struct CoreDeviceProxyHandle *proxy = NULL;
    err = core_device_proxy_connect(provider, &proxy);
    if (!err && proxy) {
        session->proxy = proxy;
        uint16_t rsd_port = 0;
        err = core_device_proxy_get_server_rsd_port(proxy, &rsd_port);
        if (!err && rsd_port > 0) {
            struct AdapterHandle *adapter = NULL;
            // The proxy handle is consumed by create_tcp_adapter
            err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
            if (!err && adapter) {
                session->adapter = adapter;
                session->proxy = NULL; // Mark as consumed
                struct ReadWriteOpaque *stream = NULL;
                err = adapter_connect(adapter, rsd_port, &stream);
                if (!err && stream) {
                    session->stream = stream;
                    struct RsdHandshakeHandle *handshake = NULL;
                    // The stream handle is consumed by rsd_handshake_new
                    err = rsd_handshake_new(stream, &handshake);
                    if (!err && handshake) {
                        session->handshake = handshake;
                        session->stream = NULL; // Mark as consumed
                        return NULL;
                    }
                }
            }
        }
    }
    if (err) { if (last_err) idevice_error_free(last_err); last_err = err; }
    [self _freeRsdSession:session];

    const char *services[] = {"com.apple.mobile.restored", "com.apple.remoteserver", "com.apple.remoteserviceproxy"};
    for (int i = 0; i < 3; i++) {
        uint16_t rsd_port = 0; bool ssl = false;
        err = lockdownd_start_service(lockdown, services[i], &rsd_port, &ssl);
        if (!err && rsd_port > 0) {
            struct TcpFeedObject *feeder = NULL; struct TcpEatObject *eater = NULL; struct AdapterHandle *adapter = NULL;
            err = idevice_tcp_stack_into_sync_objects("0.0.0.0", [ipStr UTF8String], &feeder, &eater, &adapter);
            if (!err && adapter && feeder && eater) {
                session->adapter = adapter; session->feeder = feeder; session->eater = eater;
                [self _bridgeTcpForSession:session ip:ipStr port:rsd_port];
                struct ReadWriteOpaque *stream = NULL;
                err = adapter_connect(adapter, rsd_port, &stream);
                if (!err && stream) {
                    session->stream = stream;
                    struct RsdHandshakeHandle *handshake = NULL;
                    err = rsd_handshake_new(stream, &handshake);
                    if (!err && handshake) {
                        session->handshake = handshake;
                        session->stream = NULL; // Consumed
                        if (last_err) idevice_error_free(last_err);
                        return NULL;
                    }
                }
            }
        }
        if (err) { if (last_err) idevice_error_free(last_err); last_err = err; }
        [self _freeRsdSession:session];
    }
    return last_err;
}

- (uint16_t)port { [_lock lock]; uint16_t p = _port; [_lock unlock]; return p; }


- (void)_bridgeTcpForSession:(RsdSession *)session ip:(NSString *)ip port:(uint16_t)port {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return;
    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);
    if (inet_pton(AF_INET, [ip UTF8String], &serv_addr.sin_addr) <= 0) { close(sock); return; }
    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) { close(sock); return; }
    struct TcpFeedObject *feeder = session->feeder;
    struct TcpEatObject *eater = session->eater;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        uint8_t buf[16384];
        while (YES) {
            ssize_t n = recv(sock, buf, sizeof(buf), 0);
            if (n <= 0) break;
            struct IdeviceFfiError *err = idevice_tcp_feed_object_write(feeder, buf, (uintptr_t)n);
            if (err) { idevice_error_free(err); break; }
        }
        close(sock);
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        while (YES) {
            uint8_t *data = NULL; uintptr_t len = 0;
            struct IdeviceFfiError *err = idevice_tcp_eat_object_read(eater, &data, &len);
            if (err) { idevice_error_free(err); break; }
            if (data && len > 0) {
#ifdef MSG_NOSIGNAL
                send(sock, data, len, MSG_NOSIGNAL);
#else
                send(sock, data, len, 0);
#endif
                idevice_data_free(data, len);
            } else if (data) {
                idevice_data_free(data, len);
            } else {
                break;
            }
        }
        close(sock);
    });
}

- (void)_freeRsdSession:(RsdSession *)session {
    if (session->handshake) rsd_handshake_free(session->handshake);
    if (session->stream) idevice_stream_free(session->stream);
    if (session->adapter) {
        struct IdeviceFfiError *e = adapter_close(session->adapter);
        if (e) idevice_error_free(e);
        adapter_free(session->adapter);
    }
    if (session->proxy) core_device_proxy_free(session->proxy);
    if (session->feeder) idevice_free_tcp_feed_object(session->feeder);
    if (session->eater) idevice_free_tcp_eat_object(session->eater);
    memset(session, 0, sizeof(RsdSession));
}

- (void)_handleError:(NSString *)msg {
    [_lock lock]; self.lastError = msg; self.status = IdeviceStatusError; [_lock unlock];
    [self disconnect];
}

- (void)_handleFfiError:(struct IdeviceFfiError *)err fallback:(NSString *)fallback {
    NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: [fallback UTF8String]] : fallback;
    if (err) idevice_error_free(err); [self _handleError:msg];
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
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingForProvider, "frappe-idevice", &localProvider); if (!err) pairingForProvider = NULL;
    if (err || !localProvider) {
        [self _handleFfiError:err fallback:@"プロバイダーの作成に失敗しました"];
        if (pairingForProvider) idevice_pairing_file_free(pairingForProvider);
        if (pairingForSession) idevice_pairing_file_free(pairingForSession);
        return;
    }
    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) {
        [self _handleFfiError:err fallback:@"Lockdownサービスへの接続に失敗しました"];
        if (localProvider) idevice_provider_free(localProvider);
        if (pairingForSession) idevice_pairing_file_free(pairingForSession);
        return;
    }
    err = lockdownd_start_session(localLockdown, pairingForSession); if (!err) pairingForSession = NULL;
    if (err) {
        [self _handleFfiError:err fallback:@"セッションの開始に失敗しました"];
        if (pairingForSession) idevice_pairing_file_free(pairingForSession);
        if (localLockdown) lockdownd_client_free(localLockdown);
        if (localProvider) idevice_provider_free(localProvider);
        return;
    }
    err = heartbeat_connect(localProvider, &localHb); if (err) { idevice_error_free(err); }
    BOOL ddiFlag = NO; struct ImageMounterHandle *mounter = NULL;
    err = image_mounter_connect(localProvider, &mounter);
    if (!err && mounter) {
        plist_t *devices = NULL; size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) {
            ddiFlag = (count > 0);
            if (devices) idevice_plist_array_free(devices, (uintptr_t)count);
        } else {
            idevice_error_free(err);
        }
        image_mounter_free(mounter);
    } else if (err) { idevice_error_free(err); }
    [_lock lock];
    if (self.status == IdeviceStatusConnecting) {
        _pairingFile = pairingForSession; _provider = localProvider; _lockdownClient = localLockdown;
        _heartbeatClient = localHb; _heartbeatActive = (localHb != NULL); _ddiMounted = ddiFlag; _status = IdeviceStatusConnected;
        if (localHb) { dispatch_async(dispatch_get_main_queue(), ^{ [self _startHeartbeatTimer]; }); }
        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });
    } else {
        if (localHb) heartbeat_client_free(localHb);
        if (localLockdown) lockdownd_client_free(localLockdown);
        if (localProvider) idevice_provider_free(localProvider);
        if (pairingForSession) idevice_pairing_file_free(pairingForSession);
    }
    [_lock unlock];
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

- (void)_startHeartbeatTimer {
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(_sendHeartbeat) userInfo:nil repeats:YES];
}

- (void)captureSysdiagnoseWithCompletion:(void (^)(NSString *path, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd;
        struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err || !rsd.handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDセッションの確立に失敗しました"] : @"RSDセッションの確立に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }]); });
            return;
        }

- (void)connect {
    [_lock lock];
    if (self.status == IdeviceStatusConnected || self.status == IdeviceStatusConnecting) { [_lock unlock]; return; }
    self.status = IdeviceStatusConnecting; self.lastError = nil;
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [self _performConnect]; });
}

- (void)dealloc {
    [self disconnect];
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

- (void)getAppListWithCompletion:(void (^)(NSArray *apps, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct IdeviceProviderHandle *p = self.provider;
    [_lock unlock];
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
            for (size_t i = 0; i < out_result_len; i++) {
                if (handles[i]) {
                    id obj = [self _convertPlistToObjC:handles[i] depth:0];
                    if (obj) [finalApps addObject:obj];
                }
            }
            idevice_plist_array_free(handles, (uintptr_t)out_result_len);
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(finalApps, nil); });
    });
}

- (void)getProcessListWithCompletion:(void (^)(NSArray *processes, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd;
        struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err || !rsd.handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDセッションの確立に失敗しました"] : @"RSDセッションの確立に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }]); });
            return;
        }

- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd;
        struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
        if (err || !rsd.handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDセッションの確立に失敗しました"] : @"RSDセッションの確立に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }]); });
            return;
        }

- (void)launchAppWithBundleId:(NSString *)bundleId completion:(void (^)(NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider || !self.lockdownClient) {
        [_lock unlock];
        if (completion) completion([NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct LockdowndClientHandle *l = self.lockdownClient;
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint16_t service_port = 0;
        bool ssl = false;
        struct IdeviceFfiError *err = lockdownd_start_service(l, "com.apple.mobile.installation_proxy", &service_port, &ssl);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "アプリ起動サービスの開始に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:4 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] Successfully verified service for launch attempt of %@", bundleId]];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}

- (void)selectPairingFile:(NSString *)path { self.pairingFilePath = path; }


- (void)setDdiMounted:(BOOL)ddiMounted { [_lock lock]; _ddiMounted = ddiMounted; [_lock unlock]; }


- (void)setHeartbeatActive:(BOOL)heartbeatActive { [_lock lock]; _heartbeatActive = heartbeatActive; [_lock unlock]; }


- (void)setIpAddress:(NSString *)ipAddress { [_lock lock]; _ipAddress = [ipAddress copy]; [[NSUserDefaults standardUserDefaults] setObject:_ipAddress forKey:@"IdeviceIP"]; [_lock unlock]; }


- (void)setLastError:(NSString *)lastError { [_lock lock]; _lastError = [lastError copy]; [_lock unlock]; }


- (void)setPairingFilePath:(NSString *)pairingFilePath { [_lock lock]; _pairingFilePath = [pairingFilePath copy]; [[NSUserDefaults standardUserDefaults] setObject:_pairingFilePath forKey:@"IdevicePairingPath"]; [_lock unlock]; }


- (void)setPort:(uint16_t)port { [_lock lock]; _port = port; [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)_port forKey:@"IdevicePort"]; [_lock unlock]; }


- (void)setStatus:(IdeviceConnectionStatus)status { [_lock lock]; _status = status; [_lock unlock]; }


- (void)startSyslogCaptureWithCallback:(void (^)(NSString *line))callback {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        return;
    }
    if (self.syslogActive) { [_lock unlock]; return; }
    struct IdeviceProviderHandle *p = self.provider;
    self.syslogActive = YES;
    [_lock unlock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct SyslogRelayClientHandle *client = NULL;
        struct IdeviceFfiError *err = syslog_relay_connect_tcp(p, &client);
        if (err || !client) {
            if (err) idevice_error_free(err);
            [self stopSyslogCapture];
            return;
        }

        [self->_lock lock];
        self.syslogClient = client;
        [self->_lock unlock];

        while (true) {
            [self->_lock lock];
            BOOL active = self.syslogActive;
            struct SyslogRelayClientHandle *c = self.syslogClient;
            [self->_lock unlock];

            if (!active || !c) break;

            char *line = NULL;
            err = syslog_relay_next(c, &line);
            if (err) {
                idevice_error_free(err);
                break;
            }
            if (line) {
                NSString *nsLine = [NSString stringWithUTF8String:line];
                if (callback) dispatch_async(dispatch_get_main_queue(), ^{ callback(nsLine); });
                rsd_free_string(line);
            }
        }
        [self stopSyslogCapture];
    });
}

- (void)stopSyslogCapture {
    [_lock lock];
    self.syslogActive = NO;
    if (self.syslogClient) {
        syslog_relay_client_free(self.syslogClient);
        self.syslogClient = NULL;
    }
    [_lock unlock];
}

- (void)takeScreenshotWithCompletion:(void (^)(UIImage *image, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct IdeviceProviderHandle *p = self.provider;
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RsdSession rsd;
        struct IdeviceFfiError *err = [self _establishRsdSession:&rsd];
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
                        remote_server_free(rs_handle);
                        [self _freeRsdSession:&rsd];
                        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); });
                        return;
                    }
                    if (data) idevice_data_free(data, (uintptr_t)len);
                }
                remote_server_free(rs_handle);
            }
            if (err) idevice_error_free(err);
            [self _freeRsdSession:&rsd];
        } else if (err) {
            idevice_error_free(err);
        }
        struct ScreenshotrClientHandle *client = NULL;
        err = screenshotr_connect(p, &client);
        if (err || !client) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Screenshotrへの接続に失敗しました"] : @"Screenshotrへの接続に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:17 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        struct ScreenshotData data; memset(&data, 0, sizeof(data));
        err = screenshotr_take_screenshot(client, &data);
        screenshotr_client_free(client);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "スクリーンショットの取得に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:18 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        if (data.data && data.length > 0) {
            NSData *pngData = [NSData dataWithBytes:data.data length:data.length];
            UIImage *img = [UIImage imageWithData:pngData];
            screenshotr_screenshot_free(data);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(img, nil); });
        } else {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:19 userInfo:@{NSLocalizedDescriptionKey: @"データが空です"}]); });
        }
    });
}

@end
