# MKS 1.14 HTTP API · v1

MKS 通过独立的 root daemon 提供 HTTP 服务。在 1.12 已验证的 Rootless 设备上，强制关闭 MKS App、重启桌面后仍可调用；前提是 daemon 仍运行、越狱环境有效，且调用端能连接手机网络。App 右上角「接口文档」展示当前 Wi‑Fi 地址、设备编号、访问令牌与完整示例，右上角「复制」可复制文档。

2026-11-20 补充了三轮真机专项测试：每轮启动并强制关闭 App，确认 App 进程消失后，分别通过 HTTP 执行改机和恢复。六次操作均返回 202 并进入 succeeded，六次均观察到桌面 PID 更换；重启后的 18 次状态查询全部返回 200，daemon PID 始终不变。测试结束后恢复原参数，没有执行真实 Keychain 清理。

这里的「重启桌面」仅指 SpringBoard 重启，不是整机重启。整机重启、退出越狱、daemon 被停止或网络断开时，不保证接口可用；本轮未测试整机重启后的服务恢复。

1.14 增加本地首次绑定、状态描述和备份标识。v1 路由、原状态字段、Bearer 认证、USB UDID 路由、幂等 Key/job 与清理提交语义继续兼容。上述 1.11 / 1.12 真机记录属于历史验收。1.14 本轮的验证范围见文末。

## 连接与设备标识

默认监听 IPv4 `0.0.0.0:33237`，用于同一可信 Wi‑Fi。访问使用随机生成的本机 Bearer token，保存在越狱根目录下的 `var/lib/mks-http/token`，不上传到服务器。HTTP 本身未加密，不将端口映射到公网。

设备路由使用 USB 连接报告的 UDID，独立保存在越狱根目录下的 `var/lib/mks-http/device-id`；MKS 的随机改机参数不会覆盖它。UDID 用于选设备，token 用于授权，两者用途不同。

首次在新设备安装时，从电脑 USB 工具获取实际 UDID。MKS App 的「未绑定设备 / 设备绑定」或「接口文档」可输入并确认编号；App 通过现有受控 Unix socket 请求 root daemon 写入。daemon 核对本地 UID 和 App 路径，并比较用户确认的原编号，防止旧确认覆盖其他更新。

CLI 入口也可在设备 root shell 使用。

```sh
# Rootless
/var/jb/usr/libexec/mksd --set-device-id 'USB_DEVICE_UDID'

# RootHide bootstrap shell
/usr/libexec/mksd --set-device-id 'USB_DEVICE_UDID'
```

UDID 接受 8 位十六进制、连字符、16 位十六进制，或 40 位十六进制。输入会去除首尾空白并转为大写。CLI 成功时 stdout 输出以下 JSON，退出 0，写入已完成原子发布、权限设置、文件与目录同步及回读校验。

```json
{"ok":true,"deviceId":"00000000-0000000000000000","configured":true,"outcomeUnknown":false}
```

| CLI 退出码 | error | 处理 |
| --- | --- | --- |
| 1 | `permission_denied` | 使用本地 App 或 root CLI |
| 2 | `invalid_device_id` / `invalid_arguments` | 核对参数与 USB UDID 格式 |
| 3 | `state_directory_unavailable` / `persistence_failed` / `device_id_state_invalid` / `device_id_readback_failed` | 检查安装和状态目录，先查询现值 |
| 5 | `resource_busy` | 配置锁正被其他进程持有，稍后核对 |

App 重新绑定会显示原值和新值并要求确认。若期间原值改变，返回 `device_id_changed`，需重新读取并确认。CLI 是 root 明确执行的设置命令，可直接更新已有编号。配置入口只接受设备编号，文件路径由服务固定。

配置、令牌和幂等账本在同一环境内升级保留。尚未配置设备编号时，经过 Bearer 认证的 HTTP 返回以下结果。错误令牌仍返回 401。此状态需要完成本地配置。

```json
{"ok":false,"error":"device_id_not_configured","stage":"device_setup","requiresLocalSetup":true,"retryable":false,"outcomeUnknown":false}
```

HTTP 状态码为 503。未绑定状态可直接在本地 App 查询。HTTP 保持设备路由和认证规则，不新增初始化网络入口。

## 快速调用

将地址、设备编号、令牌替换为 App 文档中的实际值：

```sh
export MKS_HOST='http://PHONE_WIFI_IP:33237'
export MKS_DEVICE='USB_DEVICE_UDID'
export MKS_TOKEN='TOKEN_FROM_APP_DOCUMENTATION'
export MKS_BASE="$MKS_HOST/v1/devices/$MKS_DEVICE"

# 状态查询
curl -H "Authorization: Bearer $MKS_TOKEN" "$MKS_BASE/status"

# 一键改机：生成参数、保存、重启桌面
curl -X POST "$MKS_BASE/spoof" \
  -H "Authorization: Bearer $MKS_TOKEN" \
  -H 'Idempotency-Key: spoof-001' \
  -H 'Content-Type: application/json' -d '{}'

# 恢复原机：写入停用记录、重启桌面
curl -X POST "$MKS_BASE/restore" \
  -H "Authorization: Bearer $MKS_TOKEN" \
  -H 'Idempotency-Key: restore-001' \
  -H 'Content-Type: application/json' -d '{}'

# 全局 Keychain 清理：备份后按参考插件的规则清理，不重启桌面
curl -X POST "$MKS_BASE/keychain/clean" \
  -H "Authorization: Bearer $MKS_TOKEN" \
  -H 'Idempotency-Key: clean-001' \
  -H 'Content-Type: application/json' -d '{"confirm":true}'

# 使用 POST 返回的 jobId 查询结果
curl -H "Authorization: Bearer $MKS_TOKEN" "$MKS_BASE/jobs/JOB_ID"
```

