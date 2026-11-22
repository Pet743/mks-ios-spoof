# MKS 验证摘要

## 1.14.1 安装验收

2026-11-22 在 USB 连接的 RootHide iPhone 上完成 1.13 → 1.14 → 1.14.1 覆盖升级。1.14 真机暴露新增布尔字段被序列化为数字的问题，1.14.1 已显式转换为 BOOL。主机 HTTP 两种分支各 61 项、合成 Keychain 77 项及两份包校验通过。

- dpkg 确认 1.14.1 / iphoneos-arm64e，App Info.plist 确认 1.14.1 / 115，uicache 注册路径对应本环境安装根目录。
- App 主程序、Info.plist 与注入库逐字节核对。daemon 的 40 字节差异仅涉及 RootHide 对 arm64e 的 __TEXT 节标记及其对应 SHA-256 代码页哈希，安装后签名验证通过。
- HTTP 版本为 1.14.1，设备编号与 USB 一致，deviceConfigured 严格为布尔 true，环境为 roothide，API v1 和三项能力存在。
- 桌面重启后 SpringBoard PID 更换，daemon PID 保持，三次 HTTP 状态查询成功。
- 配置、token、device-id 与 jobs.json 的升级前后 SHA-256 一致。1.14 生成的 installation-id 在 1.14.1 升级及桌面重启后保持一致。

本轮安装验收使用状态读取和桌面重启。三动作、真实 Keychain 专用数据及 Rootless 真机验收待完成。设备凭据、编号和状态文件只保存在本地诊断目录。

## 1.14 本机检查

2026-11-22（Asia/Shanghai）完成本轮改进与本地验收。

| 检查 | 结果 |
| --- | --- |
| 改机核心 | 389 项通过，覆盖字段类型、配置、并发与恢复 |
| Keychain 合成数据 | 77 项通过，覆盖备份标识、备份失败不删除、事务回滚和注入的 COMMIT 失败 |
| UDP daemon | 9 项通过 |
| HTTP Rootless / RootHide | 各 61 项通过，覆盖未绑定、认证、状态增量字段、旧 Key/job、持久化故障及账本损坏 |
| CLI / App IPC / HTTP 绑定 | 69 项通过，包含两种构建分支、实际 macOS 非 root CLI 失败、权限/格式/锁、原值比较、路由生效和令牌/账本保留 |
| 两份 DEB | arm64 / arm64e，签名、布局、链接、脚本、载荷与版本检查通过 |
| iPhone 16e 模拟器 | 未绑定入口、UDID 输入、错误反馈、绑定确认及服务未就绪提示通过 |

主机测试只访问临时配置、合成 SQLite 数据和假重启记录。RootHide 的 macOS 路径 API 使用合成 shim，两份 iOS DEB 使用各自正式路径与官方 RootHide SDK 构建。主机正向配置测试模拟 root UID 并省略 root 文件所有权设置；另行编译未开启测试宏的 CLI，验证实际非 root 执行返回 JSON permission_denied 与退出码 1。真实 iOS root 权限与 App 进程路径校验待真机验收。

本轮可见设备状态为 unavailable，1.14 的真机安装、App 注册、注入、三动作、SpringBoard 重启和 USB 中断恢复均待设备验证。真实 Keychain 清理需专用测试数据。[对接验收流程](integration.md)

复跑本轮检查可使用以下命令。

```sh
python3 tests/run_host_tests.py
python3 tests/test_keychain.py
python3 tests/test_daemon.py
python3 tests/test_http.py
python3 tests/test_http.py --scheme roothide
python3 tests/test_setup.py
python3 scripts/build.py
python3 tests/verify_packages.py
python3 scripts/build.py --simulator
```

## 1.13 本机检查

2026-11-22（Asia/Shanghai）完成两个版本的构建和本机验证。

| 检查 | Rootless | RootHide |
| --- | --- | --- |
| DEB 架构 | `iphoneos-arm64` | `iphoneos-arm64e` |
| 包布局 | `/var/jb` | bootstrap 根目录 |
| App、插件与 daemon | arm64 / arm64e，两种切片的签名和路径检查通过 | arm64 / arm64e，两种切片均链接 RootHide 路径库，签名和路径检查通过 |
| 安装脚本与 LaunchDaemon | 包中四个脚本语法及预期路径通过 | 包中四个脚本语法及 bootstrap 路径通过 |

主机回归通过 389 项改机、65 项合成 Keychain、9 项 UDP 和 39 项 HTTP 检查。本轮没有连接 iPhone。1.13 的真机安装、App 注册、注入与 daemon 运行均待设备验证。

## 1.12 历史验收

日期：2026-11-21（Asia/Shanghai）。此文件为公开摘要，私人设备编号、地址、令牌、配置、日志和截图不上传。

## 本机检查

| 检查 | 结果 |
| --- | --- |
| 原改机 Objective-C 回归 | 389 项通过：字段类型、配置更新、返回值所有权、sysctl、并发及停用恢复 |
| Keychain 合成数据库 | 65 项通过：与样本五条 SQL 的结果一致、受保护/NULL 分组、WAL 快照、锁、事务回滚、备份权限和 Unix socket 校验 |
| UDP daemon | 9 项通过：完整命令与实际配置状态，拒绝 UDP 清理命令 |
| HTTP 服务 | 39 项通过：Bearer、设备路由、请求解析、任务、并发幂等、临时配置与假重启、合成清理、daemon 重启中断恢复、损坏任务文件拒绝启动 |
| 构建与安装包 | arm64 + arm64e，三个程序签名校验通过；DEB/IPA 载荷、权限、注入过滤和版本检查通过 |
| 模拟器 UI（1.11 历史验收） | 右上角接口文档可打开，展示三个 curl 操作与任务查询，复制反馈已观察 |

