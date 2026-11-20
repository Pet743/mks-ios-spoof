# MKS 改机

自用 rootless iOS 工具，当前版本 **1.11**。提供一键改机、恢复原机、全局 Keychain 清理，以及同一 Wi-Fi 内的 HTTP 调用。无卡密、激活或远程授权。

## 使用

安装完整 `dist/mks_1.11.deb` 后，打开 MKS：

- **一键改机**：生成并保存参数，然后自动重启桌面，手机短暂黑屏。
- **恢复原机**：写入停用配置，然后自动重启桌面。
- **清理全局 Keychain**：独立确认后备份并按参考插件规则清理，不重启桌面。
- **右上角「接口文档」**：查看本机 Wi-Fi 地址、设备 UDID 路由、访问令牌与三个功能的 curl 示例，可一键复制。

HTTP 默认端口 `33237`，路径前缀 `/v1/devices/{USB_UDID}`。改机不会修改 HTTP 服务单独保存的设备编号。Bearer token 用于授权，UDID 用于路由。操作返回任务编号，查询任务确认完成；带 Idempotency-Key 的重复请求不会重复改机或清理。

## 文档

- [HTTP API、curl 与 Python 示例](docs/http-api.md)
- [安装、设备编号配置与升级](docs/install.md)
- [全局 Keychain 规则及 REA/Craft Anything 分析](docs/keychain-cleaner.md)
- [验证结果与实际边界](docs/validation.md)
- [DPP 底层对照分析](docs/dpp-analysis.md)
- [项目交接总文档](HANDOVER.md)

## 构建与验证

macOS + Xcode iPhoneOS SDK，无需 Theos：

```sh
python3 tests/run_host_tests.py
python3 tests/test_keychain.py
python3 tests/test_daemon.py
python3 tests/test_http.py
python3 scripts/build.py
python3 tests/verify_packages.py
```

输出 `dist/mks_1.11.deb` 和 `dist/MKS-spoofer-1.11.ipa`，均为 arm64 + arm64e。完整 DEB 包含 App、tweak、daemon 和 HTTP 服务；独立 IPA 不安装 daemon。模拟器预览：`python3 scripts/build.py --simulator`。

## 设备信息替换

App、tweak 和 daemon 共用强类型配置解析器，兼容旧版 14 段配置；覆盖 MobileGestalt、IOKit Create/Search、sysctl、系统版本字典、IDFV 及允许跟踪时的 IDFA。内部 MG hook 保留原系统的类型输出，MGGetStringAnswer 按原函数所有权返回引用；原生缺失的敏感属性保留缺失状态。

主配置 `/var/jb/var/lib/mks/mks.config` 使用原子写入和回读验证。停用记录具有优先权，避免旧配置重新启用。安装时在主配置不存在的情况下迁移旧 Media 配置。用户已反馈改机功能测试正常；本轮没有独立验收 Apple 账户登录成功。

Keychain 清理与用户提供的 App 清理插件使用相同的五条 SQL 和保护组规则，增加事务与一致快照备份；不同于恢复改机配置，已提交的 Keychain 删除不会因点击「恢复原机」而自动恢复。

## 1.11 设备与发布状态

已在 USB 连接的 iOS 16.3.1 rootless iPhone 安装 1.11，通过局域网实测改机、恢复接口及实际桌面重启，测试后恢复原参数。HTTP 清理执行在合成数据库验证，真实设备 Keychain 未在本轮删除。源码、安装产物及总文档随 1.11 同步；私人诊断、设备编号与访问令牌不纳入仓库。
