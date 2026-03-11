#import "AppManager.h"
#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "HeartbeatManager.h"
#import "JITScripts.h"

@implementation AppInfo
@end

@implementation AppManager

+ (instancetype)sharedManager {
    static AppManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[AppManager alloc] init]; });
    return shared;
}

- (void)fetchAppsWithProvider:(struct IdeviceProviderHandle *)provider completion:(void (^)(NSArray<AppInfo *> *apps, NSString *error))completion {
    if (!provider) { completion(nil, @"Missing provider"); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct InstallationProxyClientHandle *instproxy = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(provider, &instproxy);
        if (err) { completion(nil, [NSString stringWithUTF8String:err->message]); idevice_error_free(err); return; }
        NSMutableArray *allApps = [NSMutableArray array];
        [self fetchAppsWithType:"User" client:instproxy list:allApps];
        [self fetchAppsWithType:"System" client:instproxy list:allApps];
        installation_proxy_client_free(instproxy);
        completion(allApps, nil);
    });
}

- (void)fetchAppsWithType:(const char *)type client:(struct InstallationProxyClientHandle *)client list:(NSMutableArray *)list {
    plist_t options = plist_new_dict();
    plist_dict_set_item(options, "ApplicationType", plist_new_string(type));
    plist_t *result_array = NULL; size_t result_count = 0;
    struct IdeviceFfiError *err = installation_proxy_browse(client, options, &result_array, &result_count);
    if (!err && result_array) {
        for (size_t i = 0; i < result_count; i++) {
            plist_t item = result_array[i]; if (!item) continue;
            AppInfo *info = [AppInfo new]; info.isSystem = strcmp(type, "System") == 0;
            plist_t bid_node = plist_dict_get_item(item, "CFBundleIdentifier");
            if (bid_node) { char *val = NULL; plist_get_string_val(bid_node, &val); if (val) { info.bundleId = [NSString stringWithUTF8String:val]; plist_mem_free(val); } }
            plist_t name_node = plist_dict_get_item(item, "CFBundleDisplayName");
            if (!name_node) name_node = plist_dict_get_item(item, "CFBundleName");
            if (name_node) { char *val = NULL; plist_get_string_val(name_node, &val); if (val) { info.name = [NSString stringWithUTF8String:val]; plist_mem_free(val); } }
            if (info.bundleId) { if (!info.name) info.name = info.bundleId; [list addObject:info]; }
        }
        idevice_plist_array_free(result_array, result_count);
    }
    if (err) { NSLog(@"[Apps] Browse error for %s: %s", type, err->message); idevice_error_free(err); }
    plist_free(options);
}

