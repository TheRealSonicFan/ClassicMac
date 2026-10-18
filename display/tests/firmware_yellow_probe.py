#!/usr/bin/env python3
"""Where does OpenBIOS's pale yellow show? Watch every frame of a boot.

Boots a disk (APFS clone, deleted afterwards) with -display classicmac and
measures, for the frames delivered during the first seconds, the share of
pale-yellow pixels (OpenBIOS's palette entry 0, 0xFFFFCC). Run it once with
the firmware build-qemu.sh stages (background patched to black) and once
with the unpatched screamer/openbios-ppc (--firmware) to see the difference.

    firmware_yellow_probe.py --qemu BIN --bios PC_BIOS --disk DISK.img \\
        --card vga|ati --out DIR [--firmware openbios-ppc] [--seconds 20]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmdclient as C  # noqa: E402


def yellow_share(c, step=13):
    s = c.surface
    buf = c.frame
    n = yellow = 0
    total = s["stride"] * s["height"]
    for a in range(0, total, 4 * step):
        b, g, r = buf[a], buf[a + 1], buf[a + 2]
        n += 1
        if r > 200 and g > 200 and b < r - 25:
            yellow += 1
    return yellow / max(n, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qemu", required=True)
    ap.add_argument("--bios", required=True)
    ap.add_argument("--disk", required=True)
    ap.add_argument("--card", choices=("vga", "ati"), required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--firmware", help="openbios-ppc to use instead of BIOS's")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--ndrvloader", default="shared/ndrvloader")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="cmdy", dir="/tmp")
    bios = a.bios
    if a.firmware:
        bios = os.path.join(tmp, "pc-bios")
        shutil.copytree(a.bios, bios)
        shutil.copy(a.firmware, os.path.join(bios, "openbios-ppc"))
    disk = os.path.join(out, "disk.img")
    subprocess.run(["cp", "-c", a.disk, disk], check=True)
    sock = os.path.join(tmp, "d.sock")
    c = C.DisplayClient(sock)
    argv = [a.qemu, "-accel", "tcg,tb-size=512"]
    if a.card == "vga":
        argv += ["-icount", "shift=4,sleep=off"]
    argv += ["-M", "mac99,via=cuda", "-cpu", "7400", "-m", "512", "-L", bios]
    if a.card == "vga":
        argv += ["-vga", "std", "-global", "VGA.host-resize=on",
                 "-global", "VGA.vgamem_mb=64", "-global", "VGA.packed-lowbpp=on",
                 "-global", "VGA.untracked-vram=on",
                 "-global", "VGA.hardware-cursor=on",
                 "-global", "VGA.classicmac-boot-handoff=on",
                 "-g", "1024x768x15"]
    else:
        argv += ["-vga", "none", "-device",
                 "ati-vga,id=ati0,model=r100,vgamem_mb=32,romfile=,guest_hwcursor=on,"
                 "xres=1024,yres=768,refresh_rate=75000",
                 "-prom-env", "classicmac-display=1024x768",
                 "-prom-env", "retroboot-display=1024x768",
                 "-g", "640x480x32"]
    argv += ["-global", "macio-ide.dma-completion-delay-ns=0",
             "-prom-env", "output-device=ttya",
             "-display", f"classicmac,socket={sock}",
             "-monitor", "none", "-serial", "none", "-nic", "none",
             "-drive", f"file={disk},format=raw,media=disk",
             "-device", f"loader,addr=0x4000000,file={os.path.abspath(a.ndrvloader)}",
             "-prom-env", "boot-command=init-program go",
             "-device", "virtio-tablet-pci"]
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.STDOUT, start_new_session=True)
    t0 = time.time()
    timeline = []
    first_yellow = None
    try:
        c.accept(10)
        last = -1.0
        while time.time() - t0 < a.seconds:
            n = len(c.damage)
            c.pump(0.05)
            if not c.surface:
                continue
            now = time.time() - t0
            if (len(c.damage) != n or not timeline) and now - last >= 0.1:
                last = now
                share = yellow_share(c)
                size = (c.surface["width"], c.surface["height"])
                if not timeline or timeline[-1]["size"] != list(size) or \
                        abs(timeline[-1]["yellow"] - share) > 0.01:
                    timeline.append({"t": round(now, 2), "size": list(size),
                                     "yellow": round(share, 3)})
                if share > 0.02 and first_yellow is None:
                    first_yellow = now
                    c.snapshot(os.path.join(out, "first-yellow.png"))
        frames = len(c.damage)
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        c.close()
        shutil.rmtree(tmp, ignore_errors=True)
        os.unlink(disk)
    result = {"card": a.card, "firmware": a.firmware or "staged (build-qemu.sh)",
              "seconds": a.seconds, "damage_msgs": frames,
              "first_yellow_s": round(first_yellow, 2) if first_yellow else None,
              "timeline": timeline}
    with open(os.path.join(out, "yellow.json"), "w") as f:
        json.dump(result, f, indent=1)
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
