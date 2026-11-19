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

#define APP_PORT 33236
#define CFG "/var/mobile/Media/mks.config"
#define FLAG "/var/mobile/Media/mks.respring"
#define LOGF "/var/mobile/mksd.log"

static void logmsg(const char *fmt, ...) {
    FILE *f = fopen(LOGF, "a");
    if (!f) return;
    time_t t = time(NULL);
    struct tm tm; localtime_r(&t, &tm);
    fprintf(f, "%02d:%02d:%02d ", tm.tm_hour, tm.tm_min, tm.tm_sec);
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fprintf(f, "\n"); fclose(f);
}

static int do_respring(void) {
    logmsg("respring requested -> killall SpringBoard");
    unlink(FLAG);
    const char *paths[] = {"/var/jb/usr/bin/killall", "/usr/bin/killall", "/var/jb/bin/killall", NULL};
    for (int i = 0; paths[i]; i++) {
        if (access(paths[i], X_OK) != 0) continue;
        pid_t pid = 0;
        const char *argv[] = {paths[i], "-9", "SpringBoard", NULL};
        int r = posix_spawn(&pid, paths[i], NULL, NULL, (char *const *)argv, NULL);
        logmsg("spawn %s rc=%d pid=%d", paths[i], r, pid);
        if (r == 0) return 0;
    }
    logmsg("no killall found");
    return -1;
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    logmsg("mksd started (pid=%d, uid=%d)", getpid(), getuid());

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
        if (n <= 0) continue;
        buf[n] = 0;
        if (!strncmp(buf, "PING", 4)) {
            sendto(fd, "PONG", 4, 0, (struct sockaddr *)&peer, plen);
        } else if (!strncmp(buf, "RESPRING", 8)) {
            do_respring();
            sendto(fd, "OK", 2, 0, (struct sockaddr *)&peer, plen);
        } else if (!strncmp(buf, "STATUS", 6)) {
            struct stat st;
            const char *r = (stat(CFG, &st) == 0) ? "SPOOFED" : "CLEAN";
            sendto(fd, r, strlen(r), 0, (struct sockaddr *)&peer, plen);
        }
    }
    return 0;
}
