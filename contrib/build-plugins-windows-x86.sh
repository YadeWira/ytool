#!/usr/bin/env bash
# Downloads win32 (i386) plugin DLLs for the Win7-x86 build. Unlike the native
# objects ({$L}-linked at compile time), every codec here is loaded at runtime
# via LoadLibrary (imports/*.pas + TLibImport) -- if a given plugin has no
# win32 build, that codec just reports unavailable at runtime, same as an
# already-missing .dll does on the win64 build today. This script only
# fetches what's confirmed to exist for win32 so far; extend it as more
# plugins get i686 builds.
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
CSRC="$(pwd)/.csrc"
ROOT="$(cd .. && pwd)"
mkdir -p "$CSRC"

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
    && echo "   OK -> packpng-x86.dll (prebuilt $PACKPNG_VER, win32; rename to" \
    && echo "         packpng.dll next to the win32 ytool.exe, NOT the win64 one)" \
    || echo "   (packpng: extraccion fallo)"
else
  echo "   (packpng: descarga fallo)"
fi

echo "Hecho. Plugins .dll win32 en la raiz del repo (gitignored, prefijo -x86 para"
echo "no pisar los .dll win64 de build-plugins-windows.sh)."
