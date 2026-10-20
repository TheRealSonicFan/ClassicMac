/*
 * ClassicMac Display (startup extension) - the 68k INIT variant of ClassicMac
 * Display (../display.c).
 *
 * Derived from RetroBoot Display's startup extension
 * (guest/rbdisplay/init/rbdisplayinit.c, RetroBoot commit 1860881, MIT); only
 * the option names, file creator and strings differ. See ../LICENSE.
 *
 * ATI's display driver starts every Mac OS session at 640 x 480. The host
 * passes the wanted Mac screen size as an Open Firmware option, which Mac OS
 * copies into the Name Registry:
 *
 *     -prom-env classicmac-display=WIDTHxHEIGHT
 *     (RetroBoot's -prom-env retroboot-display=WIDTHxHEIGHT is read too)
 *
 * The background-only application sets that size when the Process Manager
 * starts it, after the Finder appears. This system extension does the same
 * job while the extensions load, so the Finder starts at the right size: it
 * reads the option and, when the main screen is not already that size, sets
 * the matching mode through the Display Manager exactly as the Monitors
 * control panel does, keeping the current colour depth and preferring a
 * 60 Hz timing. Then it saves the configuration (DMSaveScreenPrefs): without
 * it the Display Manager puts the ATI display back at 640 x 480 when the
 * Process Manager starts. Later startups then get the size from Mac OS itself.
 *
 * Nothing happens without the Name Registry, Display Manager 2 or the option
 * (the standard card), or when the driver does not offer that size. Every
 * call's result is checked; any failure leaves the screen and the preferences
 * as they were. Nothing stays resident.
 *
 * INIT time: no application A5 world, so QuickDraw gets temporary globals and
 * a colour port of its own (as ShowInitIcon does) while the Display Manager
 * works, and A5 is put back before returning. The extension icons drawn
 * before the switch are erased by the redraw; the next ones continue along the
 * bottom edge of the new screen (the ShowINIT position words at 0x928-0x92E
 * move with it).
 *
 * The file must not carry the Finder flag kHasNoINITs (0x0080): Mac OS sets
 * it on files it found without 'INIT' resources and then never calls them.
 *
 * Built with Retro68 (68k flat code resource, see ../build.sh). The 68k traps
 * (_NameRegistryDispatch 0xABE9, the Display Manager's 0xABEB) need no Mixed
 * Mode glue.
 */
#include <Gestalt.h>
#include <OSUtils.h>
#include <Quickdraw.h>
#include <Displays.h>
#include <Video.h>
#include <NameRegistry.h>
#include "Retro68Runtime.h"

/* ClassicMac's option first, then RetroBoot's (disks prepared for RetroBoot) */
#define kOption     "classicmac-display"
#define kOptionRB   "retroboot-display"
#define kOptionsKey "Devices:device-tree:options"
#define kHz60       (60L << 16)

/* ShowINIT's shared extension-icon position (low memory, with checksums) */
#define LMVCheckSum (*(volatile unsigned short *)0x928)
#define LMVCoord    (*(volatile short *)0x92A)
#define LMHCoord    (*(volatile short *)0x92C)
#define LMHCheckSum (*(volatile unsigned short *)0x92E)

typedef struct {
    unsigned long w, h;          /* wanted size */
    short depth;                 /* current pixel size, kept */
    unsigned long modeID;        /* best match so far */
    unsigned long depthMode;
    Fixed refresh;
    int found;
} Want;

typedef struct {
    QDGlobals qd;                /* temporary QuickDraw globals */
    long qdGlobalsPtr;           /* A5 points here */
} QDStorage;

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

/* Display Manager mode list callback (a 68k pascal routine): the wanted size
 * at the current depth, preferring 60 Hz (else the first timing listed). */
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

static int has_managers(void)
{
    long r;

    if (Gestalt(gestaltNameRegistryVersion, &r) != noErr)
        return 0;
    if (Gestalt(gestaltDisplayMgrAttr, &r) != noErr || !(r & (1L << gestaltDisplayMgrPresent)))
        return 0;
    /* display mode lists (DMNewDisplayModeList) arrived with Display Manager 2.0 */
    if (Gestalt(gestaltDisplayMgrVers, &r) != noErr || r < 0x00020000L)
        return 0;
    return 1;
}

static unsigned short icon_checksum(short x)
{
    return (unsigned short)(((x << 1) | (x >> 15)) ^ 0x1021);
}

/* The extension icons run along the bottom of the screen: keep the next one
 * the same distance from the new bottom edge. */
static void move_icon_row(short oldBottom, short newBottom)
{
    short v = LMVCoord;

    if (icon_checksum(v) != LMVCheckSum)
        return;                  /* no icon yet: the next one starts at the new bottom */
    v = (short)(v + (newBottom - oldBottom));
    LMVCoord = v;
    LMVCheckSum = icon_checksum(v);
}

static int is_size(GDHandle gd, unsigned long w, unsigned long h)
{
    return (unsigned long)((**gd).gdRect.right - (**gd).gdRect.left) == w &&
           (unsigned long)((**gd).gdRect.bottom - (**gd).gdRect.top) == h;
}

/* Find and set the mode, then save the configuration; the caller has
 * QuickDraw globals and a port. */
static void set_size(const Want *wanted)
{
    GDHandle gd;
    DisplayIDType id;
    DMListType list = NULL;
    DMListIndexType count = 0, i;
    DMDisplayModeListIteratorUPP upp;
    Handle state = NULL;
    Want want = *wanted;
    short oldBottom;
    OSErr err;

    gd = GetMainDevice();
    if (!gd || !*gd || !(**gd).gdPMap || !*(**gd).gdPMap)
        return;
    if (is_size(gd, want.w, want.h)) {
        DMSaveScreenPrefs(0, 0, 0);
        return;
    }
    oldBottom = (**gd).gdRect.bottom;
    want.depth = (**(**gd).gdPMap).pixelSize;
    if (DMGetDisplayIDByGDevice(gd, &id, false) != noErr)
        return;
    if (DMNewDisplayModeList(id, 0, 0, &count, &list) != noErr || !list)
        return;
    upp = NewDMDisplayModeListIteratorUPP(consider);
    for (i = 0; i < count; i++)
        DMGetIndexedDisplayModeFromList(list, i, 0, upp, &want);
    DisposeDMDisplayModeListIteratorUPP(upp);
    DMDisposeList(list);
    if (!want.found)
        return;
    err = DMBeginConfigureDisplays(&state);
    if (err != noErr)
        return;
    err = DMSetDisplayMode(gd, want.modeID, &want.depthMode, 0, state);
    DMEndConfigureDisplays(state);
    if (err != noErr || !is_size(gd, want.w, want.h))
        return;
    DMSaveScreenPrefs(0, 0, 0);
    move_icon_row(oldBottom, (**gd).gdRect.bottom);
}

static void run(void)
{
    Want want;
    QDStorage qds;
    CGrafPort port;
    long oldA5;

    want.found = 0;
    if (!has_managers() || !read_option(&want.w, &want.h))
        return;
    oldA5 = SetA5((long)&qds.qdGlobalsPtr);
    InitGraf(&qds.qd.thePort);
    OpenCPort(&port);
    set_size(&want);
    CloseCPort(&port);
    SetA5(oldA5);
}

void _start(void)
{
    RETRO68_RELOCATE();
    Retro68CallConstructors();
    run();
    Retro68FreeGlobals();
}
