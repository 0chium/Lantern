// Private opt-in diagnostic adapter. Never import into the published source.
#pragma once
#include "LanternDiagnosticCore.h"
#include "LanternDiagnosticBuild.h"
#include <stdint.h>
#include <mach/mach_time.h>
#include <dispatch/dispatch.h>
#include <notify.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static LDCore LDState;
static mach_timebase_info_data_t LDTimebase;
static LDU64 LDEpoch,LDEntryTicks;
static int LDPid; static unsigned LDUid;
static dispatch_queue_t LDQueue;
static unsigned LDExportAttempts;
static LDU64 LDLastRequest;
static char LDActualProcess[64],LDModel[64],LDOSBuild[64];
static inline LDU64 LDNow() { return mach_continuous_time(); }
static void LDInitRecord(LDU64 e,LDU64 a=0,LDU64 b=0,LDU64 c=0,LDU64 d=0) { LDCoreInit(&LDState,LDNow(),e,a,b,c,d); }
static void LDLog(LDU64 e,LDU64 a=0,LDU64 b=0,LDU64 c=0,LDU64 d=0) { LDCoreLog(&LDState,LDNow(),e,a,b,c,d); }
static inline LDU64 LDHash(const char *s) { LDU64 h=14695981039346656037ULL; if(s) for(unsigned i=0;s[i]&&i<128;i++){h^=(unsigned char)s[i];h*=1099511628211ULL;} return s?h:0; }
struct LDCall {
    LDHardware *record;
    LDCall(unsigned arg1,unsigned levels):record(LDCoreBegin(&LDState,LDNow(),arg1,levels)) {}
    void attempt(LDU64 warm,unsigned output,LDReason reason) { LDCoreAttempt(&LDState,record,warm,output,reason); }
    void returned(LDU64 result) { LDCoreReturn(&LDState,record,LDNow(),result); }
    ~LDCall() { LDCoreEnd(&LDState,LDNow()); }
};
static LDU64 LDTicks(unsigned seconds) { return (LDU64)seconds*1000000000ULL*LDTimebase.denom/LDTimebase.numer; }
static void LDSanitize(char *s) { for(unsigned i=0;s[i];i++) if(!((s[i]>='a'&&s[i]<='z')||(s[i]>='A'&&s[i]<='Z')||(s[i]>='0'&&s[i]<='9')||s[i]=='.'||s[i]=='-'||s[i]=='_'))s[i]='_'; }
static void LDMetadata(char *out,const char *key) { size_t n=64; if(sysctlbyname(key,out,&n,0,0)!=0||n>64)strcpy(out,"unavailable");out[63]=0;LDSanitize(out); }
static bool LDDirValid(int fd,bool sticky=false) {
    struct stat s; return fd>=0&&fstat(fd,&s)==0&&S_ISDIR(s.st_mode)&&s.st_uid==0&&(!(s.st_mode&0022)||(sticky&&(s.st_mode&S_ISVTX)));
}
static int LDOpenDirectory() {
    int root=open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(!LDDirValid(root)) {if(root>=0)close(root);return -1;}
    int p=openat(root,"private",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(root);
    if(!LDDirValid(p)) {if(p>=0)close(p);return -1;}
    int v=openat(p,"var",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(p);
    if(!LDDirValid(v)) {if(v>=0)close(v);return -1;}
    int t=openat(v,"tmp",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(v);
    if(!LDDirValid(t,true)) {if(t>=0)close(t);return -1;}
    char name[96];snprintf(name,sizeof(name),"LanternB51DiagS1-%u",LDUid);
    if(mkdirat(t,name,0700)<0&&errno!=EEXIST){close(t);return -1;}
    int d=openat(t,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);close(t);
    struct stat s;
    if(d<0||fstat(d,&s)<0||!S_ISDIR(s.st_mode)||s.st_uid!=LDUid||(s.st_mode&0777)!=0700){if(d>=0)close(d);return -1;}
    return d;
}
static bool LDWrite(int fd,const char *b,size_t n,size_t *total) {
    if(*total>65536||n>65536-*total)return false;
    unsigned interrupted=0;
    while(n){ssize_t w=write(fd,b,n);if(w<0&&errno==EINTR&&interrupted++<4)continue;if(w<=0)return false;*total+=(size_t)w;b+=w;n-=(size_t)w;}return true;
}
// Serial queue only. No files until an explicit request; no overwrites/cleanup.
static void LDExport() {
    LDU64 now=LDNow();
    if(LDExportAttempts>=2){LDInitRecord(LD_DIAG_ERROR,108);return;}
    if(LDLastRequest&&now-LDLastRequest<LDTicks(10)){LDInitRecord(LD_DIAG_ERROR,109);return;}
    LDLastRequest=now;++LDExportAttempts;
    if(LDRead(&LDState.active)||(now-LDRead(&LDState.last)<LDTicks(2))){LDInitRecord(LD_DIAG_ERROR,110);return;}
    if(!LDCoreFreeze(&LDState)){LDInitRecord(LD_DIAG_ERROR,111);return;}
    // Do not copy atomic members. Records are stable under freeze/active protocol.
    LDRecord init[32],detail[256];LDHardware hardware[64];
    unsigned ni=LDState.initCount,nd=LDState.detailCount;
    memcpy(init,LDState.init,sizeof(init));memcpy(detail,LDState.detail,sizeof(detail));memcpy(hardware,LDState.hardware,sizeof(hardware));
    LDU64 capture=LDRead(&LDState.capture),drop=LDRead(&LDState.dropped),filtered=LDRead(&LDState.filtered);
    LDU64 captureStart=LDRead(&LDState.captureStart),captureEnd=LDRead(&LDState.captureEnd);
    LDU64 flags[]={LDRead(&LDState.entered),LDRead(&LDState.firstFailure),LDRead(&LDState.diagError),LDRead(&LDState.symbolFound),LDRead(&LDState.hookRequested),LDRead(&LDState.originalAvailable),LDRead(&LDState.executionObserved),LDRead(&LDState.receiptObserved),LDRead(&LDState.attemptObserved),LDRead(&LDState.returnObserved)};
    LDU64 cutoff=LDNow(); // after freezing/copying; records cannot exceed this time
    LDCoreUnfreeze(&LDState);
    int d=LDOpenDirectory();if(d<0){LDInitRecord(LD_DIAG_ERROR,112,errno);return;}
    char name[128];snprintf(name,sizeof(name),"%s-%d-%016llx-%u.csv",LD_ROLE,LDPid,LDEpoch,LDExportAttempts);
    int fd=openat(d,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);close(d);
    struct stat st;
    if(fd<0){LDInitRecord(LD_DIAG_ERROR,113,errno);return;}
    if(fstat(fd,&st)<0||!S_ISREG(st.st_mode)||st.st_uid!=LDUid||st.st_nlink!=1||(st.st_mode&0777)!=0600){close(fd);LDInitRecord(LD_DIAG_ERROR,114);return;}
    char line[1024];size_t total=0;struct timeval tv;bool utc=gettimeofday(&tv,0)==0;
    LDU64 utcAnchor=LDNow();
    int n=snprintf(line,sizeof(line),"# schema=1 build=%s baseline=Build51 role=%s actual_process=%s pid=%d uid=%u epoch=%016llx capture=%016llx capture_start=%llu capture_end=%llu snapshot_ticks=%llu entry_ticks=%llu utc_unix=%lld utc_anchor_ticks=%llu clock=mach_continuous_time numer=%u denom=%u model=%s os_build=%s os_version=unavailable macho_uuid=unavailable color=unverified\n",LD_BUILD_ID,LD_ROLE,LDActualProcess,LDPid,LDUid,LDEpoch,capture,captureStart,captureEnd,cutoff,LDEntryTicks,utc?(long long)tv.tv_sec:-1LL,utcAnchor,LDTimebase.numer,LDTimebase.denom,LDModel,LDOSBuild);
    bool ok=n>0&&n<(int)sizeof(line)&&LDWrite(fd,line,(size_t)n,&total);
    n=snprintf(line,sizeof(line),"# flags entered=%llu first_failure=%llu diagnostic_error=%llu symbol_found=%llu hook_requested=%llu original_available=%llu execution_observed=%llu receipt_observed=%llu transformed_attempt_observed=%llu raw_return_observed=%llu dropped=%llu filtered_calls=%llu\n",flags[0],flags[1],flags[2],flags[3],flags[4],flags[5],flags[6],flags[7],flags[8],flags[9],drop,filtered);
    ok=ok&&n>0&&n<(int)sizeof(line)&&LDWrite(fd,line,(size_t)n,&total);
    for(unsigned bank=0;ok&&bank<2;bank++)for(unsigned i=0;ok&&i<(bank?nd:ni);i++){
        LDRecord r=bank?detail[i]:init[i];n=snprintf(line,sizeof(line),"event,%u,%u,%llu,%llu,%llu,%llu,%llu,%llu\n",bank,i,r.ticks,r.event,r.a,r.b,r.c,r.d);
        ok=n>0&&n<(int)sizeof(line)&&LDWrite(fd,line,(size_t)n,&total);
    }
    unsigned calls=0;
    for(unsigned i=0;ok&&i<64;i++)if(hardware[i].id){LDHardware r=hardware[i];++calls;
        n=snprintf(line,sizeof(line),"call,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu\n",r.id,r.begin,r.end,r.arg1,r.input,r.output,r.warm,r.reason,r.result,r.returned);
        ok=n>0&&n<(int)sizeof(line)&&LDWrite(fd,line,(size_t)n,&total);
    }
    if(ok){n=snprintf(line,sizeof(line),"# complete init=%u detail=%u calls=%u cutoff_ticks=%llu\n",ni,nd,calls,cutoff);ok=n>0&&n<(int)sizeof(line)&&LDWrite(fd,line,(size_t)n,&total);}
    int closed=close(fd);if(!ok||closed!=0)LDInitRecord(LD_DIAG_ERROR,115); // missing footer/close error is not confirmed success
}
static void LDSetup() {
    if(mach_timebase_info(&LDTimebase)!=KERN_SUCCESS||!LDTimebase.numer||!LDTimebase.denom||
       LDTimebase.denom>~0ULL/(60ULL*1000000000ULL)||!LDTicks(1)) {
        LDInitRecord(LD_DIAG_ERROR,101);return;
    }
    arc4random_buf(&LDEpoch,sizeof(LDEpoch));if(!LDEpoch)LDEpoch=LDEntryTicks^(LDU64)LDPid;
    const char *process=getprogname();snprintf(LDActualProcess,sizeof(LDActualProcess),"%s",process?process:"unavailable");LDSanitize(LDActualProcess);
    LDMetadata(LDModel,"hw.machine");LDMetadata(LDOSBuild,"kern.osversion");
    LDQueue=dispatch_queue_create("com.ochium.lantern.private.s1",DISPATCH_QUEUE_SERIAL);
    if(!LDQueue){LDInitRecord(LD_DIAG_ERROR,102);return;}
    int arm=-1,stop=-1,exportToken=-1;
    uint32_t a=notify_register_dispatch(LD_ARM_NAME,&arm,LDQueue,^(int token){
        uint64_t id=0;uint32_t status=notify_get_state(token,&id);
        if(status||!LDCoreArm(&LDState,LDNow(),LDTicks(60),id))LDInitRecord(LD_DIAG_ERROR,104,status);
    });
    uint32_t b=notify_register_dispatch(LD_STOP_NAME,&stop,LDQueue,^(int){LDCoreStop(&LDState);});
    uint32_t c=notify_register_dispatch(LD_EXPORT_NAME,&exportToken,LDQueue,^(int){LDExport();});
    if(a||b||c){if(arm>=0)notify_cancel(arm);if(stop>=0)notify_cancel(stop);if(exportToken>=0)notify_cancel(exportToken);LDInitRecord(LD_DIAG_ERROR,103,a,b,c);return;}
    LDInitRecord(LD_DIAG_READY);
}
static void LDComponentEntry() {
    LDStore(&LDState.entered,1); // earliest plain marker, even if later setup fails
    LDPid=getpid();LDUid=(unsigned)getuid();LDEntryTicks=LDNow();
    LDCoreInit(&LDState,LDEntryTicks,LD_ENTRY,(LDU64)LDPid,LDUid);
    // No private selectors, filesystem I/O or new services in the constructor.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{LDSetup();});
}
