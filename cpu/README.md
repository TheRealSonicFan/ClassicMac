# Faster PowerPC CPU emulation

Five QEMU patches from RetroBoot, applied verbatim by `scripts/build-qemu.sh`
in this order (they build on each other) after ClassicMac's own PowerPC/TCG
patches and before the ATI card. Each is a property of the PowerPC CPU that
defaults on; `-cpu 7400,<property>=off` restores QEMU's behaviour.

| Patch | Property | What |
| --- | --- | --- |
| `retroboot-ppc-mmu-contexts.patch` | `mmu-contexts` | 32-bit hash MMU: up to 5 address spaces (SRs, BATs, SDR1) keep their own translated-mode MMU indexes, so Mac OS 9's per-interrupt address-space switches stop flushing the whole softmmu TLB |
| `retroboot-ppc-fpu-fast.patch` | `fast-fpu`, `x-fast-fpu-mask` | scalar FP instructions in one helper using host IEEE double arithmetic when the outcome is provably softfloat's (else the original sequence); lfs/stfs and fsel inline |
| `retroboot-ppc-fpu-vmx.patch` | (`fast-fpu` part 0x8) | AltiVec FP lanes on the host under the same conditions |
| `retroboot-ppc-fpu-r17.patch` | (`x-fast-fpu-mask` 0x10-0x40) | FP helpers called without globals sync where FP exceptions cannot be raised, leaner paths, inline AltiVec element loads/stores; the x86 SSE lanes are compiled out on arm64 (`FV_SIMD 0`) |
| `retroboot-ppc-branch-cache.patch` | `fast-branch`, `x-fast-branch-mask` | cached destinations for cross-page direct branches, a return-address stack for bl/blr and per-site indirect-branch slots, validated by a global generation (single vCPU only) |

All of them require `-ffp-contract=off`, which `build-qemu.sh` passes to
every C, C++ and Objective-C compile: clang's arm64 default fuses `a*b+c`
into one FMA, which rounds differently from the separate operations the fast
paths are proved against (RetroBoot `emulator/reports/arm64-20261013.md`).

## Provenance and license

RetroBoot `emulator/patches/`, at RetroBoot commit
`1860881266449ca2575061e0bd4055c1265cf217`; GPL-2.0-or-later like the QEMU
files they change ("RetroBoot contributors").

| Patch | SHA-256 | Last RetroBoot change |
| --- | --- | --- |
| `retroboot-ppc-mmu-contexts.patch` | `e168e0c1b8f19b2d84cb12d88a39a5ffb999b3e5921d7699a1de70c3ca672f93` | `8759e67` |
| `retroboot-ppc-fpu-fast.patch` | `7b3d799cd15f475cf22f06874a3ed555153c4959eec5223f0ed07b12fda31120` | `e5f8bdf` |
| `retroboot-ppc-fpu-vmx.patch` | `aca6d803cc813c21feff1dd025376131abfb27c55ff2930166f0a03aaf867a44` | `41a2766` |
| `retroboot-ppc-fpu-r17.patch` | `9a0b2a5f493c3c178f850fea9710659ecb56ba3106900bf9d0956093e7318355` | `98d81bc` |
| `retroboot-ppc-branch-cache.patch` | `1f12c4983bb070f3d473e581546a7e9080ae9021524a080ad03607055b6d8116` | `4f10b3f` |

Measurements and reasoning: RetroBoot `emulator/reports/ppcfpu-20261012.md`
and `ppcfpu2-20261012.md`; ClassicMac's own correctness and speed checks are
in `docs/engine-4.0-ati.md`. RetroBoot pairs the branch cache with a VIA
timer-2 hold (`retroboot-via-t2-hold.patch`, not included) because faster
branches exposed a ROM timer-calibration race on slow Linux hosts; see the
report for the risk on ClassicMac.
