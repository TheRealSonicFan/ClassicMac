# ClassicMac 4.0 engine: the ATI Radeon R100 replaces GXMetal

Branch `claude/4.0-engine`, cut from main `3e24594`. Engine-only: no `app/`
change. Evidence is under `output/4.0-engine/` in the worktree (ignored by Git).

## Summary

- **GXMetal is gone from the engine and release tooling**: no `VGA.gxmetal`
  transport, no Metal renderer, no GXMetal guest software on the Tools CD, the
  OS 9.2.1 installer CD or new OS 9 templates. The `gxmetal/` tree and the
  GXMetal-only scripts are deleted (Git history keeps them).
- **The Power Mac G4 gets an emulated ATI Radeon R100** (PCI 1002:5144, Open
  Firmware `ATY,Rage6p`), ported from RetroBoot. Mac OS 9's own ATI software
  drives it; 3D (RAVE and OpenGL) is rendered on the Mac's GPU through a new
  macOS back end: CGL, OpenGL 4.1 Core profile, `OpenGL.framework` loaded at
  run time. No ClassicMac guest driver is involved.
- **Standard VGA is unchanged** (host resize, packed 1/2/4-bit depths,
  hardware cursor, untracked VRAM, Finder hand-off, icount boot).
- **OpenBIOS** is rebuilt reproducibly with the ATI node patch; the 3.x
  firmware rebuilds bit-identically from source.
- **Tools CD**: GXMetal folder removed; new **ClassicMac Display** helper
  (MIT, derived from RetroBoot Display) so user-installed Mac OS 9 systems
  with ATI's software start at the chosen ATI resolution.
- Optional, separate commit: RetroBoot's **faster PowerPC CPU emulation**
  (MMU contexts, FPU fast paths, branch cache) with `-ffp-contract=off`:
  bit-identical in the FP conformance harness, Quake III +48 %.

## Engine changes

