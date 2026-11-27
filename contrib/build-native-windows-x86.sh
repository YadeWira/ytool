#!/usr/bin/env bash
# Rebuilds the native xxHash/lzma objects for Windows x86 (32-bit, i386-win32)
# using the mingw-w64 i686 cross-compiler from Linux. 32-bit sibling of
# build-native-windows.sh.
#
# Why only xxHash and lzma: the repo ships prebuilt win32 objects for zstd
# (zstd4delphi.*.x86.o) and lz4 (LZ4DELPHI.*.X86.OBJ) inherited from the
# original Delphi project (32-bit was a real target there). xxHash has NO
# win32 object at all (same gap as win64 originally had -- xxhashlib expected
# it but it never existed), and lzma is a new addition (PrecompLZMA.pas) with
# no win32 object either.
#
# xxHash needs -msse2 explicitly here: unlike x86-64 (where SSE2 is baseline),
# i686 doesn't enable it by default, and xxhash.h's SSE2 accumulator won't even
# parse (__m128i undeclared) without it. Only the plain SSE2 object is needed
# -- xxhashlib.pas's win32 branch picks AVX2.X86.O only under a custom AVX2
# define we don't pass, same as the win64 branch.
#
# lzma: same _7ZIP_ST amalgamation as the other native-object scripts (see
# build-native-linux.sh and lzmadelphi.c's own comments). LzmaUncompress needs
# an explicit, fully-decorated `external name '_LzmaUncompress@24'` (matching
# LzmaLib.h's MY_STDAPI/__stdcall under _WIN32) -- unlike cdecl, FPC does NOT
# auto-decorate stdcall externals with the leading underscore or the "@N"
# suffix, so a bare `stdcall; external;` silently looks up the wrong,
# undecorated name and fails to link. LzmaCompressEx/LzmaDecodeToEndMark
# (ytool's own, plain "int"/cdecl functions) don't need this since FPC DOES
# auto-add the leading underscore for cdecl -- see contrib/LZMADelphi/LZMALib.pas.
#
# The inherited win32 zstd/lz4 bindings (ZSTDLib.pas, lz4lib.pas) had a
# related but opposite bug: their Chet-generated "private" identifiers
# (_ZSTD_compress, and lz4lib.pas's `_PU = '_'` prefix constant) already
# baked in a leading underscore, which FPC's cdecl auto-decoration then
# prefixed AGAIN, producing undefined double-underscored symbols
# (__ZSTD_compress etc) at link time -- fixed by never manually adding the
# underscore FPC already supplies (see the "name '...'" clauses added to
# both files, and lz4lib.pas's now-empty win32 `_PU`).
#
# contrib/WinLibcShim/WinLibcShim.pas supplies memset/memcpy/memmove/malloc/
# calloc/free (plain Pascal wrappers around Move/FillChar/GetMem/FreeMem) and
# links a handful of tiny objects this script extracts straight out of the
# i686-w64-mingw32 toolchain's own libgcc.a: __alloca/___chkstk (the stack-
# probe helper, real ASM manipulating ESP directly -- can't be reimplemented
# in Pascal) and the i386 64-bit-arithmetic helpers (__udivdi3 etc, needed
# since i386 has no native 64-bit divide/shift instructions). None of these
# are in FPC's i386-win32 RTL, but the zstd/xxhash/lz4 C objects call them
# internally.
#
# mORMot's SynCrypto.pas SHA512_X86 path (i386-only) would otherwise need
# contrib/mORMot/static/i386-win32/sha512-x86.o -- the only available source,
# contrib/mORMot/sha512-x86.obj, is a legacy Delphi-era OMF object FPC's
# linker rejects outright ("Illegal COFF Magic"), and it isn't a real GNU
# COFF object to begin with. Sidestepped entirely by building with
# `-dABSOLUTEPASCAL` (see winbuild-x86.ps1), which routes SynCrypto.pas to
# its pure-Pascal SHA512 fallback instead -- no object file needed.
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
CSRC="$(pwd)/.csrc"
mkdir -p "$CSRC"

