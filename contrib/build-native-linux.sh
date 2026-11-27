#!/usr/bin/env bash
# Rebuilds the native C objects (lz4/zstd/lzma) for Linux x86-64, or i386 with ARCH=x86 (Option C of
# the migration to FPC). Output: contrib/{LZ4Delphi,ZSTD4Delphi,LZMADelphi}/*.linux.$ARCH.o
#
# Sources expected in contrib/.csrc (gitignored). If missing, they are fetched:
#   zstd v1.5.2 (must match ZSTD_VERSION_STRING in ZSTDLib.pas)
#   lz4  $LZ4_REF (v1.11.1)
#   xxHash $XXHASH_REF (v0.8.4)
#   LZMA SDK 26.06 (Igor Pavlov, public domain) via fetch-lzma-sdk.sh, from the
#   7-Zip GitHub release; a .7z archive, so 7z/7za/p7zip must be installed
#
# Key notes:
#  - zstd: -DZSTD_DISABLE_ASM (avoids huf_decompress .S files; uses C fallback,
#    identical output). xxhash.c is NOT included: zstd leaves XXH64 undefined.
#  - lz4: does NOT include xxhash.c either (XXH32 left undefined).
#  - xxhash4delphi.linux.$ARCH.o is the sole owner of the XXH* symbols; both are
#    resolved from it at final link, which avoids XXH* clashes.
#  - lzma: single-threaded (_7ZIP_ST/Z7_ST, avoids needing Threads.c); LzFind.c is the
#    match finder LzmaEnc.c needs. lzmadelphi.c adds two small wrappers on top of
#    LzmaLib.h's LzmaCompress/LzmaUncompress (see its own comments) to control the
#    end-of-stream marker, needed for the "unknown uncompressed size" stream
#    variant real encoders (e.g. "xz --format=lzma") actually produce.
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/

# ARCH=x86 builds the i386 objects (*.linux.x86.o) with gcc -m32, for the
# Linux x86 build of ytool (needs libc6-dev-i386 / gcc-multilib).
ARCH="${ARCH:-x64}"
case "$ARCH" in
  x64) M="" ;;
  x86) M="-m32 -msse2" ;;   # SSE2 is not baseline on i386 (xxHash needs it)
  *) echo "ARCH must be x64 or x86" >&2; exit 2 ;;
esac
CSRC="$(pwd)/.csrc"
mkdir -p "$CSRC"

# Revisiones fijadas a lo que efectivamente se construyo y publico. Un tag se
# puede mover; un SHA no. Ver contrib/pin-repo.sh para por que el pin tiene
# que aplicarse tambien sobre un checkout que ya existe.
XXHASH_REF="c87183a77d67f7d37e3d2d1b7eaac5e7c695e4f0"   # v0.8.4

. "$(dirname "$CSRC")/pin-repo.sh"   # $CSRC es absoluto; $0 no sirve, cada script hace cd distinto

# lz4 pinneado por SHA y no por tag: 0774d05 es posterior al tag v1.10.0 y
# trae el merge de fix_read_oob (PR #1753). Como ytool decodifica .ytp no
# confiable, volver al tag sacaria ese fix.
#
# Los tres scripts que compilan lz4 comparten $CSRC/lz4, asi que TIENEN que
# pedir la misma revision: entre 1.9.4 y 1.10.0 cambio LZ4HC_CLEVEL_MIN (3 -> 2)
# y el nivel 2 -- el primer candidato de la busqueda de nivel -- pasa a ser
# otro algoritmo. Un .ytp codificado con una version se restaura mal con la
# otra, a veces en silencio. Ver contrib/pin-repo.sh.
# v1.11.1 since 0.9.9a, which starts a new baseline: its output differs from
# 0774d05 (1.10.0 + fix_read_oob) for fast mode at every acceleration, HC
# levels 1, 2 and 10-12, and frames at those levels, so .ytp files from the
# older pre-releases that hold such streams do not restore with it.
LZ4_REF="aa4647fad575d01a874aaaadcdbe8e6a40e072f5"   # v1.11.1

pin_repo https://github.com/facebook/zstd "$CSRC/zstd" v1.5.2
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
pin_repo https://github.com/Cyan4973/xxHash "$CSRC/xxhash" "$XXHASH_REF"
. "$(dirname "$CSRC")/fetch-lzma-sdk.sh"
fetch_lzma_sdk || exit 1

echo "==> xxhash4delphi.linux.$ARCH.o (dueno unico de los simbolos XXH*, incl. XXH3)"
gcc $M -c -O2 -fPIC -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/xxhash4delphi.linux.$ARCH.o XXHASH4Delphi/xxhash4delphi.SSE2.c

