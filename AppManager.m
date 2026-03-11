// AppManager.m
// Omega JIT Engine — 超安定・超安全・超神速版 Rev.3
//
// ═══════════════════════════════════════════════════════════
//  Rev.3 修正内容 (本バージョン)
// ═══════════════════════════════════════════════════════════
//
//  [CRASH-1] ★最重大★ JIT有効・無効どちらでもアプリが起動しないクラッシュ
//    根本原因: debug_proxy_read_response が生の GDB RSP パケット
//              "$payload#cs" を返すのに、エンベロープ($と#cs)を
//              剥がしていなかった。結果として scanStopPkt に
//              "$T05...#xx" が渡り、先頭の '$' で 'T' を見つけられず
//              st.tid / st.pc が 0 のまま → vCont;c 無限ループ →
//              ターゲットアプリが制御を取り戻せず「起動しない」。
//    修正: gdb_strip_envelope() を omegaReadResponse 内で必ず適用。
//
//  [CACHE-1] ★重大★ GCache direct-mapped index の致命的バグ
//    根本原因: ARM64 命令は 4 バイトアライン (下位 2 ビット常に 0)。
//              pc & 0x0F では 0/4/8/12 の 4 値しか取れず、
//              16 スロット中 4 スロットしか使われない。
//              さらに 4 命令ごとにキャッシュが衝突し事実上無効。
//    修正: (pc >> 2) & kTlCacheMask で全 16 スロットを均等利用。
//
//  [STRLEN] strlen の多用を排除
//    - debug_proxy_read_response の返す長さが使えない場合は
//      strnlen(r, kPktBufSize) を使用 (バッファオーバーリード防止)。
//    - 既知長 (vsnprintf 戻り値等) を再利用し strlen 呼び出しゼロ。
//
//  [RSP] scanStopPkt の GDB RSP 仕様準拠強化
//    - gdb_strip_envelope 後のペイロードに '#' が残る場合を二重安全で処理。
//    - end ポインタを '#' 手前に設定し OOB を完全排除。
//
//  [FAST] omegaSend small packet スタックバッファ最適化
//    - 512 バイト以下のパケット (vCont;c, m, P, D 等ほぼ全て) は
//      スタックバッファを使用し heap アクセスをゼロに。
//    - va_copy で vsnprintf 二重呼び出しを回避。
//
// ═══════════════════════════════════════════════════════════
//  Rev.2 修正内容 (維持)
// ═══════════════════════════════════════════════════════════
//  A. JIT起動クラッシュ → debug_proxy_connect_rsd エラーを正しく捕捉・解放
//  B. omegaExchange ACK 処理完全実装
//     (ACK 受信後はデータ読み取りリトライのみ、再送禁止)
//  C. GCache → direct-mapped (本Rev でインデックスバグも修正)
//  D. JS prepare_memory_region の malloc → thread-local バッファ
//  E. scanStopPkt の ; delimiter を memchr ベースに統一
//  F. strlen → vsnprintf 戻り値の再利用
//
// ═══════════════════════════════════════════════════════════
//  Rev.1 修正内容 (維持)
// ═══════════════════════════════════════════════════════════
//  1-12. (省略: Rev.2 コメント参照)

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

static const uint32_t kArm64BrkMask    = 0xFFE0001F;
static const uint32_t kArm64BrkPattern = 0xD4200000;

static const uint32_t kBrkImmOmegaCtrl = 0xF00D;
static const uint32_t kBrkImmJsEval    = 0x0068;

static const uint64_t kOmegaCmdDetach  = 0;
static const uint64_t kOmegaCmdPrepare = 1;

static const size_t   kPktBufSize      = 65536;
static const uint32_t kWriteChunkSize  = 16384;
static const char     kFillHi          = '6';
static const char     kFillLo          = '9';

static const int      kMaxRetries      = 8;
static const NSTimeInterval kRetryInitDelay = 1.0;
static const double   kRetryBackoff    = 1.5;

/// キャッシュサイズは必ず 2 の累乗 (direct-mapped index で使用)
static const size_t kTlCacheSize = 16;
static const size_t kTlCacheMask = 15; // kTlCacheSize - 1

/// omegaSend スタックバッファしきい値
/// これ以下のペイロードはスタックで完結 (heap アクセスゼロ)
#define OMEGA_STACK_BUF_SIZE  512u

