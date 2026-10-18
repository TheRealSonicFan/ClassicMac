# ClassicMac 4.1.0 shipped

Stable GitHub Latest: https://github.com/amcchord/ClassicMac/releases/tag/v4.1.0
Source/tag `a6922db84952d8ec5522b469d264bc297db7e1cf`, integrated through PR #24.
Mac DMG/ZIP, Windows x64 ZIP and Linux x64 DEB/tar.gz are public, with matching
QEMU/Copland sources and checksums. Fresh public downloads match every hash;
the public Mac DMG passes notary/staple/Gatekeeper/package verification.

Integration: 122 Swift tests, two Copland fixture skips, zero failures; all
12 desktop tests pass. Native Windows/Linux packaged CI passes. Exact CI ZIP
and DEB also pass OS9 Finder/pause/clean-restart/reconnect/native accented
input/normal shutdown on the dedicated Proxmox hosts. Linux 9p host-read and
guest-write passes. Both hosts also pass real Library interrupted/resumed
import and Quadra MacOS8.1 CD boot/shutdown. Screenshots are refreshed.

Evidence: docs/4.1.0-validation.md, docs/desktop-release-validation.md,
docs/evidence/4.1.0 and docs/screenshots/desktop. Windows is unsigned;
Copland is Mac-only; Windows 9p sharing is unavailable. Physical GPU/audio,
Internet browsing and a game suite remain unqualified on the virtual hosts.
The Platinum pixel gate covers its documented Mac controls/fonts, not the
whole interface or CSS desktop.

Dedicated SazProx QA VMs 170/171 are retained for future work. Windows auto-login
and its registry password were removed after testing; host shutdown requested.
No unrelated VM/template, user machine or root gxmetal files were changed.
Prior releases/assets remain available; Library catalog unchanged.

Next: hardware GPU/audio/game qualification and remaining Platinum UI states
when that follow-up work is requested. No release action remains pending.
