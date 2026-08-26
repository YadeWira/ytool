#!/usr/bin/env bash
# Rebuilds the native C objects (lz4/zstd/lzma) for Linux x86-64 (Option C of
# the migration to FPC). Output: contrib/{LZ4Delphi,ZSTD4Delphi,LZMADelphi}/*.linux.x64.o
#
# Sources expected in contrib/.csrc (gitignored). If missing, they are fetched:
#   zstd v1.5.2 (must match ZSTD_VERSION_STRING in ZSTDLib.pas)
#   lz4  (recent release)
#   LZMA SDK (Igor Pavlov, public domain; official 7-zip.org distribution,
#   only ships as a .7z archive -- needs 7z/7za/p7zip installed)
#
# Key notes:
#  - zstd: -DZSTD_DISABLE_ASM (avoids huf_decompress .S files; uses C fallback,
#    identical output). xxhash.c is NOT included: zstd leaves XXH64 undefined and
#    it is resolved at final link from the lz4 object (which DOES include xxhash.c).
#    This avoids XXH* symbol clashes when linking lz4lib + ZSTDLib together.
#  - lz4: includes xxhash.c -> is the "owner" of the XXH* symbols (also used
#    by the xxhashlib unit).
#  - lzma: single-threaded (_7ZIP_ST, avoids needing Threads.c); LzFind.c is the
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
XXHASH_REF="e573d4d2aaeaba0f3e5a0a9a54144a1f2b4b56e7"

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
LZ4_REF="0774d05537f9762f838f7ab541b7765f1a729cb5"

pin_repo https://github.com/facebook/zstd "$CSRC/zstd" v1.5.2
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
pin_repo https://github.com/Cyan4973/xxHash "$CSRC/xxhash" "$XXHASH_REF"
if [ ! -d "$CSRC/lzma-sdk-ref" ]; then
  SEVENZ="$(command -v 7z || command -v 7za || true)"
  if [ -z "$SEVENZ" ]; then
    echo "ERROR: LZMA SDK sources missing and no 7z/7za found to extract them." >&2
    echo "       Install p7zip (e.g. 'apt install p7zip-full') or place the" >&2
    echo "       extracted SDK yourself at $CSRC/lzma-sdk-ref/C/*.c" >&2
    exit 1
  fi
  # Pinned to 19.00, not the current release: from 20.xx+ onward LzmaEnc.c
  # references MatchFinderMt_* unconditionally (needs LzFindMt.c/Threads.c
  # even under _7ZIP_ST); 19.00 still guards them with #ifndef _7ZIP_ST,
  # matching this single-threaded build.
  curl -sL -o "$CSRC/lzma-sdk.7z" https://www.7-zip.org/a/lzma1900.7z
  mkdir -p "$CSRC/lzma-sdk-ref"
  "$SEVENZ" x -y -o"$CSRC/lzma-sdk-ref" "$CSRC/lzma-sdk.7z" >/dev/null
fi

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
gcc -c -O2 -fPIC -I "$CSRC/lzma-sdk-ref/C" \
  -o LZMADelphi/lzmadelphi.linux.x64.o LZMADelphi/lzmadelphi.c

echo "OK: objetos Linux generados."
