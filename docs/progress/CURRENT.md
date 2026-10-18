# ClassicMac 4.0.0 stable release and Windows port

The user authorized bundling Iconfactory icons (separate permission confirmed),
publishing a real stable release, then work on Windows on October 18, 2026.

Stable release worktree: `worktrees/4.0-stable-release`, branch
`codex/4.0-stable-release`, baseline main `8bf3632`. Artwork is bundled and
default, attribution retained; imported collections can override it. Signed
app is in `output/4.0.0/dist`. 118 Swift tests (three fixture skips), packaged
release/device/display gates and ATI Finder boot pass. Notarization is pending:
`classicmac-notary` is unavailable from the current login keychain. User has
been asked to unlock it or identify the correct profile. No stable release
published yet; Preview 3 and v3.2.1 remain available. Catalog unchanged.

Next: finish Standard-card UI smoke, notarize app/DMG, commit/push/merge release
source, publish v4.0.0 as stable Latest, verify a fresh public download. Windows
will use a separate contained worktree; preserve all existing worktrees and
untracked root gxmetal artifacts.
