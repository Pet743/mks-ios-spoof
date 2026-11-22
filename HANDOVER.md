# MKS 项目交接总文档

更新日期：2026-11-23（Asia/Shanghai）。当前交付版本 **1.15**。

## 1.15 交付与未结事项

本版同步此前未提交的参数生成、14 段展示及 App/daemon 保存前规则校验。默认 `iPhone16,2`、`LL/A`；序列号两处一致、IMEI2 是 IMEI 的前 14 位、芯片输出限于 HTML 校验接受的 T7000–T8999。测试修正了把合法的 D73AP 当作错误样例的问题，增加格式导出回读检查；HTTP 版本断言同步为 1.15。详细字段与兼容性见[参数规则](docs/profile-rules.md)，本次测试、安装与状态保留结果见[验证记录](docs/validation.md)。

Apple ID 原事件的实际登录请求仍为未知：本版 hook 仅更新日志版本号，注入过滤、缓存读取、登录 daemon 刷新未新增修复。本轮另以临时探针完成六进程主动 API 采样：218 项匹配、24 项原生缺失、88 项 passthrough；330 项恢复摘要一致。配置合法、任务 succeeded 和桌面重启不证明登录进程读取一致。公开仓库仅记录脱敏结论，原报告及凭据留在本机。[事件核查](docs/login-incident.md)。

RootHide 手机已从 1.14.1 覆盖升级至 1.15 / 116，桌面重启后三次状态查询通过，App 已打开。主配置、授权、设备绑定和安装标识原样保留；12 条任务的 JSON 内容一致，重序列化导致账本字节哈希改变。随后完成两轮真机改机/恢复诊断，逐字节恢复原配置并保持停用，原 12 条任务保留并新增 4 条诊断动作，临时探针已移除，真实 Keychain 未清理。

发行入口：[v1.15](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.15)。

## 1.14.1 真机安装与字段修正

RootHide iPhone 已覆盖安装 1.14.1 / 115，状态接口、App 注册、文件载荷与桌面重启后的三次查询通过。1.14 真机发现 deviceConfigured 的 JSON 类型为数字，已在 1.14.1 显式使用 BOOL，并同步修正清理回执相关布尔表达式。配置、授权和幂等账本校验值保持一致。详细结果见 [验证记录](docs/validation.md)，安装包见 [v1.14.1](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.14.1)。

## 1.14 对接改进

App 新增本地 USB UDID 绑定，重绑定比较用户确认的原值，CLI 输出 JSON 与可靠退出码。状态接口增加 apiVersion、deviceConfigured、environment、capabilities 和 installationId。清理回执增加 backupId、backupCreated 和 backupFormatVersion。任务持久化失败后拒绝新操作，既有 job 可继续查询；损坏账本保持原文件并拒绝启动 HTTP listener。

本版已通过 Rootless / RootHide 两个分支的主机故障回归和模拟器绑定交互。真机部署及三动作验收待完成。安装包见 [v1.14](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.14)，对接方优先阅读 [首次接入与恢复流程](docs/integration.md) 和 [HTTP 协议](docs/http-api.md)。

## 1.13 双发行版历史

- Rootless DEB 使用 `iphoneos-arm64` 和固定的 `/var/jb`。
- RootHide DEB 使用 `iphoneos-arm64e`，安装脚本运行于 bootstrap 路径环境，程序通过官方 `jbroot()` 解析越狱文件路径。
- 同一越狱环境内升级会复用已有配置、HTTP 状态和 Keychain 备份目录。两种环境切换时各自使用自己的数据目录。
- 两个 DEB 已通过本机构建和验证。1.13 真机安装与注入待验证。下载见 [v1.13](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.13)，[安装步骤](docs/install.md)。

## 功能与历史真机验收

| 功能 | 当前实现与证据 |
| --- | --- |
| 一键改机 | App 按钮与 HTTP 真机复测；27 项 getter/字段断言匹配，常驻进程自动读取新配置 |
| 恢复原机 | 三次真机恢复；六类 API 与注入前原始结果一致，未读取到旧改机参数；实际桌面重启 |
| 全局 Keychain 清理 | REA + Craft Anything 分析样本，复刻五条 SQL 与保护组；65 项合成数据库检查通过；本轮未删除真实 Keychain |
| HTTP 对接 | 局域网端口 33237，USB UDID 路由＋Bearer token，持久化任务、幂等 Key、状态查询 |
| App 内文档 | 右上角「接口文档」，显示地址/令牌/示例，可复制；模拟器验证导航和复制，真机安装后核对入口 |
| 手机更新 | 已删除旧包后通过 USB 安装 1.12；程序载荷核对一致；测试后恢复原参数 |
| Apple 账户登录 | 1.11 曾经系统密码确认完成登录；1.12 刷新认证进程后退出并重新登录成功，重开后目标账户仍在 |

## 主要修复历史

