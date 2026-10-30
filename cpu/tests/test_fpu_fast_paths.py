#!/usr/bin/env python3
"""Differential test: PowerPC FPU/AltiVec fast paths versus softfloat.

The RetroBoot fast paths (cpu/README.md) must produce exactly what QEMU's
softfloat produces. They differ by host: x86_64 builds also enable the SSE2
four-lane AltiVec code and the SSSE3 vperm (PPC_FAST_FPU_SIMD), which arm64
builds compile out, and scalar fast paths use the host's IEEE arithmetic. This
test boots a tiny bare-metal ROM on mac99 (no guest OS or Apple ROM needed)
that runs scalar FP and AltiVec instructions over generated and edge-case
operands, in every rounding mode and in both AltiVec Java modes, and records
each result together with FPSCR, VSCR and CR. The same ROM runs with
fast-fpu=off (softfloat reference), the default fast paths, and the fast paths
without the SIMD lanes; all memory images must be bit-identical.

Usage: test_fpu_fast_paths.py path/to/qemu-system-ppc path/to/pc-bios
"""
from __future__ import annotations

import math
import os
from pathlib import Path
import random
import struct
import subprocess
import sys
import tempfile
import time

ROM_BASE = 0xFFF00000
ROM_SIZE = 1024 * 1024
# mac99 maps its NVRAM over the ROM at 0xFFF04000-0xFFF05FFF; stay clear of it.
CODE_OFFSET = 0x8000
VECTORS_END = 0x4000
RESULT_BASE = 0x00100000
MARKER_ADDR = 0x0
MARKER = 0xC0FFEE42
SEED = 20261030

# --------------------------------------------------------------------------
# A minimal big-endian PowerPC encoder for the instructions used here.
# --------------------------------------------------------------------------


def d_form(op, rt, ra, d):
    return (op << 26) | (rt << 21) | (ra << 16) | (d & 0xFFFF)


