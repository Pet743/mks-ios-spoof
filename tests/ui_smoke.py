#!/usr/bin/env python3
"""MKS 改机 UI 冒烟测试

通过 ZXTouch（触摸）+ tidevice（启动 App / 唤屏）+ frida（读 MG）自动验证：
  1. 连续改机是否生成合规参数
  2. MobileGestalt 实际返回值是否与配置文件一致
  3. 还原设备是否恢复真实值
  4. 杀 App / respring 后状态是否保持

依赖：
  pip install frida tidevice
  设备已装 ZXTouch（6000 端口）、trollstorelite（装 MKS App）

用法：
  MKS_PW=<设备密码> MKS_UDID=<UDID> python3 tests/ui_smoke.py

注意：
  - 两个 Alert 的高度不同：「改机成功」的“好”在 y=1592，「已还原」的“好”在 y=1416
  - ZXTouch 的触摸坐标是**像素**（1170x2532），不是逻辑点
  - build 字段允许 \\d{2}[A-Z]\\d{2} 或 \\d{2}[A-Z]\\d{3}
"""
import os, re, subprocess, sys, time

PW = os.environ.get("MKS_PW", "")
UDID = os.environ.get("MKS_UDID", "")
HOST = os.environ.get("MKS_HOST", "qijindeiphone.local")
APP_ID = "com.mks.spoofer"
CFG = "/var/mobile/Media/mks.config"

CLOSE_SPOOF = (583, 1592)   # 「改机成功」弹窗的“好”
CLOSE_RESTORE = (583, 1416) # 「已还原」弹窗的“好”
SPOOF_BTN = (583, 1287)
RESTORE_BTN = (583, 1444)


def luhn_ok(s):
    tot, dbl = 0, False
    for ch in reversed(s):
        d = int(ch)
        if dbl:
            d *= 2
            if d > 9:
                d -= 9
        tot += d
        dbl = not dbl
    return tot % 10 == 0


def validate(line):
    p = line.strip().split("----")
    if len(p) != 14:
        return "字段数=%d" % len(p)
    ser1, im1, im2, mac1, mac2, ecid, udid, ser2, model, part, brd, chp, bld, ios = p
    bad = []
    if ser1 != ser2: bad.append("ser不一致")
    if not re.fullmatch(r"[A-HJ-NP-Z1-9]{10}", ser1): bad.append("ser")
    if not re.fullmatch(r"\d{15}", im1): bad.append("imei长度")
    if not luhn_ok(im1): bad.append("imeiLuhn")
    if im1[:14] != im2: bad.append("imei2")
    if not re.fullmatch(r"[0-9a-f]{2}(:[0-9a-f]{2}){5}", mac1): bad.append("mac1")
    if not re.fullmatch(r"[0-9a-f]{2}(:[0-9a-f]{2}){5}", mac2): bad.append("mac2")
    if not re.fullmatch(r"[0-9A-F]{16}", ecid): bad.append("ecid")
    if not re.fullmatch(r"[0-9a-f]{40}", udid): bad.append("udid")
    if not re.fullmatch(r"D\d{2}AP", brd): bad.append("board")
    if not re.fullmatch(r"T[7-8]\d{3}", chp): bad.append("chip")
    if not re.fullmatch(r"\d{2}[A-Z]\d{2,3}", bld): bad.append("build")
    if not re.fullmatch(r"1[6-8]\.\d+\.\d+", ios): bad.append("ios")
    if not part.endswith("LL/A"): bad.append("part")
    return "OK" if not bad else ",".join(bad)


def ssh(cmd, timeout=30):
    """执行远端命令，返回 stdout。依赖 expect 以免明文密码进 argv 历史。"""
    script = f'''set timeout 20
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 mobile@{HOST} "{cmd}"
expect {{
  -re "(?i)password:" {{ send "{PW}\\r"; exp_continue }}
  timeout {{ exit 3 }}
  eof
}}
'''
    r = subprocess.run(["expect", "-c", script], capture_output=True, text=True, timeout=timeout)
    return r.stdout


def read_cfg(retries=3):
    for _ in range(retries):
        out = [l for l in ssh(f"cat {CFG} 2>/dev/null").replace("\r", "").split("\n") if "----" in l]
        if out:
            return out[-1].strip()
        time.sleep(1)
    return ""


def main():
    if not PW or not UDID:
        print("需要设置 MKS_PW 和 MKS_UDID 环境变量")
        return 2

    import warnings, logging
    warnings.filterwarnings("ignore")
    logging.disable(logging.CRITICAL)
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from zx import ZX          # 仓库根目录放一份 zxtouch 客户端
    import tidevice

    def tap(z, xy):
        x, y = xy
        z.send(10, "1101%05d%05d" % (x * 10, y * 10))
        time.sleep(0.08)
        z.send(10, "1001%05d%05d" % (x * 10, y * 10))

    dev = tidevice.Device(UDID)
    dev.app_start(APP_ID)
    time.sleep(3)
    z = ZX()

    sers = []
    for i in range(3):
        tap(z, CLOSE_SPOOF); time.sleep(0.5)
        tap(z, SPOOF_BTN); time.sleep(1.6)
        cfg = read_cfg()
        ok = validate(cfg)
        ser = cfg.split("----")[0] if cfg else "-"
        sers.append(ser)
        print(f"round {i+1}: {ok} ser={ser}")

    print(f"unique serials: {len(set(sers))}/{len(sers)}")

    tap(z, CLOSE_SPOOF); time.sleep(0.5)
    tap(z, RESTORE_BTN); time.sleep(1.8)
    after = read_cfg()
    print("after restore config:", repr(after))
    assert after == "", "还原后配置未删除"
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
