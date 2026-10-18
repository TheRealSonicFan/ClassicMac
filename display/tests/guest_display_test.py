#!/usr/bin/env python3
"""Boot a Mac OS 9 machine through -display classicmac and exercise it.

The test client (cmdclient.py) plays the ClassicMac app: it listens on the
display socket, QEMU connects, and every frame shown here is the client's
private copy updated only from DAMAGE rectangles. QEMU runs headless with
ClassicMac's Power Mac arguments (std-VGA with its globals and the icount
boot, or the ATI Radeon R100), a QMP socket for the clock-handoff fallback
and quitting, and the classicvirtio tablet for absolute pointing.

    guest_display_test.py --qemu BIN --bios PC_BIOS --disk DISK.img \\
        --out DIR --scenario vga|ati [--size 1024x768] [--depth 15|32]

The disk is APFS-cloned into DIR and deleted afterwards (--keep-disk keeps
it). Writes DIR/report.json, DIR/frames/*.png and DIR/qemu.log; QEMU is
always stopped.
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmdclient as C  # noqa: E402

EDID_MAX_CLOCK_KHZ = 162000


def edid_refresh(w, h):
    for hz in (75, 60, 50):
        xb, yb = w * 35 // 100, h * 35 // 1000
        if hz * 1000 * (w + xb) * (h + yb) // 10000000 * 10 <= EDID_MAX_CLOCK_KHZ:
            return hz
    return None


def build_argv(a, sock, qmp, disk):
    w, h = (int(v) for v in a.size.split("x"))
    argv = [a.qemu, "-accel", "tcg,tb-size=512"]
    if a.scenario == "vga":
        argv += ["-icount", "shift=4,sleep=off"]
    argv += ["-M", "mac99,via=cuda,audiodev=snd0", "-cpu", "7400",
             "-m", "512", "-L", a.bios]
    if a.scenario == "vga":
        argv += ["-vga", "std",
                 "-global", "VGA.host-resize=on", "-global", "VGA.vgamem_mb=64",
                 "-global", "VGA.packed-lowbpp=on",
                 "-global", "VGA.untracked-vram=on",
                 "-global", "VGA.hardware-cursor=on",
                 "-global", "VGA.classicmac-boot-handoff=on"]
        boot = f"{w}x{h}x{a.depth}"
    else:
        dev = "ati-vga,id=ati0,model=r100,vgamem_mb=32,romfile=,guest_hwcursor=on"
        hz = edid_refresh(w, h)
        if hz and (w, h) != (640, 480):
            dev += f",xres={w},yres={h},refresh_rate={hz * 1000}"
        argv += ["-vga", "none", "-device", dev,
                 "-prom-env", f"classicmac-display={w}x{h}",
                 "-prom-env", f"retroboot-display={w}x{h}"]
        boot = "640x480x32"
    argv += ["-global", "macio-ide.dma-completion-delay-ns=0",
             "-prom-env", "output-device=ttya", "-g", boot,
             "-name", "display test", "-audiodev", "none,id=snd0",
             "-display", f"classicmac,socket={sock}",
             "-qmp", f"unix:{qmp},server=on,wait=off",
             "-monitor", "none",
             "-action", "reboot=shutdown",
             "-serial", "none",
             "-drive", f"file={disk},format=raw,media=disk",
             "-drive", "if=ide,index=3,media=cdrom,id=cd0,readonly=on",
             "-drive", "if=ide,index=2,media=cdrom,id=tools0,readonly=on",
             "-nic", "none"] + a.extra + [
             "-device", f"loader,addr=0x4000000,file={a.ndrvloader}",
             "-prom-env", "boot-command=init-program go",
             "-device", "virtio-tablet-pci"]
    return argv


def cpu_seconds(pid):
    out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)],
                         capture_output=True, text=True).stdout.strip()
    if not out:
        return None
    parts = out.replace("-", ":").split(":")
    secs = 0.0
    for p in parts:
        secs = secs * 60 + float(p)
    return secs


def is_yellow(rgb):
    r, g, b = rgb
    return r > 180 and g > 180 and b < r - 25


def stats(values):
    if not values:
        return None
    v = sorted(values)
    return {"n": len(v), "mean": round(sum(v) / len(v), 2),
            "p50": round(v[len(v) // 2], 2),
            "p95": round(v[min(len(v) - 1, int(len(v) * 0.95))], 2),
            "max": round(v[-1], 2)}


class Run:
    def __init__(self, a):
        self.a = a
        self.out = os.path.abspath(a.out)
        os.makedirs(os.path.join(self.out, "frames"), exist_ok=True)
        self.tmp = tempfile.mkdtemp(prefix="cmdt", dir="/tmp")
        self.sock = os.path.join(self.tmp, "d.sock")
        self.qmp_path = os.path.join(self.tmp, "q.sock")
        self.c = C.DisplayClient(self.sock)
        self.report = {"scenario": a.scenario, "size": a.size,
                       "depth": a.depth, "steps": []}
        self.t0 = None
        self.proc = None
        self.disk = os.path.join(self.out, "disk.img")
        self.shots = 0

    # helpers ----------------------------------------------------------------
    def log(self, msg, **kv):
        t = round(time.time() - self.t0, 2) if self.t0 else 0
        entry = {"t": t, "step": msg}
        entry.update(kv)
        self.report["steps"].append(entry)
        print(f"[{t:7.2f}] {msg} {json.dumps(kv) if kv else ''}", flush=True)

    def shot(self, name, source="frame"):
        self.shots += 1
        path = os.path.join(self.out, "frames", f"{self.shots:03d}-{name}.png")
        self.c.snapshot(path, source)
        return os.path.relpath(path, self.out)

    def size(self):
        s = self.c.surface
        return (s["width"], s["height"]) if s else None

    def qmp(self):
        return C.QMP(self.qmp_path)

    def quiet(self, quiet_s=1.0, timeout=10):
        """Pump until no DAMAGE arrived for quiet_s; True if quiet."""
        end = time.time() + timeout
        while time.time() < end:
            n = len(self.c.damage)
            self.c.pump(quiet_s)
            if len(self.c.damage) == n:
                return True
        return False

    def check_frame(self, what):
        same, rows = self.c.frame_matches_shared()
        self.log(f"damage-applied copy == shared buffer ({what})",
                 match=same, differing_rows=rows)
        return same

    # phases -----------------------------------------------------------------
    def start(self):
        self.report["host_loadavg_at_start"] = [round(v, 2) for v in os.getloadavg()]
        subprocess.run(["cp", "-c", self.a.disk, self.disk], check=True)
        argv = build_argv(self.a, self.sock, self.qmp_path, self.disk)
        with open(os.path.join(self.out, "argv.json"), "w") as f:
            json.dump(argv, f, indent=1)
        env = dict(os.environ, CLASSICMAC_SESSION=f"test-{self.a.scenario}")
        self.proc = subprocess.Popen(
            argv, stdin=subprocess.DEVNULL,
            stdout=open(os.path.join(self.out, "qemu.log"), "wb"),
            stderr=subprocess.STDOUT, env=env, start_new_session=True)
        self.t0 = time.time()
        self.c.accept(15)
        self.log("QEMU connected", pid=self.proc.pid)

    def boot(self):
        """Watch the boot: every distinct early frame, yellow detection."""
        c = self.c
        yellow = []
        last_save = 0
        seen_sizes = []
        finder_at = None
        boot_timeout = self.a.boot_timeout
        early_resize_sent = False
        while time.time() - self.t0 < boot_timeout:
            n = len(c.damage)
            c.pump(0.1)
            if not c.surface:
                continue
            sz = self.size()
            if not seen_sizes or seen_sizes[-1] != sz:
                seen_sizes.append(sz)
                self.log("SURFACE", width=sz[0], height=sz[1],
                         stride=c.surface["stride"], size=c.surface["size"],
                         fstat=c.surface["fstat_size"])
            if (self.a.scenario == "vga" and not early_resize_sent and
                    not self.a.no_early_resize):
                # what the app does when its window opens
                w, h = (int(v) for v in self.a.size.split("x"))
                c.resize(w, h)
                early_resize_sent = True
            if len(c.damage) != n:
                w, h = sz
                mean = c.region_stats(0, 0, w, h)
                if is_yellow(mean):
                    yellow.append((round(time.time() - self.t0, 2), mean))
                now = time.time() - self.t0
                if now - last_save >= (0.5 if now < 8 else 3):
                    last_save = now
                    self.shot(f"boot-{now:05.1f}s")
            if finder_at is None:
                if any(e.get("event") == "boot-handoff" for _, e in c.events):
                    finder_at = time.time() - self.t0
                    self.log("boot-handoff event (Finder detected)")
                    if self.a.scenario == "vga":
                        break
            if (self.a.scenario == "ati" and self.size() == tuple(
                    int(v) for v in self.a.size.split("x"))
                    and time.time() - self.t0 > 15):
                # the display helper switched; give the Finder time to draw
                if finder_at is None:
                    finder_at = time.time() - self.t0
                if time.time() - self.t0 - finder_at > 8:
                    break
        self.report["yellow_frames"] = yellow
        self.report["boot_sizes"] = seen_sizes
        self.log("boot watched", yellow_frames=len(yellow),
                 sizes=seen_sizes, finder_at=finder_at)
        if finder_at is None:
            # ClassicMac's HMP fallback for the clock hand-off
            q = self.qmp()
            q.hmp("classicmac-boot-complete")
            q.close()
            self.log("hand-off fallback sent")
        self.quiet(1.5, 20)
        self.report["finder_s"] = finder_at
        self.log("Finder", shot=self.shot("finder"))

    def resize_test(self):
        c = self.c
        w, h = (int(v) for v in self.a.size.split("x"))
        if self.size() != (w, h):
            c.resize(w, h)
            ok = c.wait_for(lambda: self.size() == (w, h), 20)
            self.log(f"RESIZE {w}x{h} after Finder", ok=ok,
                     events=[e for _, e in c.events
                             if e.get("event") == "resize-request"][-1:])
        for tw, th in ((800, 600), (w, h)):
            n_ev = len(c.events)
            t = time.time()
            c.resize(tw, th)
            ok = c.wait_for(lambda: self.size() == (tw, th), 20)
            ev = [e for _, e in c.events[n_ev:] if e.get("event") == "resize-request"]
            self.quiet(1.0, 10)
            self.log(f"RESIZE {tw}x{th}", new_surface=ok,
                     seconds=round(time.time() - t, 2), event=ev[:1],
                     shot=self.shot(f"resize-{tw}x{th}"))
        self.check_frame("after resizes")

    def cursor_test(self):
        c = self.c
        n_cur, n_mouse = len(c.cursors), len(c.mice)
        w, h = self.size()
        sent = []
        for i in range(40):
            x = int(w / 2 + 200 * math.cos(i / 40 * 2 * math.pi))
            y = int(h / 2 + 150 * math.sin(i / 40 * 2 * math.pi))
            c.pointer(x, y)
            sent.append((x, y))
            c.pump(0.03)
        c.pump(0.5)
        mice = c.mice[n_mouse:]
        info = {"cursor_msgs_total": len(c.cursors),
                "mouse_msgs_total": len(c.mice),
                "mouse_msgs_during_sweep": len(mice)}
        if c.cursors:
            _, hx, hy, cw, ch, px = c.cursors[-1]
            values = sorted(set(px))
            info.update(cursor={"hot": [hx, hy], "size": [cw, ch],
                                "distinct_pixels": [f"0x{v:08x}" for v in values[:8]]})
            self.save_cursor(px, cw, ch)
        if mice:
            last = mice[-1]
            info["last_mouse"] = list(last[1:])
            info["last_sent"] = list(sent[-1])
            # MOUSE carries the cursor image's top-left corner or hot spot
            info["mouse_minus_sent"] = [last[1] - sent[-1][0], last[2] - sent[-1][1]]
        self.report["cursor"] = info
        self.log("hardware cursor", **info)

    def save_cursor(self, px, w, h):
        rgb = bytearray()
        for v in px:
            a = (v >> 24) & 0xff
            r, g, b = (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff
            # composite over mid gray to show transparency
            rgb += bytes(((r * a + 128 * (255 - a)) // 255,
                          (g * a + 128 * (255 - a)) // 255,
                          (b * a + 128 * (255 - a)) // 255))
        big = bytearray()
        scale = 8
        for y in range(h):
            row = bytearray()
            for x in range(w):
                row += rgb[(y * w + x) * 3:(y * w + x) * 3 + 3] * scale
            big += row * scale
        C.write_png(os.path.join(self.out, "frames", "cursor-x8.png"),
                    w * scale, h * scale, bytes(big))

    def menu_and_keys(self):
        c = self.c
        w, h = self.size()
        before = c.region_stats(0, 20, 220, 200)
        c.click(20, 10)                          # Apple menu (sticky)
        c.pump(1.0)
        after = c.region_stats(0, 20, 220, 200)
        self.log("click Apple menu", region_before=before, region_after=after,
                 shot=self.shot("apple-menu"))
        c.click(w // 2, h // 2)                  # close it on the desktop
        c.pump(1.0)
        self.shot("menu-closed")
        # type-select the startup disk on the desktop, Command-O opens it
        c.tap("m")
        c.tap("a")
        c.pump(0.5)
        self.shot("type-select")
        c.tap("meta_l", "o")
        self.quiet(1.5, 10)
        self.log("type-select + Command-O", shot=self.shot("cmd-o"))

    def motion(self, name, duration, driver):
        """Run driver(i, t) every ~8 ms; measure what QEMU delivers."""
        c = self.c
        n_dmg, n_mouse = len(c.damage), len(c.mice)
        cpu0 = cpu_seconds(self.proc.pid)
        t0 = time.time()
        i = 0
        while time.time() - t0 < duration:
            driver(i, time.time() - t0)
            i += 1
            c.pump(0.008)
        elapsed = time.time() - t0
        cpu1 = cpu_seconds(self.proc.pid)
        dmg = c.damage[n_dmg:]
        times = [t for t, _, _ in dmg]
        gaps = [(b - a) * 1000 for a, b in zip(times, times[1:])]
        area = [sum(r[2] * r[3] for r in rects) for _, _, rects in dmg]
        res = {"seconds": round(elapsed, 2), "inputs": i,
               "host_loadavg": [round(v, 2) for v in os.getloadavg()],
               "damage_msgs": len(dmg),
               "damage_per_s": round(len(dmg) / elapsed, 1),
               "interval_ms": stats(gaps),
               "pixels_per_damage": stats(area),
               "mouse_msgs": len(c.mice) - n_mouse,
               "mouse_per_s": round((len(c.mice) - n_mouse) / elapsed, 1),
               "qemu_cpu_pct": round((cpu1 - cpu0) / elapsed * 100, 1)
               if cpu0 is not None and cpu1 is not None else None}
        self.report.setdefault("motion", {})[name] = res
        self.log(f"motion: {name}", **res)
        return res

    def idle(self, seconds=6):
        c = self.c
        self.quiet(1.5, 15)
        n = len(c.damage)
        cpu0 = cpu_seconds(self.proc.pid)
        t0 = time.time()
        c.pump(seconds)
        cpu1 = cpu_seconds(self.proc.pid)
        res = {"seconds": seconds, "damage_msgs": len(c.damage) - n,
               "qemu_cpu_pct": round((cpu1 - cpu0) / (time.time() - t0) * 100, 1)}
        self.report["idle"] = res
        self.log("idle Finder", **res)

    def reconnect(self):
        c = self.c
        c.drop()
        c.hello = None
        n_surf, n_dmg, n_ev = len(c.surfaces), len(c.damage), len(c.events)
        n_cur, n_mouse = len(c.cursors), len(c.mice)
        c.accept(5)
        c.wait_for(lambda: c.hello and len(c.surfaces) > n_surf and
                   len(c.damage) > n_dmg, 5)
        c.pump(0.5)
        res = {"hello": bool(c.hello), "surface": len(c.surfaces) - n_surf,
               "full_damage": bool(c.damage[n_dmg:]) and
               c.damage[n_dmg][2] == [(0, 0) + self.size()],
               "events": [e["event"] for _, e in c.events[n_ev:]],
               "cursor": len(c.cursors) - n_cur, "mouse": len(c.mice) - n_mouse}
        self.report["reconnect"] = res
        self.log("app reconnect", **res, shot=self.shot("reconnected"))

    def stop(self):
        if self.proc and self.proc.poll() is None:
            try:
                q = C.QMP(self.qmp_path, timeout=5)
                q.cmd("quit")
                q.close()
                self.proc.wait(15)
            except Exception as exc:     # noqa: BLE001
                print(f"QMP quit failed ({exc}); killing QEMU")
                self.proc.kill()
                self.proc.wait()
        c = self.c
        try:
            log = open(os.path.join(self.out, "qemu.log"), errors="replace").read()
            self.report["qemu_display_log"] = [
                l for l in log.splitlines() if "classicmac-display" in l]
        except OSError:
            pass
        self.report["counts"] = {C.NAMES.get(k, str(k)): v
                                 for k, v in sorted(c.counts.items())}
        self.report["seq_gaps"] = c.seq_gaps
        self.report["events"] = [e for _, e in c.events]
        c.close()
        shutil.rmtree(self.tmp, ignore_errors=True)
        if not self.a.keep_disk and os.path.exists(self.disk):
            os.unlink(self.disk)
        with open(os.path.join(self.out, "report.json"), "w") as f:
            json.dump(self.report, f, indent=1)


def vga_scenario(r):
    r.boot()
    if r.a.boot_only:
        return
    r.resize_test()
    r.cursor_test()
    r.menu_and_keys()
    r.idle()
    r.check_frame("idle")
    w, h = r.size()
    c = r.c

    # window drag: the Finder window opened by Command-O; its title bar is
    # found near the top of the screen. Drag the frontmost window's title in
    # a circle (Mac OS draws the outline into the frame).
    def sweep(i, t):
        x = int(w / 2 + 180 * math.cos(t * 2.0))
        y = int(h / 2 + 140 * math.sin(t * 2.0))
        c.pointer(x, y)
    r.motion("pointer sweep (hardware cursor, MOUSE only)", 4, sweep)
    r.check_frame("after pointer sweep")

    drag_from = (r.a.drag_x, r.a.drag_y) if r.a.drag_x else None
    if drag_from:
        c.pointer(*drag_from)
        c.pump(0.2)
        c.button(0, True)
        c.pump(0.3)

        def drag(i, t):
            c.pointer(int(drag_from[0] + 150 * math.sin(t * 2.5)),
                      int(drag_from[1] + 100 * (1 - math.cos(t * 2.5))))
        r.motion("window drag outline", 5, drag)
        c.pointer(*drag_from)
        c.pump(0.2)
        c.button(0, False)
        r.quiet(1.0, 10)
        r.shot("after-drag")
        r.check_frame("after drag")
    stall(r)
    r.reconnect()
    r.check_frame("after reconnect")


def stall(r, seconds=8.0):
    """The app stops reading while the guest draws: QEMU must keep running,
    coalesce damage, and catch the app up afterwards."""
    c = r.c
    w, h = r.size()
    n_dmg = len(c.damage)
    t0 = time.time()
    i = 0
    while time.time() - t0 < seconds:        # input only, nothing read
        c.pointer(int(w / 2 + 200 * math.cos(i / 10)),
                  int(h / 2 + 150 * math.sin(i / 10)))
        i += 1
        time.sleep(0.008)
    c.pump(0.0)
    burst = len(c.damage) - n_dmg
    r.quiet(1.0, 10)
    res = {"stalled_s": seconds, "inputs": i,
           "damage_msgs_read_after_stall": burst,
           "connected": c.conn is not None and r.proc.poll() is None}
    r.report["stall"] = res
    r.log("app stalled (not reading) while the guest drew", **res)
    r.check_frame("after stall")


def ati_scenario(r):
    r.boot()
    c = r.c
    w, h = r.size()
    r.log("ATI frame", size=[w, h])
    r.cursor_test()
    r.idle()
    r.check_frame("idle")

    def sweep(i, t):
        x = int(w / 2 + 250 * math.cos(t * 3.0))
        y = int(h / 2 + 200 * math.sin(t * 3.0))
        c.pointer(x, y)
    r.motion("pointer sweep (cursor drawn by the card)", 5, sweep)
    r.quiet(1.0, 10)
    r.check_frame("after pointer sweep")
    r.menu_and_keys()
    r.reconnect()
    r.check_frame("after reconnect")
    if r.a.quake:
        quake(r)


def quake(r):
    """Quake III Arena Demo: launch, play demo001 normally, measure."""
    c = r.c
    c.click(974, 55)
    c.click(974, 55)
    r.quiet(1.5, 10)

    def typetext(s):
        for ch in s:
            if ch == " ":
                c.tap("spc")
            elif ch == "_":
                c.tap("shift", "minus")
            elif ch.isupper():
                c.tap("shift", ch.lower())
            else:
                c.tap(ch)
    typetext("Games")
    c.tap("meta_l", "o")
    r.quiet(1.5, 10)
    typetext("Quake 3")
    c.tap("meta_l", "o")
    r.quiet(1.5, 10)
    typetext("MacQuake3")
    c.tap("meta_l", "o")
    ok = c.wait_for(lambda: r.size() == (640, 480), 120)
    r.log("Quake III switched to 640x480", ok=ok)
    if not ok:
        r.shot("quake-failed")
        return
    c.pump(20)
    r.shot("q3-menu")
    c.tap("grave_accent")
    c.pump(1.5)
    typetext("cg_drawfps 1")
    c.tap("ret")
    c.pump(0.5)
    typetext("demo demo001")
    c.tap("ret")
    c.pump(10)                  # past the demo's loading
    r.shot("q3-demo-start")

    def flips():
        q = r.qmp()
        stats = q.cmd("qom-get", path="/machine/peripheral/ati0",
                      property="x-accel-stats")
        q.close()
        return int(dict(kv.split("=", 1) for kv in stats.split()
                        if "=" in kv)["flips"])

    for ms in (16, 8):
        c.refresh_rate(ms)
        c.pump(0.5)
        f0, t0 = flips(), time.time()
        res = r.motion(f"Quake III demo001 (3D, ATI), REFRESH_RATE {ms}", 10,
                       lambda i, t: None)
        r.shot(f"q3-demo-refresh{ms}")
        guest = (flips() - f0) / (time.time() - t0)
        res["guest_flips_per_s"] = round(guest, 1)
        res["delivered_vs_guest"] = round(res["damage_per_s"] / guest, 2) if guest else None
        r.log(f"Quake III guest frame rate (REFRESH_RATE {ms})",
              guest_flips_per_s=res["guest_flips_per_s"],
              delivered_per_s=res["damage_per_s"],
              ratio=res["delivered_vs_guest"])
    c.refresh_rate(16)
    r.shot("q3-demo")
    c.tap("grave_accent")
    c.pump(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--qemu", required=True)
    ap.add_argument("--bios", required=True)
    ap.add_argument("--disk", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--scenario", choices=("vga", "ati"), required=True)
    ap.add_argument("--size", default="1024x768")
    ap.add_argument("--depth", type=int, default=15)
    ap.add_argument("--ndrvloader", default="shared/ndrvloader")
    ap.add_argument("--boot-timeout", type=float, default=90)
    ap.add_argument("--drag-x", type=int)
    ap.add_argument("--drag-y", type=int)
    ap.add_argument("--quake", action="store_true")
    ap.add_argument("--keep-disk", action="store_true")
    ap.add_argument("--no-early-resize", action="store_true",
                    help="do not send RESIZE as soon as the first SURFACE arrives")
    ap.add_argument("--boot-only", action="store_true")
    ap.add_argument("--extra", action="append", default=[],
                    help="one extra QEMU argument (repeat)")
    a = ap.parse_args()
    a.ndrvloader = os.path.abspath(a.ndrvloader)
    r = Run(a)
    try:
        r.start()
        (vga_scenario if a.scenario == "vga" else ati_scenario)(r)
        r.report["result"] = "completed"
    except Exception as exc:     # noqa: BLE001
        r.report["result"] = f"error: {exc!r}"
        print(f"ERROR: {exc!r}")
        try:
            if r.c.surface:
                r.shot("error")
        except Exception:        # noqa: BLE001
            pass
        raise
    finally:
        r.stop()
        print(json.dumps({k: r.report.get(k) for k in
                          ("result", "counts", "seq_gaps", "motion", "idle",
                           "cursor", "reconnect", "yellow_frames")}, indent=1))


if __name__ == "__main__":
    main()