def x_form(op, rt, ra, rb, xo, rc=0):
    return (op << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc


def a_form(op, frd, fra, frb, frc, xo, rc=0):
    return (op << 26) | (frd << 21) | (fra << 16) | (frb << 11) | (frc << 6) | (xo << 1) | rc


def vx(vd, va, vb, xo):
    return (4 << 26) | (vd << 21) | (va << 16) | (vb << 11) | xo


def vc(vd, va, vb, xo, rc):
    return (4 << 26) | (vd << 21) | (va << 16) | (vb << 11) | (rc << 10) | xo


def va_form(vd, va, vb, vcr, xo):
    return (4 << 26) | (vd << 21) | (va << 16) | (vb << 11) | (vcr << 6) | xo


def addi(rt, ra, si): return d_form(14, rt, ra, si)
def addis(rt, ra, si): return d_form(15, rt, ra, si)
def ori(ra, rs, ui): return d_form(24, rs, ra, ui)
def stw(rs, ra, d): return d_form(36, rs, ra, d)
def lfd(frt, ra, d): return d_form(50, frt, ra, d)
def stfd(frs, ra, d): return d_form(54, frs, ra, d)
def lvx(vd, ra, rb): return x_form(31, vd, ra, rb, 103)
def stvx(vs, ra, rb): return x_form(31, vs, ra, rb, 231)
def mtmsr(rs): return x_form(31, rs, 0, 0, 146)
def mfcr(rt): return x_form(31, rt, 0, 0, 19)
def mtcrf(crm, rs): return (31 << 26) | (rs << 21) | (crm << 12) | (144 << 1)
def isync(): return (19 << 26) | (150 << 1)
def mffs(frt): return x_form(63, frt, 0, 0, 583)
def mtfsf(fm, frb): return (63 << 26) | (fm << 17) | (frb << 11) | (711 << 1)
def mfvscr(vd): return vx(vd, 0, 0, 1540)
def mtvscr(vb): return vx(0, 0, vb, 1604)
def branch(offset): return (18 << 26) | (offset & 0x03FFFFFC)
def mfspr(rt, spr): return (31 << 26) | (rt << 21) | ((((spr & 0x1F) << 5) | (spr >> 5)) << 11) | (339 << 1)


def load_imm32(reg, value):
    return [addis(reg, 0, (value >> 16) & 0xFFFF), ori(reg, reg, value & 0xFFFF)]


# --------------------------------------------------------------------------
# Operands
# --------------------------------------------------------------------------

F32_SPECIAL = [
    0x00000000, 0x80000000, 0x3F800000, 0xBF800000, 0x00800000, 0x80800000,  # 0, 1, FLT_MIN
    0x00800001, 0x007FFFFF, 0x807FFFFF, 0x00000001, 0x00400000,              # denormals
    0x7F7FFFFF, 0xFF7FFFFF, 0x7F000000, 0x7F800000, 0xFF800000,              # max, inf
    0x7FC00000, 0xFFC00000, 0x7F800001, 0x7FA00000, 0x01000000, 0x00FFFFFF,  # NaNs, near FLT_MIN
    0x3EAAAAAB, 0x4B000000, 0x4B7FFFFF, 0x4F000000, 0xCF000000, 0x4F800000,  # 1/3, int limits
    0x5F000000, 0x3F000000, 0x3FFFFFFF, 0x34000000,
]
F64_SPECIAL = [
    0x0000000000000000, 0x8000000000000000, 0x3FF0000000000000, 0xBFF0000000000000,
    0x0010000000000000, 0x000FFFFFFFFFFFFF, 0x0000000000000001, 0x7FEFFFFFFFFFFFFF,
    0x7FF0000000000000, 0xFFF0000000000000, 0x7FF8000000000000, 0xFFF8000000000000,
    0x7FF0000000000001, 0x7FF4000000000000, 0x3FD5555555555555, 0x41DFFFFFFFC00000,
    0x41E0000000000000, 0xC1E0000000000000, 0x36A0000000000000, 0x3810000000000000,
    0x47EFFFFFE0000000, 0x47F0000000000000, 0x3FE0000000000001, 0x4330000000000000,
    0x3810000020000000, 0x380FFFFFE0000000,
]


def f32_bits(value):
    return struct.unpack(">I", struct.pack(">f", value))[0]


def f64_bits(value):
    return struct.unpack(">Q", struct.pack(">d", value))[0]


def random_f32(rng):
    roll = rng.random()
    if roll < 0.10:
        return rng.choice(F32_SPECIAL)
    if roll < 0.75:  # ordinary magnitudes: the fast paths' domain
        return f32_bits(rng.choice((-1, 1)) * rng.uniform(1e-3, 1e3) * (2.0 ** rng.randint(-20, 20)))
    if roll < 0.90:  # products/sums near the edges of the single range
        return f32_bits(rng.choice((-1, 1)) * rng.uniform(1.0, 2.0) * (2.0 ** rng.choice((-127, -126, -125, -100, 100, 126, 127))))
    return rng.getrandbits(32)  # arbitrary bit patterns


def random_f64(rng):
    roll = rng.random()
    if roll < 0.10:
        return rng.choice(F64_SPECIAL)
    if roll < 0.75:
        return f64_bits(rng.choice((-1, 1)) * rng.uniform(1e-3, 1e3) * (2.0 ** rng.randint(-60, 60)))
    if roll < 0.90:  # values whose single rounding is delicate
        exponent = rng.choice((-149, -127, -126, -125, 126, 127, 128, -1022, 1022))
        return f64_bits(rng.choice((-1, 1)) * (1.0 + rng.getrandbits(52) / 2.0 ** 52) * (2.0 ** exponent))
    return rng.getrandbits(64)


# --------------------------------------------------------------------------
# Test program
# --------------------------------------------------------------------------

VMX_BINARY = {"vaddfp": 10, "vsubfp": 74, "vmaxfp": 1034, "vminfp": 1098}
VMX_UNARY = {"vrefp": 266, "vrsqrtefp": 330, "vexptefp": 394, "vlogefp": 458,
             "vrfin": 522, "vrfiz": 586, "vrfip": 650, "vrfim": 714}
VMX_UIMM = {"vcfux": 778, "vcfsx": 842, "vctuxs": 906, "vctsxs": 970}
VMX_COMPARE = {"vcmpeqfp": 198, "vcmpgefp": 454, "vcmpgtfp": 710, "vcmpbfp": 966}
VMX_THREE = {"vmaddfp": 46, "vnmsubfp": 47, "vperm": 43}
FP_THREE = {"fmadd": (63, 29), "fmsub": (63, 28), "fnmadd": (63, 31), "fnmsub": (63, 30),
            "fmadds": (59, 29), "fmsubs": (59, 28), "fnmadds": (59, 31), "fnmsubs": (59, 30),
            "fsel": (63, 23)}
FP_BINARY = {"fadd": (63, 21), "fsub": (63, 20), "fdiv": (63, 18),
             "fadds": (59, 21), "fsubs": (59, 20), "fdivs": (59, 18)}
FP_MUL = {"fmul": (63, 25), "fmuls": (59, 25)}
FP_UNARY_A = {"fres": (59, 24), "frsqrte": (63, 26)}
FP_UNARY_X = {"frsp": 12, "fctiw": 14, "fctiwz": 15}


def mtctr(rs): return (31 << 26) | (rs << 21) | (288 << 11) | (467 << 1)
def bdnz(offset): return (16 << 26) | (16 << 21) | (offset & 0xFFFC)


class Program:
    """One CTR loop per instruction over its operand records."""

    def __init__(self):
        self.code = []
        self.data = bytearray()
        self.results = 0
        self.groups = []  # (first result offset, record size, count, name)

    def emit(self, *words):
        self.code.extend(words)

    def loop(self, name, insn, records, kind):
        if not records:
            return
        size = 48 if kind == "vmx" else 32
        self.groups.append((self.results, size, len(records), name))
        for record in records:
            self.data += record
        self.emit(*load_imm32(7, len(records)), mtctr(7))
        if kind == "vmx":
            # r3 walks the operands (a, b, c, VSCR image), r4 the results
            # (vD, VSCR, CR).
            body = [lvx(1, 0, 3), addi(3, 3, 16), lvx(2, 0, 3), addi(3, 3, 16),
                    lvx(3, 0, 3), addi(3, 3, 16), lvx(6, 0, 3), addi(3, 3, 16),
                    mtvscr(6), mtcrf(0xFF, 0), insn,
                    stvx(4, 0, 4), addi(4, 4, 16), mfvscr(5), stvx(5, 0, 4), addi(4, 4, 16),
                    mfcr(5), stw(5, 4, 0), addi(4, 4, 16)]
        else:
            # Operands (a, b, c, FPSCR image); results (frD, FPSCR, CR).
            body = [lfd(1, 3, 0), lfd(2, 3, 8), lfd(3, 3, 16), lfd(4, 3, 24), addi(3, 3, 32),
                    mtfsf(0xFF, 4), mtcrf(0xFF, 0), insn,
                    stfd(5, 4, 0), mffs(6), stfd(6, 4, 8), mfcr(5), stw(5, 4, 16), addi(4, 4, 32)]
        self.emit(*body, bdnz(-4 * len(body)))
        self.results += size * len(records)

    def describe(self, offset):
        for first, size, count, name in self.groups:
            if first <= offset < first + size * count:
                return "%s case %d" % (name, (offset - first) // size)
        return "unknown case"

    def rom(self):
        data_offset = CODE_OFFSET + 4 * (len(self.code) + 16)
        data_offset = (data_offset + 15) & ~15
        image = bytearray(ROM_SIZE)
        # Every exception vector records its offset, SRR0 and SRR1, and stops.
        for vector in range(0x200, VECTORS_END, 0x100):
            stub = [addi(9, 0, vector), stw(9, 0, MARKER_ADDR + 4), mfspr(9, 26), stw(9, 0, MARKER_ADDR + 8),
                    mfspr(9, 27), stw(9, 0, MARKER_ADDR + 12), branch(0)]
            struct.pack_into(">7I", image, vector, *stub)
        msr = 0x02003040  # VEC | FP | ME | IP
        entry = [*load_imm32(1, msr), mtmsr(1), isync(), branch(CODE_OFFSET - 0x100 - 16)]
        struct.pack_into(">%dI" % len(entry), image, 0x100, *entry)
        prologue = [addi(0, 0, 0), *load_imm32(3, ROM_BASE + data_offset), *load_imm32(4, RESULT_BASE)]
        epilogue = [*load_imm32(9, MARKER), stw(9, 0, MARKER_ADDR), branch(0)]
        words = prologue + self.code + epilogue
        require(CODE_OFFSET + 4 * len(words) <= data_offset, "code overlaps data")
        require(data_offset + len(self.data) <= ROM_SIZE,
                "test program (%d bytes of operands) larger than the ROM" % len(self.data))
        struct.pack_into(">%dI" % len(words), image, CODE_OFFSET, *words)
        image[data_offset:data_offset + len(self.data)] = self.data
        return bytes(image)


def require(condition, message):
    if not condition:
        raise SystemExit("FAIL  " + message)


def build_program():
    rng = random.Random(SEED)
    program = Program()

    def vec():
        return [random_f32(rng) for _ in range(4)]

    def ordinary_vec():
        return [f32_bits(rng.choice((-1, 1)) * rng.uniform(0.5, 4.0) * 2.0 ** rng.randint(-8, 8)) for _ in range(4)]

    def bits_vec():
        return [rng.getrandbits(32) for _ in range(4)]

    def vrecord(a, b, c, vscr):
        return struct.pack(">12I4I", *a, *b, *c, 0, 0, 0, vscr)

    # NJ=1 (non-Java, the reset value), NJ=0, and with SAT already set.
    vscrs = (0x00010000, 0x00000000, 0x00010001)
    iterations = 20

    def vmx(name, insn, operands):
        records = [vrecord(*operands(), vscr) for vscr in vscrs for _ in range(iterations)]
        program.loop(name, insn, records, "vmx")

    for name, xo in VMX_BINARY.items():
        vmx(name, vx(4, 1, 2, xo), lambda: (vec(), vec(), vec()))
        vmx(name + " (ordinary)", vx(4, 1, 2, xo), lambda: (ordinary_vec(), ordinary_vec(), vec()))
    for name, xo in VMX_UNARY.items():
        vmx(name, vx(4, 0, 2, xo), lambda: (vec(), vec(), vec()))
        vmx(name + " (ordinary)", vx(4, 0, 2, xo), lambda: (vec(), ordinary_vec(), vec()))
    for name, xo in VMX_UIMM.items():
        for uimm in (0, 1, 7, 31):
            label = "%s %d" % (name, uimm)
            vmx(label, vx(4, uimm, 2, xo), lambda: (vec(), vec(), vec()))
            vmx(label + " (bits)", vx(4, uimm, 2, xo), lambda: (vec(), bits_vec(), vec()))
            vmx(label + " (ordinary)", vx(4, uimm, 2, xo), lambda: (vec(), ordinary_vec(), vec()))
    for name, xo in VMX_COMPARE.items():
        for rc in (0, 1):
            label = name + ("." if rc else "")
            vmx(label, vc(4, 1, 2, xo, rc), lambda: (vec(), vec(), vec()))
            vmx(label + " (ordinary)", vc(4, 1, 2, xo, rc), lambda: (ordinary_vec(), ordinary_vec(), vec()))

            def same():
                a = ordinary_vec()
                return a, list(a), vec()
            vmx(label + " (equal)", vc(4, 1, 2, xo, rc), same)
    for name, xo in VMX_THREE.items():
        # vmaddfp vD,vA,vC,vB is encoded with fields vA=1, vB=2, vC=3.
        third = bits_vec if name == "vperm" else vec
        vmx(name, va_form(4, 1, 2, 3, xo), lambda: (vec(), vec(), third()))
        vmx(name + " (ordinary)", va_form(4, 1, 2, 3, xo),
            lambda: (ordinary_vec(), ordinary_vec(), bits_vec() if name == "vperm" else ordinary_vec()))

    def cancel():
        a = ordinary_vec()
        return a, list(a), vec()
    vmx("vsubfp (cancellation)", vx(4, 1, 2, VMX_BINARY["vsubfp"]), cancel)

    def negate_product():
        a = ordinary_vec()
        return a, [0] * 4, a
    vmx("vnmsubfp (zero addend)", va_form(4, 1, 2, 3, VMX_THREE["vnmsubfp"]), negate_product)

    def fp():
        return random_f64(rng)

    def ordinary_fp():
        return f64_bits(rng.choice((-1, 1)) * rng.uniform(0.5, 4.0) * 2.0 ** rng.randint(-30, 30))

    # Round to nearest/zero/+inf/-inf, all enables (VE OE UE ZE XE) with
    # nearest and with -inf, and non-IEEE mode.
    fpscrs = (0x0, 0x1, 0x2, 0x3, 0xF8, 0xFB, 0x4)
    fp_iterations = 12

    def scalar(name, insn, operands):
        records = [struct.pack(">4Q", *operands(), fpscr) for fpscr in fpscrs for _ in range(fp_iterations)]
        program.loop(name, insn, records, "fp")

    for rc in (0, 1):
        dot = "." if rc else ""
        for name, (op, xo) in FP_THREE.items():
            scalar(name + dot, a_form(op, 5, 1, 2, 3, xo, rc), lambda: (fp(), fp(), fp()))
            scalar(name + dot + " (ordinary)", a_form(op, 5, 1, 2, 3, xo, rc),
                   lambda: (ordinary_fp(), ordinary_fp(), ordinary_fp()))
        for name, (op, xo) in FP_BINARY.items():
            scalar(name + dot, a_form(op, 5, 1, 2, 0, xo, rc), lambda: (fp(), fp(), fp()))
            scalar(name + dot + " (ordinary)", a_form(op, 5, 1, 2, 0, xo, rc),
                   lambda: (ordinary_fp(), ordinary_fp(), fp()))
        for name, (op, xo) in FP_MUL.items():
            scalar(name + dot, a_form(op, 5, 1, 0, 3, xo, rc), lambda: (fp(), fp(), fp()))
            scalar(name + dot + " (ordinary)", a_form(op, 5, 1, 0, 3, xo, rc),
                   lambda: (ordinary_fp(), fp(), ordinary_fp()))
        for name, (op, xo) in FP_UNARY_A.items():
            scalar(name + dot, a_form(op, 5, 0, 2, 0, xo, rc), lambda: (fp(), fp(), fp()))
            scalar(name + dot + " (ordinary)", a_form(op, 5, 0, 2, 0, xo, rc),
                   lambda: (fp(), ordinary_fp(), fp()))
        for name, xo in FP_UNARY_X.items():
            scalar(name + dot, x_form(63, 5, 0, 2, xo, rc), lambda: (fp(), fp(), fp()))
            scalar(name + dot + " (ordinary)", x_form(63, 5, 0, 2, xo, rc),
                   lambda: (fp(), ordinary_fp(), fp()))

        def same():
            a = ordinary_fp()
            return a, a, fp()
        scalar("fsub" + dot + " (cancellation)", a_form(63, 5, 1, 2, 0, FP_BINARY["fsub"][1], rc), same)
    return program


def run(qemu, pcbios, rom, cpu, out_dir, label):
    dump = out_dir / (label + ".bin")
    monitor = out_dir / (label + ".sock")
    command = [str(qemu), "-M", "mac99", "-cpu", cpu, "-m", "64", "-L", str(pcbios),
               "-bios", str(rom), "-display", "none", "-serial", "none", "-parallel", "none",
               "-vga", "none", "-net", "none", "-monitor", "stdio"]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    try:
        time.sleep(3)
        output, _ = process.communicate(
            'pmemsave 0x%x 0x%x "%s"\nquit\n' % (MARKER_ADDR, RESULT_BASE + RESULTS_SIZE, dump), timeout=120)
    finally:
        if process.poll() is None:
            process.kill()
    require(dump.is_file(), label + ": no memory image (QEMU output: " + output.strip()[-400:] + ")")
    image = dump.read_bytes()
    marker, vector, srr0, srr1 = struct.unpack_from(">IIII", image, MARKER_ADDR)
    require(vector == 0, "%s: exception vector 0x%x taken at 0x%08x (SRR1 0x%08x)" % (label, vector, srr0, srr1))
    require(marker == MARKER, label + ": test program did not finish")
    return image[RESULT_BASE:RESULT_BASE + RESULTS_SIZE]


def first_difference(reference, candidate):
    for offset in range(0, len(reference), 16):
        if reference[offset:offset + 16] != candidate[offset:offset + 16]:
            return offset
    return None


RESULTS_SIZE = 0


def main():
    global RESULTS_SIZE
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    qemu, pcbios = Path(sys.argv[1]), Path(sys.argv[2])
    program = build_program()
    RESULTS_SIZE = program.results
    cases = sum(count for _, _, count, _ in program.groups)
    with tempfile.TemporaryDirectory(prefix="classicmac-fpu-") as folder:
        out_dir = Path(folder)
        rom = out_dir / "fpu-test.rom"
        rom.write_bytes(program.rom())
        configs = [
            ("softfloat", "7400,fast-fpu=off"),
            ("fast", "7400"),
            ("fast-no-simd", "7400,x-fast-fpu-mask=%d" % (0x7F & ~0x20)),
        ]
        images = {label: run(qemu, pcbios, rom, cpu, out_dir, label) for label, cpu in configs}
        reference = images["softfloat"]
        require(any(reference), "the test produced no results")
        for label, _ in configs[1:]:
            offset = first_difference(reference, images[label])
            if offset is not None:
                require(False, "%s differs from softfloat in %s (result offset 0x%x): %s != %s" % (
                    label, program.describe(offset), offset,
                    images[label][offset:offset + 16].hex(), reference[offset:offset + 16].hex()))
            print("    OK  %s == softfloat: %d cases in %d instruction groups, bit-identical" % (
                label, cases, len(program.groups)))


if __name__ == "__main__":
    main()
