#!/usr/bin/env bash
# Reconstruye los objetos C nativos (lz4/zstd) para Linux x86-64 (Opcion C de la
# migracion a FPC). Salida: contrib/{LZ4Delphi,ZSTD4Delphi}/*.linux.x64.o
#
# Fuentes esperadas en contrib/.csrc (gitignored). Si no estan, se clonan:
#   zstd v1.5.2 (debe coincidir con ZSTD_VERSION_STRING en ZSTDLib.pas)
#   lz4  (release reciente)
#
# Notas clave:
#  - zstd: -DZSTD_DISABLE_ASM (evita los .S de huf_decompress; usa fallback C,
#    salida identica). NO se incluye xxhash.c: zstd deja XXH64 sin definir y se
#    resuelve al enlace final desde el objeto de lz4 (que SI incluye xxhash.c).
#    Asi se evita el choque de simbolos XXH* al enlazar lz4lib + ZSTDLib juntos.
#  - lz4: incluye xxhash.c -> es el "dueno" de los simbolos XXH* (usados tambien
#    por la unidad xxhashlib).
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
CSRC="$(pwd)/.csrc"
mkdir -p "$CSRC"

[ -d "$CSRC/zstd" ] || git clone --depth 1 --branch v1.5.2 https://github.com/facebook/zstd.git "$CSRC/zstd"
[ -d "$CSRC/lz4" ]  || git clone --depth 1 https://github.com/lz4/lz4.git "$CSRC/lz4"

echo "==> zstd4delphi.linux.x64.o"
gcc -c -O2 -fPIC -DZSTD_DISABLE_ASM \
  -I "$CSRC/zstd/lib" -I "$CSRC/zstd/lib/common" \
  -I "$CSRC/zstd/lib/compress" -I "$CSRC/zstd/lib/decompress" \
  -o ZSTD4Delphi/zstd4delphi.linux.x64.o ZSTD4Delphi/zstd4delphi.c

echo "==> lz4delphi.linux.x64.o"
cat > "$CSRC/lz4delphi_lin.c" <<'EOF'
#include "lz4.c"
#include "lz4hc.c"
#include "lz4frame.c"
#include "xxhash.c"
EOF
gcc -c -O2 -fPIC -I "$CSRC/lz4/lib" \
  -o LZ4Delphi/lz4delphi.linux.x64.o "$CSRC/lz4delphi_lin.c"

echo "OK: objetos Linux generados."
