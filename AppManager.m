#import "AppManager.h"
#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "HeartbeatManager.h"
#import "JITScripts.h"
#include <arm_neon.h>
#include <stdarg.h>

@implementation AppInfo
@end

// Omega JIT Session State
typedef struct {
    struct DebugProxyHandle *proxy;
    char *pktBuf;
    size_t pktBufSize;
    BOOL noAck;
} OmegaSession;

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
        err = process_control_launch_app(proc_control, [bid UTF8String], env, (uint32_t)envArray.count, NULL, 0, NO, YES, &pid);
        if (env) { for (NSUInteger i = 0; i < envArray.count; i++) free((void *)env[i]); free(env); }

        if (err) {
            safeCompletion(NO, [NSString stringWithFormat:@"Launch Error: %s", err->message]); idevice_error_free(err);
            process_control_free(proc_control); remote_server_free(remoteserver); rsd_handshake_free(handshake); adapter_free(adapter);
            return;
        }

        if (jitMode != JitModeNone && pid > 0) {
            process_control_disable_memory_limit(proc_control, pid);
            if (jitMode == JitModeJS) { [self activateUniversalJitSyncForPid:pid adapter:adapter handshake:handshake]; }
            else if (jitMode == JitModeNative) { [self activateGodlyNativeJitSyncForPid:pid adapter:adapter handshake:handshake]; }
            safeCompletion(YES, [NSString stringWithFormat:@"Launched with JIT (%@, PID: %llu).", (jitMode == JitModeJS ? @"JS" : @"God-Speed"), pid]);
        } else { safeCompletion(YES, [NSString stringWithFormat:@"Launched successfully (PID: %llu).", pid]); }

        process_control_free(proc_control); remote_server_free(remoteserver); rsd_handshake_free(handshake); adapter_free(adapter);
    });
}

// Omega-God GDB Utilities
static const uint8_t kHex[256] = {
    ['0']=0,['1']=1,['2']=2,['3']=3,['4']=4,['5']=5,['6']=6,['7']=7,['8']=8,['9']=9,
    ['a']=10,['b']=11,['c']=12,['d']=13,['e']=14,['f']=15,
    ['A']=10,['B']=11,['C']=12,['D']=13,['E']=14,['F']=15
};

static inline char vToH(uint8_t v) { return "0123456789abcdef"[v & 0xF]; }

static inline uint8_t omega_neon_sum(const uint8_t *p, size_t l) {
    if (l == 0) return 0;
    uint8x16_t vsum = vdupq_n_u8(0); size_t i = 0;
    for (; i + 16 <= l; i += 16) vsum = vaddq_u8(vsum, vld1q_u8(p + i));
    uint8_t a[16]; vst1q_u8(a, vsum); uint8_t s = 0;
    for (int j = 0; j < 16; j++) s += a[j];
    for (; i < l; i++) s += p[i];
    return s;
}

static inline void writeLE64Hex(char *out, uint64_t v) {
    for (int i=0; i<8; i++) {
        uint8_t b = (v >> (i * 8)) & 0xFF;
        out[i*2] = vToH(b >> 4); out[i*2+1] = vToH(b & 0xF);
    }
    out[16] = 0;
}

static inline uint64_t decodeLE64(const char *p) {
    uint64_t v = 0;
    for (int i=0; i<8; i++) {
        uint8_t b = (kHex[(uint8_t)p[i*2]] << 4) | kHex[(uint8_t)p[i*2+1]];
        v |= ((uint64_t)b << (i * 8));
    }
    return v;
}

static inline uint32_t decodeLE32(const char *p) {
    uint32_t v = 0;
    for (int i=0; i<4; i++) {
        uint8_t b = (kHex[(uint8_t)p[i*2]] << 4) | kHex[(uint8_t)p[i*2+1]];
        v |= (b << (i * 8));
    }
    return v;
}

static char* omegaExchange(OmegaSession *s, const char *pkt) {
    int retries = 3; size_t len = strlen(pkt);
    while (retries--) {
        debug_proxy_send_raw(s->proxy, (const uint8_t*)pkt, len);
        char *r = NULL; struct IdeviceFfiError *err = debug_proxy_read_response(s->proxy, &r);
        if (err) { idevice_error_free(err); continue; }
        if (!r) continue;
        if (!s->noAck) {
            if (r[0] == '-') { free(r); continue; }
            if (r[0] == '+') {
                if (strlen(r) == 1) { free(r); r = NULL; debug_proxy_read_response(s->proxy, &r); if (!r) continue; }
                else { char *old = r; r = strdup(old + 1); free(old); }
            }
        }
        return r;
    }
    return NULL;
}

static int omegaBuildPkt(OmegaSession *s, const char *fmt, ...) {
    s->pktBuf[0] = '$'; va_list a; va_start(a, fmt);
    int l = vsnprintf(s->pktBuf + 1, (int)s->pktBufSize - 5, fmt, a); va_end(a);
    uint8_t sum = omega_neon_sum((uint8_t*)s->pktBuf + 1, (size_t)l);
    s->pktBuf[l+1] = '#'; s->pktBuf[l+2] = vToH(sum >> 4); s->pktBuf[l+3] = vToH(sum & 0xF); s->pktBuf[l+4] = 0;
    return l + 4;
}

