#!/usr/bin/env bash
# Builds ytool for Linux x86 (i386) on an x86-64 Linux host, into build-x86/:
# the binary and its codec libraries, like the repo root holds for x86-64.
#
# Needs:
#  - FPC 3.2.2 for i386-linux. Distributions ship only their native compiler,
#    so this uses the official build (fpc-3.2.2.i386-linux.tar from
#    freepascal.org, unpacked: its binary.i386-linux.tar holds base.*.tar.gz
#    and units-*.tar.gz, each extracted into one prefix). FPC386=<that prefix>
#    /lib/fpc/3.2.2, the folder with ppc386 and units/.
#  - gcc-multilib and g++-multilib (gcc -m32). Since 0.9.9f zlib is built in
#    (contrib/ZLibStatic): no 32-bit libz is needed (ZLIB32 is still read, as
#    an extra library path, if set).
#
# FPC 3.2.2's i386 startup code (si_c21) still refers to __libc_csu_init and
# __libc_csu_fini, which glibc 2.34 removed; the link fails without them.
# glibc ignores what a program passes there, so empty ones are linked in
# (FPC fixed it after 3.2.2; Debian patches its own packages the same way).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/build-x86"
FPC386="${FPC386:?FPC386=<prefix>/lib/fpc/3.2.2 of an FPC 3.2.2 i386-linux install}"
PPC="$FPC386/ppc386"
[ -x "$PPC" ] || { echo "no ppc386 in $FPC386" >&2; exit 1; }
gcc -m32 -print-libgcc-file-name >/dev/null 2>&1 || { echo "gcc -m32 does not work (gcc-multilib)" >&2; exit 1; }
ZL=""
[ -n "${ZLIB32:-}" ] && ZL="-Fl$ZLIB32"

mkdir -p "$OUT/fu"
echo "==> C objects (i386)"
ARCH=x86 bash contrib/build-native-linux.sh >/dev/null
echo "==> codec libraries (i386)"
ARCH=x86 OUT="$OUT" bash contrib/build-plugins-linux.sh | grep -E 'OK ->|fallo|fail' || true

printf 'void __libc_csu_init(void) {}\nvoid __libc_csu_fini(void) {}\n' > "$OUT/csu.c"
gcc -m32 -O2 -c "$OUT/csu.c" -o "$OUT/csu.o"

echo "==> ytool (i386)"
GL="$(dirname "$(gcc -m32 -print-libgcc-file-name)")"
# -n: not the system fpc.cfg, which points at the x86-64 units
"$PPC" -n -Mdelphi -Sg -O2 -Fu"$FPC386/units/i386-linux/*" -Fl/usr/lib32 $ZL -Fl"$GL" \
  -k"$OUT/csu.o" -FU"$OUT/fu" -Fucompat -Fucommon -Fuprecompressor -Fuio -Fuimports \
  -Fusources -Fudbgenerator -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
  -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -Fucontrib/LZMADelphi -Fucontrib/ZLibStatic \
  -o"$OUT/ytool" ytool.dpr >"$OUT/fpc.log" 2>&1 || { grep -E 'Error|Fatal|undefined' "$OUT/fpc.log" >&2; exit 1; }
file "$OUT/ytool" | grep -q 'Intel 80386\|Intel i386' || { echo "build-x86/ytool is not i386" >&2; exit 1; }
echo "OK: $OUT/ytool"
