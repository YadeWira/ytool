#!/usr/bin/env bash
# Rebuilds the native xxHash/lzma objects for Windows x86-64 (COFF/PE) using
# the mingw-w64 cross-compiler from Linux. Windows equivalent of
# build-native-linux.sh.
#
# Why only xxHash and lzma: the repo ships prebuilt Windows objects for zstd
# (zstd4delphi.*.x64.o) and lz4 (LZ4DELPHI.*.X64.OBJ) inherited from the original
# Delphi project, but did NOT bring xxHash's (xxhashlib expected it but it never existed).
# Here we generate it from the same C source used on Linux. lzma is a new
# addition (PrecompLZMA.pas) with no prebuilt object at all.
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

CC=x86_64-w64-mingw32-gcc
command -v "$CC" >/dev/null || { echo "ERROR: falta $CC (instala mingw-w64)"; exit 1; }

echo "==> XXHASH4DELPHI.SSE2.X64.O (dueno de los simbolos XXH*, incl. XXH3)"
"$CC" -c -O2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.SSE2.X64.O XXHASH4Delphi/xxhash4delphi.SSE2.c

echo "==> XXHASH4DELPHI.AVX2.X64.O"
"$CC" -c -O2 -mavx2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.AVX2.X64.O XXHASH4Delphi/xxhash4delphi.avx2.c

echo "==> lzmadelphi.win64.x64.o"
"$CC" -c -O2 -I "$CSRC/lzma-sdk-ref/C" \
  -o LZMADelphi/lzmadelphi.win64.x64.o LZMADelphi/lzmadelphi.c

echo "OK: objetos Windows generados."
