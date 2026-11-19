# MKS 改机

一个 iOS 越狱设备的**设备信息伪造（改机）**插件，由两部分组成：

| 组件 | 说明 |
|---|---|
| `mks_1.4.deb` | Tweak（注入 SpringBoard / 设置 / 微信 / App Store 等进程），负责 hook 设备信息 API |
| `MKS-spoofer.ipa` | 桌面 App，提供「一键改机 / 还原设备」界面 |

改机参数**自动生成**，每次点击都会随机生成一套新的，并且强制满足格式校验规则，不需要手动编辑任何配置文件。

---

## 功能

- **一键改机**：随机生成 14 段设备参数 → 写入配置 → 立即生效（无需重启）
- **还原设备**：删除配置 → 立刻恢复真实设备信息
- 无悬浮窗、无授权码、无网络请求

### 覆盖的字段

| MobileGestalt key | 伪造内容 |
|---|---|
| `ProductType` | 机型标识，如 `iPhone16,2` |
| `SerialNumber` | 序列号（10 位） |
| `ModelNumber` | 型号，如 `MAS4CLL/A` |
| `HardwareModel` | 主板型号，如 `D81AP` |
| `ProductVersion` | iOS 版本，如 `16.3.6` |
| `BuildVersion` | 版本号，如 `21Z45` |
| `UniqueDeviceID` | UDID（40 位 hex） |
| `InternationalMobileEquipmentIdentity` | IMEI（15 位，含 Luhn 校验） |
| `InternationalMobileEquipmentIdentity2` | IMEI2（前 14 位） |
| `EthernetMacAddress` / `BluetoothAddress` | MAC 地址 |
| `ChipID` | 芯片段，如 `T8507` |

以及 sysctl 层：

| key | 伪造内容 |
|---|---|
| `hw.machine` | `iPhone16,2` |
| `hw.model` | `D81AP` |
| `kern.osproductversion` | `16.3.6` |
| `kern.osversion` | `21Z45` |

### 参数校验规则

生成器保证每组参数都满足以下规则（与常见"地区机型序列生成器"的校验一致）：

- 序列号：10 位，字符集排除 `I` 和 `0`
- IMEI：15 位数字，**通过 Luhn 校验**，且前 14 位与 IMEI2 一致
- MAC：`xx:xx:xx:xx:xx:xx`（小写 hex）
- ECID：16 位大写 hex
- UDID：40 位小写 hex
- 型号 `part`：`M` + 4 位 + `LL/A` 结尾
- 主板 `board`：`D\d{2}AP`
- 芯片 `chip`：`T[7-8]\d{3}`
- 版本号 `build`：两位年 + 一位字母 + 两位数字（如 `21Z45`）
- iOS 版本：`16.x.x`

> ⚠️ 注意：这里的"通过校验"指**本地格式校验**。序列号和 IMEI 是随机生成的，苹果官方的保修/激活查询接口无法识别这些 SN 真实存在。如果目标应用只做格式与一致性校验，这套参数可以工作；若它联网核验 SN 真实性，随机值无法通过。

---

## 安装

### 环境要求

- 已越狱的 iOS 设备（rootless，`/var/jb` 结构，如 Dopamine / palera1n rootless）
- 注入框架：ellekit（`libellekit.dylib`，提供 `MSHookFunction`）
- 若想用 App 图标形式安装：TrollStore / TrollStoreLite

### 第一步：安装 Tweak

任选一种：

**方式 A：deb 安装（Sileo / Filza / dpkg）**

```bash
dpkg -i mks_1.4.deb
# 或把 deb 传到手机，用 Sileo「安装本地 deb」
```

安装完成后会自动 respring。

**方式 B：手动部署**

