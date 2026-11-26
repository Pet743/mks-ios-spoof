# 新设备：Mac + USB 安装 MKS RootHide

适用于已运行 RootHide 越狱环境的 iPhone，包括 RootHide Dopamine。本文使用电脑上的 `pymobiledevice3` 传文件和转发 USB 端口，在手机的 RootHide shell 内用 `dpkg` 安装完整 DEB。Rootless 请使用[通用安装说明](install.md)中的对应包和 `/var/jb` 路径。

## 1. 准备手机

- 保持手机已越狱，Sileo 可以打开，安装好该环境的 `ellekit` 和 `roothide`。
- 在 Sileo 安装 OpenSSH，并确认 SSH 服务正在运行。RootHide Dopamine 不一定存在单独的 Bootstrap App；通过实际 SSH 服务判断，不必寻找固定名称的开关。
- 使用越狱时设置的 `mobile` 密码。SSH 密码与锁屏密码是不同的凭据，不要默认两者一致；安装时由 SSH 和 `sudo` 交互询问。
- USB 连接并解锁手机，在手机上信任此电脑。

MKS 不依赖 ZXTouch 或 Python；需要触控自动化时再安装适配本环境的 ZXTouch。电脑上安装的 Python 与手机上的 Python 是两套环境。

## 2. 准备电脑并读取真实 USB UDID

在 Mac 的终端执行，以下步骤都在同一工作目录内进行。需要 Python 3.9 或更新版本。

```sh
mkdir -p "$HOME/Downloads/mks-usb-install"
cd "$HOME/Downloads/mks-usb-install"
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pymobiledevice3
python -m pymobiledevice3 usbmux list
```

从输出中选中 `ConnectionType` 为 `USB` 的目标手机，复制其 `Identifier`。多台设备时逐台操作，后续命令始终指定同一个 UDID。

```sh
export MKS_UDID='USB_DEVICE_UDID'
printf '%s\n' "$MKS_UDID" > device.udid
chmod 600 device.udid
```

`USB_DEVICE_UDID` 必须替换为电脑刚读到的值。它用于选择物理手机和绑定接口路由，不能使用 MKS 生成的随机 `UniqueDeviceID`。

## 3. 下载最新正式版并校验

下面脚本通过 GitHub `releases/latest` 选择唯一的 RootHide DEB，核对 Release 提供的 SHA-256，然后保存为固定文件名 `MKS-roothide.deb`。下次安装重新运行即可，无需修改版本号。元数据保存在本地 `release.json`，用于核对实际下载版本。

```sh
python - <<'PY'
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

def fetch(url):
    request = Request(url, headers={'User-Agent': 'MKS-USB-Install'})
    with urlopen(request, timeout=60) as response:
        return response.read()

release = json.loads(fetch('https://api.github.com/repos/Pet743/mks-ios-spoof/releases/latest'))
matches = [a for a in release['assets']
           if a['name'].endswith('_roothide_iphoneos-arm64e.deb')]
if len(matches) != 1:
    raise SystemExit('Release 中没有唯一的 RootHide DEB，请检查发布页面。')
asset = matches[0]
expected = (asset.get('digest') or '').removeprefix('sha256:')
if len(expected) != 64:
    sums = next(a for a in release['assets'] if a['name'] == 'SHA256SUMS')
    entries = [line.split() for line in fetch(sums['browser_download_url']).decode().splitlines()]
    expected = next(parts[0] for parts in entries
                    if len(parts) == 2 and parts[1].lstrip('*') == asset['name'])
data = fetch(asset['browser_download_url'])
actual = hashlib.sha256(data).hexdigest()
if actual != expected:
    raise SystemExit('SHA-256 不匹配，文件未写入。')
Path('MKS-roothide.deb').write_bytes(data)
Path('release.json').write_text(json.dumps(release, ensure_ascii=False, indent=2))
print('Release:', release['tag_name'])
print('Asset:', asset['name'])
print('SHA256:', actual)
print('校验通过：MKS-roothide.deb')
PY
```

## 4. 开启 USB SSH 转发

另开一个 Mac 终端，执行并保持运行：

```sh
cd "$HOME/Downloads/mks-usb-install"
. .venv/bin/activate
python -m pymobiledevice3 usbmux forward --udid "$(cat device.udid)" 2222 22
```

这里 `2222` 是电脑端口，`22` 是手机 SSH 端口。如果手机的 SSH 实际监听 `2222`，只将命令最后的 `22` 改为 `2222`。转发进程运行不等于手机 SSH 已开启，下一步能够登录才算连通。