// ─────────────────────────────────────────────
// MARK: - Omega JIT セッション型
// ─────────────────────────────────────────────

typedef struct {
    struct DebugProxyHandle *proxy;
    char   *pktBuf;     ///< large packet 用ヒープバッファ
    size_t  pktBufSize;
    BOOL    noAck;
} OmegaSession;

// ─────────────────────────────────────────────
// MARK: - スレッドローカル GCache (pthread_key_t)
// ─────────────────────────────────────────────

typedef struct {
    uint64_t pc;
    uint32_t instr;
    BOOL     valid;
} GCache;

typedef struct {
    GCache cache[kTlCacheSize]; ///< direct-mapped: index = (pc>>2) & kTlCacheMask
} GCacheStore;

static pthread_key_t  s_gcache_key;
static pthread_once_t s_gcache_once = PTHREAD_ONCE_INIT;
static void gcache_destructor(void *p) { free(p); }
static void gcache_key_init(void)      { pthread_key_create(&s_gcache_key, gcache_destructor); }

static GCacheStore *gcache_get(void) {
    pthread_once(&s_gcache_once, gcache_key_init);
    GCacheStore *st = (GCacheStore *)pthread_getspecific(s_gcache_key);
    if (__builtin_expect(!st, 0)) {
        st = (GCacheStore *)calloc(1, sizeof(GCacheStore));
        pthread_setspecific(s_gcache_key, st);
    }
    return st;
}

/// [CACHE-1] O(1) lookup: ARM64 は 4 バイトアライン → >> 2 で全スロット活用
NS_INLINE GCache *gcache_lookup(GCacheStore *st, uint64_t pc) {
    GCache *slot = &st->cache[(size_t)(pc >> 2) & kTlCacheMask];
    return (__builtin_expect(slot->valid && slot->pc == pc, 0)) ? slot : NULL;
}

/// [CACHE-1] O(1) insert: SMC 安全 (valid=NO→書き込み→valid=YES)
NS_INLINE void gcache_insert(GCacheStore *st, uint64_t pc, uint32_t instr) {
    GCache *slot = &st->cache[(size_t)(pc >> 2) & kTlCacheMask];
    slot->valid = NO;
    slot->pc    = pc;
    slot->instr = instr;
    slot->valid = YES;
}

// ─────────────────────────────────────────────
// MARK: - スレッドローカル prepare バッファ (pthread_key_t)
// ─────────────────────────────────────────────

static pthread_key_t  s_prepbuf_key;
static pthread_once_t s_prepbuf_once = PTHREAD_ONCE_INIT;
static void prepbuf_destructor(void *p) { free(p); }
static void prepbuf_key_init(void)      { pthread_key_create(&s_prepbuf_key, prepbuf_destructor); }

static char *prepbuf_get(void) {
    pthread_once(&s_prepbuf_once, prepbuf_key_init);
    char *buf = (char *)pthread_getspecific(s_prepbuf_key);
    if (__builtin_expect(!buf, 0)) {
        buf = (char *)malloc(kPktBufSize);
        if (buf) pthread_setspecific(s_prepbuf_key, buf);
    }
    return buf;
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

NS_INLINE char    vToH(uint8_t v)                { return "0123456789abcdef"[v & 0xF]; }
NS_INLINE uint8_t hexPairToByte(char hi, char lo) {
    return (uint8_t)((kHexTable[(uint8_t)hi] << 4) | kHexTable[(uint8_t)lo]);
}

static void writeLE64Hex(char *out, uint64_t v) {
    for (int i = 0; i < 8; i++) {
        uint8_t b = (uint8_t)((v >> (i * 8)) & 0xFF);
        out[i*2]   = vToH(b >> 4);
        out[i*2+1] = vToH(b & 0xF);
    }
    out[16] = '\0';
}

static uint64_t decodeLE64(const char *p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++)
        v |= (uint64_t)hexPairToByte(p[i*2], p[i*2+1]) << (i*8);
    return v;
}

static uint32_t decodeLE32(const char *p) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++)
        v |= (uint32_t)hexPairToByte(p[i*2], p[i*2+1]) << (i*8);
    return v;
}

// ─────────────────────────────────────────────
// MARK: - NEON チェックサム
// ─────────────────────────────────────────────

