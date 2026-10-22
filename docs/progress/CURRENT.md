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
20 desktop tests with the real image tool pass, browser flow checks pass.

Native Windows/Linux runs 39806245692 / 39806241075 pass all 20 desktop tests,
both setup routes, real download/pause/resume/first Finder boot, normal shutdown,
restart/reconnect and toolbar geometry. Both exercise unavailable-audio fallback.
Completed logs/reports are retained; GitHub's Actions/PR incident leaves some
status projections stale. All 57 packaged source/UI files match on each host;
Linux DEB/TAR application archives match. Mac signing/notarization/staples,
Gatekeeper, exact package checks and final Finder boot pass. Nine archives
and SHA256SUMS are staged. No tag/release is public.

Next: merge PR #33, consolidated root checks once, publish stable Latest v4.3.0
and verify fresh anonymous downloads. See docs/4.3.0-validation.md.
Retain stable v4.2.0 for rollback. No catalog/hosting/infrastructure changes.
