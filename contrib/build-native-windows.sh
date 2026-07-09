#!/usr/bin/env bash
# Rebuilds the native xxHash object for Windows x86-64 (COFF/PE) using the
# mingw-w64 cross-compiler from Linux. Windows equivalent of build-native-linux.sh.
#
# Why only xxHash: the repo ships prebuilt Windows objects for zstd
# (zstd4delphi.*.x64.o) and lz4 (LZ4DELPHI.*.X64.OBJ) inherited from the original
# Delphi project, but did NOT bring xxHash's (xxhashlib expected it but it never existed).
# Here we generate it from the same C source used on Linux.
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
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
CSRC="$(pwd)/.csrc"
mkdir -p "$CSRC"

[ -d "$CSRC/xxhash" ] || git clone --depth 1 https://github.com/Cyan4973/xxHash.git "$CSRC/xxhash"

CC=x86_64-w64-mingw32-gcc
command -v "$CC" >/dev/null || { echo "ERROR: falta $CC (instala mingw-w64)"; exit 1; }

echo "==> XXHASH4DELPHI.SSE2.X64.O (dueno de los simbolos XXH*, incl. XXH3)"
"$CC" -c -O2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.SSE2.X64.O XXHASH4Delphi/xxhash4delphi.SSE2.c

echo "==> XXHASH4DELPHI.AVX2.X64.O"
"$CC" -c -O2 -mavx2 -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/XXHASH4DELPHI.AVX2.X64.O XXHASH4Delphi/xxhash4delphi.avx2.c

echo "OK: objetos Windows (xxHash) generados."
