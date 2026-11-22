# 全局 Keychain 清理：样本分析与 MKS 1.10

用户确认现有改机功能测试正常。本轮以本地 1.9 为基线，新增独立的全局清理入口；不增加目标 App 选择。

## 实际分析结果

样本 `App清理(1).deb` SHA-256：`3951e1bdbc54baed0af6b90931bd63bb36e92a67f9961dba6e1528329c0d92a8`。解包后包名 `com.123.cleanapps`，版本 `0.0.1`；`CleanApps` 为 arm64 iOS 可执行文件。原始包与程序未运行，安装脚本未执行。

Craft Anything **0.6.1** 实际执行 `apple-macho-show` 和 `native-strings-find`，定位 sqlite3 导入、数据库路径、SQL、按钮和方法名。REA **6.9.0** / Ghidra **12.2** 实际执行 overview 和四个函数反编译：

| 地址 | 观察 |
| --- | --- |
| `0x100008240` | `CleanRootViewController.cleanKeychain` 显示确认框 |
| `0x10000838c` | 确认回调调用 `AppTool.cleanKeychainDatabase`，按返回 BOOL 显示结果 |
| `0x100008ca8` | `AppTool.cleanKeychainDatabase` 打开 `/var/Keychains/keychain-2.db`，checkpoint 后依次执行五条 DELETE |
| `0x100009298` | `AppTool.fixKeychain` 查找 securityd PID 后构造 `cynject ... KeychainFix.dylib` 命令；上述确认回调没有调用它 |

样本 DELETE 规则如下，作用于全局数据库，不按 App bundle ID 过滤：

```sql
DELETE FROM genp WHERE agrp <> 'apple';
DELETE FROM cert WHERE agrp <> 'lockdown-identities';
DELETE FROM keys WHERE agrp <> 'lockdown-identities';
DELETE FROM inet;
DELETE FROM sqlite_sequence;
```

SQL 的 `<>` 不匹配 NULL，因此空 agrp 记录也保留。以上保留规则只代表指定表的指定组，不代表保留所有系统登录项。KeychainFix.dylib 没有包含在样本包内，其内部效果未建立。MKS 使用自身清理实现，不复制或执行该注入命令。

本地完整证据在 `diagnostics/keychain-cleaner-20261120/`，包含两个工具的 JSON、准确命令/退出码、四份伪代码及原包副本。

## MKS 的实现

- 新增独立「清理全局 Keychain」按钮及确认框。后台执行期间禁用重复点击，完成后显示已提交的删除数量和备份位置；通信结果不明确时不自动重试。
- root daemon 使用独立 Unix socket，核对内核提供的 peer UID、PID 和真实可执行文件路径。仅完整 DEB 的 MKS App 可调用。原 UDP PING/STATUS/RESPRING 接口不接受清理指令。
- 先校验现有数据库结构并取得写事务锁，再通过 SQLite backup API 保存包含 WAL 已提交数据的一致快照。备份失败不删除。
- 四个条目表采用与样本相同的谓词，在一个事务内删除；不存在 sqlite_sequence 时跳过该可选表。任何步骤出错则回滚，成功时核对剩余数量和数据库完整性后提交。
- 备份放在独立 root 所有的 越狱根目录下的 `var/lib/mks-keychain-backups`，避免放入 mobile 可写的配置目录。备份目录 0700，文件 0600；结果不输出密码、令牌或密钥内容。
- 对齐样本确认回调，只清理数据库；不注入缺失的 KeychainFix，也不自动终止 securityd 或重启桌面。
- 保留现有改机配置、共享路径和 hook 代码；清理不会更换改机参数，也不自动触发重启桌面。

备份是数据库快照；事务失败回滚已在合成数据库测试。源码回滚不会自动恢复已经清理的真机 Keychain，真机备份恢复也尚未验收。

## 验证与当前交付

`tests/test_keychain.py` 将真实清理代码编译后，仅对临时合成数据库执行：WAL 快照、受保护/NULL 分组、四表删除数量、重复清理、无 sqlite_sequence、触发器导致中途失败后的回滚、写锁冲突、缺失结构、文件权限及调用身份校验。没有访问或清理 Mac/iPhone 的真实 Keychain。

现有改机 385 项回归仍通过；另验证 daemon 拒绝 UDP 清理命令。双架构 DEB/IPA 均构建并核对载荷和签名。模拟器确认了按钮、确认框和模拟器反馈。

本轮检测到 USB 连接设备数为 0，因此新版本尚未安装到手机，真实 Keychain 清理效果仍待设备验收。历史 1.9 的改机已由用户确认测试正常。

复跑命令：

```sh
python3 tests/run_host_tests.py
python3 tests/test_keychain.py
python3 tests/test_daemon.py
python3 scripts/build.py
python3 tests/verify_packages.py
```

后续分析提示：

```text
复用同一 SHA-256 的 App清理样本与已保存 Ghidra checkpoint，追踪
0x10000838c -> 0x100008ca8。区分数据库 DELETE 的确切谓词、NULL 语义、
孤立的 fixKeychain 方法和实际按钮调用链。只用合成数据库验证删除与回滚；
保留既有 MKS 改机基线，真实设备结果单独记录。
```

## 1.11 HTTP 补充

1.11 增加 Bearer token 鉴权的 HTTP 清理任务入口，复用同一清理实现及互斥锁。原 Unix socket 仍核对 MKS 可执行路径。1.10 轮次未连接手机的状态属于历史；1.11 已安装到 USB 设备，但真实 Keychain 删除仍未执行。调用方式见 [HTTP API](http-api.md)。

## 1.12 验证补充

本轮复跑 65 项合成数据库检查通过；1.12 的共享映射修复不改变五条清理 SQL。真实设备未在本轮执行 Keychain 删除，改机与恢复不会自动调用清理。安装新版保留已有备份目录。
