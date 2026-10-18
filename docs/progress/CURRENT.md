# ClassicMac 4.1.0 — final release qualification

User authorized AustinLand/Proxmox feature parity tests, Linux, refreshed
GitHub screenshots and a combined stable release. Work is contained in
`worktrees/windows-app`, branch `codex/windows-app`, PR #24. Root integration
checkout remains main; its unrelated untracked gxmetal directory is untouched.

Dedicated SazProx VMs 170 (Debian 13) and 171 (Windows 11) pass final OS9
Finder/pause/clean-restart/reconnect/native MacRoman input/shutdown tests.
Both pass real Library pause/resume/hash/import and Quadra OS8.1 CD boot.
Linux passes an actual host-read/guest-write 9p round trip. Reports/screenshots
are in docs/evidence/4.1.0 and docs/screenshots/desktop. Native GPU/audio/game
qualification remains outside the measured VM scope. Windows is unsigned;
Copland is Mac-only and Windows 9p sharing is unavailable.

Mac 4.1 app/DMG are signed, notarized, stapled and pass release verification,
ATI realization and native display reconnect gates. Native app code is
unchanged from integrated 4.0. Strict packaged CI waits for Finder menu titles;
Windows run 39158984879 and Linux run 39158930105 are finishing. Twelve Node
tests pass. Consolidated integration tests/publication have not happened yet.

Next: finish CI, integrate PR #24, run consolidated checks, publish stable
v4.1.0 with all platform downloads and sources, verify public assets, remove
test auto-login and stop the dedicated VMs. Keep prior releases for rollback.
