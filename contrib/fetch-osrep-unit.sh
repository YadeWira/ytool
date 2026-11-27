#!/usr/bin/env bash
# Vendors OSREP's embeddable unit (github.com/YadeWira/omega-srep, MIT) into
# contrib/osrep/: ytool links OSREP into its own binary (-ddo runs it in
# process, docs/ROADMAP-1.0.0.md point 3) instead of starting the osrep program.
#
#   bash contrib/fetch-osrep-unit.sh
#
# The release's osrep-unit-<ver>.tar.gz, checked against the SHA-256 of that
# release's SHA256SUMS. Its src/pascal units are copied as they are, except
# that each {$L osrep_X.o} becomes a per-target choice: the tarball keeps one
# object folder per target (obj/<target>/osrep_X.o, same names), and here they
# sit side by side as osrep_X.<target>.o, so one -Fucontrib/osrep serves every
# build. The result is committed; rerun this to move to another release.
set -euo pipefail
cd "$(dirname "$0")"                 # contrib/
OSREP_UNIT_VER="0.0.19"
OSREP_UNIT_SHA256="4a0e10982cdef6feed1edf3d0724a60758b9ae2dc6b6af5f7879c5612b437b12"
OUT="$(pwd)/osrep"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TGZ="$TMP/osrep-unit.tar.gz"
curl -sfL -o "$TGZ" \
  "https://github.com/YadeWira/omega-srep/releases/download/v$OSREP_UNIT_VER/osrep-unit-$OSREP_UNIT_VER.tar.gz"
echo "$OSREP_UNIT_SHA256  $TGZ" | sha256sum -c --status \
  || { echo "osrep-unit: download failed or SHA-256 differs" >&2; exit 1; }
tar xzf "$TGZ" -C "$TMP"
SRC="$TMP/osrep-unit-$OSREP_UNIT_VER"
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$SRC/LICENSE" "$SRC/VERSION" "$OUT/"
for t in linux-x86_64 linux-x86 linux-arm64 win64 win32; do
  for o in "$SRC"/obj/$t/*.o; do
    cp "$o" "$OUT/$(basename "$o" .o).$t.o"
  done
done
for p in "$SRC"/src/pascal/*.pas; do
  python3 - "$p" "$OUT/$(basename "$p")" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8', errors='surrogateescape').read()
def per_target(m):
    n = m.group(1)
    return ("{$IF defined(LINUX) and defined(CPUX86_64)}{$L %s.linux-x86_64.o}"
            "{$ELSEIF defined(LINUX) and defined(CPUI386)}{$L %s.linux-x86.o}"
            "{$ELSEIF defined(LINUX) and defined(CPUAARCH64)}{$L %s.linux-arm64.o}"
            "{$ELSEIF defined(WIN64)}{$L %s.win64.o}"
            "{$ELSEIF defined(WIN32)}{$L %s.win32.o}{$ENDIF}") % (n, n, n, n, n)
s = re.sub(r'\{\$[Ll] (osrep_[a-z_]+)\.o\}', per_target, s)
open(dst, 'w', encoding='utf-8', errors='surrogateescape').write(s)
PY
done
echo "OK: OSREP $OSREP_UNIT_VER unit in $OUT"
