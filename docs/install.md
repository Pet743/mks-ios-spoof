# MKS 1.15.4 安装与升级

按越狱环境选择一份 DEB。两个包均包含 App、注入库、daemon、Keychain 清理与 HTTP 服务。

| 越狱环境 | 依赖 | 安装包 |
| --- | --- | --- |
| Rootless，越狱根目录是 `/var/jb` | ElleKit | [mks_1.15.4_rootless_iphoneos-arm64.deb](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.15.4/mks_1.15.4_rootless_iphoneos-arm64.deb) |
| RootHide，使用自己的 bootstrap 根目录 | RootHide 核心包及该环境的 ElleKit | [mks_1.15.4_roothide_iphoneos-arm64e.deb](https://github.com/Pet743/mks-ios-spoof/releases/download/v1.15.4/mks_1.15.4_roothide_iphoneos-arm64e.deb) |

用越狱环境的包管理器打开对应文件并安装。也可在该环境的 root shell 中执行对应命令，其中 `/path/to` 换成当前 shell 可访问的下载目录。

```sh
# Rootless
dpkg -i /path/to/mks_1.15.4_rootless_iphoneos-arm64.deb

# RootHide bootstrap shell
dpkg -i /path/to/mks_1.15.4_roothide_iphoneos-arm64e.deb
```

同一越狱环境可覆盖升级。安装脚本保留已有主配置、HTTP 状态和 Keychain 备份。首次安装时，当主配置不存在而原系统的 `/var/mobile/Media/mks.config` 存在，安装脚本会迁移这份旧配置。切换越狱环境后，两个安装根目录内的数据各自独立。需要先卸载旧包时，执行 `dpkg -r com.mks.spoof`，随后安装对应版本。

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

1.15.4 的 RootHide 包仅排除 akd，AppStore 与其他商店/账户进程保留注入；Rootless 过滤范围保持原样。目标进程重新启动时会加载更新后的 dylib。桌面重启只刷新 SpringBoard。需要刷新 akd、accountsd、amsaccountsd、appstored 或 itunesstored 时，在没有登录或下载进行时重启相关进程，并核对 PID 已变更。

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

1.15.4 的本机与真机升级检查见[验证记录](validation.md)。覆盖升级不自动重新生成参数；原来的停用/启用状态与配置继续保留。需要使用新生成规则时，通过既有一键改机入口显式执行。HTML 格式通过与 Apple 登录进程的属性一致性是独立的验收项。[参数规则](profile-rules.md) · [登录事件核查](login-incident.md)
