#!/usr/bin/env bash
# Cross-compila los plugins/codecs externos de ytool para Windows x86-64 DESDE LINUX
# via mingw-w64 (x86_64-w64-mingw32-gcc/g++) + cmake, y los deja como .dll en la raiz
# del repo. Estos artefactos estan gitignored (regenerables). Hermano de
# contrib/build-plugins-linux.sh (misma fuente, distinto compilador/formato de salida).
#
# Requisitos: git, mingw-w64 (x86_64-w64-mingw32-gcc/g++), cmake. Cada plugin es
# independiente: si una fuente no clona o el cross-compile falla, se salta y sigue.
#
# jojpeg_dll.dll NO se construye: no existe fuente publica/abierta de jojpeg (como
# oodle), asi que ese codec queda dormido en el build Windows tambien.
#
# LECCION MinGW: los headers upstream (packjpg/packmp3/fast-lzma2) definen su macro
# EXPORT/API con __declspec(dllexport) solo bajo ciertos -D (BUILD_DLL, BUILD_LIB,
# FL2_DLL_EXPORT...); para no depender de que cada uno este bien cableado, TODOS los
# links de plugin agregan -Wl,--export-all-symbols (fuerza la tabla de exportacion PE
# aunque falte el atributo), salvo que ya usen su propio -D idiomatico (fast-lzma2).
# packMP3 en particular: sus funciones pmplib_* estan DENTRO de un #if defined(BUILD_LIB)
# en el .cpp (no solo en el .h) -> hay que pasar -DBUILD_LIB o el codigo ni se compila.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CSRC="$ROOT/contrib/.csrc"
mkdir -p "$CSRC"
CC="x86_64-w64-mingw32-gcc"
CXX="x86_64-w64-mingw32-g++"
TOOLCHAIN="$CSRC/mingw-toolchain.cmake"
command -v "$CC" >/dev/null || { echo "falta mingw-w64 ($CC); nada que hacer"; exit 0; }

cat > "$TOOLCHAIN" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

# ── lzo2 (codec lzo1x/lzo1c/lzo2a) — tarball oficial Oberhumer ───────────────
echo "==> lzo2 (lzo2.dll)"
if [ ! -d "$CSRC/lzo-2.10" ]; then
  curl -sL https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz \
    -o "$CSRC/lzo-2.10.tar.gz" && tar xzf "$CSRC/lzo-2.10.tar.gz" -C "$CSRC"
