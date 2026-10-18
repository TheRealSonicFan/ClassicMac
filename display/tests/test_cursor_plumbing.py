#!/usr/bin/env python3
"""std-VGA hardware cursor -> CURSOR / MOUSE, without a guest disk.

Mac OS 9 is not needed to exercise the path: QEMU starts mac99 with std-VGA
and -global VGA.hardware-cursor=on, OpenBIOS stops at its prompt
(auto-boot? false), and the test client types Forth at that prompt with the
protocol's KEY messages (QEMU's ADB keyboard). The Forth programs the QEXT
cursor registers exactly as ClassicMac's NDRV does (byte-swapped 32-bit
stores at BAR2 + 0x600): a 16 x 16 ARGB image whose quadrants are opaque
red, green, blue and transparent, hot spot (3, 4), then DEFINE+MOVE, a move
and a hide. The client must receive the image as CURSOR and each position
as MOUSE. (OpenBIOS echoes on the black-on-black screen, so the messages
are the only evidence; that is the point.)

usage: test_cursor_plumbing.py QEMU_SYSTEM_PPC PC_BIOS_DIR [OUT_DIR]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmdclient as C  # noqa: E402

# written as ARGB (0xAARRGGBB), the QEXT format the NDRV uses
QUADRANTS = {"top-left": 0xFFFF0000, "top-right": 0xFF00FF00,
             "bottom-left": 0xFF0000FF, "bottom-right": 0x00000000}
SHIFTED = {":": "semicolon", "!": "1", "+": "equal", "*": "8"}
PLAIN = {";": "semicolon", " ": "spc", "-": "minus", ".": "dot", "\r": "ret"}


def type_line(c, text):
    for ch in text + "\r":
        if ch in SHIFTED:
            keys = ("shift", SHIFTED[ch])
        elif ch in PLAIN:
            keys = (PLAIN[ch],)
        else:
            keys = (ch,)
        c.tap(*keys, hold=0.03)
        c.pump(0.02)
    c.pump(0.3)


def rb_swap(v):
    return (v & 0xff00ff00) | ((v >> 16) & 0xff) | ((v & 0xff) << 16)


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    qemu, bios = sys.argv[1], sys.argv[2]
    out = os.path.abspath(sys.argv[3]) if len(sys.argv) == 4 else None
    tmp = tempfile.mkdtemp(prefix="cmdc", dir="/tmp")
    sock, qmp = (os.path.join(tmp, n) for n in ("d.sock", "q.sock"))
    c = C.DisplayClient(sock)
    argv = [qemu, "-M", "mac99,via=cuda", "-cpu", "7400", "-m", "256",
            "-L", bios, "-vga", "std", "-global", "VGA.host-resize=on",
            "-global", "VGA.hardware-cursor=on",
            "-prom-env", "auto-boot?=false", "-g", "800x600x32",
            "-display", f"classicmac,socket={sock}",
            "-qmp", f"unix:{qmp},server=on,wait=off",
            "-serial", "none", "-monitor", "none", "-nic", "none"]
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT,
                         start_new_session=True)
    result = {"argv": argv}
    try:
        c.accept(10)
        c.pump(8)                       # OpenBIOS up to its prompt
        q = C.QMP(qmp)
        pci = q.hmp("info pci")
        q.close()
        block = pci[pci.index("1234:1111"):]
        bar2 = int(re.search(r"BAR2: 32 bit memory at (0x[0-9a-f]+)", block).group(1), 16)
        result["bar2"] = hex(bar2)
        n_cur, n_mouse = len(c.cursors), len(c.mice)
        type_line(c, "hex")
        type_line(c, f"{bar2 + 0x600:x} constant qx")
        type_line(c, ": q qx + swap lbflip swap l! ;")
        type_line(c, ": b 8 0 do 8 0 do 2dup j 10 * i + + 4 * 100 + q loop loop 2drop ;")
        for base, key in ((0, "top-left"), (8, "top-right"),
                          (0x80, "bottom-left"), (0x88, "bottom-right")):
            type_line(c, f"{QUADRANTS[key]:x} {base:x} b")
        type_line(c, "10 18 q 10 1c q 3 20 q 4 24 q")
        type_line(c, "64 28 q 78 2c q 1 30 q 3 34 q")   # (100,120) visible, DEFINE|MOVE
        c.pump(0.5)
        type_line(c, "c8 28 q 96 2c q 2 34 q")          # move to (200,150)
        c.pump(0.3)
        type_line(c, "0 30 q 2 34 q")                   # hide
        c.pump(0.5)
        cursors = c.cursors[n_cur:]
        mice = [tuple(m[1:]) for m in c.mice[n_mouse:]]
        result["cursor_msgs"] = len(cursors)
        result["mouse"] = mice
        if not cursors:
            raise RuntimeError(f"no CURSOR message (MOUSE {mice})")
        _, hx, hy, w, h, px = cursors[-1]
        quads = {"top-left": px[0], "top-right": px[8],
                 "bottom-left": px[8 * 16], "bottom-right": px[8 * 16 + 8]}
        result["cursor"] = {
            "hot": [hx, hy], "size": [w, h],
            "quadrants_written_argb": {k: f"0x{v:08x}" for k, v in QUADRANTS.items()},
            "quadrants_received": {k: f"0x{v:08x}" for k, v in quads.items()}}
        if all(quads[k] == v for k, v in QUADRANTS.items()):
            result["byte_order"] = "ARGB 0xAARRGGBB, as written"
        elif all(quads[k] == rb_swap(v) for k, v in QUADRANTS.items()):
            result["byte_order"] = ("red and blue swapped: 0xAABBGGRR "
                                    "(vga-hardware-cursor.patch's conversion)")
        else:
            result["byte_order"] = "unexpected"
        checks = {
            "cursor geometry": (w, h, hx, hy) == (16, 16, 3, 4),
            "mouse after define": (100, 120, 1) in mice,
            "mouse after move": (200, 150, 1) in mice,
            "mouse hidden": mice[-1:] == [(200, 150, 0)],
            "pixels ARGB 0xAARRGGBB": result["byte_order"].startswith("ARGB"),
        }
        result["checks"] = checks
        result["ok"] = all(checks.values())
        print(json.dumps(result, indent=1))
        if out:
            os.makedirs(out, exist_ok=True)
            with open(os.path.join(out, "cursor-plumbing.json"), "w") as f:
                json.dump(result, f, indent=1)
        sys.exit(0 if result["ok"] else 1)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        c.close()
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
