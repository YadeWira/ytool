#!/usr/bin/env bash
# Cross-compiles ytool's external plugins/codecs for Windows x86-64 FROM LINUX
# via mingw-w64 (x86_64-w64-mingw32-gcc/g++) + cmake, and leaves them as .dll in the
# repo root. These artifacts are gitignored (regenerable). Sibling of
# contrib/build-plugins-linux.sh (same source, different compiler/output format).
#
# Requirements: git, mingw-w64 (x86_64-w64-mingw32-gcc/g++), cmake. Each plugin is
# independent: if a source fails to clone or the cross-compile fails, it is skipped and continues.
#
# LESSON MinGW: upstream headers (packjpg/packmp3/fast-lzma2) define their
# EXPORT/API macro with __declspec(dllexport) only under certain -D (BUILD_DLL, BUILD_LIB,
# FL2_DLL_EXPORT...); to avoid depending on each one being correctly wired, ALL
# plugin links add -Wl,--export-all-symbols (forces the PE export table
# even if the attribute is missing), except when they already use their own idiomatic -D (fast-lzma2).
# packMP3 in particular: its pmplib_* functions are INSIDE an #if defined(BUILD_LIB)
# in the .cpp (not just in the .h) -> you must pass -DBUILD_LIB or the code doesn't even compile.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CSRC="$ROOT/contrib/.csrc"
mkdir -p "$CSRC"

# Revisiones fijadas a lo que efectivamente se construyo y publico. Un tag se
# puede mover; un SHA no. Ver contrib/pin-repo.sh para por que el pin tiene
# que aplicarse tambien sobre un checkout que ya existe.
PREFLATE_REF="609eefaa96ac6c51d7b1a3fb29e0ed94d0f3623e"
FLZMA2_REF="756d1c9f0c5806873c6a4c9e59f270e3daf445c7"   # fast-lzma2-v1.2.0
FLAC_REF="b430c3a58b64b70642ab5c72c36084dd4083d165"
WAVPACK_REF="0a3e393c57cb835e24f47366894a045b84f02611"
BRUNSLI_REF="c18b9625ef045b0b89ebb4439ae2339e2160df71"   # master 2026-09-10 (no newer tag than v0.1, 2019)

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

# ── zlib1.dll — required at process startup, not optional ─────────────────────
# Unlike every other plugin here (loaded lazily via LoadLibrary, tolerant of being
# missing), zlib1.dll ends up as a hard load-time dependency of the exe (mORMot's
# SynZip.pas links against an external zlib on Win64 -- see its USEEXTZLIB
# conditional-compilation block); without a real zlib1.dll next to the binary the
# process fails to start at all (STATUS_DLL_NOT_FOUND). Previously this was a
# manually-provided DLL of undocumented origin (didn't match either mingw-w64
# host copy's size) -- built from source here instead, so it's reproducible.
# Confirmed drop-in compatible: exports a superset of what's actually used
# (inflate/inflateEnd/inflateInit2_/inflateReset/crc32/deflate/compress/uncompress
# etc.), verified with a real round-trip on the Windows VM.

