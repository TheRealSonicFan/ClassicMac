# Platinum appearance

ClassicMac draws its own interface in the Mac OS 8/9 "Platinum" appearance,
shared with RetroBoot so the two products look and behave alike. Everything in
this directory is original and MIT licensed; nothing is copied from Apple
software.

- `fonts/` — RetroBoot System 12, Regular 12 and Small 10 bitmap fonts:
  original pixel art "in the spirit of" the classic system fonts (see
  `LICENSE-fonts.txt`). Source: RetroBoot `presenter/ui/assets/fonts`
  at `531f953` (2026-10-11).
- `icons/` — the matching icon set and palette (see `LICENSE-icons.txt`),
  from RetroBoot `presenter/ui/assets/icons` at the same revision.
- `tools/build_platinum_swift.py` — compiles the bitmap fonts to pixel-square
  TrueType (64 units per pixel; Regular and Small also get QuickDraw-style
  synthetic bold) and embeds fonts and icons in
  `app/Sources/PlatinumKit/Generated/PlatinumAssets.swift`. Standard library
  only. Run it after changing anything here.

The control drawing tables in `app/Sources/PlatinumKit/Core/Chrome.swift`
(window frame, pinstripes, push button and default ring, checkboxes, radio
buttons, group box, fields, lists, scroll bar) were measured pixel by pixel
from Mac OS 8.1 in the author's M5Tab-Macintosh project and ported through
RetroBoot's rbui (`presenter/ui/src/platinum.c`, MIT). The pop-up button,
progress bar, focus ring, menus, title-bar boxes and grow box are original
drawings in the same palette.

One Mac pixel is one point. On Retina displays that is exactly two device
pixels, so the interface is never resampled.
