#!/usr/bin/env bash
# Cross-compiles/downloads ytool's external plugins/codecs for Windows x86
# (i386, 32-bit) FROM LINUX via mingw-w64 (i686-w64-mingw32-gcc/g++) + cmake,
# and leaves them as -x86-suffixed .dll/.exe in the repo root (gitignored,
# regenerable). i686 sibling of build-plugins-windows.sh -- same sources,
# same flags, just the 32-bit cross-compiler. Read that script's own comments
# first (LESSON MinGW, packMP3's BUILD_LIB requirement, etc.) since they all
# apply here unchanged; only genuinely 32-bit-specific gotchas are repeated
# below.
#
# Requirements: git, mingw-w64 (i686-w64-mingw32-gcc/g++/windres), cmake.
# Each plugin is independent: if a source fails to clone or the cross-compile
# fails, it is skipped and the script continues with the rest.
#
# Every codec here is loaded at runtime via LoadLibrary (imports/*.pas +
# TLibImport) -- if a given plugin has no win32 build, that codec just
# reports unavailable, same as an already-missing .dll does on the win64
# build today. zlib1.dll is the one exception: it's a hard load-time
# dependency (see its own step below), not lazily loaded.
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
CSRC="$(pwd)/.csrc"
ROOT="$(cd .. && pwd)"
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
CC=i686-w64-mingw32-gcc
CXX=i686-w64-mingw32-g++
TOOLCHAIN="$CSRC/mingw-toolchain-x86.cmake"
command -v "$CC" >/dev/null || { echo "falta mingw-w64 i686 ($CC); nada que hacer"; exit 0; }

cat > "$TOOLCHAIN" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86)
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_RC_COMPILER i686-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH /usr/i686-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

