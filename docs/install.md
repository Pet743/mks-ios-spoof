# MKS 1.15.12 安装与升级

## 新设备快速开始

**RootHide + Mac + USB：** 按[USB 快速安装指南](install-usb-roothide.md)操作。指南包含自动选择最新正式版、校验 SHA-256、USB 传包、SSH 安装、绑定设备编号和安装后检查；RootHide Dopamine 设备也适用，不要求手机上存在单独的 Bootstrap App。

直接在手机安装时：

1. 确认手机已进入相应越狱环境，Sileo 能正常打开，已安装该环境的 ElleKit；RootHide 还需核心包 `roothide`。
2. 打开[最新正式版](https://github.com/Pet743/mks-ios-spoof/releases/latest)，选择下表对应的完整 DEB，用 Sileo 安装。
3. 安装后打开桌面的「MKS 改机」，核对 App 版本与所选 Release 一致。
4. 需要 HTTP 对接时，先用电脑读取真实 USB UDID，再通过 App 的「接口文档」绑定；不要填写改机参数中的随机 UDID。
5. 需要立即使用新参数时，执行一次「一键改机」，等待桌面重启，再打开 MKS 检查启用状态与参数。安装或升级本身不会自动改机。

新设备通常通过包管理器安装即可。OpenSSH 是电脑远程安装时的通道，ZXTouch 是可选的触控自动化工具，Python 用于相应自动化脚本；后三者均不是 MKS 本身的依赖。

## 选择安装包

按越狱环境选择一份 DEB。两个包均包含 App、注入库、daemon、Keychain 清理与 HTTP 服务。

| 越狱环境 | 依赖 | 安装包 |
| --- | --- | --- |
| Rootless，越狱根目录是 `/var/jb` | ElleKit | [mks_1.15.12_rootless_iphoneos-arm64.deb](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.15.12/mks_1.15.12_rootless_iphoneos-arm64.deb) |
| RootHide，包括 RootHide Dopamine，使用动态越狱根目录 | RootHide 核心包及该环境的 ElleKit | [mks_1.15.12_roothide_iphoneos-arm64e.deb](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.15.12/mks_1.15.12_roothide_iphoneos-arm64e.deb) |

使用 Sileo 等越狱环境的包管理器打开对应 DEB 并安装。DEB 会一起安装桌面上的 MKS App、注入库及后台服务。巨魔商店只负责独立 IPA 的 App 安装，单装 IPA 缺少本插件和后台服务，完整功能请安装 DEB。

安装前确认本环境的 ElleKit 可用；RootHide 包还依赖 RootHide 核心包。两个方案只选与当前环境匹配的一份。也可在该环境的 root shell 中执行对应命令，其中 `/path/to` 换成当前 shell 可访问的下载目录。

```sh
# Rootless
dpkg -i /path/to/mks_1.15.12_rootless_iphoneos-arm64.deb

# RootHide bootstrap shell
dpkg -i /path/to/mks_1.15.12_roothide_iphoneos-arm64e.deb
```

## 已有旧版本如何升级

同一越狱环境直接覆盖升级，通常无需先卸载旧版。App、注入库和后台服务由同一个 `com.mks.spoof` DEB 更新。安装脚本保留已有主配置、HTTP 状态和 Keychain 备份；保留下来的旧参数不表示仍在运行旧版程序。可按 USB 指南分别核对包版本、App 版本和后台服务，再显式改机生成新参数。

首次安装时，当主配置不存在而原系统的 `/var/mobile/Media/mks.config` 存在，安装脚本会迁移这份旧配置。切换越狱环境后，两个安装根目录内的数据各自独立。确需先移除旧包时，使用 Sileo 卸载或执行 `dpkg -r com.mks.spoof`；仅删除桌面图标不能代替核对 `dpkg` 包状态。随后安装对应版本。升级前的配置备份及回退步骤见 [USB 指南](install-usb-roothide.md#备份与回退)。

设备 Bundle ID 为 `com.mks.spoofer`。使用完整功能时，应从 DEB 注册的 App 进入；如果同时保留了相同 Bundle ID 的独立 IPA，先删除独立安装的 App。守护进程和插件随 DEB 一同更新。

## HTTP 设备编号

首次部署时，从电脑的 USB 工具确认手机实际 UDID。打开 MKS 的「未绑定设备」或「接口文档」，点击「绑定 USB 设备编号」，填写并确认。已绑定时显示原值，重绑定需再次确认。写入由核对 UID 与 App 可执行路径的本地 daemon 完成，写后回读并返回 daemon 状态。HTTP 不提供远程绑定入口。

也可在对应越狱环境的 root shell 中执行 CLI。

```sh
# Rootless
/var/jb/usr/libexec/mksd --set-device-id 'USB_DEVICE_UDID'

# RootHide bootstrap shell
/usr/libexec/mksd --set-device-id 'USB_DEVICE_UDID'
```

CLI 成功输出 JSON 且退出码为 0。

```json
{"ok":true,"deviceId":"00000000-0000000000000000","configured":true,"outcomeUnknown":false}
```

权限不足退出 1，格式错误退出 2，持久化或回读失败退出 3，另一个配置进程占锁时退出 5。错误同样输出 JSON，具体字段与处理流程见 [HTTP 与 CLI 文档](http-api.md)。调用方应记录退出码和 JSON，并以电脑实际 USB UDID 查询 `/status` 核验。

编号独立保存，同一环境升级时复用。打开 App 右上角「接口文档」可获取当前地址、令牌和调用案例。HTTP 默认端口为 `33237`，Bearer token 随首次 daemon 启动生成。[HTTP 文档](http-api.md)

## 升级后进程刷新

1.15.12 RootHide 在“一键改机”和“恢复原机”时，会先按精确名称结束原来的 AppStore、akd、accountsd、amsaccountsd、appstored、itunesstored、lockdownd、itunescloudd、identityservicesd、adid、fairplayd.H2、storebookkeeperd，再重启 SpringBoard。检查原 PID 已退出后才报告刷新成功，可选进程不存在不算失败，权限或超时会报告失败。系统会按需重启服务。正常使用不需要手工 killall。

Rootless 维持原刷新行为。覆盖安装本身保留原参数，执行改机/恢复后相应进程才会加载本轮配置和新版注入库；请在没有账户登录或下载进行时执行。

一键改机和恢复原机均会重启桌面。Keychain 清理单独执行。HTTP 返回持久化任务编号，调用方需查询任务终态。

## 文件位置

| 用途 | 相对于越狱根目录的位置 |
| --- | --- |
| 主改机配置 | `var/lib/mks/mks.config`，mobile 可写，0644 |
| HTTP 状态 | `var/lib/mks-http`，root:mobile，0750 |
| 访问令牌与设备编号 | HTTP 状态目录内的 `token`、`device-id`，root:mobile，0640 |
| 安装标识 | HTTP 状态目录内的 `installation-id`，root:mobile，0640 |
| HTTP 任务 | HTTP 状态目录内的 `jobs.json`，root，0600 |
| Keychain 备份 | `var/lib/mks-keychain-backups`，root:wheel，0700，文件 0600 |

Rootless 使用 `/var/jb`。RootHide 在 bootstrap shell 中使用上表路径的绝对形式，从原系统查看时可用 RootHide 的 `jbroot` 工具解析路径。

恢复原机写入 `enabled:false` 配置。Keychain 清理后的备份与恢复是独立操作。[Keychain 文档](keychain-cleaner.md)

1.15.12 的主机与真机结果见[验证记录](validation.md)。覆盖升级不自动重新生成参数；原来的停用/启用状态与配置继续保留。需要使用新生成规则时，通过既有一键改机入口显式执行。RootHide 无双重认证账号已完成一次密码登录、重开保持与后台字段匹配；双重认证账号仍存在验证后未登录、需再次提交密码的问题。Rootless 没有本轮真机登录验收。[完整复测](roothide-login-compatibility.md)。

历史版本 [1.15.4](https://github.com/Pet743/mks-ios-spoof/releases/tag/v1.15.4) 的标签与安装包继续保留。
