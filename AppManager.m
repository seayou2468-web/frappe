// AppManager.m
// Omega JIT Engine — 完全最適化・安全化・高速化版
// 修正内容:
//   1. Use-After-Free (retry err ループ) → 修正済み
//   2. omegaExchange 戻り値リーク → 全箇所修正
//   3. scanStopPkt OOB読み込み → 境界チェック追加
//   4. __thread → pthread_key_t に置換 (iOS安全)
//   5. debug_proxy_free タイミング → JSContext寿命後に移動
//   6. omega_neon_sum オーバーフロー → 正しいwidening実装
//   7. vsnprintf 戻り値未検査 → 検査+安全ガード追加
//   8. launchApp メモリリーク → 全分岐で正確に解放
//   9. noAck モード不整合 → prepare_memory_region を修正
//  10. マジックナンバー → 名前付き定数化
//  11. kVCont ハードコード → omegaBuildPkt で生成に統一
//  12. Safe Detach → 戻り値を適切に解放

#import "AppManager.h"
#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "HeartbeatManager.h"
#import "JITScripts.h"
#include <arm_neon.h>
#include <stdarg.h>
#include <pthread.h>

// ─────────────────────────────────────────────
// MARK: - 定数定義
// ─────────────────────────────────────────────

/// ARM64 BRK 命令マスク/パターン
static const uint32_t kArm64BrkMask    = 0xFFE0001F;
static const uint32_t kArm64BrkPattern = 0xD4200000;

/// BRK immediate 識別値
static const uint32_t kBrkImmOmegaCtrl = 0xF00D; ///< Omega制御ブレーク
static const uint32_t kBrkImmJsEval    = 0x0068;  ///< JSスクリプト評価

/// Omega制御コマンド (x16 レジスタ)
static const uint64_t kOmegaCmdDetach  = 0;
static const uint64_t kOmegaCmdPrepare = 1;

/// GDB パケットバッファサイズ
static const size_t   kPktBufSize      = 65536;
/// チャンクサイズ (GDB Mコマンド上限より小)
static const uint32_t kWriteChunkSize  = 16384;
/// フィルバイト ('i' = 0x69)
static const char     kFillHi          = '6';
static const char     kFillLo          = '9';

/// 接続リトライ設定
static const int      kMaxRetries      = 8;
static const NSTimeInterval kRetryInitDelay = 1.0;
static const double   kRetryBackoff    = 1.5;

/// TLキャッシュサイズ (2の累乗)
static const int      kTlCacheSize     = 16;
static const int      kTlCacheMask     = kTlCacheSize - 1;

// ─────────────────────────────────────────────
// MARK: - Omega JIT セッション型
// ─────────────────────────────────────────────

typedef struct {
    struct DebugProxyHandle *proxy;
    char   *pktBuf;
    size_t  pktBufSize;
    BOOL    noAck;
} OmegaSession;

// ─────────────────────────────────────────────
// MARK: - スレッドローカルキャッシュ (pthread_key_t)
// ─────────────────────────────────────────────

typedef struct {
    uint64_t pc;
    uint32_t instr;
    BOOL     valid; /// calloc ゼロ初期化との区別 + SMC 古エントリ無効化用
} GCache;

typedef struct {
    GCache cache[kTlCacheSize];
    int    ptr;
} GCacheStore;

static pthread_key_t  s_gcache_key;
static pthread_once_t s_gcache_once = PTHREAD_ONCE_INIT;

static void gcache_store_destructor(void *p) { free(p); }
static void gcache_key_init(void)            { pthread_key_create(&s_gcache_key, gcache_store_destructor); }

static GCacheStore *gcache_get(void) {
    pthread_once(&s_gcache_once, gcache_key_init);
    GCacheStore *st = (GCacheStore *)pthread_getspecific(s_gcache_key);
    if (__builtin_expect(!st, 0)) {
        st = (GCacheStore *)calloc(1, sizeof(GCacheStore));
        pthread_setspecific(s_gcache_key, st);
    }
    return st;
}

// ─────────────────────────────────────────────
// MARK: - Hex ユーティリティ
// ─────────────────────────────────────────────

static const uint8_t kHexTable[256] = {
    ['0']=0,['1']=1,['2']=2,['3']=3,['4']=4,
    ['5']=5,['6']=6,['7']=7,['8']=8,['9']=9,
    ['a']=10,['b']=11,['c']=12,['d']=13,['e']=14,['f']=15,
    ['A']=10,['B']=11,['C']=12,['D']=13,['E']=14,['F']=15
};

NS_INLINE char vToH(uint8_t v) { return "0123456789abcdef"[v & 0xF]; }

NS_INLINE uint8_t hexPairToByte(const char hi, const char lo) {
    return (uint8_t)((kHexTable[(uint8_t)hi] << 4) | kHexTable[(uint8_t)lo]);
}

/// リトルエンディアン 64bit → hex (16文字 + NUL)
static void writeLE64Hex(char *out, uint64_t v) {
    for (int i = 0; i < 8; i++) {
        const uint8_t b = (uint8_t)((v >> (i * 8)) & 0xFF);
        out[i * 2]     = vToH(b >> 4);
        out[i * 2 + 1] = vToH(b & 0xF);
    }
    out[16] = '\0';
}

