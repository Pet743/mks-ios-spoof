// mks tweak —— 读 App 写入的配置，动态决定是否伪造
// 配置：/var/mobile/Media/mks.config 或 App 容器 Documents/mks.config
// 文件内容为 14 段 "----" 分隔参数；文件不存在 = 还原真实设备
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <glob.h>

extern void MSHookFunction(void *symbol, void *replace, void **result);

static char g_ser[64], g_imei1[64], g_imei2[64], g_mac1[64], g_mac2[64];
static char g_ecid[64], g_udid[128], g_model[64], g_part[64];
static char g_board[64], g_chip[64], g_build[64], g_ios[64];
static int g_active = 0;

static CFStringRef g_cf_ser, g_cf_imei1, g_cf_imei2, g_cf_mac1, g_cf_mac2;
static CFStringRef g_cf_ecid, g_cf_udid, g_cf_model, g_cf_part, g_cf_board;
static CFStringRef g_cf_chip, g_cf_build, g_cf_ios, g_cf_product;

static char g_cfg[2048];
static time_t g_cfg_mtime = 0;

static void logline(const char *fmt, ...) {
    FILE *f = fopen("/var/mobile/mks.log", "a");
    if (!f) return;
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fputc('\n', f); fclose(f);
}

static CFStringRef cf(const char *s) { return CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8); }

static void split_params(const char *line) {
    char buf[2048];
    strncpy(buf, line, sizeof(buf)-1); buf[sizeof(buf)-1]=0;
    char *fields[16]={0}; int n=0; char *save=NULL;
    for (char *p = strtok_r(buf, "----", &save); p && n<16; p = strtok_r(NULL, "----", &save)) fields[n++]=p;
    if (n < 14) { g_active = 0; return; }
    strncpy(g_ser, fields[0], 63);  strncpy(g_imei1, fields[1], 63);
    strncpy(g_imei2, fields[2], 63); strncpy(g_mac1, fields[3], 63);
    strncpy(g_mac2, fields[4], 63);  strncpy(g_ecid, fields[5], 63);
    strncpy(g_udid, fields[6], 127); strncpy(g_model, fields[8], 63);
    strncpy(g_part, fields[9], 63);  strncpy(g_board, fields[10], 63);
    strncpy(g_chip, fields[11], 63); strncpy(g_build, fields[12], 63);
    strncpy(g_ios, fields[13], 63);
    g_active = 1;
    if (g_cf_ser) { /* 重建 CF 对象 */ }
    g_cf_ser = cf(g_ser); g_cf_imei1 = cf(g_imei1); g_cf_imei2 = cf(g_imei2);
    g_cf_mac1 = cf(g_mac1); g_cf_mac2 = cf(g_mac2); g_cf_ecid = cf(g_ecid);
    g_cf_udid = cf(g_udid); g_cf_model = cf(g_model); g_cf_part = cf(g_part);
    g_cf_board = cf(g_board); g_cf_chip = cf(g_chip); g_cf_build = cf(g_build);
    g_cf_ios = cf(g_ios);
}

static int read_cfg_path(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    if (st.st_mtime == g_cfg_mtime && g_active) return 1;
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    size_t n = fread(g_cfg, 1, sizeof(g_cfg)-1, f);
    fclose(f);
    g_cfg[n] = 0;
    while (n > 0 && (g_cfg[n-1]=='\n' || g_cfg[n-1]=='\r' || g_cfg[n-1]==' ')) g_cfg[--n] = 0;
    g_cfg_mtime = st.st_mtime;
    split_params(g_cfg);
    return g_active;
}

// 检查 respring 标志文件（只有 SpringBoard 响应）
static void check_respring(void) {
    struct stat st;
    if (stat("/var/mobile/Media/mks.respring", &st) != 0) return;
    const char *pn = getprogname();
    if (!pn || strcmp(pn, "SpringBoard") != 0) return;
    unlink("/var/mobile/Media/mks.respring");
    logline("[*] respring flag detected -> exiting SpringBoard");
    kill(getpid(), SIGTERM);
}

