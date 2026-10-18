#!/usr/bin/env python3
"""Cold-boot a Power Mac G4 template many times and check each Finder.

Each boot starts QEMU headless with guest_run.py's argument set (std-VGA with
the instruction-clock boot, or the ATI Radeon in real time) on an APFS clone
of the template disk, then:

  - first content: the first frame with more than two colours (the Mac OS
    gray with the Happy Mac; the ATI card shows a flat gray before it);
  - Finder: a light menu bar whose right end reads "Finder" (tesseract);
  - responsive: a click on the Apple menu opens it and a second click closes
    it (the guest's event loop runs);
  - otherwise, after --timeout: a hang, with HMP "info registers" and a frame
    kept (type B, the ROM timer-2 calibration race, ends in the nanokernel
    debugger with SRR0 0x6806D444).

QEMU is then quit and the clone deleted. --arm NAME='QEMU ARGS' interleaves
arms (boot k uses arm k mod the number of arms, so arms share the host's
load); --stress N runs N busy-looping processes for the whole run; --jobs runs
boots concurrently. --trace-t2 records the guest's VIA timer loads with host
timestamps (mos6522_set_counter), which shows how long the ROM's calibration
loops ran against their 1 ms deadline.

    boot_soak.py --qemu BIN --bios PC_BIOS --disk TEMPLATE/disk.img \\
        --out DIR --card ati --runs 10 [--display-option retroboot-display]

Writes DIR/results.jsonl (one line per boot) and prints a summary per arm.
"""
import argparse
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guest_run as G  # noqa: E402

REGS = re.compile(r"\b(NIP|LR|CTR|MSR|SRR0|SRR1|DAR)\s+([0-9a-fA-F]{8,16})")
T2_LOAD = re.compile(r"T(\d\d):(\d\d):(\d\d)\.(\d{6})Z mos6522_set_counter T2\.counter=(\d+)")


def screendump(rel, name):
    path = os.path.join(rel, name + ".ppm")
    G.hmp(rel, f"screendump {path}")
    with open(path, "rb") as f:
        data = f.read()
    parts = data.split(maxsplit=4)
    w, h = int(parts[1]), int(parts[2])
    return w, h, parts[4][-(w * h * 3):]


def colours(img, step=16):
    w, h, px = img
    seen = set()
    for y in range(0, h, step):
        for x in range(0, w, step):
            i = (y * w + x) * 3
            seen.add(px[i:i + 3])
    return len(seen)


def region_mean(img, x0, y0, x1, y1):
    w, h, px = img
    total = n = 0
    for y in range(y0, y1):
        row = px[(y * w + x0) * 3:(y * w + x1) * 3]
        total += sum(row)
        n += len(row)
    return total / max(n, 1)


def region_changed(a, b, x0, y0, x1, y1):
    """fraction of pixels that differ between two frames of the same size"""
    w, _, pa = a
    pb = b[2]
    diff = n = 0
    for y in range(y0, y1):
        for x in range(x0, x1, 2):
            i = (y * w + x) * 3
            n += 1
            if pa[i:i + 3] != pb[i:i + 3]:
                diff += 1
    return diff / max(n, 1)


