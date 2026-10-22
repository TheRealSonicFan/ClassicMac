# ClassicMac 4.4.0 — qualification in progress

Branch `codex/4.4-retire-gxmetal` in `worktrees/4.4-retire-gxmetal` retires the
remaining GXMetal app metadata, dormant NDRV transport, current guides and clean
OS9 image. New clean ATI image is published; all existing user machines and
immutable archives remain unchanged. Catalog backup and exact image checks are
in `docs/evidence/4.4.0/`. Mac app/DMG notarization and release verification pass.

Next: native Windows/Linux packaged qualification, final signed Mac boot,
merge and consolidated root validation, then stable Latest 4.4.0 publication
and fresh anonymous download checks. Retain 4.3.0 for rollback. User local
GXMetal build artifacts and unrelated worktrees are preserved.
