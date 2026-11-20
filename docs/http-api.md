# MKS 1.11 HTTP API

MKS 通过 root daemon 提供 HTTP 服务，关闭 App 或重启桌面后仍可调用。App 右上角「接口文档」展示当前 Wi‑Fi 地址、设备编号、访问令牌与完整示例，右上角「复制」可复制文档。

## 连接与设备标识

默认监听 IPv4 `0.0.0.0:33237`，用于同一可信 Wi‑Fi。访问使用随机生成的本机 Bearer token，保存在 `/var/jb/var/lib/mks-http/token`，不上传到服务器。HTTP 本身未加密，不将端口映射到公网。

设备路由使用 USB 连接报告的 UDID，独立保存在 `/var/jb/var/lib/mks-http/device-id`；MKS 的随机改机参数不会覆盖它。UDID 用于选设备，token 用于授权，两者用途不同。

首次在新设备安装时，从 USB 工具获取该设备实际 UDID，然后在设备 root shell 配置一次：

```sh
/var/jb/usr/libexec/mksd --set-device-id 'USB_DEVICE_UDID'
```

配置和令牌在升级时保留。尚未配置设备编号时，HTTP 返回 `503 device_id_not_configured`。更换设备应重新配置，不复制另一台手机的 device-id 文件。

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
| GET | `/status` | 当前版本、deviceId、配置有效性与 enabled |
| POST | `/spoof` | 随机生成并保存参数，自动重启桌面 |
| POST | `/restore` | 停用改机，自动重启桌面 |
| POST | `/keychain/clean` | 全局清理，要求 `confirm:true` |
| GET | `/jobs/{jobId}` | 查询任务状态和结果 |

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

Keychain 成功结果包含 `committed:true`、`deleted` 各表数量和 `backup` 路径；与 App 中独立清理使用同一个后端及操作锁。沿用参考插件的保护组和 NULL 语义，具体范围见 [Keychain 说明](keychain-cleaner.md)。

## 超时和幂等

每个 POST 必须带 `Idempotency-Key`，长度 1–128，允许字母、数字和 `- _ : .`。每次**新操作**使用新 Key；同一操作因网络问题重试时使用原 Key，返回原任务，不重复执行。相同 Key 换用另一种操作返回 409。

任务按接收顺序串行执行。队列与 Key 保存到 `/var/jb/var/lib/mks-http/jobs.json`，最多保留最近 100 项；达到上限时只淘汰已结束任务。被淘汰的 Key 不再具备去重记录。daemon 重启时将遗留 queued/running 任务标记 interrupted，不自动重放。

出现 interrupted 或 `outcomeUnknown:true` 时，先核对 `/status`、配置及备份，而不是换新 Key 自动重试。状态文件损坏时服务停止接收 HTTP 操作，避免丢掉去重记录后重复执行。

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

监听最多同时处理 8 条连接，每条请求读取总期限 5 秒，不支持 chunked、重复头字段、HTTP pipelining 或 URL 中的令牌。

## 已验证范围

本机测试运行真实 HTTP 服务与操作实现，使用临时配置、合成 Keychain 数据库和可观察的假重启函数。真机已通过同一 Wi‑Fi 验证改机/恢复 HTTP 202、任务完成、实际桌面 PID 更换、幂等重试；测试后恢复了原配置。真实 Keychain 删除未在该轮执行，仅验证缺少确认值返回 400。验收见 [验证记录](validation.md)。
