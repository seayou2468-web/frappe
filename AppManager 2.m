#import "AppManager.h"
#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "HeartbeatManager.h"
#import "JITScripts.h"
#include <arm_neon.h>
#include <stdarg.h>
#include <pthread.h>
#include <netinet/tcp.h>
#include <sys/socket.h>

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

static const size_t   kPageSize       = 4096;
static const uint64_t kPageAddrMask   = 0xFFFFFFFFFFFFF000ULL;
static const size_t   kPageOffset     = 12;

#define kCacheSets     64u
#define kCacheWays     4u
#define kInstrPerPage  1024u

#define OMEGA_SO_BUFSIZE     (512 * 1024)

#define REG_FOUND_X0   (1ULL << 0)
#define REG_FOUND_X1   (1ULL << 1)
#define REG_FOUND_X16  (1ULL << 16)
#define REG_FOUND_PC   (1ULL << 32)

#define OMEGA_STACK_BUF_SIZE 512u

#define DEFERRED_WRITE_MAX   8

NS_INLINE const char *omegaSafeErrCString(const struct IdeviceFfiError *err) {
    if (!err || !err->message || err->message[0] == '\0') return "(no detail)";
    return err->message;
}
NS_INLINE NSString *omegaErrNSString(const struct IdeviceFfiError *err) {
    return [NSString stringWithUTF8String:omegaSafeErrCString(err)];
}

typedef struct {
    size_t maxPktSize;
    BOOL   hasNonStop;
    BOOL   hasMultiProc;
} SessionCaps;

typedef struct {
    struct DebugProxyHandle *proxy;
    char   *pktBuf;
    size_t  pktBufSize;
    BOOL    noAck;
    SessionCaps caps;
} OmegaSession;

typedef struct {
    uint64_t base;
    uint32_t instrs[kInstrPerPage];
    uint64_t gen;
    BOOL     loaded;
} PageEntry;

typedef struct {
    PageEntry ways[kCacheWays];
} CacheSet;

typedef struct {
    uint64_t base;
    BOOL     pending;
} PrefetchSlot;

typedef struct {
    CacheSet     sets[kCacheSets];
    uint64_t     globalGen;

    PrefetchSlot prefetch[2];
    int          pf_head;
    int          pf_count;

    uint64_t     lastPageBase;
    BOOL         lastPageValid;
} PageStore;

static pthread_key_t  s_pagestore_key;
static pthread_once_t s_pagestore_once = PTHREAD_ONCE_INIT;
static void pagestore_dtor(void *p) { free(p); }
static void pagestore_key_init(void) { pthread_key_create(&s_pagestore_key, pagestore_dtor); }

static PageStore *pagestore_get(void) {
    pthread_once(&s_pagestore_once, pagestore_key_init);
    PageStore *ps = (PageStore *)pthread_getspecific(s_pagestore_key);
    if (__builtin_expect(!ps, 0)) {
        ps = (PageStore *)calloc(1, sizeof(PageStore));
        pthread_setspecific(s_pagestore_key, ps);
    }
    return ps;
}

NS_INLINE uint32_t page_set_index(uint64_t pageBase) {
    const uint32_t pn = (uint32_t)(pageBase >> kPageOffset);
    return (pn * 2654435761u) >> 26;
}

NS_INLINE const uint32_t *pcache_lookup(PageStore *ps, uint64_t pc) {
    const uint64_t base = pc & kPageAddrMask;
    CacheSet      *set  = &ps->sets[page_set_index(base)];
    for (uint32_t w = 0; w < kCacheWays; w++) {
        PageEntry *e = &set->ways[w];
        if (__builtin_expect(e->loaded && e->base == base, 0)) {
            e->gen = ++ps->globalGen;
            return &e->instrs[(pc - base) >> 2];
        }
    }
    return NULL;
}

typedef struct {
    uint64_t pc;
    uint64_t x0;
    uint64_t x1;
    uint64_t x16;
    BOOL     valid;
} RegSnap;

static pthread_key_t  s_regsnap_key;
static pthread_once_t s_regsnap_once = PTHREAD_ONCE_INIT;
static void regsnap_dtor(void *p) { free(p); }
static void regsnap_key_init(void) { pthread_key_create(&s_regsnap_key, regsnap_dtor); }

static RegSnap *regsnap_get(void) {
    pthread_once(&s_regsnap_once, regsnap_key_init);
    RegSnap *rs = (RegSnap *)pthread_getspecific(s_regsnap_key);
    if (__builtin_expect(!rs, 0)) {
        rs = (RegSnap *)calloc(1, sizeof(RegSnap));
        pthread_setspecific(s_regsnap_key, rs);
    }
    return rs;
}

typedef struct {
    char pkt[64];
    size_t pktLen;
} DeferredWrite;

typedef struct {
    DeferredWrite entries[DEFERRED_WRITE_MAX];
    int           count;
} DeferredQueue;

static pthread_key_t  s_prepbuf_key;
static pthread_once_t s_prepbuf_once = PTHREAD_ONCE_INIT;
static void prepbuf_dtor(void *p) { free(p); }
static void prepbuf_key_init(void) { pthread_key_create(&s_prepbuf_key, prepbuf_dtor); }

static char *prepbuf_get(void) {
    pthread_once(&s_prepbuf_once, prepbuf_key_init);
    char *buf = (char *)pthread_getspecific(s_prepbuf_key);
    if (__builtin_expect(!buf, 0)) {
        buf = (char *)malloc(kPktBufSize);
        if (buf) pthread_setspecific(s_prepbuf_key, buf);
    }
    return buf;
}

static const uint8_t kHexTable[256] = {
    ['0']=0,['1']=1,['2']=2,['3']=3,['4']=4,
    ['5']=5,['6']=6,['7']=7,['8']=8,['9']=9,
    ['a']=10,['b']=11,['c']=12,['d']=13,['e']=14,['f']=15,
    ['A']=10,['B']=11,['C']=12,['D']=13,['E']=14,['F']=15
};

