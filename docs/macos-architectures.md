# macOS architectures: Apple Silicon, Intel and universal builds

ClassicMac for macOS builds natively for **arm64** (Apple Silicon) and
**x86_64** (Intel). It can ship as two releases, one per architecture, or as
one **universal** app. All of them use the same sources, the macOS 15
deployment target, the hardened runtime with QEMU's JIT entitlements,
Developer ID signing and notarization.

## Audit: what was Apple Silicon specific

The emulator and the app don't depend on Apple Silicon. Only the build,
packaging and release checks assumed arm64.

| Area | Finding |
| --- | --- |
| QEMU patch set (`qfb/`, `cocoaui/`, `powermac/`, `cpu/`, `timers/`, `startup/`, `ati/`, `display/`, ...) | Architecture-neutral. The same prepared sources already ship in the x64 Windows and Linux editions. The RetroBoot AltiVec fast path has an SSE2 lane path that switches on for x86_64 (`FV_SIMD`). It falls back to the portable path on arm64. Every FPU fast path stays bit-identical to softfloat on both, and `-ffp-contract=off` is still passed. The PowerPC timebase uses QEMU virtual time, not a host counter. Shared-memory sizes use the host page size (16 KiB on arm64, 4 KiB on x86_64). |
| TCG | QEMU picks its own TCG backend for the host (aarch64 or i386/x86_64). `MAP_JIT` with `com.apple.security.cs.allow-jit` works the same way on both. The arm64-only W^X toggling stays under QEMU's own `__aarch64__` guard. |
| ATI Radeon R100 | macOS back end: CGL plus an OpenGL 4.1 Core profile loaded at run time. Intel Macs provide it through Intel, AMD or NVIDIA drivers, or Apple's software renderer. `x-gl-renderer` reports which one is in use. |
| GXMetal | Removed in 4.0 (the ATI card replaces it). Nothing to port. |
| Swift app (`app/`) | No architecture-specific code. `swift build --arch` builds either architecture from either host. |
| Copland engine (DingusPPC + SDL2) | Portable C++/CMake. Builds with `CMAKE_OSX_ARCHITECTURES`. |
| `scripts/bundle-release-libraries.py` | **arm64-only:** hard-coded `arm64_sequoia` bottles, `/opt/homebrew`, arm64 receipts, the arm64 OCI platform and thin-arm64 checks. |
| `scripts/build-qemu.sh`, `bundle-qemu.sh` | Ran whichever `brew` came first on `PATH`, built Swift for the host only, and the configure stamp did not record an architecture, so a tree could link the wrong Homebrew. |
| `scripts/verify-release.sh` | Required `arm64` QEMU binaries. |
| Docs | Stated "Apple Silicon Mac required". |

Two gaps that don't depend on architecture showed up during the first Intel
build. Both are fixed for every architecture:

- **Extended attributes.** QEMU's macOS build (`scripts/entitlement.sh`) attaches a Finder icon to `qemu-system-*` (a `Rez` resource fork and `SetFile` FinderInfo). `codesign` rejects both as "detritus". `scripts/lib/sign-app.sh` now clears extended attributes before it signs.
- **dtc.** QEMU picked up Homebrew's dynamic `libfdt` from `/usr/local/lib`, which is on the default linker path. On arm64, `/opt/homebrew/lib` is not on that path, so arm64 builds used QEMU's internal static dtc. `build-qemu.sh` now pins `--enable-fdt=internal`. With that pin, the x86_64 engine links the same set of libraries as the published 4.2.0 arm64 engine, and the prepared tree matches `ClassicMac-macOS-QEMU-source.tar.gz` exactly.

### Homebrew and macOS 15 on Intel

Homebrew no longer publishes Intel macOS bottles for most current formulae.
The arm64 release keeps its rule unchanged: every bundled library is the exact
official `arm64_sequoia` bottle of the installed version. For x86_64,
`bundle-release-libraries.py --arch x86_64` uses the official `sequoia`
bottle, or else an older (`sonoma`, `ventura`) one. When the installed version
has no official Intel bottle at all, `bundle-qemu.sh` passes
`--allow-local-kegs`, and the library comes from the installed keg. These
local-keg libraries still have to pass the same checks:

- thin x86_64
- a macOS 15.0 or earlier minimum version
- an official `homebrew/core` stable receipt for x86_64
- no unbundled dependencies

`release-libraries.json` records them as `"resolution": "local-keg"`. Set
`CLASSICMAC_REQUIRE_OFFICIAL_BOTTLES=1` to refuse them instead.

Homebrew builds from source for the host macOS version. An Intel builder
running macOS 15 Sequoia produces libraries that support macOS 15. A newer
builder can produce libraries that need a newer macOS, and the staging step
rejects them.

## Building one architecture

On the Mac whose architecture you want, the existing commands are unchanged:

```bash
./scripts/build-qemu.sh
./scripts/build-copland.sh
./scripts/build-guest-cd.sh          # or reuse a qualified ClassicMacTools.iso
APP_VERSION=4.2.0 APP_BUILD_VERSION=4.2.0 ./scripts/bundle-qemu.sh
./scripts/make-dmg.sh                # sign, notarize and staple
EXPECTED_ARCHS=x86_64 ./scripts/verify-release.sh dist/ClassicMac.dmg 4.2.0 4.2.0
```

