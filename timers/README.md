# VIA timer 2 and the Mac OS ROM's startup calibration

Three QEMU patches from RetroBoot, applied verbatim by `scripts/build-qemu.sh`
in this order after the faster PowerPC CPU patches (`cpu/`) and before the
ATI card. They are the companion of the branch cache: RetroBoot applies them
in the same place.

| Patch | Property (default) | What |
| --- | --- | --- |
| `retroboot-cuda-via-timers.patch` | `mos6522-cuda.coherent-timers` (on) | VIA timer interrupts come when the guest-visible counter (Cuda's VIA counts in timebase ticks) passes zero, instead of at a random point of the period, and timer 2 fires once per load like the real 6522 |
| `retroboot-pmu-via-timers.patch` | `mos6522-pmu.coherent-timers` (on) | the same for the PMU machine's VIA (`-M mac99,via=pmu`); ClassicMac only starts `via=cuda`, but the next patch needs this one's property list |
| `retroboot-via-t2-hold.patch` | `mos6522-cuda.t2-hold`, `mos6522-pmu.t2-hold` (on); `x-t2-hold-quiet-us` (100), `x-t2-hold-max-us` (4000) | while timer 2's interrupt is enabled, a timer-2 interrupt that falls due while the vCPU is translating code waits until the vCPU has not translated for 100 µs, at most 4 ms; adds `cpu_translation_watch/begin/end/quiet_ns()` to `system/cpu-timers.c`, bracketing `tb_gen_code()` |

`-global mos6522-cuda.t2-hold=off` gives RetroBoot's r17 behaviour, and
adding `-global mos6522-cuda.coherent-timers=off` gives QEMU's (ClassicMac
4.0 before these patches).

## Why

At startup the Mac OS ROM times four loops against VIA timer 2: it loads 1 ms,
enables the interrupt and counts a loop of at most 65,536 iterations. The
interrupt handler jumps to the code after the loop, which stores the count and
moves a table pointer on to the next loop, whose first instructions load timer
2 again. If the interrupt arrives in the dozen instructions between the
pointer's advance and that load, the ROM runs the store twice, overwrites a
low-memory vector and ends in the nanokernel debugger before the gray screen.
On hardware those instructions take a microsecond. Under TCG they run for the
first time right after the first loop and are translated block by block, and
in real time guest time follows the host clock, so a deadline shortly after
the end of that loop can land among them. The branch cache makes the first
loop run out much sooner, which moves that window toward the deadline on
slower or busy hosts.

- **ATI starts and CD starts** run in real time and are exposed.
- **Standard-VGA hard-disk starts** use the instruction clock (`-icount`):
  guest time does not advance while TCG translates, and `t2-hold` switches
  itself off (`cpu_translation_watch()` refuses icount, more than one vCPU or
  no TCG). `coherent-timers` still applies there.

QEMU's own timer-2 model was also wrong for Cuda's tick-based counters: the
interrupt came at a random point of the 1 ms period and then re-fired every
period. `coherent-timers` fixes that; `t2-hold` needs it.

On this branch's host (Apple M5 Max) an unloaded ATI start runs the first
calibration loop out about 0.33 ms after its load (0.55 ms with
`-cpu 7400,fast-branch=off`), so the deadline is far away; slower Apple
Silicon, efficiency cores and a loaded host move it closer. Measurements:
`docs/engine-4.0-via-timers.md`.

## Provenance and license

RetroBoot `emulator/patches/`, at RetroBoot commit
`1860881266449ca2575061e0bd4055c1265cf217` (the same commit as `cpu/`);
GPL-2.0-or-later like the QEMU files they change ("RetroBoot contributors").

| Patch | SHA-256 | Last RetroBoot change |
| --- | --- | --- |
| `retroboot-cuda-via-timers.patch` | `ab7be6ebc2c0b3df550c16b4b5fb1264a1fde19a885c5bd8e158d2930c5d07cd` | `524d86e` |
| `retroboot-pmu-via-timers.patch` | `f177e9fa53f755630a7916127fd514f9250a51bf5b511da11b782debd1be75ad` | `0d3f58c` |
| `retroboot-via-t2-hold.patch` | `8f44ec141d787fb82608cba14c22b6992b21cfdbc031db38aac0da8c679685c5` | `aefec02` |

They apply to ClassicMac's tree with line offsets only. Not ported, because
these three do not need them: RetroBoot's other Cuda patches
(`retroboot-cuda-idle-interrupt.patch`, an empty Cuda interrupt every 50 ms
while idle; `retroboot-cuda-shift-interrupt-timing.patch`, the Cuda sync
handshake race, "type A"), the IDE reset race (`retroboot-macio-ide-srst-complete.patch`,
"type C") and the PMU patches. RetroBoot's reports:
`emulator/reports/pregray-hang-20261011.md` (types A, B, C and
`coherent-timers`) and `emulator/reports/viacal-20261013.md` (`t2-hold`).
