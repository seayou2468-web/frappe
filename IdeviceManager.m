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
        _ipAddress = [[defaults stringForKey:@"IdeviceIP"] copy] ?: @"10.7.0.1";
        _port = (uint16_t)[defaults integerForKey:@"IdevicePort"] ?: 62078;
        _pairingFilePath = [[defaults stringForKey:@"IdevicePairingPath"] copy];
        _status = IdeviceStatusDisconnected;
        idevice_init_logger(Debug, Disabled, NULL);
    }
    return self;
}

#pragma mark - Thread-safe Properties

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
    NSString *ip = self.ipAddress; uint16_t port = self.port; NSString *pairingPath = self.pairingFilePath;
    struct sockaddr_in sa; memset(&sa, 0, sizeof(sa)); sa.sin_family = AF_INET; sa.sin_port = htons(port);
    if (!ip || ip.length == 0 || inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr) <= 0) { [self _handleError:@"IPアドレスの形式が正しくありません"]; return; }
    struct IdeviceFfiError *err = NULL; struct IdeviceProviderHandle *localProvider = NULL;
    struct LockdowndClientHandle *localLockdown = NULL; struct HeartbeatClientHandle *localHb = NULL;
    struct IdevicePairingFile *pairingForProvider = NULL; struct IdevicePairingFile *pairingForSession = NULL;
    if (pairingPath && pairingPath.length > 0) {
        err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForProvider);
        if (!err) {
            err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForSession);
        }
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
        idevice_pairing_file_free(pairingForProvider);
        idevice_pairing_file_free(pairingForSession);
        return;
    }
    // Note: localProvider now owns pairingForProvider logic internally usually,
    // but if idevice_tcp_provider_new fails, we must free it.

    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) {
        [self _handleFfiError:err fallback:@"Lockdownサービスへの接続に失敗しました"];
        idevice_provider_free(localProvider);
        idevice_pairing_file_free(pairingForSession);
        return;
    }

    err = lockdownd_start_session(localLockdown, pairingForSession);
    if (err) {
        [self _handleFfiError:err fallback:@"セッションの開始に失敗しました"];
        idevice_pairing_file_free(pairingForSession);
        lockdownd_client_free(localLockdown);
        idevice_provider_free(localProvider);
        return;
    }
    err = heartbeat_connect(localProvider, &localHb); if (err) idevice_error_free(err);
    BOOL ddi = NO; struct ImageMounterHandle *mounter = NULL;
    err = image_mounter_connect(localProvider, &mounter);
    if (!err && mounter) {
        plist_t *devices = NULL; size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) {
            ddi = (count > 0);
            if (devices) idevice_plist_array_free(devices, (uintptr_t)count);
        } else {
            if (err) idevice_error_free(err);
        }
        image_mounter_free(mounter);
    } else if (err) idevice_error_free(err);
    [_lock lock];
    if (self.status == IdeviceStatusConnecting) {
        _pairingFile = pairingForSession; _provider = localProvider; _lockdownClient = localLockdown;
        _heartbeatClient = localHb; _heartbeatActive = (localHb != NULL); _ddiMounted = ddi; _status = IdeviceStatusConnected;
        if (localHb) { dispatch_async(dispatch_get_main_queue(), ^{ [self _startHeartbeatTimer]; }); }
        dispatch_async(dispatch_get_main_queue(), ^{ [[NSNotificationCenter defaultCenter] postNotificationName:@"IdeviceStatusChanged" object:nil]; });
    } else {
        if (localHb) heartbeat_client_free(localHb);
        lockdownd_client_free(localLockdown); idevice_provider_free(localProvider); idevice_pairing_file_free(pairingForSession);
    }
    [_lock unlock];
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
        if (err) { if (err) idevice_error_free(err); [strongSelf disconnect]; strongSelf.lastError = @"ハートビートが途切れました"; }
    });
}

