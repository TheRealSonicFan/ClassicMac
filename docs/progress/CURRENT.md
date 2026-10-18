# ClassicMac 4.0 Preview 3 — published as a GitHub pre-release

**Objective:** ClassicMac 4.0: RetroBoot's emulated ATI Radeon instead of
GXMetal, the Mac OS Library, and an Apple Platinum interface shared with
RetroBoot (Mac now; iPad, PC and Linux later).

**Where it is:** branch `claude/4.0` in `worktrees/4.0-engine` (integration
of `claude/4.0-engine`, `claude/4.0-platinum`, `claude/4.0-display`,
`claude/4.0-via-timers` and the Cuda/IDE startup-race fixes), merged into
`main` on GitHub at the user's request (October 18). No GitHub release; the
public 3.2.1 release and catalog are unchanged.

**Preview 3:** published October 18 as GitHub pre-release
[v4.0.0-preview.3](https://github.com/amcchord/ClassicMac/releases/tag/v4.0.0-preview.3)
(tag on `6dab4a6`; app built from `46ca338`, which differs only in docs).
Notarized (app `4926df73-ed34-4e3f-b790-2228ff763515`, DMG
`72576009-ce31-4f5d-b5a6-38710bcb6ab0`, both Accepted), stapled,
`verify-release.sh` passed. DMG SHA-256
`9fee51fda7fad28185f80ade6a5c077deb75d19ec80565daad1b5649434d8b01`; ZIP
`3552de30…`; Copland source `43400b87…`. A fresh download matched its
checksum, validated its staple and passed Gatekeeper. v3.2.1 remains the
latest (stable) release; the download catalog is unchanged.

**Test build:** `worktrees/4.0-engine/output/dist-4.0-p2/ClassicMac-4.0.0-Preview-2.dmg`
(version 4.0.0, bundle id `com.classicmac.emulator`), Developer ID signed,
notarized (app `c39a82ca-05c9-4ff9-acb0-c087bd999fe6`, DMG
`c50c13be-3f33-4263-951a-d4df98ae6efe`, both Accepted), stapled;
`verify-release.sh` passed. DMG SHA-256
`80eabae01b8da4ef6b92dded21d392ea521739c02532ff747f2436bd77e14073`.
Preview 1 (`afb6b04a…`) remains in `output/dist-4.0/`.

**Preview 2 adds** the Platinum guest window (`-display classicmac`, toolbar,
startup curtain, input) after the user found QEMU's black Cocoa window and
OpenBIOS yellow unacceptable.

**Verified:** Preview 2 notarized app boots Deluxe v6 (ATI) to a 1024×768
Finder in its Platinum window and shuts down cleanly; 9.2.1 (Standard)
reaches a 1024×768 Finder after Mac OS's 640×480 restore is re-asserted;
display backend gates and guest tests (60 fps delivery) in
`worktrees/4.0-display/output/4.0-display/`. Earlier: 117 Swift tests; every `build-qemu.sh` gate including host GL;
Deluxe v6 boots on the ATI card to a 1024×768 Finder with 3D on the Apple
M5 Max (headless harness and from the bundled app with the Cocoa window);
Quake III demo 153–156 fps; Mac OS 9.2.1 on the Standard card; screenshots
of every Platinum window from the bundled app in a scratch home.

**Not verified:** typing, clicking and mouse capture by a person in the new
guest window (tested by injected protocol messages only); full screen;
a person using the app interactively (menus, pop-ups,
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
