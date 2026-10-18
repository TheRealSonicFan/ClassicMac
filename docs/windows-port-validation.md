# Historical Windows prototype — October 18, 2026

The prototype below is superseded by the stable 4.1 Windows/Linux release.
See [current qualification](desktop-release-validation.md) for shipped features and tests.

Source: `3b2d435` on `codex/windows-app`, [draft PR #24](https://github.com/amcchord/ClassicMac/pull/24).
[Native Windows CI run 39143255474](https://github.com/amcchord/ClassicMac/actions/runs/39143255474)
completed successfully. This is initial Windows work, separate from the
notarized macOS 4.0.0 stable release.

## Result

The Windows runner compiled the shared patched QEMU 11.0.2 m68k/PowerPC
engines and WGL backend under MSYS2 UCRT64, staged their DLL dependency
closure and firmware, and built an Electron x64 distribution. Device/ATI
realization gates and six JavaScript tests pass (symlink tests may skip when
the Windows account lacks symlink privileges). A required libgcrypt backend
provides authenticated VNC's DES cipher; it is not disabled to make boot pass.

The **packaged Windows EXE**, with only its bundled runtime, booted a
checksum-pinned disposable Mac OS 9.2.1 machine to Finder. The screenshot was
visually reviewed. The test also verifies pause/resume status, reset into a
new engine, display reconnection and normal guest shutdown. QEMU exits were
code 0 with `host-qmp-system-reset`, then `guest-shutdown`. Display evidence:
`connected=true`, `canvas=true`; shutdown evidence: `cleanShutdown=true`.
The CI artifact contains no guest disk. The macOS development frontend smoke
also passes against the native Mac engine, but is not counted as Windows proof.

The ZIP and evidence are retained locally at `output/windows/2026-10-18/`:

- `ClassicMac-4.0.0-Windows-x64.zip`
- SHA256 `ae7b408dbd47472b0e11409a2fed87077e76887d65c13fb61b9a1e4619980db7`
- `desktop.png`, display/shutdown JSON, README and SHA256SUMS.

Unzip and run `ClassicMac.exe`, preserving its neighboring files. Open a
stopped `.classic` folder copied from Mac or create a new Mac and select its
installation CD. The implementation supports G4 and Quadra packages, settings,
media, power controls and loopback password-protected noVNC. The renderer is
sandboxed and isolated from Node; QMP uses private process pipes.

## Outstanding before Windows publication

This prototype is **unsigned** and has not been published as a Windows
release. Copland, integrated Library downloads, host text paste and host folder
sharing are still unported. Actual Windows hardware ATI/OpenGL acceleration,
Quadra guest boot, audio/networking and game/installer compatibility need
qualification. CI can fall back to 3D off when its host lacks OpenGL 4.1;
that does not validate accelerated games. The CSS frontend is not certified
against the Mac Platinum screenshot gate.
