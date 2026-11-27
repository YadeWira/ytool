#!/usr/bin/env bash
# Builds ytool's external plugins/codecs for Linux x86-64 (or i386 with
# ARCH=x86, into OUT=<dir>) from open source
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

# Revisiones fijadas a lo que efectivamente se construyo y publico. Un tag se
# puede mover; un SHA no. Ver contrib/pin-repo.sh para por que el pin tiene
# que aplicarse tambien sobre un checkout que ya existe.
PREFLATE_REF="609eefaa96ac6c51d7b1a3fb29e0ed94d0f3623e"
FLZMA2_REF="756d1c9f0c5806873c6a4c9e59f270e3daf445c7"   # fast-lzma2-v1.2.0
BRUNSLI_REF="c18b9625ef045b0b89ebb4439ae2339e2160df71"   # master 2026-09-10 (no newer tag than v0.1, 2019)
CXX="$(command -v clang++ || command -v g++)"
CC="$(command -v gcc || command -v clang || command -v cc)"

# ARCH=x86: the same libraries for Linux i386 (gcc -m32; needs gcc-multilib and
# g++-multilib), written to $OUT instead of the repo root, where the x86-64
# ones live. ARCH=x64 (the default) is unchanged.
ARCH="${ARCH:-x64}"
case "$ARCH" in
  x64) M=""; OUT="${OUT:-$ROOT}" ;;
  x86) M="-m32 -msse2"; OUT="${OUT:?ARCH=x86 needs OUT=<dir> (the x86-64 libraries are in the repo root)}"
       CXX="$(command -v g++)"; CC="$(command -v gcc)" ;;
  *) echo "ARCH must be x64 or x86" >&2; exit 2 ;;
esac
mkdir -p "$OUT"

. "$(dirname "$CSRC")/pin-repo.sh"   # $CSRC es absoluto; $0 no sirve, cada script hace cd distinto