`confirm` 必须是 JSON 布尔值 `true`，字符串或数字不接受。三个操作只接受 POST。改机/恢复请求体为 `{}`，不接受远端传入 shell 命令、数据库路径或任意参数。

## 接口与返回

路径前缀统一为 `/v1/devices/{UDID}`：

| 方法 | 路径 | 行为 |
| --- | --- | --- |
| GET | `/status` | 版本、deviceId、配置有效性、enabled、环境、能力与安装身份 |
| POST | `/spoof` | 随机生成并保存参数，自动重启桌面 |
| POST | `/restore` | 停用改机，自动重启桌面 |
| POST | `/keychain/clean` | 全局清理，要求 `confirm:true` |
| GET | `/jobs/{jobId}` | 查询任务状态和结果 |

认证后的状态示例。`deviceId` 必须与电脑从 USB 读取并规范化后的 UDID 一致。

```json
{
  "ok":true,
  "version":"1.14",
  "apiVersion":1,
  "deviceId":"00000000-0000000000000000",
  "deviceConfigured":true,
  "enabled":false,
  "profileValid":true,
  "environment":{"jailbreak":"roothide","layoutVersion":1},
  "capabilities":{"spoof":true,"restore":true,"keychainClean":true},
  "installationId":"00000000-0000-4000-8000-000000000001"
}
```

`environment.jailbreak` 为 `rootless` 或 `roothide`。`layoutVersion` 描述本版安装布局。能力字段描述该构建实现的操作，任务仍可能因设备状态失败。`installationId` 是非敏感的随机 UUID，存储在本环境状态目录，首次启动时生成；同目录升级、卸载后保留状态再安装时复用。更换越狱环境或重新创建状态目录会产生新值。它独立于设备 UDID 和 Bearer token。状态响应不包含令牌。

POST 返回 HTTP 202：

```json
{"jobId":"EXAMPLE-JOB-ID","action":"spoof","state":"queued","createdAt":1234567890}
```

这仅表示任务已持久化并进入队列。查询返回 `queued`、`running`、`succeeded`、`failed` 或 `interrupted`。成功改机/恢复示例：

```json
{
  "jobId":"EXAMPLE-JOB-ID",
  "action":"restore",
  "state":"succeeded",
  "result":{
    "ok":true,
    "profileSaved":true,
    "enabled":false,
    "respringCommandSucceeded":true,
    "error":null
  }
}
```

响应发送后才调度执行，改机/恢复保存成功后自动重启桌面，手机短暂黑屏。`respringCommandSucceeded` 表示重启命令返回成功；实际桌面恢复由调用方或设备观察核对。若保存成功、重启失败，任务返回 `failed`，其中 `profileSaved:true`；不要误认为所有改动都未执行。

Keychain 成功结果增量包含稳定备份标识。`backup` 保留本地诊断路径，客户端应记录 `backupId` 并核对 `backupCreated` 和 `backupFormatVersion`。

```json
{
  "ok":true,
  "committed":true,
  "stage":"complete",
  "deleted":{"genp":0,"inet":0,"cert":0,"keys":0},
  "backupId":"00000000-0000-4000-8000-000000000002",
  "backupCreated":true,
  "backupFormatVersion":1,
  "backup":"ABSOLUTE_PATH_FOR_LOCAL_DIAGNOSTICS",
  "retryable":false,
  "outcomeUnknown":false
}
```

格式 1 是 SQLite 一致快照。备份在数据库删除前完成快照、完整性校验、文件及目录同步，备份失败则撤回事务。只有 COMMIT 返回成功才设置 `committed:true`。提交阶段发生错误或回滚失败时设置 `outcomeUnknown:true`，这时 `committed:false` 表示未确认提交。此时保留原 Key/job 先核对结果。备份存在也可能对应清理失败，不能单凭 `backupCreated` 判定清理成功。当前接口不提供按备份 ID 下载或恢复的操作。

App 与 HTTP 清理使用同一个后端及操作锁。沿用参考插件的保护组和 NULL 语义，具体范围见 [Keychain 说明](keychain-cleaner.md)。

## 超时和幂等

每个 POST 必须带 `Idempotency-Key`，长度 1–128，允许字母、数字和 `- _ : .`。每次**新操作**使用新 Key；同一操作因网络问题重试时使用原 Key，返回原任务，不重复执行。相同 Key 换用另一种操作返回 409。

