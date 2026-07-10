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
#
# jojpeg_dll.dll is NOT built: no public/open source exists (like oodle).
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
CSRC="$(pwd)/.csrc"
ROOT="$(cd .. && pwd)"
mkdir -p "$CSRC"
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
echo "==> zlib1.dll (from source, zlib 1.3.1, i686)"
[ -d "$CSRC/zlib" ] || git clone --depth 1 --branch v1.3.1 https://github.com/madler/zlib.git "$CSRC/zlib"
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

# ── srep (external dedup -dd<N>) — Intensity/srep, with its own Win32 backend ──
# Same source/threading-shim setup as the win64 build (contrib/srep-win32/,
# see build-plugins-windows.sh's own comment for the why). i386-SPECIFIC BUG:
# Compression/SREP/hashes.cpp's CRC32 helper uses inline asm with a "rm"
# (register-or-memory) constraint on a uint8 operand -- safe on x86_64 (every
# GPR has a REX byte-addressable form) but not on i386, where only
# eax/ebx/ecx/edx have legacy 8-bit sub-registers (esi/edi/ebp/esp don't);
# GCC's i386 codegen fails with "unsupported size for integer register"
# (reported at the enclosing function due to inlining, not the true line).
# Fixed by narrowing the constraint to "qm" (byte-addressable registers
# only), applied as an idempotent sed patch below (checks before patching,
# safe to re-run).
echo "==> srep (srep-x86.exe)"
[ -d "$CSRC/srep" ] || git clone --depth 1 https://github.com/Intensity/srep "$CSRC/srep"
if [ -d "$CSRC/srep" ]; then
  cp "$ROOT/contrib/srep-win32/ThreadsWin32.h" "$ROOT/contrib/srep-win32/ThreadsWin32.c" \
    "$CSRC/srep/Compression/LZMA2/C/"
  cp "$ROOT/contrib/srep-win32/Handle.h" "$CSRC/srep/Compression/LZMA2/MultiThreading/"
  HASHES="$CSRC/srep/Compression/SREP/hashes.cpp"
  if grep -q '\[value\] "rm" (value)' "$HASHES" 2>/dev/null; then
    sed -i 's/\[value\] "rm" (value)/[value] "qm" (value)/' "$HASHES"
  fi
  ( cd "$CSRC/srep" && "$CXX" -O3 -std=c++17 \
    -I"$ROOT/contrib/mingw-shims" \
    -ICompression -ICompression/_Encryption -ICompression/_Encryption/headers -ICompression/_Encryption/hashes \
    -DFREEARC_WIN -DFREEARC_INTEL_BYTE_ORDER -D_FILE_OFFSET_BITS=64 -DUNICODE -D_UNICODE \
    -Wno-write-strings -Wno-unused-result \
    Compression/Common.cpp Compression/SREP/srep.cpp \
    -static-libgcc -static-libstdc++ -lole32 -luuid -o "$ROOT/srep-x86.exe" ) \
    && echo "   OK -> srep-x86.exe" || echo "   (srep fallo)"
fi

# ── lzo2 (lzo1x/lzo1c/lzo2a codec) — official Oberhumer tarball ───────────────
echo "==> lzo2 (lzo2-x86.dll)"
if [ ! -d "$CSRC/lzo-2.10" ]; then
  curl -sL https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz \
    -o "$CSRC/lzo-2.10.tar.gz" && tar xzf "$CSRC/lzo-2.10.tar.gz" -C "$CSRC"
