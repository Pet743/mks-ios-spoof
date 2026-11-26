#include "MKSProcessRefresh.h"
#if __has_include("MKSProcessPolicy.h")
#include "MKSProcessPolicy.h"
#else
static int MKSShouldInstallIdentityHooks(const char *name) { (void)name;return 1; }
#endif
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

typedef struct { int gone[4];unsigned kills[4]; } Fixture;
static int checks,failures;
#define CHECK(c) do { checks++;if (!(c)) failures++; } while (0)
static int list(void *context,pid_t *pids,size_t count) {
    (void)context;
    for (int i=0;pids && i<4 && (size_t)i<count;i++) pids[i]=41000+i;
    return 4;
}
static int name(void *context,pid_t pid,char *out,size_t size) {
    Fixture *f=context;int i=pid-41000;
    const char *names[]={"lockdownd","akd","storekitd","lockdownd-helper"};
    if(i<0 || i>=4 || f->gone[i]) { errno=ESRCH;return 0; }
    return snprintf(out,size,"%s",names[i]);
}
static int signalProcess(void *context,pid_t pid,int signal) {
    Fixture *f=context;int i=pid-41000;
    if(i<0 || i>=4 || f->gone[i]) { errno=ESRCH;return -1; }
    if(signal==SIGKILL) { f->kills[i]++;f->gone[i]=1; }
    return 0;
}
static void pauseProcess(void *context,unsigned milliseconds) {
    (void)context;(void)milliseconds;
}
int main(void) {
#if defined(MKS_ROOTHIDE)
    CHECK(!MKSShouldInstallIdentityHooks("lockdownd"));
    const char *scheme="roothide";
#else
    CHECK(MKSShouldInstallIdentityHooks("lockdownd"));
    const char *scheme="rootless";
#endif
    const char *allowed[]={"AppStore","akd","accountsd","appstored","itunesstored","storekitd","lockdownd-helper","",NULL};
    for (unsigned i=0;i<sizeof(allowed)/sizeof(allowed[0]);i++) CHECK(MKSShouldInstallIdentityHooks(allowed[i]));
#if defined(MKS_ROOTHIDE)
    Fixture f={0};MKSRefreshResult result;MKSProcessOps ops={&f,list,name,signalProcess,pauseProcess};
    CHECK(MKSRefreshWithOps(&ops,&result)==0);
    CHECK(f.kills[0]==0 && f.gone[0]==0);
    CHECK(f.kills[1]==1 && f.kills[2]==1 && f.kills[3]==0);
    CHECK(result.matched==2 && result.signaled==2 && result.finished==2);
    CHECK(result.errors==0 && result.timedOut==0);
#endif
    printf("USB_TRUST %s checks=%d failures=%d; host signals=0\n",scheme,checks,failures);
    return failures?1:0;
}
