#!/usr/bin/env python3
"""Build gate for -display classicmac (no guest disk needed).

Starts a paused mac99 (std-VGA, as ClassicMac launches it) against a test
listener and checks that QEMU accepts -display classicmac,socket=PATH,
connects, says HELLO with the session from CLASSICMAC_SESSION, sends a
SURFACE whose shared XRGB8888 buffer maps, a full-surface DAMAGE and the
clock and pointer-mode events; then that a dropped app connection is
re-established with the same greeting. Exits 0 on success.

usage: test_display_gate.py QEMU_SYSTEM_PPC PC_BIOS_DIR
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmdclient  # noqa: E402


def fail(msg, log=None):
    print(f"FAIL: {msg}")
    if log and os.path.exists(log):
        print(open(log, errors="replace").read()[-3000:])
    sys.exit(1)


def greeting(c, log, what):
    c.pump(0.0)
    ok = c.wait_for(lambda: c.hello and c.surface and c.counts.get(cmdclient.DAMAGE)
                    and len(c.events) >= 2, 10)
    if not ok:
        fail(f"{what}: incomplete greeting (counts {c.counts})", log)
    s = c.surface
    if s["format"] != cmdclient.XRGB8888 or s["stride"] != s["width"] * 4:
        fail(f"{what}: unexpected surface {s}")
    if s["size"] % os.sysconf("SC_PAGE_SIZE") or s["size"] < s["stride"] * s["height"]:
        fail(f"{what}: bad buffer size {s}")
    kinds = [e["event"] for _, e in c.events]
    if kinds[:2] != ["clock", "pointer-mode"]:
        fail(f"{what}: events {kinds}")
    _, seq, rects = c.damage[0]
    if rects != [(0, 0, s["width"], s["height"])]:
        fail(f"{what}: first damage {rects}")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    qemu, bios = sys.argv[1], sys.argv[2]
    tmp = tempfile.mkdtemp(prefix="cmdg", dir="/tmp")
    sock = os.path.join(tmp, "d.sock")
    log = os.path.join(tmp, "qemu.log")
    env = dict(os.environ, CLASSICMAC_SESSION="gate-session")
    argv = [qemu, "-M", "mac99,via=cuda", "-cpu", "7400", "-m", "256",
            "-L", bios, "-vga", "std", "-global", "VGA.host-resize=on",
            "-global", "VGA.hardware-cursor=on", "-S",
            "-display", f"classicmac,socket={sock},idle-refresh=100",
            "-qmp", f"unix:{tmp}/qmp.sock,server=on,wait=off",
            "-monitor", "none", "-serial", "none", "-nic", "none"]
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                         stdout=open(log, "wb"), stderr=subprocess.STDOUT,
                         env=env, start_new_session=True)
    c = None
    try:
        # the app comes up after QEMU: QEMU keeps retrying every 100 ms
        time.sleep(1.0)
        if p.poll() is not None:
            fail("QEMU exited", log)
        c = cmdclient.DisplayClient(sock)
        t = time.time()
        try:
            c.accept(5)
        except OSError:
            fail("QEMU did not connect", log)
        if time.time() - t > 1.0:
            fail(f"connect took {time.time() - t:.2f} s")
        greeting(c, log, "first connection")
        if c.hello != {"version": 1, "pid": p.pid, "session": "gate-session",
                       "len": 48}:
            fail(f"HELLO {c.hello}")
        first = dict(c.surface)

        # the app goes away and comes back: QEMU must greet it again
        c.drop()
        c.hello = c.surface = None
        c.counts.clear()
        c.events.clear()
        c.damage.clear()
        try:
            c.accept(5)
        except OSError:
            fail("QEMU did not reconnect", log)
        greeting(c, log, "reconnection")
        if (c.surface["width"], c.surface["height"]) != (first["width"], first["height"]):
            fail(f"reconnect surface {c.surface} != {first}")

        q = cmdclient.QMP(os.path.join(tmp, "qmp.sock"))
        q.cmd("quit")
        q.close()
        p.wait(10)
        text = open(log, errors="replace").read()
        if "connected to the app" not in text:
            fail("no connection log line", log)
        print(f"    OK  -display classicmac: HELLO, SURFACE {first['width']}x"
              f"{first['height']} (shared {first['size']} bytes), DAMAGE, "
              f"events, reconnect")
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        if c:
            c.close()
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