# ── zlib1.dll — required at process startup, not optional (see the win64 ──────
# script's comment on the same step for why). i686 sibling of that build.

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
echo "==> libzstd.dll (i686)"
pin_repo https://github.com/facebook/zstd "$CSRC/zstd-lib" "$ZSTD_LIB_REF"
( cd "$CSRC/zstd-lib/lib" && "$CC" -shared -O2 -DZSTD_DLL_EXPORT=1 -DZSTD_DISABLE_ASM \
    -I. -Icommon common/*.c compress/*.c decompress/*.c -static-libgcc -o "$ROOT/libzstd-x86.dll" ) \
  && echo "   OK -> libzstd-x86.dll" || echo "   (libzstd fallo)"

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
echo "==> liblz4.dll (i686)"
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
if [ -d "$CSRC/lz4/lib" ]; then
  ( cd "$CSRC/lz4/lib" && "$CC" -shared -O2 -Wl,--export-all-symbols \
      lz4.c lz4hc.c lz4frame.c xxhash.c -static-libgcc -o "$ROOT/liblz4-x86.dll" ) \
    && echo "   OK -> liblz4-x86.dll" || echo "   (liblz4 fallo)"
fi

echo "==> zlib1.dll (from source, zlib 1.4, i686)"
pin_repo https://github.com/madler/zlib "$CSRC/zlib" 99623ef7097352da7993ba614161fd6a311e046e   # v1.4: deflate output equal to 1.3.1 in 3888 of 3888 cases measured
if [ -d "$CSRC/zlib" ]; then
  ( cd "$CSRC/zlib" && rm -f *.o && "$CC" -c -O2 -DZLIB_DLL adler32.c compress.c crc32.c deflate.c \
      gzclose.c gzlib.c gzread.c gzwrite.c infback.c inffast.c inflate.c inftrees.c trees.c \
      uncompr.c zutil.c && \
    "$CC" -shared -O2 -o "$ROOT/zlib1-x86.dll" *.o win32/zlib.def \
      -Wl,--out-implib,libzlib1-x86.a -static-libgcc ) \
    && echo "   OK -> zlib1-x86.dll (rename to zlib1.dll next to the win32 ytool.exe," \
    && echo "         NOT the win64 one)" \
    || echo "   (zlib1-x86.dll fallo)"
fi

# srep is not part of this repository (SREP 3.93a is "All rights reserved";
# see THIRD_PARTY.md). Personal builds: github.com/YadeWira/srep-builds.

# ── lzo2 (lzo1x/lzo1c/lzo2a codec) — official Oberhumer tarball ───────────────
echo "==> lzo2 (lzo2-x86.dll)"
if [ ! -d "$CSRC/lzo-2.10" ]; then
  curl -sL https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz \
    -o "$CSRC/lzo-2.10.tar.gz" && tar xzf "$CSRC/lzo-2.10.tar.gz" -C "$CSRC"
fi
[ -d "$CSRC/lzo-2.10" ] && ( cd "$CSRC/lzo-2.10" && "$CC" -shared -O2 -Iinclude \
  -Wl,--export-all-symbols src/*.c -static-libgcc -o "$ROOT/lzo2-x86.dll" ) \
  && echo "   OK -> lzo2-x86.dll" || echo "   (lzo2 fallo)"

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
PJA_ASSET="pja-${PJA_VER}-lib-windows-x86.zip"
PJA_SHA256="36a3bde0e0546cb5de65a765ed4f51f028a108515b907682eed3b1c0c14ba4ac"
echo "==> PJA (pja-x86.dll)"
if curl -sfL -o "$CSRC/$PJA_ASSET" \
    "https://github.com/YadeWira/PJA/releases/download/v${PJA_VER}/$PJA_ASSET" \
  && echo "$PJA_SHA256  $CSRC/$PJA_ASSET" | sha256sum -c --status; then
  rm -rf "$CSRC/pja-lib" && mkdir -p "$CSRC/pja-lib" \
    && ( cd "$CSRC/pja-lib" && unzip -q -o "$CSRC/$PJA_ASSET" ) \
    && cp "$CSRC/pja-lib/pja-${PJA_VER}-lib-windows-x86/pja.dll" "$ROOT/pja-x86.dll" \
    && echo "   OK -> pja-x86.dll" || echo "   (PJA: no se pudo extraer)"
else
  rm -f "$CSRC/$PJA_ASSET"; echo "   (PJA: descarga fallida o SHA-256 distinto)"
fi

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
echo "==> preflate (preflate_dll-x86.dll)"
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
      $SRCS preflate_wrap.cpp -static-libgcc -static-libstdc++ -o "$ROOT/preflate_dll-x86.dll"
  ) && echo "   OK -> preflate_dll-x86.dll" || echo "   (preflate fallo)"
fi

# ── fast-lzma2 (final internal LZMA2 compression, -l#) ─────────────────────────
# From YadeWira/ultra-fast-lzma2, the maintained fork (conor42/fast-lzma2 is
# frozen). Its fast-lzma2/ folder is the FL2_* library ytool loads; the uf-lzma2
# line at the repo root has a renamed UF2_* API and is not used. 1.2.0 keeps
# the compressed bytes of every level, so .ytp files are unchanged.
echo "==> fast-lzma2 (fast-lzma2-x86.dll)"
pin_repo https://github.com/YadeWira/ultra-fast-lzma2 "$CSRC/ultra-fast-lzma2" "$FLZMA2_REF"
# FL2_DLL_EXPORT marks the FL2_* API dllexport, so only that is exported.
( cd "$CSRC/ultra-fast-lzma2/fast-lzma2" && "$CC" -shared -O2 -DFL2_DLL_EXPORT=1 \
  *.c -static-libgcc -o "$ROOT/fast-lzma2-x86.dll" ) \
  && echo "   OK -> fast-lzma2-x86.dll" || echo "   (fast-lzma2 fallo)"
# (the x86_64-only asm decoder files, lzma_dec_x86_64.asm/.S, aren't matched
# by the *.c glob and are additionally guarded by 64-bit-only preprocessor
# checks in the C sources -- they never enter this 32-bit build.)

# ── FLAC (lossless WAV media codec) ──────────────────────────────────────────
# Fresh out-win-x86 build dir -- do NOT reuse the win64 script's out-win/,
# which already has x86_64 CMakeCache state.
#
# -DWITH_ASM=OFF: disables libFLAC's legacy hand-written i386 asm routines
# (FLAC__CPU_IA32-gated), untested by upstream in years against a modern
# mingw toolchain -- a reasonable safety default for a first-time 32-bit
# build.
#
# -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc" is the REAL fix for what was
# originally logged as a mysterious cross-architecture decode failure: the
# resulting libFLAC.dll dynamically linked against libgcc_s_dw2-1.dll (i686's
# DW2 unwinder, needed for GCC's exception-handling runtime) -- a DLL that
# ships with mingw-w64 itself but isn't part of any stock Windows install and
# wasn't bundled alongside the codec DLL. LoadLibrary failed with
# ERROR_MOD_NOT_FOUND (126), so FLACDLL.DLLLoaded was silently False on every
# 32-bit run -- ytool's own codec-unavailable fallback (store literally)
# masked this in same-architecture testing (looks reversible, just never
# really invokes FLAC at all), and only surfaced as a hard decode exception
# when asked to decode a stream a WORKING encoder (64-bit, whose mingw build
# happens not to need this DLL -- x86_64 uses Windows' native SEH instead of
# DW2) had genuinely FLAC-compressed. x86_64 was never affected (confirmed:
# libFLAC_dynamic.dll only imports KERNEL32/msvcrt, no libgcc_s_seh
# dependency), so this flag isn't needed in build-plugins-windows.sh.
echo "==> FLAC (libFLAC_dynamic-x86.dll)"
pin_repo https://github.com/xiph/flac "$CSRC/flac" "$FLAC_REF"
if [ -d "$CSRC/flac" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/flac" && mkdir -p out-win-x86 && cd out-win-x86 && \
    cmake -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SHARED_LINKER_FLAGS="-static-libgcc" \
      -DBUILD_SHARED_LIBS=ON -DBUILD_CXXLIBS=OFF -DBUILD_PROGRAMS=OFF \
      -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DBUILD_DOCS=OFF -DWITH_OGG=OFF \
      -DINSTALL_MANPAGES=OFF -DINSTALL_PKGCONFIG_MODULES=OFF \
      -DINSTALL_CMAKE_CONFIG_MODULE=OFF -DENABLE_MULTITHREADING=OFF \
      -DWITH_FORTIFY_SOURCE=OFF -DWITH_STACK_PROTECTOR=OFF -DWITH_ASM=OFF .. >/dev/null 2>&1 && \
    make -j4 >/dev/null 2>&1 )
  DLL=$(find "$CSRC/flac/out-win-x86" -iname "libFLAC.dll" | head -1)
  [ -n "$DLL" ] && cp "$DLL" "$ROOT/libFLAC_dynamic-x86.dll" \
    && echo "   OK -> libFLAC_dynamic-x86.dll" || echo "   (FLAC fallo)"
else
  echo "   (FLAC: falta cmake o el clone)"
fi

# ── WavPack (lossless WAV media codec, alternative to FLAC) ───────────────────
echo "==> WavPack (wavpackdll-x86.dll)"
pin_repo https://github.com/dbry/WavPack "$CSRC/wavpack" "$WAVPACK_REF"
if [ -d "$CSRC/wavpack" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/wavpack" && mkdir -p out-win-x86 && cd out-win-x86 && \
    cmake -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON -DWAVPACK_BUILD_PROGRAMS=OFF -DBUILD_TESTING=OFF \
      -DWAVPACK_INSTALL_DOCS=OFF -DWAVPACK_ENABLE_THREADS=OFF .. >/dev/null 2>&1 && \
    make -j4 >/dev/null 2>&1 )
  DLL=$(find "$CSRC/wavpack/out-win-x86" -iname "libwavpack*.dll" | head -1)
  [ -n "$DLL" ] && cp "$DLL" "$ROOT/wavpackdll-x86.dll" \
    && echo "   OK -> wavpackdll-x86.dll" || echo "   (WavPack fallo)"
else
  echo "   (WavPack: falta cmake o el clone)"
fi

# ── brunsli (JPEG media codec, alternative to PJA) — requires cmake ────────
echo "==> brunsli (brunsli-x86.dll)"
pin_repo https://github.com/google/brunsli "$CSRC/brunsli" "$BRUNSLI_REF"
if [ -d "$CSRC/brunsli" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/brunsli" && mkdir -p out-win-x86 && cd out-win-x86 && \
    cmake -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. >/dev/null 2>&1 && \
    make -j4 brunslienc-static brunslidec-static brunslicommon-static \
      brotlienc-static brotlidec-static brotlicommon-static >/dev/null 2>&1 )
  A="$CSRC/brunsli/out-win-x86/artifacts"; BR="$CSRC/brunsli/out-win-x86/_deps/brotli-build"
  "$CXX" -shared -std=c++11 -O2 -Wl,--export-all-symbols -I "$CSRC/brunsli/c/include" \
    "$ROOT/contrib/brunsli_wrap.cpp" -Wl,--start-group \
    "$A/libbrunslienc-static.a" "$A/libbrunslidec-static.a" "$A/libbrunslicommon-static.a" \
    "$BR/libbrotlienc-static.a" "$BR/libbrotlidec-static.a" "$BR/libbrotlicommon-static.a" \
    -Wl,--end-group -static-libgcc -static-libstdc++ -o "$ROOT/brunsli-x86.dll" \
    && echo "   OK -> brunsli-x86.dll" || echo "   (brunsli link fallo)"
else
  echo "   (brunsli: falta cmake o el clone)"
fi

echo "Hecho. Plugins -x86.dll en la raiz del repo (gitignored)."
echo "Al empaquetar: renombrar cada uno quitando el sufijo -x86 junto al ytool.exe"
echo "de 32-bit (pja-x86.dll -> pja.dll, zlib1-x86.dll -> zlib1.dll, etc.),"
echo "NO junto al de 64-bit."