# -- libzstd (-mzstd) ----------------------------------------------------------
# imports/ZSTDDLL.pas is all that -mzstd uses; the zstd objects compiled into
# ytool are not. Without a library of its own, Linux loaded the distro's
# libzstd.so.1 and Windows loaded nothing: no package shipped libzstd.dll, so
# -mzstd stored every stream literally there (measured on the v0.9.8 x64 zip).
#
# v1.6.0 because its output is the same as 1.5.7's in every case measured
# (264 of 264: 4 inputs x levels 1-22, checksum on and off, compress2 and
# compressCCtx), while 1.5.2 differs in 189. So .ytp files made against a
# distro 1.5.7 still restore, and .zst files from a current zstd reproduce.
# Own checkout: $CSRC/zstd stays at v1.5.2 for the compiled-in objects.
ZSTD_LIB_REF="916e8e70b33317d469a41ee837e47317807815c8"   # v1.6.0
echo "==> libzstd.dll (x86-64)"
pin_repo https://github.com/facebook/zstd "$CSRC/zstd-lib" "$ZSTD_LIB_REF"
# ZSTD_MULTITHREAD: frames the zstd CLI writes with its default one worker
# thread (-T1) need nbWorkers to be reproduced (see build-plugins-linux.sh).
( cd "$CSRC/zstd-lib/lib" && "$CC" -shared -O2 -DZSTD_DLL_EXPORT=1 -DZSTD_DISABLE_ASM \
    -DZSTD_MULTITHREAD \
    -I. -Icommon common/*.c compress/*.c decompress/*.c -static-libgcc -o "$ROOT/libzstd.dll" ) \
  && echo "   OK -> libzstd.dll" || echo "   (libzstd fallo)"

# ── liblz4.dll — sin esto los codecs -mlz4/-mlz4hc/-mlz4f estan MUERTOS en Windows ──
# imports/LZ4DLL.pas carga PluginsPath + 'liblz4.dll' (en Unix cae a
# liblz4.so.1 del sistema, por eso Linux nunca lo noto). Esa DLL no se
# construia en ningun lado ni viajaba en el paquete, asi que LZ4DLL.DLLLoaded
# era False y los tres codecs se reportaban no disponibles: ytool guardaba
# cada stream LZ4 literal y el round-trip pasaba igual, que es exactamente
# como se paso por alto. Verificado en Windows real: sin la DLL un .lz4 del
# CLI da .ytp de 312810 bytes (literal, mas grande que la entrada); con ella
# da 1599715 y round-trip bit-exacto, igual que Linux.
# --export-all-symbols porque lz4 solo marca dllexport bajo LZ4_DLL_EXPORT,
# que su propio build system define; compilando los .c sueltos no aplica.
echo "==> liblz4.dll (x86-64)"
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
if [ -d "$CSRC/lz4/lib" ]; then
  ( cd "$CSRC/lz4/lib" && "$CC" -shared -O2 -Wl,--export-all-symbols \
      lz4.c lz4hc.c lz4frame.c xxhash.c -static-libgcc -o "$ROOT/liblz4.dll" ) \
    && echo "   OK -> liblz4.dll" || echo "   (liblz4 fallo)"
fi

echo "==> zlib1.dll (from source, zlib 1.4)"
pin_repo https://github.com/madler/zlib "$CSRC/zlib" 99623ef7097352da7993ba614161fd6a311e046e   # v1.4: deflate output equal to 1.3.1 in 3888 of 3888 cases measured
if [ -d "$CSRC/zlib" ]; then
  ( cd "$CSRC/zlib" && rm -f *.o && "$CC" -c -O2 -DZLIB_DLL adler32.c compress.c crc32.c deflate.c \
      gzclose.c gzlib.c gzread.c gzwrite.c infback.c inffast.c inflate.c inftrees.c trees.c \
      uncompr.c zutil.c && \
    "$CC" -shared -O2 -o "$ROOT/zlib1.dll" *.o win32/zlib.def \
      -Wl,--out-implib,libzlib1.a -static-libgcc ) \
    && echo "   OK -> zlib1.dll" || echo "   (zlib1.dll fallo)"
fi

# srep is not part of this repository (SREP 3.93a is "All rights reserved";
# see THIRD_PARTY.md). Personal builds: github.com/YadeWira/srep-builds.

# ── lzo2 (lzo1x/lzo1c/lzo2a codec) — official Oberhumer tarball ───────────────
echo "==> lzo2 (lzo2.dll)"
fetch_lzo   # checked against its SHA-256 (pin-repo.sh)
[ -d "$CSRC/lzo-2.10" ] && ( cd "$CSRC/lzo-2.10" && "$CC" -shared -O2 -Iinclude \
  -Wl,--export-all-symbols src/*.c -static-libgcc -o "$ROOT/lzo2.dll" ) \
  && echo "   OK -> lzo2.dll" || echo "   (lzo2 fallo)"

# ── PJA (JPEG, JPEG-LS, JPEG 2000) — replaces packJPG since 0.9.9a ──────────
# github.com/YadeWira/PJA (MIT), packJPG's successor: its own format, smaller
# and verified before it returns (pja_compress decodes its result and compares
# it; pja_decompress checks the stored size and BLAKE3 hash). Measured inside
# ytool on 78 real JPEGs: PJA takes 61 streams and writes 76.54% of the input,
# packJPG 5.0f 50 and 80.81%, brunsli 47 and 79.71%.
#
# The library is PJA's released build (FreePascal plus C), downloaded and
# checked against the SHA-256 in that release's SHA256SUMS; the version is
# spelled once.
PJA_VER="0.9.14"
PJA_ASSET="pja-${PJA_VER}-lib-windows-x64.zip"
PJA_SHA256="a1529e2b5ff9884899de3b7852aef876e7f4d196c7770c9f8af21450a756b354"
echo "==> PJA (pja.dll)"
if curl -sfL -o "$CSRC/$PJA_ASSET" \
    "https://github.com/YadeWira/PJA/releases/download/v${PJA_VER}/$PJA_ASSET" \
  && echo "$PJA_SHA256  $CSRC/$PJA_ASSET" | sha256sum -c --status; then
  rm -rf "$CSRC/pja-lib" && mkdir -p "$CSRC/pja-lib" \
    && ( cd "$CSRC/pja-lib" && unzip -q -o "$CSRC/$PJA_ASSET" ) \
    && cp "$CSRC/pja-lib/pja-${PJA_VER}-lib-windows-x64/pja.dll" "$ROOT/pja.dll" \
    && echo "   OK -> pja.dll" || echo "   (PJA: no se pudo extraer)"
else
  rm -f "$CSRC/$PJA_ASSET"; echo "   (PJA: descarga fallida o SHA-256 distinto)"
fi

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
echo "==> preflate (preflate_dll.dll)"
pin_repo https://github.com/deus-libri/preflate "$CSRC/preflate" "$PREFLATE_REF"
if [ -d "$CSRC/preflate" ]; then
  cp "$ROOT/contrib/preflate_wrap.cpp" "$CSRC/preflate/preflate_wrap.cpp"
  # Unsynchronized check-then-init data race in upstream task_pool.h, patched
  # the same way here as in build-plugins-linux.sh (see its comment for the
  # full rationale) -- std::call_once instead of a lockless `if (_state ==
  # INIT) _init();`.
  grep -q "_onceInit" "$CSRC/preflate/support/task_pool.h" || perl -0777 -pi -e '
    s/if \(_state == INIT\) \{\s*\n\s*_init\(\);\s*\n\s*\}/std::call_once(_onceInit, [this] { _init(); });/;
    s/(std::queue<std::function<void\(\)>> _tasks;)/$1\n  std::once_flag _onceInit;/;
  ' "$CSRC/preflate/support/task_pool.h"
  ( cd "$CSRC/preflate"
    SRCS=$(ls preflate_*.cpp | grep -vE "preflate_dumper|preflate_unpack|preflate_checker|preflate_wrap")
    SRCS="$SRCS $(ls support/*.cpp | grep -vE "support_tests|filestream")"
    "$CXX" -shared -std=c++11 -O2 -Wl,--export-all-symbols \
      -include cstdint -include cstddef -include cstring -include cstdio \
      $SRCS preflate_wrap.cpp -static-libgcc -static-libstdc++ -o "$ROOT/preflate_dll.dll"
  ) && echo "   OK -> preflate_dll.dll" || echo "   (preflate fallo)"
fi

# ── fast-lzma2 (final internal LZMA2 compression, -l#) ─────────────────────────
# From YadeWira/ultra-fast-lzma2, the maintained fork (conor42/fast-lzma2 is
# frozen). Its fast-lzma2/ folder is the FL2_* library ytool loads; the uf-lzma2
# line at the repo root has a renamed UF2_* API and is not used. 1.2.0 keeps
# the compressed bytes of every level, so .ytp files are unchanged.
echo "==> fast-lzma2 (fast-lzma2.dll)"
pin_repo https://github.com/YadeWira/ultra-fast-lzma2 "$CSRC/ultra-fast-lzma2" "$FLZMA2_REF"
# FL2_DLL_EXPORT marks the FL2_* API dllexport, so only that is exported.
( cd "$CSRC/ultra-fast-lzma2/fast-lzma2" && \
  "$CC" -c -DMS_x64_CALL=1 lzma_dec_x86_64.S -o lzma_dec_x86_64.o && \
  "$CC" -shared -O2 -DFL2_DLL_EXPORT=1 -DLZMA2_DEC_OPT \
  *.c lzma_dec_x86_64.o -static-libgcc -o "$ROOT/fast-lzma2.dll" ) \
  && echo "   OK -> fast-lzma2.dll" || echo "   (fast-lzma2 fallo)"

# ── FLAC (lossless WAV media codec) ──────────────────────────────────────────
echo "==> FLAC (libFLAC_dynamic.dll)"
pin_repo https://github.com/xiph/flac "$CSRC/flac" "$FLAC_REF"
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

# ── WavPack (lossless WAV media codec, alternative to FLAC) ───────────────────
echo "==> WavPack (wavpackdll.dll)"
pin_repo https://github.com/dbry/WavPack "$CSRC/wavpack" "$WAVPACK_REF"
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

# ── brunsli (JPEG media codec, alternative to PJA) — requires cmake ────────
echo "==> brunsli (brunsli.dll)"
pin_repo https://github.com/google/brunsli "$CSRC/brunsli" "$BRUNSLI_REF"
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


# libdeflate (-mlibdeflate), pinned in pin-repo.sh
build_libdeflate "$ROOT/libdeflate.dll" "$CC" -DLIBDEFLATE_DLL -static-libgcc

# lzlib (-mlzip), pinned in pin-repo.sh
build_lzlib "$ROOT/lzlib.dll" "$CC" -Wl,--export-all-symbols -static-libgcc

# OSREP (-ddo), released binary, next to ytool
fetch_osrep osrep-windows-x86_64.exe "$ROOT/osrep.exe"

echo "Hecho. Plugins .dll en la raiz del repo (gitignored)."
