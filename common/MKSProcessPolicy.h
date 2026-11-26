#ifndef MKS_PROCESS_POLICY_H
#define MKS_PROCESS_POLICY_H
#include <string.h>

static inline int MKSShouldInstallIdentityHooks(const char *processName) {
#if defined(MKS_ROOTHIDE)
    // USB pairing must see the same native identity in enabled/disabled modes.
    // Keep this guard even if an older or broader injection filter loads MKS.
    if (processName && !strcmp(processName,"lockdownd")) return 0;
#else
    (void)processName;
#endif
    return 1;
}
#endif
