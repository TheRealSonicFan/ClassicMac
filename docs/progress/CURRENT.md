# ClassicMac 4.4.0 — stable release complete

[Stable Latest v4.4.0](https://github.com/amcchord/ClassicMac/releases/tag/v4.4.0),
published October 22, 2026. Exact source/tag:
`15240410d2164a69f6af35765cf27ff102ae318d` (PR #34).
All ten assets are public; all nine fresh anonymous archive downloads match
SHA256SUMS. The public Mac DMG passes full verification, Gatekeeper and staples.

GXMetal app metadata, dormant NDRV transport, obsolete guides and five old
screenshots are retired. Clean OS9 image v4 uses native Apple/ATI software
on the emulated Radeon, with zero retired files/raw byte strings. Current
Deluxe/SuperDeluxe have no retired files. Existing user machines are unchanged;
immutable historical archives remain available. The original catalog backup
is retained for rollback. The initial v3 candidate was withdrawn before release.

Consolidated root checks pass 131 Swift tests (two optional Copland fixture
skips), all 21 desktop tests, 15 Python checks and both NDRV contracts. Final
notarized Mac native download/import/Finder/clean shutdown passes. Native
Windows 39814128066 and Linux 39813549507 pass both setup routes, real public
v4 download/pause/resume/hash/import/first ATI Finder boot/normal shutdown and
standard-card restart/display/toolbar checks. All 57 source/UI assets and NDRV
match each package; prepared sources match. See docs/4.4.0-validation.md.

No release action remains. Task guests stopped and mounts detached; local
user build artifacts, machines and unrelated worktrees are preserved. Task
worktree/output are retained for support. No temporary notary key was created.
Catalog/image publication was atomic; no DNS, hosting config or service restart.

Rollback: promote v4.3.0 with `gh release edit v4.3.0 --latest`; restore the
checked pre-4.4 catalog backup if downloads need rollback, and record the reason.
Windows remains unsigned and Copland remains Mac-only. Physical Windows/Linux
GPU/audio qualification remains outside hosted-runner coverage.
