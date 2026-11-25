#!/bin/bash
# Builds srep, the external dedup helper behind -dd<N>, from vendor/srep/.
#
#   bash contrib/build-srep.sh [linux|win64|win32|all]     (default: linux)
#
# Outputs, in the repo root (gitignored):
#   linux -> srep64        win64 -> srep.exe        win32 -> srep-x86.exe
#
# srep is NOT part of the ytool build. ytool compiles and runs without it:
# only -dd<N> (external dedup) needs the helper, and -dd (in-memory dedup) does
# not. Building it is a separate, optional step, so a change in srep never
# rebuilds ytool and a missing toolchain for srep never blocks ytool.
#
# Source: Intensity/srep 48f4b97, SREP 3.93a beta (October 11, 2014), vendored
# in full in vendor/srep/ (see VENDORED.md). The tree is copied to a scratch
# directory and patched there by contrib/patch_srep.py, so vendor/srep/ stays
# pristine and the patches stay a visible diff. Each patch has a real failure
# behind it; see vendor/srep/OMEGA-IMPROVEMENTS.md and TOOL-FIXES.md.
#
# CLI trap worth knowing: srep needs the explicit `-d` on decode. Without it, it
# sees two filenames, re-compresses the compressed file and exits 0 with 100.04 %
# of its input. PrecompMain.pas passes it (SREP_DECODE_MODE).
#
# Windows: upstream kept only the Unix threading backend. contrib/srep-win32/
# adds ThreadsWin32.* (adapted from the public-domain LZMA SDK) and an empty
# Handle.h stub. Also needed: -DUNICODE/-D_UNICODE (Common.h assumes
# TCHAR=wchar_t), -lole32 -luuid (the Win7 taskbar progress code still links),
# and contrib/mingw-shims/ for <ShObjIdl.h> on a case-sensitive host.
# The vmac.c and CRC32 patches matter most on win32: that is the build where
# VMAC's portable 32-bit fallback is miscompiled under strict aliasing and where
# the "rm" asm constraint does not compile at all.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CSRC="$ROOT/contrib/.csrc"
mkdir -p "$CSRC"
TARGET="${1:-linux}"
rc=0

[ -f "$ROOT/vendor/srep/Makefile" ] || { echo "falta vendor/srep/Makefile"; exit 1; }

# fresh patched copy of vendor/srep in $1
prepare() {
  rm -rf "$1" && cp -a "$ROOT/vendor/srep" "$1" || return 1
  python3 "$ROOT/contrib/patch_srep.py" "$1" >/dev/null || {
    echo "   (srep: los parches no aplicaron)"; return 1; }
}

build_linux() {
  echo "==> srep (srep64)"
  local B="$CSRC/srep-build"
  prepare "$B" || return 1
  ( cd "$B" && make >/dev/null 2>&1 && cp bin/srep "$ROOT/srep64" ) \
    && echo "   OK -> srep64" || { echo "   (srep fallo)"; return 1; }
}

# $1 = compiler, $2 = scratch dir, $3 = output name
build_windows() {
  echo "==> srep ($3)"
  command -v "$1" >/dev/null || { echo "   (falta $1)"; return 1; }
  prepare "$2" || return 1
  cp "$ROOT/contrib/srep-win32/ThreadsWin32.h" "$ROOT/contrib/srep-win32/ThreadsWin32.c" \
    "$2/Compression/LZMA2/C/"
  cp "$ROOT/contrib/srep-win32/Handle.h" "$2/Compression/LZMA2/MultiThreading/"
  ( cd "$2" && "$1" -O3 -std=c++17 \
    -I"$ROOT/contrib/mingw-shims" \
    -ICompression -ICompression/_Encryption -ICompression/_Encryption/headers -ICompression/_Encryption/hashes \
    -DFREEARC_WIN -DFREEARC_INTEL_BYTE_ORDER -D_FILE_OFFSET_BITS=64 -DUNICODE -D_UNICODE \
    -Wno-write-strings -Wno-unused-result \
    Compression/Common.cpp Compression/SREP/srep.cpp \
    -static-libgcc -static-libstdc++ -lole32 -luuid -o "$ROOT/$3" ) \
    && echo "   OK -> $3" || { echo "   (srep fallo)"; return 1; }
}

case "$TARGET" in
  linux) build_linux || rc=1 ;;
  win64) build_windows x86_64-w64-mingw32-g++ "$CSRC/srep-build-w64" srep.exe || rc=1 ;;
  win32) build_windows i686-w64-mingw32-g++ "$CSRC/srep-build-x86" srep-x86.exe || rc=1 ;;
  all)
    build_linux || rc=1
    build_windows x86_64-w64-mingw32-g++ "$CSRC/srep-build-w64" srep.exe || rc=1
    build_windows i686-w64-mingw32-g++ "$CSRC/srep-build-x86" srep-x86.exe || rc=1 ;;
  *) echo "uso: $0 [linux|win64|win32|all]"; exit 2 ;;
esac
exit $rc