NS_INLINE char    vToH(uint8_t v)                  { return "0123456789abcdef"[v & 0xF]; }
NS_INLINE uint8_t hexPairToByte(char hi, char lo)  {
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

static BOOL decodeLE64_safe(const char *src, size_t avail, uint64_t *out) {
    if (!src || !out || avail < 16) return NO;
    *out = decodeLE64(src);
    return YES;
}

static BOOL decodeLE32_safe(const char *src, size_t avail, uint32_t *out) {
    if (!src || !out || avail < 8) return NO;
    *out = decodeLE32(src);
    return YES;
}

static uint8_t omega_neon_checksum(const uint8_t *p, size_t l) {
    if (__builtin_expect(l == 0, 0)) return 0;
    uint32x4_t vsum = vdupq_n_u32(0);
    size_t i = 0;
    for (; i + 16 <= l; i += 16) {

        vsum = vaddq_u32(vsum, vpaddlq_u16(vpaddlq_u8(vld1q_u8(p + i))));
    }
    uint32_t s = vaddvq_u32(vsum);
    for (; i < l; i++) s += p[i];
    return (uint8_t)(s & 0xFF);
}

NS_INLINE const char *neon_find_delim(const char *p, size_t len, char *out_ch) {
    const uint8x16_t vs = vdupq_n_u8((uint8_t)';');
    const uint8x16_t vc = vdupq_n_u8((uint8_t)':');
    const uint8_t   *b  = (const uint8_t *)p;
    size_t i = 0;

    const size_t neon_limit = (len > 16) ? (len - 16) : 0;

    for (; i + 16 <= neon_limit; i += 16) {
        uint8x16_t v   = vld1q_u8(b + i);
        uint8x16_t any = vorrq_u8(vceqq_u8(v, vs), vceqq_u8(v, vc));
        if (vmaxvq_u8(any)) {
            for (size_t j = i, end = i + 16; j < end; j++) {
                if (b[j] == ';' || b[j] == ':') {
                    if (out_ch) *out_ch = (char)b[j];
                    return p + j;
                }
            }
        }
    }

    for (; i < len; i++) {
        if (b[i] == ';' || b[i] == ':') {
            if (out_ch) *out_ch = (char)b[i];
            return p + i;
        }
    }
    return NULL;
}

NS_INLINE const char *neon_find_hash_rev(const char *p, size_t len) {

    const size_t tailLen = (len > 32) ? 32 : len;
    for (ssize_t i = (ssize_t)len - 1; i >= (ssize_t)(len - tailLen); i--) {
        if (p[i] == '#') return p + i;
    }

    if (len > 32) {
        for (ssize_t i = (ssize_t)(len - 32) - 1; i >= 0; i--) {
            if (p[i] == '#') return p + i;
        }
    }
    return NULL;
}

static char *gdb_strip_envelope(char *r, size_t rlen) {
    if (!r || rlen < 1 || r[0] != '$') return r;

    const char *hp      = neon_find_hash_rev(r, rlen);
    ssize_t     hashPos = hp ? (ssize_t)(hp - r) : -1;

    if (hashPos > 0) {

        const size_t payloadLen = (size_t)hashPos - 1;
        memmove(r, r + 1, payloadLen);
        r[payloadLen] = '\0';
    } else if (hashPos == 0) {

        r[0] = '\0';
    } else {

        if (rlen > 1) {
            memmove(r, r + 1, rlen - 1);
        }
        r[rlen - 1] = '\0';
    }
    return r;
}

static char *omegaReadResponse(OmegaSession *s, BOOL *out_nak) {
    if (out_nak) *out_nak = NO;

    BOOL ackReceived = NO;

    for (int rd = 0; rd < 6; rd++) {
        char *r = NULL;
        struct IdeviceFfiError *err = debug_proxy_read_response(s->proxy, &r);
        if (err) {
            idevice_error_free(err);
            if (ackReceived) continue;
            return NULL;
        }
        if (!r) {
            if (ackReceived) continue;
            return NULL;
        }

        const size_t rlen = strnlen(r, kPktBufSize);

        if (s->noAck) return gdb_strip_envelope(r, rlen);

        if (r[0] == '%') { free(r); continue; }

        if (r[0] == '-') {
            free(r);
            if (ackReceived) { continue; }
            if (out_nak) *out_nak = YES;
            return NULL;
        }

        if (r[0] == '+') {
            ackReceived = YES;
            if (r[1] != '\0') {
                const size_t dl = rlen - 1;
                memmove(r, r + 1, dl + 1);
                return gdb_strip_envelope(r, dl);
            }
            free(r); continue;
        }

        return gdb_strip_envelope(r, rlen);
    }

    if (ackReceived) NSLog(@"[Omega] Read timeout after ACK.");
    return NULL;
}

static char *omegaReadStop(OmegaSession *s) {
    for (int rd = 0; rd < 12; rd++) {
        char *r = NULL;
        struct IdeviceFfiError *err = debug_proxy_read_response(s->proxy, &r);
        if (err) { idevice_error_free(err); return NULL; }
        if (!r)  return NULL;

        const size_t rlen  = strnlen(r, kPktBufSize);
        char        *p     = gdb_strip_envelope(r, rlen);

        if (p && p[0] != '\0') {
            const char c = p[0];
            if (c == 'T' || c == 'W' || c == 'X' || c == 'S') return p;
        }
        if (p != r) free(r); else free(p);
    }
    return NULL;
}

static char *omegaExchange(OmegaSession *s, const char *pkt, size_t pktLen) {
    if (__builtin_expect(!pkt || pktLen == 0, 0)) return NULL;

    for (int attempt = 0; attempt < 3; attempt++) {
        struct IdeviceFfiError *e =
            debug_proxy_send_raw(s->proxy, (const uint8_t *)pkt, pktLen);
        if (e) { idevice_error_free(e); continue; }

        BOOL gotNak = NO;
        char *r = omegaReadResponse(s, &gotNak);
        if (r)      return r;
        if (gotNak) continue;
        break;
    }
    return NULL;
}

static BOOL omegaSendOnly(OmegaSession *s, const char *pkt, size_t pktLen) {
    struct IdeviceFfiError *e =
        debug_proxy_send_raw(s->proxy, (const uint8_t *)pkt, pktLen);
    if (e) { idevice_error_free(e); return NO; }
    return YES;
}

static char *omegaSend(OmegaSession *s, const char *fmt, ...) {

    va_list probe;
    va_start(probe, fmt);
    const int l = vsnprintf(NULL, 0, fmt, probe);
    va_end(probe);
    if (l <= 0) return NULL;

    char stackBuf[OMEGA_STACK_BUF_SIZE];
    char *buf;
    if ((size_t)l + 5 <= OMEGA_STACK_BUF_SIZE) {
        buf = stackBuf;
    } else if ((size_t)l + 5 <= s->pktBufSize) {
        buf = s->pktBuf;
    } else {
        return NULL;
    }

    buf[0] = '$';
    va_list write;
    va_start(write, fmt);
    vsnprintf(buf + 1, (size_t)l + 1, fmt, write);
    va_end(write);

    const uint8_t sum = omega_neon_checksum((const uint8_t *)(buf + 1), (size_t)l);
    buf[l + 1] = '#';
    buf[l + 2] = vToH(sum >> 4);
    buf[l + 3] = vToH(sum & 0xF);
    buf[l + 4] = '\0';
    return omegaExchange(s, buf, (size_t)(l + 4));
}

static BOOL omegaSendFmt(OmegaSession *s, const char *fmt, ...) {
    va_list probe;
    va_start(probe, fmt);
    const int l = vsnprintf(NULL, 0, fmt, probe);
    va_end(probe);
    if (l <= 0) return NO;

    char stackBuf[OMEGA_STACK_BUF_SIZE];
    char *buf;
    if ((size_t)l + 5 <= OMEGA_STACK_BUF_SIZE) {
        buf = stackBuf;
    } else if ((size_t)l + 5 <= s->pktBufSize) {
        buf = s->pktBuf;
    } else {
        return NO;
    }

    buf[0] = '$';
    va_list write;
    va_start(write, fmt);
    vsnprintf(buf + 1, (size_t)l + 1, fmt, write);
    va_end(write);

    const uint8_t sum = omega_neon_checksum((const uint8_t *)(buf + 1), (size_t)l);
    buf[l + 1] = '#';
    buf[l + 2] = vToH(sum >> 4);
    buf[l + 3] = vToH(sum & 0xF);
    buf[l + 4] = '\0';
    return omegaSendOnly(s, buf, (size_t)(l + 4));
}

static void dq_flush(DeferredQueue *dq, OmegaSession *s) {
    if (!s->noAck || dq->count == 0) return;
    for (int i = 0; i < dq->count; i++) {
        omegaSendOnly(s, dq->entries[i].pkt, dq->entries[i].pktLen);
    }
    dq->count = 0;
}

static void dq_push_Preg(DeferredQueue *dq, OmegaSession *s,
                          uint8_t regHex, uint64_t value, const char *tid) {
    if (dq->count >= DEFERRED_WRITE_MAX) {

        char *r = omegaSend(s, "P%02x=%016llx;thread:%s",
                            (unsigned)regHex, value, tid);
        if (r) free(r);
        return;
    }
    DeferredWrite *dw = &dq->entries[dq->count];
    char vhex[17];
    writeLE64Hex(vhex, value);
    const int l = snprintf(dw->pkt + 1, sizeof(dw->pkt) - 5,
                           "P%02x=%s;thread:%s", (unsigned)regHex, vhex, tid);
    if (l <= 0 || (size_t)l >= sizeof(dw->pkt) - 5) return;
    dw->pkt[0] = '$';
    const uint8_t sum = omega_neon_checksum((const uint8_t *)(dw->pkt + 1), (size_t)l);
    dw->pkt[l + 1] = '#';
    dw->pkt[l + 2] = vToH(sum >> 4);
    dw->pkt[l + 3] = vToH(sum & 0xF);
    dw->pkt[l + 4] = '\0';
    dw->pktLen = (size_t)(l + 4);
    dq->count++;
}

static void omega_tune_socket(struct DebugProxyHandle *proxy) {
#if defined(OMEGA_HAS_PROXY_GET_FD)
    int fd = debug_proxy_get_fd(proxy);
    if (fd < 0) return;

    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    int bufSize = OMEGA_SO_BUFSIZE;
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufSize, sizeof(bufSize));
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufSize, sizeof(bufSize));

    NSLog(@"[Omega] Socket tuned: fd=%d TCP_NODELAY=1 SO_BUF=%d", fd, bufSize);