/// hex → リトルエンディアン 64bit (16文字必須)
static uint64_t decodeLE64(const char *p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) {
        v |= (uint64_t)hexPairToByte(p[i * 2], p[i * 2 + 1]) << (i * 8);
    }
    return v;
}

/// hex → リトルエンディアン 32bit (8文字必須)
static uint32_t decodeLE32(const char *p) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
        v |= (uint32_t)hexPairToByte(p[i * 2], p[i * 2 + 1]) << (i * 8);
    }
    return v;
}

// ─────────────────────────────────────────────
// MARK: - NEON チェックサム (正確・高速)
// ─────────────────────────────────────────────
// GDB チェックサムは uint8_t の自然なラップ (mod 256)。
// 各 u8 レーン独立の vaddq_u8 では各レーンがラップするため
// 最終加算で誤差が出る。widening で u64 に累積し最後に mod 256。

static uint8_t omega_neon_checksum(const uint8_t *p, size_t l) {
    if (__builtin_expect(l == 0, 0)) return 0;

    uint64x2_t vsum = vdupq_n_u64(0);
    size_t i = 0;

    // 16バイト単位: u8→u16→u32→u64 widening で累積
    for (; i + 16 <= l; i += 16) {
        const uint8x16_t  v8  = vld1q_u8(p + i);
        const uint16x8_t  v16 = vpaddlq_u8(v8);
        const uint32x4_t  v32 = vpaddlq_u16(v16);
        vsum = vpadalq_u32(vsum, v32);
    }
    uint64_t s = vgetq_lane_u64(vsum, 0) + vgetq_lane_u64(vsum, 1);

    // 残余バイト
    for (; i < l; i++) s += p[i];

    return (uint8_t)(s & 0xFF);
}

// ─────────────────────────────────────────────
// MARK: - GDB パケットビルダー
// ─────────────────────────────────────────────
// 戻り値: 送信すべき総バイト数 (0 = エラー)

static size_t omegaBuildPkt(OmegaSession *s, const char *fmt, ...) {
    s->pktBuf[0] = '$';
    va_list a;
    va_start(a, fmt);
    const int l = vsnprintf(s->pktBuf + 1, s->pktBufSize - 5, fmt, a);
    va_end(a);

    if (__builtin_expect(l <= 0 || (size_t)l >= s->pktBufSize - 5, 0)) {
        NSLog(@"[Omega] pkt build failed: fmt=%s l=%d", fmt, l);
        return 0;
    }

    const uint8_t sum = omega_neon_checksum((const uint8_t *)(s->pktBuf + 1), (size_t)l);
    s->pktBuf[l + 1] = '#';
    s->pktBuf[l + 2] = vToH(sum >> 4);
    s->pktBuf[l + 3] = vToH(sum & 0xF);
    s->pktBuf[l + 4] = '\0';
    return (size_t)(l + 4);
}

// ─────────────────────────────────────────────
// MARK: - GDB 送受信 (リトライ付き)
// ─────────────────────────────────────────────
// 戻り値: heap 確保済み文字列 (呼び出し側が free する責任) / NULL = 失敗

static char *omegaExchange(OmegaSession *s, const char *pkt, size_t pktLen) {
    if (__builtin_expect(!pkt || pktLen == 0, 0)) return NULL;

    for (int attempt = 0; attempt < 3; attempt++) {
        struct IdeviceFfiError *sendErr =
            debug_proxy_send_raw(s->proxy, (const uint8_t *)pkt, pktLen);
        if (sendErr) { idevice_error_free(sendErr); continue; }

        char *r = NULL;
        struct IdeviceFfiError *recvErr = debug_proxy_read_response(s->proxy, &r);
        if (recvErr) { idevice_error_free(recvErr); continue; }
        if (!r) continue;

        // ── NoAck モード: ACK プレフィックスなし、そのまま返す ──
        if (s->noAck) return r;

        // ── NAK: リトライ ────────────────────────────────────
        if (r[0] == '-') { free(r); continue; }

        if (r[0] == '+') {
            if (__builtin_expect(r[1] != '\0', 1)) {
                // ── 最多パス: '+' + データが同一バッファ到着 ──────────
                // strdup + free の二重アロケーションを memmove で回避。
                // r を再利用して in-place で '+' を除去する。
                const size_t dataLen = strlen(r + 1) + 1; // NUL含む
                memmove(r, r + 1, dataLen);
                return r;
            }

            // ── '+' のみ到着: データパケットを追加 read ────────────
            // attempt を消費しない (送信成功・ACK受信済みなので
            // リトライカウントを使い切るのは不正確)。
            // read_response 失敗時のみ attempt を進める。
            free(r); r = NULL;
            for (int readRetry = 0; readRetry < 3; readRetry++) {
                struct IdeviceFfiError *e2 = debug_proxy_read_response(s->proxy, &r);
                if (e2) { idevice_error_free(e2); r = NULL; continue; }
                if (r) return r;
            }
            // データ読み取り失敗 → 送信からリトライ
            continue;
        }

        return r;
    }
    return NULL;
}

