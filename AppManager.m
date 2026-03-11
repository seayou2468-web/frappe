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

// Godly High-Performance Utilities (V6 - Final & Hardened)
static const uint8_t kH[256] = {
    ['0']=0,['1']=1,['2']=2,['3']=3,['4']=4,['5']=5,['6']=6,['7']=7,['8']=8,['9']=9,
    ['a']=10,['b']=11,['c']=12,['d']=13,['e']=14,['f']=15,
    ['A']=10,['B']=11,['C']=12,['D']=13,['E']=14,['F']=15
};

static inline char uToH(uint8_t v) { return (v < 10) ? (v + '0') : (v + 87); }

static uint64_t decLE64(const char *p) {
    uint64_t v = 0;
    for (int i=0; i<8; i++) {
        uint64_t b = (kH[(uint8_t)p[i*2]] << 4) | kH[(uint8_t)p[i*2+1]];
        v |= (b << (i * 8));
    }
    return v;
}

static uint32_t decLE32(const char *p) {
    uint32_t v = 0;
    for (int i=0; i<4; i++) {
        uint32_t b = (kH[(uint8_t)p[i*2]] << 4) | kH[(uint8_t)p[i*2+1]];
        v |= (b << (i * 8));
    }
    return v;
}

static void setGdbCS(const char *s, char *o) {
    uint8_t sum = 0; while (*s != '#') sum += (uint8_t)*s++;
    o[0] = uToH(sum >> 4); o[1] = uToH(sum & 0xF);
}

typedef struct { uint64_t x0, x1, x16, pc; char tid[64]; } StopCtx;

static void fastParseStop(const char *s, StopCtx *ctx) {
    const char *p = s; if (*p == 'T') p += 3;
    while (*p) {
        if (p[0] == 't' && p[1] == 'h') { // thread:
            p += 7; int i = 0; while (*p && *p != ';' && i < 63) ctx->tid[i++] = *p++;
            ctx->tid[i] = 0;
        } else if (p[2] == ':') {
            uint64_t v = decLE64(p + 3);
            if (p[0] == '2' && p[1] == '0') ctx->pc = v;
            else if (p[0] == '1' && p[1] == '0') ctx->x16 = v;
            else if (p[0] == '0') {
                if (p[1] == '0') ctx->x0 = v;
                else if (p[1] == '1') ctx->x1 = v;
            }
            p += 19;
        }
        while (*p && *p != ';') p++;
        if (*p == ';') p++;
    }
}

// Private Variadic GDB helper (Bypasses debugserver_command_new overhead)
static char* gdbSend(struct DebugProxyHandle *proxy, const char *fmt, ...) {
    char pkt[2048]; va_list args; va_start(args, fmt);
    int len = vsnprintf(pkt, sizeof(pkt), fmt, args); va_end(args);
    debug_proxy_send_raw(proxy, (const uint8_t*)pkt, len);
    char *r = NULL; debug_proxy_read_response(proxy, &r); return r;
}