- (void)launchApp:(NSString *)bundleId jitMode:(JitMode)jitMode provider:(struct IdeviceProviderHandle *)provider completion:(void (^)(BOOL success, NSString *message))completion {
    NSString *bid = [bundleId copy];
    void (^safeCompletion)(BOOL, NSString *) = ^(BOOL success, NSString *msg) {
        [[HeartbeatManager sharedManager] resumeHeartbeat];
        if (completion) { dispatch_async(dispatch_get_main_queue(), ^{ completion(success, msg); }); }
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [[HeartbeatManager sharedManager] pauseHeartbeat];
        [NSThread sleepForTimeInterval:0.2];

        struct LockdowndClientHandle *warmup = NULL;
        struct IdeviceFfiError *warmup_err = lockdownd_connect(provider, &warmup);
        if (!warmup_err) {
            plist_t udid = NULL; lockdownd_get_value(warmup, "UniqueDeviceID", NULL, &udid);
            if (udid) plist_free(udid); lockdownd_client_free(warmup);
        } else { NSLog(@"[Launch] Warmup error: %s", warmup_err->message); idevice_error_free(warmup_err); }

        struct CoreDeviceProxyHandle *proxy = NULL; struct IdeviceFfiError *err = NULL;
        int max_retries = 8; NSTimeInterval delay = 1.0;
        for (int i = 0; i < max_retries; i++) {
            if (i > 0) {
                NSLog(@"[Launch] Tunnel attempt %d failed: %s. Retrying in %.1f s...", i, err->message, delay);
                idevice_error_free(err); [NSThread sleepForTimeInterval:delay]; delay *= 1.5;
            }
            err = core_device_proxy_connect(provider, &proxy);
            if (!err) break;
        }

        if (err) { safeCompletion(NO, [NSString stringWithFormat:@"Tunnel Error: %s", err->message]); idevice_error_free(err); return; }

        uint16_t rsd_port = 0;
        err = core_device_proxy_get_server_rsd_port(proxy, &rsd_port);
        if (err) { safeCompletion(NO, [NSString stringWithFormat:@"RSD Error: %s", err->message]); idevice_error_free(err); core_device_proxy_free(proxy); return; }

        struct AdapterHandle *adapter = NULL;
        err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
        if (err) { safeCompletion(NO, [NSString stringWithFormat:@"Adapter Error: %s", err->message]); idevice_error_free(err); return; }
        proxy = NULL;

        struct ReadWriteOpaque *rsd_stream = NULL;
        err = adapter_connect(adapter, rsd_port, &rsd_stream);
        if (err) { safeCompletion(NO, [NSString stringWithFormat:@"Stream Error: %s", err->message]); idevice_error_free(err); adapter_free(adapter); return; }

        struct RsdHandshakeHandle *handshake = NULL;
        err = rsd_handshake_new(rsd_stream, &handshake);
        if (err) { safeCompletion(NO, [NSString stringWithFormat:@"Handshake Error: %s", err->message]); idevice_error_free(err); adapter_free(adapter); return; }
        rsd_stream = NULL;

        struct RemoteServerHandle *remoteserver = NULL;
        err = remote_server_connect_rsd(adapter, handshake, &remoteserver);
        if (err) { safeCompletion(NO, [NSString stringWithFormat:@"RemoteServer Error: %s", err->message]); idevice_error_free(err); rsd_handshake_free(handshake); adapter_free(adapter); return; }

        struct ProcessControlHandle *proc_control = NULL;
        err = process_control_new(remoteserver, &proc_control);
        if (err) { safeCompletion(NO, [NSString stringWithFormat:@"ProcessControl Error: %s", err->message]); idevice_error_free(err); remote_server_free(remoteserver); rsd_handshake_free(handshake); adapter_free(adapter); return; }

        uint64_t pid = 0;
        NSMutableArray *envArray = [NSMutableArray array];
        if (jitMode != JitModeNone) [envArray addObject:@"DEBUG_AUTOMATION_SCRIPTS=1"];
        const char **env = NULL;
        if (envArray.count > 0) {
            env = (const char **)malloc((envArray.count + 1) * sizeof(char *));
            for (NSUInteger i = 0; i < envArray.count; i++) env[i] = strdup([envArray[i] UTF8String]);
            env[envArray.count] = NULL;
        }
        err = process_control_launch_app(proc_control, [bid UTF8String], env, envArray.count, NULL, 0, NO, YES, &pid);
        if (env) { for (NSUInteger i = 0; i < envArray.count; i++) free((void *)env[i]); free(env); }

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Launch Error: %s", err->message]); idevice_error_free(err);
            process_control_free(proc_control); remote_server_free(remoteserver); rsd_handshake_free(handshake); adapter_free(adapter);
            return;
        }

        if (jitMode != JitModeNone && pid > 0) {
            process_control_disable_memory_limit(proc_control, pid);
            if (jitMode == JitModeJS) { [self activateUniversalJitSyncForPid:pid adapter:adapter handshake:handshake]; }
            else if (jitMode == JitModeNative) { [self activateGodSpeedJitSyncForPid:pid adapter:adapter handshake:handshake]; }
            safeCompletion(YES, [NSString stringWithFormat:@"Launched with JIT (%@, PID: %llu).", (jitMode == JitModeJS ? @"JS" : @"God-Speed"), pid]);
        } else { safeCompletion(YES, [NSString stringWithFormat:@"Launched successfully (PID: %llu).", pid]); }

        process_control_free(proc_control); remote_server_free(remoteserver); rsd_handshake_free(handshake); adapter_free(adapter);
    });
}

