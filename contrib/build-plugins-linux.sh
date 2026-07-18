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

# ── srep (dedup -d / StoreDD) — omega-srep, github.com/YadeWira/omega-srep ──
# Was Intensity/srep (upstream, frozen since 2014) until a real cross-arch
# bug surfaced (win64-encoded `-dd1` streams failed their own checksum when
# decoded by the win32 build). Migrated to omega-srep instead of debugging
# dead upstream code -- actively maintained by the same author. An initial
# 6/6 cross-arch round-trip gate passed before migrating, but a later, more
# targeted repro (zero-LZ-match content, `-m1f`) found the bug survived the
# migration too. Root-caused via live cross-AI collaboration (see the wiki's
# Known-Issues-and-Limitations page for the full history, including the 4
# earlier candidates ruled out along the way): vmac.c's __i386__ branch never
# defines its own ADD128/MUL64/PMUL64, so the 32-bit build fell through to
# the generic portable-C fallback, which GCC's -O2+ strict-aliasing
# optimizations miscompiled. Fixed upstream in omega-srep (targeted
# #pragma GCC optimize("no-strict-aliasing"), no perf cost elsewhere),
# released as v1.0.0 -- pinned to a tag, not a moving branch.
# Verified: the full cross-arch regression matrix (357/357) now passes with
# zero -dd1 failures. Bumped to v1.0.3 afterwards (perf-only: LTO/PGO/thread-
# count tuning, byte-for-byte identical output verified by upstream). Bumped
# again to v1.0.5: v1.0.4 fixed a real cross-arch bug in -m1/-m2 (CDC) --
# PolynomialRollingHash<size_t> used a modulo that differs between 32-bit
# (2^32) and 64-bit (2^64) builds, so a cross-arch archive silently
# decompressed to garbage (no error). Fixed by pinning the hash to uint64.
# Prompted by an external report of a Win7 x64 32-bit decode HANG on `-ddX`
# (not the same symptom as the CDC bug -- that gave wrong bytes, not a hang
# -- but garbage chunk-table data could plausibly loop the decoder); verified
# on real Win7 x64 hardware (VM) with the 32-bit package: -dd1/-dd3, multiple
# codecs, no hang, bit-exact.
#
# BREAKING: omega-srep's on-disk format is a deliberate clean break from
# upstream (magic bytes "SREP"->"OSRP", extension .srep->.osr) -- any
# existing .pmp made with `-mzlib -dd1` before this migration can no longer
# be decoded (the embedded srep sub-stream starts with the old magic).
#
# CLI is unchanged for what ytool actually sends (`-m<N>f`, `-d`, stdin/
# stdout piping via "-") -- confirmed by reading srep.cpp's argument parser,
# byte-for-byte identical to upstream there. No Pascal-side flag changes.
#
# Kept the plain `srep64`/`srep.exe` filename convention (inherited from the
# old Intensity/srep dependency) until it was pointed out that omega-srep's
# own binary is genuinely named `osrep` (its Makefile installs it as such) --
# renamed here and in PrecompMain.pas's SREPEXE/SREPEXE64 constants to match.
echo "==> osrep"
[ -d "$CSRC/omega-srep" ] || git clone --depth 1 --branch v1.0.5 https://github.com/YadeWira/omega-srep "$CSRC/omega-srep"
( cd "$CSRC/omega-srep" && make >/dev/null 2>&1 && cp bin/osrep "$ROOT/osrep64" ) \
  && echo "   OK -> osrep64" || echo "   (osrep fallo)"