任务按接收顺序串行执行。队列与 Key 保存到越狱根目录下的 `var/lib/mks-http/jobs.json`，最多保留最近 100 项；达到上限时只淘汰已结束任务。被淘汰的 Key 不再具备去重记录。daemon 重启时将遗留 queued/running 任务标记 interrupted，不自动重放。

出现 interrupted 或 `outcomeUnknown:true` 时，先核对 `/status`、配置及备份，而不是换新 Key 自动重试。状态文件损坏、存在重复 jobId/Key 或完成记录缺少结果时，HTTP listener 拒绝启动，保留原账本。运行中写账本或结果失败时，服务拒绝接收新任务；仍可查询内存中已有任务。修复存储后重启服务，进行中的账本记录将标记 interrupted。

## Python 示例

```python
import os
import time
import uuid
import requests

base = os.environ['MKS_BASE']
headers = {'Authorization': 'Bearer ' + os.environ['MKS_TOKEN']}
operation_key = str(uuid.uuid4())  # 应随业务任务持久化；超时重试复用它
response = requests.post(base + '/spoof', json={}, timeout=10,
                         headers={**headers, 'Idempotency-Key': operation_key})
response.raise_for_status()
job_id = response.json()['jobId']
deadline = time.monotonic() + 60
while time.monotonic() < deadline:
    reply = requests.get(base + '/jobs/' + job_id, headers=headers, timeout=10)
    reply.raise_for_status()
    job = reply.json()
    if job['state'] not in ('queued', 'running'):
        print(job)
        break
    time.sleep(0.5)
else:
    raise TimeoutError('保留 operation_key 和 job_id，稍后继续查询')
```

## 错误码

| HTTP | 含义 |
| --- | --- |
| 200 | 查询成功 |
| 202 | 任务已接受，包含幂等重复返回 |
| 400 | 格式、请求体、确认值或幂等 Key 错误 |
| 401 | 缺少或错误的 Bearer token |
| 403 | 浏览器 Origin/Referer 请求被拒绝；不提供跨站调用 |
| 404 | UDID、路由或任务不存在 |
| 405 | 操作接口要求 POST |
| 409 | 相同 Key 用于不同操作 |
| 413 | 请求头超过 8 KiB 或 body 超过 4 KiB |
| 415 | POST Content-Type 不是 application/json |
| 503 | 未配置设备编号、队列已满或任务持久化失败 |

以下 `error` 值保持稳定。任务执行错误位于 job 的 `result`，HTTP 业务请求错误位于顶层。

| error | stage | retryable / outcomeUnknown | 调用方处理 |
| --- | --- | --- | --- |
| `unauthorized` | authentication | false / false | 更新本机授权，重新查询 |
| `device_id_not_configured` | device_setup | false / false | `requiresLocalSetup:true`，等待本地绑定 |
| `device_not_found` | device_route | false / false | 核对真实 USB UDID 与绑定值 |
| `queue_full` | queue | true / false | 等待后使用原 Key |
| `job_save_failed` | persistence | false / false | 检查存储，核对原 job，修复后重启 |
| `result_save_failed` | persistence | false / true | 核对原 job 与设备实际状态 |
| `daemon_restarted` | recovery | false / true | interrupted，核对原 job 与设备实际状态 |
| `profile_save_failed` / `profile_owner_failed` | profile_save / profile_owner | false / false | 核对配置写入和权限 |
| `respring_failed` | respring | false / false | 配置可能已保存，核对桌面与 profileSaved |
| `resource_busy` | lock | true / false | 清理尚未提交，等待资源恢复 |
| `backup_failed` | backup | false / false | 本次未删除，检查备份目录 |
| `cleanup_failed` / `cleanup_verify_failed` | delete / verify | false / false | 清理失败且已回滚，核对诊断 |
| `cleanup_outcome_unknown` | commit 或实际失败阶段 | false / true | 保留原 Key/job，禁止自动新建清理重试 |

`retryable` 表示是否适合暂时等待后再次处理。已有 job 的重试仍返回原 job，重新执行必须作为新的显式操作。调用方遇到 `outcomeUnknown:true` 应优先核对结果，即使同一响应还有其他字段。CLI 与 App 配置错误位于 `device_setup` 阶段，`persistence_failed` 的 `outcomeUnknown` 反映原子发布后的目录同步是否确认。

监听最多同时处理 8 条连接，每条请求读取总期限 5 秒，不支持 chunked、重复头字段、HTTP pipelining 或 URL 中的令牌。

## 已验证范围

1.14 的 Rootless、RootHide 分支均通过主机 CLI、App Unix socket、HTTP 绑定路由、幂等和故障回归。RootHide 的主机路径使用合成 shim，iOS DEB 使用固定校验的官方 SDK 构建。模拟器验证未绑定、输入错误、确认及服务未就绪提示。1.14 真机安装、真实 root 权限、App peer 路径校验、三动作与 USB 断连恢复仍需设备验收。真实 Keychain 删除使用专用测试数据后再验收。[验证记录](validation.md)