typedef struct { uint64_t x0, x1, x16, pc; char tid[64]; } GodState;

static void scanStopPkt(const char *s, GodState *st) {
    if (!s) return;
    const char *p = s; if (*p == 'T') p += 3;
    while (*p) {
        if (p[0] == 't' && p[1] == 'h') { // thread:
            p += 7; int i = 0; while (*p && *p != ';' && i < 63) st->tid[i++] = *p++;
            st->tid[i] = 0;
        } else if (p[2] == ':') {
            uint64_t v = decodeLE64(p + 3);
            if (p[0] == '2' && p[1] == '0') st->pc = v;
            else if (p[0] == '1' && p[1] == '0') st->x16 = v;
            else if (p[0] == '0') {
                if (p[1] == '0') st->x0 = v;
                else if (p[1] == '1') st->x1 = v;
            }
            p += 19;
        }
        while (*p && *p != ';' ) p++;
        if (*p == ';') p++;
    }
}

typedef struct { uint64_t pc; uint32_t instr; } GCache;
static __thread GCache g_tl_cache[16]; static __thread int g_tl_p = 0;

- (void)activateGodlyNativeJitSyncForPid:(uint64_t)pid adapter:(struct AdapterHandle *)adapter handshake:(struct RsdHandshakeHandle *)handshake {
    NSLog(@"[Omega-God] Starting Synchronized Session...");
    struct DebugProxyHandle *proxy = NULL;
    if (debug_proxy_connect_rsd(adapter, handshake, &proxy)) return;

    OmegaSession s = { .proxy = proxy, .pktBufSize = 65536, .noAck = NO };
    s.pktBuf = (char*)malloc(s.pktBufSize);

    omegaBuildPkt(&s, "vAttach;%llx", pid);
    char *resp = omegaExchange(&s, s.pktBuf); if (resp) free(resp);

    // Try to enable No-Ack mode for speed
    omegaBuildPkt(&s, "QStartNoAckMode");
    resp = omegaExchange(&s, s.pktBuf); if (resp && strcmp(resp, "OK") == 0) s.noAck = YES; if (resp) free(resp);

    JSContext *jsCtx = [[JSContext alloc] init];
    jsCtx[@"log"] = ^(NSString *m){ NSLog(@"[Omega Script] %@", m); };

    BOOL detached = NO;
    const char *kVCont = "$vCont;c#a8";

    while (!detached) {
        resp = omegaExchange(&s, kVCont);
        if (!resp) { NSLog(@"[Omega] Connection Lost."); break; }

        GodState st = {0}; scanStopPkt(resp, &st);
        if (st.tid[0] && st.pc > 0) {
            uint32_t instr = 0;
            for(int i=0; i<16; i++) if(g_tl_cache[i].pc == st.pc) { instr = g_tl_cache[i].instr; break; }
            if (!instr) {
                omegaBuildPkt(&s, "m%llx,4", st.pc);
                char *ir = omegaExchange(&s, s.pktBuf);
                if (ir) { instr = decodeLE32(ir); g_tl_cache[g_tl_p].pc = st.pc; g_tl_cache[g_tl_p].instr = instr; g_tl_p = (g_tl_p+1)%16; free(ir); }
            }

            if (instr) {
                if ((instr & 0xFFE0001F) == 0xD4200000) { // ARM64 BRK
                    uint32_t imm = (instr >> 5) & 0xFFFF;
                    uint64_t npc = st.pc + 4; char nle[17]; writeLE64Hex(nle, npc);
                    omegaBuildPkt(&s, "P20=%s;thread:%s", nle, st.tid);
                    char *pr = omegaExchange(&s, s.pktBuf); if (pr) free(pr);

                    if (imm == 0xf00d) {
                        if (st.x16 == 0) detached = YES;
                        else if (st.x16 == 1) { // Omega PREPARE
                            uint64_t addr = st.x0;
                            if (!addr) {
                                omegaBuildPkt(&s, "_M%llx,rx", st.x1);
                                char *xr = omegaExchange(&s, s.pktBuf); if (xr) { addr = strtoull(xr, NULL, 16); free(xr); }
                            }
                            if (addr) {
                                uint32_t total = (uint32_t)st.x1; uint32_t sent = 0;
                                while (sent < total) {
                                    uint32_t chunk = (total - sent > 16384) ? 16384 : (total - sent);
                                    int l = sprintf(s.pktBuf + 1, "M%llx,%x:", addr + sent, chunk);
                                    for(uint32_t j=0; j<chunk; j++) { s.pktBuf[l+1+j*2] = '6'; s.pktBuf[l+1+j*2+1] = '9'; }
                                    s.pktBuf[0] = '$'; size_t payload_len = (size_t)(l + chunk * 2);
                                    uint8_t sum = omega_neon_sum((uint8_t*)s.pktBuf + 1, payload_len);
                                    s.pktBuf[payload_len + 1] = '#'; s.pktBuf[payload_len + 2] = vToH(sum >> 4); s.pktBuf[payload_len + 3] = vToH(sum & 0xF); s.pktBuf[payload_len + 4] = 0;
                                    debug_proxy_send_raw(proxy, (const uint8_t*)s.pktBuf, payload_len + 4);
                                    char *r = NULL; debug_proxy_read_response(proxy, &r); if(r) free(r);
                                    sent += chunk;
                                }
                                char ale[17]; writeLE64Hex(ale, addr);
                                omegaBuildPkt(&s, "P00=%s;thread:%s", ale, st.tid);
                                char *xr = omegaExchange(&s, s.pktBuf); if (xr) free(xr);
                            }
                        }
                    } else if (imm == 0x68) {
                        omegaBuildPkt(&s, "m%llx,%llx", st.x0, st.x1);
                        char *mr = omegaExchange(&s, s.pktBuf);
                        if (mr) {
                            @autoreleasepool {
                                int sl = (int)strlen(mr)/2; char *sc = (char*)malloc(sl+1);
                                for(int i=0; i<sl; i++) { uint8_t b=(kHex[(uint8_t)mr[i*2]]<<4)|kHex[(uint8_t)mr[i*2+1]]; sc[i]=(char)b; } sc[sl]=0;
                                jsCtx[@"x0"]=@(st.x0); jsCtx[@"x1"]=@(st.x1); jsCtx[@"pc"]=@(st.pc); [jsCtx evaluateScript:@(sc)];
                                free(sc);
                            }
                            free(mr);
                        }
                    }
                } else if (resp[0] == 'T') {
                    omegaBuildPkt(&s, "vCont;S%c%c:%s", resp[1], resp[2], st.tid);
                    char *vr = omegaExchange(&s, s.pktBuf); if (vr) free(vr);
                }
            }
        }
        free(resp);
    }
    // Safe Detach Sequence
    omegaBuildPkt(&s, "vCont;c");
    char *dr1 = omegaExchange(&s, s.pktBuf); if(dr1) free(dr1);
    omegaBuildPkt(&s, "D");
    char *dr2 = omegaExchange(&s, s.pktBuf); if(dr2) free(dr2);

    free(s.pktBuf);
    debug_proxy_free(proxy);
    NSLog(@"[Omega-God] Engine Shutdown Cleanly.");
}

