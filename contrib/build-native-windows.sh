#!/usr/bin/env bash
# Rebuilds the native xxHash/lzma objects for Windows x86-64 (COFF/PE) using
# the mingw-w64 cross-compiler from Linux. Windows equivalent of
# build-native-linux.sh.
#
# Builds xxHash, lzma, and (since 0.9.9a) zstd and lz4 from pinned sources.
# Until 0.9.9a the zstd (zstd4delphi.*.x64.o) and lz4 (lz4delphi.*.x64.obj)
# objects were the prebuilt ones inherited from the original Delphi project,
# with no stated origin; xxHash's never existed (xxhashlib expected it), and
# lzma is ytool's own addition (PrecompLZMA.pas).
#
# Output (referenced by contrib/XXHASH4Delphi/xxhashlib.pas on the WIN64 branch):
#   contrib/XXHASH4Delphi/XXHASH4DELPHI.SSE2.X64.O
#   contrib/XXHASH4Delphi/XXHASH4DELPHI.AVX2.X64.O
#
# Symbols: the object exports all the XXH* (XXH32/64/3/128) that zstd and lz4
# need to resolve at final link (same pattern as on Linux: xxhash is the
# sole owner of XXH*). The C references (malloc/free/memcpy/memmove/memset) and
# ___chkstk_ms remain undefined and are resolved at link time: the former from
# xxhashlib's Pascal 'public name' implementations, ___chkstk_ms from
# contrib/LIBC/chkstk_ms.x64.o.
#
# lzma: same _7ZIP_ST amalgamation as Linux (see build-native-linux.sh and
# lzmadelphi.c's own comments). Alloc.c's dead BigAlloc/MidAlloc pull in a
# kernel32 VirtualAlloc/VirtualFree import FPC's {$L}-linked-object model
# can't resolve at link time -- lzmadelphi.c redirects them to malloc/free
# via macros for exactly this reason, so this cross-compile needs no special
# handling beyond that already being in place.
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

CC=x86_64-w64-mingw32-gcc
command -v "$CC" >/dev/null || { echo "ERROR: falta $CC (instala mingw-w64)"; exit 1; }

echo "==> XXHASH4DELPHI.SSE2.X64.O (dueno de los simbolos XXH*, incl. XXH3)"
"$CC" -c -O2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.SSE2.X64.O XXHASH4Delphi/xxhash4delphi.SSE2.c

echo "==> XXHASH4DELPHI.AVX2.X64.O"
"$CC" -c -O2 -mavx2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.AVX2.X64.O XXHASH4Delphi/xxhash4delphi.avx2.c

echo "==> lzmadelphi.win64.x64.o"
"$CC" -c -O2 -I "$LZMA_SDK_C" \
  -o LZMADelphi/lzmadelphi.win64.x64.o LZMADelphi/lzmadelphi.c

# zstd/lz4: rebuilt from the pinned sources (zstd v1.5.2 for these internal
# objects, lz4 $LZ4_REF) as on Linux. The objects committed before were the
# inherited Delphi-era builds (zstd 1.5.2, lz4 1.9.3, no stated origin). Both
# names of each pair get the same object: the AVX2 one is only linked with
# -dAVX2, which no build here sets. They leave XXH32/XXH64 undefined, for the
# xxhash object above, as the old ones did.
pin_repo https://github.com/facebook/zstd "$CSRC/zstd" v1.5.2
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
echo "==> zstd4delphi.{sse2,avx2}.x64.o"
"$CC" -c -O2 -DZSTD_DISABLE_ASM \
  -I "$CSRC/zstd/lib" -I "$CSRC/zstd/lib/common" \
  -I "$CSRC/zstd/lib/compress" -I "$CSRC/zstd/lib/decompress" \
  -o ZSTD4Delphi/zstd4delphi.sse2.x64.o ZSTD4Delphi/zstd4delphi.c
cp ZSTD4Delphi/zstd4delphi.sse2.x64.o ZSTD4Delphi/zstd4delphi.avx2.x64.o
echo "==> lz4delphi.{sse2,avx2}.x64.obj"
printf '#include "lz4.c"\n#include "lz4hc.c"\n#include "lz4frame.c"\n' > "$CSRC/lz4delphi_x64.c"
"$CC" -c -O2 -I "$CSRC/lz4/lib" \
  -o LZ4Delphi/lz4delphi.sse2.x64.obj "$CSRC/lz4delphi_x64.c"
cp LZ4Delphi/lz4delphi.sse2.x64.obj LZ4Delphi/lz4delphi.avx2.x64.obj


# zlib built in (0.9.9f, as on Linux: contrib/build-native-linux.sh). Same
# commit as zlib1.dll; Z_PREFIX. Replaces the FPC ZLib unit, which bound
# zlib1.dll at start-up.
ZLIB_REF="99623ef7097352da7993ba614161fd6a311e046e"
pin_repo https://github.com/madler/zlib "$CSRC/zlib" "$ZLIB_REF"
echo "==> StaticLibs/zlib_*.win64.x64.o (deflate + inflate, Z_PREFIX)"
mkdir -p StaticLibs
# One object per source, linked one by one ({$L} in imports/ZLibDLL.pas): FPC's
# internal linker misreads an "ld -r" merge of COFF objects (zlibVersion
# pointed at another string, every call failed), and on x64 the default
# -mcmodel=medium reaches other objects' data through .rdata$.refptr.*
# sections it does not handle either.
for f in deflate trees adler32 crc32 zutil inflate inftrees inffast; do
  "$CC" -c -O2 -mcmodel=small -DZ_PREFIX -I "$CSRC/zlib" -o StaticLibs/zlib_$f.win64.x64.o "$CSRC/zlib/$f.c"
done
rm -f StaticLibs/zlibstatic.win64.x64.o

# libdeflate and lzlib built in (0.9.9f): see build-native-linux.sh.
pin_repo https://github.com/ebiggers/libdeflate "$CSRC/libdeflate" "$LIBDEFLATE_REF"
echo "==> StaticLibs/libdeflate_*.win64.x64.o"
for f in utils deflate_compress; do
  "$CC" -c -O2 -mcmodel=small -I "$CSRC/libdeflate" -o "StaticLibs/libdeflate_$(basename $f).win64.x64.o" "$CSRC/libdeflate/lib/$f.c"
done
fetch_lzlib || exit 1
echo "==> StaticLibs/lzlib.win64.x64.o"
"$CC" -c -O2 -mcmodel=small -I "$CSRC/lzlib-$LZLIB_VER" -o "StaticLibs/lzlib.win64.x64.o" "$CSRC/lzlib-$LZLIB_VER/lzlib.c"


echo "OK: objetos Windows generados."