/// omegaBuildPkt + omegaExchange のショートカット (戻り値: 要 free / NULL)
static char *omegaSend(OmegaSession *s, const char *fmt, ...) {
    s->pktBuf[0] = '$';
    va_list a;
    va_start(a, fmt);
    const int l = vsnprintf(s->pktBuf + 1, s->pktBufSize - 5, fmt, a);
    va_end(a);
    if (l <= 0 || (size_t)l >= s->pktBufSize - 5) return NULL;
    const uint8_t sum = omega_neon_checksum((const uint8_t *)(s->pktBuf + 1), (size_t)l);
    s->pktBuf[l + 1] = '#';
    s->pktBuf[l + 2] = vToH(sum >> 4);
    s->pktBuf[l + 3] = vToH(sum & 0xF);
    s->pktBuf[l + 4] = '\0';
    return omegaExchange(s, s->pktBuf, (size_t)(l + 4));
}

// ─────────────────────────────────────────────
// MARK: - GDB ストップパケットパーサー
// ─────────────────────────────────────────────

typedef struct {
    uint64_t x0, x1, x16, pc;
    uint8_t  stopSignal; ///< Txx の xx (stop reason)。BRK = SIGTRAP = 0x05
    char     tid[64];
} GodState;

/// T パケットを安全にパース (境界チェック・stopSignal・hex検証付き)
static void scanStopPkt(const char *s, GodState *st) {
    if (!s || !st) return;

    const char *p   = s;
    const char *end = s + strlen(s); // 安全な終端

    if (*p == 'T') {
        p++;
        // "Txx" — stop reason を 2桁 hex としてパース
        if ((end - p) >= 2 &&
            isxdigit((unsigned char)p[0]) &&
            isxdigit((unsigned char)p[1])) {
            st->stopSignal = (uint8_t)((kHexTable[(uint8_t)p[0]] << 4) |
                                        kHexTable[(uint8_t)p[1]]);
            p += 2;
        } else {
            // 不正フォーマット: 読み飛ばし
            while (p < end && *p) p++;
        }
    }

    while (p < end && *p) {
        // "thread:XXXX;" の検出
        if ((end - p) >= 7 &&
            p[0] == 't' && p[1] == 'h' && p[2] == 'r' &&
            p[3] == 'e' && p[4] == 'a' && p[5] == 'd' && p[6] == ':') {
            p += 7;
            int i = 0;
            while (p < end && *p && *p != ';' && i < 63) {
                st->tid[i++] = *p++;
            }
            st->tid[i] = '\0';

        } else {
            // "rr...r:VV...V;" — レジスタ番号(1〜4桁hex) + ':' + 値(8 or 16文字)
            // レジスタ番号の末尾 ':' を動的に探す (最大4桁まで)
            const char *colon = NULL;
            for (int k = 1; k <= 4 && (p + k) < end; k++) {
                if (p[k] == ':') { colon = p + k; break; }
            }
            if (!colon) {
                // ':' が見つからない未知トークン → ';' まで読み飛ばし
                while (p < end && *p && *p != ';') p++;
                if (p < end && *p == ';') p++;
                continue;
            }

            // 値の長さを ';' または末尾で確定
            const char *valStart = colon + 1;
            const char *semi     = (const char *)memchr(valStart, ';',
                                                         (size_t)(end - valStart));
            const size_t valLen  = semi ? (size_t)(semi - valStart)
                                        : (size_t)(end  - valStart);

            // 値バッファが安全に読めることを確認してからデコード
            // さらに全文字が hex digit であることを検証 (不正パケット対策)
            if (valLen == 16) {
                BOOL allHex = YES;
                for (size_t hc = 0; hc < 16; hc++) {
                    if (!isxdigit((unsigned char)valStart[hc])) { allHex = NO; break; }
                }
                if (!allHex) {
                    p = semi ? semi : end;
                    while (p < end && *p && *p != ';') p++;
                    if (p < end && *p == ';') p++;
                    continue;
                }
                const uint64_t v = decodeLE64(valStart);
                // レジスタ番号を10進に変換して照合
                uint32_t regNum = 0;
                for (const char *q = p; q < colon; q++) {
                    regNum = (regNum << 4) | kHexTable[(uint8_t)*q];
                }
                switch (regNum) {
                    case  0: st->x0  = v; break; // x0
                    case  1: st->x1  = v; break; // x1
                    case 16: st->x16 = v; break; // x16 (ip0)
                    case 32: st->pc  = v; break; // pc
                    default: break;
                }
            } // if valLen == 16
            // valLen == 8 (32bit レジスタ) はここでは使用しないため無視

            // ';' の直前まで p を進める (共通の ';' スキップに委ねる)
            p = semi ? semi : end;
        }

        // 次の ';' まで進む
        while (p < end && *p && *p != ';') p++;
        if (p < end && *p == ';') p++;
    }
}

// ─────────────────────────────────────────────
// MARK: - GDB メモリ書き込みヘルパー
//   rx 権限付き領域へのチャンク書き込み
// ─────────────────────────────────────────────

