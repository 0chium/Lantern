// TEMPORARY diagnostic branch only. Never include in a production release.
#pragma once
#include <atomic>
#include <mach/mach_time.h>
#include <pthread.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <dispatch/dispatch.h>
#include <notify.h>
#include <string.h>

static const char *LDExportName = "com.ochium.lantern.diagnostic.build51.state.export.v1";
struct LDRecord { uint64_t ticks, thread, interaction, receiver, event, a, b, c, d; };
static LDRecord LDRecords[4096], LDSnapshot[4096];
static uintptr_t LDReceivers[128];
static size_t LDCount, LDReceiverCount;
static std::atomic_flag LDLock = ATOMIC_FLAG_INIT;
static std::atomic<uint64_t> LDDropped(0), LDActive(0), LDLast(0), LDInteractions(0);
static thread_local uint64_t LDInteraction;
static uint64_t LDSession;
static mach_timebase_info_data_t LDTimebase;
static std::atomic<bool> LDEnabled(false), LDExporting(false), LDExportInterrupted(false);
static inline uint64_t LDBits(double value) { uint64_t bits; memcpy(&bits,&value,8); return bits; }
static inline uint32_t LDFloatBits(float value) { uint32_t bits; memcpy(&bits,&value,4); return bits; }
static void LDLog(uint64_t event, const void *receiver, uint64_t a=0, uint64_t b=0, uint64_t c=0, uint64_t d=0)
{
    if (!LDEnabled.load()) return;
    if(LDExporting.load()) {LDExportInterrupted.store(true);LDDropped.fetch_add(1);return;}
    uint64_t now=mach_continuous_time(), tid=0;
    LDLast.store(now, std::memory_order_relaxed);
    if (LDLock.test_and_set(std::memory_order_acquire)) { LDDropped.fetch_add(1); return; }
    if(LDExporting.load()) {LDExportInterrupted.store(true);LDDropped.fetch_add(1);LDLock.clear(std::memory_order_release);return;}
    if (LDCount==4096) { LDDropped.fetch_add(1); LDLock.clear(std::memory_order_release); return; }
    uint64_t identity=0;
    if (receiver) {
        size_t i=0; for (;i<LDReceiverCount;i++) if (LDReceivers[i]==(uintptr_t)receiver) break;
        if (i==LDReceiverCount && i<128) LDReceivers[LDReceiverCount++]=(uintptr_t)receiver;
        if (i<128) identity=i+1; else LDDropped.fetch_add(1);
    }
    pthread_threadid_np(NULL,&tid);
    LDRecords[LDCount++]={now,tid,LDInteraction,identity,event,a,b,c,d};
    LDLock.clear(std::memory_order_release);
}
struct LDGuard {
    bool enabled; uint64_t prior;
    LDGuard(bool interaction=false):enabled(LDEnabled),prior(LDInteraction) {
        if(enabled) { if(LDExporting.load()) LDExportInterrupted.store(true); LDActive.fetch_add(1); if(interaction) LDInteraction=LDInteractions.fetch_add(1)+1; }
    }
    ~LDGuard() { if(enabled) { LDLast.store(mach_continuous_time()); LDInteraction=prior; LDActive.fetch_sub(1); } }
};
static bool LDWrite(int fd,const char *s,size_t n)
{
    while(n) { ssize_t k=write(fd,s,n); if(k<0 && errno==EINTR) continue; if(k<=0) return false; s+=k;n-=k; } return true;
}
struct LDExportScope { ~LDExportScope(){LDExporting.store(false);} };
static void LDExport(void)
{
    // No retry, timers or flashlight operations. User requests only after quiet.
    uint64_t now=mach_continuous_time(),last=LDLast.load();
    if(LDActive.load() || (double)(now-last)*LDTimebase.numer/LDTimebase.denom<2000000000.0) return;
    if(LDLock.test_and_set(std::memory_order_acquire)) return;
    if(LDActive.load()) { LDLock.clear(std::memory_order_release);return; }
    LDExportInterrupted.store(false);LDExporting.store(true);LDExportScope exportScope;
    size_t count=LDCount; memcpy(LDSnapshot,LDRecords,count*sizeof(LDRecord));
    uint64_t dropped=LDDropped.load();
    LDLock.clear(std::memory_order_release);
    char directory[128]; snprintf(directory,sizeof(directory),"/var/tmp/LanternStateDiagnostic-%u",(unsigned)getuid());
    if(mkdir(directory,0700)<0 && errno!=EEXIST) return;
    int dir=open(directory,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); if(dir<0) return;
    struct stat st; if(fstat(dir,&st)<0 || !S_ISDIR(st.st_mode) || st.st_uid!=getuid() || (st.st_mode&0777)!=0700) {close(dir);return;}
    char name[128];snprintf(name,sizeof(name),"%s-%d-%016llx.csv",LD_PROCESS,getpid(),(unsigned long long)LDSession);
    int fd=openat(dir,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);close(dir);if(fd<0)return;
    // Exclusive creation; never overwrite evidence, follow symlinks or change existing permissions.
    if(fstat(fd,&st)<0 || st.st_uid!=getuid() || !S_ISREG(st.st_mode) || st.st_nlink!=1 || fchmod(fd,0600)<0) {close(fd);return;}
    char line[512];bool ok=true;
    int n=snprintf(line,sizeof(line),"# schema=1 process=%s pid=%d uid=%u session=%016llx clock=mach_continuous_time numer=%u denom=%u exported_ticks=%llu events=%zu dropped=%llu\nsequence,ticks,thread,interaction,receiver,event,a,b,c,d\n",LD_PROCESS,getpid(),(unsigned)getuid(),(unsigned long long)LDSession,LDTimebase.numer,LDTimebase.denom,(unsigned long long)now,count,(unsigned long long)dropped);
    ok=n>0 && n<(int)sizeof(line) && LDWrite(fd,line,n);
    for(size_t i=0;ok && i<count;i++) {
        if(LDActive.load() || LDExportInterrupted.load()) {ok=false;break;}
        const LDRecord &r=LDSnapshot[i];
        n=snprintf(line,sizeof(line),"%zu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n",i+1,(unsigned long long)r.ticks,(unsigned long long)r.thread,(unsigned long long)r.interaction,(unsigned long long)r.receiver,(unsigned long long)r.event,(unsigned long long)r.a,(unsigned long long)r.b,(unsigned long long)r.c,(unsigned long long)r.d);
        ok=n>0 && n<(int)sizeof(line) && LDWrite(fd,line,n);
    }
    if(ok && !LDActive.load() && !LDExportInterrupted.load()) {n=snprintf(line,sizeof(line),"# complete events=%zu dropped_at_end=%llu\n",count,(unsigned long long)LDDropped.load());LDWrite(fd,line,n);}
    close(fd); // Missing footer is an incomplete export, never usable as a complete trace.
}
static void LDInit(void)
{
    if(mach_timebase_info(&LDTimebase)!=KERN_SUCCESS || !LDTimebase.denom) return;
    arc4random_buf(&LDSession,sizeof(LDSession));
    dispatch_queue_t q=dispatch_queue_create("com.ochium.lantern.diagnostic.export",DISPATCH_QUEUE_SERIAL);
    if(!q)return;
    int token=-1;
    if(notify_register_dispatch(LDExportName,&token,q,^(int){LDExport();})!=NOTIFY_STATUS_OK)return;
    LDEnabled=true;
    LDLog(1,NULL);
}
