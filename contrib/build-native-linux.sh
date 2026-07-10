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

[ -d "$CSRC/zstd" ]   || git clone --depth 1 --branch v1.5.2 https://github.com/facebook/zstd.git "$CSRC/zstd"
[ -d "$CSRC/lz4" ]    || git clone --depth 1 https://github.com/lz4/lz4.git "$CSRC/lz4"
[ -d "$CSRC/xxhash" ] || git clone --depth 1 https://github.com/Cyan4973/xxHash.git "$CSRC/xxhash"
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