#else
    (void)proxy;

#endif
}

static void omegaNegotiate(OmegaSession *s) {

    char *qr = omegaSend(s,
        "qSupported:PacketSize=ffff;QNonStop+;multiprocess+;xmlRegisters=arm");
    if (qr) {
        const char *ps = strstr(qr, "PacketSize=");
        if (ps) {
            unsigned long negotiated = strtoul(ps + 11, NULL, 16);
            if (negotiated > 0 && negotiated < s->pktBufSize)
                s->pktBufSize = negotiated;
        }
        s->caps.hasNonStop   = (strstr(qr, "QNonStop+") != NULL);
        s->caps.hasMultiProc = (strstr(qr, "multiprocess+") != NULL);
        free(qr);
    }

    if (s->caps.hasNonStop) {
        char *nr = omegaSend(s, "QNonStop:1");
        if (nr) { NSLog(@"[Omega] QNonStop: %s", nr); free(nr); }
    }

    char *ar = omegaSend(s, "QStartNoAckMode");
    if (ar) {
        s->noAck = (strncmp(ar, "OK", 2) == 0);
        free(ar);
        if (s->noAck) NSLog(@"[Omega] No-Ack enabled.");
    }
}

static PageEntry *pcache_evict_way(PageStore *ps, uint64_t base);

