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
    if (inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr) <= 0) { [self _handleError:@"Invalid IP address format"]; return; }
    struct IdeviceFfiError *err = NULL; struct IdeviceProviderHandle *localProvider = NULL;
    struct LockdowndClientHandle *localLockdown = NULL; struct HeartbeatClientHandle *localHb = NULL;
    struct IdevicePairingFile *pairingForProvider = NULL; struct IdevicePairingFile *pairingForSession = NULL;
    if (pairingPath) {
        err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForProvider);
        if (!err) err = idevice_pairing_file_read([pairingPath UTF8String], &pairingForSession);
        if (err || !pairingForProvider || !pairingForSession) {
            [self _handleFfiError:err fallback:@"Failed to load pairing file handles"];
            if (pairingForProvider) idevice_pairing_file_free(pairingForProvider);
            if (pairingForSession) idevice_pairing_file_free(pairingForSession);
            return;
        }
    } else { [self _handleError:@"Pairing file not selected"]; return; }
    err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairingForProvider, "frappe-idevice", &localProvider);
    if (err || !localProvider) { [self _handleFfiError:err fallback:@"Failed to create provider"]; idevice_pairing_file_free(pairingForSession); return; }
    err = lockdownd_connect(localProvider, &localLockdown);
    if (err || !localLockdown) { [self _handleFfiError:err fallback:@"Failed to connect lockdown"]; idevice_provider_free(localProvider); idevice_pairing_file_free(pairingForSession); return; }
    err = lockdownd_start_session(localLockdown, pairingForSession);
    if (err) { [self _handleFfiError:err fallback:@"Failed to start session"]; idevice_pairing_file_free(pairingForSession); lockdownd_client_free(localLockdown); idevice_provider_free(localProvider); return; }
    err = heartbeat_connect(localProvider, &localHb); if (err) idevice_error_free(err);
    BOOL ddi = NO; struct ImageMounterHandle *mounter = NULL;
    err = image_mounter_connect(localProvider, &mounter);
    if (!err && mounter) {
        plist_t devices = NULL; size_t count = 0;
        err = image_mounter_copy_devices(mounter, &devices, &count);
        if (!err) ddi = (count > 0); else idevice_error_free(err);
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
        if (err) { idevice_error_free(err); [strongSelf disconnect]; strongSelf.lastError = @"Heartbeat lost"; }
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
        if (completion) completion(nil, [NSError errorWithDomain:@"Idevice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}]);
        return;
    }
    struct IdeviceProviderHandle *p = self.provider;
    [_lock unlock];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct InstallationProxyClientHandle *client = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(p, &client);
        if (err || !client) {
            NSString *msg = err ? [NSString stringWithUTF8String:err->message ?: "Failed to connect to InstProxy"] : @"Failed to connect to InstProxy";
            if (err) idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:2 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }
        void *out_result = NULL; size_t out_result_len = 0;
        err = installation_proxy_get_apps(client, "Any", NULL, 0, &out_result, &out_result_len);
        installation_proxy_client_free(client);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message ?: "Failed to get apps"];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [NSError errorWithDomain:@"Idevice" code:3 userInfo:@{NSLocalizedDescriptionKey: msg}]); });
            return;
        }

        NSMutableArray *finalApps = [NSMutableArray array];
        if (out_result) {
            // First, try to treat as a buffer of bytes (most likely)
            plist_t parsedNode = NULL;
            if (plist_from_bin(out_result, (uint32_t)out_result_len, &parsedNode) == PLIST_ERR_SUCCESS ||
                plist_from_xml(out_result, (uint32_t)out_result_len, &parsedNode) == PLIST_ERR_SUCCESS) {
                id obj = [self _convertPlistToObjC:parsedNode depth:0];
                if ([obj isKindOfClass:[NSArray class]]) [finalApps addObjectsFromArray:obj];
                else if (obj) [finalApps addObject:obj];
                plist_free(parsedNode);
            } else {
                // If not a buffer, try treating out_result itself as a plist_t handle
                id obj = [self _convertPlistToObjC:(plist_t)out_result depth:0];
                if (obj) {
                    if ([obj isKindOfClass:[NSArray class]]) [finalApps addObjectsFromArray:obj];
                    else [finalApps addObject:obj];
                }
            }
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(finalApps, nil); });
    });
}

- (id)_convertPlistToObjC:(plist_t)node depth:(int)depth {
    if (!node || depth > 20) return nil;
    plist_type type = PLIST_NONE;
    @try { type = plist_get_node_type(node); } @catch (NSException *e) { return nil; }
    switch (type) {
        case PLIST_BOOLEAN: { uint8_t val = 0; plist_get_bool_val(node, &val); return @((BOOL)val); }
        case PLIST_INT: { uint64_t val = 0; plist_get_uint_val(node, &val); return @(val); }
        case PLIST_REAL: { double val = 0; plist_get_real_val(node, &val); return @(val); }
        case PLIST_STRING: { char *val = NULL; plist_get_string_val(node, &val); NSString *s = (val) ? [NSString stringWithUTF8String:val] : @""; if (val) plist_mem_free(val); return s; }
        case PLIST_KEY: { char *val = NULL; plist_get_key_val(node, &val); NSString *s = (val) ? [NSString stringWithUTF8String:val] : @""; if (val) plist_mem_free(val); return s; }
        case PLIST_ARRAY: {
            uint32_t size = plist_array_get_size(node);
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:size];
            for (uint32_t i = 0; i < size; i++) {
                id obj = [self _convertPlistToObjC:plist_array_get_item(node, i) depth:depth + 1];
                if (obj) [arr addObject:obj];
            }
            return arr;
        }
        case PLIST_DICT: {
            uint32_t size = plist_dict_get_size(node);
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:size];
            plist_dict_iter iter = NULL; plist_dict_new_iter(node, &iter);
            if (iter) {
                char *key = NULL; plist_t subnode = NULL;
                for (uint32_t i = 0; i < size; i++) {
                    plist_dict_next_item(node, iter, &key, &subnode);
                    if (key) {
                        NSString *nsKey = [NSString stringWithUTF8String:key];
                        id obj = [self _convertPlistToObjC:subnode depth:depth + 1];
                        if (nsKey && obj) dict[nsKey] = obj;
                        plist_mem_free(key);
                    }
                }
                free(iter);
            }
            return dict;
        }
        case PLIST_DATA: { uint64_t len = 0; const char *ptr = plist_get_data_ptr(node, &len); return (ptr && len > 0) ? [NSData dataWithBytes:ptr length:(NSUInteger)len] : [NSData data]; }
        default: return nil;
    }
}

- (void)dealloc { [self disconnect]; }
@end