// 返回 1 表示启用伪造
static int cfg_active(void) {
    check_respring();
    if (read_cfg_path("/var/mobile/Media/mks.config")) return 1;
    if (read_cfg_path("/var/mobile/Library/Preferences/com.mks.spoof.config")) return 1;
    glob_t g;
    if (glob("/var/mobile/Containers/Data/Application/*/Documents/mks.config", 0, NULL, &g) == 0) {
        int ok = 0;
        for (size_t i = 0; i < g.gl_pathc; i++) {
            if (read_cfg_path(g.gl_pathv[i])) { ok = 1; break; }
        }
        globfree(&g);
        if (!ok) g_active = 0;
        return ok;
    }
    g_active = 0;
    return 0;
}

static CFStringRef answer_for_key(CFStringRef key) {
    if (!key || !g_active) return NULL;
    char kb[128] = {0};
    if (!CFStringGetCString(key, kb, sizeof(kb), kCFStringEncodingUTF8)) return NULL;
    struct { const char *k; CFStringRef v; } map[] = {
        {"ProductType", g_cf_model},
        {"HardwareModel", g_cf_board},
        {"ModelNumber", g_cf_part},
        {"SerialNumber", g_cf_ser},
        {"UniqueDeviceID", g_cf_udid},
        {"InternationalMobileEquipmentIdentity", g_cf_imei1},
        {"InternationalMobileEquipmentIdentity2", g_cf_imei2},
        {"EthernetMacAddress", g_cf_mac1},
        {"BluetoothAddress", g_cf_mac2},
        {"ProductVersion", g_cf_ios},
        {"BuildVersion", g_cf_build},
        {"ChipID", g_cf_chip},
        {"ProductName", g_cf_product},
        {"RegulatoryModelNumber", g_cf_part},
    };
    for (size_t i = 0; i < sizeof(map)/sizeof(map[0]); i++) {
        if (!strcmp(kb, map[i].k) && map[i].v) {
            logline("[MG] %s -> spoofed", kb);
            return map[i].v;
        }
    }
    return NULL;
}

static CFStringRef (*orig_MGGetStringAnswer)(CFStringRef);
static CFStringRef my_MGGetStringAnswer(CFStringRef key) {
    cfg_active();
    CFStringRef r = answer_for_key(key);
    return r ? r : orig_MGGetStringAnswer(key);
}

static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static CFTypeRef my_MGCopyAnswer(CFStringRef key) {
    cfg_active();
    CFStringRef r = answer_for_key(key);
    return r ? (CFTypeRef)CFRetain(r) : orig_MGCopyAnswer(key);
}

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int my_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    cfg_active();
    const char *val = NULL;
    if (g_active && name) {
        if (!strcmp(name, "hw.machine")) val = g_model;
        else if (!strcmp(name, "hw.model")) val = g_board;
        else if (!strcmp(name, "kern.osproductversion")) val = g_ios;
        else if (!strcmp(name, "kern.osversion")) val = g_build;
    }
    if (val && oldp && oldlenp) {
        size_t len = strlen(val) + 1;
        size_t n = (*oldlenp < len) ? *oldlenp : len;
        memcpy(oldp, val, n);
        *oldlenp = len;
        return 0;
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}


// ===================== SpringBoard 悬浮 UI =====================
#import <UIKit/UIKit.h>

@interface MKSHandler : NSObject
@end

