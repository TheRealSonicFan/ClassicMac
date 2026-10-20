# Host-timing races before the Mac OS gray screen

Two QEMU patches from RetroBoot for the pre-gray hangs that RetroBoot calls
type A (the Mac OS ROM's Cuda sync handshake) and type C (OpenBIOS misses the
hard disk after an IDE soft reset). Type B, the VIA timer-2 calibration, is in
`timers/`. `scripts/build-qemu.sh` (section 3e) applies all five in RetroBoot's
lock order, after the faster PowerPC CPU patches (`cpu/`) and before the ATI
card:

1. `startup/retroboot-cuda-shift-interrupt-timing.patch` (A)
2. `timers/retroboot-cuda-via-timers.patch` (B)
3. `startup/retroboot-macio-ide-srst-complete.patch` (C)
4. `timers/retroboot-pmu-via-timers.patch` (B)
5. `timers/retroboot-via-t2-hold.patch` (B)

| Patch | Property (default) | What |
| --- | --- | --- |
| `retroboot-cuda-shift-interrupt-timing.patch` | `cuda.sync-sr-hold` (on), `cuda.sr-int-on-access` (on) | The shift interrupt that answers a sync step (TACK changed with TIP negated) survives one SR read made before the guest has seen it in IFR; a shift interrupt that is due is delivered when the guest next reads the VIA instead of waiting for QEMU's main loop. Trace events `cuda_sync_response`, `cuda_sync_sr_kept`, `cuda_sr_int_due`; migration subsection `cuda/sync` |
| `retroboot-macio-ide-srst-complete.patch` | `macio-ide.srst-complete-on-access` (on) | A software reset the guest has released is carried out on its next access to the controller instead of waiting for QEMU's bottom half (which then finds nothing to do); with DMA in flight the bottom half does it as before |

`-global cuda.sync-sr-hold=off -global cuda.sr-int-on-access=off` and
`-global macio-ide.srst-complete-on-access=off` restore QEMU's behaviour. The
app passes nothing new.

## Why

**Type A.** Before its first Cuda command the Mac OS ROM synchronises with
Cuda, polled, with VIA interrupts off: it asserts TACK and waits for TREQ and
the shift interrupt, then negates TACK, waits for TREQ, *reads SR to discard
the previous byte* and only then waits (15,000 polls) for this step's shift
interrupt. Real Cuda changes TREQ first and shifts the byte afterwards, so the
host always reads SR before the interrupt. QEMU changes TREQ at once and
raises the interrupt 20 µs of virtual time later. In real time that is host
time, so if the vCPU takes longer than 20 µs from the TACK write to the SR
read (first-time translation of this run-once code, a descheduled vCPU
thread, tracing), the read clears the interrupt, the wait runs out and the ROM
halts in a `BRA.S *` loop before the gray screen. The other variant (A′): the
interrupt comes after the 15,000 polls. QEMU's main loop runs the 20 µs timer,
and on macOS it can only do that in whole milliseconds: QEMU has no `ppoll`
there and rounds every main-loop timeout up to 1 ms. Measured on an Apple M5
Max with QEMU's model, the shift interrupt reached the guest a median 1.24 ms
after it was due, while the ROM's polls ran out between 2 and 4 ms after the
TACK write (`docs/engine-4.0-startup-races.md`). On a Mac the first variant is
therefore unlikely and the second one is where the margin is thin.
`sr-int-on-access` removes the second; alone it makes the first more likely
(the interrupt is never late), so it ships only with the hold. The sync branch
runs twice per boot.

**Type C.** QEMU sets BUSY at the SRST edge and carries the reset out in a
main-loop bottom half. OpenBIOS resets the master (and waits for BUSY to
clear), then probes the absent slave: another reset, a status read that
returns 0 (absent, never busy, so it does not wait) and more register reads.
When the bottom half runs milliseconds late, it resets both devices in the
middle of that probe, the hard disk is never identified, `boot` fails silently
and OpenBIOS waits at its prompt with the screen black.

**Which starts.** Type A needs real time: ATI starts and CD starts. Standard
VGA hard-disk starts run on the instruction clock (`-icount`), where the 20 µs
timer is virtual-instruction time run by the vCPU itself. Type C is a race
with the main-loop thread, which runs beside the vCPU in either clock, so it
applies to every start.

