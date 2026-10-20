# Lab build: stretch and measure the startup races

`classicmac-lab-startup-races.patch` is for the lab only.
`scripts/build-qemu.sh` never applies it, and its files are in `PATCHED_FILES`,
so the next run of the script removes it again. It adds two knobs, off by
default, that move this host to where RetroBoot's slower or busier hosts are,
and two trace events that show how far away that is.

| Knob | Default | Stands for |
| --- | --- | --- |
| `-global cuda.x-lab-sync-sr-delay-ns=N` | -1 (off) | The sync step's shift interrupt comes N ns after the TACK write instead of 20 µs: a vCPU that needs 20 µs − N longer to reach its SR read (type A) |
| `-global macio-ide.x-lab-srst-delay-us=N` | 0 (off) | QEMU's main loop runs the SRST bottom half N µs after the SRST edge (type C; RetroBoot's lab delayed it 3 ms) |

| Trace event | Fields |
| --- | --- |
| `cuda_lab_sync_sr_read` | Virtual ns from a sync step's TACK write to the guest's next SR read; IFR's SR bit at that read; whether the step's shift interrupt was still pending. `pending 0` means it had already come, and QEMU's own model then loses it (the ROM's second sync step; the SR bit is still the first step's) |
| `cuda_lab_sr_int` | Every Cuda shift interrupt: virtual ns after it was due; whether it answers a sync step; whether a VIA read delivered it (`sr-int-on-access`) or QEMU's main loop did. On macOS the main loop runs timers in whole milliseconds |
| `ide_lab_srst_done` | Host ns from the SRST edge to the reset being carried out; whether the guest had released SRST by then; whether it was carried out on access (`srst-complete-on-access`) or by the bottom half |

`ati/tests/boot_soak.py --trace EVENT` collects them per boot
(`sync_sr_reads_us`, `sr_int_late_us`, `srst_done_us`) and classifies hangs
as A, B or C.

## Build

From a tree that `scripts/build-qemu.sh` has built:

```sh
git -C vendor/qemu apply "$PWD/startup/lab/classicmac-lab-startup-races.patch"
ninja -C vendor/qemu/build qemu-system-ppc
mkdir -p output/startup/bin-lab
cp vendor/qemu/build/qemu-system-ppc output/startup/bin-lab/
scripts/build-qemu.sh      # resets the tree and rebuilds the product binary
```

The lab binary uses the same `vendor/qemu/pc-bios`. Measurements and the
reproduction: `docs/engine-4.0-startup-races.md`.