HTTP 生命周期专项复测：1.11 真机三轮“启动 App → 强制终止并确认进程消失 → HTTP 改机 → HTTP 恢复”，合计六次操作均成功且桌面 PID 更换，重启后的 18 次状态查询成功，daemon PID 始终不变。该结论适用于 App 关闭和 SpringBoard 重启；整机重启、越狱失效或 daemon 停止不在已验证范围。测试后恢复原参数。

1. 共享配置、类型和所有权：统一 App/tweak/daemon 解析；内部 MG 的第二参数是真实 32 位类型输出；替换答案时保留原系统元数据。MGGetStringAnswer 需为调用方提供持有引用，防止 App Store 释放后破坏配置字符串。
2. 沙箱可读性：旧 `/var/mobile/Media/mks.config` 在多个登录进程中被拒绝，1.9 改为 `/var/jb/var/lib/mks/mks.config` 并验证原子更新与停用行为。
3. 进程残留：旧 DPP/mkscore 虽已从磁盘卸载，长时间运行的登录 daemon 仍保留内存映射；刷新进程后分别核对磁盘文件、模块和接口结果，不能仅看安装状态。
4. Keychain：App 清理样本实际通过 SQLite DELETE 清理全局数据。独立 fixKeychain 方法没有在按钮回调里执行，依赖的外部库也不在样本包中；MKS 不增加该注入或自动重启 securityd。
5. 1.11：三个操作暴露为 HTTP 任务；修改/恢复完成保存后重启桌面。UDID 单独保存作为路由，访问令牌承担授权。任务持久化、幂等去重，daemon 重启不自动重放未完成任务。

6. 1.12：真机发现 `ProductName` 被误写为设备家族（`iPhone`），已改为保留系统名称（本机为 `iPhone OS`）。新增四项回归先验证旧映射失败，再验证修复通过；总计 389 项改机回归、65 项合成 Keychain、9 项 UDP 和 39 项 HTTP 检查通过。修复前后各完成六次真机改机/恢复操作。该字段错误与历史登录失败的因果关系尚未建立。

## 对接文档

- [README 总览](README.md)
- [HTTP API 与 curl/Python 示例](docs/http-api.md)
- [安装和设备编号配置](docs/install.md)
- [清理范围、保护组与备份](docs/keychain-cleaner.md)
- [1.15 参数规则](docs/profile-rules.md)
- [Apple ID 事件结论与诊断步骤](docs/login-incident.md)
- [公开验证摘要](docs/validation.md)
- [DPP 静态分析与限制](docs/dpp-analysis.md)

## 状态边界

接口参数变化、HTTP 202 或命令退出 0 均不等于 Apple 认证成功。HTTP 202 只代表任务入队；需查询终态。改机与恢复的重启命令结果已另用真机桌面 PID 更换验证。各进程原生为空的敏感字段仍保留空值，不能声称每条认证信息均已替换。

Keychain 操作的备份与事务失败回滚已有合成数据库验证，真实设备备份恢复尚未验收。源码回滚不会恢复手机上的配置、账号或已删除 Keychain。

## 1.12 发布

发行标签：[v1.12](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.12)。完整包为 `dist/mks_1.12.deb`，独立 App 为 `dist/MKS-spoofer-1.12.ipa`。安装和验证步骤见下列文档；真实 Keychain 未在本轮清理。

## 私人诊断与发布

本地 `diagnostics/` 保存原包、REA/Craft JSON、设备检查、完整测试和截图，不提交。仓库只保留源码、合成测试输入、公开说明和当前安装产物；访问令牌、真实设备编号、账号、密码、验证码和私人配置均不上传。旧仓库历史没有在本轮重写。

1.11 源码、完整 DEB/IPA 和上述总文档已同步到默认 `main` 分支，代码提交为 `84e035396c19b5a56caa54662111c33c1556c2ac`，发行标签为 [v1.11](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.11)。本文件后续的发布记录更新不改变该代码与二进制版本。

发行附件 SHA-256：DEB `7ee0424aa0a4731f4c6c09707509fae3386c13f06f2f43c199cb3cb2f1db56e0`；IPA `eb09d81fd087060a47b40aa6141ee15de752670d8592d28074fcffe58b2031f0`。

1.12 真机重新安装已完成：先执行 `dpkg -r com.mks.spoof` 并核对旧文件移除，再安装完整 1.12 包。当前仅注册一份 App，版本 1.12 / 112；保留测试前启用的改机参数、HTTP 令牌及路由。卸载重装保留配置，所以不等于恢复原机。认证 daemon 曾出现 TERM 后 PID 未变化，已显式刷新并在随后完成重新登录验收。

1.12 发行附件 SHA-256：DEB `6fb5653c4231a42705af34bfbe618b2153dd50ba81f1ebceee3f044a392af4bf`；IPA `0c283a650719e3b713a8426d8915e07c2e5a1a7621a70f65e3311a24492d3b0e`。