def ocr_region(rel, img, x0, y0, x1, y1, scale=3):
    w, _, px = img
    rows = []
    for y in range(y0, y1):
        row = b"".join(px[(y * w + x) * 3:(y * w + x) * 3 + 3] * scale for x in range(x0, x1))
        rows.extend([row] * scale)
    path = os.path.join(rel, "ocr.ppm")
    with open(path, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % ((x1 - x0) * scale, (y1 - y0) * scale))
        f.write(b"".join(rows))
    try:
        return subprocess.run(["tesseract", path, "-"], capture_output=True,
                              text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def finder_visible(rel, img):
    w, h, _ = img
    if w < 512 or h < 384 or region_mean(img, 0, 2, w, 18) < 170:
        return False
    return "Finder" in ocr_region(rel, img, w - 140, 0, w, 20)


def click(rel, x, y, w, h):
    q = G.QMP(rel)
    try:
        q.cmd("input-send-event", events=G.abs_event(x, y, w, h))
        time.sleep(0.2)
        q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": True, "button": "left"}}])
        time.sleep(0.12)
        q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": False, "button": "left"}}])
    finally:
        q.close()


def responsive(rel, w, h):
    """the Apple menu opens on a click and closes on a second one"""
    before = screendump(rel, "resp0")
    click(rel, 18, 10, w, h)
    box = (0, 22, min(w, 260), min(h, 240))
    opened = 0.0
    for _ in range(10):
        time.sleep(0.5)
        menu = screendump(rel, "resp1")
        opened = region_changed(before, menu, *box)
        if opened > 0.05:
            break
    click(rel, 18, 10, w, h)
    closed = 1.0
    for _ in range(10):
        time.sleep(0.5)
        after = screendump(rel, "resp2")
        closed = region_changed(before, after, *box)
        if closed < 0.02:
            break
    return {"menu_opened": round(opened, 3), "menu_left": round(closed, 3),
            "responsive": opened > 0.05 and closed < 0.02}


def t2_loads(path):
    """T2 loads as (ms since the first, ticks) from a mos6522_set_counter trace"""
    loads = []
    try:
        with open(path, errors="replace") as f:
            for line in f:
                m = T2_LOAD.search(line)
                if m:
                    hh, mm, ss, us, ticks = (int(g) for g in m.groups())
                    loads.append((((hh * 60 + mm) * 60 + ss) * 1e6 + us, ticks))
    except OSError:
        return []
    if not loads:
        return []
    t0 = loads[0][0]
    return [(round((t - t0) / 1000, 3), v) for t, v in loads]


def boot(a, index, arm_name, arm_args, lock):
    rel = f"b{index:03d}-{arm_name}"
    os.makedirs(rel)
    disk = os.path.join(rel, "disk.img")
    subprocess.run(["cp", "-c", a.disk, disk], check=True)
    args = argparse.Namespace(
        out=rel, qemu=a.qemu, bios=a.bios, disk=disk, card=a.card, size=a.size,
        depth=a.depth, ram=512, name=a.name, icount=None,
        display_option=a.display_option, ndrvloader=a.ndrvloader,
        tools_cd=None, env=[], extra=[])
    argv = G.build_argv(args)
    # relative socket paths: macOS limits AF_UNIX paths to 104 bytes
    argv = [x.replace(os.path.abspath(rel), rel) for x in argv]
    argv[argv.index("-cpu") + 1] = a.cpu
    if a.trace_t2:
        argv += ["-trace", "mos6522_set_counter", "-msg", "timestamp=on",
                 "-D", os.path.join(rel, "trace.log")]
    argv += arm_args + a.extra
    with open(os.path.join(rel, "argv.json"), "w") as f:
        json.dump(argv, f, indent=1)
    r = {"boot": index, "arm": arm_name, "card": a.card,
         "load_at_start": round(os.getloadavg()[0], 2), "stress": a.stress}
    log = open(os.path.join(rel, "qemu.log"), "ab")
    t0 = time.time()
    proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log,
                            stderr=subprocess.STDOUT, start_new_session=True)
    try:
        while not os.path.exists(os.path.join(rel, "hmp.sock")):
            if proc.poll() is not None or time.time() - t0 > 20:
                raise RuntimeError("QEMU did not start")
            time.sleep(0.05)
        img = None
        while True:
            if proc.poll() is not None:
                raise RuntimeError(f"QEMU exited ({proc.returncode})")
            if time.time() - t0 > a.timeout:
                r["hang"] = True
                regs = G.hmp(rel, "info registers")
                with open(os.path.join(rel, "registers.txt"), "w") as f:
                    f.write(regs)
                r["registers"] = {k: v.lower() for k, v in REGS.findall(regs)}
                r["hang_type"] = "B" if r["registers"].get("SRR0", "").endswith("6806d444") else "?"
                G.shot(rel, "hang")
                break
            time.sleep(a.poll)
            img = screendump(rel, "boot")
            if "first_content_s" not in r and colours(img) > 2:
                r["first_content_s"] = round(time.time() - t0, 2)
            if "first_content_s" in r and finder_visible(rel, img):
                r["finder_s"] = round(time.time() - t0, 2)
                r["finder_size"] = f"{img[0]}x{img[1]}"
                break
        if "finder_s" in r:
            time.sleep(a.settle)
            r.update(responsive(rel, img[0], img[1]))
            if not r["responsive"]:
                G.shot(rel, "unresponsive")
    except Exception as exc:
        r["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        try:
            q = G.QMP(rel, timeout=5)
            q.cmd("quit")
            q.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        if a.trace_t2:
            loads = r["t2_loads"] = t2_loads(os.path.join(rel, "trace.log"))
            # Mac OS 9's ROM: one load with the interrupt off, then a warm-up
            # and a timed run per loop; a timed run that ends (next load)
            # before 1 ms ran out before its interrupt
            if len(loads) >= 8:
                r["t2_timed_runs_ms"] = [round(loads[i + 1][0] - loads[i][0], 3)
                                         for i in (2, 4, 6)]
        for f in os.listdir(rel):
            if f.endswith(".ppm"):
                os.unlink(os.path.join(rel, f))
        os.unlink(disk)
        r["ok"] = bool(r.get("responsive"))
        with lock:
            with open("results.jsonl", "a") as f:
                f.write(json.dumps(r) + "\n")
            state = "ok" if r["ok"] else ("HANG " + r.get("hang_type", "") if r.get("hang") else "FAIL")
            print(f"[{index:3d}] {arm_name:10s} {state:7s} first {r.get('first_content_s')} s, "
                  f"Finder {r.get('finder_s')} s, load {r['load_at_start']}"
                  + (f", {r['error']}" if "error" in r else ""), flush=True)
    return r


def summarize(results):
    arms = {}
    for r in results:
        arms.setdefault(r["arm"], []).append(r)
    for name, rs in arms.items():
        ok = [r for r in rs if r["ok"]]
        times = sorted(r["finder_s"] for r in ok)
        hangs = [r for r in rs if r.get("hang")]
        med = times[len(times) // 2] if times else None
        print(f"{name}: {len(ok)}/{len(rs)} responsive Finder; hangs {len(hangs)} "
              f"({', '.join(r.get('hang_type', '?') for r in hangs) or '-'}); "
              f"Finder min/median/max {times[0] if times else '-'}/{med}/"
              f"{times[-1] if times else '-'} s")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--qemu", required=True)
    ap.add_argument("--bios", required=True)
    ap.add_argument("--disk", required=True, help="template disk.img (cloned, never written)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--card", choices=("vga", "ati"), default="vga")
    ap.add_argument("--size", default="1024x768")
    ap.add_argument("--depth", type=int, default=15)
    ap.add_argument("--name", default="Power Mac G4")
    ap.add_argument("--cpu", default="7400")
    ap.add_argument("--display-option", action="append", default=[])
    ap.add_argument("--ndrvloader", default="shared/ndrvloader")
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--arm", action="append", default=[], help="NAME='QEMU ARGS'")
    ap.add_argument("--stress", type=int, default=0, help="busy-looping host processes")
    ap.add_argument("--timeout", type=float, default=90)
    ap.add_argument("--poll", type=float, default=0.5)
    ap.add_argument("--settle", type=float, default=3)
    ap.add_argument("--trace-t2", action="store_true")
    ap.add_argument("extra", nargs="*", help="QEMU arguments for every arm")
    a = ap.parse_args()
    for name in ("qemu", "bios", "disk", "ndrvloader"):
        setattr(a, name, os.path.abspath(getattr(a, name)))
    arms = []
    for spec in a.arm or ["default="]:
        name, _, args = spec.partition("=")
        arms.append((name, shlex.split(args)))
    os.makedirs(a.out, exist_ok=True)
    os.chdir(a.out)
    stress = [subprocess.Popen([sys.executable, "-I", "-c", "while True: pass"])
              for _ in range(a.stress)]
    lock = threading.Lock()
    results = []
    first = sum(1 for _ in open("results.jsonl")) if os.path.exists("results.jsonl") else 0
    try:
        queue = list(range(first, first + a.runs))
        qlock = threading.Lock()

        def worker():
            while True:
                with qlock:
                    if not queue:
                        return
                    i = queue.pop(0)
                name, args = arms[i % len(arms)]
                results.append(boot(a, i, name, args, lock))

        threads = [threading.Thread(target=worker) for _ in range(a.jobs)]
        for t in threads:
            t.start()
            time.sleep(1.5)
        for t in threads:
            t.join()
    finally:
        for p in stress:
            p.kill()
    summarize(results)
    return 0 if all(r["ok"] for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
