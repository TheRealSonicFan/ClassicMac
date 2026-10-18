# ClassicMac 4.0.0 release, fidelity audit and Windows

The user authorized the included Iconfactory artwork, stable publication and
Windows work on October 18, then requested a pixel-accuracy audit.

Artwork/release PR #23 merged as 7960abd. Both ATI Deluxe and Standard OS9
Finder boots pass on disposable copies. Existing API release credentials work;
no keychain unlock is needed. Stable publication is still pending the final
UI build and notarization. The catalog and user machines are unchanged.

`worktrees/platinum-pixel-audit` corrects reference-backed control/font errors
and adds 32 control/pattern fixtures at 1×/2× plus 95 system glyphs. Full-app
pixel perfection is not claimed; remaining gaps are in
`docs/platinum-fidelity-audit.md`. Next: merge the audit, rebuild/sign/notarize
4.0.0, publish stable Latest, verify fresh public artifacts.

Windows draft PR #24 has a native QEMU/Electron package and isolated smoke
workflow. The first Windows boot exposed a missing VNC DES backend; the
explicit libgcrypt build is running. Preserve all worktrees and root gxmetal.