// God-Speed "Godly" Fast Utilities
static const uint8_t kHexLookup[256] = {
    ['0']=0,['1']=1,['2']=2,['3']=3,['4']=4,['5']=5,['6']=6,['7']=7,['8']=8,['9']=9,
    ['a']=10,['b']=11,['c']=12,['d']=13,['e']=14,['f']=15,
    ['A']=10,['B']=11,['C']=12,['D']=13,['E']=14,['F']=15
};

static inline uint64_t fastParseHex(const char *p, int len) {
    uint64_t v = 0;
    for (int i=0; i<len; i++) v = (v << 4) | kHexLookup[(uint8_t)p[i]];
    return v;
}

static inline uint64_t fastParseLEHex(const char *p, int len) {
    uint64_t v = 0;
    for (int i=0; i<len; i+=2) {
        uint8_t b = (kHexLookup[(uint8_t)p[i]] << 4) | kHexLookup[(uint8_t)p[i+1]];
        v |= ((uint64_t)b << (i*4));
    }
    return v;
}

static char u8toHexChar(uint8_t val) { return (val < 10) ? (val + '0') : (val + 87); }

static void writeAddr9(char *p, uint64_t a) {
    for(int i=0; i<9; i++) p[i] = u8toHexChar((a >> ((8-i)*4)) & 0xF);
}

static void calcGdbChecksum(char *s, char *out) {
    uint8_t sum = 0; while (*s != '#') sum += (uint8_t)*s++;
    out[0] = u8toHexChar(sum >> 4); out[1] = u8toHexChar(sum & 0xF);
}

// PC Instruction Cache
typedef struct { uint64_t pc; uint32_t instr; } InstrCache;
#define CACHE_SIZE 4
static InstrCache g_instr_cache[CACHE_SIZE];
static int g_cache_idx = 0;

static uint32_t get_cached_instr(uint64_t pc) {
    for(int i=0; i<CACHE_SIZE; i++) if(g_instr_cache[i].pc == pc) return g_instr_cache[i].instr;
    return 0;
}

static void set_cached_instr(uint64_t pc, uint32_t instr) {
    g_instr_cache[g_cache_idx].pc = pc; g_instr_cache[g_cache_idx].instr = instr;
    g_cache_idx = (g_cache_idx + 1) % CACHE_SIZE;
}