回到原来的 Mac 终端，验证 SSH 登录：

```sh
ssh -o HostKeyAlias="mks-usb-$MKS_UDID" -p 2222 mobile@127.0.0.1
```

首次连接确认手机主机密钥，输入该手机的 SSH 密码。`HostKeyAlias` 为每台手机保存独立记录，便于以后使用同一电脑端口安装其他设备。登录后先执行以下命令，再 `exit` 回到 Mac：

```sh
dpkg --print-architecture
dpkg-query -W -f='${Package} ${Version} ${Status}\n' ellekit roothide
exit
```

RootHide 应输出 `iphoneos-arm64e`，两个依赖应为 `install ok installed`。如果为其他架构，先重新确认环境和 DEB 选择。

## 5. USB 传包并安装

在 Mac 原终端执行。拉回一份并比较，确认 USB 传输后的文件完全一致：

```sh
python -m pymobiledevice3 afc push --udid "$MKS_UDID" MKS-roothide.deb /MKS-roothide.deb
python -m pymobiledevice3 afc pull --udid "$MKS_UDID" /MKS-roothide.deb USB-readback.deb
cmp MKS-roothide.deb USB-readback.deb && echo 'USB 传输校验通过'
ssh -o HostKeyAlias="mks-usb-$MKS_UDID" -p 2222 mobile@127.0.0.1
```

以下在手机 SSH shell 执行。已有配置时可先执行文末的备份步骤。

```sh
sudo dpkg -i /rootfs/var/mobile/Media/MKS-roothide.deb
dpkg-query -W -f='${Package} ${Version} ${Architecture} ${Status}\n' com.mks.spoof
sudo launchctl list com.mks.daemon
uiopen --bundleid com.mks.spoofer
```

**路径说明：** AFC 的 `/MKS-roothide.deb` 是原系统的 `/var/mobile/Media/MKS-roothide.deb`。RootHide shell 通过 `/rootfs/var/mobile/Media/MKS-roothide.deb` 访问它；在该 shell 中直接使用 `/var/mobile/Media` 可能找到另一份目录。包内文件则使用 `/Applications/MKS.app`、`/usr/libexec/mksd` 等 RootHide shell 路径，不需要自己拼接随机 `.jbroot-*` 目录。

安装应出现 `Setting up com.mks.spoof`；查询结果应为所下载版本、`iphoneos-arm64e` 和 `install ok installed`。后台服务应有有效 `PID`，并且没有反复异常退出。打开手机上的 MKS，核对 App 版本与 `release.json` 对应的 Release 一致。1.15.12 的 App build 为 128。

退出手机 shell 后，可以清理传包文件；电脑仍保留已校验的 DEB：

```sh
exit
python -m pymobiledevice3 afc rm --udid "$MKS_UDID" /MKS-roothide.deb
```

## 6. 新设备绑定 HTTP 编号

仅使用 App 的一键改机按钮时可以跳过；HTTP 对接必须先绑定真实 USB UDID。推荐打开 MKS →「接口文档」→「绑定 USB 设备编号」，填写第二步的值。

也可以在 Mac 原终端执行下面的命令。`-t` 让远端 `sudo` 正常询问密码，UDID 从当前终端变量传入：

```sh
ssh -t -o HostKeyAlias="mks-usb-$MKS_UDID" -p 2222 mobile@127.0.0.1 \
  "sudo /usr/libexec/mksd --set-device-id '$MKS_UDID'"
```

成功返回包含 `ok:true`、正确 `deviceId`、`configured:true` 的 JSON，退出码为 0。之后在 App 的「接口文档」查看地址和令牌，按 [HTTP 文档](http-api.md)查询 `/v1/devices/{USB_UDID}/status`，确认 `version`、`environment.jailbreak=roothide`、`deviceConfigured=true`。

接口返回 `device_id_not_configured` 表示还没有完成绑定，不能只凭 `33237` 端口可连接判断已可对接。绑定编号与改机参数分别存储，覆盖升级复用原值。

## 7. 安装后验收和旧版排查

安装检查不需要自动改机。需要实际验证时，在没有账户登录或下载进行的情况下，手动点击一次「一键改机」，等待桌面重启，解锁并重新打开 MKS，检查新参数和启用状态。此操作会生成一组新身份。

| 检查点 | 通过条件 |
| --- | --- |
| 安装包 | 官方最新正式版的 RootHide DEB，SHA-256 一致 |
| 包状态 | `com.mks.spoof` 为目标版本且 `install ok installed` |
| App | 版本与 Release 一致，能打开并读取配置 |
| 后台服务 | `launchctl list com.mks.daemon` 有 PID，服务正常响应 |
| HTTP（需要对接时） | 已绑定物理 USB UDID，`/status` 返回正确版本和环境 |
| 实际改机（用户主动测试） | 新参数生成、桌面重启、重开后仍启用且配置有效 |

