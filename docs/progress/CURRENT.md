# ClassicMac 4.3.0 — stable release complete

[Stable Latest v4.3.0](https://github.com/amcchord/ClassicMac/releases/tag/v4.3.0),
published October 22, 2026. Exact source/tag:
`7467ddd02d03cc66360273de252b9db123124cfa` (PR #33 integrated through Git).
All ten assets are public. Fresh anonymous downloads of all nine archives
match SHA256SUMS; the public Mac DMG passes full release verification,
Gatekeeper and staple validation.

A four-step first-run wizard covers software age/license responsibility,
pre-installed download or own-CD setup, preparation and first startup.
Existing libraries open directly. Newer editions keep ATI defaults. Windows
uses supported disk-creation options. Unavailable Windows/Linux audio falls
back for the session with a status message, preserving saved preferences.

Consolidated root validation: 130 Swift tests, two optional Copland fixture
skips, zero failures; all 20 desktop tests pass with the real image tool.
Native Windows 39806245692 and Linux 39806241075 pass both packaged setup
routes, real download/pause/resume/hash/install/first Finder boot, restart,
normal shutdown and toolbar checks. All 57 packaged source/UI files match;
Linux DEB/TAR application archives match. Mac app/DMG signatures, accepted
notarization/staples, final Finder boot and exact package checks pass.
See docs/4.3.0-validation.md for scope, sources and the GitHub status incident.

No release action remains. Task guests stopped normally. Existing notary
keychain credentials were used; no temporary private key was created.
User gxmetal work, machines and unrelated worktrees are preserved. No catalog,
hosting, DNS or Proxmox changes. Task checkout/output are retained under
worktrees/4.3-setup-wizard for support.

Rollback: `gh release edit v4.2.0 --latest`, then record the reason in 4.3 notes.
Windows remains unsigned; Copland is Mac-only. Physical Windows/Linux audio/GPU
and a full guest OS installation are outside this setup qualification.
