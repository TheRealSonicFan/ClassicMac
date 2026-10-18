# ClassicMac for Windows

The Windows desktop front end uses the same `.classic` machine folders,
bundled Iconfactory artwork, Platinum bitmap fonts, custom QEMU devices,
PowerPC timing fixes, firmware and noVNC display client as the Mac app.
It runs QEMU as a child process and controls it over a private stdin/stdout
QMP channel. VNC is password protected and listens only on loopback.

This is the initial Windows implementation, separate from the macOS 4.0
stable release. Power Mac G4 and Quadra 800 are supported by the code.
Copland, integrated catalog downloads, host text paste and host folder
sharing remain to be ported. The Library button explains the current import
path. Settings changes require a stopped machine. Guest audio uses
DirectSound; the ATI backend creates a WGL OpenGL 4.1 context on the renderer
thread, with 3D off if the host driver cannot supply it. Full Windows guest
boot/input/audio/game qualification is still required before a Windows release.

## Run from source

Install Node.js, MSYS2 UCRT64 and the packages listed in
`.github/workflows/windows.yml`. From the project root in UCRT64:

```sh
desktop/scripts/build-engine.sh
```

Place the qualified `ClassicMacTools.iso` at
`output/desktop/runtime/ClassicMacTools.iso` (the workflow obtains it from
the pinned, checksum-verified Preview 3 ZIP). The QEMU build writes the rest
of this runtime directory, including firmware, ROM and notices.

```sh
cd desktop
npm ci
npm test
npm start
npm run package:win
```

Set `CLASSICMAC_RUNTIME` to the absolute `output/desktop/runtime` path for a
development launch. A packaged app finds `resources/runtime` automatically.
Unzip the resulting distribution and run `ClassicMac.exe`; keep the files
beside it. This initial build is unsigned. Do not publish it as a qualified
Windows release until actual Windows guest tests and signing are complete.

**Open Mac…** opens an existing `.classic` folder. Copy a machine after
shutting it down on the Mac; Windows uses its disk in place. **New Mac…**
creates a sparse raw disk. Choose your installation CD with **Media…** and
start the Mac. Missing Mac-specific CD paths must be ejected or replaced in
Get Info before startup. Existing machines are never automatically converted.

Use **Shut Down** in the guest or toolbar before quitting. A nonresponsive
Mac stays running until **Force Off** is explicitly confirmed. Unsaved work
can be lost with Force Off.

## Development verification

`npm test` checks launch profiles, installer safeguards, comma escaping,
loopback/authenticated displays, settings bounds, explicit feature limits
and prevention of package-path/symlink escapes. The Windows workflow builds
both engines natively, probes devices/ATI realization, packages the desktop
app, and retains runtime, matching QEMU source and ZIP artifacts.

For a macOS development smoke test only, `CLASSICMAC_MAC_APP` can point to a
qualified Mac app and `CLASSICMAC_RUNTIME` to its `Contents/Resources`.
This exercises the same JavaScript launch/QMP/noVNC stack with native Mac
engines; it does not qualify the Windows engines or WGL backend.

The renderer uses a sandbox and context isolation, and all IPC handlers
validate the sender against the single local application window, following
[Electron’s security guidance](https://www.electronjs.org/docs/latest/tutorial/security/).
No remote website receives filesystem or process APIs.
