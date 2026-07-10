#!/usr/bin/env python3
"""Patches Intensity/srep's vmac.c: nh_16_func and poly_step_func's hand-written
MMX inline asm (Compression/_Encryption/hashes/vmac/vmac.c) declare mp/kp/nw
(nh_16_func) and mh (poly_step_func) as plain read-only operands ("S"/"D"/"c"),
but the asm body genuinely advances esi/edi and decrements ecx in its loop (and
poly_step_func reuses esi as scratch past its initial load). Per GCC's extended-asm
contract this is undefined: -O2+'s -fipa-ra interprocedural register allocator can
assume these registers are unchanged across a call and skip reloading them before
a second back-to-back call (both functions are called twice in a row whenever
VMAC_TAG_LEN==128, which is what Compression/SREP/hashes.cpp configures) -- this is
a real, independently-confirmed 32-bit crash (ECX underflows, the MMX copy loop
runs unbounded past the buffer) in the sibling omega-srep fork
(github.com/YadeWira/omega-srep, commit 22bbe43). Fixed the same way there: route
the modified operands through local read-write ("+") operands.

Idempotent (checks for the "mp_scratch" marker before patching, safe to re-run
against a fresh clone or one already patched).
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

if "mp_scratch" in src:
    print("   (vmac.c ya parcheado)")
    sys.exit(0)

old_nh_open = (
    "#ifdef __GNUC__\n"
    "\t__asm__ __volatile__\n"
    "\t(\n"
    "\t\t\".intel_syntax noprefix;\"\n"
    "#else\n"
)
new_nh_open = (
    "#ifdef __GNUC__\n"
    "\tconst uint64_t *mp_scratch = mp;\n"
    "\tconst uint64_t *kp_scratch = kp;\n"
    "\tsize_t nw_scratch = nw;\n"
    "\t__asm__ __volatile__\n"
    "\t(\n"
    "\t\t\".intel_syntax noprefix;\"\n"
    "#else\n"
)
assert src.count(old_nh_open) == 1, f"nh_16_func open anchor count={src.count(old_nh_open)}"
src = src.replace(old_nh_open, new_nh_open, 1)

old_nh_operands = (
    "\t\t:\n"
    "\t\t: \"S\" (mp), \"D\" (kp), \"c\" (nw), \"a\" (rl), \"d\" (rh)\n"
    "\t\t: \"memory\", \"cc\"\n"
)
new_nh_operands = (
    "\t\t: \"+S\" (mp_scratch), \"+D\" (kp_scratch), \"+c\" (nw_scratch)\n"
    "\t\t: \"a\" (rl), \"d\" (rh)\n"
    "\t\t: \"memory\", \"cc\"\n"
)
assert src.count(old_nh_operands) == 1, f"nh_16_func operands count={src.count(old_nh_operands)}"
src = src.replace(old_nh_operands, new_nh_operands, 1)

old_poly_open = (
    "#ifdef __GNUC__\n"
    "\tuint32_t temp;\n"
    "\t__asm__ __volatile__\n"
    "\t(\n"
    "\t\t\"mov %%ebx, %0;\"\n"
    "\t\t\"mov %1, %%ebx;\"\n"
    "\t\t\".intel_syntax noprefix;\"\n"
)
new_poly_open = (
    "#ifdef __GNUC__\n"
    "\tuint32_t temp;\n"
    "\tconst uint64_t *mh_scratch = mh;\n"
    "\t__asm__ __volatile__\n"
    "\t(\n"
    "\t\t\"mov %%ebx, %0;\"\n"
    "\t\t\"mov %2, %%ebx;\"\n"
    "\t\t\".intel_syntax noprefix;\"\n"
)
assert src.count(old_poly_open) == 1, f"poly_step_func open anchor count={src.count(old_poly_open)}"
src = src.replace(old_poly_open, new_poly_open, 1)

old_poly_operands = (
    "\t\t: \"=m\" (temp)\n"
    "\t\t: \"m\" (ahi), \"D\" (ml), \"d\" (kh), \"a\" (alo), \"S\" (mh), \"c\" (kl)\n"
)
new_poly_operands = (
    "\t\t: \"=m\" (temp), \"+S\" (mh_scratch)\n"
    "\t\t: \"m\" (ahi), \"D\" (ml), \"d\" (kh), \"a\" (alo), \"c\" (kl)\n"
)
assert src.count(old_poly_operands) == 1, f"poly_step_func operands count={src.count(old_poly_operands)}"
src = src.replace(old_poly_operands, new_poly_operands, 1)

open(path, "w", encoding="utf-8").write(src)
print("   OK -> vmac.c parcheado (nh_16_func + poly_step_func, +S/+D/+c)")