static uint8_t omega_neon_checksum(const uint8_t *p, size_t l) {
    if (__builtin_expect(l == 0, 0)) return 0;
    uint64x2_t vsum = vdupq_n_u64(0);
    size_t i = 0;
    for (; i + 16 <= l; i += 16) {
        vsum = vpadalq_u32(vsum, vpaddlq_u16(vpaddlq_u8(vld1q_u8(p + i))));
    }
    uint64_t s = vgetq_lane_u64(vsum, 0) + vgetq_lane_u64(vsum, 1);
    for (; i < l; i++) s += p[i];
    return (uint8_t)(s & 0xFF);
}

// ─────────────────────────────────────────────
// MARK: - GDB RSP エンベロープ剥がし [CRASH-1 修正の核心]
// ─────────────────────────────────────────────
//
// debug_proxy_read_response が返す生パケット形式:
//   "+$T05thread:p1.1;...#ab"  ← ACK + エンベロープ付きパケット
//   "$T05thread:p1.1;...#ab"   ← エンベロープ付きパケット (ACKなし)
//   "W00"                       ← エンベロープなしパケット (終了通知等)
//
// ACK 除去後に '$' で始まる場合、本関数でペイロードのみを抽出する。
// 変換例: "$T05...#ab" → "T05..."
//
// 注意: GDB RSP 仕様では '#' はペイロード中にはエスケープして出現しないため
//       右端の '#' がチェックサム区切りと確定できる。
//
// rlen: strnlen(r, kPktBufSize) の値 (NUL 終端を含まない)
// 戻り値: r (in-place 編集済み)
// ─────────────────────────────────────────────

static char *gdb_strip_envelope(char *r, size_t rlen) {
    // '$' で始まらない場合はエンベロープなし (W/X/O/etc.) → そのまま返す
    if (!r || rlen < 1 || r[0] != '$') return r;

    // '#' を右端から O(n) で検索 (最後の '#' = チェックサム区切り)
    ssize_t hashPos = -1;
    for (ssize_t i = (ssize_t)rlen - 1; i >= 0; i--) {
        if (r[i] == '#') { hashPos = i; break; }
    }

    if (hashPos > 0) {
        // "$payload#cs" → payload = r[1..hashPos-1]
        const size_t payloadLen = (size_t)hashPos - 1;
        memmove(r, r + 1, payloadLen);
        r[payloadLen] = '\0';
    } else if (hashPos == 0) {
        // "$#cs" → 空ペイロード (OK パケット等)
        r[0] = '\0';
    } else {
        // '#' なし: '$' だけ除去 ("$OK" → "OK" など)
        // rlen バイト + NUL を移動
        memmove(r, r + 1, rlen); // r[rlen] は既に '\0' または strnlen の終端
    }
    return r;
}

// ─────────────────────────────────────────────
// MARK: - GDB 受信 (ACK 処理完全版 + エンベロープ剥がし)
// ─────────────────────────────────────────────
//
// GDB RSP 受信ステートマシン:
//
//  送信後に到着するパターン:
//  (a) "+$payload#cs"  ← ACK + データ同一バッファ (最頻出)
//  (b) "+"             ← ACK のみ (分割到着) → 続けてデータを読む
//  (c) "-"             ← NAK → 呼び出し側が再送する
//  (d) "%Stop:..."     ← 非同期通知 → 透過してスキップ
//  (e) "$payload#cs"   ← ACK なしで直接データ (一部スタブ)
//  (f) "W00" など      ← エンベロープなし停止パケット
//
// 重要: ACK 受信後にデータ読み取りが失敗しても再送しない。
//       サーバー側はコマンドを処理済みなので再送は重複実行を招く。
//
// 戻り値: heap 確保済みペイロード文字列 (呼び出し側 free 必須) / NULL
//   out_nak: YES なら NAK 受信 → 呼び出し側は再送してよい
// ─────────────────────────────────────────────