. "$(dirname "$CSRC")/pin-repo.sh"   # $CSRC es absoluto; $0 no sirve, cada script hace cd distinto

# Revisiones fijadas a lo que efectivamente se construyo y publico. Un tag se
# puede mover; un SHA no. Ver contrib/pin-repo.sh para por que el pin tiene
# que aplicarse tambien sobre un checkout que ya existe.
XXHASH_REF="c87183a77d67f7d37e3d2d1b7eaac5e7c695e4f0"   # v0.8.4

pin_repo https://github.com/Cyan4973/xxHash "$CSRC/xxhash" "$XXHASH_REF"
# lz4 pinned by SHA, same revision as build-native-linux.sh and the plugin
# scripts (they share $CSRC/lz4).
LZ4_REF="aa4647fad575d01a874aaaadcdbe8e6a40e072f5"   # v1.11.1
. "$(dirname "$CSRC")/fetch-lzma-sdk.sh"
fetch_lzma_sdk || exit 1

CC=i686-w64-mingw32-gcc
command -v "$CC" >/dev/null || { echo "ERROR: falta $CC (instala mingw-w64, paquete gcc-mingw-w64-i686)"; exit 1; }

echo "==> XXHASH4DELPHI.SSE2.X86.O"
"$CC" -c -O2 -msse2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.SSE2.X86.O XXHASH4Delphi/xxhash4delphi.SSE2.c

echo "==> lzmadelphi.win32.x86.o"
"$CC" -c -O2 -I "$LZMA_SDK_C" \
  -o LZMADelphi/lzmadelphi.win32.x86.o LZMADelphi/lzmadelphi.c

# zstd/lz4: rebuilt from the pinned sources (zstd v1.5.2 for these internal
# objects, lz4 $LZ4_REF) as on Linux. The objects committed before were the
# inherited Delphi-era builds (zstd 1.5.2, lz4 1.9.3, no stated origin). Both
# names of each pair get the same object: the AVX2 one is only linked with
# -dAVX2, which no build here sets. They leave XXH32/XXH64 undefined, for the
# xxhash object above, as the old ones did.
pin_repo https://github.com/facebook/zstd "$CSRC/zstd" v1.5.2
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
echo "==> zstd4delphi.{sse2,avx2}.x86.o"
"$CC" -c -O2 -DZSTD_DISABLE_ASM \
  -I "$CSRC/zstd/lib" -I "$CSRC/zstd/lib/common" \
  -I "$CSRC/zstd/lib/compress" -I "$CSRC/zstd/lib/decompress" \
  -o ZSTD4Delphi/zstd4delphi.sse2.x86.o ZSTD4Delphi/zstd4delphi.c
cp ZSTD4Delphi/zstd4delphi.sse2.x86.o ZSTD4Delphi/zstd4delphi.avx2.x86.o
echo "==> lz4delphi.{sse2,avx2}.x86.obj"
printf '#include "lz4.c"\n#include "lz4hc.c"\n#include "lz4frame.c"\n' > "$CSRC/lz4delphi_x86.c"
# the patched copy, fast mode as on 64-bit (lz4_lib32 in pin-repo.sh): since
# 0.9.9f -mlz4* use this object, not liblz4.dll
lz4_lib32 "$CSRC/lz4" "$CSRC/lz4-lib32" || exit 1
"$CC" -c -O2 -I "$CSRC/lz4-lib32" \
  -o LZ4Delphi/lz4delphi.sse2.x86.obj "$CSRC/lz4delphi_x86.c"
cp LZ4Delphi/lz4delphi.sse2.x86.obj LZ4Delphi/lz4delphi.avx2.x86.obj

