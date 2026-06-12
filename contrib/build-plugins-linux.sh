#!/usr/bin/env bash
# Construye los plugins/codecs externos de ytool para Linux x86-64 desde fuente
# abierta y los deja como .so / binarios en la raiz del repo (junto al ejecutable
# xtool, que es el PluginsPath por defecto). Estos artefactos estan gitignored
# (regenerables). Distintos de contrib/build-native-linux.sh, que hace los objetos
# C estaticos (lz4/zstd/xxhash) enlazados dentro del binario.
#
# Fuentes se clonan a contrib/.csrc (gitignored). Requisitos: git, clang++/g++,
# cmake (para brunsli). Cada plugin es independiente: si una fuente no clona, se
# salta y sigue con las demas.
#
# LECCION FPC<->C: las libs con punto flotante intensivo (packjpg DCT, etc.) pueden
# disparar SIGFPE bajo FPC (que desenmascara las excepciones FPU). El fix vive en
# el lado Pascal (SetExceptionMask en el *DLL.pas correspondiente), no aqui.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CSRC="$ROOT/contrib/.csrc"
mkdir -p "$CSRC"
CXX="$(command -v clang++ || command -v g++)"

# ── srep (dedup -d / StoreDD) ────────────────────────────────────────────────
echo "==> srep"
[ -d "$CSRC/srep" ] || git clone --depth 1 https://github.com/Intensity/srep "$CSRC/srep"
( cd "$CSRC/srep" && make >/dev/null 2>&1 && cp bin/srep "$ROOT/srep64" ) \
  && echo "   OK -> srep64" || echo "   (srep fallo)"

# ── packjpg (codec media JPEG) — fork v4.0e del usuario ──────────────────────
echo "==> packjpg (libpackjpg.so)"
[ -d "$CSRC/packJPG" ] || git clone --depth 1 https://github.com/YadeWira/packJPG "$CSRC/packJPG"
( cd "$CSRC/packJPG" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -DBUILD_SO -fPIC \
  -fvisibility=hidden -shared -Wl,-soname,libpackjpg.so \
  source/aricoder.cpp source/bitops.cpp source/packjpg.cpp -s -lpthread \
  -o "$ROOT/libpackjpg.so" ) && echo "   OK -> libpackjpg.so" || echo "   (packjpg fallo)"

# ── preflate (mejora el codec zlib: reconstruye deflate de cualquier encoder) ─
echo "==> preflate (libpreflate.so)"
[ -d "$CSRC/preflate" ] || git clone --depth 1 https://github.com/deus-libri/preflate "$CSRC/preflate"
if [ -d "$CSRC/preflate" ]; then
  cp "$ROOT/contrib/preflate_wrap.cpp" "$CSRC/preflate/preflate_wrap.cpp"
  ( cd "$CSRC/preflate"
    SRCS=$(ls preflate_*.cpp | grep -vE "preflate_dumper|preflate_unpack|preflate_checker|preflate_wrap")
    SRCS="$SRCS $(ls support/*.cpp | grep -vE "support_tests|filestream")"
    "$CXX" -shared -fPIC -fvisibility=hidden -std=c++11 -O2 \
      -include cstdint -include cstddef -include cstring -include cstdio \
      $SRCS preflate_wrap.cpp -lpthread -o "$ROOT/libpreflate.so"
  ) && echo "   OK -> libpreflate.so" || echo "   (preflate fallo)"
fi

echo "Hecho. Plugins .so/srep64 en la raiz del repo (gitignored)."
