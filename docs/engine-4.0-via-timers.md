# ClassicMac 4.0 engine: VIA timer 2 for the faster CPU

Branch `claude/4.0-via-timers`, cut from `claude/4.0` `69f703a`. Engine
only: no `app/` change. Evidence is under `output/via-timers/` and
`output/q3/` in the worktree (ignored by Git).

## Summary

- Commit `74275dd` ("engine: faster PowerPC CPU emulation") ported RetroBoot's
  MMU-context, FPU and branch-cache patches but not RetroBoot's VIA timer-2
  hold, which RetroBoot ships with the branch cache because faster branches
  push the Mac OS ROM's timer-2 calibration into a race (pre-gray hang,
  "type B"). ATI starts and CD starts run in real time and were exposed.
- This branch adds RetroBoot's three VIA timer patches, verbatim, in
  `timers/` (provenance and hashes in `timers/README.md`), applied by
  `scripts/build-qemu.sh` right after the CPU patches: `coherent-timers`
  (timer interrupts when the guest-visible counter passes zero, timer 2
  one-shot) on `mos6522-cuda` and `mos6522-pmu`, and `t2-hold` (a due
  timer-2 interrupt waits while the vCPU is translating, at most 4 ms; off
  by itself under icount, SMP or without TCG).
- The build resets `hw/misc/mos6522.c`, `include/hw/misc/mos6522.h` and
  `hw/misc/macio/pmu.c` on reruns, and gates the four properties on both VIAs
  and that `coherent-timers` and `t2-hold` default on.
- `ati/tests/boot_soak.py`: repeated cold boots with Finder detection, a
  responsiveness check (Apple menu opens and closes), hang register capture,
  optional host stress and a trace of the ROM's timer-2 loads.
- The `-cpu 7400,fast-branch=off` stopgap is no longer needed.

## Engine changes

