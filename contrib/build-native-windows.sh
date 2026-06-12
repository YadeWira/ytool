#!/usr/bin/env bash
# Reconstruye el objeto nativo de xxHash para Windows x86-64 (COFF/PE) usando el
# cross-compiler mingw-w64 desde Linux. Equivalente Windows de build-native-linux.sh.
#
# Por que solo xxHash: el repo trae prebuilt los objetos Windows de zstd
# (zstd4delphi.*.x64.o) y lz4 (LZ4DELPHI.*.X64.OBJ) heredados del proyecto Delphi
# original, pero NO traia el de xxHash (xxhashlib lo esperaba pero nunca existio).
# Aqui lo generamos desde la misma fuente C que en Linux.
#
# Salida (referenciada por contrib/XXHASH4Delphi/xxhashlib.pas en la rama WIN64):
#   contrib/XXHASH4Delphi/XXHASH4DELPHI.SSE2.X64.O
#   contrib/XXHASH4Delphi/XXHASH4DELPHI.AVX2.X64.O
#
# Simbolos: el objeto exporta todos los XXH* (XXH32/64/3/128) que zstd y lz4
# necesitan resolver al enlace final (igual patron que en Linux: xxhash es el
# unico dueno de XXH*). Las referencias C (malloc/free/memcpy/memmove/memset) y
# ___chkstk_ms quedan indefinidas y se resuelven al enlazar: las primeras desde
# las implementaciones Pascal 'public name' de xxhashlib, ___chkstk_ms desde
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
