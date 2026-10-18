# ClassicMac 4.0 Preview 1 — local test build

**Objective:** ClassicMac 4.0: RetroBoot's emulated ATI Radeon instead of
GXMetal, the Mac OS Library, and an Apple Platinum interface shared with
RetroBoot (Mac now; iPad, PC and Linux later).

**Where it is:** branch `claude/4.0` in `worktrees/4.0-engine` (integration
of `claude/4.0-engine` and `claude/4.0-platinum`). Not pushed, no PR, nothing
published, catalog unchanged. `main` is still 3.2.1 (`3e24594`).

**Test build:** `worktrees/4.0-engine/output/dist-4.0/ClassicMac-4.0.0-Preview-1.dmg`
(version 4.0.0, bundle id `com.classicmac.emulator`), Developer ID signed,
notarized (app `31625b34-2387-4a92-8f90-2480a84c98bb`, DMG
`b208a142-ce21-4068-afbd-a817b464f99b`, both Accepted), stapled;
`verify-release.sh` passed. DMG SHA-256
`afb6b04a84b6be08a891236736f50911b519d96b8a96f6c5c168acb98f6ef4a0`.

**Verified:** 117 Swift tests; every `build-qemu.sh` gate including host GL;
Deluxe v6 boots on the ATI card to a 1024×768 Finder with 3D on the Apple
M5 Max (headless harness and from the bundled app with the Cocoa window);
Quake III demo 153–156 fps; Mac OS 9.2.1 on the Standard card; screenshots
of every Platinum window from the bundled app in a scratch home.

**Not verified:** a person using the app interactively (menus, pop-ups,
drag/resize, WindowShade by hand); long soaks; sound/networking on the ATI
card; Intel or GPU-less Macs; macOS 15; the user's own library (untouched).

**Risks / decisions to confirm:**
- Faster-CPU commit omits RetroBoot's VIA timer-2 hold; a very slow or loaded
  Mac could hang early in an ATI start. Switch: `-cpu 7400,fast-branch=off`.
- `PlatinumKit`'s 8.1 control tables come from the private RetroBoot/M5Tab
  work under MIT; confirm before publishing in the public repository.
- Iconfactory icons are personal-use only: ClassicMac only reads the user's
  own copy and never ships or screenshots them.
- Apple's OpenGL is deprecated; without it the ATI card runs with 3D off.

**Next safe action:** the user tests the Preview DMG; then decide on the
CPU commit and publication, push `claude/4.0`, open a PR, and qualify a 4.0
release.
