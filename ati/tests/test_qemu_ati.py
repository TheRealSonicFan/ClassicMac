#!/usr/bin/env python3
"""Realization checks for ClassicMac's Power Mac display devices.

Starts qemu-system-ppc (mac99, paused, no display) with the ATI Radeon R100
and with the standard VGA argument set, and reads the card's QOM status over
QMP:

* ati-vga,model=r100 realizes; x-accel-stats reports gl=on and x-gl-renderer
  names an OpenGL 4 renderer (unless --gl-optional);
* CLASSICMAC_ATI_3D=off turns the 3D engine off (gl=off, empty renderer);
* the standard VGA set with ClassicMac's globals realizes.

usage: test_qemu_ati.py [--gl-optional] QEMU_SYSTEM_PPC PC_BIOS_DIR
"""
import argparse
import json
import os
import subprocess
import sys

ATI_DEVICE = "ati-vga,id=ati0,model=r100,vgamem_mb=32,romfile=,guest_hwcursor=on"
STANDARD_VGA = [
    "-vga", "std",
    "-global", "VGA.host-resize=on", "-global", "VGA.vgamem_mb=64",
    "-global", "VGA.packed-lowbpp=on", "-global", "VGA.untracked-vram=on",
    "-global", "VGA.hardware-cursor=on",
    "-global", "VGA.classicmac-boot-handoff=on",
]


class QMP:
    def __init__(self, argv, env=None):
        self.proc = subprocess.Popen(
            argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=env)
        greeting = self._read()
        if "QMP" not in greeting:
            raise RuntimeError(f"no QMP greeting: {greeting}")
        self.cmd("qmp_capabilities")

    def _read(self):
        while True:
            line = self.proc.stdout.readline()
            if not line:
                err = self.proc.stderr.read()
                raise RuntimeError(f"QEMU exited: {err.strip()}")
            msg = json.loads(line)
            if "event" not in msg:
                return msg

    def cmd(self, name, **args):
        self.proc.stdin.write(json.dumps({"execute": name, "arguments": args}) + "\n")
        self.proc.stdin.flush()
        reply = self._read()
        if "error" in reply:
            raise RuntimeError(f"{name}: {reply['error']}")
        return reply.get("return")

    def close(self):
        try:
            self.cmd("quit")
        except Exception:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        return self.proc.stderr.read()


def base(qemu, bios):
    return [qemu, "-M", "mac99,via=cuda", "-cpu", "7400", "-m", "256",
            "-L", bios, "-display", "none", "-monitor", "none",
            "-serial", "none", "-nic", "none", "-S", "-qmp", "stdio"]


def ati_status(qemu, bios, env=None):
    q = QMP(base(qemu, bios) + ["-vga", "none", "-device", ATI_DEVICE], env)
    try:
        stats = q.cmd("qom-get", path="/machine/peripheral/ati0",
                      property="x-accel-stats")
        renderer = q.cmd("qom-get", path="/machine/peripheral/ati0",
                         property="x-gl-renderer")
    finally:
        log = q.close()
    return stats, renderer, log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gl-optional", action="store_true")
    ap.add_argument("qemu")
    ap.add_argument("bios")
    a = ap.parse_args()
    failures = 0

    def check(ok, what):
        nonlocal failures
        print(f"    {'OK' if ok else 'FAIL'}  {what}")
        failures += 0 if ok else 1

    env = {k: v for k, v in os.environ.items()
           if k not in ("CLASSICMAC_ATI_3D", "RETROBOOT_ATI_3D")}
    stats, renderer, log = ati_status(a.qemu, a.bios, env)
    gl_on = " gl=on" in stats
    print(f"    ati-vga x-gl-renderer: {renderer or '(none)'}")
    if gl_on or not a.gl_optional:
        check(gl_on, "ATI 3D engine on host GL (x-accel-stats gl=on)")
        check("GL 4." in renderer, "x-gl-renderer names an OpenGL 4 renderer")
        check("ati: 3D engine on host GL" in log, "QEMU logs the host GL renderer")
    else:
        print("    WARN  no host GL on this builder (--gl-optional)")

    stats, renderer, log = ati_status(a.qemu, a.bios,
                                      dict(env, CLASSICMAC_ATI_3D="off"))
    check(" gl=off" in stats and renderer == "",
          "CLASSICMAC_ATI_3D=off disables the 3D engine")
    check("CLASSICMAC_ATI_3D=off" in log, "QEMU logs the disabled 3D engine")

    q = QMP(base(a.qemu, a.bios) + STANDARD_VGA, env)
    try:
        types = {d["type"] for d in q.cmd("qom-list", path="/machine/unattached")}
        check(any(t.startswith("child<VGA") for t in types),
              "standard VGA with ClassicMac globals realizes")
    finally:
        q.close()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
