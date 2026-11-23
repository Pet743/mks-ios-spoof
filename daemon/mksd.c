// mksd - MKS 改机 root 守护进程
// 监听 UDP 127.0.0.1:33236，处理 App 的守护类请求（respring 等）
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <signal.h>
#include <time.h>
#include <stdarg.h>
#include <spawn.h>
#include <sys/wait.h>
#include <errno.h>
#include "../common/MKSPaths.h"
#if defined(MKS_ROOTHIDE)
#include "MKSProcessRefresh.h"
#endif

#ifndef APP_PORT
#define APP_PORT 33236
#endif
#define FLAG "/var/mobile/Media/mks.respring"
#define LOGF "/var/mobile/mksd.log"
extern const char *MKSStatus(void);
extern void MKSCleanerStartServer(void);
extern void MKSHTTPStartServer(void);
extern int MKSHTTPConfigureDeviceID(const char *deviceID);

static void logmsg(const char *fmt, ...) {
    FILE *f = fopen(LOGF, "a");
    if (!f) return;
    time_t t = time(NULL);
    struct tm tm; localtime_r(&t, &tm);
    fprintf(f, "%02d:%02d:%02d ", tm.tm_hour, tm.tm_min, tm.tm_sec);
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fprintf(f, "\n"); fclose(f);
}

int MKSRespring(void) {
#if defined(MKS_ROOTHIDE)
    MKSRefreshResult refresh;
    int refreshed=MKSRefreshIdentityProcesses(&refresh);
    logmsg("identity refresh matched=%u signaled=%u finished=%u errors=%u timeout=%u rc=%d",
           refresh.matched,refresh.signaled,refresh.finished,refresh.errors,refresh.timedOut,refreshed);
    if (refreshed) return -1;
#endif
    logmsg("respring requested -> killall SpringBoard");
    unlink(FLAG);
    const char *paths[] = {MKS_JB_PATH("/usr/bin/killall"), "/usr/bin/killall", MKS_JB_PATH("/bin/killall"), NULL};
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], X_OK) != 0) continue;
        pid_t pid = 0;
        const char *argv[] = {paths[i], "-9", "SpringBoard", NULL};
        int r = posix_spawn(&pid, paths[i], NULL, NULL, (char *const *)argv, NULL);
        logmsg("spawn %s rc=%d pid=%d", paths[i], r, pid);
        if (r == 0) {
            int status = 0;
            while (waitpid(pid, &status, 0) < 0) {
                if (errno != EINTR) return -1;
            }
            return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
        }
    }
    logmsg("no killall found");
    return -1;
}

int main(int argc,char **argv) {
    if(argc==3 && !strcmp(argv[1],"--set-device-id")) return MKSHTTPConfigureDeviceID(argv[2]);
    if(argc!=1) {
        fputs("{\"ok\":false,\"error\":\"invalid_arguments\"}\n",stdout);
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);
    logmsg("mksd started (pid=%d, uid=%d)", getpid(), getuid());
    MKSCleanerStartServer();
    MKSHTTPStartServer();

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { logmsg("socket failed"); return 1; }
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(APP_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        if (errno == EADDRINUSE) { logmsg("port busy, another mksd alive -> exit"); }
        else logmsg("bind %d failed errno=%d", APP_PORT, errno);
        return 1;
    }
    logmsg("listening on 127.0.0.1:%d", APP_PORT);

    char buf[512];
    while (1) {
        struct sockaddr_in peer; socklen_t plen = sizeof(peer);
        ssize_t n = recvfrom(fd, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&peer, &plen);
        if (n < 0) { if (errno == EINTR) continue; break; }
        if (n == 0) continue;
        buf[n] = 0;
        if (n == 4 && !memcmp(buf, "PING", 4)) {
            sendto(fd, "PONG", 4, 0, (struct sockaddr *)&peer, plen);
        } else if (n == 8 && !memcmp(buf, "RESPRING", 8)) {
            const char *r = MKSRespring() == 0 ? "OK" : "ERROR";
            sendto(fd, r, strlen(r), 0, (struct sockaddr *)&peer, plen);
        } else if (n == 6 && !memcmp(buf, "STATUS", 6)) {
            const char *r = MKSStatus();
            sendto(fd, r, strlen(r), 0, (struct sockaddr *)&peer, plen);
        } else {
            sendto(fd, "INVALID", 7, 0, (struct sockaddr *)&peer, plen);
        }
    }
    close(fd);
    return 1;
}
