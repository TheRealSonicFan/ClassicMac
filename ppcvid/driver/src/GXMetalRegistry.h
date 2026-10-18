/*
 * Name Registry handoff from the Power Mac VGA NDRV to the GXMetal tnsl.
 *
 * Vendored from ClassicMac 3.x gxmetal/guest/include/GXMetalRegistry.h and
 * the constants of gxmetal/protocol/gxmetal_protocol.h (protocol 1.25) that
 * this driver uses. ClassicMac 4.0 removed GXMetal: QEMU no longer exposes
 * its PCI BAR, so DriverDoDriverIO.c finds no transport and never publishes
 * the property. The probe stays in the source so the committed
 * ppcvid/qemu_vga.ndrv remains reproducible from it unchanged.
 *
 * Classic Mac OS uses one shared 32-bit logical address space, so the display
 * driver can publish the Expansion Manager's logical PCI mappings for use by
 * the RAVE engine. This record is guest-native (big-endian), not part of the
 * little-endian guest/host command wire format.
 *
 * Copyright (c) 2026 ClassicMac contributors
 * SPDX-License-Identifier: MIT
 */

#ifndef GXMETAL_REGISTRY_H
#define GXMETAL_REGISTRY_H

#include <stdint.h>

#define GXMETAL_PROTOCOL_MAGIC            UINT32_C(0x47584d54) /* "GXMT" */
#define GXMETAL_PROTOCOL_VERSION_MAJOR    1u

/* GXMetal occupied the otherwise unused end of the std-VGA BAR2 register BAR. */
#define GXMETAL_BAR2_REGISTER_OFFSET      UINT32_C(0x0b00)
#define GXMETAL_REGISTER_BYTES            UINT32_C(0x0100)

/* A separate PCI BAR was shared by the guest and renderer. */
#define GXMETAL_SHARED_BYTES              UINT32_C(0x00800000)

/* Register offsets relative to BAR2 + GXMETAL_BAR2_REGISTER_OFFSET. */
enum GXMetalRegister {
    GXMETAL_REG_MAGIC              = 0x00,
    GXMETAL_REG_VERSION            = 0x04,
    GXMETAL_REG_REGISTER_BYTES     = 0x08,
    GXMETAL_REG_SHARED_BYTES       = 0x14,
};

#define GXMETAL_REGISTRY_PROPERTY       "AAPL,GXMetal"
#define GXMETAL_REGISTRY_VERSION_MAJOR  1u
#define GXMETAL_REGISTRY_VERSION_MINOR  0u
#define GXMETAL_REGISTRY_VERSION \
    ((GXMETAL_REGISTRY_VERSION_MAJOR << 16) | \
     GXMETAL_REGISTRY_VERSION_MINOR)

typedef struct GXMetalRegistryInfo {
    uint32_t magic;
    uint32_t version;
    uint32_t registers_address;
    uint32_t registers_bytes;
    uint32_t shared_address;
    uint32_t shared_bytes;
    uint32_t framebuffer_address;
    uint32_t framebuffer_bytes;
} GXMetalRegistryInfo;

#endif /* GXMETAL_REGISTRY_H */