- (void)activateUniversalJitSyncForPid:(uint64_t)pid adapter:(struct AdapterHandle *)adapter handshake:(struct RsdHandshakeHandle *)handshake {
    struct DebugProxyHandle *proxy = NULL;
    if (debug_proxy_connect_rsd(adapter, handshake, &proxy)) return;
    JSContext *context = [[JSContext alloc] init];
    context[@"get_pid"] = ^uint64_t { return pid; };
    context[@"send_command"] = ^NSString *(NSString *cmdStr) {
        struct DebugserverCommandHandle *cmd = debugserver_command_new([cmdStr UTF8String], NULL, 0);
        char *resp_raw = NULL; struct IdeviceFfiError *e = debug_proxy_send_command(proxy, cmd, &resp_raw);
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
        OmegaSession os = { .proxy = proxy, .pktBufSize = 65536, .noAck = YES };
        os.pktBuf = (char*)malloc(os.pktBufSize);
        uint32_t total = (uint32_t)JITPagesSize; uint32_t sent = 0;
        while (sent < total) {
            uint32_t chunk = (total - sent > 16384) ? 16384 : (total - sent);
            int l = sprintf(os.pktBuf + 1, "M%llx,%x:", startAddr + sent, chunk);
            for(uint32_t j=0; j<chunk; j++) { os.pktBuf[l+1+j*2] = '6'; os.pktBuf[l+1+j*2+1] = '9'; }
            os.pktBuf[0] = '$'; size_t payload_len = (size_t)(l + chunk * 2);
            uint8_t sum = omega_neon_sum((uint8_t*)os.pktBuf + 1, payload_len);
            os.pktBuf[payload_len + 1] = '#'; os.pktBuf[payload_len + 2] = vToH(sum >> 4); os.pktBuf[payload_len + 3] = vToH(sum & 0xF); os.pktBuf[payload_len + 4] = 0;
            struct IdeviceFfiError *e = debug_proxy_send_raw(proxy, (const uint8_t *)os.pktBuf, (size_t)(payload_len + 4));
            if (e) { idevice_error_free(e); free(os.pktBuf); return @"ERROR_SEND"; }
            char *r = NULL; debug_proxy_read_response(proxy, &r); if (r) free(r);
            sent += chunk;
        }
        free(os.pktBuf); return @"OK";
    };
    context[@"log"] = ^(NSString *msg) { NSLog(@"[JIT Script] %@", msg); };
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *scriptPath = [docsDir stringByAppendingPathComponent:@"universal.js"];
    NSString *script = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil];
    if (!script) { scriptPath = [[NSBundle mainBundle] pathForResource:@"universal" ofType:@"js"]; if (scriptPath) script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil]; }
    if (!script) script = kUniversalJitScript;
    [context evaluateScript:script];
    debug_proxy_free(proxy);
}
@end
