/*
 * ClassicMac Display - puts Mac OS's screen at the size ClassicMac chose for
 * the emulated ATI Radeon R100.
 *
 * Derived from RetroBoot Display (guest/rbdisplay/rbdisplay.c, RetroBoot
 * commit 1860881, MIT); only the option names, file creator and strings
 * differ. See LICENSE.
 *
 * ATI's own display driver ("ATI Driver Update") offers a fixed list of modes
 * plus the monitor's EDID timing and, because the emulated mac99 NVRAM is not
 * kept, starts every session in its default 640 x 480. The host passes the
 * wanted size as an Open Firmware option, which Mac OS copies into the Name
 * Registry:
 *
 *     -prom-env classicmac-display=WIDTHxHEIGHT
 *     (RetroBoot's -prom-env retroboot-display=WIDTHxHEIGHT is read too)
 *
 * This background-only application lives in the Extensions folder, so the
 * Process Manager starts it at the end of startup, before the Finder. It
 * reads the option and, when the main screen is not already that size, sets
 * the matching mode through the Display Manager exactly as the Monitors
 * control panel does (DMBeginConfigureDisplays / DMSetDisplayMode /
 * DMEndConfigureDisplays), keeping the current colour depth and preferring a
 * 60 Hz timing. Then it quits.
 *
 * Nothing happens without the option (the standard card), when the size is
 * already right, or when the driver does not offer that size. A size chosen
 * later in Monitors (or by a game) lasts until Mac OS restarts.
 *
 * Built with Retro68 (PowerPC CFM).
 */
#include <Quickdraw.h>
#include <Displays.h>
#include <Video.h>
#include <NameRegistry.h>
#include <Events.h>

/* ClassicMac's option first, then RetroBoot's (disks prepared for RetroBoot) */
#define kOption     "classicmac-display"
#define kOptionRB   "retroboot-display"
#define kOptionsKey "Devices:device-tree:options"
#define kMaxModes   64
#define kHz60       (60L << 16)

typedef struct {
    unsigned long w, h;          /* wanted size */
    short depth;                 /* current pixel size, kept */
    unsigned long modeID;        /* best match so far (0: none) */
    unsigned long depthMode;
    Fixed refresh;
    int found;
} Want;

static int parse_size(const char *s, unsigned long *w, unsigned long *h)
{
    unsigned long v[2] = {0, 0};
    int i = 0, digits = 0;

    for (; *s; s++) {
        if (*s >= '0' && *s <= '9') {
            v[i] = v[i] * 10 + (unsigned long)(*s - '0');
            if (++digits > 5)
                return 0;
        } else if ((*s == 'x' || *s == 'X') && i == 0 && digits) {
            i = 1;
            digits = 0;
        } else {
            return 0;
        }
    }
    if (i != 1 || !digits || v[0] < 512 || v[1] < 384 || v[0] > 4096 || v[1] > 4096)
        return 0;
    *w = v[0];
    *h = v[1];
    return 1;
}

static int read_named(RegEntryID *options, const char *name,
                      unsigned long *w, unsigned long *h)
{
    char text[32];
    RegPropertyValueSize size = sizeof text - 1;

    if (RegistryPropertyGet(options, name, text, &size) != noErr || size == 0)
        return 0;
    text[size < sizeof text ? size : sizeof text - 1] = 0;
    /* Open Firmware strings may carry their terminating NUL inside the value */
    return parse_size(text, w, h);
}

static int read_option(unsigned long *w, unsigned long *h)
{
    RegEntryID options;
    int ok;

    RegistryEntryIDInit(&options);
    if (RegistryCStrEntryLookup(NULL, kOptionsKey, &options) != noErr)
        return 0;
    ok = read_named(&options, kOption, w, h) ||
         read_named(&options, kOptionRB, w, h);
    RegistryEntryIDDispose(&options);
    return ok;
}

/* Display Manager mode list callback: the wanted size at the current depth,
 * preferring 60 Hz (else the first timing listed). */
static pascal void consider(void *userData, DMListIndexType idx, DMDisplayModeListEntryPtr e)
{
    Want *want = (Want *)userData;
    VDResolutionInfoPtr r;
    unsigned long k;

    (void)idx;
    if (!e || !(r = e->displayModeResolutionInfo) || !e->displayModeDepthBlockInfo)
        return;
    if ((unsigned long)r->csHorizontalPixels != want->w || (unsigned long)r->csVerticalLines != want->h)
        return;
    if (want->found && want->refresh == kHz60)
        return;
    for (k = 0; k < e->displayModeDepthBlockInfo->depthBlockCount; k++) {
        DMDepthInfoPtr d = &e->displayModeDepthBlockInfo->depthVPBlock[k];
        if (!d->depthSwitchInfo || !d->depthVPBlock || d->depthVPBlock->vpPixelSize != want->depth)
            continue;
        if (!want->found || r->csRefreshRate == kHz60) {
            want->modeID = r->csDisplayModeID;
            want->depthMode = d->depthSwitchInfo->csMode;
            want->refresh = r->csRefreshRate;
            want->found = 1;
        }
        return;
    }
}

int main(void)
{
    GDHandle gd;
    DisplayIDType id;
    DMListType list = NULL;
    DMListIndexType count = 0, i;
    DMDisplayModeListIteratorUPP upp;
    Handle state = NULL;
    Want want;
    OSErr err;

    InitGraf(&qd.thePort);       /* QuickDraw globals for GetMainDevice and the DM */
    want.found = 0;
    if (!read_option(&want.w, &want.h))
        return 0;
    gd = GetMainDevice();
    if (!gd)
        return 0;
    if ((unsigned long)((**gd).gdRect.right - (**gd).gdRect.left) == want.w &&
        (unsigned long)((**gd).gdRect.bottom - (**gd).gdRect.top) == want.h)
        return 0;
    want.depth = (**(**gd).gdPMap).pixelSize;
    if (DMGetDisplayIDByGDevice(gd, &id, false) != noErr)
        return 0;
    if (DMNewDisplayModeList(id, 0, 0, &count, &list) != noErr)
        return 0;
    upp = NewDMDisplayModeListIteratorUPP(consider);
    for (i = 0; i < count; i++)
        DMGetIndexedDisplayModeFromList(list, i, 0, upp, &want);
    DisposeDMDisplayModeListIteratorUPP(upp);
    DMDisposeList(list);
    if (!want.found)
        return 0;
    err = DMBeginConfigureDisplays(&state);
    if (err == noErr)
        DMSetDisplayMode(gd, want.modeID, &want.depthMode, 0, state);
    if (state)
        DMEndConfigureDisplays(state);
    return 0;
}