static char *omegaReadResponse(OmegaSession *s, BOOL *out_nak) {
    if (out_nak) *out_nak = NO;

    BOOL ackReceived  = NO;
    const int kMaxRd  = 6;

    for (int rd = 0; rd < kMaxRd; rd++) {
        char *r = NULL;
        struct IdeviceFfiError *err = debug_proxy_read_response(s->proxy, &r);
        if (err) {
            idevice_error_free(err);
            if (ackReceived) continue; // ACK 済みなら読み取りを続ける
            return NULL;
        }
        if (!r) {
            if (ackReceived) continue;
            return NULL;
        }

        // [STRLEN] strnlen で安全に長さを取得 (strlen のバッファオーバーリード防止)
        const size_t rlen = strnlen(r, kPktBufSize);

        // ── NoAck モード: エンベロープだけ剥がして返す ──────
        if (s->noAck) return gdb_strip_envelope(r, rlen);

        // ── 非同期通知 '%': スキップ ─────────────────────────
        if (r[0] == '%') { free(r); continue; }

        // ── NAK '-': ACK 受信前のみ再送を許可 ──────────────
        if (r[0] == '-') {
            free(r);
            if (ackReceived) {
                // ACK 後の NAK は異常 (プロトコル違反) → 読み続ける
                NSLog(@"[Omega] Unexpected NAK after ACK — ignoring.");
                continue;
            }
            if (out_nak) *out_nak = YES;
            return NULL; // 呼び出し側が再送する
        }

        // ── ACK '+': データが同一バッファに続く可能性 ────────
        if (r[0] == '+') {
            ackReceived = YES;

            if (r[1] != '\0') {
                // パターン (a): "+$payload#cs" — in-place で '+' を除去後エンベロープを剥がす
                const size_t dataLen = rlen - 1; // '+' 以降の長さ (NUL 含まず)
                memmove(r, r + 1, dataLen + 1);  // NUL ごと移動
                return gdb_strip_envelope(r, dataLen);
            }

            // パターン (b): '+' のみ → データを続けて読む
            free(r); r = NULL;
            continue;
        }

        // ── パターン (e)(f): ACK なしで直接データ ────────────
        return gdb_strip_envelope(r, rlen);
    }

    if (ackReceived) NSLog(@"[Omega] Read timeout after ACK.");
    return NULL;
}

// ─────────────────────────────────────────────
// MARK: - GDB 送受信 (NAK 時のみ再送)
// ─────────────────────────────────────────────

static char *omegaExchange(OmegaSession *s, const char *pkt, size_t pktLen) {
    if (__builtin_expect(!pkt || pktLen == 0, 0)) return NULL;

    for (int attempt = 0; attempt < 3; attempt++) {
        struct IdeviceFfiError *sendErr =
            debug_proxy_send_raw(s->proxy, (const uint8_t *)pkt, pktLen);
        if (sendErr) { idevice_error_free(sendErr); continue; }

        BOOL gotNak = NO;
        char *r = omegaReadResponse(s, &gotNak);

        if (r)       return r;      // 成功
        if (gotNak)  continue;      // NAK → 再送してよい
        break;                      // IO エラー → 諦める
    }
    return NULL;
}

// ─────────────────────────────────────────────
// MARK: - omegaSend [FAST: small packet スタックバッファ]
// ─────────────────────────────────────────────
//
// OMEGA_STACK_BUF_SIZE (512) バイト以下のペイロードはスタックバッファを使用。
// vCont;c, m, P, D 等ほぼ全コマンドがこの条件を満たし heap アクセスゼロ。
// va_copy で vsnprintf 二重呼び出しを回避。
//
// 戻り値: heap 確保済み文字列 (呼び出し側 free 必須) / NULL = 失敗
// ─────────────────────────────────────────────

static char *omegaSend(OmegaSession *s, const char *fmt, ...) {
    char stackBuf[OMEGA_STACK_BUF_SIZE];

    va_list a, acopy;
    va_start(a, fmt);
    va_copy(acopy, a);

    // スタックバッファで試みる
    stackBuf[0] = '$';
    int l = vsnprintf(stackBuf + 1, OMEGA_STACK_BUF_SIZE - 5, fmt, a);
    va_end(a);

    char  *buf;
    if (__builtin_expect(l > 0 && (size_t)l < OMEGA_STACK_BUF_SIZE - 5, 1)) {
        // ── スタックバッファに収まった (最頻出パス) ──────────
        va_end(acopy);
        buf = stackBuf;
    } else {
        // ── ヒープバッファにフォールバック ───────────────────
        s->pktBuf[0] = '$';
        l = vsnprintf(s->pktBuf + 1, s->pktBufSize - 5, fmt, acopy);
        va_end(acopy);
        if (l <= 0 || (size_t)l >= s->pktBufSize - 5) {
            NSLog(@"[Omega] omegaSend: packet too large (l=%d)", l);
            return NULL;
        }
        buf = s->pktBuf;
    }

    const uint8_t sum = omega_neon_checksum((const uint8_t *)(buf + 1), (size_t)l);
    buf[l + 1] = '#';
    buf[l + 2] = vToH(sum >> 4);
    buf[l + 3] = vToH(sum & 0xF);
    buf[l + 4] = '\0';
    return omegaExchange(s, buf, (size_t)(l + 4));
}

