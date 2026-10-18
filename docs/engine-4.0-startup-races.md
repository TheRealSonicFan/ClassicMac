# ClassicMac 4.0 engine: the Cuda sync and IDE soft-reset races

Branch `claude/charming-blackburn-59de84`, cut from `claude/4.0-via-timers`
`48d3be1`. Engine only: no `app/` change. Evidence is under `output/startup/`
in the worktree (ignored by Git).

## Summary

- RetroBoot found three host-timing races that hang Mac OS before the gray
  screen (`emulator/reports/pregray-hang-20261011.md`). `claude/4.0-via-timers`
  closed type B (VIA timer 2). This branch ports RetroBoot's fixes for the
  other two, in `startup/` (provenance in `startup/README.md`):
  - **type A**, the Mac OS ROM's Cuda sync handshake:
    `retroboot-cuda-shift-interrupt-timing.patch`, `cuda.sync-sr-hold` and
    `cuda.sr-int-on-access`;
  - **type C**, OpenBIOS missing the disk after an IDE soft reset:
    `retroboot-macio-ide-srst-complete.patch`,
    `macio-ide.srst-complete-on-access`.
- `scripts/build-qemu.sh` applies them with the three timer patches in
  RetroBoot's lock order, resets the two newly touched files, and gates the
  three properties and their `on` defaults.
- **RetroBoot's Cuda idle interrupt is not ported.** It mitigates a different
  problem (a lost Mac OS wakeup that RetroBoot's VGA machine had no external
  interrupt to end), cannot affect A, B or C by RetroBoot's own analysis, and
  would add 20 interrupts a second to every guest. ATI starts already have a
  60 Hz vertical-blank interrupt. Both patches are rebased context only: every
  added and removed line is RetroBoot's.
- **What this host shows.** QEMU has no `ppoll` on macOS and runs main-loop
  timers in whole milliseconds, so with QEMU's own Cuda model the ROM's
  "20 µs" shift interrupt reached the guest a median 1.24 ms late. That makes
  RetroBoot's common type A (interrupt before the SR read) unlikely on a Mac.
  It leaves the late variant (A′) with a thin margin: the ROM gives up 2–4 ms
  after the TACK write. `sr-int-on-access` delivers the interrupt on the
  guest's next VIA read (median 2 µs after it is due), and `sync-sr-hold`
  closes the early variant that this exposes. IDE soft resets: QEMU's bottom
  half carried them out 6–14 µs after the SRST edge, after OpenBIOS had
  already released SRST; the fix carries them out on that next access.
- Each race was reproduced on demand with a lab-only patch (`startup/lab/`)
  and closed: type A 6/6 hangs without the hold, 0/6 with the fix; A′ hangs at
  a 4 ms delay; type C 6/6 (ATI) and 4/4 (VGA) hangs without the fix, 0 with
  it.

## Engine changes

| Area | Change |
| --- | --- |
| `startup/` | `retroboot-cuda-shift-interrupt-timing.patch`, `retroboot-macio-ide-srst-complete.patch` (RetroBoot `1860881`, rebased context only), `README.md` with provenance, the two rebases and the idle-interrupt decision |
| `startup/lab/` | `classicmac-lab-startup-races.patch` (never applied by the build): `cuda.x-lab-sync-sr-delay-ns`, `macio-ide.x-lab-srst-delay-us`, trace events `cuda_lab_sync_sr_read`, `cuda_lab_sr_int`, `ide_lab_srst_done`; `README.md` |
| `scripts/build-qemu.sh` | section 3e applies `startup/` and `timers/` interleaved in RetroBoot's lock order (shift interrupt, `cuda-via-timers`, SRST, `pmu-via-timers`, `t2-hold`); `PATCHED_FILES` gains `hw/ide/core.c`, `include/hw/ide/ide-bus.h`; gates `cuda` `sync-sr-hold`, `sr-int-on-access` and `macio-ide` `srst-complete-on-access`, each `default: on` |
| `ati/tests/boot_soak.py` | hangs classified A, B or C; `--trace EVENT` counts trace events per boot and keeps the lab events' values |
| `ati/tests/deluxe_q3_timedemo.py` | relative socket paths (macOS's 104-byte `AF_UNIX` limit; long worktree paths) |
| `timers/README.md`, `docs/engine-4.0-ati.md` | point at `startup/` |

No QEMU argument changes: the app passes nothing new, and the defaults are on.

## Verification

Host: Apple M5 Max (6 Super + 12 Performance cores), macOS 27.2, logged-in
session, nothing else running QEMU. Guests headless (`-display vnc=unix:…`,
HMP `screendump`, QMP input) with `ati/tests/guest_run.py`'s argument sets, one
QEMU at a time. Disks: APFS clones of `os922-deluxe-v6` and
`mac-os-9.2.1-gxmetal-2.3.0-32gb-v2` (the via-timers report's templates, used
read-only). Load average at each boot's start is in its `results.jsonl`
(2.5–6 throughout). The host was put to sleep at 00:50 local time on
October 18, near the end; everything below ran before that, except the
type C sweep (noted there). Runs started after it (two more wait-budget
points, the Quake III A/B, an IDE probe timeline) were stopped and are not
used.

### Build

| Check | Result |
| --- | --- |
| `scripts/build-qemu.sh` on a fresh `vendor/` (local clone of v11.0.2) | every gate passes, including the new `Cuda sync handshake hold and shift interrupt on access (ppc)` and `MacIO IDE soft reset completed on access (ppc)`; no compiler warnings from the patched files |
| Rerun after the lab patch was applied and built | resets every file (lab patch gone), all gates pass, binary bit-identical to the first build (`b613fde4…`) |
| Patch order | all five apply cleanly in RetroBoot's order on ClassicMac's tree |

### Boots to a responsive Finder (`boot_soak.py`, the product binary)

A boot counts when the Finder's menu bar is up and the Apple menu opens and
closes on clicks. Interleaved 2:1 with QEMU's behaviour (`old`:
`cuda.sync-sr-hold=off`, `cuda.sr-int-on-access=off`,
`macio-ide.srst-complete-on-access=off`, the same binary).

