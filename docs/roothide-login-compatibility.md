# RootHide 登录兼容性：1.15.5–1.15.12 候选记录

当前分支：`codex/roothide-login-compatibility`。1.15.4 的原始标签与安装包保留。1.15.12 的一个无双重认证账号已完成正常改机、一次密码登录、重开保持及后台字段匹配；双重认证账号仍未通过首次流程。现按用户要求发布 1.15.12 安装包，并明确保留该已知问题，不宣称全部账号已修复。

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
| 1.15.8：进一步保留原生第二 IMEI/HardwareModel，不额外安装 String getter 与 IDFV/IDFA hook | 初期要求设置验证；完整刷新长期进程并使用对应参数后，旧测试账号一次密码登录、跳过可选安全升级并重开保持；新账号仍未完整通过 |
| 1.15.8 正常生成新参数，仅重启 SpringBoard | 一次密码登录并重开保持，但后台为新序列号/IMEI 搭配上一轮机型、系统；未通过 |
| 1.15.9：RootHide 自动刷新身份/商店服务，并生成固定对应的机型/系统元组 | 真机 12 个原目标 PID 全部退出；用户后台确认机型、系统、序列号一致，但双重认证后 App Store 未登录；未通过 |
| 1.15.10：刷新检查增加进程退出过渡状态的限时重试 | 自动刷新成功；加入 amsaccountsd 注入的临时对照仍在双重认证后未登录，原过滤文件恢复 |
| 1.15.11：原生 MG 初始化读取对照 | 只做安装验证，未独立完成登录对照；随后并入 1.15.12 |
| 1.15.12：RootHide Search 白名单外字段完全保留原生，并保留原生初始化读取对照 | 一次密码、一次双重认证后仍未登录；后台 NVRJX7YWEA、机型与系统匹配；整体验收失败 |
| 1.15.12：同一身份的双重认证后诊断重试 | 再提交一次密码成功并重开保持；该身份累计两次密码，不算通过 |
| 1.15.12：切换无双重认证测试账号，重新完整执行正常改机流程 | 一次密码登录、重开保持，改机持续启用；用户后台机型、系统、IMEI 一致，本轮通过 |

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

初次换成对应机型/系统/build 后仍失败；随后发现 adid、fairplayd.H2、storebookkeeperd 为跨版本长期进程。刷新所有这些进程后，旧测试账号成功登录。该结果来自参数、hook 与刷新组合，不证明任一单独因素是唯一根因。

## 后台混合字段及自动刷新

新测试账号完成双重认证后，用户先确认后台为 iPhone 14 Pro / iOS 16.3.1 / DY3G1UN75Y，但 App Store 未登录。之后按正常流程重新生成参数，App Store 一次密码登录并重开保持，后台却显示 iPhone 14 Pro / iOS 16.3.1 / XXTSX7EXW5，IMEI 543634152958609。该轮配置实际为 iPhone16,2 / iOS 18.6.4 / XXTSX7EXW5：只有序列号和 IMEI 匹配，不能算完整生效。

读取现场进程列表证实，SpringBoard 已随本轮改机重启，而 akd、accountsd、appstored、itunesstored、lockdownd、itunescloudd、identityservicesd、adid 和 fairplayd.H2 仍是上一轮进程。源码 `MKSRespring` 原来只结束 SpringBoard。这是已确认的刷新遗漏；目前没有证明后台混合字段只有这一项成因。

RootHide 候选在改机/恢复的桌面重启前，枚举并按精确名称刷新 AppStore、akd、accountsd、amsaccountsd、appstored、itunesstored、lockdownd、itunescloudd、identityservicesd、adid、fairplayd.H2、storebookkeeperd。可选进程不存在不算失败；权限、枚举或限时检查失败会返回失败。遇到正在退出、暂时读不到名称的 PID 时限时重查，避免过渡状态被直接算作错误，同时不向名称未核实的 PID 发信号。等待的是原 PID 退出，不要求系统服务保持停止。Rootless 继续原刷新行为。

1.15.9 真机第一次正常改机的刷新日志为 `matched=12 signaled=12 finished=12 errors=0 timeout=0 rc=0`，另由 Instruments 核对旧目标 PID 无一保留，无手工 killall。新参数为 iPhone16,2 / iOS 17.0 / build 21A329 / D84AP / T8130 / 序列号 BTUHLEZ2E2。用户后台截图中的 iPhone 15 Pro Max、iOS 17.0、BTUHLEZ2E2 全部一致。然而一次密码、一次双重认证后 App Store 仍显示未登录，故这轮仅后台字段匹配通过，整体验收失败。后台“可接收验证码”状态不能替代商店账户页及重开验证。

媒体账户服务第一次注入范围对照在改机刷新检查阶段停止，未提交密码、未取得范围结论，原过滤文件逐字节恢复。1.15.10 修正过渡状态处理后重测，自动刷新 11 个进程成功；临时额外注入 amsaccountsd 后，后台 SA4SJQZCXK、机型和系统匹配，但一次密码及双重认证后仍未登录。已恢复原过滤文件；不能据此认为扩充媒体服务注入解决了问题。

RootHide 参数生成器此前将型号、主板、芯片、系统与构建号独立随机，甚至生成不存在的系统版本。候选改为固定对应元组：iPhone 15 Pro Max / iPhone16,2 / D84AP / T8130 / MU773LL/A / iOS 17.0 / 21A329，序列号、IMEI、UDID 等身份仍逐次生成。该变化不保证 Apple 登录成功；Rootless 生成行为保留。

