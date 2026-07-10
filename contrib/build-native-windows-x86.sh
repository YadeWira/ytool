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

[ -d "$CSRC/xxhash" ] || git clone --depth 1 https://github.com/Cyan4973/xxHash.git "$CSRC/xxhash"
if [ ! -d "$CSRC/lzma-sdk-ref" ]; then
  SEVENZ="$(command -v 7z || command -v 7za || true)"
  if [ -z "$SEVENZ" ]; then
    echo "ERROR: LZMA SDK sources missing and no 7z/7za found to extract them." >&2
    echo "       Install p7zip (e.g. 'apt install p7zip-full') or place the" >&2
    echo "       extracted SDK yourself at $CSRC/lzma-sdk-ref/C/*.c" >&2
    exit 1
  fi
  # Pinned to 19.00, see build-native-linux.sh for why.
  curl -sL -o "$CSRC/lzma-sdk.7z" https://www.7-zip.org/a/lzma1900.7z
  mkdir -p "$CSRC/lzma-sdk-ref"
  "$SEVENZ" x -y -o"$CSRC/lzma-sdk-ref" "$CSRC/lzma-sdk.7z" >/dev/null
fi

CC=i686-w64-mingw32-gcc
command -v "$CC" >/dev/null || { echo "ERROR: falta $CC (instala mingw-w64, paquete gcc-mingw-w64-i686)"; exit 1; }

echo "==> XXHASH4DELPHI.SSE2.X86.O"
"$CC" -c -O2 -msse2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.SSE2.X86.O XXHASH4Delphi/xxhash4delphi.SSE2.c

echo "==> lzmadelphi.win32.x86.o"
"$CC" -c -O2 -I "$CSRC/lzma-sdk-ref/C" \
  -o LZMADelphi/lzmadelphi.win32.x86.o LZMADelphi/lzmadelphi.c

echo "==> WinLibcShim/*.x86.o (extraidos de libgcc.a del toolchain i686-w64-mingw32)"
LIBGCC="$("$CC" -print-libgcc-file-name)"
[ -f "$LIBGCC" ] || { echo "ERROR: no se encontro libgcc.a ($LIBGCC)"; exit 1; }
SHIMTMP="$(mktemp -d)"
trap 'rm -rf "$SHIMTMP"' EXIT
( cd "$SHIMTMP" && ar x "$LIBGCC" _chkstk.o _udivdi3.o _divdi3.o _umoddi3.o \
    _moddi3.o _ashldi3.o _ashrdi3.o _lshrdi3.o )
cp "$SHIMTMP/_chkstk.o"   WinLibcShim/chkstk.x86.o
cp "$SHIMTMP/_udivdi3.o"  WinLibcShim/udivdi3.x86.o
cp "$SHIMTMP/_divdi3.o"   WinLibcShim/divdi3.x86.o
cp "$SHIMTMP/_umoddi3.o"  WinLibcShim/umoddi3.x86.o
cp "$SHIMTMP/_moddi3.o"   WinLibcShim/moddi3.x86.o
cp "$SHIMTMP/_ashldi3.o"  WinLibcShim/ashldi3.x86.o
cp "$SHIMTMP/_ashrdi3.o"  WinLibcShim/ashrdi3.x86.o
cp "$SHIMTMP/_lshrdi3.o"  WinLibcShim/lshrdi3.x86.o

echo "OK: objetos Windows x86 generados."
