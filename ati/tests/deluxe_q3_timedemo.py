#!/usr/bin/env python3
"""Quake III Arena Demo timedemo on the public Mac OS 9.2.2 Deluxe v6 machine.

A repeatable 3D workload for the emulated ATI Radeon R100 (and for CPU A/B
comparisons): boot an APFS clone of the template disk on the ATI card at
1024x768, open Macintosh HD > Games > Quake III Arena Demo > MacQuake3, run
``timedemo 1; demo demo001`` and read Quake's own result line
("N frames, T seconds: F fps") with tesseract. QEMU is stopped afterwards;
the clone is disposable and is deleted unless --keep-disk.

    deluxe_q3_timedemo.py --qemu BIN --bios PC_BIOS --disk TEMPLATE/disk.img \\
        --out DIR [--cpu 7400] [--ndrvloader shared/ndrvloader] [-- QEMU ARGS]

Writes DIR/result.json and screenshots; prints the result as JSON.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guest_run as G  # noqa: E402

LINE = re.compile(r"(\d+)\s*frames[,.]?\s*([\d.,]+)\s*seconds?[:;,.]?\s*([\d.,]+)\s*fps", re.I)


def ppm(out, name):
    path = os.path.abspath(os.path.join(out, name + ".ppm"))
    G.hmp(out, f"screendump {path}")
    with open(path, "rb") as f:
        data = f.read()
    parts = data.split(maxsplit=4)
    w, h = int(parts[1]), int(parts[2])
    return w, h, parts[4][-(w * h * 3):]


def region_mean(img, x0, y0, x1, y1):
    w, h, px = img
    total = n = 0
    for y in range(y0, y1):
        row = px[(y * w + x0) * 3:(y * w + x1) * 3]
        total += sum(row)
        n += len(row)
    return total / max(n, 1)


def ocr(png):
    try:
        return subprocess.run(["tesseract", png, "-"], capture_output=True,
                              text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def ocr_region(out, img, x0, y0, x1, y1, scale=3):
    """OCR a crop of a screendump, enlarged (tesseract misses 12 px text)"""
    w, h, px = img
    rows = []
    for y in range(y0, y1):
        row = b"".join(px[(y * w + x) * 3:(y * w + x) * 3 + 3] * scale for x in range(x0, x1))
        rows.extend([row] * scale)
    path = os.path.join(out, "ocr-crop.ppm")
    with open(path, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % ((x1 - x0) * scale, (y1 - y0) * scale))
        f.write(b"".join(rows))
    return ocr(path)


def key(out, *keys):
    for k in keys:
        G.hmp(out, f"sendkey {k}")
        time.sleep(0.15)


def type_text(out, text):
    for ch in text:
        k = {" ": "spc", ".": "dot", "-": "minus"}.get(ch)
        if k is None:
            k = f"shift-{ch.lower()}" if ch.isupper() else ch
        G.hmp(out, f"sendkey {k}")
        time.sleep(0.08)


def click(out, x, y, double=False):
    q = G.QMP(out)
    try:
        q.cmd("input-send-event", events=G.abs_event(x, y, 1024, 768))
        time.sleep(0.2)
        for _ in range(2 if double else 1):
            q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": True, "button": "left"}}])
            time.sleep(0.08)
            q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": False, "button": "left"}}])
            time.sleep(0.12)
    finally:
        q.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--qemu", required=True)
    ap.add_argument("--bios", required=True)
    ap.add_argument("--disk", required=True, help="template disk.img (cloned, never written)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cpu", default="7400")
    ap.add_argument("--ndrvloader", default="shared/ndrvloader")
    ap.add_argument("--boot-timeout", type=float, default=180)
    ap.add_argument("--demo-timeout", type=float, default=300)
    ap.add_argument("--keep-disk", action="store_true")
    ap.add_argument("extra", nargs="*", help="more QEMU arguments (after --)")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=False)
    disk = os.path.join(out, "disk.img")
    subprocess.run(["cp", "-c", a.disk, disk], check=True)
    result = {"qemu": a.qemu, "cpu": a.cpu, "extra": a.extra}
    args = argparse.Namespace(
        out=out, qemu=a.qemu, bios=a.bios, disk=disk, card="ati", size="1024x768",
        depth=32, ram=512, name="Deluxe v6", icount=False,
        display_option=["retroboot-display"], ndrvloader=a.ndrvloader,
        tools_cd=None, env=[], extra=a.extra)
    argv = G.build_argv(args)
    argv[argv.index("-cpu") + 1] = a.cpu
    with open(os.path.join(out, "argv.json"), "w") as f:
        json.dump(argv, f, indent=1)
    log = open(os.path.join(out, "qemu.log"), "ab")
    proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log,
                            stderr=subprocess.STDOUT, start_new_session=True)
    with open(os.path.join(out, "qemu.pid"), "w") as f:
        f.write(str(proc.pid))
    t0 = time.time()
    try:
        while not os.path.exists(os.path.join(out, "hmp.sock")):
            if proc.poll() is not None:
                raise RuntimeError("QEMU exited at start")
            time.sleep(0.1)
        time.sleep(1)
        # Finder: 1024x768 and the menu bar's "Finder" item, by OCR
        while True:
            if time.time() - t0 > a.boot_timeout:
                raise RuntimeError("no Finder")
            time.sleep(1)
            img = ppm(out, "boot")
            if img[0] != 1024:
                continue
            if "Finder" in ocr_region(out, img, 900, 0, 1024, 20):
                G.shot(out, "finder")
                break
        result["boot_to_finder_s"] = round(time.time() - t0, 1)
        time.sleep(3)
        click(out, 974, 55, double=True)          # Macintosh HD
        time.sleep(3)
        type_text(out, "Games")
        key(out, "meta_l-o")
        time.sleep(3)
        type_text(out, "Quake 3")
        key(out, "meta_l-o")
        time.sleep(3)
        type_text(out, "MacQuake3")
        key(out, "meta_l-o")
        t_launch = time.time()
        while True:
            if time.time() - t_launch > 120:
                G.shot(out, "launch-failed")
                raise RuntimeError("Quake did not switch to 640x480")
            time.sleep(2)
            if ppm(out, "launch")[0] == 640:
                break
        time.sleep(20)                            # intro, menu
        result["q3_launch_s"] = round(time.time() - t_launch, 1)
        G.shot(out, "q3-menu")
        key(out, "grave_accent")
        time.sleep(2)
        type_text(out, "timedemo 1")
        key(out, "ret")
        time.sleep(1.5)
        type_text(out, "demo demo001")
        key(out, "ret")
        t_demo = time.time()
        seen, gone = False, 0
        while time.time() - t_demo < a.demo_timeout:
            time.sleep(2)
            img = ppm(out, "demo")
            hud = img[0] == 640 and region_mean(img, 600, 440, 640, 480) > 30
            if hud:
                seen, gone = True, 0
                continue
            if seen:
                gone += 1
                if gone >= 2:
                    break
        result["demo_wall_s"] = round(time.time() - t_demo, 1)
        key(out, "grave_accent")
        time.sleep(2)
        G.shot(out, "result-console")
        # the console's upper half, enlarged: tesseract misses Quake's 8 px font
        text = ocr_region(out, ppm(out, "result-console"), 0, 0, 640, 236)
        for line in text.splitlines():
            m = LINE.search(line)
            if m:
                num = lambda s: float(s.replace(",", "."))
                result.update(line=line.strip(), frames=int(m.group(1)),
                              seconds=num(m.group(2)), fps=num(m.group(3)))
        q = G.QMP(out)
        try:
            result["x_accel_stats"] = q.cmd("qom-get", path="/machine/peripheral/ati0",
                                            property="x-accel-stats")
            result["x_gl_renderer"] = q.cmd("qom-get", path="/machine/peripheral/ati0",
                                            property="x-gl-renderer")
        finally:
            q.close()
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        try:
            q = G.QMP(out, timeout=5)
            q.cmd("quit")
            q.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, 9)
            proc.wait()
        for f in os.listdir(out):
            if f.endswith(".ppm"):
                os.unlink(os.path.join(out, f))
        if not a.keep_disk:
            os.unlink(disk)
        with open(os.path.join(out, "result.json"), "w") as f:
            json.dump(result, f, indent=1)
        print(json.dumps(result))
    return 0 if "fps" in result else 2


if __name__ == "__main__":
    sys.exit(main())
