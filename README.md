# MKS 改机

自用 iOS 越狱工具，当前版本 **1.14.1**，提供 Rootless 和 RootHide 两个安装包。提供一键改机、恢复原机、全局 Keychain 清理，以及同一 Wi-Fi 内的 HTTP 调用。无卡密、激活或远程授权。

| 越狱环境 | DEB 架构 | 下载 |
| --- | --- | --- |
| Rootless（固定 `/var/jb`） | `iphoneos-arm64` | [Rootless DEB](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.14.1/mks_1.14.1_rootless_iphoneos-arm64.deb) |
| RootHide（RootHide bootstrap + ElleKit） | `iphoneos-arm64e` | [RootHide DEB](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.14.1/mks_1.14.1_roothide_iphoneos-arm64e.deb) |

## 使用

安装与越狱环境对应的完整 DEB 后，打开 MKS：

- **一键改机**：生成并保存参数，然后自动重启桌面，手机短暂黑屏。
- **恢复原机**：写入停用配置，然后自动重启桌面。
- **清理全局 Keychain**：独立确认后备份并按参考插件规则清理，不重启桌面。
- **右上角「接口文档」**：查看本机 Wi-Fi 地址、设备 UDID 路由、访问令牌与三个功能的 curl 示例，可一键复制。

HTTP 默认端口 `33237`，路径前缀 `/v1/devices/{USB_UDID}`。改机不会修改 HTTP 服务单独保存的设备编号。Bearer token 用于授权，UDID 用于路由。操作返回任务编号，查询任务确认完成；带 Idempotency-Key 的重复请求不会重复改机或清理。

## 1.14.1 真机修正

修复 iOS 上新增布尔字段被序列化为数字的问题，显式返回 JSON true/false。RootHide iPhone 已覆盖安装 1.14.1，核对 App 版本、daemon、HTTP 状态及升级前后配置校验值，桌面重启后接口复查通过。Rootless 的 1.14.1 包已构建并通过主机检查。

## 1.14 对接改进

App 的「未绑定设备 / 设备绑定」和「接口文档」可进入 USB UDID 绑定流程，重绑定会显示原值并再次确认。CLI 返回 JSON 与退出码。状态接口增量提供环境、能力和安装标识；清理回执提供稳定备份标识，故障响应增加重试及结果未知标记。v1 路由与 Bearer 认证沿用现有协议。

## 文档

- [核销系统首次对接与恢复流程](docs/integration.md)
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
python3 tests/test_http.py --scheme roothide
python3 tests/test_setup.py
python3 scripts/build.py
python3 tests/verify_packages.py
```

默认在 `dist/` 输出上表两种 DEB。两个包的 App、tweak 和 daemon 均包含 arm64 与 arm64e Mach-O。RootHide 构建首次下载并校验固定版本的官方路径 API 头文件和链接存根。

用 `--scheme rootless` 或 `--scheme roothide` 可单独构建及校验某个包。用 `python3 scripts/build.py --scheme rootless --ipa` 可另外构建不含 daemon 的独立 IPA。用 `python3 scripts/build.py --simulator` 可生成模拟器 App。

## 1.14.1 验证状态

两个 DEB 均通过主机构建、签名、包布局、载荷、Mach-O 链接和安装脚本语法检查；两种分支的 CLI、App IPC、HTTP 与故障回归通过，模拟器验证绑定交互。RootHide 已完成本次安装和桌面重启后的状态复查。三动作与 Rootless 真机验收待完成。历史真机结果及本版检查见[验证记录](docs/validation.md)。

## 1.12 修复

修复 `ProductName` 的语义错误：该字段表示系统名称（本机为 `iPhone OS`），旧版错误替换为硬件家族 `iPhone`。1.12 保留系统原值，继续通过 `ProductType` 等字段替换设备身份。新增四项回归覆盖解析映射、字符串 getter、Copy getter 和内部带类型 getter。

## 设备信息替换

App、tweak 和 daemon 共用强类型配置解析器，兼容旧版 14 段配置；覆盖 MobileGestalt、IOKit Create/Search、sysctl、系统版本字典、IDFV 及允许跟踪时的 IDFA。内部 MG hook 保留原系统的类型输出，MGGetStringAnswer 按原函数所有权返回引用；原生缺失的敏感属性保留缺失状态。

主配置位于各自越狱根目录下的 `var/lib/mks/mks.config`，使用原子写入和回读验证。停用记录具有优先权，避免旧配置重新启用。安装时在主配置不存在的情况下迁移旧 Media 配置。1.12 在改机启用状态完成 App Store 登录与重开保持验收，详见验证摘要。

Keychain 清理与用户提供的 App 清理插件使用相同的五条 SQL 和保护组规则，增加事务与一致快照备份；不同于恢复改机配置，已提交的 Keychain 删除不会因点击「恢复原机」而自动恢复。

## 1.12 设备与发布状态

已在 USB 连接的 iOS 16.3.1 rootless iPhone 删除旧包后安装 1.12，完成 App 按钮与 HTTP 的三次改机、三次恢复；实际 API 值和桌面重启均已核对，测试后恢复原参数。刷新认证进程后，在改机启用状态重新登录 App Store，并验证重开后仍保持目标账号。HTTP 清理执行在合成数据库验证，真实设备 Keychain 未在本轮删除。源码、安装产物及总文档随 1.12 同步；私人诊断、设备编号与访问令牌不纳入仓库。
