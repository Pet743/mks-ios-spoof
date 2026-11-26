# RootHide USB 信任修复：1.15.14 / 130

2026-11-26，真实 iPhone 14 Pro / iOS 16.4.1 / RootHide 0.0.9 在 MKS 1.15.13 上复现：原机模式重新信任 Mac 后，StartSession、TLS 和 AFC 全部通过；仅执行改机，约两秒后设备公钥摘要变化，原配对持续返回 `InvalidHostID`。期间没有 USB 拔出，采集程序没有执行 Pair/Unpair 或写配对记录。此前“改机→改机”没有复现，不代表原机切换路径通过。

## 修改

- RootHide 注入名单移除 `lockdownd`；构造函数也精确排除这个进程，避免旧过滤配置加载后继续安装身份钩子。
- 改机和还原不再刷新 `lockdownd`，让 USB 配对持续使用原生身份及现有进程。
- 保留 App Store、认证服务和 StoreKit 的覆盖。Rootless 过滤模板及原行为保留。
- 主界面标题下显示从安装包读取的版本和构建号，本版为 `v1.15.14 · 130`。

升级时只刷新了一次已加载旧钩子的 lockdownd，随后日常切换不再刷新它。失效的旧配对未被自动恢复；用户在原机模式重新确认一次信任，建立修复后的验收基线。

## 验证

新增隔离回归在旧 RootHide 源码上 15 项中 3 项失败；修复后 RootHide 15 项、Rootless 10 项通过。核心 1094 项、身份答案 RootHide 148 / Rootless 50 项、进程刷新 14 项、StoreKit 刷新 6 项、HTTP 双环境各 61 项及双环境安装包校验通过。

真实 16.4.1 连续三轮 spoof→restore，共六次切换、18 次 StartSession/TLS/AFC 检查成功。同一份 Mac 配对记录、设备公钥、USB 原生 UDID 和 lockdownd PID 全程未变；启用时随机配置 UDID 与 USB 原生 UDID 不同。三轮 StoreKit 每轮 51 项配置读数匹配，共 153 项。开发者服务实际读取 SpringBoard PID。随后仅追加版本 UI 并重新构建安装，真机截图已核对。

另一台 16.0.2 当前保持 MKS 1.15.12，配对摘要与早期基线一致且 AFC 成功。其 profile 与早期快照不同，因此没有宣称它的配置全程未变；本轮操作脚本均固定目标 201E，没有对另一台提交修改。

真实 Keychain 清理未执行，独立清理操作未在本轮验收。StoreKit 是进程内读取验证，没有新增实际付款或 Apple 后台判定结论。公钥变化与 HostID 被拒已经观察，iOS 内部具体密钥创建/读取函数尚未追踪。

## 本地证据

分支 `codex/usb-trust-preservation`，保留此前 StoreKit 改动。原始复现位于 `diagnostics/usb-trust-20261126/live-20261126-231252/REPRODUCED.json`；修复验收位于 `usb-trust-fix/CYCLES.json`、`COMMERCE-PROBE-SUMMARY.json`、`DEVELOPER-SERVICE.json`。1.15.13 源码和设备七个原始安装文件已备份；独立副本回滚结果、命令、哈希及限制见任务的 `usb-trust-fix/VERIFICATION.txt`。配对证书、私钥和访问令牌原文不进入公开仓库。