| Area | Change |
| --- | --- |
| `scripts/build-qemu.sh` | no GXMetal copies/patches/gates; stale `gxmetal_*` and patch-created `ati_*` files removed on reruns; ATI patches applied last; ATI/OpenBIOS/realization gates; `CLASSICMAC_PREPARE_ONLY=1` |
| `cocoaui/` | `gxmetal-status-menu.patch` and `game-input-handoff.patch` deleted (the latter's `ui/input.c` API was the GXMetal InputSprocket bridge; its Cocoa hunks only presented that hand-off; all three of its commits were `gxmetal:`); `paste-text.patch` and `media-drawer.patch` regenerated (identical `ui/cocoa.m`) |
| `powermac/classicmac-boot-handoff-display.patch` | `vga-pci.c` section = RetroBoot's `finder-handoff-without-gxmetal.patch` |
| `ppcvid/` | NDRV source uses a vendored, trimmed `src/GXMetalRegistry.h`; protocol SHA stamp and staleness rebuild removed; `qemu_vga.ndrv` unchanged (`3b687b15…`) |
| `ati/` | RetroBoot R100 patch (verbatim), ClassicMac macOS GL patch, OpenBIOS ATI patch (verbatim), tests and harness; provenance in `ati/README.md` |
| `scripts/build-openbios.sh`, `screamer/openbios-ppc` | ATI patch, digest-pinned builder, fixed banner date, optional bit-identical reproduction of the 3.x firmware |
| `scripts/build-guest-cd.sh`, `build-os9-921-installer-cd.sh`, `guestcd/os9-installer/`, `prepare-os9-template.py` | no GXMetal; the Tools CD needs only Homebrew `hfsutils` and `unar` |
| `scripts/bundle-qemu.sh`, `notarize.sh`, `make-dmg.sh`, `verify-release.sh` | `DIST_DIR`, `DIST_NAME`, `DMG_VOLUME_NAME`, `TOOLS_CD_SRC` overrides (defaults unchanged; `APP_VERSION`/`APP_BUILD_VERSION` already existed); a GXMetal-carrying Tools CD is refused; 4.x checks ATI and the absence of GXMetal |
| `scripts/benchmark-os9-boot.py`, `disable-os9-disk-check.sh` | no `VGA.gxmetal`; `gxmetal-vnc.py` renamed `classicmac-vnc.py`; `GXMETAL_APP/QEMU` → `CLASSICMAC_APP/QEMU` |
| `guestcd/classicmac-display/` | ClassicMac Display source (68k INIT + PowerPC appe), Retro68 build script, committed MacBinary outputs; added to the Tools CD with a Read Me section |
| `cpu/` (separate commit) | RetroBoot's five PowerPC speed patches, `-ffp-contract=off`, CPU property gates, configure-flag stamp |

Deleted GXMetal-only scripts: `apply-gxmetal-to-qemu.sh`,
`build-gxmetal*.sh`, `compose-/prepare-gxmetal-game-base.sh`,
`decode-gxmetal-*.py`, `extract-gxmetal-guest-results.sh`,
`gxmetal-game-sweep*.py`, `gxmetal-ut-checkbuttonkeys.py`,
`package-gxmetal-release.sh`, `test-gxmetal-os9.sh`,
`prepare-unreal-tournament-test-image.sh`,
`prepare-reality-bytes-runtime-trace.py`.

Left as is, outside this task's scope: `scripts/package-machine-template.py`
still writes the catalog's `gxMetalVersion` field, which the 3.x app requires
(non-optional, validated); `copland/README.md`, `ios/README.md`, `docs/` and
release notes still mention GXMetal historically.

## Design: the ATI card on macOS

RetroBoot's model (see `ati/README.md`): register file, PLLs/CRTC modes, a
command processor (PIO queues and aliases, ring, indirect buffers, PCI GART,
scratch write-back), the 2D engine and the R100 3D engine. 3D draws are queued
to an `ati-gl` thread that owns the GL context and renders into one FBO per
guest colour buffer; render targets are read back into VRAM at sync points
(2D access, status reads, page flips, asynchronously at the flip). Scanout is
QEMU's VGA surface, so Cocoa, VNC and screendump see the card like std-VGA.

macOS back end (`ati/classicmac-ati-macos.patch`): `ati_gl.c` dlopens
`/System/Library/Frameworks/OpenGL.framework/OpenGL`, picks an accelerated
OpenGL 4.1 Core pixel format (any 4.1 Core renderer as a second choice, then
labelled "(software)"), creates a CGL context without a drawable and makes it
current on the `ati-gl` thread; every `ATI_GL_FUNCS` entry point is core in
both GLES 3.0 and GL 4.1 and is resolved with `dlsym` (no `glInvalidate*`, no
client-side arrays, VAO bound). Only `CGLTypes.h` is included, so nothing
deprecated is referenced and `qemu-system-ppc` has no OpenGL/Metal link
dependency (build-gated). Shaders get `#version 410 core` and an explicit
`layout(location = 0)` fragment output. ANGLE/Metal was not needed.

GL failure: as in RetroBoot, `ati: no host GL (…); 3D drawing is discarded`
is logged, `x-accel-stats` ends with `gl=off`, `x-gl-renderer` is empty, the
card stays a working 2D card, and Mac OS's ATI 3D software draws nothing
visible. `CLASSICMAC_ATI_3D=off` (or `RETROBOOT_ATI_3D=off`) forces this.

OpenBIOS: `ati/openbios-ati-radeon.patch` applies to OpenBIOS `e1e703ac` +
`powermac/openbios-classic-macos-8.patch` alone (RetroBoot's AirPort,
sound-objects, PMU and find-wordlist patches are not prerequisites). For
device 1002:5144 only it names the node `ATY,Rage6p`, enables bus mastering,
programs the `-g` boot mode through the ATI CRTC and deletes the QEMU VGA
driver property. Other devices take the unchanged path (RetroBoot verified the
card-off device tree byte-identical with its tree dumper; not re-run here, but
standard-VGA guests boot as before).

## QEMU argument sets

Everything not listed is unchanged from 3.x `QEMURunner` (machine, CPU, RAM,
`-L`, audio, monitor/QMP sockets, `-action reboot=shutdown`, drives, NIC,
ndrvloader/tablet/9p, `-prom-env output-device=ttya`).

**(a) Standard VGA** (default card): 3.x arguments minus `-global VGA.gxmetal=on`
(QEMU 4.0 rejects that property and would exit):

```
-accel tcg,tb-size=512 -icount shift=4,sleep=off      # hard-disk starts only
-M mac99,via=cuda,audiodev=snd0 -cpu 7400 -m 512 -L <pc-bios>
-vga std -global VGA.host-resize=on -global VGA.vgamem_mb=64
-global VGA.packed-lowbpp=on -global VGA.untracked-vram=on
-global VGA.hardware-cursor=on
-global VGA.classicmac-boot-handoff=on               # hard-disk starts only
-global macio-ide.dma-completion-delay-ns=0          # 1000000 for CD starts
-prom-env output-device=ttya -g <W>x<H>x<15|32>
```

**(b) ATI Radeon R100** at a Mac screen W x H:

```
-accel tcg,tb-size=512                               # no -icount
-M mac99,via=cuda,audiodev=snd0 -cpu 7400 -m 512 -L <pc-bios>
-vga none
-device ati-vga,id=ati0,model=r100,vgamem_mb=32,romfile=,guest_hwcursor=on,xres=<W>,yres=<H>,refresh_rate=<Hz*1000>
-global macio-ide.dma-completion-delay-ns=0
-prom-env output-device=ttya -g 640x480x32
-prom-env classicmac-display=<W>x<H> -prom-env retroboot-display=<W>x<H>
```

- Drop every `-global VGA.*` (no VGA device exists) and the icount boot:
  the Finder hand-off detector is a std-VGA feature, RetroBoot qualified the
  card only in real time, and Deluxe v6 reaches the Finder in about 20 s
  without it. The app's 15 s `classicmac-boot-complete` fallback is harmless
  (it reports "real-time").
- `romfile=` is required: the default `vgabios-ati.bin` is not bundled.
- `id=ati0` gives the status path `/machine/peripheral/ati0`.
- `-g 640x480x32`: ATI's driver starts every session at 640 x 480 (the
  emulated NVRAM is not kept), so the firmware boot frame matches it.