# lz4 pinned by SHA, not by tag (see contrib/pin-repo.sh).
# v1.11.1 since 0.9.9a, which starts a new baseline: its output differs from
# 0774d05 (1.10.0 + fix_read_oob) for fast mode at every acceleration, HC
# levels 1, 2 and 10-12, and frames at those levels, so .ytp files from the
# older pre-releases that hold such streams do not restore with it.
LZ4_REF="aa4647fad575d01a874aaaadcdbe8e6a40e072f5"   # v1.11.1

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
echo "==> libzstd.so ($ARCH)"
pin_repo https://github.com/facebook/zstd "$CSRC/zstd-lib" "$ZSTD_LIB_REF"
# ZSTD_MULTITHREAD: the zstd CLI writes with one worker thread by default (-T1),
# whose bytes differ from single-threaded zstd above a job's size; without it
# libzstd refuses nbWorkers and such frames (level 1 over ~2 MB, for one) could
# not be reproduced. Single-threaded output does not change.
( cd "$CSRC/zstd-lib/lib" && "$CC" $M -shared -fPIC -O2 -Wl,-Bsymbolic -DZSTD_DISABLE_ASM \
    -DZSTD_MULTITHREAD -pthread \
    -I. -Icommon common/*.c compress/*.c decompress/*.c -o "$OUT/libzstd.so" ) \
  && echo "   OK -> libzstd.so" || echo "   (libzstd fallo)"

# -- liblz4.so -- sin esto Linux usa el liblz4 de la DISTRO ------------------
# imports/LZ4DLL.pas cargaba el soname pelado 'liblz4.so.1', o sea lo que
# hubiera instalado el sistema. Windows siempre shipeo su liblz4.dll, asi que
# la asimetria pasaba desapercibida: el tarball de Linux de v0.9.8 no trae
# ninguna liblz4.
#
# Eso no es solo desprolijo. Entre lz4 1.9.4 y 1.10.0, LZ4HC_CLEVEL_MIN paso
# de 3 a 2, y el nivel 2 -- el primer candidato de la busqueda de nivel de
# PrecompLZ4 -- pasa a ser otro algoritmo. Medido end-to-end: un .ytp
# codificado contra 1.10.0 y restaurado contra 1.9.4 falla, y existe la
# variante silenciosa (mismo largo, bytes distintos) que pasa el gate de
# tamano de PrecompLZ4.pas:599 y escribe datos mal sin excepcion.
#
# Con la lib shipeada, la version deja de depender de la distro del usuario.
# -Bsymbolic para que la lib resuelva sus propios XXH* aunque el proceso
# tenga otros: hoy ./ytool no exporta ninguno (medido), pero eso es una
# propiedad del build de FPC, no una garantia.
echo "==> liblz4.so ($ARCH)"
pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
LZ4SRC="$CSRC/lz4/lib"
# x86: the patched copy, whose fast mode writes what 64-bit lz4 writes (see
# lz4_lib32 in pin-repo.sh); otherwise x86-64 .ytp files did not decode.
[ "$ARCH" = x86 ] && { lz4_lib32 "$CSRC/lz4" "$CSRC/lz4-lib32" && LZ4SRC="$CSRC/lz4-lib32" || LZ4SRC=""; }
if [ -n "$LZ4SRC" ] && [ -d "$LZ4SRC" ]; then
  ( cd "$LZ4SRC" && "$CC" $M -shared -fPIC -O2 -Wl,-Bsymbolic \
      lz4.c lz4hc.c lz4frame.c xxhash.c -o "$OUT/liblz4.so" ) \
    && echo "   OK -> liblz4.so" || echo "   (liblz4 fallo)"
fi

# srep is not part of this repository (SREP 3.93a is "All rights reserved";
# see THIRD_PARTY.md). Personal builds: github.com/YadeWira/srep-builds.

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
if [ "$ARCH" = x86 ]; then
  PJA_PLAT="linux-x86"
  PJA_SHA256="705292ef46d70c2d4d7cb1c0212deba5c566779bcd85021e82ae2a704064b16f"
else
  PJA_PLAT="linux-x86_64"
  PJA_SHA256="2b8cf9ecbb8e6b0669b4f8d7fc9e760ebb9ea466edbe50f7fff4ce2718410d83"
fi
PJA_ASSET="pja-${PJA_VER}-lib-${PJA_PLAT}.tar.gz"
echo "==> PJA (libpja.so)"
if curl -sfL -o "$CSRC/$PJA_ASSET" \
    "https://github.com/YadeWira/PJA/releases/download/v${PJA_VER}/$PJA_ASSET" \
  && echo "$PJA_SHA256  $CSRC/$PJA_ASSET" | sha256sum -c --status; then
  rm -rf "$CSRC/pja-lib" && mkdir -p "$CSRC/pja-lib" \
    && ( cd "$CSRC/pja-lib" && tar xzf "$CSRC/$PJA_ASSET" ) \
    && cp "$CSRC/pja-lib/pja-${PJA_VER}-lib-${PJA_PLAT}/pja.so" "$OUT/libpja.so" \
    && echo "   OK -> libpja.so" || echo "   (PJA: no se pudo extraer)"
else
  rm -f "$CSRC/$PJA_ASSET"; echo "   (PJA: descarga fallida o SHA-256 distinto)"
fi

# ── preflate (improves the zlib codec: reconstructs deflate from any encoder) ─
echo "==> preflate (libpreflate.so)"
pin_repo https://github.com/deus-libri/preflate "$CSRC/preflate" "$PREFLATE_REF"
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
    "$CXX" $M -shared -fPIC -fvisibility=hidden -std=c++11 -O2 \
      -include cstdint -include cstddef -include cstring -include cstdio \
      $SRCS preflate_wrap.cpp -lpthread -o "$OUT/libpreflate.so"
  ) && echo "   OK -> libpreflate.so" || echo "   (preflate fallo)"
fi

# ── fast-lzma2 (final internal LZMA2 compression, -l#) ─────────────────────────
# From YadeWira/ultra-fast-lzma2, the maintained fork (conor42/fast-lzma2 is
# frozen). Its fast-lzma2/ folder is the FL2_* library ytool loads; the uf-lzma2
# line at the repo root has a renamed UF2_* API and is not used. 1.2.0 keeps
# the compressed bytes of every level, so .ytp files are unchanged.
echo "==> fast-lzma2 (libfast-lzma2.so)"
pin_repo https://github.com/YadeWira/ultra-fast-lzma2 "$CSRC/ultra-fast-lzma2" "$FLZMA2_REF"
# Same flags as its Makefile: hidden visibility (only FL2_* exported) and, on
# x86-64, the assembler LZMA decoder.
( cd "$CSRC/ultra-fast-lzma2/fast-lzma2" && CC="$(command -v gcc || command -v clang)" && \
  if [ "$ARCH" = x64 ] && [ "$(uname -m)" = x86_64 ]; then \
    "$CC" -c -DMS_x64_CALL=0 lzma_dec_x86_64.S -o lzma_dec_x86_64.o && \
    ASM="lzma_dec_x86_64.o" && OPT="-DLZMA2_DEC_OPT"; \
  else ASM="" && OPT=""; fi && \
  "$CC" $M -shared -fPIC -O2 -pthread -fvisibility=hidden $OPT *.c $ASM \
    -o "$OUT/libfast-lzma2.so" ) \
  && echo "   OK -> libfast-lzma2.so" || echo "   (fast-lzma2 fallo)"

# ── brunsli (JPEG media codec, alternative to PJA) — requires cmake ────────
echo "==> brunsli (libbrunsli.so)"
pin_repo https://github.com/google/brunsli "$CSRC/brunsli" "$BRUNSLI_REF"
if [ -d "$CSRC/brunsli" ] && command -v cmake >/dev/null; then
  BOUT=out; [ "$ARCH" = x86 ] && BOUT=out32
  ( cd "$CSRC/brunsli" && mkdir -p $BOUT && cd $BOUT && \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_C_FLAGS="$M" -DCMAKE_CXX_FLAGS="$M" .. >/dev/null 2>&1 && \
    make -j4 >/dev/null 2>&1 )
  A="$CSRC/brunsli/$BOUT/artifacts"; BR="$CSRC/brunsli/$BOUT/_deps/brotli-build"
  "$CXX" $M -shared -fPIC -fvisibility=hidden -std=c++11 -O2 -I "$CSRC/brunsli/c/include" \
    "$ROOT/contrib/brunsli_wrap.cpp" -Wl,--start-group \
    "$A/libbrunslienc-static.a" "$A/libbrunslidec-static.a" "$A/libbrunslicommon-static.a" \
    "$BR/libbrotlienc-static.a" "$BR/libbrotlidec-static.a" "$BR/libbrotlicommon-static.a" \
    -Wl,--end-group -o "$OUT/libbrunsli.so" \
    && echo "   OK -> libbrunsli.so" || echo "   (brunsli link fallo)"
else
  echo "   (brunsli: falta cmake o el clone)"
fi

# OSREP (-ddo), released binary, next to ytool
if [ "$ARCH" = x86 ]; then fetch_osrep osrep-linux-x86 "$OUT/osrep"; else fetch_osrep osrep-linux-x86_64 "$OUT/osrep"; fi

echo "Hecho. Plugins .so en $OUT (la raiz del repo, gitignored, salvo ARCH=x86)."