| Area | Change |
| --- | --- |
| `timers/` | `retroboot-cuda-via-timers.patch`, `retroboot-pmu-via-timers.patch`, `retroboot-via-t2-hold.patch` (verbatim, RetroBoot `1860881`), `README.md` with provenance |
| `scripts/build-qemu.sh` | section 3e applies them after the CPU patches (ATI moves to 3f); `PATCHED_FILES` gains `hw/misc/mos6522.c`, `include/hw/misc/mos6522.h`, `hw/misc/macio/pmu.c` (the other touched files were already listed); gate: `coherent-timers`, `t2-hold`, `x-t2-hold-quiet-us`, `x-t2-hold-max-us` on `mos6522-cuda` and `mos6522-pmu`, the first two `default: on` |
| `cpu/README.md` | points at `timers/` instead of "not included" |
| `ati/tests/boot_soak.py` | new: repeated cold boots (`--runs`, `--arm`, `--jobs`, `--stress`, `--trace-t2`), relative socket paths (macOS's 104-byte `AF_UNIX` limit) |
| `ati/tests/deluxe_q3_timedemo.py` | `-- QEMU ARGS` passthrough for same-binary A/B |

No QEMU argument changes: the app passes nothing new, and the defaults are
on. Not ported (not needed by these three, and not caused by `74275dd`):
RetroBoot's Cuda idle interrupt, Cuda sync handshake ("type A") and IDE soft
reset ("type C") fixes; see Risks.

## Verification

Host: Apple M5 Max (6 Super + 12 Performance cores), macOS 27.2, logged-in
session. Guests headless (`-display vnc=unix:…`, HMP `screendump`, QMP
input) with the argument sets of `ati/tests/guest_run.py`. Another session
(`worktrees/4.0-display`) ran its own ATI QEMUs on this host during parts of
these runs; host load average at each boot's start is in its `result.json`.

### Build

| Check | Result |
| --- | --- |
| Fresh `vendor/` (clone of v11.0.2), `scripts/build-qemu.sh` | every gate passes, including the new `VIA timer-2 coherent timers and calibration hold (ppc)`, the ATI realization (`CGL; GL 4.1 Metal - 91.7; Apple M5 Max`, `gl=on`) and the CPU properties; no compiler warnings from the patched files |
| Rerun on the built tree | resets and re-applies every patch, incremental build, all gates pass |
| `git apply` of the three patches | clean, line offsets only (−144, −512, −661) |

### Boots to a responsive Finder (`boot_soak.py`)

Test disks from the public catalog, archive SHA-256 verified:
`mac-os-9.2.1-gxmetal-2.3.0-32gb-v2` (`bc0290ed…959d`) and `os922-deluxe-v6`
(`9d0d0c51…49dd`). Each boot uses an APFS clone of the template disk. A boot
counts when the Finder's menu bar is up and the Apple menu opens and closes
on clicks.

| Series | Boots | Responsive Finder | Hangs | Finder min / median / max | Load avg at start |
| --- | --- | --- | --- | --- | --- |
| Deluxe v6, ATI 1024x768, real time | 12 | **12** | 0 | 18.40 / 18.44 / 18.54 s | 1.7–2.2 |
| Mac OS 9.2.1, standard VGA, icount + Finder hand-off | 12 | **12** | 0 | 11.96 / 12.53 / 17.12 s | 2.3–17.2 (other sessions) |
| Deluxe v6, ATI, host loaded: 36 busy-loop processes on 18 cores | 12 | **12** | 0 | 39.58 / 40.92 / 44.42 s | 6.6–105 |
| Deluxe v6, ATI, `t2-hold=off` with each `x-fast-branch-mask` / `fast-branch=off` (timing probe) | 14 | 14 | 0 | 18.42–20.97 s | 2.8–10.9 |

`scripts/benchmark-os9-boot.py` (Mac OS 9.2.1, icount + automatic Finder
hand-off, `--minimal-devices`, 4 interleaved pairs): Finder at 8.64, 8.38,
9.18, 8.91 s with `coherent-timers` on and 9.18, 8.64, 8.66, 8.91 s with
`-global mos6522-cuda.coherent-timers=off` (medians 8.77 and 8.78 s);
welcome screen 4.87 s in both; every hand-off ended in real time.

The loaded VGA series was stopped at its start, at the user's request to
free the host. VGA starts run on the instruction clock, where `t2-hold`
switches itself off and translation takes no guest time.

Where this host sits (`--trace-t2`, host time from the first calibration
loop's timed load to the next load; under 1 ms means the loop ran out
before its interrupt):

| Configuration | First calibration loop |
| --- | --- |
| ATI, default (branch cache on) | 0.30–0.34 ms (15 boots) |
| ATI, `x-fast-branch-mask` 5 / 3 / 4 / 6 / 2 | 0.30 / 0.41 / 0.48 / 0.49 / 0.59 ms |
| ATI, `-cpu 7400,fast-branch=off` | 0.55–0.56 ms |
| ATI, host loaded (36 busy loops) | 0.42–0.51 ms, one boot 1.12 ms (the deadline fell at the end of the loop; it booted) |
| VGA, icount (host time) | 0.23–0.27 ms |

So an unloaded M5 Max is far from the deadline in every configuration,
including the `fast-branch=off` stopgap. RetroBoot's slow host (N5105) ran
the same loop out at about 0.9 ms. Slower Macs and busy hosts move toward it.

### The race, reproduced and closed

To put this host where a slow host is, the translation of first-time code
was stretched with TCG logging limited to the 68k emulator's code
(`-d in_asm,op_opt,out_asm -dfilter 0x68000000+0x200000`). The loop itself
is hot and not slowed, but the first-time code between its end and the next
timer-2 load now takes over 1 ms (the first timed run ends 1.5 ms after its
load instead of 0.3 ms), so the deadline lands among those blocks, as on a
slow host. One QEMU at a time, arms interleaved:

| Arm | Boots | Responsive Finder | Hangs |
| --- | --- | --- | --- |
| **this branch** (`coherent-timers` and `t2-hold` on) | 6 | **6** | 0 |
| `t2-hold=off` (RetroBoot r17) | 6 | 1 | **5**, all type B |
| `t2-hold=off`, `coherent-timers=off` (= `74275dd`) | 5 | 3 | **2**, both type B |

Every hang is RetroBoot's type B: the nanokernel debugger in real mode
(NIP `00f268d4`, MSR `3010`), SRR0 `6806d444`, DAR `effffe9a` (r17 arm; as
in RetroBoot's viacal report) or `efffffde` / `4a400000` (`74275dd` arm,
where the interrupt phase is random). With the hold, the first timed run
ended 1.48–1.57 ms after its load: the interrupt waited while TCG translated,
and the next load cancelled it.

### CPU correctness (RetroBoot's bare-metal harness)

`fpconf.elf` sha256 `4d58e2cc41abaa8f054861e2432673859eba8c12c629b71ad518a894762288b3`
(the 4.0 engine report's, run read-only in place); RetroBoot
`emulator/tests/ppcfpu/fpconf.py` at `1860881`.

| Check | Result |
| --- | --- |
| `conf`, seeds 0x5eed and 501 × 20,000 (101.4 M vectors per arm and seed) | `on`, `fast-branch=off`, `x-fast-branch-mask=6` and the `74275dd` binary: 5072/5072 (cfg, op) hashes equal to the softfloat reference (`fast-fpu=off`) |
| `smc` | `on`, `fast-branch=off`, masks 6 and 5: 92 calls each, equal to the `74275dd` binary, the same 2 stale results without `icbi` |

### Quake III `timedemo 1; demo demo001` (ATI, 1024x768)

The other session's ATI QEMUs shared the CPU and GPU during these runs, so
every arm sits about 10 % below the 4.0 engine report's 152.6–155.8 fps.
The comparisons are interleaved, so they share the conditions:

| A/B | Arm | fps |
| --- | --- | --- |
| Binaries | this branch | 118.9, 138.4, 139.7 |
| | `74275dd` binary (the report's `bin-cpu`, read-only) | 142.0, 144.9, 129.2 |
| One binary, properties | default (hold on) | 135.5, 112.7, 135.8 |
| | `t2-hold=off` | 127.5, 126.3, 145.7 |
| | `t2-hold=off`, `coherent-timers=off` | 133.6, 129.3, (console not opened) |
| First runs (before the A/Bs) | this branch | 141.6, 137.3, (end of demo not detected) |

All arms overlap (112.7–145.7 fps); no cost of the hold is visible. The hold
adds two clock reads per TCG translation once a VIA has switched the
bookkeeping on (ATI and CD starts), and none to translated code. RetroBoot
measured Quake III 88.7 fps with the hold against 84.7 without it.
Boot to the Finder is unchanged (18.4–19.5 s in these runs; 18.5 s in the
4.0 engine report).

## Not run

- Loaded standard-VGA series (stopped, see above); CD/installer starts
  (real time, standard VGA: the hold applies there, as on ATI); `-cpu g3`;
  `via=pmu` (ClassicMac never starts it; the PMU patch only carries the
  property the hold patch extends).
- A quiet-host Quake rerun for the absolute ~154 fps figure.
- Slower Apple Silicon (M1–M3) or a Mac under low-power mode, where the
  unpatched engine would be closest to the race. Not reproduced without the
  logging amplification on this host.
- Mac OS 8.x guests on `mac99`.

## Risks

- **The ROM's race keeps its hardware size.** As RetroBoot's report says:
  the hold covers first-time code after the first loop; loops 2–4 end in code
  that already ran. Interrupts are only delayed (at most 4 ms), and only
  while timer 2's interrupt is enabled, which in Mac OS 9 is only the ROM's
  calibration.
- **Other real-time startup races are not covered** and were already open on
  ATI starts before `74275dd`: RetroBoot's Cuda sync handshake ("type A",
  seen on idle hosts in RetroBoot's lab) and the IDE soft-reset race ("type
  C", loaded hosts). Of the 74 real-time ATI starts here (smoke 1, timing
  probe 14, unloaded 12, loaded 12, Quake 18, amplified 17), the only hangs
  were the 7 induced type-B hangs in the arms without the hold. RetroBoot
  fixes them with
  `retroboot-cuda-shift-interrupt-timing.patch` (which needs
  `retroboot-cuda-idle-interrupt.patch` textually) and
  `retroboot-macio-ide-srst-complete.patch`.
- `coherent-timers` also changes standard-VGA icount starts (timer 2
  becomes one-shot and fires when its counter passes zero, so the ROM's
  calibration values change). 12/12 VGA boots reached a responsive Finder
  through the hand-off and the boot benchmark is unchanged (above); no
  longer soak or application timing check was run.

## Next safe action

Integration owner: merge `claude/4.0-via-timers` into `claude/4.0`, run the
consolidated checks, and drop the `fast-branch=off` stopgap note from the 4.0
risk list. Optionally evaluate RetroBoot's type A/C patches for ATI and CD
starts.
