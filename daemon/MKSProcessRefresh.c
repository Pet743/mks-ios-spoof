#include "MKSProcessRefresh.h"
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int target(const char *name) {
    static const char *names[] = {
        "AppStore", "akd", "accountsd", "amsaccountsd", "appstored",
        // lockdownd owns paired USB sessions and is deliberately left running.
        "itunesstored", "itunescloudd", "identityservicesd",
        "adid", "fairplayd.H2", "storebookkeeperd", "storekitd", NULL
    };
    for (unsigned i=0; names[i]; i++) if (!strcmp(name,names[i])) return 1;
    return 0;
}

typedef struct { pid_t pid; char name[64]; int finished, signaled; } Process;

// A disappeared PID or a reused PID with another name means the original
// process has ended. Never signal a PID after its name changes.
static int alive(const MKSProcessOps *ops, const Process *p) {
    if (ops->signal(ops->context,p->pid,0)) return errno==ESRCH ? 0 : -1;
    char name[64]={0};
    if (ops->name(ops->context,p->pid,name,sizeof(name))<=0) {
        if (ops->signal(ops->context,p->pid,0) && errno==ESRCH) return 0;
        return 2; // A terminating process may remain visible before it is reaped.
    }
    return !strcmp(name,p->name);
}

int MKSRefreshWithOps(const MKSProcessOps *ops, MKSRefreshResult *result) {
    memset(result,0,sizeof(*result));
    int count=ops->list(ops->context,NULL,0);
    if (count<0 || count>65536) { result->errors++; return -1; }
    pid_t *pids=NULL; size_t capacity=0;
    for (unsigned attempt=0; attempt<3; attempt++) {
        capacity=(size_t)count+64;
        free(pids); pids=calloc(capacity,sizeof(*pids));
        if (!pids) { result->errors++; return -1; }
        count=ops->list(ops->context,pids,capacity);
        if (count<0 || count>65536) break;
        if ((size_t)count<capacity) break;
    }
    if (count<0 || (size_t)count>=capacity) {
        free(pids); result->errors++; return -1;
    }
    Process *processes=calloc((size_t)count+1,sizeof(*processes));
    if (!processes) { free(pids); result->errors++; return -1; }
    for (int i=0; i<count; i++) {
        if (pids[i]<=1 || pids[i]==getpid()) continue;
        char name[64]={0};
        int found=0,gone=0;
        for (unsigned attempt=0;attempt<=8;attempt++) {
            if (ops->name(ops->context,pids[i],name,sizeof(name))>0) { found=1;break; }
            if (ops->signal(ops->context,pids[i],0) && errno==ESRCH) { gone=1;break; }
            if (attempt<8) ops->pause(ops->context,50);
        }
        if (!found) {
            if (!gone) result->errors++;
            continue;
        }
        if (!target(name)) continue;
        Process *p=&processes[result->matched++];p->pid=pids[i];
        memcpy(p->name,name,sizeof(p->name));p->name[sizeof(p->name)-1]=0;
    }
    free(pids);
    // A failed inventory must not be reported as a successful refresh.
    if (result->errors) { free(processes); return -1; }
    for (unsigned attempt=0; attempt<=60; attempt++) {
        unsigned pending=0;
        for (unsigned i=0; i<result->matched; i++) {
            Process *p=&processes[i];if (p->finished) continue;
            int state=alive(ops,p);
            if (state==0) {
                p->finished=1;result->finished++;
                continue;
            }
            if (state<0) { p->finished=1;result->errors++;continue; }
            // An unreadable, still-live PID is pending, never permission to kill.
            if (state==1 && !p->signaled) {
                if (!ops->signal(ops->context,p->pid,SIGKILL)) { result->signaled++;p->signaled=1; }
                else if (errno==ESRCH) { p->finished=1;result->finished++;continue; }
                else { p->finished=1;result->errors++;continue; }
            }
            pending++;
        }
        if (!pending) break;
        if (attempt==60) { result->timedOut=pending; break; }
        ops->pause(ops->context,50);
    }
    free(processes);
    return result->errors || result->timedOut ? -1 : 0;
}

#ifndef MKS_REFRESH_TEST
// iPhoneOS SDK exports libproc but does not ship its public macOS header.
extern int proc_listallpids(void *,int);
extern int proc_name(int,void *,unsigned int);
static int nativeList(void *ctx,pid_t *pids,size_t capacity) {
    (void)ctx;return proc_listallpids(pids,(int)(capacity*sizeof(*pids)));
}
static int nativeName(void *ctx,pid_t pid,char *name,size_t size) {
    (void)ctx;return proc_name(pid,name,(unsigned int)size);
}
static int nativeSignal(void *ctx,pid_t pid,int sig) { (void)ctx;return kill(pid,sig); }
static void nativePause(void *ctx,unsigned ms) { (void)ctx;usleep(ms*1000); }
int MKSRefreshIdentityProcesses(MKSRefreshResult *result) {
    const MKSProcessOps ops={NULL,nativeList,nativeName,nativeSignal,nativePause};
    return MKSRefreshWithOps(&ops,result);
}
#endif
