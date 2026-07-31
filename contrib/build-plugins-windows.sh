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

# ── srep (external dedup -dd<N>) — omega-srep, github.com/YadeWira/omega-srep ──
# Was Intensity/srep until a real cross-architecture bug surfaced (win64-
# encoded `-dd1` streams failed their own checksum decoded on win32). Migrated
# after ruling out 4 candidate causes (see build-plugins-linux.sh's srep
# comment, and the wiki's Known-Issues-and-Limitations page, for the full
# history) -- omega-srep is actively maintained by the same author. The bug
# survived the initial migration too, but was root-caused via live cross-AI
# collaboration to a GCC strict-aliasing miscompile of VMAC's 32-bit ADD128/
# PMUL64 fallback, fixed upstream and released as v1.0.0. Verified: the full
# cross-arch regression matrix (357/357) now passes with zero -dd1 failures.
# Bumped to v1.0.3 afterwards (perf-only: LTO/PGO/thread-count tuning,
# byte-for-byte identical output verified by upstream) -- added the same
# -flto/-mtune=generic/-funroll-all-loops/-msse2 flags their own Makefile now
# uses, since this script compiles directly rather than via `make`/cmake
# (their platform detection doesn't cross-compile cleanly from Linux). Bumped
# again to v1.0.5, fixing a real -m1/-m2 cross-arch CDC bug -- see
# build-plugins-linux.sh's srep comment for the full story.
# BREAKING: on-disk
# format changed (magic bytes, extension) -- old `.pmp` using `-dd1` from
# before this migration can't be decoded anymore. Already ships its own
# Windows threading backend
# (Compression/LZMA2/C/ThreadsWin32.*) and properly gates out the LZMA-SDK
# Handle.h stub for MinGW builds -- neither shim from contrib/srep-win32/ is
# needed anymore. Still needs -DUNICODE/-D_UNICODE (Common.h assumes
# TCHAR=wchar_t), -lole32 -luuid -lshell32 -ladvapi32 (COM, for the Windows 7
# taskbar progress indicator), and the case shim for <ShObjIdl.h> (mingw-w64
# ships lowercase "shobjidl.h"; only matters on a case-sensitive FS like
# Linux). CLI unchanged for what ytool sends (`-m<N>f`, `-d`, stdin/stdout
# piping via "-") -- confirmed reading srep.cpp's parser, byte-for-byte
# identical to upstream there.
#
# Kept the plain `srep.exe` filename (inherited from the old Intensity/srep
# dependency) until it was pointed out that omega-srep's own binary is
# genuinely named `osrep` -- renamed here and in PrecompMain.pas's SREPEXE
# constant to match.
echo "==> osrep (osrep.exe)"
[ -d "$CSRC/omega-srep" ] || git clone --depth 1 --branch v1.0.5 https://github.com/YadeWira/omega-srep "$CSRC/omega-srep"
if [ -d "$CSRC/omega-srep" ]; then
  ( cd "$CSRC/omega-srep" && "$CXX" -O3 -flto -mtune=generic -funroll-all-loops -msse2 -std=c++17 \
    -I"$ROOT/contrib/mingw-shims" \
    -ICompression -ICompression/_Encryption -ICompression/_Encryption/headers -ICompression/_Encryption/hashes \
    -DFREEARC_WIN -DFREEARC_INTEL_BYTE_ORDER -D_FILE_OFFSET_BITS=64 -DUNICODE -D_UNICODE \
    -Wno-write-strings -Wno-unused-result \
    Compression/Common.cpp Compression/SREP/srep.cpp \
    -lstdc++ -lole32 -luuid -lshell32 -ladvapi32 -static -o "$ROOT/osrep.exe" ) \
    && echo "   OK -> osrep.exe" || echo "   (osrep fallo)"
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

