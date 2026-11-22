# RootHide Apple ID 登录故障调查（未通过验收）

更新：2026-11-23（Asia/Shanghai）。稳定分支当前为 1.15；本调查分支代码及手机测试包为 **1.15.3 / 119**。它是实验版本，不是已完成登录修复的发行版。Rootless 不作为本次故障对象，保留其既有 hook 行为。

## 必须同时满足的验收条件

1. MKS 改机保持启用，App Store 完成目标 Apple ID 登录；本轮测试采用一次密码提交，双重认证单独完成，不以重复补输密码替代通过。
2. Apple 后台对应设备的机型、序列号等可见字段与本轮改机参数一致。

配置合法、HTTP succeeded、进程读数与配置匹配、App Store 显示账户，以及使用原生认证链路成功登录，各自都不能单独替代上述两项验收。

用户已确认 Rootless MKS 与 RootHide DPP 曾满足后台设备字段核对要求。本轮尚未独立重做该参考版本的服务端对照；以下事实只描述已经保存的工具与真机证据。

## 已实际运行的 DPP 分析

从 [1024.zone 软件源](http://1024.zone.id) 的 Packages 索引下载并核验 DPP 2.1：RootHide 包 SHA-256 为 `144d06119d5d20052ab040d7fa89021cda31dc37c4a76e285a2c95885c6fa882`，Rootless 包为 `7193b9b77c00026625250dbca2b0ddf48944c36d04800326c5ccd6c48fe45d9c`。只静态分析包，未执行 DPP 安装脚本。

本次实际运行 [REA](https://github.com/morluto/rea) 6.9.0 / Ghidra 与 [Craft Anything](https://github.com/storytold/craft-anything) CLI 0.6.1。Craft 执行 apple-macho-show、native-strings-find；REA 反编译 arm64 slice 的 0x6e90、0x79e0、0x73f4、0x8520，六条分析命令均退出 0。arm64 slice SHA-256 为 `120b0aa756b412826a8326a6ad45da65d244fdb6b9cc9214b45358f27069ff31`，与旧 checkpoint 匹配。

| 项目 | DPP RootHide 2.1 | MKS 1.15 |
| --- | --- | --- |
| 包内注入过滤声明 | 未列 AppStore、akd、accountsd、amsaccountsd；列出 appstored、itunesstored 等 | 另直接注入这些认证进程 |
| 系统版本字典 hook | 0x6e90 仅在 Preferences 分支注册；0x79e0 修改版本显示值 | 所有注入目标注册，另改 ProductBuildVersion |
| sysctl hook | 已检查的初始化函数未见注册 | 注册 sysctlbyname 和 sysctl，替换机型、主板、版本、build |
| 内部 MG 返回 | 0x73f4 为配置身份直接构造 CF 值 | 先取原生值；原生为空时内部 getter 保留空值 |
| RootHide / Rootless 库 | 两包的 dipp.dylib 字节相同；dppd、App 主程序、过滤 plist 也分别相同 | 使用不同路径编译分支 |

过滤列表只证明包内声明，不证明 DPP 整个产品的全部运行态行为；初始化函数中未见某项 hook，也不作为全程序不存在它的结论。

## 实验和已撤回的结论

| 对照 | 结果 | 判断 |
| --- | --- | --- |
| 1.15 完整注入、原随机参数 | 复现转圈；认证日志含 SRP 失败和 iForgotAppleIdLocked 后续流程 | 未通过 |
| 只恢复真实 iOS / build，仍启用改机 | 进入额外密码确认 | 未通过 |
| 1.15.1 候选：放行 AppStore 及三个认证进程的原生 API | 解锁账号后，一次密码＋双重认证可登录并重开保持；用户后台未出现匹配的改机设备 | **方案已否决；先前“验收成功”的结论撤回** |
| 恢复官方 1.15 完整注入，同一已解锁账号、同一随机参数 | 再次出现额外密码确认，日志含 selected protocol key missing / -7018 | 未通过 |
| 完整注入，换成真实存在的机型／主板／芯片／系统组合 | 仍出现额外密码确认 | 未通过；不能把问题归结为随机版本组合 |
| 1.15.2 候选：RootHide 内部 MG 空答案按配置构造并填写类型 | AppStore 主动采样中原本缺失的八个身份项变为匹配，登录仍要求额外密码 | 读数差异已改善；登录未通过 |
| 1.15.3 候选：保留身份 hook，系统版本字典仅 Preferences，RootHide 不安装 sysctl hook | 登录仍出现额外密码确认 | 未通过；不能发布为修复完成 |

先前原生认证方案的登录成功不能证明改机身份登录。账号解锁与候选修改曾同时发生；后续已补做完整注入对照，仍然失败。当前没有证明 Apple 后台登记了本次随机序列号。

## 本分支的实验改动

- RootHide 内部 MG hook 在有配置值、原生返回空值时构造对应 CFString / CFNumber / CFData，并填写观测到的 32 位 MG 类型 9 / 6 / 10；未知字段、已有不兼容类型和停用配置仍保留原路径。
- RootHide 的系统版本字典 hook 限于 Preferences，不安装 sysctl 两个 hook。AppStore、akd、accountsd、amsaccountsd 仍在注入过滤列表内，未使用 1.15.1 的绕行方案。
- Rootless 的安装范围和上述空答案处理保持原逻辑。共享版本号暂为实验编号 1.15.3。

`tests/identity_answer_tests.m` 分别编译两种分支：Rootless 11 项、RootHide 23 项通过。它验证类型与空答案处理，不证明登录成功。完整回归与包校验随分支更新记录在 [验证文档](validation.md)。

1.15.2 的 AppStore 主动采样为 55 项：37 项匹配、18 项 passthrough、0 项缺失、0 项非空不匹配。其他已采到的账号/商店进程也未见非空不匹配；该轮 akd 未采齐。主动探针调用不等于 Apple 登录业务实际调用，也不证明服务器登记内容。

## 首轮登录自然调用审计

临时审计在实际登录期间捕获到 AppStore 的 MGGetStringAnswer(ProductType / BuildVersion)、MGCopyAnswer(ProductType / BuildVersion / HWModelStr)，以及 akd 的 MGCopyAnswer(SerialNumber)，这六个实际访问点均匹配当前配置。它们由登录业务自然触发，不是主动探针主动询问；仍未覆盖完整请求的所有字段，也不证明服务器登记内容。

同一轮出现额外密码确认。只读属性列表审计只捕获到一条 ec=0 的状态字典，未取得导致 selected protocol key missing 的完整错误来源；该单条状态不作为认证成功证据。审计组件已在该轮结束时移除，并刷新目标进程。

## 已完成主机检查

1.15.3 本轮通过 1094 项核心回归、77 项合成 Keychain、9 项 UDP、Rootless / RootHide 各 61 项 HTTP、69 项绑定检查；两种 DEB 的签名、双架构载荷、路径、链接和脚本检查通过。未做 Rootless 真机升级或登录，根本目标仍未通过。

## 下一步与证据规则

先用临时只读审计记录登录期间自然发生的身份字段访问与配置是否匹配，以及认证响应的非敏感错误码，定位认证失败来源。审计不修改返回值，不记录口令、验证码、完整响应、令牌或会话数据。每个候选都保留原包、配置摘要、变更和回滚记录。

最终必须重新完成 App Store 登录，并由实际后台设备详情核对本轮随机字段。没有完成这一步，分支、PR 和文档均保持“未通过验收”，不生成正式修复 Release。

原始日志、账号截图、私有状态和参考二进制留在本地忽略目录；仓库只提交源码、合成测试、脱敏结论和明确标识的测试包。
