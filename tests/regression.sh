#!/usr/bin/env bash
# Suite de regresion de ytool: verifica REVERSIBILIDAD bit-exacta (decode(precomp(x))==x)
# y reporta ratios de precompresion. Es la red de seguridad al recrear features post-0.7.9.
#
# Uso:
#   tests/regression.sh                 # build + corpus sintetico
#   NO_BUILD=1 tests/regression.sh      # usa el binario ./xtool ya compilado
#   FULL=1 tests/regression.sh          # ademas, slice de test-files2.tar si existe
#
# Sale con codigo !=0 si CUALQUIER round-trip no es bit-exacto.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
XTOOL="$ROOT/xtool"
WORK="$(mktemp -d)"
CORPUS="$WORK/corpus"
trap 'rm -rf "$WORK"' EXIT

# metodos a probar contra CADA archivo (la reversibilidad debe valer en todos)
METHODS=("" "-mzlib" "-mzlib+zstd")

fail=0; pass=0
echo "== ytool regression =="

# 1) build (salvo NO_BUILD) -------------------------------------------------
if [ "${NO_BUILD:-0}" != "1" ]; then
  echo "-- building xtool (linux) --"
  bash contrib/build-native-linux.sh >/dev/null 2>&1 || { echo "FALLO build nativo"; exit 3; }
  fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
    -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
    -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -oxtool xtool.dpr >/dev/null 2>&1 \
    || { echo "FALLO compilacion fpc"; exit 3; }
fi
[ -x "$XTOOL" ] || { echo "no existe binario $XTOOL"; exit 3; }

# 2) corpus -----------------------------------------------------------------
python3 tests/gen_corpus.py "$CORPUS" >/dev/null || { echo "FALLO gen_corpus"; exit 3; }
if [ "${FULL:-0}" = "1" ] && [ -f "$ROOT/test-files2.tar" ]; then
  echo "-- FULL: anadiendo slice de test-files2.tar (300MB) --"
  head -c 300000000 "$ROOT/test-files2.tar" > "$CORPUS/40_realworld_300m.bin"
fi

# 3) round-trips ------------------------------------------------------------
printf "%-26s %-14s %10s %10s %8s  %s\n" FILE METHOD IN PMP RATIO RESULT
for f in "$CORPUS"/*; do
  bn="$(basename "$f")"
  insz=$(stat -c%s "$f")
  for m in "${METHODS[@]}"; do
    pmp="$WORK/out.pmp"; outf="$WORK/out.bin"
    rm -f "$pmp" "$outf"
    "$XTOOL" precomp $m "$f" "$pmp" >/dev/null 2>&1
    "$XTOOL" decode "$pmp" "$outf" >/dev/null 2>&1
    pmpsz=$(stat -c%s "$pmp" 2>/dev/null || echo 0)
    if cmp -s "$f" "$outf"; then
      res="OK"; pass=$((pass+1))
    else
      res="*** FAIL ***"; fail=$((fail+1))
    fi
    if [ "$insz" -gt 0 ] && [ "$pmpsz" -gt 0 ]; then
      ratio=$(awk "BEGIN{printf \"%.3f\", $pmpsz/$insz}")
    else
      ratio="-"
    fi
    printf "%-26s %-14s %10s %10s %8s  %s\n" "$bn" "${m:-<literal>}" "$insz" "$pmpsz" "$ratio" "$res"
  done
done

echo "-- resumen: $pass OK, $fail FAIL --"
[ "$fail" -eq 0 ] && { echo "REGRESION: PASS (reversibilidad bit-exacta en todo el corpus)"; exit 0; } \
                  || { echo "REGRESION: FALLO ($fail round-trips no reversibles)"; exit 1; }