@implementation MKSHandler
- (void)tap {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"MKS 改机"
        message:@"选择操作" preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"一键改机" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *line = [MKSHandler genLine];
        [line writeToFile:@"/var/mobile/Media/mks.config" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [line writeToFile:@"/var/mobile/Library/Preferences/com.mks.spoof.config" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"改机成功" message:line preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [[MKSHandler topVC] presentViewController:ok animated:YES completion:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"还原设备" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Media/mks.config" error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Library/Preferences/com.mks.spoof.config" error:nil];
        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"已还原" message:@"设备信息恢复真实值" preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [[MKSHandler topVC] presentViewController:ok animated:YES completion:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [[MKSHandler topVC] presentViewController:ac animated:YES completion:nil];
}
+ (UIViewController *)topVC {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (!w) { for (UIWindow *x in [UIApplication sharedApplication].windows) { if (x.isKeyWindow) { w = x; break; } } }
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
+ (NSString *)genLine {
    const char *U = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    NSMutableString *ser = [NSMutableString string];
    for (int i = 0; i < 10; i++) [ser appendFormat:@"%c", U[arc4random_uniform(24)]];
    NSMutableString *imei = [NSMutableString string];
    for (int i = 0; i < 14; i++) [imei appendFormat:@"%d", arc4random_uniform(10)];
    for (int c = 0; c < 10; c++) {
        NSString *full = [imei stringByAppendingFormat:@"%d", c];
        int sum = 0; BOOL dbl = NO;
        for (NSInteger i = full.length - 1; i >= 0; i--) {
            int d = [full characterAtIndex:i] - '0';
            if (dbl) { d *= 2; if (d > 9) d -= 9; }
            sum += d; dbl = !dbl;
        }
        if (sum % 10 == 0) { imei = [full mutableCopy]; break; }
    }
    NSMutableArray *macs = [NSMutableArray array];
    for (int k = 0; k < 2; k++) {
        NSMutableArray *p = [NSMutableArray array];
        for (int i = 0; i < 6; i++) [p addObject:[NSString stringWithFormat:@"%02x", arc4random_uniform(256)]];
        [macs addObject:[p componentsJoinedByString:@":"]];
    }
    NSMutableString *ecid = [NSMutableString string];
    for (int i = 0; i < 16; i++) [ecid appendFormat:@"%X", arc4random_uniform(16)];
    NSMutableString *udid = [NSMutableString string];
    for (int i = 0; i < 40; i++) [udid appendFormat:@"%x", arc4random_uniform(16)];
    NSString *part = [NSString stringWithFormat:@"M%C%C%C%CLL/A", U[arc4random_uniform(24)], U[arc4random_uniform(24)], (char)('0'+arc4random_uniform(10)), U[arc4random_uniform(24)]];
    NSString *chip = [NSString stringWithFormat:@"T%d%03d", 7 + arc4random_uniform(2), arc4random_uniform(1000)];
    NSString *build = [NSString stringWithFormat:@"%02d%C%02d", 20 + arc4random_uniform(3), U[arc4random_uniform(24)], 10 + arc4random_uniform(90)];
    NSString *ios = [NSString stringWithFormat:@"16.%d.%d", arc4random_uniform(8), arc4random_uniform(10)];
    return [@[ser, imei, [imei substringToIndex:14], macs[0], macs[1], ecid, udid, ser, @"iPhone16,2", part, @"D81AP", chip, build, ios] componentsJoinedByString:@"----"];
}
@end

static void mks_try_install(int attempt);

static void mks_install_now(void) {
    {
        static MKSHandler *h;
        h = [MKSHandler new];
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (!win) { mks_try_install(0); return; }
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(-200, -200, 58, 58);  // 移出屏幕，不显示
        b.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:1.0 alpha:0.85];
        b.layer.cornerRadius = 29;
        b.layer.zPosition = 10000;
        [b setTitle:@"MKS" forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [b addTarget:h action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:b];
        logline("[*] floating button installed on window %p", win);
    }
}

static void mks_try_install(int attempt) {
    if (attempt > 40) { logline("[!] no keyWindow after 40s"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *win = [UIApplication sharedApplication].keyWindow;
        if (win) { mks_install_now(); }
        else { mks_try_install(attempt + 1); }
    });
}

static void mks_setup_ui(void) {
    mks_try_install(0);
}

static void mks_on_respring(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object, CFDictionaryRef info) {
    logline("[*] respring notification -> exit SpringBoard");
    kill(getpid(), SIGTERM);
}

#include <pthread.h>

__attribute__((constructor))
static void mks_init(void) {
    g_cf_product = cf("iPhone");
    cfg_active();
    logline("=== mks loaded pid=%d active=%d ===", getpid(), g_active);

    void *mg1 = dlsym(RTLD_DEFAULT, "MGGetStringAnswer");
    if (!mg1) { void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY); if (h) mg1 = dlsym(h, "MGGetStringAnswer"); }
    if (mg1) MSHookFunction(mg1, (void *)my_MGGetStringAnswer, (void **)&orig_MGGetStringAnswer);

    void *mg2 = dlsym(RTLD_DEFAULT, "MGCopyAnswer");
    if (!mg2) { void *h = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY); if (h) mg2 = dlsym(h, "MGCopyAnswer"); }
    if (mg2) MSHookFunction(mg2, (void *)my_MGCopyAnswer, (void **)&orig_MGCopyAnswer);

    void *sc = dlsym(RTLD_DEFAULT, "sysctlbyname");
    if (sc) MSHookFunction(sc, (void *)my_sysctlbyname, (void **)&orig_sysctlbyname);

    logline("[*] hooks MG1=%p MG2=%p sc=%p", mg1, mg2, sc);
    mks_setup_ui();
}
