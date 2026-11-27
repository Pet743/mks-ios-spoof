# MKS 改机

**预发布 1.16.0 / 132：** 自定义只选择 iOS 16、17 或 18，小版本、build 及其余参数自动生成并逐条执行 HTML 规则校验。保存偏好后 App 和 HTTP 共用；当前生效参数不会因预览而改变。[使用和校验依据](docs/custom-ios-version.md)。

**稳定发布 1.15.14 / 130：** 修复 RootHide 原机切换改机后的 USB 配对失效，配对服务保留原生身份且不再随改机刷新。真实 iOS 16.4.1 三轮改机/还原、18 次配对/AFC 检查通过，StoreKit 153 项读数匹配；主界面新增版本号和构建号。[修复与验收](docs/usb-trust-fix.md)。

**历史候选 1.15.13 / 129：** 修正 RootHide 应用内购买服务 `storekitd` 的注入、刷新及身份读取覆盖。真机进程内采样通过，实际付款后台判定待原应用复测。[现场及验证记录](docs/storekit-payment-investigation.md)。以下 1.15.12 为原发布记录。

**历史版本 1.15.12 / 128：** 无双重认证测试账号已按“确认退出 → MKS 正常改机 → 一次密码登录 → 重开保持”完成，用户后台核对机型、系统及 IMEI 一致。双重认证账号仍存在验证返回后未登录、需要再次提交密码的问题，本版没有宣称解决这一流程。v1.15.4 原始标签与安装包保留。[完整验收与已知问题](docs/roothide-login-compatibility.md)。