`CLASSICMAC_ARCH` (`arm64` or `x86_64`) defaults to the architecture of the
running process. Homebrew is taken from `/opt/homebrew` (arm64) or
`/usr/local` (x86_64); `CLASSICMAC_HOMEBREW_PREFIX` overrides this. A QEMU
build tree holds one architecture. Switching architecture reconfigures it.
Each script refuses engines that were built for the other architecture.

Without a Developer ID certificate, `bundle-qemu.sh` signs ad hoc, and
`scripts/make-adhoc-dmg.sh` packages that app for testers. The DMG includes
`Open ClassicMac.sh` (`scripts/open-adhoc-build.sh`), which installs and opens
the app on another Mac; see the README.

To name per-architecture releases, use the existing variables. For example:
`DIST_DIR=dist/x86_64 DIST_NAME=ClassicMac-4.2.0-x86_64`.

### x86_64 on an Apple Silicon Mac

With Rosetta 2 (`softwareupdate --install-rosetta`) and an Intel Homebrew in
`/usr/local`, use a second checkout:

```bash
CLASSICMAC_ARCH=x86_64 ./scripts/build-qemu.sh     # re-runs itself under Rosetta 2
CLASSICMAC_ARCH=x86_64 ./scripts/build-copland.sh
CLASSICMAC_ARCH=x86_64 DIST_DIR=dist/x86_64 ./scripts/bundle-qemu.sh
```

`build-qemu.sh` also runs its OpenGL and display tests on the x86_64 binary
under Rosetta.

## Universal app

Build both architectures from the same commit, with the same Tools CD, then
merge them:

```bash
scripts/make-universal-app.sh dist/arm64/ClassicMac.app dist/x86_64/ClassicMac.app
scripts/make-dmg.sh
EXPECTED_ARCHS="arm64 x86_64" scripts/verify-release.sh dist/ClassicMac.dmg 4.2.0 4.2.0
```

The merge works like this:

- Every Mach-O file found in both apps (the app, the QEMU and Copland engines, `qemu-img` and the bundled libraries) becomes a universal binary through `lipo`.
- A library that only one architecture links stays thin.
- All other files must be byte-identical. The exception is each helper's `release-libraries.json`, which combines both provenance records.
- The input signatures and tickets are dropped. The merged app is then signed by the same `scripts/lib/sign-app.sh` code as `bundle-qemu.sh`: inner code first, the hardened runtime everywhere, and the JIT entitlements on both QEMU helpers. Notarize it again with `make-dmg.sh`.

`verify-release.sh` checks the app's architectures against `EXPECTED_ARCHS`.
It also checks that every helper executable has the same architectures, and
that each architecture slice finds all of its bundled libraries. It starts
every engine slice the Mac can run: on Apple Silicon both slices (x86_64
through Rosetta 2), on Intel the x86_64 slice.

## Validation (4.2.0 sources, Intel)

Host: Mac mini, Intel Core i7-8700B, Intel UHD Graphics 630, macOS 15.8,
Xcode 26.3, Homebrew 7.0.9 in `/usr/local`.

| Check | Result |
| --- | --- |
| Prepared QEMU tree compared with the published `ClassicMac-macOS-QEMU-source.tar.gz` (v4.2.0) | identical |
| `build-qemu.sh` (x86_64), all 34 built-in gates | pass. ATI `x-gl-renderer`: `CGL; GL 4.1 INTEL-23.7.4; Intel(R) UHD Graphics 630`; 3D on, `CLASSICMAC_ATI_3D=off` honored |
| `build-copland.sh` (x86_64) | pass. Engine has macOS 15.0 minimum and system libraries only |
| Swift tests (`swift test`, x86_64) | 129 tests, 0 failures. Skipped: 2 optional Copland fixtures, plus the qemu-img test, which passed once the engine was built |
| `test_bundle_release_libraries.py` | 16 tests pass (8 new architecture tests) |
| `bundle-qemu.sh` (x86_64, ad-hoc) | 23 libraries staged (Power Mac helper): 10 formulae from official Intel `sequoia`/`sonoma` bottles, 9 from local kegs. All macOS 15 compatible |
| `verify-release.sh` with `EXPECTED_ARCHS=x86_64` on the app | pass, except the Developer ID check (no certificate on the test Mac) |
| `make-universal-app.sh` (official 4.2.0 arm64 app + this x86_64 app) | 48 universal Mach-O files. Thin by design: `libcrypto.3` (arm64), `libcrypto.4` (x86_64) |
| `verify-release.sh` with `EXPECTED_ARCHS="arm64 x86_64"` on the universal app | pass, except the Developer ID check. The arm64 engine probe is skipped on Intel |
| Bundled engines, hardened runtime + JIT entitlements: ATI realization, `-display classicmac` gate, screamer DMA timing, Quadra ROM under TCG | pass |
| Mac OS 9.2.1 Library template, cold boot through the bundled universal engine (std VGA, G4, 512 MB) | Finder in 33.4–33.8 s; real-time handoff; timebase 25.0003 MHz over 10 s of idle; input, ADB power dialog and graceful shutdown work |
| Universal `ClassicMac.app` launch on Intel | starts as x86_64 and quits cleanly |
