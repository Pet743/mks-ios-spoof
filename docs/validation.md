# MKS 验证摘要

**当前 1.15.12 / 128：** RootHide 无双重认证账号已完成标准改机登录与后台可见字段验收；双重认证账号仍需验证后再次提交密码。以下区分本版结果与历史结果，v1.15.4 原始产物继续保留。

## 1.15.12：RootHide 无双重认证账号验收通过

2026-11-23（Asia/Shanghai），退出旧 App Store 账号、关闭重开确认未登录，通过 MKS 正常 spoof 生成全新参数。12 个身份/商店进程自动退出后重启桌面，无手工刷新。改机保持启用，提交一次密码成功登录，关闭重开仍保持目标账号；配置和过滤文件逐字节未变，HTTP 状态为 1.15.12 / enabled=true / profileValid=true。

用户确认后台一致，并提供显示 iPhone 15 Pro Max、iOS 17.0、IMEI 827275389397075 的截图。该截图没有显示序列号，不把它写成截图独立核对过的字段。结论限于该无双重认证账号和本轮流程；双重认证账号仍在首次验证后回到未登录表单，同一身份诊断性第二次提交密码才成功。[详细复测](roothide-login-compatibility.md)。

| 检查 | 结果 |
| --- | --- |
| 核心回归 | 1094 项通过 |
| 身份答案 | Rootless 35 / RootHide 113 项通过；包含类型、白名单、原始读取重入保护、停用恢复 |
| 服务刷新 | 14 项隔离检查通过；精确进程名、PID 复用、缺失、权限、超时及退出过渡状态 |
| HTTP | Rootless / RootHide 各 61 项通过 |
| 包检查 | 两方案双架构、签名、路径、载荷、链接与过滤范围通过 |
| 基线失败复现 | 旧参数生成器 5 项失败；旧 Search 白名单实现 3 项失败；修正后通过 |
| 独立源码回滚 | 哈希恢复；原核心 1094 项、身份 Rootless 35 / RootHide 81 项通过；手机状态不变 |
| Rootless 真机登录 | 本轮未执行 |

发布沿用已测试并留存的两份 DEB，不重新生成二进制；公开 SHA-256：

- RootHide：`f12b8355eb8bf01aa9363fb6a5932c6e79d48a48e1fbb5b9433d48e89cbe97fa`
- Rootless：`8230510c03815243a0e046ca34f44e8b33b26127075b2a8ae0dca4c5777fd6d6`

本轮没有删除真实 Keychain 数据；临时探针已从手机移除。账户保存诊断只记录返回码，未将密码、验证码或令牌写入公开仓库。

## 1.15.4 RootHide：约定验收通过并固定保留

2026-11-23（Asia/Shanghai），在 1.15.3 加入 akd 单进程排除的真机对照中，首次登录及重开保持已观察到；随后用户要求重新取证，退出账号并生成全新随机参数，再次完成一次密码提交、双重认证、App Store 登录和重开保持。MKS 始终启用，登录前后配置与过滤文件字节一致。用户提供 Apple 后台设备详情截图，机型、序列号、系统版本三项与新配置一致。

1.15.4 / 120 将同一过滤行为写入发行构建：RootHide 仅排除 akd，Rootless 不变。主机复跑 1094 项核心、Rootless / RootHide 身份答案 11 / 23 项、两分支各 61 项 HTTP；两种 DEB 的双架构、签名、布局、链接、脚本和完整注入过滤列表校验均通过。此前 1.15.3 的 77 项合成 Keychain、9 项 UDP、69 项绑定检查属于历史结果，未冒充本版复跑。

RootHide 手机覆盖升级至 1.15.4，App 版本 1.15.4 / 120、daemon 状态、四份安装载荷已核对；配置、令牌、绑定、安装标识保持，任务账本解析后内容一致。具体桌面重启和账户重开结果随本轮验收记录保存。Rootless 本版仅完成主机和构建检查。

本次后台核对覆盖截图中的三项可见字段。它不证明全部请求字段、IMEI、ECID 或所有 DPP 功能等价。[实验与证据](roothide-login-investigation.md) · [DPP 差异](dpp-parity.md)。

1.15.4 升级后已再次关闭并重开 App Store，目标账号保持登录；保留配置逐字节等于本轮已通过后台核对的配置，包内过滤与已通过的临时对照语义一致。SpringBoard PID 更换、daemon PID 保持，重启后三次 HTTP 查询通过。临时传输 DEB 已移除。

1.15.4 安装包 SHA-256：

