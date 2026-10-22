# ClassicMac 4.3.0 — setup wizard release qualification

User requested the simplest first-install-to-first-boot flow and authorized
release as 4.3.0 after testing. Branch codex/4.3-setup-wizard, contained checkout
worktrees/4.3-setup-wizard, PR #33. Baseline stable/main: v4.2.0 / 262f663.
Root's untracked gxmetal work and existing machines are preserved.

The four-step wizard begins with software age/license responsibility, then
pre-installed downloads or own-CD setup, preparation and a Start Mac/Start
Installer ready screen. Native real Library download reached Finder and normal
shutdown. Own-CD creation reached the actual installer CD desktop and normal
shutdown. 130 Swift tests pass (three local optional engine/fixture skips),
15 desktop tests with the real image tool pass, browser flow checks pass.

Native Windows/Linux builds are running packaged first-run download and
own-CD qualification plus existing boot/restart/shutdown/layout checks.
Signed Mac 4.3.0 app uses unchanged verified public 4.2.0 engine code; app/DMG
notarization and final release gates are in progress. No tag/release is public.
See docs/4.3.0-validation.md and contained output/4.3.0 for evidence.

Next: finish native CI and Mac gates, merge PR #33, run consolidated integration
checks once, publish stable Latest v4.3.0 and verify every public archive.
Retain stable v4.2.0 for rollback. No catalog/hosting/infrastructure changes.