- (void)activateGodSpeedJitSyncForPid:(uint64_t)pid adapter:(struct AdapterHandle *)adapter handshake:(struct RsdHandshakeHandle *)handshake {
    struct DebugProxyHandle *proxy = NULL;
    if (debug_proxy_connect_rsd(adapter, handshake, &proxy)) return;

    char buf[1024]; sprintf(buf, "$vAttach;%llx#", pid);
    char cs[3]; setGdbCS(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
    char *resp = gdbSend(proxy, "%s", buf); if (resp) free(resp);

    static struct { uint64_t pc; uint32_t instr; } cache[4]; static int cp = 0;

    JSContext *jsCtx = [[JSContext alloc] init];
    jsCtx[@"log"] = ^(NSString *m){ NSLog(@"[God Script] %@", m); };
    jsCtx[@"send_command"] = ^NSString*(NSString *c){
        struct DebugserverCommandHandle *d = debugserver_command_new([c UTF8String], NULL, 0);
        char *dr=NULL; debug_proxy_send_command(proxy, d, &dr); debugserver_command_free(d);
        NSString *ns = dr ? @(dr) : nil; if(dr) free(dr); return ns;
    };

    BOOL detached = NO; int loop = 0;
    while (!detached && loop++ < 10000) {
        resp = gdbSend(proxy, "$c#63"); if (!resp) break;

        StopCtx ctx = {0}; fastParseStop(resp, &ctx);
        if (ctx.tid[0] && ctx.pc > 0) {
            uint32_t instr = 0;
            for(int i=0; i<4; i++) if(cache[i].pc == ctx.pc) { instr = cache[i].instr; break; }
            if (!instr) {
                sprintf(buf, "$m%llx,4#", ctx.pc); setGdbCS(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                char *ir = gdbSend(proxy, "%s", buf);
                if (ir) { instr = decLE32(ir); cache[cp].pc = ctx.pc; cache[cp].instr = instr; cp = (cp+1)%4; free(ir); }
            }

            if (instr) {
                if ((instr & 0xFFFFFC1F) == 0xD4200000) { // Precise ARM64 BRK Mask
                    uint32_t imm = (instr >> 5) & 0xFFFF;
                    uint64_t npc = ctx.pc + 4; char nle[17];
                    for(int i=0; i<8; i++) sprintf(nle+i*2, "%02x", (uint8_t)((npc>>(i*8))&0xFF));
                    sprintf(buf, "$P20=%s;thread:%s#", nle, ctx.tid); setGdbCS(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                    char *pr = gdbSend(proxy, "%s", buf); if (pr) free(pr);

                    if (imm == 0xf00d) {
                        if (ctx.x16 == 0) detached = YES;
                        else if (ctx.x16 == 1) { // PREPARE (Streaming implementation)
                            uint64_t addr = ctx.x0;
                            if (!addr) {
                                sprintf(buf, "$_M%llx,rx#", ctx.x1); setGdbCS(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                                char *xr = gdbSend(proxy, "%s", buf); if (xr) { addr = strtoull(xr, NULL, 16); free(xr); }
                            }
                            if (addr) {
                                uint32_t total = (uint32_t)ctx.x1; uint32_t sent = 0;
                                char mpkt[64];
                                while (sent < total) {
                                    uint64_t ca = addr + sent;
                                    sprintf(mpkt, "$M");
                                    for(int j=0; j<9; j++) mpkt[j+2] = uToH((ca >> ((8-j)*4)) & 0xF);
                                    sprintf(mpkt+11, ",1:69#"); setGdbCS(mpkt+1, mpkt+17);
                                    debug_proxy_send_raw(proxy, (const uint8_t*)mpkt, 19);
                                    char *r = NULL; debug_proxy_read_response(proxy, &r); if(r) free(r);
                                    sent += 16384;
                                }
                                char ale[17]; for(int i=0; i<8; i++) sprintf(ale+i*2, "%02x", (uint8_t)((addr>>(i*8))&0xFF));
                                sprintf(buf, "$P00=%s;thread:%s#", ale, ctx.tid); setGdbCS(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                                char *xr = gdbSend(proxy, "%s", buf); if (xr) free(xr);
                            }
                        }
                    } else if (imm == 0x68) {
                        sprintf(buf, "$m%llx,%llx#", ctx.x0, ctx.x1); setGdbCS(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                        char *mr = gdbSend(proxy, "%s", buf);
                        if (mr) {
                            @autoreleasepool {
                                int sl = (int)strlen(mr)/2; char *sc = (char*)malloc(sl+1);
                                for(int i=0; i<sl; i++) { uint8_t b=(kH[(uint8_t)mr[i*2]]<<4)|kH[(uint8_t)mr[i*2+1]]; sc[i]=(char)b; } sc[sl]=0;
                                jsCtx[@"x0"]=@(ctx.x0); jsCtx[@"x1"]=@(ctx.x1); jsCtx[@"pc"]=@(ctx.pc); [jsCtx evaluateScript:@(sc)];
                                free(sc);
                            }
                            free(mr);
                        }
                    }
                } else if (resp[0] == 'T') {
                    sprintf(buf, "$vCont;S%c%c:%s#", resp[1], resp[2], ctx.tid); setGdbCS(buf+1, cs); sprintf(buf+strlen(buf), "%s", cs);
                    char *vr = gdbSend(proxy, "%s", buf); if (vr) free(vr);
                }
            }
        }
        free(resp);
    }
    gdbSend(proxy, "$vCont;c#a8"); gdbSend(proxy, "$D#44"); debug_proxy_free(proxy);
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
        uint32_t commandCount = (uint32_t)(JITPagesSize >> 14); uint32_t commandBufferSize = commandCount * 19;
        char* commandBuffer = malloc(commandBufferSize + 1); commandBuffer[commandBufferSize] = 0;
        uint64_t curAddr = startAddr;
        for(uint32_t i = 0; i < commandCount; i++) {
            char *cur = commandBuffer + i * 19; cur[0] = '$'; cur[1] = 'M'; cur[11] = ','; cur[12] = '1'; cur[13] = ':'; cur[14] = '6'; cur[15] = '9'; cur[16] = '#';
            for(int j=0; j<9; j++) cur[j+2] = uToH((curAddr >> ((8-j)*4)) & 0xF);
            setGdbCS(cur + 1, cur + 17); curAddr += 16384;
        }
        for(uint32_t cur = 0; cur < commandCount; cur += 1024) {
            uint32_t toSend = (commandCount - cur > 1024) ? 1024 : (commandCount - cur);
            struct IdeviceFfiError *e = debug_proxy_send_raw(proxy, (const uint8_t *)commandBuffer + cur * 19, toSend * 19);
            if (e) { idevice_error_free(e); free(commandBuffer); return @"ERROR_SEND"; }
            for(uint32_t j = 0; j < toSend; j++) { char *r = NULL; struct IdeviceFfiError *e2 = debug_proxy_read_response(proxy, &r); if (r) free(r); if (e2) { idevice_error_free(e2); free(commandBuffer); return @"ERROR_READ"; } }
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
    debug_proxy_free(proxy);
}
@end
