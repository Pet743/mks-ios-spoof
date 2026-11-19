#import <UIKit/UIKit.h>
#include <spawn.h>
#include <dlfcn.h>
#include <arpa/inet.h>
#include <sys/socket.h>

static NSString *gParams = @"";

static NSString *pickStr(NSString *set, int n) {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < n; i++) {
        uint32_t idx = arc4random_uniform((uint32_t)set.length);
        [s appendFormat:@"%C", [set characterAtIndex:idx]];
    }
    return s;
}
static NSString *digits(int n) { return pickStr(@"0123456789", n); }
static BOOL luhnOK(NSString *s) {
    int sum = 0; BOOL dbl = NO;
    for (NSInteger i = s.length - 1; i >= 0; i--) {
        int d = [s characterAtIndex:i] - '0';
        if (dbl) { d *= 2; if (d > 9) d -= 9; }
        sum += d; dbl = !dbl;
    }
    return sum % 10 == 0;
}
static NSString *genIMEI(void) {
    for (int t = 0; t < 100; t++) {
        NSString *body = digits(14);
        for (int c = 0; c < 10; c++) {
            NSString *full = [body stringByAppendingFormat:@"%d", c];
            if (luhnOK(full)) return full;
        }
    }
    return @"000000000000000";
}
static NSString *randMac(void) {
    NSMutableArray *a = [NSMutableArray array];
    NSString *hex = @"0123456789abcdef";
    for (int i = 0; i < 6; i++) [a addObject:pickStr(hex, 2)];
    return [a componentsJoinedByString:@":"];
}
static NSString *genParams(void) {
    NSString *serSet = @"ABCDEFGHJKLMNPQRSTUVWXYZ123456789";
    NSString *ser = pickStr(serSet, 10);
    NSString *imei = genIMEI();
    NSString *imei2 = [imei substringToIndex:14];
    NSString *mac1 = randMac(), *mac2 = randMac();
    NSString *ecid = pickStr(@"0123456789ABCDEF", 16);
    NSString *udid = pickStr(@"0123456789abcdef", 40);
    NSString *model = @"iPhone16,2";
    NSString *U = @"ABCDEFGHJKLMNPQRSTUVWXYZ";
    NSString *part = [NSString stringWithFormat:@"M%C%C%C%CLL/A",
        [U characterAtIndex:arc4random_uniform((uint32_t)U.length)],
        [U characterAtIndex:arc4random_uniform((uint32_t)U.length)],
        (char)('0' + arc4random_uniform(10)),
        [U characterAtIndex:arc4random_uniform((uint32_t)U.length)]];
    NSString *board = @"D81AP";
    NSString *chip = [NSString stringWithFormat:@"T%d%03d", 7 + arc4random_uniform(2), arc4random_uniform(1000)];
    NSString *build = [NSString stringWithFormat:@"%02d%C%02d", 20 + arc4random_uniform(3),
        [U characterAtIndex:arc4random_uniform((uint32_t)U.length)], 10 + arc4random_uniform(90)];
    NSString *ios = [NSString stringWithFormat:@"16.%d.%d", arc4random_uniform(8), arc4random_uniform(10)];
    return [@[ser, imei, imei2, mac1, mac2, ecid, udid, ser, model, part, board, chip, build, ios]
            componentsJoinedByString:@"----"];
}

static void do_respring(void) {
    // 通知 root 守护进程 mksd 执行 respring（同 dpp 的 dppd 架构）
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd >= 0) {
        struct sockaddr_in a;
        memset(&a, 0, sizeof(a));
        a.sin_family = AF_INET;
        a.sin_port = htons(33236);
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        sendto(fd, "RESPRING", 8, 0, (struct sockaddr *)&a, sizeof(a));
        close(fd);
    }
}

@interface MKSViewController : UIViewController
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UITextView *text;
@end

@implementation MKSViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    self.title = @"MKS 改机";

    self.status = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width - 40, 30)];
    self.status.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.4 alpha:1];
    self.status.font = [UIFont boldSystemFontOfSize:20];
    self.status.text = [self currentState];

    self.text = [[UITextView alloc] initWithFrame:CGRectMake(20, 145, self.view.bounds.size.width - 40, 220)];
    self.text.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    self.text.textColor = [UIColor whiteColor];
    self.text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.text.editable = NO;
    self.text.text = [self currentParams];
    [self.view addSubview:self.status];
    [self.view addSubview:self.text];

    UIButton *b1 = [UIButton buttonWithType:UIButtonTypeSystem];
    b1.frame = CGRectMake(20, 385, self.view.bounds.size.width - 40, 52);
    [b1 setTitle:@"一键改机（随机生成并通过认证）" forState:UIControlStateNormal];
    [b1 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b1.backgroundColor = [UIColor colorWithRed:0.15 green:0.45 blue:0.9 alpha:1];
    b1.layer.cornerRadius = 10; b1.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b1 addTarget:self action:@selector(doSpoof) forControlEvents:UIControlEventTouchUpInside];

    UIButton *b2 = [UIButton buttonWithType:UIButtonTypeSystem];
    b2.frame = CGRectMake(20, 450, self.view.bounds.size.width - 40, 52);
    [b2 setTitle:@"还原设备（关闭改机）" forState:UIControlStateNormal];
    [b2 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b2.backgroundColor = [UIColor colorWithRed:0.55 green:0.18 blue:0.18 alpha:1];
    b2.layer.cornerRadius = 10; b2.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [b2 addTarget:self action:@selector(doRestore) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:b1];
    [self.view addSubview:b2];
}
- (NSString *)configPath {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [dir stringByAppendingPathComponent:@"mks.config"];
}
- (NSString *)currentState {
    NSString *s = [NSString stringWithContentsOfFile:[self configPath] encoding:NSUTF8StringEncoding error:nil];
    if (!s || s.length == 0) return @"状态：未改机（真实设备）";
    return @"状态：已改机";
}
- (NSString *)currentParams {
    NSString *s = [NSString stringWithContentsOfFile:[self configPath] encoding:NSUTF8StringEncoding error:nil];
    return (s && s.length) ? s : @"（无参数）";
}
- (void)writeConfig:(NSString *)p {
    [p writeToFile:[self configPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // 同时尝试写共享位置（越狱环境可能允许）
    [p writeToFile:@"/var/mobile/Media/mks.config" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.mks.spoof.changed"), NULL, NULL, true);
    self.status.text = [self currentState];
    self.text.text = [self currentParams];
}
- (void)doSpoof {
    gParams = genParams();
    [self writeConfig:gParams];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"改机成功"
        message:[gParams stringByAppendingString:@"\n\n3 秒后自动重启桌面"]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *x) { do_respring(); }]];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ do_respring(); });
}
- (void)doRestore {
    [[NSFileManager defaultManager] removeItemAtPath:[self configPath] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Media/mks.config" error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.mks.spoof.changed"), NULL, NULL, true);
    self.status.text = [self currentState];
    self.text.text = [self currentParams];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已还原"
        message:@"设备信息已恢复真实值" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

@interface MKSAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation MKSAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)o {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    MKSViewController *vc = [MKSViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([MKSAppDelegate class])); }
}