## 后续静态差异及失败复测

DPP 的初始化函数 `0x7f9c` 在读取替换参数前，通过原始 MG 入口读取五个混淆键。公开 MG 键映射及独立 MD5 映射核对表明其对应 SerialNumber、UniqueDeviceID、MLBSerialNumber、UniqueChipIDString、BatterySerialNumber。这里只确认调用顺序，没有证明这些读取的用途或它们能解决商店认证。`0x73bc` 的三秒延迟块进行符号检测，不是延迟加载参数。候选为 RootHide 增加相同原始读取顺序，抑制嵌套读取进入配置替换，并释放原生返回引用。Rootless 不增加这条路径。

还发现 MKS RootHide Search 钩子在显式白名单之后，继续调用通用映射器，会额外改写 `board-id`、`IOPlatformUUID`、`serial-number`。这与已分析 DPP 的白名单外原样返回行为不符，且 `board-id` 可能被替换成主板名称字符串的数据表示。新回归在 1.15.11 原实现上产生 3 项失败，修正后全部通过；Rootless 的通用映射保留。

1.15.12 普通改机成功，11 个目标进程自动退出并重启，新序列号 NVRJX7YWEA。用户后台确认 iPhone 15 Pro Max / iOS 17.0 / NVRJX7YWEA；App Store 一次密码、一次双重认证后仍回到未登录表单。初始化与白名单修正因此不能宣称已解决登录问题。该轮先保留身份，只读观察账户保存回调和 Keychain 写入返回码，不记录凭证内容，不把后续诊断性重复提交密码算成一次密码验收。

### 同身份诊断与无双重认证账号结果

在 NVRJX7YWEA 身份下安装临时只读会话探针，仅记录账户保存回调的布尔值/错误域/错误码，以及 SecItemAdd、SecItemUpdate 的数字返回码，不记录查询字典、密码、验证码、令牌或账户用户名。首次探针未加载到 hook 框架，确认无有效挂接后撤除；修正加载步骤后，目标进程挂接状态通过。保持参数不变进行诊断性重试，App Store 重新提交一次密码后成功并重开保持。记录到账户服务 8 次 SecItemAdd 和 64 次 SecItemUpdate 返回 0，另有一次 -25293；AppStore 两次 SecItemAdd 返回 0。没有捕获到公共 saveAccount 回调，不能从中推导私有保存路径未执行。

这只能说明重试期间存在成功写入和有效商店会话，不能把单次错误码当作首次失败的根因，也不能证明第一次已获得商店凭证但保存失败。双重认证后的首次商店续接仍待定位。探针源文件、动态库和诊断记录保留本地，手机上的临时注入库、过滤文件及传输文件已移除并刷新进程。

随后按用户要求切换到此前提供的无双重认证账号：先退出上述账号，关闭并重开 App Store 确认未登录，再调用 MKS 正常 spoof 操作。12 个目标进程自动退出，未手工刷新；新参数为 iPhone16,2 / iOS 17.0 / 序列号 USMNVPCTKR / IMEI 827275389397075。改机启用时只提交一次密码，账户页显示目标账号和退出按钮，关闭重开仍保持登录。配置与过滤文件逐字节未变，状态接口为 1.15.12 / enabled=true / profileValid=true。

用户明确确认后台一致，并提供显示 iPhone 15 Pro Max、iOS 17.0、IMEI 827275389397075 的截图；该截图不显示序列号，不把未显示的字段写成截图独立验证结果。本轮满足所约定的可见字段标准，证据保存在 `diagnostics/login-compatibility-20261123/no-two-factor-standard-flow`。结论限定于该无双重认证账号和这一轮新参数，不外推为所有账号已修复。1.15.12 两份安装包另存并记录 SHA-256；Rootless 只有构建与主机检查，未做本轮真机登录验收。

## 构建与回归

新增对应元组检查在 1.15.8 原代码上产生 5 项 RootHide 失败；Search 白名单检查在 1.15.11 原实现上产生 3 项失败。1.15.12 身份答案 Rootless 35 项、RootHide 113 项通过，包含原生读取重入保护与停用恢复。进程刷新包含精确名称、缺失、PID 复用、权限失败、超时和暂时读不到进程名的 14 项隔离测试，不向主机系统服务发信号。核心 1094 项、HTTP 各 61 项及双方案包校验已运行；版本更新后的结果保存在 `diagnostics/login-compatibility-20261123/refresh-fix`。Rootless 既有身份语义与过滤模板保留。

当前 RootHide 候选将五位型号/地区和 MEID 按参考格式处理；配置中的 14 位第三字段继续保留，但不会作为原生第二 IMEI 返回。ChipID 与 HardwareModel 保留原生值。RootHide 通过内部 MG 与 IOKit Search 路径替换其余支持的身份字段；UIKit/认证进程范围仍需配合最终验收选择。

## 参考软件环境已回滚

排查中曾短暂安装原版 DPP 做运行对照准备，未打开 App、未输入卡密或激活；用户要求只测试 MKS 后，立即卸载。已再次核对 DPP 包未安装、App/库/daemon 文件不存在、没有 daemon 注册或运行进程，MKS 配置与过滤文件逐字节恢复，相关进程已刷新。

后续仅对 MKS 做真机测试，DPP 只用于静态分析。没有删除真实 Keychain 数据，也没有修改原始 DPP 二进制或其授权逻辑。