fi
[ -d "$CSRC/lzo-2.10" ] && ( cd "$CSRC/lzo-2.10" && "$CC" -shared -O2 -Iinclude \
  -Wl,--export-all-symbols src/*.c -static-libgcc -o "$ROOT/lzo2.dll" ) \
  && echo "   OK -> lzo2.dll" || echo "   (lzo2 fallo)"

# ── packjpg (codec media JPEG) — fork v4.0e del usuario ──────────────────────
echo "==> packjpg (packjpg_dll.dll)"
[ -d "$CSRC/packJPG" ] || git clone --depth 1 https://github.com/YadeWira/packJPG "$CSRC/packJPG"
( cd "$CSRC/packJPG" && "$CXX" -O3 -std=c++17 -DBUILD_DLL -Wl,--export-all-symbols \
  source/aricoder.cpp source/bitops.cpp source/packjpg.cpp -shared \
  -static-libgcc -static-libstdc++ -o "$ROOT/packjpg_dll.dll" ) \
  && echo "   OK -> packjpg_dll.dll" || echo "   (packjpg fallo)"

# ── preflate (mejora el codec zlib: reconstruye deflate de cualquier encoder) ─
echo "==> preflate (preflate_dll.dll)"
[ -d "$CSRC/preflate" ] || git clone --depth 1 https://github.com/deus-libri/preflate "$CSRC/preflate"
if [ -d "$CSRC/preflate" ]; then
  cp "$ROOT/contrib/preflate_wrap.cpp" "$CSRC/preflate/preflate_wrap.cpp"
  ( cd "$CSRC/preflate"
    SRCS=$(ls preflate_*.cpp | grep -vE "preflate_dumper|preflate_unpack|preflate_checker|preflate_wrap")
    SRCS="$SRCS $(ls support/*.cpp | grep -vE "support_tests|filestream")"
    "$CXX" -shared -std=c++11 -O2 -Wl,--export-all-symbols \
      -include cstdint -include cstddef -include cstring -include cstdio \
      $SRCS preflate_wrap.cpp -static-libgcc -static-libstdc++ -o "$ROOT/preflate_dll.dll"
  ) && echo "   OK -> preflate_dll.dll" || echo "   (preflate fallo)"
fi

# ── fast-lzma2 (compresion LZMA2 final interna, -l#) ─────────────────────────
echo "==> fast-lzma2 (fast-lzma2.dll)"
[ -d "$CSRC/fast-lzma2" ] || git clone --depth 1 https://github.com/conor42/fast-lzma2 "$CSRC/fast-lzma2"
( cd "$CSRC/fast-lzma2" && "$CC" -shared -O2 -DFL2_DLL_EXPORT=1 -Wl,--export-all-symbols \
  *.c -static-libgcc -o "$ROOT/fast-lzma2.dll" ) \
  && echo "   OK -> fast-lzma2.dll" || echo "   (fast-lzma2 fallo)"

# ── packmp3 (codec media MP3) — proyecto original packjpg/packMP3 v1.0g ──────
echo "==> packmp3 (packmp3_dll.dll)"
[ -d "$CSRC/packMP3" ] || git clone --depth 1 https://github.com/packjpg/packMP3 "$CSRC/packMP3"
( cd "$CSRC/packMP3" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -Wl,--export-all-symbols \
  source/aricoder.cpp source/bitops.cpp source/huffmp3.cpp source/packmp3.cpp \
  -shared -static-libgcc -static-libstdc++ -o "$ROOT/packmp3_dll.dll" ) \
  && echo "   OK -> packmp3_dll.dll" || echo "   (packmp3 fallo)"

# ── FLAC (codec media WAV lossless) ──────────────────────────────────────────
echo "==> FLAC (libFLAC_dynamic.dll)"
[ -d "$CSRC/flac" ] || git clone --depth 1 https://github.com/xiph/flac.git "$CSRC/flac"
if [ -d "$CSRC/flac" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/flac" && mkdir -p out-win && cd out-win && \
    cmake -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON -DBUILD_CXXLIBS=OFF -DBUILD_PROGRAMS=OFF \
      -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DBUILD_DOCS=OFF -DWITH_OGG=OFF \
      -DINSTALL_MANPAGES=OFF -DINSTALL_PKGCONFIG_MODULES=OFF \
      -DINSTALL_CMAKE_CONFIG_MODULE=OFF -DENABLE_MULTITHREADING=OFF \
      -DWITH_FORTIFY_SOURCE=OFF -DWITH_STACK_PROTECTOR=OFF .. >/dev/null 2>&1 && \
    make -j4 >/dev/null 2>&1 )
  DLL=$(find "$CSRC/flac/out-win" -iname "libFLAC.dll" | head -1)
  [ -n "$DLL" ] && cp "$DLL" "$ROOT/libFLAC_dynamic.dll" \
    && echo "   OK -> libFLAC_dynamic.dll" || echo "   (FLAC fallo)"
else
  echo "   (FLAC: falta cmake o el clone)"
fi

# ── WavPack (codec media WAV lossless, alternativa a FLAC) ───────────────────
echo "==> WavPack (wavpackdll.dll)"
[ -d "$CSRC/wavpack" ] || git clone --depth 1 https://github.com/dbry/WavPack.git "$CSRC/wavpack"
if [ -d "$CSRC/wavpack" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/wavpack" && mkdir -p out-win && cd out-win && \
    cmake -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON -DWAVPACK_BUILD_PROGRAMS=OFF -DBUILD_TESTING=OFF \
      -DWAVPACK_INSTALL_DOCS=OFF -DWAVPACK_ENABLE_THREADS=OFF .. >/dev/null 2>&1 && \
    make -j4 >/dev/null 2>&1 )
  DLL=$(find "$CSRC/wavpack/out-win" -iname "libwavpack*.dll" | head -1)
  [ -n "$DLL" ] && cp "$DLL" "$ROOT/wavpackdll.dll" \
    && echo "   OK -> wavpackdll.dll" || echo "   (WavPack fallo)"
else
  echo "   (WavPack: falta cmake o el clone)"
fi

# ── brunsli (codec media JPEG alternativo a packjpg) — requiere cmake ────────
echo "==> brunsli (brunsli.dll)"
[ -d "$CSRC/brunsli" ] || git clone --depth 1 --recursive https://github.com/google/brunsli "$CSRC/brunsli"
if [ -d "$CSRC/brunsli" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/brunsli" && mkdir -p out-win && cd out-win && \
    cmake -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. >/dev/null 2>&1 && \
    make -j4 brunslienc-static brunslidec-static brunslicommon-static \
      brotlienc-static brotlidec-static brotlicommon-static >/dev/null 2>&1 )
  A="$CSRC/brunsli/out-win/artifacts"; BR="$CSRC/brunsli/out-win/_deps/brotli-build"
  "$CXX" -shared -std=c++11 -O2 -Wl,--export-all-symbols -I "$CSRC/brunsli/c/include" \
    "$ROOT/contrib/brunsli_wrap.cpp" -Wl,--start-group \
    "$A/libbrunslienc-static.a" "$A/libbrunslidec-static.a" "$A/libbrunslicommon-static.a" \
    "$BR/libbrotlienc-static.a" "$BR/libbrotlidec-static.a" "$BR/libbrotlicommon-static.a" \
    -Wl,--end-group -static-libgcc -static-libstdc++ -o "$ROOT/brunsli.dll" \
    && echo "   OK -> brunsli.dll" || echo "   (brunsli link fallo)"
else
  echo "   (brunsli: falta cmake o el clone)"
fi

echo "Hecho. Plugins .dll en la raiz del repo (gitignored)."
echo "jojpeg_dll.dll NO se construye (sin fuente abierta conocida, como oodle)."