static BOOL omegaWriteMemory(OmegaSession *s,
                              uint64_t addr,
                              uint32_t size,
                              char fillHi, char fillLo)
{
    uint32_t sent = 0;
    while (sent < size) {
        const uint32_t chunk = MIN(size - sent, kWriteChunkSize);

        // "M<addr>,<len>:<data...>"
        const int hdrLen = snprintf(s->pktBuf + 1,
                                    s->pktBufSize - 5,
                                    "M%llx,%x:", addr + sent, chunk);
        if (hdrLen <= 0 || (size_t)(hdrLen + chunk * 2) >= s->pktBufSize - 5) {
            NSLog(@"[Omega] writeMemory: buffer overflow guard triggered");
            return NO;
        }

        char *data = s->pktBuf + 1 + hdrLen;
        for (uint32_t j = 0; j < chunk; j++) {
            data[j * 2]     = fillHi;
            data[j * 2 + 1] = fillLo;
        }

        s->pktBuf[0] = '$';
        const size_t payloadLen = (size_t)(hdrLen + chunk * 2);
        const uint8_t sum = omega_neon_checksum((const uint8_t *)(s->pktBuf + 1), payloadLen);
        s->pktBuf[payloadLen + 1] = '#';
        s->pktBuf[payloadLen + 2] = vToH(sum >> 4);
        s->pktBuf[payloadLen + 3] = vToH(sum & 0xF);
        s->pktBuf[payloadLen + 4] = '\0';

        char *r = omegaExchange(s, s->pktBuf, payloadLen + 4);
        if (!r) {
            // NULL = 通信失敗。残りのチャンクを送っても無意味なので即終了
            NSLog(@"[Omega] writeMemory: exchange failed at offset %u", sent);
            return NO;
        }
        free(r);

        sent += chunk;
    }
    return YES;
}

// ─────────────────────────────────────────────
// MARK: - AppInfo
// ─────────────────────────────────────────────

@implementation AppInfo
@end

// ─────────────────────────────────────────────
// MARK: - AppManager
// ─────────────────────────────────────────────

@implementation AppManager {
    dispatch_semaphore_t _launchSemaphore; ///< 同時 JIT セッションを1つに制限
}

+ (instancetype)sharedManager {
    static AppManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[AppManager alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 同時起動を1セッションに制限 (HeartbeatManager・トンネルの競合防止)
        _launchSemaphore = dispatch_semaphore_create(1);
    }
    return self;
}

// ─────────────────────────────────────────────
// MARK: アプリ一覧取得
// ─────────────────────────────────────────────

- (void)fetchAppsWithProvider:(struct IdeviceProviderHandle *)provider
                   completion:(void (^)(NSArray<AppInfo *> *apps, NSString *error))completion
{
    if (!provider) {
        if (completion) completion(nil, @"Missing provider");
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        struct InstallationProxyClientHandle *instproxy = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(provider, &instproxy);
        if (err) {
            NSString *msg = [NSString stringWithUTF8String:err->message];
            idevice_error_free(err);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, msg); });
            return;
        }

        NSMutableArray<AppInfo *> *allApps = [NSMutableArray arrayWithCapacity:256];
        [self fetchAppsWithType:"User"   client:instproxy list:allApps];
        [self fetchAppsWithType:"System" client:instproxy list:allApps];
        installation_proxy_client_free(instproxy);

        if (completion) {
            NSArray<AppInfo *> *result = [allApps copy];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result, nil); });
        }
    });
}

- (void)fetchAppsWithType:(const char *)type
                   client:(struct InstallationProxyClientHandle *)client
                     list:(NSMutableArray<AppInfo *> *)list
{
    plist_t options = plist_new_dict();
    plist_dict_set_item(options, "ApplicationType", plist_new_string(type));

    plist_t *result_array = NULL;
    size_t   result_count = 0;
    struct IdeviceFfiError *err =
        installation_proxy_browse(client, options, &result_array, &result_count);
    plist_free(options);

    if (err) {
        NSLog(@"[Apps] Browse error for %s: %s", type, err->message);
        idevice_error_free(err);
        return;
    }

    if (!result_array) return;

    const BOOL isSystem = (strcmp(type, "System") == 0);

    for (size_t i = 0; i < result_count; i++) {
        plist_t item = result_array[i];
        if (!item) continue;

        AppInfo *info = [AppInfo new];
        info.isSystem = isSystem;

        // BundleIdentifier
        plist_t bidNode = plist_dict_get_item(item, "CFBundleIdentifier");
        if (bidNode) {
            char *val = NULL;
            plist_get_string_val(bidNode, &val);
            if (val) {
                info.bundleId = [NSString stringWithUTF8String:val];
                plist_mem_free(val);
            }
        }
        if (!info.bundleId) continue; // BundleId 必須

        // Display Name
        plist_t nameNode = plist_dict_get_item(item, "CFBundleDisplayName");
        if (!nameNode) nameNode = plist_dict_get_item(item, "CFBundleName");
        if (nameNode) {
            char *val = NULL;
            plist_get_string_val(nameNode, &val);
            if (val) {
                info.name = [NSString stringWithUTF8String:val];
                plist_mem_free(val);
            }
        }
        if (!info.name) info.name = info.bundleId;

        [list addObject:info];
    }

    idevice_plist_array_free(result_array, result_count);
}

