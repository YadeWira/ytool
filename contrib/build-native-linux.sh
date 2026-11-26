#!/usr/bin/env bash
# Rebuilds the native C objects (lz4/zstd/lzma) for Linux x86-64 (Option C of
# the migration to FPC). Output: contrib/{LZ4Delphi,ZSTD4Delphi,LZMADelphi}/*.linux.x64.o
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
#  - xxhash4delphi.linux.x64.o is the sole owner of the XXH* symbols; both are
#    resolved from it at final link, which avoids XXH* clashes.
#  - lzma: single-threaded (_7ZIP_ST/Z7_ST, avoids needing Threads.c); LzFind.c is the
#    match finder LzmaEnc.c needs. lzmadelphi.c adds two small wrappers on top of
#    LzmaLib.h's LzmaCompress/LzmaUncompress (see its own comments) to control the
#    end-of-stream marker, needed for the "unknown uncompressed size" stream
#    variant real encoders (e.g. "xz --format=lzma") actually produce.
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
CSRC="$(pwd)/.csrc"
mkdir -p "$CSRC"

# Revisiones fijadas a lo que efectivamente se construyo y publico. Un tag se
# puede mover; un SHA no. Ver contrib/pin-repo.sh para por que el pin tiene
# que aplicarse tambien sobre un checkout que ya existe.
XXHASH_REF="c87183a77d67f7d37e3d2d1b7eaac5e7c695e4f0"   # v0.8.4

. "$(dirname "$CSRC")/pin-repo.sh"   # $CSRC es absoluto; $0 no sirve, cada script hace cd distinto

# lz4 pinneado por SHA y no por tag: 0774d05 es posterior al tag v1.10.0 y
# trae el merge de fix_read_oob (PR #1753). Como ytool decodifica .pmp no
# confiable, volver al tag sacaria ese fix.
#
# Los tres scripts que compilan lz4 comparten $CSRC/lz4, asi que TIENEN que
# pedir la misma revision: entre 1.9.4 y 1.10.0 cambio LZ4HC_CLEVEL_MIN (3 -> 2)
# y el nivel 2 -- el primer candidato de la busqueda de nivel -- pasa a ser
# otro algoritmo. Un .pmp codificado con una version se restaura mal con la
# otra, a veces en silencio. Ver contrib/pin-repo.sh.
# v1.11.1 since 0.9.9a, which starts a new baseline: its output differs from
# 0774d05 (1.10.0 + fix_read_oob) for fast mode at every acceleration, HC
# levels 1, 2 and 10-12, and frames at those levels, so .pmp files from the
# older pre-releases that hold such streams do not restore with it.
LZ4_REF="aa4647fad575d01a874aaaadcdbe8e6a40e072f5"   # v1.11.1

pin_repo https://github.com/facebook/zstd "$CSRC/zstd" v1.5.2
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
pin_repo https://github.com/Cyan4973/xxHash "$CSRC/xxhash" "$XXHASH_REF"
. "$(dirname "$CSRC")/fetch-lzma-sdk.sh"
fetch_lzma_sdk || exit 1

echo "==> xxhash4delphi.linux.x64.o (dueno unico de los simbolos XXH*, incl. XXH3)"
gcc -c -O2 -fPIC -I "$CSRC/xxhash" \
  -o XXHASH4Delphi/xxhash4delphi.linux.x64.o XXHASH4Delphi/xxhash4delphi.SSE2.c

echo "==> zstd4delphi.linux.x64.o"
gcc -c -O2 -fPIC -DZSTD_DISABLE_ASM \
  -I "$CSRC/zstd/lib" -I "$CSRC/zstd/lib/common" \
  -I "$CSRC/zstd/lib/compress" -I "$CSRC/zstd/lib/decompress" \
  -o ZSTD4Delphi/zstd4delphi.linux.x64.o ZSTD4Delphi/zstd4delphi.c

echo "==> lz4delphi.linux.x64.o (SIN xxhash; usa el objeto xxhash de arriba)"
cat > "$CSRC/lz4delphi_lin.c" <<'EOF'
#include "lz4.c"
#include "lz4hc.c"
#include "lz4frame.c"
EOF
gcc -c -O2 -fPIC -I "$CSRC/lz4/lib" \
  -o LZ4Delphi/lz4delphi.linux.x64.o "$CSRC/lz4delphi_lin.c"

echo "==> lzmadelphi.linux.x64.o"
gcc -c -O2 -fPIC -I "$LZMA_SDK_C" \
  -o LZMADelphi/lzmadelphi.linux.x64.o LZMADelphi/lzmadelphi.c

echo "OK: objetos Linux generados."
