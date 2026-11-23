# RootHide 登录兼容性：1.15.5–1.15.8 候选记录

当前分支：`codex/roothide-login-compatibility`。1.15.4 的原始标签与安装包保留。后续候选均未取得新的完整验收，不作为已完成修复的发行版。

## 验收条件

改机保持启用，退出媒体账号并确认未登录，再提交一次密码完成必要双重认证；App Store 登录后重开保持，并由用户后台设备详情核对本轮可见机型、系统版本、序列号或 IMEI。第二次密码确认、只在本地读数匹配，以及后台没有出现对应设备，均不算通过。

## 已观察的候选结果

| 候选与对照 | 结果 |
| --- | --- |
| 1.15.4 完整执行 DPP 六进程刷新 | 未完成登录，出现到设置验证 Apple ID 的提示 |
| 1.15.5：RootHide 配置 MG 值直接返回、IOKit Search 身份白名单可构造原生缺失答案；仍排除 akd | 一次密码登录且重开保持，但用户提供的两条后台记录均与本轮参数不符；**完整验收未通过** |
| 同一 1.15.5 恢复 akd 注入 | 第二次密码确认，日志再次出现 selected protocol key missing / -7018 |
| 1.15.6：保留原生 ChipID，并恢复 akd 注入 | 仍要求到设置验证；未通过 |
| 1.15.6 临时采用 DPP 运行时开启范围 | 第二次密码确认；未通过 |
| 1.15.7：拆分 ModelNumber/地区、MEID 字段补齐、RootHide 不安装额外 IOKit Create hook | 同参数完整范围仍要求验证；新参数的 DPP 基础范围与商店身份范围也未通过 |
| 1.15.8：进一步保留原生第二 IMEI/HardwareModel，不额外安装 String getter 与 IDFV/IDFA hook | 仍出现到设置验证提示；未通过 |

每轮有效对照都检查配置与过滤字节未变。曾两次关闭并重开 App Store，确认未登录表单、无退出按钮和账户功能入口后再继续。Settings 顶部此前显示“登录 iPhone”；不以这一点推导全部账户缓存已清除。

临时只读审计观察到登录期间 AppStore 的机型/build/主板，以及 akd 的序列号读取匹配配置；同一轮 akd 的属性列表响应出现 ec=-22410。该审计只记录白名单错误码、字段名、匹配状态和摘要，不记录密码、验证码、完整响应或令牌。读取匹配仍不能替代登录及后台验收；错误码也没有被单独解释为最终根因。

## DPP 的新静态证据及更正

参考为用户提供的软件源中的 RootHide DPP 2.1，同一原包与 arm64 注入库的 SHA-256 已在历史调查记录中核验。实际使用 REA / Ghidra 继续追踪 daemon：

`0x100008800` 的命令 1000 在 `write_data` 成功后，调用 `0x10000c438` 重写 `dipp.plist`，再调用错误记录函数 `0x100009e4c` 与刷新函数 `0x10000bf2c`。

- 运行时选项开启时，Bundles 加入 UIKit / AppStore，Executables 加入 accountsd / akd / lockdownd。其固定基础名单还有 SpringBoard、ptpd、lsd、appstored、atc、CommCenter、adid、homed、itunesstored、cloudd、familycircled、storebookkeeperd、itunescloudd、identityservicesd、absd、fairplayd.H2、SIMSetupUIService。
- 刷新函数 `0x10000bf2c` 对 SpringBoard、lockdownd、akd、accountsd、itunescloudd、identityservicesd 调用 `0x100012e40`，逐项执行 killall -9。
- 因此，包内初始过滤文件不能代表 DPP 改机后的完整范围。此前“静态 plist 没列出这些进程”的事实仍成立，但不能用它解释全部运行态行为。没有推断该选项在用户参考设备上的默认状态。
- MG 函数 `0x73f4` 对 ChipID 明确回到原函数。已分析的映射列表没有替换第二 IMEI 或 HardwareModel；旧格式第三字段实际用于 MEID。`0xe8d4` 将完整型号字段拆成前五位 ModelNumber 与后续地区信息。
- 已分析的初始化路径注册 IOKit Search，未注册 MKS 原来额外安装的 Create、String getter、IDFV/IDFA hook。候选保留接口类型输出、返回值所有权及停用恢复检查，未将反编译的未初始化类型输出照搬为实现。

这些差异用于形成可测试的候选；没有将任一静态差异冒充已确定的认证失败原因。

机型/系统/build 换成真实对应组合且保留随机身份后，仍出现第二次密码确认。另发现 adid、fairplayd.H2、storebookkeeperd 为跨版本长期运行进程，正在进行刷新后的对照；尚未将其认定为原因。

## 构建与回归

1.15.8 的身份答案测试 Rootless 35 项、RootHide 81 项通过；两份包的签名、双架构、载荷、路径及完整过滤范围检查通过。Rootless 既有身份语义与过滤模板保留。各轮测试、失败输出、原始配置和签名差异检查保存在本地诊断目录。

当前 RootHide 候选将五位型号/地区和 MEID 按参考格式处理；配置中的 14 位第三字段继续保留，但不会作为原生第二 IMEI 返回。ChipID 与 HardwareModel 保留原生值。RootHide 通过内部 MG 与 IOKit Search 路径替换其余支持的身份字段；UIKit/认证进程范围仍需配合最终验收选择。

## 参考软件环境已回滚

排查中曾短暂安装原版 DPP 做运行对照准备，未打开 App、未输入卡密或激活；用户要求只测试 MKS 后，立即卸载。已再次核对 DPP 包未安装、App/库/daemon 文件不存在、没有 daemon 注册或运行进程，MKS 配置与过滤文件逐字节恢复，相关进程已刷新。

后续仅对 MKS 做真机测试，DPP 只用于静态分析。没有删除真实 Keychain 数据，也没有修改原始 DPP 二进制或其授权逻辑。