static void pf_enqueue(PageStore *ps, OmegaSession *s, uint64_t base) {
    if (!s->noAck || ps->pf_count >= 2) return;

    for (int i = 0; i < ps->pf_count; i++) {
        const int slot = (ps->pf_head + i) & 1;
        if (ps->prefetch[slot].pending && ps->prefetch[slot].base == base)
            return;
    }

    if (omegaSendFmt(s, "m%llx,1000", base)) {
        const int w = (ps->pf_head + ps->pf_count) & 1;
        ps->prefetch[w].base    = base;
        ps->prefetch[w].pending = YES;
        ps->pf_count++;
    }
}

static BOOL pf_consume(PageStore *ps, OmegaSession *s, uint64_t base, PageEntry *entry) {
    if (ps->pf_count == 0) return NO;

    BOOL found = NO;
    for (int i = 0; i < ps->pf_count; i++) {
        if (ps->prefetch[(ps->pf_head + i) & 1].base == base) { found = YES; break; }
    }
    if (!found) return NO;

    while (ps->pf_count > 0 && ps->prefetch[ps->pf_head & 1].base != base) {
        const int     drainSlot = ps->pf_head & 1;
        const uint64_t drainBase = ps->prefetch[drainSlot].base;

        char *dr = omegaReadResponse(s, NULL);
        ps->prefetch[drainSlot].pending = NO;
        ps->pf_head = (ps->pf_head + 1) & 1;
        ps->pf_count--;

        if (dr) {

            const size_t dlen = strnlen(dr, kPktBufSize);
            if (dlen >= 8 && dr[0] != 'E' && dr[0] != 'e' &&
                isxdigit((unsigned char)dr[0])) {
                CacheSet *dSet = &ps->sets[page_set_index(drainBase)];

                PageEntry *dEntry = NULL;
                for (uint32_t w = 0; w < kCacheWays; w++) {
                    if (!dSet->ways[w].loaded || dSet->ways[w].base == drainBase) {
                        dEntry = &dSet->ways[w]; break;
                    }
                }
                if (!dEntry) dEntry = pcache_evict_way(ps, drainBase);
                const size_t instCount = MIN(dlen / 8, kInstrPerPage);
                dEntry->base   = drainBase;
                dEntry->loaded = NO;
                memset(dEntry->instrs, 0, sizeof(dEntry->instrs));
                for (size_t k = 0; k < instCount; k++) {
                    uint32_t v = 0;
                    if (decodeLE32_safe(dr + k * 8, dlen - k * 8, &v))
                        dEntry->instrs[k] = v;
                }
                dEntry->loaded = YES;
                dEntry->gen    = ++ps->globalGen;
            }
            free(dr);
        }
    }

    if (ps->pf_count == 0 || ps->prefetch[ps->pf_head & 1].base != base) return NO;

    const int matchSlot = ps->pf_head & 1;
    char *pr = omegaReadResponse(s, NULL);
    ps->prefetch[matchSlot].pending = NO;
    ps->pf_head  = (ps->pf_head + 1) & 1;
    ps->pf_count--;

    if (!pr) return NO;
    const size_t plen = strnlen(pr, kPktBufSize);

    if (plen < 8 || pr[0] == 'E' || pr[0] == 'e' ||
        !isxdigit((unsigned char)pr[0])) {
        free(pr);
        return NO;
    }

    const size_t instCount = MIN(plen / 8, kInstrPerPage);
    entry->base   = base;
    entry->loaded = NO;
    memset(entry->instrs, 0, sizeof(entry->instrs));
    for (size_t k = 0; k < instCount; k++) {
        uint32_t instr = 0;
        if (decodeLE32_safe(pr + k * 8, plen - k * 8, &instr))
            entry->instrs[k] = instr;
    }
    entry->loaded = YES;
    entry->gen    = ++ps->globalGen;
    free(pr);
    return YES;
}

static PageEntry *pcache_evict_way(PageStore *ps, uint64_t base) {
    CacheSet *set    = &ps->sets[page_set_index(base)];
    uint64_t  minGen = UINT64_MAX;
    PageEntry *victim = &set->ways[0];
    for (uint32_t w = 0; w < kCacheWays; w++) {
        if (!set->ways[w].loaded) return &set->ways[w];
        if (set->ways[w].gen < minGen) {
            minGen = set->ways[w].gen;
            victim = &set->ways[w];
        }
    }
    return victim;
}

static const uint32_t *pcache_load(PageStore *ps, OmegaSession *s, uint64_t pc) {
    const uint64_t base = pc & kPageAddrMask;

    CacheSet  *set   = &ps->sets[page_set_index(base)];
    PageEntry *entry = NULL;
    for (uint32_t w = 0; w < kCacheWays; w++) {
        if (!set->ways[w].loaded) { entry = &set->ways[w]; break; }
    }
    if (!entry) entry = pcache_evict_way(ps, base);

    if (pf_consume(ps, s, base, entry)) {

        pf_enqueue(ps, s, base + kPageSize);
        if (base >= kPageSize) pf_enqueue(ps, s, base - kPageSize);
        ps->lastPageBase  = base;
        ps->lastPageValid = YES;
        return &entry->instrs[(pc - base) >> 2];
    }

    char *mr = omegaSend(s, "m%llx,1000", base);
    if (!mr) return NULL;

    const size_t mlen = strnlen(mr, kPktBufSize);
    if (mlen < 8 || mr[0] == 'E' || mr[0] == 'e' || !isxdigit((unsigned char)mr[0])) {
        free(mr); return NULL;
    }

    const size_t instCount = MIN(mlen / 8, kInstrPerPage);
    entry->base   = base;
    entry->loaded = NO;
    memset(entry->instrs, 0, sizeof(entry->instrs));
    for (size_t i = 0; i < instCount; i++) {
        uint32_t instr = 0;
        if (decodeLE32_safe(mr + i * 8, mlen - i * 8, &instr))
            entry->instrs[i] = instr;
    }
    entry->loaded = YES;
    entry->gen    = ++ps->globalGen;
    free(mr);

    if (ps->lastPageValid) {
        if (base == ps->lastPageBase + kPageSize) {

            pf_enqueue(ps, s, base + kPageSize);
            pf_enqueue(ps, s, base + 2 * kPageSize);
        } else if (base >= kPageSize && base == ps->lastPageBase - kPageSize) {

            pf_enqueue(ps, s, base - kPageSize);
            if (base >= 2 * kPageSize) pf_enqueue(ps, s, base - 2 * kPageSize);
        } else {

            pf_enqueue(ps, s, base + kPageSize);
            if (base >= kPageSize) pf_enqueue(ps, s, base - kPageSize);
        }
    } else {

        pf_enqueue(ps, s, base + kPageSize);
        if (base >= kPageSize) pf_enqueue(ps, s, base - kPageSize);
    }
    ps->lastPageBase  = base;
    ps->lastPageValid = YES;

    return &entry->instrs[(pc - base) >> 2];
}

