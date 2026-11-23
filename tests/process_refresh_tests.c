#include "../daemon/MKSProcessRefresh.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

typedef struct { pid_t pid; const char *name; int gone; } Entry;
typedef struct {
    Entry entries[8]; int count, listError, unreadable, denied, survives, reuse, transientName, terminating;
    unsigned kills, pauses; pid_t killed[8];
} Fixture;
static int checks,failures;
#define CHECK(c,label) do { checks++;if (!(c)) { failures++;printf("FAIL %s\n",label); } } while(0)
static Entry *entry(Fixture *f,pid_t pid) {
    for (int i=0;i<f->count;i++) if (f->entries[i].pid==pid) return &f->entries[i];
    return NULL;
}
static int list(void *ctx,pid_t *pids,size_t capacity) {
    Fixture *f=ctx;if (f->listError) return -1;
    for (int i=0;pids && i<f->count && (size_t)i<capacity;i++) pids[i]=f->entries[i].pid;
    return f->count;
}
static int name(void *ctx,pid_t pid,char *out,size_t size) {
    Fixture *f=ctx;Entry *e=entry(f,pid);
    if (f->transientName>0) { f->transientName--;errno=ESRCH;return 0; }
    if (f->terminating && f->kills && f->pauses<2) { errno=ESRCH;return 0; }
    if (!e || e->gone || f->unreadable) { errno=e && !e->gone?EACCES:ESRCH;return 0; }
    snprintf(out,size,"%s",e->name);return (int)strlen(out);
}
static int sendSignal(void *ctx,pid_t pid,int sig) {
    Fixture *f=ctx;Entry *e=entry(f,pid);
    if (!e || e->gone) { errno=ESRCH;return -1; }
    if (!sig) {
        if (f->reuse) { e->name="unrelated";f->reuse=0; }
        return 0;
    }
    if (f->denied) { errno=EPERM;return -1; }
    f->killed[f->kills++]=pid;
    if (!f->survives) e->gone=1;
    return 0;
}
static void pause(void *ctx,unsigned ms) { Fixture *f=ctx;(void)ms;f->pauses++;if(f->terminating && f->kills && f->pauses>=2)f->entries[0].gone=1; }
static int run(Fixture *f,MKSRefreshResult *r) {
    MKSProcessOps ops={f,list,name,sendSignal,pause};return MKSRefreshWithOps(&ops,r);
}
int main(void) {
    MKSRefreshResult r;
    Fixture all={.entries={{101,"akd",0},{102,"AppStore",0},{103,"fairplayd.H2",0},{104,"amsaccountsd",0}},.count=4};
    CHECK(run(&all,&r)==0,"refresh completes");
    CHECK(r.matched==4 && r.signaled==4 && r.finished==4,"every original target exits");
    CHECK(!r.errors && !r.timedOut,"truthful successful result");
    Fixture exact={.entries={{101,"akd-helper",0},{102,"notaccountsd",0},{1,"akd",0},{103,"mksd",0}},.count=4};
    CHECK(run(&exact,&r)==0 && exact.kills==0,"only exact names, never init or daemon");
    Fixture absent={.entries={{101,"unrelated",0}},.count=1};
    CHECK(run(&absent,&r)==0 && r.matched==0,"optional absent services succeed");
    Fixture lost={.entries={{101,"akd",1}},.count=1};
    CHECK(run(&lost,&r)==0 && !lost.kills,"disappeared inventory PID is harmless");
    Fixture replaced={.entries={{101,"akd",0}},.count=1,.reuse=1};
    CHECK(run(&replaced,&r)==0 && !replaced.kills && r.finished==1,"reused PID is not killed");
    Fixture blocked={.entries={{101,"akd",0}},.count=1,.denied=1};
    CHECK(run(&blocked,&r)==-1 && r.errors>0,"signal denial is failure");
    Fixture stuck={.entries={{101,"accountsd",0}},.count=1,.survives=1};
    CHECK(run(&stuck,&r)==-1 && r.timedOut==1,"surviving process cannot pass");
    CHECK(stuck.pauses==60 && stuck.kills==1,"bounded wait and one signal per original PID");
    Fixture broken={.entries={{101,"akd",0}},.count=1,.listError=1};
    CHECK(run(&broken,&r)==-1 && broken.kills==0,"failed inventory signals nothing");
    Fixture unreadable={.entries={{101,"akd",0}},.count=1,.unreadable=1};
    CHECK(run(&unreadable,&r)==-1 && unreadable.kills==0,"unreadable live PID cannot be certified");
    Fixture transient={.entries={{101,"akd",0}},.count=1,.transientName=1};
    CHECK(run(&transient,&r)==0 && transient.kills==1,"inventory retries a transient unreadable PID");
    Fixture terminating={.entries={{101,"akd",0}},.count=1,.terminating=1,.survives=1};
    CHECK(run(&terminating,&r)==0 && r.finished==1,"a terminating PID is checked until it disappears");
    printf("PROCESS_REFRESH checks=%d failures=%d; host signals=0\n",checks,failures);
    return failures?1:0;
}
