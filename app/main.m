#import <UIKit/UIKit.h>
#import "../common/MKSProfile.h"
#import "../common/MKSHTTP.h"
#import "../common/MKSKeychainIPC.h"
#import "MKSAPIDocsController.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

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
@property (nonatomic, strong) MKSProfileStore *profileStore;
@property (nonatomic, strong) UIButton *cleanupButton;
@property (nonatomic, strong) UIButton *spoofButton;
@property (nonatomic, strong) UIButton *restoreButton;
@property (nonatomic) BOOL cleanupRunning;
@end

@implementation MKSViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.profileStore=[[MKSProfileStore alloc] initWithPaths:MKSConfigPaths()];
    self.navigationController.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    self.title = @"MKS 改机";
    UILabel *titleLabel=[UILabel new];
    titleLabel.text=self.title;
    titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.textColor=UIColor.labelColor;
    titleLabel.textAlignment=NSTextAlignmentCenter;
    titleLabel.adjustsFontForContentSizeCategory=YES;
    NSDictionary *bundleInfo=NSBundle.mainBundle.infoDictionary;
    UILabel *versionLabel=[UILabel new];
    versionLabel.text=[NSString stringWithFormat:@"v%@ · %@",
        bundleInfo[@"CFBundleShortVersionString"] ?: @"—",bundleInfo[@"CFBundleVersion"] ?: @"—"];
    versionLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    versionLabel.textColor=UIColor.secondaryLabelColor;
    versionLabel.textAlignment=NSTextAlignmentCenter;
    versionLabel.adjustsFontForContentSizeCategory=YES;
    versionLabel.accessibilityIdentifier=@"mks.appVersion";
    versionLabel.accessibilityLabel=[NSString stringWithFormat:@"版本 %@，构建号 %@",
        bundleInfo[@"CFBundleShortVersionString"] ?: @"未知",bundleInfo[@"CFBundleVersion"] ?: @"未知"];
    UIStackView *titleStack=[[UIStackView alloc] initWithArrangedSubviews:@[titleLabel,versionLabel]];
    titleStack.axis=UILayoutConstraintAxisVertical;
    titleStack.alignment=UIStackViewAlignmentCenter;
    titleStack.spacing=0;
    [titleStack sizeToFit];
    self.navigationItem.titleView=titleStack;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"接口文档" style:UIBarButtonItemStylePlain target:self action:@selector(openAPIDocs)];

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
    [b1 setTitle:@"一键改机（生成测试参数）" forState:UIControlStateNormal];
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
    self.spoofButton=b1;self.restoreButton=b2;
    self.cleanupButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.cleanupButton.frame=CGRectMake(20,515,self.view.bounds.size.width-40,52);
    [self.cleanupButton setTitle:@"清理全局 Keychain" forState:UIControlStateNormal];
    [self.cleanupButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.cleanupButton.backgroundColor=[UIColor colorWithRed:0.55 green:0.3 blue:0.1 alpha:1];
    self.cleanupButton.layer.cornerRadius=10;
    self.cleanupButton.titleLabel.font=[UIFont boldSystemFontOfSize:16];
    [self.cleanupButton addTarget:self action:@selector(confirmKeychainCleanup) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cleanupButton];
}
- (void)openAPIDocs {
    [self.navigationController pushViewController:[MKSAPIDocsController new] animated:YES];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.status.text=[self currentState];self.text.text=[self currentParams];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:MKSHTTPDeviceID()?@"设备绑定":@"未绑定设备" style:UIBarButtonItemStylePlain target:self action:@selector(openAPIDocs)];
}
- (NSString *)configPath { return MKSConfigPath(); }
- (NSDictionary *)currentProfile {
    return [self.profileStore snapshot];
}
- (NSString *)currentState {
    NSDictionary *p=[self currentProfile];
    return [p[@"enabled"] boolValue]?@"状态：改机配置已启用":@"状态：改机配置已停用";
}
- (NSString *)currentParams {
    NSDictionary *p=[self currentProfile];
    if(![p[@"enabled"] boolValue]) return @"（未启用参数）";
    NSData *data=[NSJSONSerialization dataWithJSONObject:p[@"values"] options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
    NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"（参数读取失败）";
    NSArray<NSString *> *errors=MKSProfileHTMLRuleErrors(p);
    NSString *result=errors.count?[@"未通过：" stringByAppendingString:[errors componentsJoinedByString:@"、"]]:@"认证通过";
    return [NSString stringWithFormat:@"HTML 参数规则：%@\n%@\n\n%@",result,
        MKSProfileHTMLParameters(p) ?: @"（参数格式错误）",json];
}
- (BOOL)writeConfig:(NSDictionary *)profile {
    NSError *error=nil;
    if(!MKSWriteProfile(profile,[self configPath],&error)) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"配置写入失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return NO;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.mks.spoof.changed"),NULL,NULL,true);
    self.status.text=[self currentState]; self.text.text=[self currentParams];
    return YES;
}
- (void)doSpoof {
    NSDictionary *profile=MKSGenerateProfile();
    NSArray<NSString *> *errors=MKSProfileHTMLRuleErrors(profile);
    if(errors.count) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"参数未通过 HTML 规则"
            message:[errors componentsJoinedByString:@"、"] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];return;
    }
    if(![self writeConfig:profile]) return;
    [self restartAfterSave];
}
- (void)doRestore {
    // An authoritative OFF record prevents old preference/container files from reactivating spoofing.
    NSDictionary *off=@{@"schemaVersion":@2,@"enabled":@NO,@"name":@"已停用",@"values":@{}};
    if(![self writeConfig:off]) return;
    [self restartAfterSave];
}
- (void)restartAfterSave {
    self.status.text=@"配置已保存，正在重启桌面…";
    self.spoofButton.enabled=NO;self.restoreButton.enabled=NO;self.cleanupButton.enabled=NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{do_respring();});
}
- (void)confirmKeychainCleanup {
    if(self.cleanupRunning) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清理全局 Keychain？"
        message:@"将清理全局密码、证书和密钥记录，多个 App 可能需要重新登录。与参考插件相同，保留 apple 和 lockdown-identities 对应的记录。执行前会自动备份。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认清理" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self cleanKeychain];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)cleanKeychain {
    if(self.cleanupRunning) return;
    self.cleanupRunning=YES;
    self.cleanupButton.enabled=NO;self.spoofButton.enabled=NO;self.restoreButton.enabled=NO;
    [self.cleanupButton setTitle:@"正在备份并清理…" forState:UIControlStateNormal];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *result=MKSRequestKeychainClean();
        dispatch_async(dispatch_get_main_queue(),^{
            self.cleanupRunning=NO;
            self.cleanupButton.enabled=YES;self.spoofButton.enabled=YES;self.restoreButton.enabled=YES;
            [self.cleanupButton setTitle:@"清理全局 Keychain" forState:UIControlStateNormal];
            BOOL committed=[result[@"committed"] boolValue];
            BOOL unknown=[result[@"outcomeUnknown"] boolValue];
            NSString *title=committed?@"Keychain 已清理":(unknown?@"清理结果待核对":@"Keychain 未清理");
            NSString *message=nil;
            if(committed) {
                NSDictionary *counts=result[@"deleted"];
                NSUInteger total=0;
                for(NSNumber *count in counts.allValues) total+=count.unsignedIntegerValue;
                message=[NSString stringWithFormat:@"已按参考插件的规则删除 %lu 条记录。\n备份：%@",(unsigned long)total,
                    result[@"backup"] ?: @"（备份路径未返回）"];
            } else if(unknown) {
                message=@"与清理服务的连接未正常完成，尚未确认执行结果。请先核对服务和备份，避免重复操作。";
            } else {
                NSDictionary *messages=@{@"unauthorized":@"当前安装位置未通过服务校验，请使用 DEB 安装的 MKS。",
                    @"connection":@"尚未连接清理服务，请安装完整的 MKS DEB 并确认守护进程已启动。",
                    @"schema":@"当前 Keychain 数据库结构与清理规则不兼容，操作已停止。",
                    @"backup":@"备份未完成，操作已停止。",
                    @"lock":@"数据库正在使用中，本次清理未执行。",
                    @"database_missing":@"没有找到可清理的 Keychain 数据库。",
                    @"simulator":@"模拟器仅用于查看界面，清理功能需要越狱设备。"};
                message=messages[result[@"stage"]] ?: @"清理未提交，数据库事务已撤回。";
            }
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
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
