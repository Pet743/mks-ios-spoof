# MKS 1.12 验证摘要

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
