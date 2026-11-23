# DPP RootHide 功能对照与 1.15.4 保留约定

**续测发现未解决问题：** 新账号在独占操作、进程刷新、DPP 声明范围和插件隔离对照中仍出现第二次密码确认。本轮未通过；先前单账号通过记录与 v1.15.4 原始产物保留。[复测矩阵与回滚结果](roothide-login-retest.md)。

更新：2026-11-23（Asia/Shanghai）。用户确认当前 MKS 已满足要求，并要求保留这一版；DPP 可能更完善的改机功能作为后续迭代参考。1.15.4 不继续加入新 hook，后续工作从新版本开始。

## 参考样本

软件源：[http://1024.zone.id](http://1024.zone.id)。本轮重新获取 Packages 与 RootHide DEB，当前仍为 DPP 2.1；SHA-256 为 `144d06119d5d20052ab040d7fa89021cda31dc37c4a76e285a2c95885c6fa882`，与前一轮样本逐字节一致。arm64 注入库 SHA-256 为 `120b0aa756b412826a8326a6ad45da65d244fdb6b9cc9214b45358f27069ff31`。

已复用同一 REA / Ghidra checkpoint，实际补充反编译 0x81b8、0x827c、0x830c、0x85b0，四条命令均退出 0。下面的 DPP 行为来自包内声明和反编译；本轮没有安装、运行 DPP，也没有把静态观察当作 DPP 真机对照。

## 功能覆盖与差异

| 改机功能 | DPP 2.1 静态观察 | MKS 1.15.4 的实现与证据 |
| --- | --- | --- |
| MG 身份字段 | 0x73f4 覆盖序列号、IMEI/MEID、MAC、ECID、UDID、机型、主板、平台、系统版本、build、地区及部分 alias | 已有对应映射；配置值按字符串、数字、数据类型返回。RootHide 原生空答案补充类型输出。主机与历史进程采样通过，不声称每个字段均被服务器使用 |
| Baseband 字典 | 替换已有 IMEI、MEID 与 kCTPostponementInfoUniqueID | 已替换存在且有配置值的字段；默认生成器未提供 MEID，不能声称默认 MEID 与 DPP 一致 |
| IOKit Search | 0x7b34 处理序列号、ECID、MAC 和 udid-version | 已有 Search 与 Create wrapper，按原属性类型替换；保留原生空属性 |
| 系统版本字典 | 0x79e0 在 Preferences 中注册 | RootHide 同样限于 Preferences；没有向全部登录进程安装该 hook |
| sysctl | 已检查的初始化函数未见注册 | RootHide 不安装两种 sysctl hook；Rootless 保留既有实现 |
| AADeviceInfo buildVersion | 0x8520 返回配置 build | 已实现，并处理私有框架延迟加载；主机回归覆盖 |
| CoreTelephony 设备信息 | 0x83b4 修改首个设备对象的 IMEI/MEID | MKS 对可复制且 setter 类型匹配的对象建立副本再替换，以便停用后回到原缓存；具体私有类仍需逐机核对 |
| 关于本机的专用显示 getter | 0x81b8、0x827c、0x830c 分别替换 PSGAboutDataSource 的机型名称、版本、版本/build 显示 | 尚未直接 hook 这三个 getter；现有 MG/系统版本映射不能替代专用 getter 一致性的证明。列为后续改进 |
| 特定设备信息页 | 0x85b0 在 TSDeviceInfoViewController initWithOptions: 的字典副本写入 ImeiKey / MeidKey | 尚未实现该专用入口，列为后续改进 |
| App Store 与后台设备一致 | 包过滤没有直接列出 AppStore、akd、accountsd、amsaccountsd；运行态完整行为未重测 | MKS 保留 AppStore 和其他商店/账户目标，仅 RootHide 排除 akd；本轮真实登录、重开保持、后台机型/序列号/系统版本三项匹配已通过 |
| 参数切换与恢复 | 本轮未完成 DPP 真机对照 | MKS 主机覆盖快照更新、同秒写入、并发及停用恢复；历史真机恢复采样有记录。本轮为保留已通过的登录身份，没有再切换或恢复手机参数 |

因此，MKS 本轮已达到用户指定的登录和后台核对效果；完整 DPP 改机功能等价尚未建立。上表明确保留差异，后续不在 1.15.4 上直接覆盖试验。

## 后续迭代入口

先从 1.15.4 标签创建新版本。逐项研究 Settings 显示 getter、TSDeviceInfoViewController 以及默认 MEID 参数语义，先以合成对象验证类型、配置切换、停用恢复与原缓存不变，再做单项真机检查。每个候选继续完成 App Store 重新登录、重开保持和用户后台设备字段核对；未通过时回到保留的 1.15.4。

可复用任务说明：

```text
以已保留的 MKS 1.15.4 为基线，在新版本对照 DPP RootHide 2.1。
复用 SHA-256 相同的参考库和 REA checkpoint，逐项处理 PSGAboutDataSource、
TSDeviceInfoViewController 及 MEID 默认参数差异；先给出函数地址、字段语义和
可观察的行为差异，再实现并验证配置切换与停用恢复。保持 1.15.4 包与标签不变。
最终重新核对改机启用时的 App Store 登录、重开保持和后台可见设备字段。
```
