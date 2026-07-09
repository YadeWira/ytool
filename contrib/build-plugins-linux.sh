#!/usr/bin/env bash
# Builds ytool's external plugins/codecs for Linux x86-64 from open source
# and leaves them as .so / binaries in the repo root (next to the ytool
# executable, which is the default PluginsPath). These artifacts are gitignored
# (regenerable). Different from contrib/build-native-linux.sh, which builds the
# static C objects (lz4/zstd/xxhash) linked inside the binary.
#
# Sources are cloned to contrib/.csrc (gitignored). Requirements: git, clang++/g++,
# cmake (for brunsli). Each plugin is independent: if a source fails to clone, it
# is skipped and the rest continue.
#
# LESSON FPC<->C: libs with heavy floating point (packjpg DCT, etc.) can
# trigger SIGFPE under FPC (which unmasks FPU exceptions). The fix lives on
# the Pascal side (SetExceptionMask in the corresponding *DLL.pas), not here.
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

# ── packjpg (JPEG media codec) — user's fork v4.0e ──────────────────────
echo "==> packjpg (libpackjpg.so)"
[ -d "$CSRC/packJPG" ] || git clone --depth 1 https://github.com/YadeWira/packJPG "$CSRC/packJPG"
( cd "$CSRC/packJPG" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -DBUILD_SO -fPIC \
  -fvisibility=hidden -shared -Wl,-soname,libpackjpg.so \
  source/aricoder.cpp source/bitops.cpp source/packjpg.cpp -s -lpthread \
  -o "$ROOT/libpackjpg.so" ) && echo "   OK -> libpackjpg.so" || echo "   (packjpg fallo)"

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
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

# ── fast-lzma2 (final internal LZMA2 compression, -l#) ─────────────────────────
echo "==> fast-lzma2 (libfast-lzma2.so)"
[ -d "$CSRC/fast-lzma2" ] || git clone --depth 1 https://github.com/conor42/fast-lzma2 "$CSRC/fast-lzma2"
( cd "$CSRC/fast-lzma2" && CC="$(command -v gcc || command -v clang)" && \
  "$CC" -shared -fPIC -O2 *.c -lpthread -o "$ROOT/libfast-lzma2.so" ) \
  && echo "   OK -> libfast-lzma2.so" || echo "   (fast-lzma2 fallo)"

# ── brunsli (JPEG media codec, alternative to packjpg) — requires cmake ────────
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

# ── packmp3 (MP3 media codec) — original packjpg/packMP3 v1.0g project ──────
echo "==> packmp3 (libpackmp3.so)"
[ -d "$CSRC/packMP3" ] || git clone --depth 1 https://github.com/packjpg/packMP3 "$CSRC/packMP3"
if [ -d "$CSRC/packMP3" ]; then
  # upstream only gives C-linkage for BUILD_DLL/Windows; patch for Linux .so
  sed -i 's/#define EXPORT extern$/#define EXPORT extern "C"/' "$CSRC/packMP3/source/packmp3lib.h"
  ( cd "$CSRC/packMP3" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -fPIC -shared \
    source/aricoder.cpp source/bitops.cpp source/huffmp3.cpp source/packmp3.cpp \
    -lpthread -o "$ROOT/libpackmp3.so" ) \
    && echo "   OK -> libpackmp3.so" || echo "   (packmp3 fallo)"
fi

# ── packpng (PNG/APNG/JNG/MNG codec) — sibling repo of ytool's author ───────
# Building it from source requires Rust (cross-compile) + cmake for kanzi-cpp --
# much heavier than the rest of this script (only clang++/g++/cmake). Instead,
# the already-built .so is downloaded from a versioned packPNG release
# (same author, not an unknown third party) -- reproducible without a new toolchain.
echo "==> packpng (libpackpng.so)"
PACKPNG_VER="v2.0b"
if curl -sL "https://github.com/YadeWira/packPNG/releases/download/${PACKPNG_VER}/packPNG-2.0b-linux-x64-lib.tar.gz" \
  -o "$CSRC/packpng-lib.tar.gz" 2>/dev/null && [ -s "$CSRC/packpng-lib.tar.gz" ]; then
  tar -xzf "$CSRC/packpng-lib.tar.gz" -C "$CSRC" libpackpng.so 2>/dev/null \
    && mv -f "$CSRC/libpackpng.so" "$ROOT/libpackpng.so" \
    && echo "   OK -> libpackpng.so (prebuilt $PACKPNG_VER)" \
    || echo "   (packpng: extraccion fallo)"
else
  echo "   (packpng: descarga fallo)"
fi

echo "Hecho. Plugins .so/srep64 en la raiz del repo (gitignored)."