NS_INLINE BOOL neon_is_hex16_unsafe(const char *src) {
    const uint8x16_t v        = vld1q_u8((const uint8_t *)src);
    const uint8x16_t lower    = vorrq_u8(v, vdupq_n_u8(0x20));

    const uint8x16_t is_digit = vandq_u8(vcgeq_u8(v,     vdupq_n_u8('0')),
                                          vcleq_u8(v,     vdupq_n_u8('9')));
    const uint8x16_t is_alpha = vandq_u8(vcgeq_u8(lower, vdupq_n_u8('a')),
                                          vcleq_u8(lower, vdupq_n_u8('f')));
    return (vminvq_u8(vorrq_u8(is_digit, is_alpha)) == 0xFF) ? YES : NO;
}

NS_INLINE BOOL neon_is_hex16_safe(const char *src, size_t avail) {
    if (__builtin_expect(!src || avail < 16, 0)) return NO;
    return neon_is_hex16_unsafe(src);
}

static BOOL omegaFetchPC(OmegaSession *s, uint64_t *out_pc) {
    char *pr = omegaSend(s, "p20");
    if (!pr) return NO;
    const size_t plen = strnlen(pr, 20);
    BOOL ok = neon_is_hex16_safe(pr, plen) && decodeLE64_safe(pr, plen, out_pc);
    free(pr);
    return ok;
}

typedef struct {
    uint64_t  x0, x1, x16, pc;
    uint8_t   stopSignal;
    char      tid[64];
    uint64_t  foundMask;
} GodState;

static void scanStopPkt(const char *s, size_t sLen, GodState *st) {
    if (!s || !st || sLen == 0) return;

    const char *hp  = neon_find_hash_rev(s, sLen);
    const char *end = hp ? hp : s + sLen;
    const char *p   = s;

    if (p < end && *p == 'T') {
        p++;
        if ((end - p) >= 2 &&
            isxdigit((unsigned char)p[0]) && isxdigit((unsigned char)p[1])) {
            st->stopSignal = (uint8_t)((kHexTable[(uint8_t)p[0]] << 4) |
                                        kHexTable[(uint8_t)p[1]]);
            p += 2;
        } else return;
    }

    while (p < end) {
        const size_t remaining = (size_t)(end - p);
        char         delim_ch  = 0;
        const char  *d1        = neon_find_delim(p, remaining, &delim_ch);

        if (!d1) break;

        if (delim_ch == ';') {

            p = d1 + 1;
            continue;
        }

        const size_t keyLen = (size_t)(d1 - p);
        const char  *val    = d1 + 1;

        const size_t valRemain = (size_t)(end - val);
        char         dummy     = 0;
        const char  *semi      = NULL;
        {

            const char *d2 = neon_find_delim(val, valRemain, &dummy);
            if (d2 && dummy == ';') semi = d2;
            else if (d2 && dummy == ':') semi = NULL;
        }
        const char  *tokEnd = semi ? semi : end;
        const size_t valLen = (size_t)(tokEnd - val);

        if (keyLen == 6 &&
            p[0]=='t'&&p[1]=='h'&&p[2]=='r'&&p[3]=='e'&&p[4]=='a'&&p[5]=='d') {

            const size_t cl = (valLen < 63) ? valLen : 63;
            memcpy(st->tid, val, cl);
            st->tid[cl] = '\0';

        } else if (keyLen >= 2 && keyLen <= 8 && valLen >= 16) {

            if (!neon_is_hex16_safe(val, valLen)) {
                p = semi ? semi + 1 : end;
                continue;
            }

            uint64_t v = 0;
            if (!decodeLE64_safe(val, valLen, &v)) {
                p = semi ? semi + 1 : end;
                continue;
            }

            if (keyLen == 2) {
                const uint8_t k0 = (uint8_t)p[0], k1 = (uint8_t)p[1];
                if      (k0 == '0' && k1 == '0') { st->x0  = v; st->foundMask |= REG_FOUND_X0;  }
                else if (k0 == '0' && k1 == '1') { st->x1  = v; st->foundMask |= REG_FOUND_X1;  }
                else if (k0 == '1' && k1 == '0') { st->x16 = v; st->foundMask |= REG_FOUND_X16; }
                else if (k0 == '2' && k1 == '0') { st->pc  = v; st->foundMask |= REG_FOUND_PC;  }

            }

        }

        p = semi ? semi + 1 : end;
    }
}