# ── packjpg (JPEG media codec) — user's fork v5.0 (bomb-guard hardening) ──
# Format-stable bump (format_version_current unchanged, v4.0f-compatible) --
# see build-plugins-linux.sh's packjpg comment for the full story. JPEG-LS
# (new in v5.0) never reaches Windows anyway: no MinGW builds of its
# libcharls/libjxl deps exist upstream, so nothing to opt into here.
echo "==> packjpg (packjpg_dll.dll)"
[ -d "$CSRC/packJPG" ] || git clone --depth 1 --branch v5.0 https://github.com/YadeWira/packJPG "$CSRC/packJPG"
( cd "$CSRC/packJPG" && "$CXX" -O3 -std=c++17 -DBUILD_DLL -Wl,--export-all-symbols \
  source/aricoder.cpp source/bitops.cpp source/packjpg.cpp -shared \
  -static-libgcc -static-libstdc++ -o "$ROOT/packjpg_dll.dll" ) \
  && echo "   OK -> packjpg_dll.dll" || echo "   (packjpg fallo)"

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
echo "==> preflate (preflate_dll.dll)"
[ -d "$CSRC/preflate" ] || git clone --depth 1 https://github.com/deus-libri/preflate "$CSRC/preflate"
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
echo "==> fast-lzma2 (fast-lzma2.dll)"
[ -d "$CSRC/fast-lzma2" ] || git clone --depth 1 https://github.com/conor42/fast-lzma2 "$CSRC/fast-lzma2"
( cd "$CSRC/fast-lzma2" && "$CC" -shared -O2 -DFL2_DLL_EXPORT=1 -Wl,--export-all-symbols \
  *.c -static-libgcc -o "$ROOT/fast-lzma2.dll" ) \
  && echo "   OK -> fast-lzma2.dll" || echo "   (fast-lzma2 fallo)"

# ── packmp3 (MP3 media codec) — user's fork v3.0c (successor of packjpg/packMP3 v1.0g) ──
# Migrated to YadeWira/packMP3 (same author as packJPG/packPNG): full MP3 family
# support (was MPEG-1 Layer III only), CBR/VBR, threading, retuned entropy
# models. Same source files/macros/pmplib_* functions, no build recipe changes.
# BREAKING (v1.0g -> v2.0a only): retuned entropy models made that jump's
# bitstream incompatible -- old .pmp using -mpackmp3 from before it can no
# longer be decoded. v2.0a -> v3.0c is NOT another break (purely additive,
# version-gated per v3.0's own release notes).
# v2.0 (initial tag) failed to build (missing <atomic>/<thread> includes);
# v2.0a is the fix, cut upstream at our request -- see build-plugins-linux.sh's
# packmp3 comment for the full story, including why v3.0c needs packMP2's
# header (not its built library) even for this BUILD_LIB-only recipe.
echo "==> packmp3 (packmp3_dll.dll)"
[ -d "$CSRC/packMP3" ] || git clone --depth 1 --branch v3.0c https://github.com/YadeWira/packMP3 "$CSRC/packMP3"
[ -d "$CSRC/packMP3/source/vendor/packmp2-src/src/lib" ] || \
  git clone --depth 1 https://github.com/YadeWira/packMP2 "$CSRC/packMP3/source/vendor/packmp2-src"
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
PACKPNG_VER="v2.0d"
if curl -sL "https://github.com/YadeWira/packPNG/releases/download/${PACKPNG_VER}/packPNG-2.0d-win64-lib.zip" \
  -o "$CSRC/packpng-lib.zip" 2>/dev/null && [ -s "$CSRC/packpng-lib.zip" ]; then
  ( cd "$CSRC" && unzip -oq packpng-lib.zip packpng.dll ) 2>/dev/null \
    && mv -f "$CSRC/packpng.dll" "$ROOT/packpng.dll" \
    && echo "   OK -> packpng.dll (prebuilt $PACKPNG_VER)" \
    || echo "   (packpng: extraccion fallo)"
else
  echo "   (packpng: descarga fallo)"
fi

echo "Hecho. osrep.exe + plugins .dll en la raiz del repo (gitignored)."
echo "jojpeg_dll.dll NO se construye (sin fuente abierta conocida, como oodle)."
