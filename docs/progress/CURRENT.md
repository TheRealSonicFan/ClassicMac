# ClassicMac release and Windows — October 18, 2026

**Shipped:** [v4.0.0](https://github.com/amcchord/ClassicMac/releases/tag/v4.0.0)
is GitHub stable Latest, source `cee04d0`. Included Iconfactory artwork and
reference-backed Platinum fixes are merged. App and DMG are notarized and
stapled; a fresh public DMG passes checksum/Gatekeeper/package verification.
Final ATI and Standard Finder boots and normal shutdown pass on disposable
copies. 122 integration Swift tests pass with two fixture-dependent skips.
The catalog and user machine library were not changed.

**Fidelity:** 32 reference control states/patterns at 1×/2× and 95 printable
system glyphs pass zero-tolerance comparisons. The full app is not yet
pixel-perfect: see `docs/platinum-fidelity-audit.md` for remaining SwiftUI text,
font, menu, scrollbar and window-state coverage. The reference lab and all
source hashes are committed. No keychain unlock is needed.

**Windows:** draft PR #24 (`codex/windows-app`, build source `3b2d435`), native
CI run 39143255474 passes. The packaged app boots OS9 to Finder, pauses,
resumes, restarts/reconnects and shuts down cleanly. Unsigned prototype ZIP
and screenshots are retained in root `output/windows/2026-10-18/`. Full parity,
Windows hardware ATI/audio/game tests and signing remain; no Windows release
was published. See `docs/windows-port-validation.md`.

Next: extend native Platinum fixtures to the documented gaps, and continue
Windows feature parity/hardware qualification before Windows publication.
Preserve worktrees and the unrelated untracked root gxmetal directory.