```bash
scp mks.dylib root@<设备IP>:/var/jb/Library/MobileSubstrate/DynamicLibraries/
scp mks.plist root@<设备IP>:/var/jb/Library/MobileSubstrate/DynamicLibraries/
ssh root@<设备IP> 'chmod 755 /var/jb/Library/MobileSubstrate/DynamicLibraries/mks.dylib; killall -9 SpringBoard'
```

### 第二步：安装 App（可选）

App 只是操作界面，Tweak 本身已能工作。

1. 把 `MKS-spoofer.ipa` 传到手机
2. 打开 **TrollStoreLite** → 右上角 `+` → `Install from URL` 或 `Install IPA File`
3. 选择 `MKS-spoofer.ipa` → `Install`
4. 桌面出现 **MKS 改机** 图标

> 为什么需要 TrollStore：自编译的 App 只有 ad-hoc 签名，iOS 的 amfid 会直接 SIGKILL。TrollStore 利用 CoreTrust 做永久签名，无需开发者证书，也不过期。

---

## 使用

1. 打开 **MKS 改机**
2. 点 **一键改机（随机生成并通过认证）**
   - 生成一组新参数并弹窗显示
   - 状态变为「已改机」
   - 立即生效，无需重启
3. 点 **还原设备（关闭改机）**
   - 删除配置，设备信息恢复真实值
4. 重开 App 可看到当前状态与参数

### 自己验证是否生效

在越狱设备上执行：

```bash
# sysctl 层（不会被注入的进程里读到真实值，属于正常）
sysctl hw.model hw.machine

# MobileGestalt 层（在任意被注入进程中读取才是伪造值）
frida -U -n SpringBoard -e 'console.log(MGGetStringAnswer("ProductType"))'
```

或直接在 App 内观察状态与参数。

---

## 编译

需要 macOS + Xcode（iPhoneOS SDK）。

### Tweak

```bash
cd tweak
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -arch arm64e \
  -miphoneos-version-min=14.0 -dynamiclib -O2 \
  -o mks.dylib mks.m \
  -framework Foundation -framework CoreFoundation -framework UIKit \
  -undefined dynamic_lookup -isysroot "$SDK"
codesign -f -s - mks.dylib
```

### App

```bash
cd app
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -arch arm64e \
  -miphoneos-version-min=14.0 -fobjc-arc -O2 \
  -o MKS main.m -framework UIKit -framework Foundation -isysroot "$SDK"
```

打包 IPA 目录结构：

```
Payload/MKS.app/MKS
Payload/MKS.app/Info.plist
```

```bash
zip -qr MKS-spoofer.ipa Payload
```

---

## 项目结构

```
.
├── app/
│   ├── main.m          # App 源码（UI + 参数生成 + 配置写入）
│   └── Info.plist
├── tweak/
│   ├── mks.m           # Tweak 源码（MobileGestalt / sysctl hook）
│   └── mks.plist       # 注入目标配置
├── dist/
│   ├── mks_1.4.deb     # 编译好的 Tweak
│   └── MKS-spoofer.ipa # 编译好的 App
└── docs/
    └── install.md
```

## 配置位置

Tweak 按以下顺序读取配置，找到第一个就用它：

1. `/var/mobile/Media/mks.config`
2. `/var/mobile/Library/Preferences/com.mks.spoof.config`
3. `/var/mobile/Containers/Data/Application/*/Documents/mks.config`

文件内容为 14 段 `----` 分隔的参数。文件不存在 = 不改机（返回真实值）。

改机日志：`/var/mobile/mks.log`

## 已知限制

- 只覆盖 MobileGestalt 与 sysctl 两层，未覆盖 IOKit（`IOPlatformSerialNumber`）、IDFV/IDFA 等，如有需要可自行扩展 `answer_for_key` 映射表
- 参数为随机生成，不具备苹果服务器的真实性
- 需要越狱环境，非越狱设备无法使用

## 免责声明

仅供学习 iOS 逆向与 tweak 开发、以及在自有测试设备上研究使用。请勿用于绕过任何服务的风控、欺诈或其他违法用途。