fi
[ -d "$CSRC/lzo-2.10" ] && ( cd "$CSRC/lzo-2.10" && "$CC" -shared -O2 -Iinclude \
  -Wl,--export-all-symbols src/*.c -static-libgcc -o "$ROOT/lzo2-x86.dll" ) \
  && echo "   OK -> lzo2-x86.dll" || echo "   (lzo2 fallo)"

# ── packjpg (JPEG media codec) — user's fork v4.0e ──────────────────────
echo "==> packjpg (packjpg_dll-x86.dll)"
[ -d "$CSRC/packJPG" ] || git clone --depth 1 https://github.com/YadeWira/packJPG "$CSRC/packJPG"
( cd "$CSRC/packJPG" && "$CXX" -O3 -std=c++17 -DBUILD_DLL -Wl,--export-all-symbols \
  source/aricoder.cpp source/bitops.cpp source/packjpg.cpp -shared \
  -static-libgcc -static-libstdc++ -o "$ROOT/packjpg_dll-x86.dll" ) \
  && echo "   OK -> packjpg_dll-x86.dll" || echo "   (packjpg fallo)"

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
echo "==> preflate (preflate_dll-x86.dll)"
[ -d "$CSRC/preflate" ] || git clone --depth 1 https://github.com/deus-libri/preflate "$CSRC/preflate"
if [ -d "$CSRC/preflate" ]; then
  cp "$ROOT/contrib/preflate_wrap.cpp" "$CSRC/preflate/preflate_wrap.cpp"
  ( cd "$CSRC/preflate"
    SRCS=$(ls preflate_*.cpp | grep -vE "preflate_dumper|preflate_unpack|preflate_checker|preflate_wrap")
    SRCS="$SRCS $(ls support/*.cpp | grep -vE "support_tests|filestream")"
    "$CXX" -shared -std=c++11 -O2 -Wl,--export-all-symbols \
      -include cstdint -include cstddef -include cstring -include cstdio \
      $SRCS preflate_wrap.cpp -static-libgcc -static-libstdc++ -o "$ROOT/preflate_dll-x86.dll"
  ) && echo "   OK -> preflate_dll-x86.dll" || echo "   (preflate fallo)"
fi

# ── fast-lzma2 (final internal LZMA2 compression, -l#) ─────────────────────────
echo "==> fast-lzma2 (fast-lzma2-x86.dll)"
[ -d "$CSRC/fast-lzma2" ] || git clone --depth 1 https://github.com/conor42/fast-lzma2 "$CSRC/fast-lzma2"
( cd "$CSRC/fast-lzma2" && "$CC" -shared -O2 -DFL2_DLL_EXPORT=1 -Wl,--export-all-symbols \
  *.c -static-libgcc -o "$ROOT/fast-lzma2-x86.dll" ) \
  && echo "   OK -> fast-lzma2-x86.dll" || echo "   (fast-lzma2 fallo)"
# (the x86_64-only asm decoder files, lzma_dec_x86_64.asm/.S, aren't matched
# by the *.c glob and are additionally guarded by 64-bit-only preprocessor
# checks in the C sources -- they never enter this 32-bit build.)

# ── packmp3 (MP3 media codec) — original packjpg/packMP3 v1.0g project ──────
echo "==> packmp3 (packmp3_dll-x86.dll)"
[ -d "$CSRC/packMP3" ] || git clone --depth 1 https://github.com/packjpg/packMP3 "$CSRC/packMP3"
( cd "$CSRC/packMP3" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -Wl,--export-all-symbols \
  source/aricoder.cpp source/bitops.cpp source/huffmp3.cpp source/packmp3.cpp \
  -shared -static-libgcc -static-libstdc++ -o "$ROOT/packmp3_dll-x86.dll" ) \
  && echo "   OK -> packmp3_dll-x86.dll" || echo "   (packmp3 fallo)"

# ── FLAC (lossless WAV media codec) ──────────────────────────────────────────
# Fresh out-win-x86 build dir -- do NOT reuse the win64 script's out-win/,
# which already has x86_64 CMakeCache state.
#
# -DWITH_ASM=OFF: disables libFLAC's legacy hand-written i386 asm routines
# (FLAC__CPU_IA32-gated), untested by upstream in years against a modern
# mingw toolchain -- a reasonable safety default for a first-time 32-bit
# build. NOTE this does NOT fix the one known limitation of this codec: a
# stream encoded by the WIN64 build fails to decode on win32 ("Error in the
# method 'flac'"), even though win32-encoded streams decode fine on win64,
# and same-architecture round-trips (32<->32, 64<->64) always work. Tried and
# ruled out: WITH_ASM=OFF on either side, and forcing -mfpmath=sse -msse2 on
# the win32 build to match x86-64's default FP precision -- neither changed
# the outcome. Root cause not identified; kept WITH_ASM=OFF anyway since it
# removes one class of legacy-asm risk even though it wasn't the cause here.
# See Known-Issues-and-Limitations wiki page.
echo "==> FLAC (libFLAC_dynamic-x86.dll)"
[ -d "$CSRC/flac" ] || git clone --depth 1 https://github.com/xiph/flac.git "$CSRC/flac"
if [ -d "$CSRC/flac" ] && command -v cmake >/dev/null; then
  ( cd "$CSRC/flac" && mkdir -p out-win-x86 && cd out-win-x86 && \
    cmake -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release \
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
[ -d "$CSRC/wavpack" ] || git clone --depth 1 https://github.com/dbry/WavPack.git "$CSRC/wavpack"
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

# ── brunsli (JPEG media codec, alternative to packjpg) — requires cmake ────────
echo "==> brunsli (brunsli-x86.dll)"
[ -d "$CSRC/brunsli" ] || git clone --depth 1 --recursive https://github.com/google/brunsli "$CSRC/brunsli"
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

# ── packpng (PNG/APNG/JNG/MNG codec) — sibling repo of ytool's author ───────
# Confirmed real: YadeWira/packPNG's own Makefile has win-x86/lib-win-x86
# targets (i686-w64-mingw32-g++, Rust i686-pc-windows-gnu for preflate-rs),
# and the v2.0b release ships packPNG-2.0b-win32-lib.zip with a genuine PE32
# (Intel i386) packpng-x86.dll -- verified with `file`, not a renamed x64 one.
echo "==> packpng (packpng-x86.dll)"
PACKPNG_VER="v2.0b"
if curl -sL "https://github.com/YadeWira/packPNG/releases/download/${PACKPNG_VER}/packPNG-2.0b-win32-lib.zip" \
  -o "$CSRC/packpng-lib-x86.zip" 2>/dev/null && [ -s "$CSRC/packpng-lib-x86.zip" ]; then
  ( cd "$CSRC" && unzip -oq packpng-lib-x86.zip packpng-x86.dll ) 2>/dev/null \
    && mv -f "$CSRC/packpng-x86.dll" "$ROOT/packpng-x86.dll" \
    && echo "   OK -> packpng-x86.dll (prebuilt $PACKPNG_VER, win32)" \
    || echo "   (packpng: extraccion fallo)"
else
  echo "   (packpng: descarga fallo)"
fi

echo "Hecho. srep-x86.exe + plugins -x86.dll en la raiz del repo (gitignored)."
echo "jojpeg_dll.dll NO se construye (sin fuente abierta conocida, como oodle)."
echo "Al empaquetar: renombrar cada uno quitando el sufijo -x86 junto al ytool.exe"
echo "de 32-bit (packpng-x86.dll -> packpng.dll, zlib1-x86.dll -> zlib1.dll, etc.),"
echo "NO junto al de 64-bit."
