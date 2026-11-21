# MKS 1.12 安装与升级

设备需要 `/var/jb` rootless 环境及 ElleKit。完整 DEB 包含 App、注入库、daemon、Keychain 清理与 HTTP 服务。

设备 root shell：

```sh
dpkg -i /path/to/mks_1.12.deb
```

如需先删除旧包再安装新版，可先备份配置和 HTTP 状态目录，执行 `dpkg -r com.mks.spoof`，再执行上述安装命令。`dpkg -r` 保留 `/var/jb/var/lib/mks`、`mks-http` 和 Keychain 备份目录；这与删除账号或清理 Keychain 是不同操作。

安装脚本创建配置目录、备份目录和 HTTP 状态目录，迁移旧配置（已有主配置优先），加载 daemon 并注册 App。设备 Bundle ID 为 `com.mks.spoofer`。仅更新独立 IPA 不会安装/更新 daemon；需要完整功能时使用 DEB 的 App，避免保留相同 Bundle ID 的两个安装位置。

## HTTP 设备编号

首次部署时，从 USB 工具确认手机的实际 UDID，在 root shell 配置一次：

```sh
/var/jb/usr/libexec/mksd --set-device-id 'USB_DEVICE_UDID'
```

使用实际编号替换占位符。编号独立保存，升级保留；不要复制另一台设备的 HTTP 状态目录。打开 App 右上角「接口文档」可获取当前地址、令牌和调用案例。详见 [HTTP 文档](http-api.md)。同一 Wi-Fi 默认 `33237` 端口，Bearer token 随首次 daemon 启动生成。

## 升级后进程刷新

重启目标进程后才会加载新 dylib。仅重启桌面不会刷新已运行的 akd、accountsd、amsaccountsd、appstored、itunesstored；旧库从磁盘删除后仍可能留在旧进程映射中。更新注入库后，在没有登录/下载进行时刷新相关进程并核对模块。1.12 修正共享映射中的 `ProductName`：保留系统名称原值。升级后应刷新曾加载旧库的相关进程，避免继续运行旧映射。应核对刷新前后的 PID 确实变化；本次发现部分 daemon 对普通 TERM 未退出，随后在没有认证/下载进行时定向结束这些旧进程，并由系统重新拉起。仅命令返回成功不算完成升级。

一键改机和恢复原机现在均自动重启桌面；Keychain 清理保持独立，不自动重启桌面或 securityd。HTTP 先返回持久化任务编号，再执行操作，需查询任务结果。

## 文件位置

| 用途 | 路径与权限 |
| --- | --- |
| 主改机配置 | `/var/jb/var/lib/mks/mks.config`，mobile 可写，0644 |
| HTTP 状态目录 | `/var/jb/var/lib/mks-http`，root:mobile，0750 |
| 访问令牌 / 设备编号 | 上述目录 `token`、`device-id`，root:mobile，0640 |
| HTTP 任务 | 上述目录 `jobs.json`，root，0600 |
| Keychain 备份 | `/var/jb/var/lib/mks-keychain-backups`，root:wheel，0700；文件 0600 |

恢复原机写入明确的 `enabled:false` 记录，不是删除配置文件。它不恢复已经删除的 Keychain。安装脚本不会清空已有 Keychain、令牌、任务或备份。

## 本轮设备验收

已通过 USB 安装 1.12，验证三个程序文件与本地构建一致、Bearer 鉴权、UDID 路由、局域网请求、改机/恢复的任务完成与实际桌面进程更换、重复 Key 去重。测试后恢复了手机原先的参数。真实 Keychain 删除未执行，详见 [验证记录](validation.md)。