- (void)disconnect {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.heartbeatTimer invalidate]; self.heartbeatTimer = nil; });
    [_lock lock];
    if (self.heartbeatClient) { heartbeat_client_free(self.heartbeatClient); _heartbeatClient = NULL; }
    if (self.lockdownClient) { lockdownd_client_free(self.lockdownClient); _lockdownClient = NULL; }
    if (self.provider) { idevice_provider_free(self.provider); _provider = NULL; }
    if (self.pairingFile) { idevice_pairing_file_free(self.pairingFile); _pairingFile = NULL; }
    _status = IdeviceStatusDisconnected; _heartbeatActive = NO; _ddiMounted = NO;
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
            idevice_plist_array_free(handles, out_result_len);
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(finalApps, nil); });
    });
}

- (id)_convertPlistToObjC:(plist_t)node depth:(int)depth {
    if (!node || depth > 20) return nil;
    plist_type type = PLIST_NONE;
    type = plist_get_node_type(node);
    switch (type) {
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
        struct IdeviceFfiError *err = lockdownd_start_service(l, "com.apple.instruments.server.services.deviceinfo", &service_port, &ssl);
        if (err) {
            if (err) idevice_error_free(err);
            err = lockdownd_start_service(l, "com.apple.mobile.installation_proxy", &service_port, &ssl);
        }

        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "サービスの開始に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion([NSError errorWithDomain:@"Idevice" code:4 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        [[Logger sharedLogger] log:[NSString stringWithFormat:@"[Idevice] Successfully started a service on port %d for launch attempt of %@", service_port, bundleId]];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    });
}


- (void)getRsdServicesWithCompletion:(void (^)(NSArray *services, NSError *error))completion {
    [_lock lock];
    if (self.status != IdeviceStatusConnected || !self.provider) {
        [_lock unlock];
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"デバイスに接続されていません"}]);
        return;
    }
    struct LockdowndClientHandle *lockdown = self.lockdownClient;
    NSString *ipStr = self.ipAddress;
    [_lock unlock];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uint16_t rsd_port = 0;
        bool ssl = false;
        struct IdeviceFfiError *err = lockdownd_start_service(lockdown, "com.apple.mobile.restored", &rsd_port, &ssl);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "RSDサービスの開始に失敗しました"];
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:6 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct TcpFeedObject *feeder = NULL;
        struct TcpEatObject *eater = NULL;
        struct AdapterHandle *adapter = NULL;
        err = idevice_tcp_stack_into_sync_objects("0.0.0.0", [ipStr UTF8String], &feeder, &eater, &adapter);
        if (err || !adapter) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "TCPスタックの初期化に失敗しました"] : @"TCPスタックの初期化に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:7 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct ReadWriteOpaque *stream = NULL;
        err = adapter_connect(adapter, rsd_port, &stream);
        if (err || !stream) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDストリームの接続に失敗しました"] : @"RSDストリーム de 接続に失敗しました";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:8 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct RsdHandshakeHandle *handshake = NULL;
        err = rsd_handshake_new(stream, &handshake);
        if (err || !handshake) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDハンドシェイクに失敗しました"] : @"RSDハンドシェイクに失敗しました";
            if (err) idevice_error_free(err);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:9 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        struct CRsdServiceArray *rawServices = NULL;
        err = rsd_get_services(handshake, &rawServices);
        if (err || !rawServices) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "RSDサービスの取得に失敗しました"] : @"RSDサービスの取得に失敗しました";
            if (err) idevice_error_free(err);
            rsd_handshake_free(handshake);
            idevice_stream_free(stream);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:10 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        NSMutableArray *results = [NSMutableArray array];
        for (size_t i = 0; i < rawServices->count; i++) {
            struct CRsdService *s = &rawServices->services[i];
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            if (s->name) dict[@"name"] = [NSString stringWithUTF8String:s->name];
            if (s->entitlement) dict[@"entitlement"] = [NSString stringWithUTF8String:s->entitlement];
            dict[@"port"] = @(s->port);
            [results addObject:dict];
        }

        rsd_free_services(rawServices);
        rsd_handshake_free(handshake);
        idevice_stream_free(stream);

        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(results, nil); });
    });
}
