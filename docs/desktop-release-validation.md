# ClassicMac 4.1.0 qualification — October 18, 2026

The Windows/Linux desktop implementation is `389792f`; the release tag adds
screenshots and qualification records. Native x64 QEMU engines are built on
Windows/MSYS2 UCRT64 and Ubuntu 24.04. The Mac app retains the 4.0 engine and
native frontend with 4.1 version metadata and updated notices.

## Actual hosts and fixtures

AustinLand created dedicated Proxmox VMs on SazProx: VM 171, Windows 11 Pro
build 26100, and VM 170, Debian 13. Each has four cores, 8 GB RAM and a 100 GB
disk. Tests used interactive Windows sessions and an unprivileged Linux user
under Xvfb with the Chromium sandbox enabled. No user machine folder was used.

Both hosts downloaded the real Library's clean Mac OS 9.2.1/GXMetal 2.3.0
32 GB v2 archive, paused and resumed it, verified SHA-256, safely extracted
it and imported sanitized settings. Archive SHA-256:
`bc0290edf6e0eccba26738d14723d76d9b3acd9018463ce0c427f9152f77959d`.
That imported machine supplied the extended guest checks. The independent
Retro68 probe is in `desktop/tests/guest`; it is not shipped in the product.

| Check | Windows 11 | Debian 13 |
| --- | --- | --- |
| New disk, machine import and settings round trip | Pass | Pass |
| Real Library pause/resume, checksum and install | Pass | Pass |
| OS9 Finder boot and authenticated display | Pass | Pass |
| Pause/resume and QMP status | Pass | Pass |
| Clean Restart into a new engine; display reconnect | Pass | Pass |
| Native guest text input, including é and ñ | Pass, capture reviewed | Pass, capture reviewed |
| Guest normal shutdown, exit reason `guest-shutdown` | Pass | Pass |
| Quadra 800, Mac OS 8.1 CD to Finder and normal shutdown | Pass, capture reviewed | Pass, capture reviewed |
| Guest reads a host file and writes a reply through 9p | Unavailable | Pass |

[Windows and Linux captures](screenshots/desktop/README.md) are direct app
captures. The [Linux report](evidence/4.1.0/linux-parity.json) and
[Windows report](evidence/4.1.0/windows-parity.json) retain final check results.
These prove the listed operations; they do not imply exhaustive UI coverage.

## Corrections found through real-host testing

Starting an EXE with System32 as its working directory made QEMU encounter
Windows' `en-US` directory instead of its keyboard map. Engines now start in
their own bundled binary directory. Restart tests wait until the replacement
engine finishes QMP negotiation before sending commands.

The earlier hardware-reset path could leave HFS mounted and trigger Disk
First Aid on the next boot. Desktop Restart now sends the guest power key,
lets Mac OS finish normal shutdown and relaunches only after `guest-shutdown`.
The final tests complete that cycle without dismissing a startup disk check.
Guests blocking shutdown remain running until the user resolves the guest
prompt or explicitly chooses Force Off.

The smoke/extended tests require Finder framebuffer evidence before input
and after restart. Display connection alone is insufficient. An early
screenshot caught the guest still starting up, preventing a false input pass.

## Coverage and platform limits

Twelve Node tests cover launch arguments, package/path bounds, symlinks,
resumed HTTP ranges and hash verification, bounded flat-tar extraction,
MacRoman planning and paste cancellation. Native build gates check both QEMU
machines and ATI realization; Linux checks EGL/GLES 3, Windows checks WGL
where the driver provides it. CI also boots a separate checksum-pinned
8 GB OS9 fixture through the packaged applications.

Windows binaries are unsigned. Linux requires x64 and glibc 2.39 or newer,
with host desktop, audio and graphics drivers. Both new editions provide
Power Mac G4 and Quadra 800; Copland remains macOS-only. Linux supports 9p
sharing; the Windows QEMU backend does not. Physical GPU acceleration, actual
audio output, guest Internet browsing and a game compatibility suite were
not qualified on these virtual hosts. Those features must not be inferred
from boot or device-realization tests.

The Mac Platinum audit covers 32 component states/patterns at 1×/2× and 95
system-font ASCII glyphs/advances. It does not certify the entire Mac UI or
the shared CSS desktop as pixel perfect. See the
[Platinum fidelity audit](platinum-fidelity-audit.md) for remaining coverage.

Final native packaged CI passes: [Windows 39158984879](https://github.com/amcchord/ClassicMac/actions/runs/39158984879)
at `389792f`, and [Linux 39158930105](https://github.com/amcchord/ClassicMac/actions/runs/39158930105)
at `b488733`. The source difference is a Windows workflow artifact/cache-only
change. Every packaged src/UI file was compared with the final implementation
(allowing Windows CRLF); both match. Bundled runtime inventories, Tools CD hash
and current notices were checked: Windows 209 files/72 license notices;
Linux 190 files/37 license notices. Both packaged CI captures were reviewed.