- Refresh: the highest of 75, 60, 50 Hz whose EDID pixel clock stays at or
  below 162 MHz: `clock_kHz = Hz*1000*(W + W*35/100)*(H + H*35/1000) / 10^7 * 10`
  (integer arithmetic, as QEMU's `edid-generate.c`); ATI's driver ignores the
  whole EDID above about 165 MHz. 1024x768 → 75 Hz (`refresh_rate=75000`),
  1280x800 → 75 Hz, 1920x1200 → 50 Hz.
- `classicmac-display` is read by ClassicMac Display (Tools CD);
  `retroboot-display` by RetroBoot Display, which the Deluxe v6 template
  already has. Passing both is harmless.
- Environment: `CLASSICMAC_ATI_3D=off` disables 3D (diagnostics only).
- CD/installer starts should stay on standard VGA (RetroBoot never uses the
  card for the CD route).

## What the app should tell users about the ATI card

- **What it is**: an emulated ATI Radeon (Radeon Mac Edition, PCI) that
  Mac OS 9's own ATI drivers use; QuickDraw 3D RAVE and OpenGL games render on
  the Mac's GPU. Applies at the next start of the guest.
- **Needs ATI's Mac OS 9 software in the guest**: *ATI Driver Update*,
  *ATI Radeon 3D Accelerator*, *ATI Resource Manager*, Apple's
  *OpenGLRendererATI* in Extensions (Deluxe v6 has them). Without them
  (e.g. the Mac OS 9.2.1 template) Mac OS falls back to its generic "VGA
  Display" driver: 640 x 480, Millions of colors only, no resolution choice,
  no 3D acceleration, but it boots and works (verified). The app cannot fix
  that from the host.
- **Resolution** (RetroBoot's policy, recommended for the app): exact sizes
  from 640 x 480 up to 1920 x 1440, landscape, width a multiple of 8, within
  the pixel-clock rule above (the EDID's detailed timing becomes a mode);
  otherwise the largest fixed ATI mode that fits (640x480, 800x600, 832x624,
  1024x768, 1152x870, 1280x960, 1280x1024, 1600x1200, 1792x1344, 1856x1392,
  1920x1080, 1920x1200, 1920x1440; Monitors on Deluxe v6 lists these plus
  the EDID "built-in" modes). Mac OS starts at 640 x 480; a display
  helper (ClassicMac Display, or RetroBoot Display on Deluxe v6) switches
  during the extension parade. Without a helper Mac OS stays at 640 x 480
  until the user picks a size in Monitors. Resizing the host window does not
  change the guest resolution (no host-resize channel); a size chosen in
  Monitors or by a game lasts until restart.
- **Colors**: ATI's driver offers 256, Thousands and Millions; no Black &
  White, 4 or 16 colors (std-VGA's packed low-depth modes are not available).
- **Cursor**: drawn by the card into the frame (`guest_hwcursor=on`), not a
  host cursor layer.
- **Failure fallback**: if this Mac has no usable OpenGL, QEMU still starts
  but 3D is discarded (games draw nothing). The app should probe once (see
  below) and offer the card only when `x-gl-renderer` is non-empty, falling
  back to standard VGA otherwise.
- **Known issue (not ATI-specific)**: an intermittent "Apple Audio Extension
  illegal instruction" alert at startup, from OpenBIOS's truncated
  `sound-objects` property; see Risks.

## Detecting 3D at run time

QOM on `/machine/peripheral/ati0` (QMP `qom-get`):

- `x-gl-renderer` (string): e.g. `CGL; GL 4.1 Metal - 91.7; Apple M5 Max`;
  empty when 3D is off (no host GL or `CLASSICMAC_ATI_3D=off`). A suffix
  `(software)` means Apple's software renderer.
- `x-accel-stats` (string): `ops2d=… packets3=… draws3d=… verts3d=… flips=…
  vblanks=… gl=on|off`. `draws3d` increasing means the guest is drawing 3D
  through the card right now; `gl=on` means host GL is up.

Probe before offering the card (well under 0.2 s, no guest): start
`qemu-system-ppc -M mac99,via=cuda -cpu 7400 -m 256 -L <pc-bios> -vga none
-device ati-vga,id=ati0,model=r100,vgamem_mb=32,romfile= -display none
-monitor none -serial none -nic none -S -qmp stdio`, read `x-gl-renderer`,
quit (this is `ati/tests/test_qemu_ati.py`).

## Build, bundle and release

```sh
scripts/build-copland.sh                         # Copland engine (bundle needs it)
scripts/build-qemu.sh                            # QEMU + all gates (needs a GPU session)
CLASSICMAC_PREPARE_ONLY=1 scripts/build-qemu.sh  # patch the vendor tree only
scripts/build-guest-cd.sh                        # dist/ClassicMacTools.iso (hfsutils, unar)
APP_VERSION=4.0.0 APP_BUILD_VERSION=4.0.0 DIST_DIR=$PWD/output/dist \
  scripts/bundle-qemu.sh                         # SIGN_IDENTITY=- for ad hoc
DIST_DIR=$PWD/output/dist APP_VERSION=4.0.0 APP_BUILD_VERSION=4.0.0 \
  scripts/verify-release.sh output/dist/ClassicMac.app
# release only, not run here:
DIST_DIR=... DIST_NAME=ClassicMac-4.0.0 DMG_VOLUME_NAME=ClassicMac scripts/make-dmg.sh
```

Optional rebuilds: `OPENBIOS_VERIFY_PINNED=1 scripts/build-openbios.sh`
(Docker/colima, pinned builder; `OPENBIOS_MAKE_JOBS=1` avoided qemu-user
segfaults under colima's x86 emulation; `OPENBIOS_EXTRA_PATCHES=` for
extra OpenBIOS patches), `PPCVID_BUILD_NDRV=1` or
`RETRO68_BUILD=… scripts/build-ppcvid-ndrv.sh`,
`RETRO68_TOOLCHAIN=… guestcd/classicmac-display/build.sh`,
`ati/tests/run-gl-smoke.sh` (host GL check without QEMU).
Existing build directories are reconfigured automatically when the compiler
flags change (configure stamp).

Firmware and driver hashes: `screamer/openbios-ppc` (unstaged ELF)
`e03e97cc1f54841abe72013adbe2b9fece0ee7f5ae80c3dfe99820cbdb841904`, staged
(black background) `3f50958a9663da41b44153d868457a50f0ebed768bb15eb75756b1f3fbd5af62`;
OpenBIOS `e1e703ac0ad615ab0d7edea54db600aaa629bf07`, builder
`ghcr.io/openbios/openbios-builder@sha256:bf806644…ef8b38`, banner date
"Oct 17 2026 00:00", patches `openbios-classic-macos-8.patch` `82134e41…0744`
and `openbios-ati-radeon.patch` `c6282bb9…0a88`. `ppcvid/qemu_vga.ndrv`
`3b687b15…5722` (unchanged). Tools CD built here (not committed):
`23a42184811c7e1ad8718b6746e061c3a1c3e3dd43af25c9c828b3fa326fca22`.

## Verification

Host: Apple M5 Max, macOS 27.2, Xcode SDK; logged-in session (CGL worked).
Guests ran headless (`-display vnc=unix:…`, HMP `screendump`, QMP input) with
the harness `ati/tests/guest_run.py`; every emulator was stopped.

Source and build (reproducible checks):

| Check | Result |
| --- | --- |
| `git apply` of every patch in order (GXMetal-free series, then ATI) | clean; regenerated `paste-text`/`media-drawer` give a byte-identical `ui/cocoa.m` |
| `ppcvid/driver` rebuilt (Retro68 + Universal Interfaces from the root checkout's existing `vendor/Retro68-build`, used read-only in place, nothing copied; built in `scratch/`) | old source and vendored-header source both `3b687b15…`, identical to the committed NDRV |
| ClassicMac Display built with the same toolchain (read-only) | no warnings; MacBinary type/creator `INIT`/`CMds` and `appe`/`CMds`, Finder flags clear |
| OpenBIOS unmodified rebuild (3.x date) | bit-identical to 3.x `cc5bccd2…` |
| `scripts/build-qemu.sh` gates | all pass, incl. ATI realization: `CGL; GL 4.1 Metal - 91.7; Apple M5 Max`, `gl=on`; off switch; VGA set realizes; no OpenGL/Metal link |
| `ati/tests/run-gl-smoke.sh` | context, both shaders compile/link under GLSL 4.10, FBO complete, triangle colour exact, no GL error |
| Bundle at HEAD (Developer ID for local test, hardened runtime, 4.0.0, `DIST_DIR=output/4.0-engine/dist`) + `verify-release.sh` (app) | pass (`verify-release-app-2.log`; helper sha256 `ac9cc7da…90bd`); the bundled helper passes the ATI realization test and boots Deluxe v6 on the ATI card to a 1024x768 Finder with the Tools CD mounted (`bnd/`) |
| Tools CD | no `GXMetal` bytes; ClassicMac Display folder present |
| `scripts/test-prepare-os9-template.py`, `test_package_machine_template.py`, `test_bundle_release_libraries.py` | pass |
| `swift test` in `app/` (unchanged app) | 110 tests, 2 skipped, 0 failures (see Not run) |

Guest evidence (actual guest runs, `output/4.0-engine/…`):

| Run | Evidence | Result |
| --- | --- | --- |
| Deluxe v6 (catalog sha256 `9d0d0c51…` verified) on ATI 1024x768, real time | `dlx/t12.png` (640x480 "Starting Up"), `dlx/t20.png` (Finder 1024x768) | Finder at ~20 s at the requested size; QEMU log `ati: 3D engine on host GL: CGL; GL 4.1 Metal - 91.7; Apple M5 Max` |
| Same, interactive | `dlx/s01…s17` | HD/Games/Quake folders opened by mouse and type-select; Quake III Arena Demo menu and `demo001` rendered textured and lit; guest `gfxinfo`: `GL_VENDOR ATI Technologies Inc.`, `GL_RENDERER ATI Radeon OpenGL Engine`, `GL_VERSION 1.1 ATI-6.26`; `x-accel-stats` draws3d 0 → 2,137,869, verts3d 144 M, `gl=on`; Quake quit back to a 1024x768 Finder; Special > Shut Down exited QEMU |
| Quake III `timedemo 1; demo demo001`, baseline engine | `dlx/s10-result.png`, `q3-base-1..3` (`ati/tests/deluxe_q3_timedemo.py`) | 90.8 fps (first, manual run), then 102.8 (read from `q3-base-1/result-console.png`; OCR missed it), 105.4, 104.7 fps (1346 frames); boot to Finder 21.5/20.5/20.5 s |
| Mac OS 9.2.1 template (`bc0290ed…` verified) on standard VGA, icount + automatic hand-off | `v921/t25.png`, `v921b/*` | Finder; clock hand-off reported real-time; HD window opened; GXMetal extension loads and GXMetal Test reports "GXMetal loaded, but RAVE rejected it for the main display" (graceful, no crash); clean Shut Down |
| Same template on the 3.x engine (the root checkout's existing `vendor/qemu` build, run read-only with `-global VGA.gxmetal=on`, A/B) | `ab32/t30.png` | the same 640x480 Finder under VNC as the 4.0 engine, so the 640x480 (not the `-g` 1024x768) is template/VNC behaviour, not a regression; the Cocoa window's host-resize normally sets the size |
| Mac OS 9.2.1 template on ATI (no ATI software on disk) | `v921a/*` | boots to Finder at 640x480; Monitors shows "VGA Display", Millions only, 640x480 only; `x-accel-stats` vblanks 0, mmio_w 11 (no ATI driver attached); responsive; clean Shut Down |
| ClassicMac Display (Deluxe clone, RetroBoot Display moved out, ClassicMac Display installed, `classicmac-display=1280x800`, xres/yres 1280x800) | `cmd*/t12.png`, `cmd*/t30.png` | 640x480 at 12 s, 1280x800 Finder at 30 s on three boots; the first boot of that disk stopped at "Apple Audio Extension illegal instruction" (see Risks) |
| Deluxe v6 on ATI, Monitors control panel | `dmon/s02…s04` | "VGA Display": colours 256 / Thousands / Millions (Grays disabled); resolutions 640x480 … 1920x1440 fixed ATI modes plus EDID "built-in" modes; clean Shut Down |
| Experiment: ATI with `-icount shift=4,sleep=off` and the 15 s HMP hand-off | `dlxic/t*.png` | boots to the Finder at 1024x768 by ~18 s, i.e. no gain over real time (18.5 s); not recommended, not qualified |
| ClassicMac's own boot benchmark (`scripts/benchmark-os9-boot.py`, 9.2.1, icount + hand-off) | `boot-bench-vga.jsonl` | Finder in 9.3 / 9.3 / 9.9 s (baseline engine) |

Across the 28 guest boots of this session one failed (the Apple Audio
Extension alert above); all others reached a responsive Finder.

### Optional commit: faster PowerPC CPU emulation

Correctness (bare metal, RetroBoot's harness `tests/ppcfpu`: 317 FP and
AltiVec encodings x 16 FPSCR/MSR/VSCR configurations, every outcome bit;
`fpconf.elf` built with the pinned builder image's `powerpc-linux-gnu-gcc`
12.2.0, sha256 `4d58e2cc…88b3`; `output/4.0-engine/fpconf/`):

| Check | Result |
| --- | --- |
| `conf`, 8 seeds x 20,000 = 811 M vectors per arm | 11 arms bit-identical to the softfloat reference (`fast-fpu=off`): all on, `fast-branch=off`, `x-fast-fpu-mask` 0x6f/0x5f/0x3f, `x-fast-branch-mask` 5/3/2, `mmu-contexts=off`, and the unpatched ClassicMac 4.0 build |
| `smc` (code rewritten under every branch cache, with and without `icbi`) | every arm equal to the unpatched build (92 calls; the same 2 stale results QEMU gives without `icbi`) |
| Mac OS 9.2.1 on VGA with icount boot + hand-off | Finder, Calculator 1/7 = .14285714286, clean Shut Down (`v921c/`) |

Speed (same host, interleaved where possible):

| Workload | Without | With |
| --- | --- | --- |
| Quake III `demo001` on ATI (fps, 3 runs) | 102.8, 105.4, 104.7 | 155.8, 152.6, 154.8 (+48 %) |
| Deluxe v6 boot to Finder on ATI, real time (s) | 21.5, 20.5, 20.5 | 18.5, 18.5, 18.5 |
| Mac OS 9.2.1 boot to Finder, icount + hand-off (s) | 9.35, 9.31, 9.90 | 9.34, 8.76, 9.60 (unchanged: no branch slots in icount TBs) |
| FP kernels (`fpconf bench`, ns/op, best of 3) | e.g. fadd 11.6, fmul 11.5, fdiv 13.0, fmadds 17.1, AltiVec lighting 10.8 | 3.0, 2.3, 2.5, 4.6, 4.7 (x1.6–x5.2); `int_with_lfs_stfs` 0.29 → 0.38 (slower) |

Risk (closed by `timers/`, see `docs/engine-4.0-via-timers.md`): RetroBoot
pairs the branch cache with a VIA timer-2 hold because faster branches moved
the Mac OS ROM's timer-calibration loop into a race on a slow Linux host
(N5105), causing a pre-gray hang. VGA boots are immune (icount: guest time
does not advance while translating); ATI and CD starts run in real time.
ClassicMac now applies RetroBoot's `cuda-via-timers`, `pmu-via-timers` and
`via-t2-hold` patches after the CPU patches.

## Not run

- Cocoa window display with the ATI card (`-display cocoa`): not opened on
  the user's desktop; only VNC/screendump paths were exercised. RetroBoot
  never used Cocoa either. Cocoa scans out the same VGA surface, but this is
  unverified.
- Notarization, DMG creation, `make-dmg.sh`/`notarize.sh` execution (not
  authorized); `verify-release.sh` was run on the `.app` only.
- No Intel Mac, no Mac without GPU (software CGL fallback untested), no
  macOS 15 host.
- No long soak, no restart chains, no sound path (`-audiodev none`), no
  networking, no shared folder with the ATI card.
- In-guest installation of ClassicMac Display from the Tools CD by drag and
  drop (installed offline on a disk clone instead).
- The app itself was not changed or launched against this engine. `swift
  test` passed (110 tests, 2 skipped, 0 failures) only because its
  QEMURunner tests check argument lists, which
  still contain `-global VGA.gxmetal=on`; with this engine those arguments
  make QEMU exit ("can't apply global VGA.gxmetal=on: Property 'VGA.gxmetal'
  not found", reproduced).

## Risks

- **App coupling**: the 3.x app passes `-global VGA.gxmetal=on`; QEMU 4.0
  exits with "Property 'VGA.gxmetal' not found". The app (and its tests,
  GXMetal status menu/JSON `gxmetal-status` QOM reads, the catalog's
  `gxMetalVersion`) must change together with this engine.
- **Apple Audio Extension crash (pre-existing)**: OpenBIOS e1e703ac publishes
  the screamer `sound-objects` property 2 bytes short; Mac OS 9's Apple Audio
  Extension then sometimes overruns a stack buffer at startup ("illegal
  instruction"). Seen once in 28 boots here; RetroBoot measured it and
  fixed it with `emulator/patches/openbios-sound-objects-terminator.patch`
  (one length, 0x3e4 → 0x3e6). Not included (outside this task's OpenBIOS
  scope); `OPENBIOS_EXTRA_PATCHES=…/openbios-sound-objects-terminator.patch
  scripts/build-openbios.sh` builds it.
- **3D without host GL** draws nothing; the app must probe before offering
  the card. Apple's OpenGL is deprecated (still present on macOS 27.2); a
  future macOS without OpenGL.framework would turn 3D off (logged, `gl=off`).
- **Apple GL log noise**: Apple's driver logs once "unit 1
  GLD_TEXTURE_INDEX_2D is unloadable … using zero texture" when a sampler
  has no texture bound; same result as GLES (zero texture), harmless.
- The ATI card is new to ClassicMac: Cocoa presentation, the media drawer,
  paste-text, Force Quit and window resize flows were not exercised with it.

## Next safe action

Integration owner: update `QEMURunner`/tests to the argument sets above (drop
`VGA.gxmetal`), add the card choice with the GL probe and status from
`x-gl-renderer`/`x-accel-stats`, then decide on the CPU-speed commit and the
sound-objects OpenBIOS fix before a 4.0 beta build.
