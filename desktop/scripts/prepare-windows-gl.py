#!/usr/bin/env python3
"""Apply the Windows-only host GL overlay after the shared QEMU patches."""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
qemu = Path(sys.argv[1])
source = qemu / "hw/display/ati_gl.c"
text = source.read_text()
if '#include "ati_gl_windows.inc"' not in text:
    text = text.replace('#include <dlfcn.h>', '#ifndef _WIN32\n#include <dlfcn.h>\n#endif', 1)
    text = text.replace('#ifdef __APPLE__', '#if defined(_WIN32)\n#include "ati_gl_windows.inc"\n#elif defined(__APPLE__)', 1)
    source.write_text(text)
header = qemu / "hw/display/ati_gl.h"
header.write_text(header.read_text().replace('#ifdef __APPLE__', '#if defined(__APPLE__) || defined(_WIN32)'))
shutil.copyfile(root / "ati_gl_windows.inc", qemu / "hw/display/ati_gl_windows.inc")