static BOOL omegaWriteMemory(OmegaSession *s,
                              uint64_t addr, uint32_t size,
                              char fillHi, char fillLo)
{
    uint32_t sent = 0;
    while (sent < size) {
        const uint32_t chunk = MIN(size - sent, kWriteChunkSize);

        const int hdrLen = snprintf(s->pktBuf + 1, s->pktBufSize - 5,
                                    "M%llx,%x:", addr + sent, chunk);
        if (hdrLen <= 0 || (size_t)(hdrLen + chunk * 2) >= s->pktBufSize - 5) {
            NSLog(@"[Omega] writeMemory: overflow guard");
            return NO;
        }

        char *data = s->pktBuf + 1 + hdrLen;
        for (uint32_t j = 0; j < chunk; j++) {
            data[j*2]   = fillHi;
            data[j*2+1] = fillLo;
        }

        s->pktBuf[0] = '$';
        const size_t  payloadLen = (size_t)(hdrLen + chunk * 2);
        const uint8_t sum = omega_neon_checksum((const uint8_t *)(s->pktBuf + 1), payloadLen);
        s->pktBuf[payloadLen + 1] = '#';
        s->pktBuf[payloadLen + 2] = vToH(sum >> 4);
        s->pktBuf[payloadLen + 3] = vToH(sum & 0xF);
        s->pktBuf[payloadLen + 4] = '\0';

        char *r = omegaExchange(s, s->pktBuf, payloadLen + 4);
        if (!r) { NSLog(@"[Omega] writeMemory: exchange failed at %u", sent); return NO; }
        free(r);
        sent += chunk;
    }
    return YES;
}

@implementation AppInfo
@end

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
    if (self) { _launchSemaphore = dispatch_semaphore_create(1); }
    return self;
}

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
            NSString *msg = omegaErrNSString(err);
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
        NSLog(@"[Apps] Browse error for %s: %s", type, omegaSafeErrCString(err));
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
    dispatch_semaphore_t launchSem = _launchSemaphore;

    void (^safeCompletion)(BOOL, NSString *) = ^(BOOL success, NSString *msg) {
        BOOL already = NO;
        @synchronized (self) { already = completionFired; if (!already) completionFired = YES; }
        if (already) return;
        [[HeartbeatManager sharedManager] resumeHeartbeat];
        dispatch_semaphore_signal(launchSem);
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(success, msg); });
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        if (dispatch_semaphore_wait(launchSem,
                dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) != 0) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, @"Previous JIT session timed out");
            });
            return;
        }
        [[HeartbeatManager sharedManager] pauseHeartbeat];

        {
            struct LockdowndClientHandle *warmup = NULL;
            struct IdeviceFfiError *we = lockdownd_connect(provider, &warmup);
            if (!we) {
                plist_t udid = NULL;
                lockdownd_get_value(warmup, "UniqueDeviceID", NULL, &udid);
                if (udid) plist_free(udid);
                lockdownd_client_free(warmup);
            } else { idevice_error_free(we); }
        }
        [NSThread sleepForTimeInterval:0.2];

        struct CoreDeviceProxyHandle *proxy = NULL;
        {
            struct IdeviceFfiError *err = NULL;
            NSTimeInterval delay = kRetryInitDelay;
            for (int i = 0; i < kMaxRetries; i++) {
                if (i > 0) { idevice_error_free(err); err = NULL;
                             [NSThread sleepForTimeInterval:delay]; delay *= kRetryBackoff; }
                err = core_device_proxy_connect(provider, &proxy);
                if (!err) break;
            }
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Tunnel Error: %@", omegaErrNSString(err)];
                idevice_error_free(err); safeCompletion(NO, msg); return;
            }
        }

        uint16_t rsdPort = 0;
        {
            struct IdeviceFfiError *err = core_device_proxy_get_server_rsd_port(proxy, &rsdPort);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"RSD Error: %@", omegaErrNSString(err)];
                idevice_error_free(err); core_device_proxy_free(proxy); safeCompletion(NO, msg); return;
            }
        }

        struct AdapterHandle *adapter = NULL;
        {
            struct IdeviceFfiError *err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
            proxy = NULL;
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Adapter Error: %@", omegaErrNSString(err)];
                idevice_error_free(err); safeCompletion(NO, msg); return;
            }
        }

        struct ReadWriteOpaque *rsdStream = NULL;
        {
            struct IdeviceFfiError *err = adapter_connect(adapter, rsdPort, &rsdStream);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Stream Error: %@", omegaErrNSString(err)];
                idevice_error_free(err); adapter_free(adapter); safeCompletion(NO, msg); return;
            }
        }

        struct RsdHandshakeHandle *handshake = NULL;
        {
            struct IdeviceFfiError *err = rsd_handshake_new(rsdStream, &handshake);
            rsdStream = NULL;
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Handshake Error: %@", omegaErrNSString(err)];
                idevice_error_free(err); adapter_free(adapter); safeCompletion(NO, msg); return;
            }
        }

        struct RemoteServerHandle *remoteServer = NULL;
        {
            struct IdeviceFfiError *err = remote_server_connect_rsd(adapter, handshake, &remoteServer);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"RemoteServer Error: %@", omegaErrNSString(err)];
                idevice_error_free(err); rsd_handshake_free(handshake); adapter_free(adapter);
                safeCompletion(NO, msg); return;
            }
        }

        struct ProcessControlHandle *procControl = NULL;
        {
            struct IdeviceFfiError *err = process_control_new(remoteServer, &procControl);
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"ProcessControl Error: %@", omegaErrNSString(err)];
                idevice_error_free(err); remote_server_free(remoteServer);
                rsd_handshake_free(handshake); adapter_free(adapter); safeCompletion(NO, msg); return;
            }
        }

        uint64_t pid = 0;
        {
            const char **env = NULL;
            NSUInteger envCnt = 0;
            if (jitMode != JitModeNone) {
                envCnt = 1;
                env    = (const char **)malloc(2 * sizeof(char *));
                env[0] = strdup("DEBUG_AUTOMATION_SCRIPTS=1");
                env[1] = NULL;
            }
            struct IdeviceFfiError *err =
                process_control_launch_app(procControl, [bid UTF8String],
                                           env, (uint32_t)envCnt, NULL, 0, NO, YES, &pid);
            if (env) { for (NSUInteger i = 0; i < envCnt; i++) free((void *)env[i]); free(env); }
            if (err) {
                NSString *msg = [NSString stringWithFormat:@"Launch Error: %@", omegaErrNSString(err)];
                idevice_error_free(err);
                process_control_free(procControl); remote_server_free(remoteServer);
                rsd_handshake_free(handshake); adapter_free(adapter); safeCompletion(NO, msg); return;
            }
        }

        if (jitMode != JitModeNone && pid > 0) {
            process_control_disable_memory_limit(procControl, pid);
            process_control_free(procControl); remote_server_free(remoteServer);
            procControl = NULL; remoteServer = NULL;

            if (jitMode == JitModeJS)
                [self activateUniversalJitSyncForPid:pid adapter:adapter handshake:handshake];
            else if (jitMode == JitModeNative)
                [self activateGodlyNativeJitSyncForPid:pid adapter:adapter handshake:handshake];
            else { rsd_handshake_free(handshake); adapter_free(adapter); }

            NSString *mode = (jitMode == JitModeJS) ? @"JS" : @"God-Speed";
            safeCompletion(YES, [NSString stringWithFormat:@"Launched with JIT (%@, PID: %llu).", mode, pid]);
        } else {
            process_control_free(procControl); remote_server_free(remoteServer);
            rsd_handshake_free(handshake); adapter_free(adapter);
            safeCompletion(YES, [NSString stringWithFormat:@"Launched (PID: %llu).", pid]);
        }
    });
}

