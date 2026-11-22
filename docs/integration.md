# MKS 1.15 核销系统对接

本页面向通过 USB 或局域网调用 MKS 的客户端维护者。协议细节和返回示例见 [HTTP API](http-api.md)。Rootless 与 RootHide 使用相同 v1 业务接口。

## 首次接入

1. 安装对应环境的 1.15 DEB，确认 MKS App 和 daemon 已启动。
2. 在电脑上通过 USB 读取实际 UDID。使用首尾去空白并转为大写后的值作为路由编号。
3. 在 MKS 的「未绑定设备 / 设备绑定」或「接口文档」填写这个编号并确认。root CLI 也可完成配置，需同时核对 JSON 与退出码。
4. 从 MKS App「接口文档」导入当前本机 token。客户端按设备保管授权，错误令牌会收到 401。
5. 使用实际 USB UDID 调用 `/v1/devices/{UDID}/status`。核对 `ok`、`deviceId`、`apiVersion`、`deviceConfigured`、`environment`、`capabilities` 与 `installationId`。

服务端监听设备端口 33237。USB 调用端可复用现有 usbmux 连接或本地端口转发，将目标端口映射到设备 33237；局域网调用可使用 App 显示的地址。HTTP 路径、Bearer 认证和任务语义相同。

首次配置未完成时，经过认证的请求返回 503、`device_id_not_configured`、`requiresLocalSetup:true`。客户端应停止无效重试，等待本地配置完成。401 表示授权需要核对。404 `device_not_found` 表示路由编号不匹配。服务不会通过序列号或改机值推算实际 USB UDID。

```python
import os
import requests

host = os.environ['MKS_HOST'].rstrip('/')
usb_udid = os.environ['MKS_USB_UDID'].strip().upper()
headers = {'Authorization': 'Bearer ' + os.environ['MKS_TOKEN']}
response = requests.get(
    f'{host}/v1/devices/{usb_udid}/status',
    headers=headers,
    timeout=10,
)
body = response.json()
if body.get('requiresLocalSetup'):
    raise RuntimeError('等待手机完成本地设备绑定')
response.raise_for_status()
assert body['ok'] and body['deviceConfigured']
assert body['apiVersion'] == 1 and body['deviceId'] == usb_udid
assert body['environment']['jailbreak'] in ('rootless', 'roothide')
assert all(body['capabilities'][name] for name in ('spoof', 'restore', 'keychainClean'))
installation_id = body['installationId']  # 随设备连接记录保存
```

## 执行与恢复

新操作先在客户端持久化动作和 `Idempotency-Key`，然后发送 POST。收到 202 后继续保存 `jobId`。三项动作分别是 `/spoof`、`/restore` 与 `/keychain/clean`，清理要求 `{"confirm":true}`。

断连或响应丢失后，用同一个 Key 重发相同动作以找回原 job，或使用已保存的 jobId 继续查询。相同 Key 的不同动作返回 409。账本最多保留 100 项，已被淘汰的 Key 不再具有去重记录，客户端需控制自动重试的生命周期。

| 观察结果 | 客户端动作 |
| --- | --- |
| queued / running | 查询同一 job |
| succeeded | 核对操作结果字段和实际设备状态 |
| failed，outcomeUnknown 为 false | 记录原 job，根据错误处理本地问题。需要再次执行时，由显式操作创建新 Key |
| interrupted 或 outcomeUnknown 为 true | 保留原 Key/job，核对设备与备份，再决定后续动作 |
| 503 job_save_failed | 核对账本存储。修复后重启服务，继续查原 job |
| USB 连接中断 | 重新建立到同一实际 USB UDID 的连接，继续查询原 job |

`respringCommandSucceeded:true` 表示命令成功。调用方仍需核验桌面恢复、输入服务和业务界面。App 关闭与 SpringBoard 重启后，daemon 应继续提供接口，前提是越狱及 daemon 仍有效。

## 1.15 参数规则与登录验收

`spoof` 在保存前检查新生成的 14 段参数规则。若失败，job 进入 failed，结果为 `profile_html_validation_failed`、`stage:profile_validate`、`profileSaved:false`、`retryable:false`、`outcomeUnknown:false`，配置和桌面均未改变。接口、任务和原配置读取规则继续兼容。

规则通过只表示格式和局部字段关系符合本地 HTML 校验。客户端仍应独立核验业务登录结果；`succeeded`、`profileValid:true`、桌面恢复与参数格式通过均不证明 Apple 登录所经进程实际读取一致。本轮已完成六进程主动采样，原事件与实际登录请求仍待复现，见[核查结论与诊断流程](login-incident.md)。

## 清理回执

清理成功要求 `result.ok:true`、`committed:true`、`backupCreated:true` 和 `backupFormatVersion:1`。保存 `backupId` 和 `deleted` 各表真实数量。`backup` 是本地诊断路径，旧客户端仍可读取该字段。

备份失败时本次数据库删除不执行。提交阶段故障可能返回 `cleanup_outcome_unknown` 和 `outcomeUnknown:true`，需核对原任务及备份后再处理。备份标识对应一次快照，不能单凭备份存在判断删除已提交。当前服务没有网络备份下载或恢复接口。

## 升级与环境变化

1.14 在既有状态目录生成非敏感的 `installation-id`，同时复用 token、device-id 与 jobs.json。同一目录的包升级及保留状态后重新安装会保留该标识。更换越狱环境或重新初始化状态目录会生成新标识。

客户端记录 installationId 可辅助识别状态目录变化。发现变化后重新核对本机授权和 USB 绑定。UDID、安装标识与 token 各自独立。旧 token 遇到新安装令牌时返回 401，需要重新导入授权。

## 对接验收

两种环境都需在真实设备逐项完成以下流程，并记录版本、安装标识、jobId、错误码、清理数量和提交结果。

- 首次未绑定、绑定成功、错误权限与格式、重新绑定确认。
- 覆盖升级与保留状态后重新安装，核对 token、设备编号及幂等记录。
- 关闭 App 后调用 daemon，执行三动作成功与失败流程。
- SpringBoard 重启后查询原 job，USB 中断后重连同一设备继续查询。
- 相同 Key 去重、不同动作冲突、错误 UDID 拒绝执行。
- 备份失败不删除，提交未知保留原 job，账本损坏时停止操作。

本版主机测试使用临时 SQLite 数据库，RootHide 主机路径使用合成 shim。模拟器绑定交互属于 1.14 历史验收；1.15 的安装和检查结果见[验证记录](validation.md)。六进程主动采样已完成；实际 Apple 登录请求及真实 Keychain 专用数据验收仍待执行。

Instruments 服务准备、唤屏、ZXTouch 输入、扫码付款和卡密核销状态由调用系统独立处理。MKS 只返回自身操作及诊断结果。
