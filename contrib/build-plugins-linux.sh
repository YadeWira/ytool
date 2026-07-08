#!/usr/bin/env bash
# Construye los plugins/codecs externos de ytool para Linux x86-64 desde fuente
# abierta y los deja como .so / binarios en la raiz del repo (junto al ejecutable
# ytool, que es el PluginsPath por defecto). Estos artefactos estan gitignored
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

# ── fast-lzma2 (compresion LZMA2 final interna, -l#) ─────────────────────────
echo "==> fast-lzma2 (libfast-lzma2.so)"
[ -d "$CSRC/fast-lzma2" ] || git clone --depth 1 https://github.com/conor42/fast-lzma2 "$CSRC/fast-lzma2"
( cd "$CSRC/fast-lzma2" && CC="$(command -v gcc || command -v clang)" && \
  "$CC" -shared -fPIC -O2 *.c -lpthread -o "$ROOT/libfast-lzma2.so" ) \
  && echo "   OK -> libfast-lzma2.so" || echo "   (fast-lzma2 fallo)"

# ── brunsli (codec media JPEG alternativo a packjpg) — requiere cmake ────────
echo "==> brunsli (libbrunsli.so)"
[ -d "$CSRC/brunsli" ] || git clone --depth 1 --recursive https://github.com/google/brunsli "$CSRC/brunsli"
if [ -d "$CSRC/brunsli" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/brunsli" && mkdir -p out && cd out && \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. >/dev/null 2>&1 && \
    make -j4 >/dev/null 2>&1 )
  A="$CSRC/brunsli/out/artifacts"; BR="$CSRC/brunsli/out/_deps/brotli-build"
  "$CXX" -shared -fPIC -fvisibility=hidden -std=c++11 -O2 -I "$CSRC/brunsli/c/include" \
    "$ROOT/contrib/brunsli_wrap.cpp" -Wl,--start-group \
    "$A/libbrunslienc-static.a" "$A/libbrunslidec-static.a" "$A/libbrunslicommon-static.a" \
    "$BR/libbrotlienc-static.a" "$BR/libbrotlidec-static.a" "$BR/libbrotlicommon-static.a" \
    -Wl,--end-group -o "$ROOT/libbrunsli.so" \
    && echo "   OK -> libbrunsli.so" || echo "   (brunsli link fallo)"
else
  echo "   (brunsli: falta cmake o el clone)"
fi

# ── packmp3 (codec media MP3) — proyecto original packjpg/packMP3 v1.0g ──────
echo "==> packmp3 (libpackmp3.so)"
[ -d "$CSRC/packMP3" ] || git clone --depth 1 https://github.com/packjpg/packMP3 "$CSRC/packMP3"
if [ -d "$CSRC/packMP3" ]; then
  # el upstream solo da C-linkage para BUILD_DLL/Windows; parche para Linux .so
  sed -i 's/#define EXPORT extern$/#define EXPORT extern "C"/' "$CSRC/packMP3/source/packmp3lib.h"
  ( cd "$CSRC/packMP3" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -fPIC -shared \
    source/aricoder.cpp source/bitops.cpp source/huffmp3.cpp source/packmp3.cpp \
    -lpthread -o "$ROOT/libpackmp3.so" ) \
    && echo "   OK -> libpackmp3.so" || echo "   (packmp3 fallo)"
fi

echo "Hecho. Plugins .so/srep64 en la raiz del repo (gitignored)."
