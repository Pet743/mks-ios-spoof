# MKS 1.11 验证摘要

日期：2026-11-20（Asia/Shanghai）。此文件为公开摘要，私人设备编号、地址、令牌、配置、日志和截图不上传。

## 本机检查

| 检查 | 结果 |
| --- | --- |
| 原改机 Objective-C 回归 | 385 项通过：字段类型、配置更新、返回值所有权、sysctl、并发及停用恢复 |
| Keychain 合成数据库 | 65 项通过：与样本五条 SQL 的结果一致、受保护/NULL 分组、WAL 快照、锁、事务回滚、备份权限和 Unix socket 校验 |
| UDP daemon | 9 项通过：完整命令与实际配置状态，拒绝 UDP 清理命令 |
| HTTP 服务 | 39 项通过：Bearer、设备路由、请求解析、任务、并发幂等、临时配置与假重启、合成清理、daemon 重启中断恢复、损坏任务文件拒绝启动 |
| 构建与安装包 | arm64 + arm64e，三个程序签名校验通过；DEB/IPA 载荷、权限、注入过滤和版本检查通过 |
| 模拟器 UI | 右上角接口文档可打开，展示三个 curl 操作与任务查询，复制反馈已观察 |

HTTP 测试运行真实监听器和真实操作代码，只有桌面重启替换为临时日志写入；清理使用合成 SQLite 数据，不访问 Mac 或 iPhone 的真实 Keychain。

## 真机接口

在同一 Wi-Fi 由 Mac 调用 USB 连接的 rootless iPhone：

- 设备包版本为 1.11，App/tweak/daemon 文件与本地构建逐字节匹配。
- GET 状态成功，设备路由与安装时确认的 USB 标识一致。
- POST 改机与恢复均先返回 202/queued，随后任务 succeeded；主配置 enabled 状态对应，实际 SpringBoard PID 更换。
- 相同 Idempotency-Key 重发返回原任务编号，没有重复执行。
- 清理请求缺少 confirm 返回 400；真机 Keychain 未执行删除。
- 测试结束后将手机参数恢复到测试前原文件，并重启桌面；没有为接口测试更换用户日常参数。

## 覆盖边界

上述结果不证明 Apple 账户登录成功，也不证明全部 iOS 版本或私有 API 一致。全局清理已按样本规则完成，但真实设备清理和备份恢复仍待独立验收。HTTP 任务的重启成功字段是命令结果，本轮另以桌面 PID 验证；调用方也应核对实际设备恢复。

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
