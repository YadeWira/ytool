#!/usr/bin/env bash
# Cross-compiles ytool's external plugins/codecs for Windows x86-64 FROM LINUX
# via mingw-w64 (x86_64-w64-mingw32-gcc/g++) + cmake, and leaves them as .dll in the
# repo root. These artifacts are gitignored (regenerable). Sibling of
# contrib/build-plugins-linux.sh (same source, different compiler/output format).
#
# Requirements: git, mingw-w64 (x86_64-w64-mingw32-gcc/g++), cmake. Each plugin is
# independent: if a source fails to clone or the cross-compile fails, it is skipped and continues.
#
# jojpeg_dll.dll is NOT built: no public/open source exists for jojpeg (like
# oodle), so that codec also stays dormant in the Windows build.
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
echo "==> zlib1.dll (from source, zlib 1.3.1)"
[ -d "$CSRC/zlib" ] || git clone --depth 1 --branch v1.3.1 https://github.com/madler/zlib.git "$CSRC/zlib"
if [ -d "$CSRC/zlib" ]; then
  ( cd "$CSRC/zlib" && rm -f *.o && "$CC" -c -O2 -DZLIB_DLL adler32.c compress.c crc32.c deflate.c \
      gzclose.c gzlib.c gzread.c gzwrite.c infback.c inffast.c inflate.c inftrees.c trees.c \
      uncompr.c zutil.c && \
    "$CC" -shared -O2 -o "$ROOT/zlib1.dll" *.o win32/zlib.def \
      -Wl,--out-implib,libzlib1.a -static-libgcc ) \
    && echo "   OK -> zlib1.dll" || echo "   (zlib1.dll fallo)"
fi

# ── srep (external dedup -dd<N>) — Intensity/srep, with its own Win32 backend ──
# srep's threading API (Compression/LZMA2/C/ThreadsUnix.h) is the same one from
# 7-Zip's LZMA SDK (Igor Pavlov, public domain); the Windows side (ThreadsWin32.*)
# wasn't included in this fork (it kept only the Unix one), so it's added, adapted from
# the official LZMA SDK (contrib/srep-win32/). Handle.h is a stub: Synchronization.h
# includes it under #ifdef _WIN32 but no class in that file uses a "Handle" type.
# Also: -DUNICODE/-D_UNICODE (Common.h assumes TCHAR=wchar_t), -lole32 -luuid (COM,
# for the Windows 7 taskbar progress indicator, a feature irrelevant for a
# headless helper but still needs linking), and a case shim
# for <ShObjIdl.h> (mingw-w64 ships "shobjidl.h"; only matters on a case-sensitive FS
# like Linux, on real Windows it was never a problem).
# Also patches two inline-asm register-clobber bugs (hashes.cpp's CRC32 helper,
# vmac.c's nh_16_func/poly_step_func) that only strictly matter on i386 (see
# build-plugins-windows-x86.sh's own comment for the full story) but are applied
# here too for consistency/safety -- verified byte-identical x86_64 output
# before/after.
echo "==> srep (srep.exe)"
[ -d "$CSRC/srep" ] || git clone --depth 1 https://github.com/Intensity/srep "$CSRC/srep"
if [ -d "$CSRC/srep" ]; then
  cp "$ROOT/contrib/srep-win32/ThreadsWin32.h" "$ROOT/contrib/srep-win32/ThreadsWin32.c" \
    "$CSRC/srep/Compression/LZMA2/C/"
  cp "$ROOT/contrib/srep-win32/Handle.h" "$CSRC/srep/Compression/LZMA2/MultiThreading/"
  HASHES="$CSRC/srep/Compression/SREP/hashes.cpp"
  if ! grep -qF '[value] "qm" (value) : "cc"' "$HASHES" 2>/dev/null; then
    # Handles both a fresh clone ("rm", unpatched) and one patched by an
    # earlier version of this script that only did "rm"->"qm" without the
    # "cc" clobber -- whichever pattern isn't present is simply a no-op.
    sed -i 's/\[value\] "rm" (value)/[value] "qm" (value) : "cc"/' "$HASHES"
    sed -i 's/\[value\] "qm" (value));/[value] "qm" (value) : "cc");/' "$HASHES"
  fi
  VMAC="$CSRC/srep/Compression/_Encryption/hashes/vmac/vmac.c"
  [ -f "$VMAC" ] && python3 "$ROOT/contrib/patch_srep_vmac.py" "$VMAC"
  ( cd "$CSRC/srep" && "$CXX" -O3 -std=c++17 \
    -I"$ROOT/contrib/mingw-shims" \
    -ICompression -ICompression/_Encryption -ICompression/_Encryption/headers -ICompression/_Encryption/hashes \
    -DFREEARC_WIN -DFREEARC_INTEL_BYTE_ORDER -D_FILE_OFFSET_BITS=64 -DUNICODE -D_UNICODE \
    -Wno-write-strings -Wno-unused-result \
    Compression/Common.cpp Compression/SREP/srep.cpp \
    -static-libgcc -static-libstdc++ -lole32 -luuid -o "$ROOT/srep.exe" ) \
    && echo "   OK -> srep.exe" || echo "   (srep fallo)"
