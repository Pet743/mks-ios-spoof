# DPP 对照分析与 MKS 1.9

日期：2026-11-20（Asia/Shanghai）。目标是借鉴 DPP 完善 MKS 的底层改机能力，保留 MKS 的一键改机/还原操作；不实现卡密、激活、远程授权或完整 DPP 界面。

## 样本与实际使用的工具

- 原始 `dpp_rootless.deb` SHA-256：`7193b9b77c00026625250dbca2b0ddf48944c36d04800326c5ccd6c48fe45d9c`。原文件保持不变。
- [Craft Anything](https://github.com/storytold/craft-anything) CLI **0.6.1**：已实际运行 `apple-nib-decode`、`apple-macho-show`、`native-strings-find`。证据包含控件连接、Mach-O、字段及服务字符串。
- [REA](https://github.com/morluto/rea) npm **6.9.0** + Ghidra **12.2** + Temurin JDK **25.0.5.1**：已实际运行原生 overview、procedure search 和七个函数的反编译。Apple Silicon decompiler 从该 Ghidra 发行版附带源码本地编译。
- REA 使用提取后 `dipp.dylib` 的 arm64 副本，SHA-256：`120b0aa756b412826a8326a6ad45da65d244fdb6b9cc9214b45358f27069ff31`。没有执行原包安装脚本或运行原插件。
- REA overview 报告 3332 个 procedure、7047 个 Ghidra 已定义字符串；该数字只代表后端已识别的 inventory，不表示完整恢复了源码。

## REA 带来的具体进展

以下地址是上述 arm64 slice 中的 Ghidra 分析地址，image base 为 `0x0`。它们不是本轮在手机上取得的运行地址。

| 函数/地址 | 反编译观察 | MKS 本轮处理 |
| --- | --- | --- |
| `FUN_00006e90` / `0x6e90` | 初始化中定位 MGCopyAnswer，解析入口第二条指令的分支目标，再 hook 内部实现；同时注册若干 ObjC getter | 新增受指令模式校验的 ARM64 B/MOV+B 解析；同镜像目标才尝试内部 hook，否则保留导出入口方案 |
| `FUN_000073f4` / `0x73f4` | 内部替换函数接受两个参数，透传原函数时保留第二参数；替换多种 MG key，并修改 BasebandPostponementStatusBlob 字典 | 独立 wrapper、baseband 字典替换及两个哈希 alias；后续真机证实第二参数是 32 位 MG 类型输出，修正版先调用原函数填入类型，再替换兼容类型的值 |
| `FUN_000083b4` / `0x83b4` | `mobileEquipmentInfoDict` 返回非空时，取 allValues 的首个对象并调用 setIMEI:/setMEID: | 对可复制、具有匹配 setter 签名的设备信息对象建立副本后替换；不修改原缓存，便于停用恢复。该实现仍需真机核对类的可复制性 |
| `FUN_00008520` / `0x8520` | AADeviceInfo.buildVersion 在配置有效时返回自定义 build | 新增同名实例 getter；检查运行时签名，处理私有框架延迟加载 |
| `FUN_00007b34` / `0x7b34` | IOKit Search 替换序列号、8 字节 ECID、6 字节 MAC 和 4 字节 udid-version | 补充 Search、udid-version 和 MAC 映射，并根据原属性保留返回类型 |
| `_posix_getmem` / `0x6588` | SecItemCopyMatching 定向查询 service=com.apple.dpp、account=dpp_token，取返回数据 | 记录为 DPP 自命名 keychain 项的定向读取；不增加授权机制 |
| `_posix_addmem` / `0x63c4` | 同名条目经 SecItemDelete 后以 SecItemAdd 写入 | 记录为同名条目的定向覆盖；不据此推导它遍历 Apple 账号或改写硬件身份 |

`allValues`、`firstObject` 和 `performSelector:withObject:` 的 selector 注释另外使用 Xcode llvm-objdump 对齐验证。这部分是辅助工具观察，不冒充 REA 输出。

## 已落到代码并本机验证的行为

共享解析器、强类型 MG 返回值、IOKit Create/Search、sysctlbyname/MIB、系统版本字典、IDFV/UUID 更新、baseband 字典、CoreTelephony 对象副本及 AADeviceInfo getter，均有实际 Objective-C 回归测试。测试直接调用真实 wrapper 与解析器，系统原函数通过明确的 host stub 提供；它们不能证明真实 iOS 私有接口的 ABI、注入效果或服务端接受情况。

本轮还修复旧版配置切换后 UUID 不变、CF 对象生命周期、纳秒内更新识别、并发快照及停用后旧配置复活的问题。新随机参数使用对应的机型/主板/SoC 和版本/build 表，格式正确不等于真实设备身份。

## 仍未建立的结论

2026-11-20 登录排查更新：原先仅将 Media 文件 chmod 0644 不能解决沙箱拒绝；App Store、akd、appstored 的实际 open 返回 EPERM。1.9 改用已在这些进程实测可读的 `/var/jb/var/lib/mks/mks.config`，安装时按“已有主配置优先”迁移旧数据。另发现旧 akd 仍映射已经从磁盘卸载的 dipp.dylib，商店 daemon 仍映射旧 mkscore；已针对性刷新并核对七个进程都加载当前 MKS。MGGetStringAnswer 的原实现直接返回内部 Copy 结果，调用方会释放；原 MKS 返回共享借用引用，已改为每次持有 +1，修复 App Store JetEngine 调用路径中的崩溃。该轮本机 385 项回归及五种真实 preinst 迁移情形通过。敏感 MG key 在部分进程原生为空时仍保留空值；登录成功尚未建立。证据在 `diagnostics/login-check-20261120/`。

2026-11-20 后续真机修订：用户启用改机并重启桌面后，SpringBoard 在 `MGGetSInt64Answer` 的类型校验路径主动中止，设备进入 ElleKit 安全模式。原内部 hook 替换答案时没有填写第二参数指向的类型输出。原系统反汇编及实测证实该参数宽度为 32 位，数字类型为 6、字符串为 9、数据为 10；这些数值不同于 CFTypeID。修正版保留原函数填入的 MG 类型，仅在 CF 类型兼容时替换结果。380 项本机回归通过，设备上已核对模块加载、类型输出、整数读取，并完成 App 内生成参数后重启桌面的流程，未再出现安全模式或新的桌面崩溃。证据保存在 `diagnostics/mg-type-fix-20261120/`。这只覆盖已检查设备和路径。

- 未证明 MKS 与完整 DPP 产品功能等价。DPP 的设置显示 getter、特定设备信息控制器、共享内存/加密数据路径并未逐项复制。
- DPP keychain 条目的全部数据语义及其所有调用场景尚未完成分析；函数存在不等于本轮观察到了执行。
- 内部 MG hook 与 SpringBoard 中的数字读取、daemon 重启已有本机型真机结果；晚加载私有类及全部跨进程沙箱可读性尚未逐项核对。
- 未完成 App Store 已登录账户页验收；没有证据支持把接口参数变化当作登录成功。
- DPP 的授权部分不是 MKS 的需求，已明确排除，不算待补齐功能。

## 本地证据位置与复跑

当前工作目录中的 `../dpp-replica/evidence/` 保存 Craft Anything 证据；`diagnostics/rea-dpp-20261120/` 保存 REA JSON、导出的伪代码 `.c`、准确 CLI 命令、退出状态及后端 checkpoint。原始参考二进制和这些本地分析产物未纳入源码补丁。

REA 调用形式：

```sh
rea decompile /absolute/path/dipp.arm64.dylib ram:0x73f4 --provider ghidra --json
```

可复用的后续分析提示：

```text
继续分析同一 SHA-256 的 DPP arm64 slice。复用现有 Ghidra checkpoint，分别跟踪
0x73f4 的内部 MG 路径与 0x83b4 的 CoreTelephony 路径。保留原函数第二参数、
CF 所有权和原对象不变性；区分反编译观察、本机 stub 回归与真机结果。
只把能给出具体地址、调用关系和回归测试的行为补进 MKS，不添加卡密或远程授权。
不要把 keychain 符号、格式校验或接口替换写成 Apple 登录成功。
```

## 2026-11-21：1.12 系统名称修复

真机原生/注入对照确认 `ProductName` 原值为 `iPhone OS`，旧映射把它当作设备家族改为 `iPhone`。1.12 去除此映射并补充四项回归。App 按钮及 HTTP 的改机/恢复另行通过常驻探针验证，原生缺失字段维持既有行为。此前“尚未验收登录”的文字为当时记录；本次已在改机启用状态观察到目标账户登录及重开保持，但没有证据将旧版每次认证失败归因于此字段。