// ─────────────────────────────────────────────
// MARK: アプリ起動 + JIT 有効化
// ─────────────────────────────────────────────

- (void)launchApp:(NSString *)bundleId
          jitMode:(JitMode)jitMode
         provider:(struct IdeviceProviderHandle *)provider
       completion:(void (^)(BOOL success, NSString *message))completion
{
    if (!bundleId.length || !provider) {
        if (completion) completion(NO, @"Invalid arguments");
        return;
    }

    NSString *bid = [bundleId copy];

    // safeCompletion は必ず1回のみ呼ばれる (atomic フラグで二重呼び出し防止)
    __block atomic_flag completionFired = ATOMIC_FLAG_INIT;
    dispatch_semaphore_t launchSem = _launchSemaphore; // ivar をローカルでキャプチャ

    void (^safeCompletion)(BOOL, NSString *) = ^(BOOL success, NSString *msg) {
        if (atomic_flag_test_and_set(&completionFired)) return; // 2回目以降は無視
        [[HeartbeatManager sharedManager] resumeHeartbeat];
        dispatch_semaphore_signal(launchSem); // セッション終了を通知
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success, msg); });
        }
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        // 前のセッションが終わるまで待機 (タイムアウト 30 秒)
        if (dispatch_semaphore_wait(launchSem,
                dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) != 0) {
            NSLog(@"[Launch] Timed out waiting for previous session.");
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Previous JIT session timed out");
            });
            return;
        }
        [[HeartbeatManager sharedManager] pauseHeartbeat];

        // ── Lockdownd ウォームアップ ──────────────────────────
        {
            struct LockdowndClientHandle *warmup = NULL;
            struct IdeviceFfiError *we = lockdownd_connect(provider, &warmup);
            if (!we) {
                plist_t udid = NULL;
                lockdownd_get_value(warmup, "UniqueDeviceID", NULL, &udid);
                if (udid) plist_free(udid);
                lockdownd_client_free(warmup);
            } else {
                NSLog(@"[Launch] Warmup warning: %s", we->message);
                idevice_error_free(we);
            }
        }
        // 短いウォームアップ後の待機 (スレッド内なので dispatch_after 不可)
        [NSThread sleepForTimeInterval:0.2];

        // ── CoreDevice Proxy 接続 (指数バックオフリトライ) ────
        struct CoreDeviceProxyHandle *proxy = NULL;
        {
            struct IdeviceFfiError *err      = NULL;
            NSTimeInterval          delay    = kRetryInitDelay;

            for (int i = 0; i < kMaxRetries; i++) {
                if (i > 0) {
                    // 前回のエラーをここで解放 (Use-After-Free 防止)
                    NSLog(@"[Launch] Tunnel attempt %d failed: %s. Retry in %.1fs…",
                          i, err->message, delay);
                    idevice_error_free(err);
                    err = NULL;
                    [NSThread sleepForTimeInterval:delay];
                    delay *= kRetryBackoff;
                }
                err = core_device_proxy_connect(provider, &proxy);
                if (!err) break;
            }

            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Tunnel Error: %s", err->message];
                idevice_error_free(err);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── RSD ポート取得 ────────────────────────────────────
        uint16_t rsdPort = 0;
        {
            struct IdeviceFfiError *err = core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"RSD Error: %s", err->message];
                idevice_error_free(err);
                core_device_proxy_free(proxy);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── TCP アダプター ────────────────────────────────────
        struct AdapterHandle *adapter = NULL;
        {
            struct IdeviceFfiError *err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
            core_device_proxy_free(proxy); // 所有権を adapter に移譲後は解放
            proxy = NULL;
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Adapter Error: %s", err->message];
                idevice_error_free(err);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── RSD ストリーム ────────────────────────────────────
        struct ReadWriteOpaque *rsdStream = NULL;
        {
            struct IdeviceFfiError *err = adapter_connect(adapter, rsdPort, &rsdStream);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Stream Error: %s", err->message];
                idevice_error_free(err);
                adapter_free(adapter);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── RSD ハンドシェイク ────────────────────────────────
        struct RsdHandshakeHandle *handshake = NULL;
        {
            struct IdeviceFfiError *err = rsd_handshake_new(rsdStream, &handshake);
            rsdStream = NULL; // 所有権移譲
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Handshake Error: %s", err->message];
                idevice_error_free(err);
                adapter_free(adapter);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── RemoteServer ──────────────────────────────────────
        struct RemoteServerHandle *remoteServer = NULL;
        {
            struct IdeviceFfiError *err =
                remote_server_connect_rsd(adapter, handshake, &remoteServer);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"RemoteServer Error: %s", err->message];
                idevice_error_free(err);
                rsd_handshake_free(handshake);
                adapter_free(adapter);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── ProcessControl ────────────────────────────────────
        struct ProcessControlHandle *procControl = NULL;
        {
            struct IdeviceFfiError *err = process_control_new(remoteServer, &procControl);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"ProcessControl Error: %s", err->message];
                idevice_error_free(err);
                remote_server_free(remoteServer);
                rsd_handshake_free(handshake);
                adapter_free(adapter);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── アプリ起動 ────────────────────────────────────────
        uint64_t pid = 0;
        {
            const char **env  = NULL;
            NSUInteger envCnt = 0;

            if (jitMode != JitModeNone) {
                envCnt = 1;
                env    = (const char **)malloc(2 * sizeof(char *));
                env[0] = strdup("DEBUG_AUTOMATION_SCRIPTS=1");
                env[1] = NULL;
            }

            struct IdeviceFfiError *err =
                process_control_launch_app(procControl,
                                           [bid UTF8String],
                                           env, (uint32_t)envCnt,
                                           NULL, 0,
                                           NO, YES,
                                           &pid);

            if (env) {
                for (NSUInteger i = 0; i < envCnt; i++) free((void *)env[i]);
                free(env);
            }

            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Launch Error: %s", err->message];
                idevice_error_free(err);
                process_control_free(procControl);
                remote_server_free(remoteServer);
                rsd_handshake_free(handshake);
                adapter_free(adapter);
                safeCompletion(NO, msg);
                return;
            }
        }

        // ── JIT 有効化 ────────────────────────────────────────
        if (jitMode != JitModeNone && pid > 0) {
            process_control_disable_memory_limit(procControl, pid);

            // ProcessControl は JIT セッション前に解放して良い
            process_control_free(procControl);
            remote_server_free(remoteServer);
            procControl  = NULL;
            remoteServer = NULL;

            if (jitMode == JitModeJS) {
                [self activateUniversalJitSyncForPid:pid
                                            adapter:adapter
                                          handshake:handshake];
                // adapter/handshake は activateXxx 内で解放済み
            } else if (jitMode == JitModeNative) {
                [self activateGodlyNativeJitSyncForPid:pid
                                              adapter:adapter
                                            handshake:handshake];
                // adapter/handshake は activateXxx 内で解放済み
            } else {
                // 未知の jitMode: ハンドルをここで解放しないとリーク
                NSLog(@"[Launch] Unknown jitMode %d — freeing handles.", (int)jitMode);
                rsd_handshake_free(handshake);
                adapter_free(adapter);
            }

            NSString *modeStr = (jitMode == JitModeJS) ? @"JS" : @"God-Speed";
            safeCompletion(YES, [NSString stringWithFormat:
                @"Launched with JIT (%@, PID: %llu).", modeStr, pid]);
        } else {
            process_control_free(procControl);
            remote_server_free(remoteServer);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            safeCompletion(YES, [NSString stringWithFormat:
                @"Launched successfully (PID: %llu).", pid]);
        }
    });
}

