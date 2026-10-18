/* ClassicMac Display (startup extension) resources (Retro68 Rez).
 * The INIT is a flat 68k code resource ($$read of the linker's .flt output). */
#include "Retro68.r"
#include "MacTypes.r"

type 'INIT' {
    RETRO68_CODE_TYPE
};

resource 'INIT' (128, locked) {
    dontBreakAtEntry, $$read("ClassicMacDisplayInit.flt");
};

resource 'vers' (1) {
    0x01, 0x00, release, 0x00, verUS,
    "1.0",
    "1.0, ClassicMac: Mac OS screen size for the ATI Radeon, set at startup"
};
