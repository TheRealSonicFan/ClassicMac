# ClassicMac 4.1.0 cross-platform release — in progress

User authorized AustinLand/Proxmox feature parity tests, a Linux edition,
updated repository screenshots and a new combined release on October 18.
Working checkout: `worktrees/windows-app`, branch `codex/windows-app`, PR #24.
Root remains the integration checkout; preserve its untracked gxmetal files.

The common Windows/Linux Electron frontend is now under `desktop/`.
Linux native QEMU build completed; its first gate incorrectly required the
Mac's desktop OpenGL 4 signature instead of Linux EGL/GLES 3. The gate is
being corrected without changing the renderer requirement. Native CI runs
39155483260 (Linux failed at that gate) and 39155483053 (Windows building).
Library/resume/SHA256/safe extraction, MacRoman paste and Linux 9p sharing
have been implemented locally; 12 focused tests pass. Not yet release-qualified.

Dedicated Proxmox hosts: Linux VM 170 (`classicmac-linux41-test`, SazProx,
Debian 13) is running at 192.168.101.96. Windows VM 171
(`classicmac-win41-test`, SazProx, Windows 11) was started despite AustinLand
returning a task-warning 500; its post-clone setup was completed separately
through AustinLand's guest-agent helper. Interactive desktop/SSH setup runs.
Credentials stay in root output/4.1.0/private with protected permissions.
No other VM or template was changed. No new release published yet.

Next: finish native builds, run the packaged feature matrix on these two VMs,
fix measured failures, refresh screenshots, then integrate and publish 4.1.0
with an explicit platform feature/support matrix and matching sources.
