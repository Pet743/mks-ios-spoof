#ifndef MKS_PROCESS_REFRESH_H
#define MKS_PROCESS_REFRESH_H
#include <stddef.h>
#include <sys/types.h>

typedef struct {
    void *context;
    int (*list)(void *, pid_t *, size_t);
    int (*name)(void *, pid_t, char *, size_t);
    int (*signal)(void *, pid_t, int);
    void (*pause)(void *, unsigned);
} MKSProcessOps;

typedef struct {
    unsigned matched, signaled, finished, errors, timedOut;
} MKSRefreshResult;

int MKSRefreshWithOps(const MKSProcessOps *, MKSRefreshResult *);
int MKSRefreshIdentityProcesses(MKSRefreshResult *);
#endif