fi

# ── lzo2 (lzo1x/lzo1c/lzo2a codec) — official Oberhumer tarball ───────────────
echo "==> lzo2 (lzo2.dll)"
if [ ! -d "$CSRC/lzo-2.10" ]; then
  curl -sL https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz \
    -o "$CSRC/lzo-2.10.tar.gz" && tar xzf "$CSRC/lzo-2.10.tar.gz" -C "$CSRC"
fi
[ -d "$CSRC/lzo-2.10" ] && ( cd "$CSRC/lzo-2.10" && "$CC" -shared -O2 -Iinclude \
  -Wl,--export-all-symbols src/*.c -static-libgcc -o "$ROOT/lzo2.dll" ) \
  && echo "   OK -> lzo2.dll" || echo "   (lzo2 fallo)"

# ── packjpg (JPEG media codec) — user's fork v4.0e ──────────────────────
echo "==> packjpg (packjpg_dll.dll)"
[ -d "$CSRC/packJPG" ] || git clone --depth 1 https://github.com/YadeWira/packJPG "$CSRC/packJPG"
( cd "$CSRC/packJPG" && "$CXX" -O3 -std=c++17 -DBUILD_DLL -Wl,--export-all-symbols \
  source/aricoder.cpp source/bitops.cpp source/packjpg.cpp -shared \
  -static-libgcc -static-libstdc++ -o "$ROOT/packjpg_dll.dll" ) \
  && echo "   OK -> packjpg_dll.dll" || echo "   (packjpg fallo)"

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
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

# ── fast-lzma2 (final internal LZMA2 compression, -l#) ─────────────────────────
echo "==> fast-lzma2 (fast-lzma2.dll)"
[ -d "$CSRC/fast-lzma2" ] || git clone --depth 1 https://github.com/conor42/fast-lzma2 "$CSRC/fast-lzma2"
( cd "$CSRC/fast-lzma2" && "$CC" -shared -O2 -DFL2_DLL_EXPORT=1 -Wl,--export-all-symbols \
  *.c -static-libgcc -o "$ROOT/fast-lzma2.dll" ) \
  && echo "   OK -> fast-lzma2.dll" || echo "   (fast-lzma2 fallo)"

# ── packmp3 (MP3 media codec) — original packjpg/packMP3 v1.0g project ──────
echo "==> packmp3 (packmp3_dll.dll)"
[ -d "$CSRC/packMP3" ] || git clone --depth 1 https://github.com/packjpg/packMP3 "$CSRC/packMP3"
( cd "$CSRC/packMP3" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -Wl,--export-all-symbols \
  source/aricoder.cpp source/bitops.cpp source/huffmp3.cpp source/packmp3.cpp \
  -shared -static-libgcc -static-libstdc++ -o "$ROOT/packmp3_dll.dll" ) \
  && echo "   OK -> packmp3_dll.dll" || echo "   (packmp3 fallo)"

# ── FLAC (lossless WAV media codec) ──────────────────────────────────────────
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

# ── WavPack (lossless WAV media codec, alternative to FLAC) ───────────────────
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

# ── brunsli (JPEG media codec, alternative to packjpg) — requires cmake ────────
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

# ── packpng (PNG/APNG/JNG/MNG codec) — sibling repo of ytool's author ───────
# Same criteria as in build-plugins-linux.sh: building from source requires Rust
# (cross-compile to x86_64-pc-windows-gnu) + cmake for kanzi-cpp -- instead the
# already-built .dll is downloaded from a versioned packPNG release.
echo "==> packpng (packpng.dll)"
PACKPNG_VER="v2.0b"
if curl -sL "https://github.com/YadeWira/packPNG/releases/download/${PACKPNG_VER}/packPNG-2.0b-win64-lib.zip" \
  -o "$CSRC/packpng-lib.zip" 2>/dev/null && [ -s "$CSRC/packpng-lib.zip" ]; then
  ( cd "$CSRC" && unzip -oq packpng-lib.zip packpng.dll ) 2>/dev/null \
    && mv -f "$CSRC/packpng.dll" "$ROOT/packpng.dll" \
    && echo "   OK -> packpng.dll (prebuilt $PACKPNG_VER)" \
    || echo "   (packpng: extraccion fallo)"
else
  echo "   (packpng: descarga fallo)"
fi

echo "Hecho. srep.exe + plugins .dll en la raiz del repo (gitignored)."
echo "jojpeg_dll.dll NO se construye (sin fuente abierta conocida, como oodle)."