[下载 1.16.0 预发布](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.16.0) · [下载稳定版](https://github.com/Pet743/mks-ios-spoof/releases/latest) · [安装说明](docs/install.md) · [新设备：Mac + USB 快速安装 RootHide](docs/install-usb-roothide.md) · [DPP 对照与复测记录](docs/roothide-login-compatibility.md)。

自用 iOS 越狱工具，当前预发布版本 **1.16.0**（稳定发布为 **1.15.14**），提供 Rootless 和 RootHide 两个安装包。提供一键改机、恢复原机、全局 Keychain 清理，以及同一 Wi-Fi 内的 HTTP 调用。无卡密、激活或远程授权。

| 越狱环境 | DEB 架构 | 下载 |
| --- | --- | --- |
| Rootless（固定 `/var/jb`） | `iphoneos-arm64` | [Rootless DEB](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.16.0/mks_1.16.0_rootless_iphoneos-arm64.deb) |
| RootHide（RootHide bootstrap + ElleKit） | `iphoneos-arm64e` | [RootHide DEB](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.16.0/mks_1.16.0_roothide_iphoneos-arm64e.deb) |

## 1.16.0 更新与已知问题

只选择 iOS 16、17、18，小版本和 build 按离线固件表配套生成，其他参数自动生成。App 与 HTTP 共用大版本偏好；升级保留当前参数和绑定。详见[版本说明](docs/releases/v1.16.0.md)。

**应用内购问题尚未解决。** 用户在同一台 RootHide 设备报告还原后可购买、启用改机后购买失败。本版未通过改机状态下的实际内购验收；本地 HTML 规则校验通过不代表 Apple 登录、购买或审核通过。具体失败原因仍未定位，因此本版标记为预发布。

## 1.15.12 更新

RootHide 改机/恢复时自动刷新认证和商店服务，再重启桌面，避免只重启桌面后仍使用上一轮进程缓存；生成器使用对应的 iPhone 15 Pro Max / iOS 17.0 / build 21A329 元组；IOKit Search 白名单以外的字段保留原生值，并对照 DPP 增加原始 MG 初始化读取。Rootless 原有生成、刷新和 hook 行为保留。

本轮 RootHide 无双重认证账号已通过实际登录、重开保持及后台可见字段核对。Rootless 完成构建与主机检查，未做本轮真机登录验收；双重认证账号的问题见上文。安装包与手机已测试的 1.15.12 产物相同。

## 1.15.4：已保留的 RootHide 验收版本

2026-11-23 在改机启用时完成一次密码提交及双重认证，App Store 登录成功，关闭并重开后仍保持登录；用户提供的 Apple 后台设备详情中，机型、序列号和系统版本与该轮随机参数逐项一致。该结果满足本次约定的验收条件。

RootHide 包仅排除 akd 的直接注入，保留 AppStore、accountsd、amsaccountsd、appstored、itunesstored 的身份替换；Rootless 保持原有过滤范围。版本 **1.15.4 / 120** 固定保存这一行为；后续 DPP 对齐工作另行迭代。[验收与历史候选](docs/roothide-login-investigation.md) · [DPP 功能差异](docs/dpp-parity.md) · [保留版本下载](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.15.4)。

## 使用

使用 Sileo 等越狱包管理器安装与环境对应的完整 DEB，依赖为本环境的 ElleKit；RootHide 还需要 RootHide 核心包。DEB 包含 MKS App、注入库和后台服务，安装后打开桌面的 MKS。巨魔商店单装独立 IPA 缺少注入库和后台服务，完整功能需要安装 DEB。[具体步骤](docs/install.md)。

- **一键改机**：生成并保存参数，然后自动重启桌面，手机短暂黑屏。
- **自定义 iOS 版本**：选择 16、17、18，预览后应用，或保存为后续 App／HTTP 改机偏好。
- **恢复原机**：写入停用配置，然后自动重启桌面。
- **清理全局 Keychain**：独立确认后备份并按参考插件规则清理，不重启桌面。
- **右上角「接口文档」**：查看本机 Wi-Fi 地址、设备 UDID 路由、访问令牌与三个功能的 curl 示例，可一键复制。

HTTP 默认端口 `33237`，路径前缀 `/v1/devices/{USB_UDID}`。改机不会修改 HTTP 服务单独保存的设备编号。Bearer token 用于授权，UDID 用于路由。操作返回任务编号，查询任务确认完成；带 Idempotency-Key 的重复请求不会重复改机或清理。

## 1.15 参数规则与展示

一键改机默认生成 iPhone 15 Pro Max（`iPhone16,2`）、美国地区参数，遵循本地 HTML 的 14 段格式规则；App 展示校验结果、可复制参数行与 JSON。App 和 HTTP daemon 保存新生成参数前均执行校验，失败时不写入、不重启桌面。旧配置继续兼容读取，覆盖升级保留原有参数。

这些检查验证字符串格式及部分字段关系；随机机型、主板、芯片、iOS 与 build 不代表真实硬件组合，也不是 Apple 认证。1.15 没有修改 Apple 登录进程的注入和缓存逻辑。1.15 当时刷新六个目标进程后，218 项 API 读数匹配配置、330 项恢复比对一致；1.15.4 的实际登录及后台核对见上文。[参数规则](docs/profile-rules.md) · [登录事件核查结论](docs/login-incident.md)

## 1.14.1 真机修正

修复 iOS 上新增布尔字段被序列化为数字的问题，显式返回 JSON true/false。RootHide iPhone 已覆盖安装 1.14.1，核对 App 版本、daemon、HTTP 状态及升级前后配置校验值，桌面重启后接口复查通过。Rootless 的 1.14.1 包已构建并通过主机检查。

## 1.14 对接改进

App 的「未绑定设备 / 设备绑定」和「接口文档」可进入 USB UDID 绑定流程，重绑定会显示原值并再次确认。CLI 返回 JSON 与退出码。状态接口增量提供环境、能力和安装标识；清理回执提供稳定备份标识，故障响应增加重试及结果未知标记。v1 路由与 Bearer 认证沿用现有协议。

## 文档

- [核销系统首次对接与恢复流程](docs/integration.md)
- [HTTP API、curl 与 Python 示例](docs/http-api.md)
- [安装、设备编号配置与升级](docs/install.md)
- [全局 Keychain 规则及 REA/Craft Anything 分析](docs/keychain-cleaner.md)
- [1.15 参数生成、14 段格式与校验](docs/profile-rules.md)
- [Apple ID 登录事件与 1.15 结论](docs/login-incident.md)
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

## 1.15 验证状态

本版 1094 项核心回归及 HTTP、Keychain、绑定回归通过，两份 DEB 校验通过。RootHide 已覆盖安装 1.15 / 116，桌面重启后接口与 App 正常，配置保持停用。详细结果见[验证记录](docs/validation.md)。历史版本的 Apple 账户登录验收不等于 1.15 已通过登录验证；本轮进程内主动采样不等于已验证 Apple 实际登录请求。

## 1.12 修复

修复 `ProductName` 的语义错误：该字段表示系统名称（本机为 `iPhone OS`），旧版错误替换为硬件家族 `iPhone`。1.12 保留系统原值，继续通过 `ProductType` 等字段替换设备身份。新增四项回归覆盖解析映射、字符串 getter、Copy getter 和内部带类型 getter。

## 设备信息替换

App、tweak 和 daemon 共用强类型配置解析器，兼容旧版 14 段配置；覆盖 MobileGestalt、IOKit Create/Search、sysctl、系统版本字典、IDFV 及允许跟踪时的 IDFA。内部 MG hook 保留原系统的类型输出，MGGetStringAnswer 按原函数所有权返回引用；原生缺失的敏感属性保留缺失状态。

主配置位于各自越狱根目录下的 `var/lib/mks/mks.config`，使用原子写入和回读验证。停用记录具有优先权，避免旧配置重新启用。安装时在主配置不存在的情况下迁移旧 Media 配置。1.12 在改机启用状态完成 App Store 登录与重开保持验收，详见验证摘要。

Keychain 清理与用户提供的 App 清理插件使用相同的五条 SQL 和保护组规则，增加事务与一致快照备份；不同于恢复改机配置，已提交的 Keychain 删除不会因点击「恢复原机」而自动恢复。

## 1.12 设备与发布状态

已在 USB 连接的 iOS 16.3.1 rootless iPhone 删除旧包后安装 1.12，完成 App 按钮与 HTTP 的三次改机、三次恢复；实际 API 值和桌面重启均已核对，测试后恢复原参数。刷新认证进程后，在改机启用状态重新登录 App Store，并验证重开后仍保持目标账号。HTTP 清理执行在合成数据库验证，真实设备 Keychain 未在本轮删除。源码、安装产物及总文档随 1.12 同步；私人诊断、设备编号与访问令牌不纳入仓库。
