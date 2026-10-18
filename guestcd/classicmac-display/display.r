/* ClassicMac Display resources (Retro68 Rez).  'cfrg' comes from RetroPPCAPPL.r. */
#include "Processes.r"
#include "MacTypes.r"

resource 'vers' (1) {
    0x01, 0x00, release, 0x00, verUS,
    "1.0",
    "1.0, ClassicMac: Mac OS screen size for the ATI Radeon"
};

/* background only: started by the Process Manager from the Extensions folder */
resource 'SIZE' (-1) {
    reserved,
    ignoreSuspendResumeEvents,
    reserved,
    canBackground,
    doesActivateOnFGSwitch,
    onlyBackground,
    dontGetFrontClicks,
    ignoreChildDiedEvents,
    is32BitCompatible,
    notHighLevelEventAware,
    onlyLocalHLEvents,
    notStationeryAware,
    dontUseTextEditServices,
    reserved,
    reserved,
    reserved,
    256 * 1024,
    128 * 1024
};
