#include "MKSProcessRefresh.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

typedef struct { int dead, kills, pauses; } Fixture;
static int list(void *context,pid_t *pids,size_t count) {
    (void)context;
    if (pids && count>=2) { pids[0]=40001;pids[1]=40002; }
    return 2;
}
static int name(void *context,pid_t pid,char *out,size_t size) {
    Fixture *f=context;
    if (pid==40001 && f->dead) { errno=ESRCH;return 0; }
    return snprintf(out,size,"%s",pid==40001?"storekitd":"storekitd-helper");
}
static int signalProcess(void *context,pid_t pid,int signal) {
    Fixture *f=context;
    if (pid==40001 && f->dead) { errno=ESRCH;return -1; }
    if (signal==SIGKILL) { f->kills++;if (pid==40001) f->dead=1; }
    return 0;
}
static void pauseProcess(void *context,unsigned milliseconds) {
    Fixture *f=context;(void)milliseconds;f->pauses++;
}
int main(void) {
    Fixture f={0};MKSRefreshResult result;
    MKSProcessOps ops={&f,list,name,signalProcess,pauseProcess};
    int rc=MKSRefreshWithOps(&ops,&result);
    int failures=(rc!=0)+(result.matched!=1)+(result.finished!=1)+
        (f.kills!=1)+(!f.dead)+(result.errors!=0 || result.timedOut!=0);
    printf("STOREKIT_REFRESH checks=6 failures=%d; host signals=0\n",failures);
    return failures?1:0;
}