// ─────────────────────────────────────────────
// MARK: Native JIT (Omega-God GDB エンジン)
// ─────────────────────────────────────────────

- (void)activateGodlyNativeJitSyncForPid:(uint64_t)pid
                                  adapter:(struct AdapterHandle *)adapter
                                handshake:(struct RsdHandshakeHandle *)handshake
{
    NSLog(@"[Omega-God] Starting Synchronized Session (PID: %llu)…", pid);

    struct DebugProxyHandle *proxy = NULL;
    if (debug_proxy_connect_rsd(adapter, handshake, &proxy)) {
        NSLog(@"[Omega-God] debug_proxy_connect_rsd failed.");
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return;
    }

    OmegaSession s = {
        .proxy      = proxy,
        .pktBufSize = kPktBufSize,
        .noAck      = NO
    };
    s.pktBuf = (char *)malloc(kPktBufSize);
    if (!s.pktBuf) {
        NSLog(@"[Omega-God] malloc failed.");
        debug_proxy_free(proxy);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return;
    }

    // vAttach
    {
        char *r = omegaSend(&s, "vAttach;%llx", pid);
        if (r) free(r);
    }

    // No-Ack モード交渉
    {
        char *r = omegaSend(&s, "QStartNoAckMode");
        if (r) {
            s.noAck = (strcmp(r, "OK") == 0);
            free(r);
        }
    }

    // JSContext — ログ用途のみ
    JSContext *jsCtx = [[JSContext alloc] init];
    jsCtx[@"log"] = ^(NSString *m) { NSLog(@"[Omega Script] %@", m); };

    // スレッドローカルキャッシュを取得し、セッション開始時にクリア
    // (スレッド再利用時に前セッションの古いエントリが残るのを防ぐ)
    GCacheStore *gcStore = gcache_get();
    if (!gcStore) {
        NSLog(@"[Omega-God] gcache alloc failed — aborting.");
        free(s.pktBuf);
        debug_proxy_free(proxy);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return;
    }
    memset(gcStore->cache, 0, sizeof(gcStore->cache));
    gcStore->ptr = 0;

    BOOL detached = NO;

    while (!detached) {
        // vCont;c — プロセス継続
        char *resp = omegaSend(&s, "vCont;c");
        if (!resp) {
            NSLog(@"[Omega-God] Connection lost.");
            break;
        }

        GodState st = {0};
        scanStopPkt(resp, &st);

        if (!st.tid[0] || st.pc == 0) {
            free(resp);
            continue;
        }

        // ── 命令キャッシュ検索 ──────────────────────────────
        // ※ instr==0 も有効な命令値のため、ヒット判定は専用フラグで行う
        uint32_t instr    = 0;
        BOOL     cacheHit = NO;
        for (int i = 0; i < kTlCacheSize; i++) {
            if (gcStore->cache[i].valid && gcStore->cache[i].pc == st.pc) {
                instr    = gcStore->cache[i].instr;
                cacheHit = YES;
                break;
            }
        }

        if (!cacheHit) {
            char *ir = omegaSend(&s, "m%llx,4", st.pc);
            if (ir) {
                if (strlen(ir) >= 8) {
                    instr    = decodeLE32(ir);
                    cacheHit = YES;
                    const int slot = gcStore->ptr & kTlCacheMask;
                    gcStore->cache[slot].valid = NO;   // 書き込み中は一旦無効化 (SMC安全)
                    gcStore->cache[slot].pc    = st.pc;
                    gcStore->cache[slot].instr = instr;
                    gcStore->cache[slot].valid = YES;  // 全フィールド確定後に有効化
                    gcStore->ptr++;
                }
                free(ir);
            }
        }

        if (!cacheHit) { free(resp); continue; }

        // ── ARM64 BRK 判定 ──────────────────────────────────
        // BRK 命令は SIGTRAP (0x05) で停止する。それ以外の stop reason では
        // BRK 由来ではないのでシグナル転送のみ行う (誤検知防止)
        const BOOL isSigTrap = (st.stopSignal == 0x05);

        if (isSigTrap && (instr & kArm64BrkMask) == kArm64BrkPattern) {
            const uint32_t imm = (instr >> 5) & 0xFFFF;

            // PC を BRK の次の命令へ進める
            {
                const uint64_t npc = st.pc + 4;
                char nle[17]; writeLE64Hex(nle, npc);
                char *pr = omegaSend(&s, "P20=%s;thread:%s", nle, st.tid);
                if (pr) free(pr);
            }

            if (imm == kBrkImmOmegaCtrl) {
                if (st.x16 == kOmegaCmdDetach) {
                    // x16 == 0: 正常終了シグナル
                    detached = YES;

                } else if (st.x16 == kOmegaCmdPrepare) {
                    // x16 == 1: JIT ページ準備
                    uint64_t addr = st.x0;

                    if (!addr) {
                        // アドレス未確定 → _M コマンドで新規確保
                        char *xr = omegaSend(&s, "_M%llx,rx", st.x1);
                        if (xr) {
                            addr = strtoull(xr, NULL, 16);
                            free(xr);
                        }
                    }

                    if (addr) {
                        omegaWriteMemory(&s, addr, (uint32_t)st.x1, kFillHi, kFillLo);

                        // x0 に確保アドレスをセット
                        char ale[17]; writeLE64Hex(ale, addr);
                        char *xr = omegaSend(&s, "P00=%s;thread:%s", ale, st.tid);
                        if (xr) free(xr);
                    }
                }

            } else if (imm == kBrkImmJsEval) {
                // x0: スクリプトアドレス, x1: スクリプト長
                char *mr = omegaSend(&s, "m%llx,%llx", st.x0, st.x1);
                if (mr) {
                    @autoreleasepool {
                        const size_t sl = strlen(mr) / 2;
                        char *sc = (char *)malloc(sl + 1);
                        if (sc) {
                            for (size_t k = 0; k < sl; k++) {
                                sc[k] = (char)hexPairToByte(mr[k * 2], mr[k * 2 + 1]);
                            }
                            sc[sl] = '\0';
                            jsCtx[@"x0"] = @(st.x0);
                            jsCtx[@"x1"] = @(st.x1);
                            jsCtx[@"pc"] = @(st.pc);
                            [jsCtx evaluateScript:@(sc)];
                            free(sc);
                        }
                    }
                    free(mr);
                }
            }

        } else if ((resp[0] == 'W' || resp[0] == 'X')) {
            // W = プロセス正常終了 / X = シグナルで強制終了
            // どちらもプロセスは既に死んでいるのでデタッチして終了
            NSLog(@"[Omega-God] Process exited (%c). Stopping session.", resp[0]);
            detached = YES;

        } else if (!isSigTrap &&
                   resp[0] == 'T' &&
                   isxdigit((unsigned char)resp[1]) &&
                   isxdigit((unsigned char)resp[2]) &&
                   st.tid[0]) {
            // SIGTRAP 以外のシグナル: そのままプロセスへ転送
            char *vr = omegaSend(&s, "vCont;S%c%c:%s", resp[1], resp[2], st.tid);
            if (vr) free(vr);
        }

        free(resp);
    }

    // ── 安全デタッチシーケンス ──────────────────────────────
    {
        char *r = omegaSend(&s, "vCont;c"); if (r) free(r);
        r = omegaSend(&s, "D");             if (r) free(r);
    }

    free(s.pktBuf);
    debug_proxy_free(proxy);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    NSLog(@"[Omega-God] Engine shut down cleanly.");
}