- `mks_1.15.4_roothide_iphoneos-arm64e.deb`：`80035d390a19643a441d4dbb88674cd47ae3649b2350352d1b9f95712a8f1eda`
- `mks_1.15.4_rootless_iphoneos-arm64.deb`：`7a555212dc6f93e2974391e696a47d28c610a3c2cb8da4e94f3880fe7dda93b4`

## 1.15 主机回归与 RootHide 升级

2026-11-23（Asia/Shanghai）同步参数规则改动，完成两种 DEB 构建、检查及 USB 连接的 RootHide iPhone 覆盖升级。原事件的实际登录请求仍待复现；本次增加六进程主动 API 采样，不将其标记为新 hook 修复。

| 检查 | 本版结果 |
| --- | --- |
| 改机核心 | 1094 项通过；新增生成规则、14 段导出回读与错误字段；保留配置、hook、类型、并发和恢复回归 |
| Keychain 合成数据 | 77 项通过；真实 Keychain 未执行删除 |
| UDP daemon | 9 项通过 |
| HTTP Rootless / RootHide | 各 61 项通过，版本断言为 1.15 |
| CLI / App IPC / HTTP 绑定 | 69 项通过，两种环境均覆盖 |
| 两份 DEB | 三个程序各含 arm64 / arm64e；签名、布局、载荷、链接和脚本检查通过 |
| RootHide 真机安装 | dpkg 从 1.14.1 升级到 1.15，App 1.15 / 116；四份安装文件核对通过 |
| 桌面与接口 | SpringBoard PID 更换；daemon PID 保持；重启后三次 HTTP 状态查询均为 1.15 |
| 注入加载 | 采集到新版 SpringBoard 的 MKS 1.15 构造日志；不等于 Apple 登录进程属性验收 |
| App | Instruments 启动后前台为 com.mks.spoofer，截图确认主界面和配置停用状态 |

升级前后主配置、token、device-id、installation-id 的 SHA-256 完全一致；jobs.json 在 daemon 启动时重新序列化，字节哈希改变，但解析后的 12 条任务及每个字段完全相同。升级保留原来的 `enabled:false` 和有效配置；本轮没有重新生成日常参数。临时传输 DEB 已移除，设备上的升级前状态备份保留。

App、Info.plist、注入库与包内载荷逐字节匹配。daemon 的差异经校验仅为 RootHide arm64e 的 __TEXT 节标记及对应代码页签名哈希，安装后签名验证通过。

基线 1.14.1 独立副本通过 389 项核心回归和两种 HTTP 分支各 61 项检查。1.15 的完整补丁另在独立副本逆向应用并复核，恢复 1.14.1 文件与回归结果；主工作目录和手机保持 1.15。完整命令、原始输出及哈希保存在本地诊断记录。

上述主机测试使用临时配置、合成 SQLite 数据和假重启。真机完成安装、状态保留、桌面重启和 App 打开后，另执行两轮改机/恢复与六进程主动 API 采样。未执行真实 Keychain 删除、Apple 登录或 Rootless 真机验收。[事件结论与复核流程](login-incident.md)。

安装包 SHA-256：

- `mks_1.15_roothide_iphoneos-arm64e.deb`：`81a79dc412781b4f55688b2538d664158609657dfcbc64563a325c972c7b45d1`
- `mks_1.15_rootless_iphoneos-arm64.deb`：`9a59c5927ef8cf8f9a3e609b16fa7dd5f9202615fe360c0064d42b410be0a0f5`

## 1.15 RootHide 六进程诊断

升级后进一步采样 AppStore、akd、accountsd、amsaccountsd、appstored、itunesstored。每进程 55 个读取点：合计 218 项匹配配置、24 项与基线相同的原生缺失、88 项 passthrough；0 项非空替换值不匹配。恢复后 330 项 SHA-256 读数摘要与停用基线一致。各项缺失和 passthrough 不计为替换通过，IOKit 原生空值不构成正向替换证据。

正式测试先刷新目标进程，再通过正常注入路径加载临时只读探针。五个 daemon 在各轮基线、启用和恢复期间保持 PID；AppStore 在桌面重启后重新打开。主动探针调用不等于 Apple 登录业务的实际属性调用，更不证明账户锁定原因。

两轮共生成四条新诊断任务，原有 12 条任务逐字段保留。测试后恢复原配置字节、enabled:false、授权和绑定；临时探针及传输文件已移除、采样进程已刷新，MKS 已打开。诊断构建入口另验证 RootHide、Rootless 两种双架构签名产物，未将探针加入发行 DEB。[逐进程表与复跑方法](login-incident.md)。

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
