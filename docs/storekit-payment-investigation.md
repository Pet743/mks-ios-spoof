# RootHide StoreKit 身份覆盖修正（1.15.13 / 129）

此候选修正应用内购买服务的身份读取覆盖；实际付款及后台设备判定仍需在原应用复测。上游源码基线为 `4511fff5d3682a9f0980a50863660094a21a061c`，本地分支为 `codex/storekit-identity-coverage`。

## 现场证据

2026-11-26，指定 USB 设备运行 iOS 16.4.1 / RootHide，安装 MKS 1.15.12，配置启用。App Store 和 StoreKit 使用独立进程。设备过滤文件缺少 `storekitd`，自动刷新名单也缺少它；首次检查时它的 PID 为 853。

只读探针在原过滤范围下启动 StoreKit 后，确认配置可读且有效，但 `mksLoaded=false`。MG Copy/String 的机型、系统、构建号、序列号读取与当前配置不符，IMEI 读取缺失；sysctl 四项及平台 UUID 也不匹配。探针只记录字段名、匹配状态与摘要，不记录账号或付款凭证。

## 改动

- RootHide 过滤和刷新名单加入 `storekitd`。
- 该进程安装已有的 MG String、sysctl、系统版本字典读取钩子。
- 该进程的 IOKit Create/Search 对原生存在的 UUID、serial-number 应用配置映射，保持原生返回类型和所有权；board-id 保持原生二进制值。
- App、daemon 和注入日志标识更新为 1.15.13 / 129。

认证服务的现有读取策略和 Rootless 过滤模板沿用。配置没有重新生成，Apple ID 会话及 Keychain 没有被清理。

## 验证

基线回归显示 RootHide 缺少 StoreKit 注入，刷新测试六项中四项失败。修正后覆盖及刷新测试通过；核心 1094 项、身份答案 Rootless 50 项 / RootHide 148 项、进程刷新 14 项、RootHide HTTP 61 项均通过。RootHide DEB 的 arm64/arm64e、签名、链接、路径及脚本检查通过。

最终真机 StoreKit PID 1849，配置可读、有效且 `mksLoaded=true`。与基线可比的 38 项读数由 0 项匹配变为全部匹配；扩展采样中 51 项有配置预期的答案全部匹配，其余 7 项为保留原生行为，另有 1 项进程元数据。采样是进程内主动读取，不代表已经核验 Apple 实际付款请求或服务端判定。

本地 `VERIFICATION.txt` 保存命令、输入、原始输出、退出状态、文件哈希及原机备份位置。回滚在另一份源码副本验证，恢复原始哈希及原覆盖缺口；另核验原机七个包文件的备份。实际设备继续保留修正版本。