// ─────────────────────────────────────────────
// MARK: Universal JS JIT
// ─────────────────────────────────────────────

- (void)activateUniversalJitSyncForPid:(uint64_t)pid
                                adapter:(struct AdapterHandle *)adapter
                              handshake:(struct RsdHandshakeHandle *)handshake
{
    struct DebugProxyHandle *proxy = NULL;
    if (debug_proxy_connect_rsd(adapter, handshake, &proxy)) {
        NSLog(@"[JIT-JS] debug_proxy_connect_rsd failed.");
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return;
    }

    // ── vAttach: JS スクリプト実行前にプロセスへアタッチ ───────
    // これを省くと send_command が未アタッチのプロキシに送信し、
    // 全コマンドが即 nil を返してスクリプトが即終了する。
    // ※ NoAck 交渉は行わない: send_command (debug_proxy_send_command) は
    //   高レベル API なので Ack モードを独自に処理する。生パケット側で
    //   NoAck を有効にすると send_command の応答読み取りが壊れる。
    {
        char *pktBuf = (char *)malloc(kPktBufSize);
        if (pktBuf) {
            OmegaSession setupSession = {
                .proxy      = proxy,
                .pktBufSize = kPktBufSize,
                .pktBuf     = pktBuf,
                .noAck      = NO
            };
            char *r = omegaSend(&setupSession, "vAttach;%llx", pid);
            if (r) {
                NSLog(@"[JIT-JS] vAttach response: %s", r);
                free(r);
            } else {
                NSLog(@"[JIT-JS] vAttach got no response — continuing anyway.");
            }
            free(pktBuf);
        }
    }

    // ── JSContext セットアップ ───────────────────────────────
    // proxy を __block でキャプチャし、JSContext 寿命中は解放しない
    __block struct DebugProxyHandle *capturedProxy = proxy;

    JSContext *context = [[JSContext alloc] init];

    context[@"get_pid"] = ^uint64_t {
        return pid;
    };

    context[@"send_command"] = ^NSString *(NSString *cmdStr) {
        if (!cmdStr.length) return nil;
        struct DebugserverCommandHandle *cmd =
            debugserver_command_new([cmdStr UTF8String], NULL, 0);
        char *respRaw = NULL;
        struct IdeviceFfiError *e =
            debug_proxy_send_command(capturedProxy, cmd, &respRaw);
        debugserver_command_free(cmd);
        if (e) { idevice_error_free(e); return nil; }
        if (!respRaw) return nil;
        NSString *result = [NSString stringWithUTF8String:respRaw];
        free(respRaw);
        return result;
    };

    context[@"import_script"] = ^NSString *(NSString *filename) {
        if (!filename.length) return @"ERROR: empty filename";

        // Documents ディレクトリ優先
        NSString *docsDir =
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                 NSUserDomainMask, YES) firstObject];
        NSString *path = [docsDir stringByAppendingPathComponent:filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            path = [[NSBundle mainBundle]
                    pathForResource:[filename stringByDeletingPathExtension]
                             ofType:[filename pathExtension]];
        }
        if (!path) return [NSString stringWithFormat:@"ERROR: not found: %@", filename];

        NSError *e = nil;
        NSString *content =
            [NSString stringWithContentsOfFile:path
                                      encoding:NSUTF8StringEncoding
                                         error:&e];
        if (!content) {
            return [NSString stringWithFormat:@"ERROR: %@", e.localizedDescription];
        }
        [[JSContext currentContext] evaluateScript:content];
        return @"OK";
    };

    // prepare_memory_region — NoAck は使用しない (接続モードに合わせる)
    context[@"prepare_memory_region"] = ^NSString *(uint64_t startAddr, uint64_t jitPagesSize) {
        char *buf = (char *)malloc(kPktBufSize);
        if (!buf) return @"ERROR_ALLOC";

        OmegaSession os = {
            .proxy      = capturedProxy,
            .pktBufSize = kPktBufSize,
            .pktBuf     = buf,
            .noAck      = NO  // サーバー側のモードに合わせる (交渉済みでなければ NO)
        };

        BOOL ok = omegaWriteMemory(&os, startAddr, (uint32_t)jitPagesSize,
                                   kFillHi, kFillLo);
        free(buf);
        return ok ? @"OK" : @"ERROR_SEND";
    };

    context[@"log"] = ^(NSString *msg) {
        NSLog(@"[JIT Script] %@", msg);
    };

    // ── スクリプト読み込み (Documents → Bundle → 組み込み) ──
    NSString *script = nil;
    {
        NSString *docsDir =
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                 NSUserDomainMask, YES) firstObject];
        NSString *path = [docsDir stringByAppendingPathComponent:@"universal.js"];

        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            script = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
        }
        if (!script) {
            NSString *bundlePath =
                [[NSBundle mainBundle] pathForResource:@"universal" ofType:@"js"];
            if (bundlePath) {
                script = [NSString stringWithContentsOfFile:bundlePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
            }
        }
        if (!script) script = kUniversalJitScript;
    }

    [context evaluateScript:script];

    // ── JSContext の解放後に proxy を解放 ───────────────────
    // context がスコープを抜けてから解放することで Use-After-Free を防止
    context = nil;
    capturedProxy = NULL;

    debug_proxy_free(proxy);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    NSLog(@"[JIT-JS] Session complete.");
}

@end
