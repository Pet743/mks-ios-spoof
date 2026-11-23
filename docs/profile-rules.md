# MKS 1.15 参数生成与 HTML 规则

## 1.15.12 RootHide 更新

RootHide 新生成参数使用对应的固定元组：iPhone 15 Pro Max / `iPhone16,2` / `D84AP` / `T8130` / `MU773LL/A` / iOS `17.0` / build `21A329`。序列号、IMEI、ECID、UDID、MAC 等仍逐次生成；字段格式和 14 段导出保持兼容。已有配置在覆盖升级时原样保留，需点击“一键改机”才生成新参数。

Rootless 保留下文 1.15 的生成行为。RootHide 的 ChipID、第二 IMEI、HardwareModel 保留原生读取，ModelNumber 按前五位型号与地区拆分，MEID 可回退到旧格式第三段；因此“配置字符串存在”不等于每个进程都使用该字符串。完整字段与登录结果见[兼容性记录](roothide-login-compatibility.md)。

以下表格记录历史 1.15 默认规则；机型、主板、芯片、版本及构建号的独立随机方式仅在 Rootless 继续使用。

1.15 将新生成参数对齐本地参考 HTML 的默认机型和地区。App 与 HTTP daemon 在保存前使用同一个规则检查器；App「当前参数」显示检查结果、14 段参数行与 JSON。检查通过表示符合本地格式规则，不表示真实硬件、Apple 认证或登录所用属性已全部替换。

## 默认值与字段顺序

导出使用 `----` 分隔，顺序如下。数据均为本地生成的测试参数。

| 段 | JSON 字段 | 生成或导出规则 |
| --- | --- | --- |
| 1 | SerialNumber | 10 位大写字母和 1–9，排除 I、O、0 |
| 2 | InternationalMobileEquipmentIdentity | 15 位数字，Luhn 校验 |
| 3 | InternationalMobileEquipmentIdentity2 | 第 2 段的前 14 位 |
| 4 | WifiAddress | 小写冒号分隔 MAC；首字节 02；EthernetMacAddress 同值 |
| 5 | BluetoothAddress | 独立生成的同格式 MAC，首字节 02 |
| 6 | UniqueChipID | 16 位大写十六进制；导出移除 0x；DieId 同值 |
| 7 | UniqueDeviceID | 40 位小写十六进制 |
| 8 | MLBSerialNumber | 与第 1 段相同 |
| 9 | ProductType | 默认 iPhone16,2（iPhone 15 Pro Max） |
| 10 | ModelNumber | M + 两个字母 + 一位数字 + 一个字母 + LL/A |
| 11 | HWModelStr | 默认随机 D80AP–D89AP；规则接受 D + 两位数字 + AP |
| 12 | HardwarePlatform | T7000–T8999；ChipID 使用相同四位数作为 0x 十六进制字符串 |
| 13 | BuildVersion | 20–22 + 一个大写字母 + 10–99 |
| 14 | ProductVersion | 主版本 16、17 或 18；次版本和补丁位各 0–9 |

地区默认 `RegionCode:LL`、`RegionInfo:LL/A`。检查器兼容 US/LL、CA/CL、DE/DN、CN/CH、HK/ZP 对应后缀，允许六种参考机型 ID，但本版没有新增机型或地区选择 UI。生成器不额外添加 MEID；原生 MEID 因而沿用既有 passthrough 行为。

参考 HTML 的芯片生成范围是 T7000–T9999，但其校验规则仅接受 T7000–T8999；MKS 使用后者以避免新生成值被自身校验拒绝。主板校验是格式检查，D73AP 也符合规则。

## 保存、兼容与结果语义

App 检查失败时展示错误并停止保存；daemon 返回 `profile_html_validation_failed` 与 `stage:profile_validate`，不保存、不重启桌面。检查成功后仍由原来的强类型解析、原子写入与回读检查完成保存。

升级保留旧配置；旧版 JSON 和 14 段配置继续按原解析器读取，恢复原机写入 `enabled:false`。旧配置可能显示“未通过”HTML 规则，这不等于旧配置解析失效。`profileValid` 只报告解析器是否接受配置。

机型、主板、芯片、系统版本与 build 独立随机，规则未验证真实设备组合。版本和 build 不再固定为 16.3.1 / 20D67，MLB 也从独立值改为重复序列号。这些行为变化应在业务使用前单独验收；[Apple ID 事件](login-incident.md)中的登录路径一致性尚无修复结论。

## 回归入口

```sh
python3 tests/run_host_tests.py
python3 tests/test_http.py
python3 tests/test_http.py --scheme roothide
```

回归覆盖生成参数、Luhn、字段映射、14 段导出回读、非法芯片/序列号/机型/主板，以及既有 hook、停用恢复和 HTTP 流程。实际运行结果见[验证记录](validation.md)。
