// Private passive recorder. No libc, Apple APIs, pointers, I/O or flashlight calls.
#pragma once
typedef unsigned long long LDU64;
static_assert(sizeof(LDU64)==8, "64-bit records required");
static_assert(__atomic_always_lock_free(8, 0), "diagnostic counters must be lock-free");
enum LDEvent : LDU64 {
    LD_ENTRY=1, LD_INIT_STAGE=2, LD_INIT_FAILURE=3, LD_INIT_READY=4,
    LD_DIAG_READY=5, LD_DIAG_ERROR=6, LD_HOOK_REQUEST=7, LD_HOOK_ORIGINAL=8,
    LD_SYMBOL_FOUND=9, LD_MODE_RECEIVED=10, LD_UI_INTENT=11, LD_UI_SET=12,
    LD_UI_POST=13, LD_UI_SAME=14, LD_UI_TYPE_FAILURE=15, LD_SLIDER_FORWARD=16
};
enum LDReason : LDU64 { LD_ZERO=0, LD_WHITE=1, LD_PATTERN=2, LD_TRANSFORM=3, LD_NO_ORIGINAL=4 };
struct LDRecord { LDU64 ticks,event,a,b,c,d; };
struct LDHardware {
    LDU64 id,begin,end,arg1,input,output,warm,reason,result,returned;
};
struct LDCore {
    alignas(8) LDU64 entered,firstFailure,diagError,symbolFound,hookRequested,
        originalAvailable,executionObserved,receiptObserved,attemptObserved,returnObserved;
    alignas(8) LDU64 deadline,capture,armedOnce,dropped,filtered,active,last,admissions;
    unsigned char lock,freeze;
    unsigned initCount,detailCount;
    LDRecord init[32],detail[256];
    LDHardware hardware[64];
    alignas(8) LDU64 captureStart,captureEnd;
};
static inline LDU64 LDRead(const LDU64 *p) { return __atomic_load_n(p,__ATOMIC_ACQUIRE); }
static inline void LDStore(LDU64 *p,LDU64 v) { __atomic_store_n(p,v,__ATOMIC_RELEASE); }
static inline bool LDTryLock(LDCore *s) { return !__atomic_test_and_set(&s->lock,__ATOMIC_ACQUIRE); }
static inline void LDUnlock(LDCore *s) { __atomic_clear(&s->lock,__ATOMIC_RELEASE); }
static inline bool LDFrozen(LDCore *s) { return __atomic_load_n(&s->freeze,__ATOMIC_SEQ_CST); }
static inline void LDDrop(LDCore *s) { __atomic_fetch_add(&s->dropped,1,__ATOMIC_RELAXED); }
static inline void LDCoreInit(LDCore *s,LDU64 now,LDU64 event,LDU64 a=0,LDU64 b=0,LDU64 c=0,LDU64 d=0) {
    if(event==LD_ENTRY) LDStore(&s->entered,1);
    if(event==LD_INIT_FAILURE) { LDU64 zero=0; __atomic_compare_exchange_n(&s->firstFailure,&zero,a,false,__ATOMIC_RELEASE,__ATOMIC_RELAXED); }
    if(event==LD_DIAG_ERROR) LDStore(&s->diagError,a);
    if(event==LD_SYMBOL_FOUND) LDStore(&s->symbolFound,1);
    if(event==LD_HOOK_REQUEST) LDStore(&s->hookRequested,1);
    if(event==LD_HOOK_ORIGINAL) LDStore(&s->originalAvailable,a);
    if(LDFrozen(s)||!LDTryLock(s)) { LDDrop(s); return; }
    if(LDFrozen(s)||s->initCount==32) LDDrop(s);
    else s->init[s->initCount++]={now,event,a,b,c,d};
    LDUnlock(s);
}
static inline bool LDCoreArmed(LDCore *s,LDU64 now) {
    LDU64 end=LDRead(&s->deadline); return end && now<end;
}
static inline void LDCoreLog(LDCore *s,LDU64 now,LDU64 event,LDU64 a=0,LDU64 b=0,LDU64 c=0,LDU64 d=0) {
    if(event==LD_MODE_RECEIVED) LDStore(&s->receiptObserved,1);
    if(!LDCoreArmed(s,now)) return;
    LDStore(&s->last,now);
    if(LDFrozen(s)||!LDTryLock(s)) { LDDrop(s); return; }
    if(LDFrozen(s)||s->detailCount==256) LDDrop(s);
    else s->detail[s->detailCount++]={now,event,a,b,c,d};
    LDUnlock(s);
}
// One window per epoch is deliberately stricter than the design's upper bounds.
static inline bool LDCoreArm(LDCore *s,LDU64 now,LDU64 duration,LDU64 capture) {
    if(!capture||!duration||now>~0ULL-duration) return false;
    LDU64 zero=0;
    if(!__atomic_compare_exchange_n(&s->armedOnce,&zero,1,false,__ATOMIC_ACQ_REL,__ATOMIC_RELAXED)) return false;
    LDStore(&s->capture,capture); LDStore(&s->captureStart,now); LDStore(&s->captureEnd,now+duration);
    LDStore(&s->deadline,now+duration); return true;
}
static inline void LDCoreStop(LDCore *s) { LDStore(&s->deadline,0); }
static inline LDHardware *LDCoreBegin(LDCore *s,LDU64 now,LDU64 arg1,LDU64 levels) {
    // Sequentially ordered admission/freeze handshake is required on arm64.
    __atomic_fetch_add(&s->active,1,__ATOMIC_SEQ_CST);
    LDStore(&s->executionObserved,1); LDStore(&s->last,now);
    if(!LDCoreArmed(s,now)||LDFrozen(s)) return 0;
    LDU64 i=__atomic_fetch_add(&s->admissions,1,__ATOMIC_RELAXED);
    if(i>=64) { __atomic_fetch_add(&s->filtered,1,__ATOMIC_RELAXED); return 0; }
    LDHardware *r=&s->hardware[i];
    *r={i+1,now,0,arg1,levels,levels,~0ULL,LD_NO_ORIGINAL,0,0}; return r;
}
static inline void LDCoreAttempt(LDCore *s,LDHardware *r,LDU64 warm,LDU64 output,LDU64 reason) {
    if(reason==LD_TRANSFORM) LDStore(&s->attemptObserved,1);
    if(r) { r->warm=warm; r->output=output; r->reason=reason; }
}
static inline void LDCoreReturn(LDCore *s,LDHardware *r,LDU64 now,LDU64 result) {
    LDStore(&s->returnObserved,1);
    if(r) { r->result=result; r->end=now; r->returned=1; }
}
static inline void LDCoreEnd(LDCore *s,LDU64 now) {
    LDStore(&s->last,now); __atomic_fetch_sub(&s->active,1,__ATOMIC_RELEASE);
}
// Freeze + active count prevent copying slots while a call writes them.
// Producers never wait. Any post-cutoff activity is outside this snapshot.
static inline bool LDCoreFreeze(LDCore *s) {
    if(!LDTryLock(s)) return false;
    __atomic_store_n(&s->freeze,1,__ATOMIC_SEQ_CST);
    if(__atomic_load_n(&s->active,__ATOMIC_SEQ_CST)) { __atomic_store_n(&s->freeze,0,__ATOMIC_SEQ_CST); LDUnlock(s); return false; }
    return true; // caller copies only plain record arrays, then unfreezes
}
static inline void LDCoreUnfreeze(LDCore *s) { __atomic_store_n(&s->freeze,0,__ATOMIC_SEQ_CST); LDUnlock(s); }
static_assert(sizeof(LDCore)*2<128*1024, "recorder and snapshot memory cap");
