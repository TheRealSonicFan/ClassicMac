# ClassicMac 4.4.0 — ready for integration and publication

Branch `codex/4.4-retire-gxmetal` retires remaining GXMetal app metadata,
dormant NDRV transport, obsolete guides/screenshots and the clean OS9 image.
Qualified immutable ATI image v4 is published with a checked catalog rollback
backup. Existing user machines and historical archives are preserved.

All 131 Swift tests (three local optional fixture/engine skips), all 21 desktop
tests with real qemu-img, NDRV mode/gamma and image preparation checks pass.
Final signed/notarized/stapled Mac app/DMG verification, actual public native
wizard import/Finder/normal shutdown and HFS+ clean flag pass. Native Windows
39814128066 and Linux 39813549507 pass both setup routes and existing package
checks at 92b977d. All 57 source/UI assets and current NDRV match each package;
prepared sources match. See docs/4.4.0-validation.md and docs/evidence/4.4.0/.

Next: integrate PR #34 to main, run consolidated root checks, publish stable
Latest v4.4.0 and verify fresh anonymous downloads. Keep 4.3.0 for rollback.
No public 4.4 tag/release yet. User local build artifacts are preserved.
