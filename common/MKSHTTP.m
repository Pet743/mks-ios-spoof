#import "MKSHTTP.h"
#include <ifaddrs.h>
#include <arpa/inet.h>

NSString *MKSHTTPStateDirectory(void) {
#ifdef MKS_HTTP_TEST
    return @(getenv("MKS_TEST_STATE"));
#else
    return [MKS_HTTP_TOKEN_PATH stringByDeletingLastPathComponent];
#endif
}
NSString *MKSNormalizeDeviceID(NSString *value) {
    if(![value isKindOfClass:NSString.class]) return nil;
    NSString *normalized=[[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    NSString *pattern=@"\\A([0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{40})\\z";
    return [normalized rangeOfString:pattern options:NSRegularExpressionSearch].location==NSNotFound?nil:normalized;
}
NSString *MKSHTTPInstallationID(void) {
    NSString *path=[MKSHTTPStateDirectory() stringByAppendingPathComponent:@"installation-id"];
    NSString *value=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return [[NSUUID alloc] initWithUUIDString:value].UUIDString;
}
NSString *MKSHTTPToken(void) {
    NSString *value=[NSString stringWithContentsOfFile:MKS_HTTP_TOKEN_PATH encoding:NSUTF8StringEncoding error:NULL];
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
NSString *MKSHTTPDeviceID(void) {
    NSString *path=[MKSHTTPStateDirectory() stringByAppendingPathComponent:@"device-id"];
    NSString *value=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return MKSNormalizeDeviceID(value);
}
NSString *MKSHTTPBaseURL(void) {
    struct ifaddrs *interfaces=NULL;
    NSString *address=nil;
    if(getifaddrs(&interfaces)==0) {
        for(struct ifaddrs *p=interfaces;p;p=p->ifa_next) {
            if(p->ifa_addr && p->ifa_addr->sa_family==AF_INET && !strcmp(p->ifa_name,"en0")) {
                char text[INET_ADDRSTRLEN]={0};
                if(inet_ntop(AF_INET,&((struct sockaddr_in *)p->ifa_addr)->sin_addr,text,sizeof(text))) address=@(text);
            }
        }
        freeifaddrs(interfaces);
    }
    return [NSString stringWithFormat:@"http://%@:%d",address ?: @"127.0.0.1",MKS_HTTP_PORT];
}
NSString *MKSHTTPDocumentation(NSString *baseURL,NSString *token) {
    NSString *device=MKSHTTPDeviceID() ?: @"USB_DEVICE_UDID";
    baseURL=[baseURL stringByAppendingFormat:@"/v1/devices/%@",device];
    return [NSString stringWithFormat:
        @"MKS HTTP API · v1\n\n地址\n%@\n\n访问令牌\n%@\n\n"
        "同一 Wi-Fi 调用；服务由 daemon 提供，关闭 App 仍可调用。需要安装完整 MKS DEB。"
        "明文 HTTP 仅用于可信局域网；不要做公网端口映射。令牌是本机接口凭据，无卡密或远程授权。\n\n"
        "认证\nAuthorization: Bearer <令牌>\n\n"
        "设备标识\n地址中的 devices 后面是 USB UDID；改机不修改本服务保存的路由标识。编号需与当前手机一致。\n\n"
        "首次配置\n在此页面点击“绑定 USB 设备编号”，填入电脑通过 USB 读取的实际 UDID。重新绑定需确认原值和新值。\n\n"
        "状态字段\napiVersion=1；environment.jailbreak=rootless 或 roothide；deviceConfigured 表示设备编号已绑定。"
        "installationId 标识当前持久化安装状态，同一环境升级保留；新状态目录会生成新标识。\n\n"
        "1. 查看状态\ncurl -H 'Authorization: Bearer %@' '%@/status'\n\n"
        "2. 一键改机＋重启桌面\n"
        "curl -X POST '%@/spoof' \\\n  -H 'Authorization: Bearer %@' \\\n  -H 'Idempotency-Key: spoof-001' \\\n  -H 'Content-Type: application/json' -d '{}'\n\n"
        "3. 恢复原机＋重启桌面\n"
        "curl -X POST '%@/restore' \\\n  -H 'Authorization: Bearer %@' \\\n  -H 'Idempotency-Key: restore-001' \\\n  -H 'Content-Type: application/json' -d '{}'\n\n"
        "4. 全局清理 Keychain\n"
        "curl -X POST '%@/keychain/clean' \\\n  -H 'Authorization: Bearer %@' \\\n  -H 'Idempotency-Key: clean-001' \\\n  -H 'Content-Type: application/json' -d '{\"confirm\":true}'\n\n"
        "5. 查询任务\n"
        "curl -H 'Authorization: Bearer %@' '%@/jobs/<jobId>'\n\n"
        "响应规则\nPOST 返回 HTTP 202 与 jobId；不代表执行完成。查询直到 state=succeeded 或 failed。"
        "改机/恢复保存成功后会重启桌面，手机短暂黑屏，完成状态的 respringCommandSucceeded 只表示系统命令成功。"
        "若保存成功而重启失败，result.profileSaved=true。Keychain 清理不重启桌面。\n\n"
        "重复调用\n每次新操作换一个 Idempotency-Key；网络超时重试使用相同 Key，返回同一任务，不重复执行。"
        "同一 Key 用于不同操作返回 409。最多保留最近 100 个任务；daemon 重启后的未完成任务标记 interrupted，需先核对实际状态。\n\n"
        "任务示例\n{\"jobId\":\"...\",\"action\":\"spoof\",\"state\":\"queued\"}\n\n"
        "HTTP 状态码\n200 查询成功；202 已接受；400 请求格式错误；401 令牌错误；403 拒绝浏览器跨源调用；"
        "404 路径不存在；405 方法错误；409 Key 冲突；413 请求过大；415 非 JSON；503 服务或任务持久化失败。\n\n"
        "清理回执\nbackupId 是稳定备份标识，backupCreated=true、backupFormatVersion=1 表示备份成功且采用 SQLite 快照。"
        "backup 保留本地诊断路径。committed=true 才表示事务提交，outcomeUnknown=true 时先核对原任务与备份。\n\n"
        "错误处理\n401 unauthorized 需更新本机令牌；503 device_id_not_configured 且 requiresLocalSetup=true 时先在 App 绑定。"
        "不要为网络中断或未知清理结果换新 Key 自动重发。\n\n"
        "清理范围\n全局清理，需 confirm=true。沿用参考插件的保留组，执行前自动备份。可能使多个 App 退出登录。"
        "不从 URL 参数读取令牌，不支持 GET 触发操作，不自动重试任务。",
        baseURL,token,token,baseURL,baseURL,token,baseURL,token,baseURL,token,token,baseURL];
}
