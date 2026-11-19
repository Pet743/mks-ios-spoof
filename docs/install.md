# 安装说明

## 1. 前置条件

- 越狱设备（rootless `/var/jb`，Dopamine / palera1n rootless 等）
- ellekit 注入框架（检查 `/var/jb/usr/lib/libellekit.dylib` 是否存在）
- App 形式安装需要 TrollStore：`apt install com.opa334.trollstorelite`

## 2. 安装 Tweak

### 通过 deb

```bash
scp dist/mks_1.4.deb root@<设备IP>:/var/mobile/
ssh root@<设备IP> 'dpkg -i /var/mobile/mks_1.4.deb'
```

或用 Sileo：`包` → `...` → `安装本地 deb`。

### 手动方式

```bash
scp mks.dylib root@<设备IP>:/var/jb/Library/MobileSubstrate/DynamicLibraries/
scp mks.plist root@<设备IP>:/var/jb/Library/MobileSubstrate/DynamicLibraries/
ssh root@<设备IP> '
  chmod 755 /var/jb/Library/MobileSubstrate/DynamicLibraries/mks.dylib
  chown root:wheel /var/jb/Library/MobileSubstrate/DynamicLibraries/mks.*
  killall -9 SpringBoard
'
```

验证是否加载：

```bash
ssh root@<设备IP> 'cat /var/mobile/mks.log'
# 应看到：=== mks loaded pid=... active=1 ===
#         [*] hooks MG1=0x... MG2=0x... sc=0x...
```

## 3. 安装 App

1. 把 `dist/MKS-spoofer.ipa` 传到手机（AirDrop / scp / 文件 App）
2. 打开 **TrollStoreLite**
3. 右上角 `+` → `Install from URL`（输入 `file:///var/mobile/MKS-spoofer.ipa`）或 `Install IPA File`
4. 确认元数据里显示 `Bundle Identifier: com.mks.spoofer`、`Sandboxing: unsandboxed`
5. 点 `Install`

桌面出现「MKS 改机」图标。

> 如果提示 `Install Error 179`（bundle id 冲突），说明之前装过同 id 的 App。换一个 bundle id 重新打包（改 `app/Info.plist` 的 `CFBundleIdentifier`），或先卸载旧包：
> `dpkg -r com.mks.spoofapp && rm -rf /var/jb/Applications/MKS.app && uicache -a`

## 4. 验证

App 内：

- 状态显示「未改机（真实设备）」= 初始状态
- 点「一键改机」→ 状态变「已改机」并弹出参数

命令行验证（在 SpringBoard 里读才是伪造值）：

```bash
frida -U -n SpringBoard -l /dev/stdin <<'JS'
const f = new NativeFunction(Module.findGlobalExportByName('MGGetStringAnswer'),'pointer',['pointer']);
const mk = new NativeFunction(Module.findGlobalExportByName('CFStringCreateWithCString'),'pointer',['pointer','pointer','uint']);
const gs = new NativeFunction(Module.findGlobalExportByName('CFStringGetCString'),'bool',['pointer','pointer','long','uint']);
['ProductType','SerialNumber','ModelNumber','HardwareModel','ProductVersion'].forEach(k=>{
  const r=f(mk(ptr(0),Memory.allocUtf8String(k),0x08000100));
  const b=Memory.alloc(256); gs(r,b,256,0x08000100);
  console.log(k,'=',b.readUtf8String());
});
JS
```

## 5. 卸载

```bash
dpkg -r com.mks.spoof
killall -9 SpringBoard
```

TrollStore 装的 App：在 TrollStore 里左滑 → Uninstall，或长按桌面图标删除。

## 6. 常见问题

**Q: App 点改机没反应 / 状态不变**
检查 `/var/mobile/mks.log` 是否有 `mks loaded`。没有说明 tweak 没加载，确认 ellekit 是否正常、plist 是否在正确目录。

**Q: 改了但目标 App 还是识别真实机型**
该 App 可能读的是 IOKit（`IOPlatformSerialNumber`）或 IDFV，当前版本未覆盖，需要在 `answer_for_key` 或新增 hook 里扩展。

**Q: 想固定某一组参数，不要每次随机**
把 `tweak/mks.m` 里的参数写死，或在 App 生成后用 `echo "..." > /var/mobile/Media/mks.config` 固定。
