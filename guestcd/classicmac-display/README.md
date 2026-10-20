# ClassicMac Display

Mac OS 9 helper for the emulated ATI Radeon R100 (`ati/`). ATI's own display
driver starts every session at 640 x 480 because the emulated NVRAM is not
kept. ClassicMac passes the wanted Mac screen size as an Open Firmware option,

```
-prom-env classicmac-display=WIDTHxHEIGHT
```

which Mac OS copies into the Name Registry. ClassicMac Display reads it (and,
for disks prepared by RetroBoot, `retroboot-display`) and sets the matching
mode through the Display Manager, as the Monitors control panel does, keeping
the colour depth and preferring 60 Hz. The size must be one ATI's driver
offers: its fixed modes, or the monitor EDID's detailed timing, which QEMU
builds from `ati-vga,xres=W,yres=H,refresh_rate=…`.

| File on the Tools CD | Type/creator | What |
| --- | --- | --- |
| ` ClassicMac Display Startup` | `INIT`/`CMds` | 68k startup extension: switches during the extension parade and saves the configuration (`DMSaveScreenPrefs`), so the Finder starts at the size; the leading space loads it early |
| `ClassicMac Display` | `appe`/`CMds` | PowerPC background-only application: the same switch when the Process Manager starts it, for disks without the extension |

Both go into `System Folder:Extensions`. Without the option (the standard
card), at the right size already, or when the driver lacks the size, nothing
happens. A size chosen later in Monitors or by a game lasts until restart.

## Build

`bin/*.bin` are committed MacBinary files (like the other prebuilt guest
drivers), so `scripts/build-guest-cd.sh` needs no cross compiler. To rebuild
them with Retro68 (PowerPC and 68k toolchains):

```sh
RETRO68_TOOLCHAIN=/path/to/Retro68-build/toolchain guestcd/classicmac-display/build.sh
```

| File | SHA-256 |
| --- | --- |
| `bin/ClassicMacDisplay.bin` | `420a14c7de5c88dc319c5867ecaf8f0374eb95f0f863adcf5bf2ad0c0beea37b` |
| `bin/ClassicMacDisplayInit.bin` | `3efea02800c2225d1f032324aa84027c011900547f19424d6950ee19bb6baaa2` |

## Provenance and license

MIT (`LICENSE`). Derived from RetroBoot Display (RetroBoot
`guest/rbdisplay/rbdisplay.c` and `guest/rbdisplay/init/rbdisplayinit.c`,
RetroBoot commit `1860881266449ca2575061e0bd4055c1265cf217`, "Original
RetroBoot code (MIT)"). Changes: the option name (`classicmac-display`, with
`retroboot-display` as a fallback), the file creator (`CMds` instead of
`RBds`), names and version strings. The application imports Mac OS's
DisplayLib and NameRegistryLib at run time (Universal Interfaces import stubs
at build time) and both files contain Retro68's start-up runtime, as
ClassicMac's other Retro68-built guest drivers do.