| Series | Arm | Boots | Responsive Finder | Hangs | Finder min / median / max | Load avg at start |
| --- | --- | --- | --- | --- | --- | --- |
| Deluxe v6, ATI 1024x768, real time | **fix** | 12 | **12** | 0 | 17.93 / 17.95 / 18.45 s | 3.4–4.1 |
| | old | 6 | 6 | 0 | 18.41 / 18.94 / 18.97 s | 3.2–3.9 |
| Mac OS 9.2.1, standard VGA, icount + Finder hand-off | **fix** | 12 | **12** | 0 | 11.98 / 11.99 / 12.57 s | 3.0–4.9 |
| | old | 6 | 6 | 0 | 11.97 / 12.26 / **36.71** s | 2.9–5.8 |

ATI starts reach the Finder about 1 s sooner with the fix (the harness polls
every 0.5 s): `sr-int-on-access` delivers the ~540 shift interrupts per boot
that the ROM polls for within microseconds instead of the main loop's
~1.24 ms (540 × 1.24 ms ≈ 0.67 s). Across all ATI boots of this report
without the sync-delay knob: Finder median 17.95 s with `sr-int-on-access`
(30 boots, 17.91–18.98 s) and 18.94 s without it (10 boots, 18.41–18.97 s;
the via-timers report's 12 unloaded boots: 18.40–18.54 s). Under icount the
vCPU runs those timers itself, so VGA starts do not change.

One `old` VGA boot reached the Finder after 36.7 s instead of 12 s (first
content at 5.1 s as usual, no hang; no trace or frames were kept for it). No
other VGA boot of this report took longer than 12.57 s (29 with the Cuda fix,
7 more without it); the cause is unknown. RetroBoot's startup stall (see
Risks), which neither arm addresses, is one candidate.

`scripts/benchmark-os9-boot.py` (Mac OS 9.2.1, `-icount shift=4,sleep=off`
as the app passes it, `--handoff-at-finder --minimal-devices`, 4 interleaved
pairs against the `claude/4.0-via-timers` binary `d8d4e2af…`):

| Binary | Finder (s) | Median | Welcome (median) |
| --- | --- | --- | --- |
| this branch | 9.20, 8.90, 8.65, 8.64 | 8.77 | 4.88 |
| `claude/4.0-via-timers` | 9.18, 8.88, 9.18, 8.91 | 9.04 | 4.87 |

Unchanged within the benchmark's ~0.26 s polling steps (the via-timers report
had 8.77 and 8.78 s); every hand-off ended in real time.

### Quake III: not run

The A/B (`ati/tests/deluxe_q3_timedemo.py`, this binary against the
`claude/4.0-via-timers` binary, 3 interleaved pairs) did not run. Its first
attempt failed on macOS's 104-byte limit for Unix socket paths (this
worktree's path is longer than via-timers'; `deluxe_q3_timedemo.py` now uses
relative socket paths like `boot_soak.py`). The host was put to sleep at
00:50 local time, before the second attempt, and was only awake for short
maintenance wakes without graphics after that, so the attempt was stopped. To
run it on an awake host, one QEMU at a time:

```sh
for i in 1 2 3; do for arm in fix viatimers; do
  python3 ati/tests/deluxe_q3_timedemo.py --qemu output/startup/bin-$arm/qemu-system-ppc \
    --bios vendor/qemu/pc-bios --disk ../../../worktrees/4.0-via-timers/scratch/dlx/disk.img \
    --out output/startup/q3-$arm-$i
done; done
```

The fixes touch only Cuda's shift interrupt, which Quake does not use while
the demo runs (the ADB mouse and keyboard are idle), and the IDE reset, which
runs at startup; the via-timers report found its own startup change
invisible in Quake's frame rate.

### The margins on this host

From the lab build (`startup/lab/`) without its knobs, fix defaults unless
noted. QEMU's real-time clock on macOS moves in 1 µs steps.

| Quantity | ATI, real time | Standard VGA, icount |
| --- | --- | --- |
| Sync step's TACK write to the ROM's SR read | 0–3 µs (deadline 20 µs) | 0.4 µs of virtual time |
| Cuda shift interrupt after it is due, QEMU's model (main loop) | median 1.24 ms, p99 1.25–1.26 ms, max 1.8 ms (4 boots, 4,848 interrupts) | 0 (the vCPU runs icount timers at their deadline); real time after the Finder hand-off |
| the same with `sr-int-on-access` (polled reads) | median 2 µs, p99 6–11 µs (2,183) | 0 |
| ROM's wait for a sync step's interrupt (lab delay) | 1 and 2 ms boot; 4 and 8 ms hang (type A) | — |
| IDE soft reset after its edge, QEMU's bottom half | 6–14 µs, after OpenBIOS released SRST in 28 of 28 | 6–11 µs, after the release in 24 of 28 |
| the same with `srst-complete-on-access` | 3–16 µs; 26 of 28 on the guest's first access after the release, 2 by the bottom half before it | 3–8 µs; 24 of 28 on access |

So on this Mac, with QEMU's model:

- **A** (interrupt before the SR read) needs the SR read more than 20 µs
  after the TACK write (it came after 0–3 µs) at a moment when the main loop
  runs the timer on time (2 of 8 sync steps; the other 6 came 1.24–1.25 ms
  late): far away.
- **A′** (interrupt after the ROM's polls) has a margin of about 2× unloaded
  (1.25 ms against 2–4 ms). RetroBoot's loaded Linux builder saw the timer up
  to 14.6 ms late. A loaded or throttled Mac moves toward it.
- **C** needs the bottom half late by somewhere between 14 µs and 1.26 ms
  (below); it ran 6–14 µs after the edge here. A bottom half wakes the main
  loop at once, unlike a timer, but anything that keeps the main loop from
  running for about a millisecond during OpenBIOS's probe hangs a start
  without the fix.

### The races, reproduced and closed

The lab build's knobs put this host where RetroBoot's slower or busier hosts
are; `ati/tests/boot_soak.py` classifies the hangs. Arms interleaved, one QEMU
at a time.

**Type A**: the sync step's shift interrupt 1 µs after the TACK write (ATI;
0.2 µs under icount), standing for a vCPU that needs 20 µs longer to reach its
SR read:

| Start | Arm | Boots | Responsive Finder | Hangs |
| --- | --- | --- | --- | --- |
| ATI | **fix** | 6 | **6** | 0 (the hold kept the interrupt in 3 boots, `cuda_sync_sr_kept`) |
| ATI | `sync-sr-hold=off` | 6 | 0 | **6**, all type A |
| ATI | both off (QEMU's model) | 6 | 6 | 0: the main loop delivered the interrupt ~1.2 ms late, after the read |
| VGA, icount | **fix** | 3 | **3** | 0 (kept in 3 of 3) |
| VGA, icount | both off | 3 | 0 | **3**, all type A (icount runs the timer at its deadline) |

Every type A hang (these 9 and the 2 below) is RetroBoot's: the 68k
emulator's halt loop at NIP `0x680B07F0` or `0x68067EC0`–`EC8` (RetroBoot's
two addresses; LR `0x680B07F0`), the ROM's sync routine as the 68k PC in r24
(`0xFFC09694`/`96`; RetroBoot `0xFFC09694`), `0x2600` in r21 (RetroBoot:
A7 = `0x2600`), and `BRA.S *` (`0x60FE`) in r27 in the samples taken at
`0x68067EC0`. In the type A arms the SR read came 1–3 µs (0.4 µs under
icount) after the TACK write with the step's interrupt already raised.