- (void)activateGodlyNativeJitSyncForPid:(uint64_t)pid
                                  adapter:(struct AdapterHandle *)adapter
                                handshake:(struct RsdHandshakeHandle *)handshake
{
    NSLog(@"[Omega-God] Rev.5 session start (PID: %llu)", pid);

    struct DebugProxyHandle *proxy = NULL;
    {
        struct IdeviceFfiError *e = debug_proxy_connect_rsd(adapter, handshake, &proxy);
        if (!e) { adapter = NULL; handshake = NULL; }
        else {
            NSLog(@"[Omega-God] connect failed: %s", omegaSafeErrCString(e));
            idevice_error_free(e); rsd_handshake_free(handshake); adapter_free(adapter); return;
        }
    }

    char *pktBuf = (char *)malloc(kPktBufSize);
    if (!pktBuf) {
        NSLog(@"[Omega-God] malloc failed");
        debug_proxy_free(proxy); rsd_handshake_free(handshake); adapter_free(adapter); return;
    }

    OmegaSession s = { .proxy = proxy, .pktBuf = pktBuf, .pktBufSize = kPktBufSize, .noAck = NO };

    omega_tune_socket(proxy);

    { char *r = omegaSend(&s, "vAttach;%llx", pid); if (r) free(r); }

    omegaNegotiate(&s);

    PageStore *ps = pagestore_get();
    if (!ps) {
        NSLog(@"[Omega-God] pagestore alloc failed");
        free(s.pktBuf); debug_proxy_free(proxy);
        rsd_handshake_free(handshake); adapter_free(adapter); return;
    }
    memset(ps, 0, sizeof(PageStore));

    RegSnap *regSnap = regsnap_get();
    if (regSnap) memset(regSnap, 0, sizeof(RegSnap));

    JSContext *jsCtx = [[JSContext alloc] init];
    jsCtx[@"log"] = ^(NSString *m) { NSLog(@"[Omega Script] %@", m); };

    BOOL detached = NO;

    DeferredQueue dq = { .count = 0 };

    char lastTid[64] = { 0 };

    while (!detached) {
        char *resp;

        if (s.noAck) {
            dq_flush(&dq, &s);
            if (lastTid[0]) {
                omegaSendFmt(&s, "vCont;c:%s", lastTid);
            } else {
                omegaSendFmt(&s, "vCont;c");
            }
            resp = omegaReadStop(&s);
        } else {
            if (lastTid[0]) {
                resp = omegaSend(&s, "vCont;c:%s", lastTid);
            } else {
                resp = omegaSend(&s, "vCont;c");
            }
        }

        if (!resp) { NSLog(@"[Omega-God] Connection lost."); break; }

        const size_t respLen = strnlen(resp, kPktBufSize);

        if (respLen > 0 && (resp[0] == 'W' || resp[0] == 'X')) {
            NSLog(@"[Omega-God] Process exited (%c).", resp[0]);
            free(resp); detached = YES; break;
        }

        const BOOL isT05 = (respLen >= 3 &&
                            resp[0] == 'T' &&
                            resp[1] == '0' &&
                            resp[2] == '5');

        GodState st = {0};
        scanStopPkt(resp, respLen, &st);

        if ((st.foundMask & REG_FOUND_PC) == 0) {

            if (regSnap && regSnap->valid && regSnap->pc != 0) {
                st.pc = regSnap->pc;
                if ((st.foundMask & REG_FOUND_X0)  == 0) st.x0  = regSnap->x0;
                if ((st.foundMask & REG_FOUND_X1)  == 0) st.x1  = regSnap->x1;
                if ((st.foundMask & REG_FOUND_X16) == 0) st.x16 = regSnap->x16;
            } else {
                uint64_t fetchedPC = 0;
                if (omegaFetchPC(&s, &fetchedPC)) {
                    st.pc = fetchedPC;

                    if (regSnap) { regSnap->pc = fetchedPC; regSnap->valid = YES; }
                }
            }
        }

        if (regSnap && st.foundMask) {
            if (st.foundMask & REG_FOUND_PC)  regSnap->pc  = st.pc;
            if (st.foundMask & REG_FOUND_X0)  regSnap->x0  = st.x0;
            if (st.foundMask & REG_FOUND_X1)  regSnap->x1  = st.x1;
            if (st.foundMask & REG_FOUND_X16) regSnap->x16 = st.x16;
            regSnap->valid = YES;
        }

        if (!st.tid[0] || st.pc == 0) { free(resp); continue; }

        if (st.tid[0]) {
            strlcpy(lastTid, st.tid, sizeof(lastTid));
        }

        const uint32_t *instrPtr = pcache_lookup(ps, st.pc);
        if (!instrPtr) instrPtr = pcache_load(ps, &s, st.pc);
        if (!instrPtr) { free(resp); continue; }
        const uint32_t instr = *instrPtr;

        if (isT05 && (instr & kArm64BrkMask) == kArm64BrkPattern) {
            const uint32_t imm = (instr >> 5) & 0xFFFF;

            const uint64_t nextPC = st.pc + 4;
            dq_push_Preg(&dq, &s, 0x20, nextPC, st.tid);
            if (regSnap) regSnap->pc = nextPC;

            if (imm == kBrkImmOmegaCtrl) {
                if (st.x16 == kOmegaCmdDetach) {

                    dq_flush(&dq, &s);
                    detached = YES;

                } else if (st.x16 == kOmegaCmdPrepare) {
                    uint64_t addr = st.x0;
                    if (!addr) {
                        char *xr = omegaSend(&s, "_M%llx,rx", st.x1);
                        if (xr) { addr = strtoull(xr, NULL, 16); free(xr); }
                    }
                    if (addr) {

                        dq_flush(&dq, &s);
                        omegaWriteMemory(&s, addr, (uint32_t)st.x1, kFillHi, kFillLo);

                        dq_push_Preg(&dq, &s, 0x00, addr, st.tid);
                    }
                }

            } else if (imm == kBrkImmJsEval) {
                dq_flush(&dq, &s);
                char *mr = omegaSend(&s, "m%llx,%llx", st.x0, st.x1);
                if (mr) {
                    @autoreleasepool {
                        const size_t mrLen = strnlen(mr, kPktBufSize);
                        const size_t sl    = mrLen / 2;
                        char *sc = (char *)malloc(sl + 1);
                        if (sc) {
                            for (size_t k = 0; k < sl; k++)
                                sc[k] = (char)hexPairToByte(mr[k*2], mr[k*2+1]);
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

        } else if (!isT05 &&
                   resp[0] == 'T' && respLen >= 3 &&
                   isxdigit((unsigned char)resp[1]) &&
                   isxdigit((unsigned char)resp[2]) &&
                   st.tid[0]) {

            dq_flush(&dq, &s);
            char *vr = omegaSend(&s, "vCont;S%c%c:%s", resp[1], resp[2], st.tid);
            if (vr) free(vr);
        }

        free(resp);
    }

    dq_flush(&dq, &s);
    { char *r = omegaSend(&s, "vCont;c"); if (r) free(r); }
    { char *r = omegaSend(&s, "D");       if (r) free(r); }

    free(s.pktBuf);
    debug_proxy_free(proxy);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    NSLog(@"[Omega-God] Rev.5 engine shut down cleanly.");
}

- (void)activateUniversalJitSyncForPid:(uint64_t)pid
                                adapter:(struct AdapterHandle *)adapter
                              handshake:(struct RsdHandshakeHandle *)handshake
{
    struct DebugProxyHandle *proxy = NULL;
    {
        struct IdeviceFfiError *e = debug_proxy_connect_rsd(adapter, handshake, &proxy);
        if (!e) { adapter = NULL; handshake = NULL; }
        else {
            NSLog(@"[JIT-JS] connect failed: %s", omegaSafeErrCString(e));
            idevice_error_free(e); rsd_handshake_free(handshake); adapter_free(adapter); return;
        }
    }

    omega_tune_socket(proxy);

    {
        char *buf = prepbuf_get();
        if (buf) {
            OmegaSession setup = { .proxy = proxy, .pktBuf = buf,
                                   .pktBufSize = kPktBufSize, .noAck = NO };
            char *r = omegaSend(&setup, "vAttach;%llx", pid);
            if (r) free(r);
            else NSLog(@"[JIT-JS] vAttach no response — continuing.");
            omegaNegotiate(&setup);
        }
    }

    __block struct DebugProxyHandle *capturedProxy = proxy;
    JSContext *context = [[JSContext alloc] init];

    context[@"get_pid"] = ^uint64_t { return pid; };

    context[@"send_command"] = ^NSString *(NSString *cmdStr) {
        if (!cmdStr.length) return nil;
        struct DebugserverCommandHandle *cmd =
            debugserver_command_new([cmdStr UTF8String], NULL, 0);
        char *respRaw = NULL;
        struct IdeviceFfiError *e = debug_proxy_send_command(capturedProxy, cmd, &respRaw);
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
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [docsDir stringByAppendingPathComponent:filename];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            path = [[NSBundle mainBundle]
                    pathForResource:[filename stringByDeletingPathExtension]
                             ofType:[filename pathExtension]];
        }
        if (!path) return [NSString stringWithFormat:@"ERROR: not found: %@", filename];
        NSError *e = nil;
        NSString *content = [NSString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding error:&e];
        if (!content) return [NSString stringWithFormat:@"ERROR: %@", e.localizedDescription];
        [[JSContext currentContext] evaluateScript:content];
        return @"OK";
    };

    context[@"prepare_memory_region"] = ^NSString *(uint64_t startAddr, uint64_t jitPagesSize) {
        char *buf = prepbuf_get();
        if (!buf) return @"ERROR_ALLOC";
        OmegaSession os = { .proxy = capturedProxy, .pktBuf = buf,
                            .pktBufSize = kPktBufSize, .noAck = NO };
        BOOL ok = omegaWriteMemory(&os, startAddr, (uint32_t)jitPagesSize, kFillHi, kFillLo);
        return ok ? @"OK" : @"ERROR_SEND";
    };

    context[@"log"] = ^(NSString *msg) { NSLog(@"[JIT Script] %@", msg); };

    NSString *script = nil;
    {
        NSString *docsDir =
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [docsDir stringByAppendingPathComponent:@"universal.js"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (!script) {
            NSString *bp = [[NSBundle mainBundle] pathForResource:@"universal" ofType:@"js"];
            if (bp) script = [NSString stringWithContentsOfFile:bp encoding:NSUTF8StringEncoding error:nil];
        }
        if (!script) script = kUniversalJitScript;
    }

    [context evaluateScript:script];

    context = nil;
    capturedProxy = NULL;
    debug_proxy_free(proxy);
    rsd_handshake_free(handshake);
    adapter_free(adapter);

    NSLog(@"[JIT-JS] Session complete.");
}

@end