# ── packjpg (JPEG media codec) — user's fork v5.0 ──────────────────────
# v4.0f added native arithmetic-coded JPEG support (SOF C9/CA) alongside the
# existing Huffman path. v5.0 is a support-policy/security bump, not a format
# break: drops Windows XP, adds a 3-layer decompression-bomb defense
# (exhaustion detection, blowup-ratio guard, absolute output cap -- default
# 256mb, `-maxout<MB>`), and adds JPEG-LS recompression as a new capability.
# format_version_current stays 40 -- verified bidirectionally byte-compatible
# with v4.0f by upstream. Same 3 source files, no build recipe changes needed.
# JPEG-LS is NOT enabled here: it needs libcharls-dev + libjxl-dev and is
# feature-gated behind -DHAVE_JPEGLS (auto no-op without the flag) -- skipped
# to avoid adding 2 new hard build dependencies for a rare format; revisit if
# JPEG-LS content shows up in practice.
echo "==> packjpg (libpackjpg.so)"
[ -d "$CSRC/packJPG" ] || git clone --depth 1 --branch v5.0 https://github.com/YadeWira/packJPG "$CSRC/packJPG"
( cd "$CSRC/packJPG" && "$CXX" -O3 -std=c++17 -DBUILD_LIB -DBUILD_SO -fPIC \
  -fvisibility=hidden -shared -Wl,-soname,libpackjpg.so \
  source/aricoder.cpp source/bitops.cpp source/packjpg.cpp -s -lpthread \
  -o "$ROOT/libpackjpg.so" ) && echo "   OK -> libpackjpg.so" || echo "   (packjpg fallo)"

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
echo "==> preflate (libpreflate.so)"
[ -d "$CSRC/preflate" ] || git clone --depth 1 https://github.com/deus-libri/preflate "$CSRC/preflate"
if [ -d "$CSRC/preflate" ]; then
  cp "$ROOT/contrib/preflate_wrap.cpp" "$CSRC/preflate/preflate_wrap.cpp"
  # Upstream data race, patched here (not fixable upstream -- deus-libri/preflate
  # isn't ours to patch): support/task_pool.h's TaskPool::addTask() checked
  # `if (_state == INIT) _init();` with no lock at all. Two threads calling into
  # preflate_decode concurrently for the first time in the process -- exactly
  # what happens when ytool's own -t>1 dispatch hands off several streams big
  # enough to engage preflate's internal thread pool at once -- can both
  # observe INIT and both call _init(), racing to push worker threads into the
  # same std::vector<std::thread> from two threads simultaneously: a genuine,
  # unsynchronized data race on process-global state (found while chasing a
  # rare Windows-only -mpreflate non-determinism report; the race window is
  # too narrow to force a live repro, but it's unambiguous by inspection and
  # free to close). Guarded with std::call_once instead (no new header needed,
  # <mutex> already included by task_pool.h).
  grep -q "_onceInit" "$CSRC/preflate/support/task_pool.h" || perl -0777 -pi -e '
    s/if \(_state == INIT\) \{\s*\n\s*_init\(\);\s*\n\s*\}/std::call_once(_onceInit, [this] { _init(); });/;
    s/(std::queue<std::function<void\(\)>> _tasks;)/$1\n  std::once_flag _onceInit;/;
  ' "$CSRC/preflate/support/task_pool.h"
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

# ── packmp3 (MP3 media codec) — user's fork v2.0a (successor of packjpg/packMP3 v1.0g) ──
# Migrated to YadeWira/packMP3 (same author as packJPG/packPNG): full MP3 family
# support (was MPEG-1 Layer III only), CBR/VBR, intra-file/-th batch threading,
# retuned entropy models. Same 4 source files, same BUILD_LIB/BUILD_DLL macros,
# same pmplib_* function set the Pascal binding already expects -- no API changes.
# BREAKING: entropy models were retuned, so the compressed bitstream itself is
# not compatible across major versions (their own release notes say so
# explicitly) -- any .pmp made with -mpackmp3 before this migration can no
# longer be decoded. Accepted given ytool is pre-1.0, same call as omega-srep.
#
# v2.0 (the initial tag) failed to build: source/packmp3.cpp uses std::atomic/
# std::thread (new -k/-th chunking) without #include <atomic>/<thread> anywhere
# in the tree -- reproduced with both clang++ and g++14, so a real upstream bug,
# not a compiler-strictness artifact. Already fixed on their master along with a
# proper extern "C" on the library headers (see below); v2.0a is that fix,
# cut as a new tag at our request so this pins to something reproducible
# instead of a moving branch. The old sed C-linkage patch for Linux .so builds
# is no longer needed as of v2.0a (headers now declare extern "C" natively).
echo "==> packmp3 (libpackmp3.so)"
[ -d "$CSRC/packMP3" ] || git clone --depth 1 --branch v2.0a https://github.com/YadeWira/packMP3 "$CSRC/packMP3"
if [ -d "$CSRC/packMP3" ]; then
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
PACKPNG_VER="v2.0c"
if curl -sL "https://github.com/YadeWira/packPNG/releases/download/${PACKPNG_VER}/packPNG-2.0c-linux-x64-lib.tar.gz" \
  -o "$CSRC/packpng-lib.tar.gz" 2>/dev/null && [ -s "$CSRC/packpng-lib.tar.gz" ]; then
  tar -xzf "$CSRC/packpng-lib.tar.gz" -C "$CSRC" libpackpng.so 2>/dev/null \
    && mv -f "$CSRC/libpackpng.so" "$ROOT/libpackpng.so" \
    && echo "   OK -> libpackpng.so (prebuilt $PACKPNG_VER)" \
    || echo "   (packpng: extraccion fallo)"
else
  echo "   (packpng: descarga fallo)"
fi

echo "Hecho. Plugins .so/srep64 en la raiz del repo (gitignored)."