HTTP 测试运行真实监听器和真实操作代码，只有桌面重启替换为临时日志写入；清理使用合成 SQLite 数据，不访问 Mac 或 iPhone 的真实 Keychain。

## 1.12 问题定位与修复

真机对照发现原生 `MGCopyAnswer("ProductName")` 返回 `iPhone OS`，旧 MKS 在启用改机后返回 `iPhone`。该字段是系统名称，不能从硬件家族推导。1.12 去掉此替换，让所有 MobileGestalt getter 保留系统原值。新增四项测试在旧映射下全部失败，修复后 389 项回归全部通过。

## 真机接口

1.12 本轮使用 USB 转发读取并调用服务；同一 Wi-Fi 的接口可用性和重复 Key 去重另有 1.11 历史验收：

- 设备旧包已卸载后安装 1.12，App/tweak/daemon 文件与本地构建逐字节匹配；App 注册版本为 1.12 / 112。
- GET 状态成功，设备路由与安装时确认的 USB 标识一致。
- POST 改机与恢复均先返回 202/queued，随后任务 succeeded；主配置 enabled 状态对应，实际 SpringBoard PID 更换。
- 相同 Idempotency-Key 重发返回原任务编号，没有重复执行（1.11 真机历史验收，1.12 主机 HTTP 回归再次覆盖）。
- 清理请求缺少 confirm 返回 400；真机 Keychain 未执行删除。
- 测试结束后将手机参数恢复到测试前原文件，并重启桌面；没有为接口测试更换用户日常参数。

## 1.12 真机改机/恢复复测

通过 App 按钮执行一轮恢复/改机，再在 MKS App 已关闭时通过 HTTP 执行两轮恢复/改机，合计六次操作。每次均核对实际 SpringBoard PID 更换、daemon PID 保持、磁盘配置与 HTTP 状态一致。一个常驻探针直接加载设备安装的 MKS dylib，并在同一进程中读取状态变化：

- 每组改机参数核对 27 个可用 getter/字段断言，覆盖随机标识、机型和系统信息，抽查机型包含 iPhone14,7 与 iPhone15,2。
- 三次恢复均核对 MobileGestalt Copy、String、两种 sysctl、系统版本字典和 IOKit 属性恢复至同一探针注入前的原始值，未读到旧改机参数。
- 启用状态下 `ProductName` 保持 `iPhone OS`。原生缺失的 IMEI/MEID 等字段仍按既有行为保留缺失。
- 完成测试后逐字节恢复测试前的启用配置。

## App 关闭与桌面重启专项复测（1.11 历史记录）

2026-11-20 在同一台 1.11 rootless iPhone 上追加三轮：

1. 启动 MKS 后强制终止，确认 MKS App 进程已消失，HTTP 状态查询成功。
2. App 不运行时提交一次 HTTP 改机，任务 succeeded，实际桌面 PID 更换；随后三次状态 GET 均为 200。
3. 继续提交一次 HTTP 恢复，任务 succeeded，实际桌面 PID 再次更换；随后三次状态 GET 均为 200。

总计六次改机/恢复 POST 成功、六次真实桌面重启、重启后 18 次状态 GET 成功，daemon PID 在所有步骤中保持不变，MKS App 没有被重新启动。最后恢复测试前原配置。未执行 Keychain 清理，未测试整机重启或退出越狱后的可用性。

## 1.12 App Store 登录复测

新版安装并刷新认证进程后，先核对现有目标账号，再在 App Store 退出该媒体账号并用同一账号重新登录。测试期间 `enabled=true`，当前配置与测试前保存的参数逐字节一致。观察到登录后的目标账号和“登出”按钮；强制关闭并重新打开 App Store 后再次核对账号仍匹配。该次提交未出现额外系统密码确认页；旧版本次也曾在补完系统确认后登录成功，因此没有把 1.12 的成功归因于单一字段修复。

手机仅注册一份 `com.mks.spoofer`，版本 `1.12`、构建 `112`。卸载旧包后曾确认旧 App、dylib、daemon 文件均已移除，再安装新版，核对三个二进制、过滤文件、配置、令牌与设备路由。部分认证 daemon 在第一次 TERM 后仍保留原 PID，随后显式刷新并核对更换，再做上述重新登录测试。

## 覆盖边界

Apple 账户登录单独通过账户页与重开 App Store 的结果验收；接口响应和参数变化不作为登录成功的替代证据。上述结果覆盖本机 iOS 16.3.1 rootless 环境，未证明全部 iOS 版本或私有 API 一致。全局清理已按样本规则完成，但真实设备清理和备份恢复仍待独立验收。HTTP 任务的重启成功字段是命令结果，本轮另以桌面 PID 验证；调用方也应核对实际设备恢复。

首次部署需将真实 USB UDID 配置到 root-owned device-id，路由标识独立于随机改机值。当前单设备部署的编号由安装过程核对，接口不提供硬件身份认证或自动发现跨设备路由的承诺。

## 复跑

```sh
python3 tests/run_host_tests.py
python3 tests/test_keychain.py
python3 tests/test_daemon.py
python3 tests/test_http.py
python3 scripts/build.py
python3 tests/verify_packages.py
```