## Not ported

| RetroBoot patch | Why not |
| --- | --- |
| `retroboot-cuda-idle-interrupt.patch` | See below. The shift patch needs it only textually (three hunks' context lines) |
| `retroboot-macio-ide-pio-status-drain.patch` | Speeds up OpenBIOS's PIO reads; not a race. The SRST patch needs it only textually (context lines) |
| `retroboot-ide-srst-no-irq.patch` | A reset carried out after the guest released SRST with nIEN clear left INTRQ asserted; Mac OS 9.2.2 hung on it at a wake from sleep (PMU machines). ClassicMac starts `via=cuda`, which does not sleep. The SRST patch only carries out a reset on access when the bottom half had not yet run by the time the guest released SRST, so the reset lands after the release either way |
| `retroboot-ide-atapi-bcl-abort-irq.patch` | A boot-time wait for CD drives (an aborted ATAPI command without an interrupt), not a hang |

**The idle interrupt.** RetroBoot's `cuda.idle-irq-ms` (default 50) pulses
the Cuda interrupt every 50 ms while Cuda is idle and the guest has enabled
the shift interrupt. It mitigates a different problem, RetroBoot's startup
stall: Mac OS 9 sometimes loses the wakeup of its main task, which then only
runs again at the next external interrupt, and RetroBoot's standard-VGA
machine had none for up to 33 s (`emulator/reports/startup-stall-20261011.md`).
RetroBoot's own analysis says it cannot affect types A, B or C: it fires only
while the shift interrupt is enabled, which the ROM has not done at any of the
three hang points. For ClassicMac it is left out:

- On ATI starts the card raises its own 60 Hz vertical-blank interrupt (the
  external interrupt a real Mac has), so such a stall would end within a
  frame. Unloaded ATI starts reach the Finder in a narrow band (18.40–18.54 s
  in 12 boots on `claude/4.0-via-timers`), with no stall-sized outlier.
- It changes what every guest sees, 20 extra interrupts a second while idle,
  including Mac OS 8.x and other systems on `mac99`, which RetroBoot did not
  test (its report names Linux's Cuda driver as one that may disable the
  line), and it costs idle host CPU.
- Where the stall could still matter for ClassicMac is a real-time start on
  standard VGA (CD and installer starts). Not measured here.

So the shift patch was rebased without it.

## Provenance, license and the two rebases

RetroBoot `emulator/patches/`, at RetroBoot commit
`1860881266449ca2575061e0bd4055c1265cf217` (the same commit as `cpu/` and
`timers/`; neither file has changed up to RetroBoot `f8a5f53`);
GPL-2.0-or-later like the QEMU files they change ("RetroBoot contributors").
RetroBoot's report: `emulator/reports/pregray-hang-20261011.md`.

| Patch | RetroBoot SHA-256 (last change) | This directory's SHA-256 |
| --- | --- | --- |
| `retroboot-cuda-shift-interrupt-timing.patch` | `151e07ab3023d4dc44bf3df0a0e2b5bd6d828f8d9fef2843a033d7d0f3f499d2` (`524d86e`) | `fdfb738341d66b30ade88b2a6f3e3ddb6c21dc038ac34eca1a314a9e7002627a` |
| `retroboot-macio-ide-srst-complete.patch` | `5a77ed4c49f84975f0cc92e95877fa955cee82d950c73be58542bc24d320071d` (`c7bff7d`) | `b4813025a33004b07d60d723024ec8c4ecddcd229b4e288010a16f45fea0ca5a` |

Both are rebased, context only: RetroBoot applies the shift patch after the
idle interrupt and the SRST patch after the PIO status drain, and three hunks
of each have those patches' lines as context. They were cherry-picked with
Git's three-way merge onto ClassicMac's tree as it stands before section 3e,
dropping only the other patch's lines. Checked:

- every added and removed line is identical to RetroBoot's, in the same order
  (106 and 47 lines); `diff` against RetroBoot's files shows only hunk headers
  and context;
- the files they touch, after all five patches in this order, differ from
  RetroBoot's order with the idle interrupt and the PIO drain by exactly those
  two patches' added lines.

`lab/` holds a lab-only patch with knobs that stretch each race on demand and
trace its margin; the build never applies it (`lab/README.md`).