echo "==> WinLibcShim/*.x86.o (extraidos de libgcc.a del toolchain i686-w64-mingw32)"
LIBGCC="$("$CC" -print-libgcc-file-name)"
[ -f "$LIBGCC" ] || { echo "ERROR: no se encontro libgcc.a ($LIBGCC)"; exit 1; }
SHIMTMP="$(mktemp -d)"
trap 'rm -rf "$SHIMTMP"' EXIT
( cd "$SHIMTMP" && ar x "$LIBGCC" _chkstk.o _chkstk_ms.o _udivdi3.o _divdi3.o \
    _umoddi3.o _moddi3.o _ashldi3.o _ashrdi3.o _lshrdi3.o _ctzdi2.o )
cp "$SHIMTMP/_chkstk.o"   WinLibcShim/chkstk.x86.o
# ___chkstk_ms: what the zstd/lz4 objects built above call for large stack
# frames (the inherited ones called __alloca, which _chkstk.o provides).
cp "$SHIMTMP/_chkstk_ms.o" WinLibcShim/chkstk_ms.x86.o
cp "$SHIMTMP/_udivdi3.o"  WinLibcShim/udivdi3.x86.o
cp "$SHIMTMP/_divdi3.o"   WinLibcShim/divdi3.x86.o
cp "$SHIMTMP/_umoddi3.o"  WinLibcShim/umoddi3.x86.o
cp "$SHIMTMP/_moddi3.o"   WinLibcShim/moddi3.x86.o
cp "$SHIMTMP/_ashldi3.o"  WinLibcShim/ashldi3.x86.o
cp "$SHIMTMP/_ashrdi3.o"  WinLibcShim/ashrdi3.x86.o
cp "$SHIMTMP/_lshrdi3.o"  WinLibcShim/lshrdi3.x86.o
# ___ctzdi2: the 32-bit lz4 with a 64-bit reg_t (lz4_lib32) counts trailing
# zeros of 64-bit words; since 0.9.9f that lz4 is linked into ytool
cp "$SHIMTMP/_ctzdi2.o"   WinLibcShim/ctzdi2.x86.o


# zlib built in (0.9.9f, as on Linux: contrib/build-native-linux.sh). Same
# commit as zlib1.dll; Z_PREFIX. Replaces the FPC ZLib unit, which bound
# zlib1.dll at start-up.
ZLIB_REF="99623ef7097352da7993ba614161fd6a311e046e"
pin_repo https://github.com/madler/zlib "$CSRC/zlib" "$ZLIB_REF"
echo "==> StaticLibs/zlib_*.win32.x86.o (deflate + inflate, Z_PREFIX)"
mkdir -p StaticLibs
# One object per source, linked one by one ({$L} in imports/ZLibDLL.pas): FPC's
# internal linker misreads an "ld -r" merge of COFF objects (zlibVersion
# pointed at another string, every call failed), and on x64 the default
# -mcmodel=medium reaches other objects' data through .rdata$.refptr.*
# sections it does not handle either.
for f in deflate trees adler32 crc32 zutil inflate inftrees inffast; do
  "$CC" -c -O2 -DZ_PREFIX -I "$CSRC/zlib" -o StaticLibs/zlib_$f.win32.x86.o "$CSRC/zlib/$f.c"
done
rm -f StaticLibs/zlibstatic.win32.x86.o

# libdeflate and lzlib built in (0.9.9f): see build-native-linux.sh.
pin_repo https://github.com/ebiggers/libdeflate "$CSRC/libdeflate" "$LIBDEFLATE_REF"
echo "==> StaticLibs/libdeflate_*.win32.x86.o"
for f in utils deflate_compress; do
  "$CC" -c -O2 -I "$CSRC/libdeflate" -o "StaticLibs/libdeflate_$(basename $f).win32.x86.o" "$CSRC/libdeflate/lib/$f.c"
done
fetch_lzlib || exit 1
echo "==> StaticLibs/lzlib.win32.x86.o"
"$CC" -c -O2 -I "$CSRC/lzlib-$LZLIB_VER" -o "StaticLibs/lzlib.win32.x86.o" "$CSRC/lzlib-$LZLIB_VER/lzlib.c"

echo "OK: objetos Windows x86 generados."
