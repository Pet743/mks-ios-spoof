import socket, plistlib, struct, sys, time

MUX = "/var/run/usbmuxd"  # usbmuxd unix socket

def mux_connect(port=6000):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    s.connect(MUX)
    def recv_exact(n):
        b = b""
        while len(b) < n:
            c = s.recv(n - len(b))
            if not c: raise RuntimeError("mux eof")
            b += c
        return b
    def req(obj):
        payload = plistlib.dumps(dict({"ClientVersionString": "Recharge 0.1", "ProgName": "Recharge", "kLibUSBMuxVersion": 3}, **obj))
        s.sendall(struct.pack("<IIII", len(payload) + 16, 1, 8, 1) + payload)
        length, version, kind, _ = struct.unpack("<IIII", recv_exact(16))
        if length < 16: raise RuntimeError("bad header")
        return plistlib.loads(recv_exact(length - 16))
    devs = req({"MessageType": "ListDevices", "ClientVersionString": "libusbmuxd-1.0", "ProgName": "mks"}).get("DeviceList", [])
    if not devs: raise RuntimeError("no devices")
    dev = devs[0]
    r = req({"MessageType": "Connect", "DeviceID": dev["DeviceID"], "PortNumber": socket.htons(port), "ClientVersionString": "libusbmuxd-1.0", "ProgName": "mks"})
    if r.get("Number") != 0: raise RuntimeError("connect failed: %r" % r)
    return s

class ZX:
    def __init__(self):
        self.s = mux_connect()
        self.s.settimeout(10)
        self.buf = b""
    def line(self):
        while b"\r\n" not in self.buf:
            d = self.s.recv(4096)
            if not d: raise RuntimeError("closed")
            self.buf += d
        line, self.buf = self.buf.split(b"\r\n", 1)
        return line
    def send(self, task, *fields):
        payload = str(task) + ";;".join(str(f) for f in fields) + "\r\n"
        self.s.sendall(payload.encode())
    def cmd(self, task, *fields):
        self.send(task, *fields)
        return self.line().decode("utf-8", "replace").split(";;")
    def shot(self, path):
        self.send(30)
        fields = self.line().split(b";;")
        if len(fields) != 3 or fields[0] != b"0": raise RuntimeError("shot failed %r" % fields[:2])
        size = int(fields[2])
        while len(self.buf) < size:
            d = self.s.recv(65536)
            if not d: raise RuntimeError("eof")
            self.buf += d
        data, self.buf = self.buf[:size], self.buf[size:]
        open(path, "wb").write(data)
        return path
    def tap(self, x, y):
        self.send(10, "1101%05d%05d" % (int(x*10), int(y*10)))
        time.sleep(0.05)
        self.send(10, "1001%05d%05d" % (int(x*10), int(y*10)))

if __name__ == "__main__":
    z = ZX()
    print("size:", z.cmd(25, 1))
    print("fg:", z.cmd(25, 32))
    print("shot:", z.shot("/tmp/zx1.jpg"))