// ─────────────────────────────────────────────
// MARK: - GDB ストップパケットパーサー [RSP 仕様準拠版]
// ─────────────────────────────────────────────
//
// 入力: gdb_strip_envelope 適用済みのペイロード (エンベロープなし)
//       例: "T05thread:p1.1;00:0000000000000000;..."
//
// GDB RSP 仕様:
//  - "Txx key:value;" 形式のキーバリューリスト
//  - キーは "thread", "threads", "hexadecimal-register-number" など
//  - レジスタ番号は 16 進数 (1〜4 桁)、値は LE hex
//  - ';' は各エントリの終端区切り
//
// sLen: strnlen(s, kPktBufSize) の値 (NUL 含まず)
//       '#' が残存する場合 (gdb_strip_envelope 未適用) も安全に処理。
// ─────────────────────────────────────────────

typedef struct {
    uint64_t x0, x1, x16, pc;
    uint8_t  stopSignal; ///< 0x05 = SIGTRAP (BRK)
    char     tid[64];
} GodState;

static void scanStopPkt(const char *s, size_t sLen, GodState *st) {
    if (!s || !st || sLen == 0) return;

    // [RSP] '#' が残存する場合に備えて end を '#' 手前に設定 (二重安全)
    const char *hashPtr = (const char *)memchr(s, '#', sLen);
    const char *end     = hashPtr ? hashPtr : s + sLen;

    const char *p = s;

    // ── 'T' ヘッダー: stop reason を 2 桁 hex でパース ────────
    if (p < end && *p == 'T') {
        p++;
        if ((end - p) >= 2 &&
            isxdigit((unsigned char)p[0]) &&
            isxdigit((unsigned char)p[1])) {
            st->stopSignal = (uint8_t)((kHexTable[(uint8_t)p[0]] << 4) |
                                        kHexTable[(uint8_t)p[1]]);
            p += 2;
        } else {
            return; // 不正フォーマット
        }
    }

    // ── キーバリューループ: memchr ベースで ';' を確定 ─────────
    while (p < end) {
        // トークン末尾の ';' を O(1) で検索
        const char *semi   = (const char *)memchr(p, ';', (size_t)(end - p));
        const char *tokEnd = semi ? semi : end;

        // ':' を検索してキーと値を分離
        const char *colon = (const char *)memchr(p, ':', (size_t)(tokEnd - p));
        if (!colon) {
            // ':' なし → 不明トークン (例: "watch" 等) → スキップ
            p = semi ? semi + 1 : end;
            continue;
        }

        const size_t keyLen = (size_t)(colon - p);
        const char  *val    = colon + 1;
        const size_t valLen = (size_t)(tokEnd - val);

        // ── "thread:tid" ─────────────────────────────────────
        // GDB RSP では "thread:p<pid>.<tid>" または単純な数値
        if (keyLen == 6 &&
            p[0]=='t' && p[1]=='h' && p[2]=='r' &&
            p[3]=='e' && p[4]=='a' && p[5]=='d') {
            const size_t copyLen = (valLen < 63) ? valLen : 63;
            memcpy(st->tid, val, copyLen);
            st->tid[copyLen] = '\0';

        // ── レジスタ: "rr:VVVVVVVVVVVVVVVV" (keyLen=1..4, valLen=16) ──
        } else if (keyLen >= 1 && keyLen <= 4 && valLen == 16) {
            // 全文字が hex digit であることを検証
            BOOL allHex = YES;
            for (size_t hc = 0; hc < 16; hc++) {
                if (!isxdigit((unsigned char)val[hc])) { allHex = NO; break; }
            }
            if (allHex) {
                const uint64_t v = decodeLE64(val);
                // レジスタ番号を hex 文字列 → uint32 に変換
                uint32_t regNum = 0;
                for (size_t ki = 0; ki < keyLen; ki++) {
                    regNum = (regNum << 4) | kHexTable[(uint8_t)p[ki]];
                }
                switch (regNum) {
                    case  0: st->x0  = v; break; // x0
                    case  1: st->x1  = v; break; // x1
                    case 16: st->x16 = v; break; // x16 / ip0
                    case 32: st->pc  = v; break; // pc
                    default: break;
                }
            }
        }
        // valLen == 8 (32 bit レジスタ) はここでは不使用

        // 次トークンへ: ';' の次、または末尾
        p = semi ? semi + 1 : end;
    }
}