同一环境下覆盖安装会更新 App、插件和 daemon，原配置继续保留。怀疑旧版影响时，先查上述三处版本和包状态；不要因为仍显示旧参数就删除配置。仅删除桌面 App 不一定卸载整个 DEB，使用 `dpkg-query` 判断实际安装状态。相同 Bundle ID 的独立 IPA 也应排除，确保打开的是 DEB 注册的 App。

1.15.12 RootHide 在改机/恢复时自动刷新认证及商店进程后重启桌面，正常流程不需要另外逐个 `killall`。若使用 HTTP 测试改机，提交返回的是异步任务：继续查询 `/jobs/{jobId}`，直到 **`state`** 为 `succeeded`，并核对 `result.profileSaved` 与 `result.respringCommandSucceeded`；`queued`、`running` 或 HTTP 202 都不表示已完成。刷新清单和注入清单的用途不同；例如 1.15.12 会刷新 `amsaccountsd`，但正式包未选择向它注入。

RootHide 可能在安装时给可执行文件写入本机 brand 并更新代码签名页哈希，因此安装后 daemon 的整个文件 SHA-256 可能与 DEB 内不同。先校验下载包和传输文件；判断运行中是否为新版时结合包版本、App、服务与实际行为，不要仅据这一哈希差异判定为旧版残留。

## 备份与回退

覆盖升级前，可在手机 RootHide SSH shell 中备份现有配置、HTTP 状态和 Keychain 备份目录。不存在的目录跳过；备份目录仅 root 可读：

```sh
sudo /bin/sh -c '
umask 077
backup="/var/tmp/mks-before-install-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
for name in mks mks-http mks-keychain-backups; do
  if [ -e "/var/lib/$name" ]; then
    cp -a "/var/lib/$name" "$backup/"
  fi
done
printf "Backup: %s\n" "$backup"
'
```

需要回退程序时，从 [Releases](https://github.com/Pet743/mks-ios-spoof/releases)选择同一环境的旧版完整 DEB，重新校验、USB 传输并用 `sudo dpkg -i` 覆盖安装；回退程序不等于恢复旧参数。只想停止改机时，使用 App 的「恢复原机」。HTTP 状态目录包含访问令牌，备份留在本机私有目录，不要提交仓库。Keychain 清理及其备份恢复属于独立操作，安装验收不需要执行。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| USB 列表为空或读取失败 | 解锁手机、确认信任电脑，检查数据线和 USB 连接；不要用随机改机 UDID 选设备。 |
| SSH 连接被拒绝 | 确认已安装且运行 OpenSSH，核对手机实际端口；转发使用的是手机端口，不是电脑端口。 |
| `Permission denied` | 使用该手机设置的 SSH 用户和密码；通常为 `mobile`，不等于锁屏密码。 |
| `sudo` 要求密码或 `dpkg` 权限不足 | 在交互 SSH shell 内执行 `sudo`；从 Mac 单条执行需要密码的命令时加 `ssh -t`。 |
| 找不到 AFC 传入的 DEB | 在 RootHide shell 使用 `/rootfs/var/mobile/Media/...`；按第五步拉回比较确认目标手机与文件名。 |
| 架构不匹配或缺少依赖 | RootHide 选择 `iphoneos-arm64e`，先装该环境的 ElleKit 和 RootHide 核心包，避免混用 Rootless DEB。 |
| 新设备提示缺少仓库签名公钥 | 检查对应官方源和 keyring；不使用关闭签名校验的命令。MKS 本身不要求为了安装额外添加 Python 源。 |
| `dpkg` 提示其他包缺少 Description/Maintainer | 检查最终退出码和 `com.mks.spoof` 状态；其他包的元数据警告不能代替 MKS 安装结果。 |
| 桌面没有 App 或打开的仍像旧版 | 核对包版本；在手机 RootHide shell 执行 `sudo uicache -p /Applications/MKS.app`，再排除独立 IPA 的同 Bundle ID 冲突。 |
| 新版仍显示升级前参数 | 覆盖升级保留配置属正常行为，主动「一键改机」后才生成新参数；不要直接删除状态目录。 |

完成后，在运行 USB 转发的终端按 Ctrl+C 结束转发。下次换新设备时，重新读取并保存 `device.udid`，不要复用上一台手机的编号。