**Type A′**: the sync step's interrupt delayed (fix arm, so it is delivered
on the next read once due): 1 ms and 2 ms boot; 4 ms and 8 ms hang with the
same signature, so the ROM gives up between 2 and 4 ms after the TACK write.
QEMU's model delivered it up to 1.25 ms late (1.8 ms for other shift
interrupts). With `sr-int-on-access` the sync steps' interrupts came 1–44 µs
after they were due (8 steps in 4 boots).

**Type C**: the SRST bottom half 3 ms late (RetroBoot's S1 used 3 ms):

| Start | Arm | Boots | Responsive Finder | Hangs |
| --- | --- | --- | --- | --- |
| ATI | **fix** | 6 | **6** | 0 (42 resets, all on access 2–21 µs after the edge) |
| ATI | `srst-complete-on-access=off` | 6 | 0 | **6**, all type C |
| VGA, icount | **fix** | 4 | **4** | 0 |
| VGA, icount | `srst-complete-on-access=off` | 4 | 0 | **4**, all type C |

Every type C hang: OpenBIOS (NIP `0xFFF1B80C`–`818`), screen black, only 4 soft
resets instead of 7, serial output identical to a good boot's up to that
point. So type C applies to standard-VGA icount starts too: it is a race with
the main-loop thread, not with guest time.

**Where type C's window opens.** The knob delays the bottom half with a QEMU
timer, and on macOS that fires at the main loop's next millisecond at the
earliest: settings of 30 µs, 100 µs, 300 µs and 1 ms carried the resets out
1.26–1.53 ms after the edge, and every one of those 8 boots stopped at
OpenBIOS's prompt. So the window opens between this host's 6–14 µs and
1.26 ms; RetroBoot traced a normal probe's IDENTIFY 0.3 ms after the second
reset, which would put it near 0.3 ms. Only the 30 µs boots had their
resets before the host went to sleep; the other 6 ran in its maintenance
wakes, and 4 of the 8 were suspended between their resets and the hang
check, which does not change where OpenBIOS stopped. A finer delay needs a
different lab knob (a helper thread that schedules the bottom half late),
not tried.

## Not run

- **Quake III A/B** (see above): the host went to sleep first.
- An IDE trace of OpenBIOS's probe (SRST edges against the IDENTIFY that a
  late reset clobbers), which would place type C's window more precisely.
- Host load (busy loops) and slower Apple Silicon: the user asked that hosts
  not be stressed. The A′ margin under load is inferred from the unloaded
  numbers above and RetroBoot's loaded-host measurements.
- The app's own display paths (`-display cocoa`, `-display classicmac`):
  every boot here was headless (VNC), so a busier main loop with a window was
  not measured.
- CD and installer starts (real time, standard VGA; both fixes apply there),
  `-cpu g3`, Mac OS 8.x guests on `mac99`, `g3beige`.
- Restart and Shut Down chains (the sync branch runs twice per boot,
  RetroBoot's restart chains with these patches passed).
- Migration (`cuda/sync` is a new subsection; ClassicMac does not migrate).

## Risks

- **Cuda timing changes on macOS.** With `sr-int-on-access` a due shift
  interrupt reaches a polling guest within microseconds instead of the main
  loop's ~1.2 ms. That is the timing QEMU's model intends (20 µs) and what
  RetroBoot ships, but on macOS it is a visible change for every polled Cuda
  transfer (about 540 per ATI boot). Interrupt-driven transfers still wait for
  the main loop.
- **The startup stall RetroBoot's idle interrupt mitigates** was not measured
  on ClassicMac's real-time standard-VGA starts (CD and installer), the one
  configuration with neither a vertical-blank interrupt nor icount.
- `retroboot-ide-srst-no-irq.patch` (a reset carried out after the release
  with nIEN clear leaves INTRQ asserted) is not ported: its hang needs a PMU
  machine's wake from sleep. With QEMU's own bottom half the resets on this
  host already landed after the release (28 of 28), so the fix does not change
  when INTRQ is raised.

## Next safe action

On an awake, otherwise idle host: run the Quake III A/B above. Then the
integration owner merges `claude/4.0-via-timers`, then this branch, into
`claude/4.0` and runs the consolidated checks. Optionally measure a CD start
for RetroBoot's startup stall before deciding on the idle interrupt for that
case.
