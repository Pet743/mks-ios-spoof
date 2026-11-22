#import "MKSAPIDocsController.h"
#import "../common/MKSHTTP.h"
#import "../common/MKSKeychainIPC.h"
#include <TargetConditionals.h>

@interface MKSAPIDocsController ()
@property(strong) UITextView *document;
@property(strong) UILabel *bindingStatus;
@property(strong) UIButton *bindingButton;
@property(copy) NSDictionary *localStatus;
@property BOOL bindingRunning;
@end
@implementation MKSAPIDocsController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"HTTP 调用文档";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.bindingStatus=[UILabel new];self.bindingStatus.numberOfLines=0;
    self.bindingStatus.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.bindingStatus.adjustsFontForContentSizeCategory=YES;
    self.bindingStatus.textColor=UIColor.labelColor;
    self.bindingStatus.text=@"正在查询设备绑定…";
    self.bindingButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.bindingButton setTitle:@"绑定 USB 设备编号" forState:UIControlStateNormal];
    self.bindingButton.titleLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.bindingButton.titleLabel.adjustsFontForContentSizeCategory=YES;
    self.bindingButton.contentEdgeInsets=UIEdgeInsetsMake(10,0,10,0);
    self.bindingButton.enabled=NO;
    [self.bindingButton addTarget:self action:@selector(bindDevice) forControlEvents:UIControlEventTouchUpInside];
    [self.bindingButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    self.document=[UITextView new];self.document.translatesAutoresizingMaskIntoConstraints=NO;
    self.document.editable=NO;self.document.selectable=YES;
    self.document.font=[UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.document.adjustsFontForContentSizeCategory=YES;
    self.document.textColor=UIColor.labelColor;
    self.document.textContainerInset=UIEdgeInsetsMake(12,0,24,0);
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.bindingStatus,self.bindingButton,self.document]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyDocument)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[self refreshBinding];
}
- (void)refreshDocument {
    NSString *token=MKSHTTPToken();
#if TARGET_OS_SIMULATOR
    token=@"SIMULATOR_EXAMPLE_TOKEN";
#endif
    self.document.text=MKSHTTPDocumentation(MKSHTTPBaseURL(),token ?: @"（服务未就绪：安装完整 MKS DEB 后返回重进）");
    self.navigationItem.rightBarButtonItem.title=@"复制";
}
- (void)refreshBinding {
    [self refreshDocument];
    self.bindingButton.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *status=MKSRequestLocalStatus();
        dispatch_async(dispatch_get_main_queue(),^{
            self.localStatus=status;
            BOOL ready=[status[@"ok"] boolValue];
            self.bindingButton.enabled=ready;
            self.bindingStatus.text=ready?([status[@"deviceConfigured"] boolValue]?
                [NSString stringWithFormat:@"USB 设备编号\n%@",status[@"deviceId"]]:@"未配置设备编号"):
                @"设备绑定服务未就绪，请确认已安装完整 DEB 并启动守护进程。";
#if TARGET_OS_SIMULATOR
            self.bindingStatus.text=@"未配置设备编号（模拟器预览）";
            self.bindingButton.enabled=YES;
#endif
            [self.bindingButton setTitle:[status[@"deviceConfigured"] boolValue]?@"重新绑定 USB 设备编号":@"绑定 USB 设备编号" forState:UIControlStateNormal];
        });
    });
}
- (void)showMessage:(NSString *)title text:(NSString *)text {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)bindDevice {
    if(self.bindingRunning) return;
    id previous=self.localStatus[@"deviceId"] ?: NSNull.null;
    BOOL configured=[previous isKindOfClass:NSString.class];
    NSString *message=configured?[NSString stringWithFormat:@"当前编号\n%@\n\n请输入电脑通过 USB 读取的实际 UDID。",previous]:
        @"请输入电脑通过 USB 读取的实际 UDID。支持 8 位十六进制、连字符和 16 位十六进制，或 40 位十六进制。";
    UIAlertController *input=[UIAlertController alertControllerWithTitle:@"USB 设备编号" message:message preferredStyle:UIAlertControllerStyleAlert];
    [input addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder=@"USB UDID";field.accessibilityLabel=@"USB 设备编号";
        field.autocorrectionType=UITextAutocorrectionTypeNo;
        field.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;
        field.text=configured?previous:@"";
    }];
    [input addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [input addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *device=MKSNormalizeDeviceID(input.textFields.firstObject.text);
        if(!device) {
            [self showMessage:@"设备编号格式错误" text:@"请填写电脑读取的 USB UDID，例如 8 位十六进制、连字符和 16 位十六进制，或 40 位十六进制。"];
            return;
        }
        NSString *confirmation=configured?[NSString stringWithFormat:@"原编号\n%@\n\n新编号\n%@\n\n绑定后 HTTP 路由将使用新编号。",previous,device]:
            [NSString stringWithFormat:@"将绑定到\n%@\n\n请核对它与电脑读取的实际 USB UDID 一致。",device];
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:configured?@"确认重新绑定？":@"确认绑定？" message:confirmation preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"确认绑定" style:configured?UIAlertActionStyleDestructive:UIAlertActionStyleDefault handler:^(UIAlertAction *choice) {
            [self saveBinding:device previous:previous];
        }]];
        [self presentViewController:confirm animated:YES completion:nil];
    }]];
    [self presentViewController:input animated:YES completion:nil];
}
- (void)saveBinding:(NSString *)device previous:(id)previous {
    self.bindingRunning=YES;self.bindingButton.enabled=NO;
    self.bindingStatus.text=@"正在绑定并核对守护进程状态…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDictionary *result=MKSRequestDeviceBinding(device,previous);
        BOOL verified=[result[@"ok"] boolValue] && [result[@"status"][@"deviceConfigured"] boolValue] &&
            [result[@"status"][@"deviceId"] isEqual:device];
        dispatch_async(dispatch_get_main_queue(),^{
            self.bindingRunning=NO;
            if(verified) [self showMessage:@"设备已绑定" text:[NSString stringWithFormat:@"%@\n\n守护进程已确认生效。请在电脑端用同一 USB UDID 查询状态。",device]];
            else {
                NSDictionary *messages=@{@"device_id_changed":@"设备编号已被其他操作更改。请重新打开绑定界面，核对当前编号。",
                    @"permission_denied":@"守护进程需要以 root 运行。请重新安装完整 DEB。",
                    @"invalid_device_id":@"设备编号格式错误，请核对电脑读取的 USB UDID。",
                    @"resource_busy":@"另一个本地配置操作正在执行，请稍后重新核对。"};
                NSString *message=messages[result[@"error"]] ?: @"绑定尚未核验，请检查守护进程和配置目录，然后重新查询当前编号。";
                [self showMessage:@"绑定待核对" text:message];
            }
            [self refreshBinding];
        });
    });
}
- (void)copyDocument {
    UIPasteboard.generalPasteboard.string=self.document.text;
    self.navigationItem.rightBarButtonItem.title=@"已复制";
}
@end