echo "==> zstd4delphi.linux.$ARCH.o"
gcc $M -c -O2 -fPIC -DZSTD_DISABLE_ASM \
  -I "$CSRC/zstd/lib" -I "$CSRC/zstd/lib/common" \
  -I "$CSRC/zstd/lib/compress" -I "$CSRC/zstd/lib/decompress" \
  -o ZSTD4Delphi/zstd4delphi.linux.$ARCH.o ZSTD4Delphi/zstd4delphi.c

echo "==> lz4delphi.linux.$ARCH.o (SIN xxhash; usa el objeto xxhash de arriba)"
cat > "$CSRC/lz4delphi_lin.c" <<'EOF'
#include "lz4.c"
#include "lz4hc.c"
#include "lz4frame.c"
EOF
# x86: the patched copy, fast mode as on 64-bit (lz4_lib32 in pin-repo.sh).
# Since 0.9.9f -mlz4* use this object (not a liblz4), so it needs the same
# patch the 32-bit liblz4 had: without it x64 fast-mode .ytp files do not
# decode on x86.
LZ4INC="$CSRC/lz4/lib"
if [ "$ARCH" = x86 ]; then lz4_lib32 "$CSRC/lz4" "$CSRC/lz4-lib32" || exit 1; LZ4INC="$CSRC/lz4-lib32"; fi
gcc $M -c -O2 -fPIC -I "$LZ4INC" \
  -o LZ4Delphi/lz4delphi.linux.$ARCH.o "$CSRC/lz4delphi_lin.c"

echo "==> lzmadelphi.linux.$ARCH.o"
gcc $M -c -O2 -fPIC -I "$LZMA_SDK_C" \
  -o LZMADelphi/lzmadelphi.linux.$ARCH.o LZMADelphi/lzmadelphi.c

# zlib built in (0.9.9f; docs/ROADMAP-1.0.0.md point 3): the deflate side of
# -mzlib/-mpng, which used the SYSTEM libz.so.1 on Linux (another zlib, e.g.
# zlib-ng in compatibility mode, could write other bytes). Same commit as
# Windows' zlib1.dll (build-plugins-windows.sh): v1.4, deflate output equal to
# 1.3.1 in 3888 of 3888 cases measured. Z_PREFIX (z_deflate...) so it never
# clashes with a zlib a plugin loads. Inflate too: FPC's ZLib unit is a binding
# to the system libz (it made libz.so.1 a NEEDED of ytool).
ZLIB_REF="99623ef7097352da7993ba614161fd6a311e046e"
pin_repo https://github.com/madler/zlib "$CSRC/zlib" "$ZLIB_REF"
echo "==> StaticLibs/zlibstatic.linux.$ARCH.o (deflate + inflate, Z_PREFIX)"
mkdir -p StaticLibs
ZO=""
for f in deflate trees adler32 crc32 zutil inflate inftrees inffast; do
  gcc $M -c -O2 -fPIC -DZ_PREFIX -I "$CSRC/zlib" -o "$CSRC/zs_$f.$ARCH.o" "$CSRC/zlib/$f.c"
  ZO="$ZO $CSRC/zs_$f.$ARCH.o"
done
# shellcheck disable=SC2086
gcc $M -r -nostdlib -o StaticLibs/zlibstatic.linux.$ARCH.o $ZO

# libdeflate and lzlib built in (0.9.9f), from the same pins as their shared
# libraries (pin-repo.sh: build_libdeflate, build_lzlib). One object per source,
# as on Windows. libdeflate: the compressor only (ytool's -mlibdeflate uses
# nothing else).
. "$(dirname "$CSRC")/pin-repo.sh"
pin_repo https://github.com/ebiggers/libdeflate "$CSRC/libdeflate" "$LIBDEFLATE_REF"
echo "==> StaticLibs/libdeflate_*.linux.$ARCH.o"
for f in utils deflate_compress; do
  gcc $M -c -O2 -fPIC -I "$CSRC/libdeflate" -o "StaticLibs/libdeflate_$(basename $f).linux.$ARCH.o" "$CSRC/libdeflate/lib/$f.c"
done
fetch_lzlib || exit 1
echo "==> StaticLibs/lzlib.linux.$ARCH.o"
gcc $M -c -O2 -fPIC -I "$CSRC/lzlib-$LZLIB_VER" -o "StaticLibs/lzlib.linux.$ARCH.o" "$CSRC/lzlib-$LZLIB_VER/lzlib.c"

fetch_lzo || exit 1
echo "==> StaticLibs/lzo_*.linux.$ARCH.o (lzo $LZO_VER: lzo1x, lzo1c, lzo2a)"
for f in $LZO_SRC; do
  gcc $M -c -O2 -fPIC -I "$CSRC/lzo-$LZO_VER/include" -I "$CSRC/lzo-$LZO_VER/src" \
    -o "StaticLibs/lzo_$f.linux.$ARCH.o" "$CSRC/lzo-$LZO_VER/src/$f.c"
done

echo "OK: objetos Linux generados."