// ─────────────────────────────────────────────
// MARK: - GDB メモリ書き込みヘルパー
// ─────────────────────────────────────────────

static BOOL omegaWriteMemory(OmegaSession *s,
                              uint64_t addr,
                              uint32_t size,
                              char fillHi, char fillLo)
{
    uint32_t sent = 0;
    while (sent < size) {
        const uint32_t chunk = MIN(size - sent, kWriteChunkSize);

        // ヘッダー: "M<addr>,<len>:" を s->pktBuf[1..] に書き込む
        const int hdrLen = snprintf(s->pktBuf + 1, s->pktBufSize - 5,
                                    "M%llx,%x:", addr + sent, chunk);
        if (hdrLen <= 0 || (size_t)(hdrLen + chunk * 2) >= s->pktBufSize - 5) {
            NSLog(@"[Omega] writeMemory: buffer overflow guard triggered");
            return NO;
        }

        // データ部分 (fillHi/fillLo を chunk * 2 バイト書き込む)
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
    dispatch_semaphore_t _launchSemaphore;
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

        AppInfo *info  = [AppInfo new];
        info.isSystem  = isSystem;

        plist_t bidNode = plist_dict_get_item(item, "CFBundleIdentifier");
        if (bidNode) {
            char *val = NULL;
            plist_get_string_val(bidNode, &val);
            if (val) { info.bundleId = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }
        if (!info.bundleId) continue;

        plist_t nameNode = plist_dict_get_item(item, "CFBundleDisplayName");
        if (!nameNode) nameNode = plist_dict_get_item(item, "CFBundleName");
        if (nameNode) {
            char *val = NULL;
            plist_get_string_val(nameNode, &val);
            if (val) { info.name = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
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

    __block BOOL completionFired = NO;
    dispatch_queue_t completionGuardQueue = dispatch_queue_create("omega.appmanager.launch.completion", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t launchSem = _launchSemaphore;

    void (^safeCompletion)(BOOL, NSString *) = ^(BOOL success, NSString *msg) {
        __block BOOL alreadyCompleted = NO;
        dispatch_sync(completionGuardQueue, ^{
            alreadyCompleted = completionFired;
            if (!completionFired) completionFired = YES;
        });
        if (alreadyCompleted) return;

        [[HeartbeatManager sharedManager] resumeHeartbeat];
        dispatch_semaphore_signal(launchSem);
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success, msg); });
        }
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
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
        [NSThread sleepForTimeInterval:0.2];

        // ── CoreDevice Proxy 接続 (指数バックオフリトライ) ────
        struct CoreDeviceProxyHandle *proxy = NULL;
        {
            struct IdeviceFfiError *err   = NULL;
            NSTimeInterval          delay = kRetryInitDelay;
            for (int i = 0; i < kMaxRetries; i++) {
                if (i > 0) {
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
            core_device_proxy_free(proxy); proxy = NULL;
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
            NSUInteger   envCnt = 0;

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
            process_control_free(procControl);
            remote_server_free(remoteServer);
            procControl  = NULL;
            remoteServer = NULL;

            if (jitMode == JitModeJS) {
                [self activateUniversalJitSyncForPid:pid adapter:adapter handshake:handshake];
            } else if (jitMode == JitModeNative) {
                [self activateGodlyNativeJitSyncForPid:pid adapter:adapter handshake:handshake];
            } else {
                NSLog(@"[Launch] Unknown jitMode %d — freeing handles.", (int)jitMode);
                rsd_handshake_free(handshake);
                adapter_free(adapter);
            }

            NSString *modeStr = (jitMode == JitModeJS) ? @"JS" : @"God-Speed";
            safeCompletion(YES, [NSString stringWithFormat:
                @"Launched with JIT (%@, PID: %llu).", modeStr, pid]);

        } else {
            // JitModeNone または pid == 0
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
    NSLog(@"[Omega-God] Starting session (PID: %llu)…", pid);

    struct DebugProxyHandle *proxy = NULL;
    {
        struct IdeviceFfiError *dbgErr = debug_proxy_connect_rsd(adapter, handshake, &proxy);
        if (dbgErr) {
            NSLog(@"[Omega-God] debug_proxy_connect_rsd failed: %s", dbgErr->message);
            idevice_error_free(dbgErr);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            return;
        }
    }

    char *pktBuf = (char *)malloc(kPktBufSize);
    if (!pktBuf) {
        NSLog(@"[Omega-God] malloc failed.");
        debug_proxy_free(proxy);
        rsd_handshake_free(handshake);
        adapter_free(adapter);
        return;
    }

    OmegaSession s = {
        .proxy      = proxy,
        .pktBuf     = pktBuf,
        .pktBufSize = kPktBufSize,
        .noAck      = NO
    };

    // vAttach
    { char *r = omegaSend(&s, "vAttach;%llx", pid); if (r) free(r); }

    // No-Ack モード交渉
    {
        char *r = omegaSend(&s, "QStartNoAckMode");
        if (r) { s.noAck = (strcmp(r, "OK") == 0); free(r); }
    }

    JSContext *jsCtx = [[JSContext alloc] init];
    jsCtx[@"log"] = ^(NSString *m) { NSLog(@"[Omega Script] %@", m); };

    // [CACHE-1] direct-mapped cache を取得してセッション開始時にクリア
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

    BOOL detached = NO;

    while (!detached) {
        // プロセス継続
        char *resp = omegaSend(&s, "vCont;c");
        if (!resp) {
            NSLog(@"[Omega-God] Connection lost.");
            break;
        }

        // [STRLEN] strnlen を使用 (バッファオーバーリード防止)
        const size_t respLen = strnlen(resp, kPktBufSize);

        // ── プロセス終了判定を最初に行う ──────────────────────
        // 'W' = 正常終了, 'X' = シグナル終了
        // gdb_strip_envelope 後なのでエンベロープなし
        if (respLen > 0 && (resp[0] == 'W' || resp[0] == 'X')) {
            NSLog(@"[Omega-God] Process exited (%c). Stopping session.", resp[0]);
            free(resp);
            detached = YES;
            break;
        }

        GodState st = {0};
        // [CRASH-1] gdb_strip_envelope は omegaReadResponse で適用済み
        //           ここでは純粋なペイロード (例: "T05thread:p1.1;...") が届く
        scanStopPkt(resp, respLen, &st);

        if (!st.tid[0] || st.pc == 0) {
            free(resp);
            continue;
        }

        // ── [CACHE-1] O(1) direct-mapped lookup ───────────────
        uint32_t instr    = 0;
        BOOL     cacheHit = NO;
        {
            GCache *hit = gcache_lookup(gcStore, st.pc);
            if (hit) { instr = hit->instr; cacheHit = YES; }
        }

        if (!cacheHit) {
            char *ir = omegaSend(&s, "m%llx,4", st.pc);
            if (ir) {
                // [STRLEN] strnlen 一度だけ
                if (strnlen(ir, 9) >= 8) {
                    instr    = decodeLE32(ir);
                    cacheHit = YES;
                    gcache_insert(gcStore, st.pc, instr); // O(1) insert
                }
                free(ir);
            }
        }

        if (!cacheHit) { free(resp); continue; }

        // ── ARM64 BRK 判定 ──────────────────────────────────
        const BOOL isSigTrap = (st.stopSignal == 0x05);

        if (isSigTrap && (instr & kArm64BrkMask) == kArm64BrkPattern) {
            const uint32_t imm = (instr >> 5) & 0xFFFF;

            // PC を BRK の次の命令へ進める
            {
                char nle[17];
                writeLE64Hex(nle, st.pc + 4);
                char *pr = omegaSend(&s, "P20=%s;thread:%s", nle, st.tid);
                if (pr) free(pr);
            }

            if (imm == kBrkImmOmegaCtrl) {
                if (st.x16 == kOmegaCmdDetach) {
                    detached = YES;

                } else if (st.x16 == kOmegaCmdPrepare) {
                    uint64_t addr = st.x0;
                    if (!addr) {
                        char *xr = omegaSend(&s, "_M%llx,rx", st.x1);
                        if (xr) { addr = strtoull(xr, NULL, 16); free(xr); }
                    }
                    if (addr) {
                        omegaWriteMemory(&s, addr, (uint32_t)st.x1, kFillHi, kFillLo);
                        char ale[17];
                        writeLE64Hex(ale, addr);
                        char *xr = omegaSend(&s, "P00=%s;thread:%s", ale, st.tid);
                        if (xr) free(xr);
                    }
                }

            } else if (imm == kBrkImmJsEval) {
                char *mr = omegaSend(&s, "m%llx,%llx", st.x0, st.x1);
                if (mr) {
                    @autoreleasepool {
                        // [STRLEN] strnlen 一度だけ
                        const size_t mrLen = strnlen(mr, kPktBufSize);
                        const size_t sl    = mrLen / 2;
                        char *sc = (char *)malloc(sl + 1);
                        if (sc) {
                            for (size_t k = 0; k < sl; k++) {
                                sc[k] = (char)hexPairToByte(mr[k*2], mr[k*2+1]);
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

        } else if (!isSigTrap &&
                   resp[0] == 'T' &&
                   respLen >= 3 &&
                   isxdigit((unsigned char)resp[1]) &&
                   isxdigit((unsigned char)resp[2]) &&
                   st.tid[0]) {
            // SIGTRAP 以外のシグナル → プロセスへ転送
            char *vr = omegaSend(&s, "vCont;S%c%c:%s", resp[1], resp[2], st.tid);
            if (vr) free(vr);
        }

        free(resp);
    }

    // ── 安全デタッチ ────────────────────────────────────────
    { char *r = omegaSend(&s, "vCont;c"); if (r) free(r); }
    { char *r = omegaSend(&s, "D");       if (r) free(r); }

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
    {
        struct IdeviceFfiError *dbgErr = debug_proxy_connect_rsd(adapter, handshake, &proxy);
        if (dbgErr) {
            NSLog(@"[JIT-JS] debug_proxy_connect_rsd failed: %s", dbgErr->message);
            idevice_error_free(dbgErr);
            rsd_handshake_free(handshake);
            adapter_free(adapter);
            return;
        }
    }

    // ── vAttach ──────────────────────────────────────────────
    // [FAST] thread-local バッファ (prepbuf_get) で malloc/free ゼロ
    {
        char *buf = prepbuf_get();
        if (buf) {
            OmegaSession setup = {
                .proxy      = proxy,
                .pktBuf     = buf,
                .pktBufSize = kPktBufSize,
                .noAck      = NO
            };
            char *r = omegaSend(&setup, "vAttach;%llx", pid);
            if (r) {
                NSLog(@"[JIT-JS] vAttach response: %s", r);
                free(r);
            } else {
                NSLog(@"[JIT-JS] vAttach got no response — continuing anyway.");
            }
            // buf は thread-local なので free しない
        }
    }

    // ── JSContext セットアップ ───────────────────────────────
    __block struct DebugProxyHandle *capturedProxy = proxy;

    JSContext *context = [[JSContext alloc] init];

    context[@"get_pid"] = ^uint64_t { return pid; };

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
            [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];
        if (!content) return [NSString stringWithFormat:@"ERROR: %@", e.localizedDescription];
        [[JSContext currentContext] evaluateScript:content];
        return @"OK";
    };

    // [FAST] prepare_memory_region: thread-local バッファで毎回 malloc ゼロ
    context[@"prepare_memory_region"] = ^NSString *(uint64_t startAddr, uint64_t jitPagesSize) {
        char *buf = prepbuf_get();
        if (!buf) return @"ERROR_ALLOC";
        OmegaSession os = {
            .proxy      = capturedProxy,
            .pktBuf     = buf,
            .pktBufSize = kPktBufSize,
            .noAck      = NO
        };
        BOOL ok = omegaWriteMemory(&os, startAddr, (uint32_t)jitPagesSize,
                                   kFillHi, kFillLo);
        // buf は thread-local なので free しない
        return ok ? @"OK" : @"ERROR_SEND";
    };

    context[@"log"] = ^(NSString *msg) { NSLog(@"[JIT Script] %@", msg); };

    // ── スクリプト読み込み ────────────────────────────────────
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
            NSString *bp = [[NSBundle mainBundle] pathForResource:@"universal" ofType:@"js"];
            if (bp) {
                script = [NSString stringWithContentsOfFile:bp
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
            }
        }
        if (!script) script = kUniversalJitScript;
    }

    [context evaluateScript:script];

    // JSContext の完全解放後に proxy を解放 (Use-After-Free 防止)
    context = nil;
    capturedProxy = NULL;

    debug_proxy_free(proxy);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    NSLog(@"[JIT-JS] Session complete.");
}

@end