- (void)activateGodSpeedJitSyncForPid:(uint64_t)pid adapter:(struct AdapterHandle *)adapter handshake:(struct RsdHandshakeHandle *)handshake {
    struct DebugProxyHandle *debug_proxy = NULL;
    if (debug_proxy_connect_rsd(adapter, handshake, &debug_proxy)) return;

    // Send Raw Continue for speed
    auto sendRaw = [&](const char *raw) -> char* {
        debug_proxy_send_raw(debug_proxy, (const uint8_t*)raw, strlen(raw));
        char *r = NULL; debug_proxy_read_response(debug_proxy, &r); return r;
    };

    char buf[256]; sprintf(buf, "$vAttach;%llx#", pid);
    char cs[3]; calcGdbChecksum(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
    char *resp = sendRaw(buf); if (resp) free(resp);

    JSContext *jsCtx = nil; BOOL detached = NO; int loop = 0;
    while (!detached && loop++ < 10000) {
        resp = sendRaw("$c#63"); if (!resp) break;

        uint64_t x0_v=0, x1_v=0, x16_v=0, pc_v=0; char tid_s[64]={0};
        char *p = resp;
        while (*p) {
            if (strncmp(p, "thread:", 7)==0) { p+=7; int i=0; while(p[i]&&p[i]!=';') {tid_s[i]=p[i]; i++;} tid_s[i]=0; p+=i; }
            else if (strncmp(p, "00:", 3)==0) { x0_v = fastParseLEHex(p+3, 16); p+=19; }
            else if (strncmp(p, "01:", 3)==0) { x1_v = fastParseLEHex(p+3, 16); p+=19; }
            else if (strncmp(p, "10:", 3)==0) { x16_v = fastParseLEHex(p+3, 16); p+=19; }
            else if (strncmp(p, "20:", 3)==0) { pc_v = fastParseLEHex(p+3, 16); p+=19; }
            else p++;
        }

        if (tid_s[0] && pc_v > 0) {
            uint32_t instr = get_cached_instr(pc_v);
            if (!instr) {
                sprintf(buf, "$m%llx,4#", pc_v); calcGdbChecksum(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                char *ir = sendRaw(buf);
                if (ir) { instr = (uint32_t)fastParseLEHex(ir, 8); set_cached_instr(pc_v, instr); free(ir); }
            }

            if (instr) {
                uint32_t brk_imm = (instr >> 5) & 0xFFFF;
                if ((instr & 0xFFE0001F) == 0xD4200000) { // ARM64 BRK
                    // PC+4 jump
                    uint64_t n_pc = pc_v + 4; char n_le[17];
                    for(int i=0; i<8; i++) sprintf(n_le+i*2, "%02x", (uint8_t)((n_pc>>(i*8))&0xFF));
                    sprintf(buf, "$P20=%s;thread:%s#", n_le, tid_s); calcGdbChecksum(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                    char *pr = sendRaw(buf); if (pr) free(pr);

                    if (brk_imm == 0xf00d) {
                        if (x16_v == 0) detached = YES;
                        else if (x16_v == 1) { // PREPARE
                            uint64_t addr = x0_v;
                            if (!addr) {
                                sprintf(buf, "$_M%llx,rx#", x1_v); calcGdbChecksum(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                                char *xr = sendRaw(buf); if (xr) { addr = strtoull(xr, NULL, 16); free(xr); }
                            }
                            if (addr) {
                                uint32_t count = (uint32_t)(x1_v >> 14); if (!count && x1_v) count = 1;
                                char *m_buf = (char*)malloc(count * 19 + 4); uint64_t ca = addr;
                                for(uint32_t i=0; i<count; i++) {
                                    char *c = m_buf + i*19; c[0]='$'; c[1]='M'; c[11]=','; c[12]='1'; c[13]=':'; c[14]='6'; c[15]='9'; c[16]='#';
                                    writeAddr9(c+2, ca); calcGdbChecksum(c+1, c+17); ca += 16384;
                                }
                                for(uint32_t c=0; c<count; c+=1024) {
                                    uint32_t ts = (count-c > 1024) ? 1024 : (count-c);
                                    debug_proxy_send_raw(debug_proxy, (const uint8_t*)m_buf + c*19, ts*19);
                                    for(uint32_t j=0; j<ts; j++) { char *r=NULL; debug_proxy_read_response(debug_proxy, &r); if(r) free(r); }
                                }
                                free(m_buf);
                                char a_le[17]; for(int i=0; i<8; i++) sprintf(a_le+i*2, "%02x", (uint8_t)((addr>>(i*8))&0xFF));
                                sprintf(buf, "$P00=%s;thread:%s#", a_le, tid_s); calcGdbChecksum(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                                char *xr = sendRaw(buf); if (xr) free(xr);
                            }
                        }
                    } else if (brk_imm == 0x68) { // Inject
                        sprintf(buf, "$m%llx,%llx#", x0_v, x1_v); calcGdbChecksum(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                        char *mr = sendRaw(buf);
                        if (mr) {
                            char *sc = (char*)malloc(strlen(mr)/2+1);
                            int sl=0; for(int i=0; mr[i]&&mr[i+1]; i+=2) { uint8_t b=(kHexLookup[(uint8_t)mr[i]]<<4)|kHexLookup[(uint8_t)mr[i+1]]; if(!b)break; sc[sl++]=(char)b; } sc[sl]=0;
                            if (!jsCtx) {
                                jsCtx = [[JSContext alloc] init];
                                jsCtx[@"log"] = ^(NSString *m){ NSLog(@"[God Script] %@", m); };
                                jsCtx[@"send_command"] = ^NSString*(NSString *c){
                                    struct DebugserverCommandHandle *d = debugserver_command_new([c UTF8String], NULL, 0);
                                    char *dr=NULL; debug_proxy_send_command(debug_proxy, d, &dr); debugserver_command_free(d);
                                    NSString *ns = dr ? @(dr) : nil; if(dr) free(dr); return ns;
                                };
                            }
                            jsCtx[@"x0"]=@(x0_v); jsCtx[@"x1"]=@(x1_v); jsCtx[@"pc"]=@(pc_v); [jsCtx evaluateScript:@(sc)];
                            free(sc); free(mr);
                        }
                    }
                } else if (resp[0] == 'T') {
                    sprintf(buf, "$vCont;S%c%c:%s#", resp[1], resp[2], tid_s); calcGdbChecksum(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                    char *vr = sendRaw(buf); if (vr) free(vr);
                }
            }
        }
        free(resp);
    }
    sendRaw("$D#44"); debug_proxy_free(debug_proxy);
}

- (void)activateUniversalJitSyncForPid:(uint64_t)pid adapter:(struct AdapterHandle *)adapter handshake:(struct RsdHandshakeHandle *)handshake {
    struct DebugProxyHandle *debug_proxy = NULL;
    if (debug_proxy_connect_rsd(adapter, handshake, &debug_proxy)) return;
    JSContext *context = [[JSContext alloc] init];
    context[@"get_pid"] = ^uint64_t { return pid; };
    context[@"send_command"] = ^NSString *(NSString *cmdStr) {
        struct DebugserverCommandHandle *cmd = debugserver_command_new([cmdStr UTF8String], NULL, 0);
        char *resp_raw = NULL; struct IdeviceFfiError *e = debug_proxy_send_command(debug_proxy, cmd, &resp_raw);
        debugserver_command_free(cmd); if (e) { idevice_error_free(e); return nil; }
        NSString *resp = resp_raw ? [NSString stringWithUTF8String:resp_raw] : nil;
        if (resp_raw) free(resp_raw); return resp;
    };
    context[@"import_script"] = ^(NSString *filename) {
        NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [docsDir stringByAppendingPathComponent:filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) path = [[NSBundle mainBundle] pathForResource:[filename stringByDeletingPathExtension] ofType:[filename pathExtension]];
        NSError *e = nil; NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];
        if (content) { [[JSContext currentContext] evaluateScript:content]; return @"OK"; }
        else return [NSString stringWithFormat:@"ERROR: %@", e.localizedDescription];
    };
    context[@"prepare_memory_region"] = ^NSString *(uint64_t startAddr, uint64_t JITPagesSize) {
        uint32_t commandCount = (uint32_t)(JITPagesSize >> 14); uint32_t commandBufferSize = commandCount * 19;
        char* commandBuffer = malloc(commandBufferSize + 1); commandBuffer[commandBufferSize] = 0;
        uint64_t curAddr = startAddr;
        for(uint32_t i = 0; i < commandCount; i++) {
            char *cur = commandBuffer + i * 19; cur[0] = '$'; cur[1] = 'M'; cur[11] = ','; cur[12] = '1'; cur[13] = ':'; cur[14] = '6'; cur[15] = '9'; cur[16] = '#';
            for(int j=0; j<9; j++) cur[j+2] = u8toHexChar((curAddr >> ((8-j)*4)) & 0xF);
            calcGdbChecksum(cur + 1, cur + 17); curAddr += 16384;
        }
        for(uint32_t cur = 0; cur < commandCount; cur += 1024) {
            uint32_t toSend = (commandCount - cur > 1024) ? 1024 : (commandCount - cur);
            struct IdeviceFfiError *e = debug_proxy_send_raw(debug_proxy, (const uint8_t *)commandBuffer + cur * 19, toSend * 19);
            if (e) { idevice_error_free(e); free(commandBuffer); return @"ERROR_SEND"; }
            for(uint32_t j = 0; j < toSend; j++) { char *r = NULL; struct IdeviceFfiError *e2 = debug_proxy_read_response(debug_proxy, &r); if (r) free(r); if (e2) { idevice_error_free(e2); free(commandBuffer); return @"ERROR_READ"; } }
        }
        free(commandBuffer); return @"OK";
    };
    context[@"log"] = ^(NSString *msg) { NSLog(@"[JIT Script] %@", msg); };
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *scriptPath = [docsDir stringByAppendingPathComponent:@"universal.js"];
    NSString *script = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil];
    if (!script) { scriptPath = [[NSBundle mainBundle] pathForResource:@"universal" ofType:@"js"]; if (scriptPath) script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil]; }
    if (!script) script = kUniversalJitScript;
    [context evaluateScript:script];
    debug_proxy_free(debug_proxy);
}
@end
