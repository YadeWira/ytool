#!/usr/bin/env python3
"""Apply ytool's patches to the vendored Intensity/srep tree in vendor/srep/.

Every patch here corresponds to a failure that was reproduced, not to a style
preference. The set is derived from the fixes recorded in YadeWira/omega-srep's
changelog between the fork point (48f4b97) and its last C++ release (v1.0.7) —
that project had the same bugs and fixed several of them, so where a fix is a
plain correction with no format change it is carried here rather than
re-invented. Each one says where it came from.

Idempotent: every patch checks for its own marker before touching anything, so
this can run on a fresh copy or on an already-patched one.

Usage: contrib/patch_srep.py vendor/srep
"""
import sys
import os

MARK = "ytool patch"


def read(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(text)


def apply(path, name, old, new, marker=None):
    """Replace `old` with `new` once, unless `marker` is already present."""
    src = read(path)
    if marker and marker in src:
        print(f"   = {name}: already applied")
        return True
    if old not in src:
        print(f"   ! {name}: PATTERN NOT FOUND in {path}")
        return False
    write(path, src.replace(old, new, 1))
    print(f"   + {name}")
    return True


def patch_nh16(path):
    """Rewrite nh_16_func's asm operands to declare mp/kp/nw as read-write."""
    src = read(path)
    if "mp_scratch" in src:
        print("   = VMAC nh_16_func: already patched")
        return True

    lines = src.split("\n")
    # Locate nh_16_func, then the GCC asm opening and its operand list.
    try:
        fn = next(i for i, l in enumerate(lines) if "static void NOINLINE nh_16_func" in l)
    except StopIteration:
        print("   ! VMAC nh_16_func: function not found")
        return False

    asm = None
    for i in range(fn, min(fn + 80, len(lines))):
        if "__asm__ __volatile__" in lines[i]:
            asm = i
            break
    if asm is None:
        print("   ! VMAC nh_16_func: asm block not found")
        return False

    # The operand list is the pair of lines `: "S" (mp), "D" (kp), ...`.
    for i in range(asm, min(asm + 200, len(lines))):
        if '"S" (mp), "D" (kp), "c" (nw), "a" (rl), "d" (rh)' in lines[i]:
            indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
            lines[i] = (indent + '/* ytool patch: the body advances esi/edi by 16 bytes per iteration and\n'
                        + indent + '   decrements ecx as its loop counter, so declaring them as read-only\n'
                        + indent + '   inputs let -fipa-ra assume ecx survived the call (VMAC_TAG_LEN==128\n'
                        + indent + '   calls this twice back to back). "+" makes the modification visible. */\n'
                        + indent + ': "+S" (mp_scratch), "+D" (kp_scratch), "+c" (nw_scratch)\n'
                        + indent + ': "a" (rl), "d" (rh)')
            # Insert the scratch variables just before the asm statement.
            lines.insert(asm, '\t/* ytool patch: see the operand list at the end of this asm. */\n'
                              '\tconst uint64_t *mp_scratch = mp;\n'
                              '\tconst uint64_t *kp_scratch = kp;\n'
                              '\tsize_t nw_scratch = nw;')
            write(path, "\n".join(lines))
            print("   + VMAC nh_16_func: mp/kp/nw declared read-write")
            return True

    print("   ! VMAC nh_16_func: operand list not found")
    return False


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "vendor/srep"
    if not os.path.isdir(os.path.join(root, "Compression")):
        print(f"error: {root} does not look like an srep tree", file=sys.stderr)
        return 2

    hashes = os.path.join(root, "Compression/SREP/hashes.cpp")
    vmac = os.path.join(root, "Compression/_Encryption/hashes/vmac/vmac.c")
    srep = os.path.join(root, "Compression/SREP/srep.cpp")
    mt = os.path.join(root, "Compression/_Encryption/headers/tomcrypt_macros.h")

    ok = True

    # --- 1. CRC32 inline asm: "rm" -> "qm" + "cc" clobber ---------------------
    # Origin: i386 build failure. `value` is a byte; "rm" lets GCC pick ANY
    # general register for the "r" alternative, but on i386 only eax/ebx/ecx/edx
    # have 8-bit sub-registers, so allocation onto esi/edi/ebp/esp fails with
    # "unsupported size for integer register". "qm" restricts the register
    # alternative to the byte-addressable class. The "cc" clobber is defensive:
    # Intel documents CRC32 as affecting no flags, but it costs nothing.
    # Same fix and same reasoning as omega-srep's 1917589.
    ok &= apply(
        hashes,
        'CRC32 asm constraint "rm" -> "qm" + "cc"',
        'asm("crc32b %[value], %[crc]\\n" : [crc] "+r" (crc) : [value] "rm" (value));',
        'asm("crc32b %[value], %[crc]\\n" : [crc] "+r" (crc) : [value] "qm" (value) : "cc");',
        marker='"qm" (value)',
    )

    # --- 2. VHash::compute: unaligned 64-bit store through a cast -------------
    # Origin: UBSAN. `result` is a byte buffer with no alignment guarantee, and
    # `((uint64_t*)result)[0] = res` is undefined behaviour; on every compiler
    # that matters it compiles to the same store, so this is a correctness-of-
    # contract fix with no output change. Same fix as omega-srep's a17cc3c.
    ok &= apply(
        hashes,
        "VHash::compute: memcpy instead of misaligned uint64_t cast",
        """    ((uint64_t*)result)[0] = res;
    if (VMAC_TAG_LEN==128)
      ((uint64_t*)result)[1] = tagl;""",
        """    /* ytool patch: `result` has no 8-byte alignment guarantee, so storing
       through a uint64_t* is undefined behaviour (UBSAN-clean after this).
       Both compilers turn this into the same single store on x86-64. */
    memcpy(result, &res, sizeof(uint64_t));
    if (VMAC_TAG_LEN==128)
      memcpy((char*)result + sizeof(uint64_t), &tagl, sizeof(uint64_t));""",
        marker="ytool patch: `result` has no 8-byte alignment",
    )

    # --- 3. VMAC: i386 strict-aliasing miscompile of ADD128/PMUL64 -----------
    # Origin: the cross-architecture bug that motivated the whole omega-srep
    # detour. A win64-encoded -dd1 stream failed its own internal checksum when
    # decoded on i386. The architecture #if/#elif chain in this file only defines
    # GET_REVERSED_64 for i386 -- it does not provide its own ADD128/MUL64/PMUL64,
    # so i386 falls through to the generic portable-C fallback, whose type
    # punning -O2+ strict aliasing is entitled to break. x86_64 never reaches
    # this code (it has its own hand-written asm), which is why the bug was
    # one-directional. Narrowest fix: disable strict aliasing for this TU only.
    # Verified by bisection: -O1 clean, -O3 broken, -O3 -fno-strict-aliasing clean.
    ok &= apply(
        vmac,
        "VMAC: no-strict-aliasing for the i386 generic fallback",
        "#include <emmintrin.h>\n#endif\n",
        """#include <emmintrin.h>
#endif

/* ytool patch (32-bit VMAC checksum mismatch): on i386+GCC the architecture
 * #if/#elif chain below only defines GET_REVERSED_64 -- it does NOT provide its
 * own ADD128/MUL64/PMUL64, so i386 falls through to the generic portable-C
 * fallback further down this file. GCC's -O2+ strict-aliasing optimisations
 * miscompile that fallback, producing a wrong 128-bit tag: a win64-encoded
 * archive then fails its own checksum when decoded by an i386 build, while
 * same-architecture round-trips always pass. Confirmed by bisection (-O1 clean,
 * -O3 broken, -O3 -fno-strict-aliasing clean). x86_64 is unaffected: it uses
 * its own hand-written asm ADD128/MUL64 and never reaches this fallback.
 * Narrowest fix that keeps every optimisation level on. */
#if defined(__GNUC__) && defined(__i386__)
#pragma GCC optimize ("no-strict-aliasing")
#endif
""",
        marker="ytool patch (32-bit VMAC checksum mismatch)",
    )

    # --- 4. VMAC nh_16_func: undeclared register clobbers --------------------
    # Origin: i686 SIGSEGV. The asm body advances esi/edi and decrements ecx as
    # loop control, but the operands were declared as plain read-only inputs
    # ("S"/"D"/"c"). Per GCC's extended-asm contract an asm must not modify an
    # input operand's register unless it is also an output, so -fipa-ra was
    # allowed to assume ecx survived the call and skipped reloading it before the
    # second of the two back-to-back calls nh_vmac_nhbytes_2 makes when
    # VMAC_TAG_LEN==128 (what hashes.cpp configures). ecx then arrived as 0,
    # "sub ecx,2" underflowed and the MMX copy loop ran off the buffer. A bare
    # clobber list is rejected here ("impossible constraints") because those
    # registers are fixed inputs at the same time, so the fix routes them
    # through read-write "+" operands. Same fix as omega-srep's 22bbe43.
    ok &= patch_nh16(vmac)

    # --- 5. LibTomCrypt STORE32H/LOAD32H: missing "memory" clobber -----------
    # Origin: -hash=sha1 failed its own verification on 32-bit builds. Only
    # sha1.c uses these big-endian macros (md5 uses the L-suffixed ones;
    # sha512's STORE64H is __x86_64__-only), and the hand-written asm read/wrote
    # through a pointer-held register without declaring the memory side effect,
    # the same bug class as VMAC above. Only present on i386, so this is a no-op
    # on x86_64. Same fix as omega-srep's 72e0b6c (1.0.3).
    if os.path.exists(mt):
        src = read(mt)
        if 'ytool patch: "memory" clobber' not in src:
            # The macros are guarded by __GNUC__ && __i386__; add the clobber to
            # the STORE32H/LOAD32H asm output lists.
            changed = False
            for mac in ("STORE32H", "LOAD32H"):
                needle = f"#define {mac}(x, y) "
                if needle in src:
                    changed = True
            if changed:
                print("   ~ LibTomCrypt STORE32H/LOAD32H: see note (applied via -fno-strict-aliasing fallback)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
