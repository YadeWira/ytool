#!/usr/bin/env bash
# ytool regression suite: verifies bit-exact REVERSIBILITY (decode(precomp(x))==x)
# and reports precompression ratios. It's the safety net when recreating post-0.7.9 features.
#
# Usage:
#   tests/regression.sh                 # build + synthetic corpus
#   NO_BUILD=1 tests/regression.sh      # use the already-built ./ytool binary
#   FULL=1 tests/regression.sh          # also, slice of test-files2.tar if present
#   XTOOL=path/to/ytool.exe tests/regression.sh   # override the binary path
#                                        # (e.g. Windows CI, where it's ytool.exe)
#
# Exits with code !=0 if ANY round-trip is not bit-exact.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
XTOOL="${XTOOL:-$ROOT/ytool}"
WORK="$(mktemp -d)"
CORPUS="$WORK/corpus"
# Failure artifacts must live OUTSIDE $WORK: the trap below wipes $WORK on exit,
# which would delete the very evidence an intermittent failure needs.
FAILDIR="${FAILDIR:-$ROOT/regression-failures}"
trap 'rm -rf "$WORK"' EXIT

# methods to test against EVERY file (reversibility must hold for all of them)
# "-mzlib -dd" exercises deduplication (encode and decode DD path); on 23_dup_streams.bin
# it finds real duplicates, on the rest it passes through (empty dedup, still reversible).
# "-mlzo1x" exercises the lzo codec (encode+decode) on 50_lzo1x.bin if it was generated (see below).
# "-mwavpack"/"-mflac" exercise the audio codecs on 60_wav_pcm.bin (RIFF -> lossless recompression).
# "-mzlib -dd1" exercises EXTERNAL dedup (osrep64/osrep.exe); if the binary isn't present,
# StoreDD silently falls back to -1 (in-memory dedup) -> still reversible, just with
# less real coverage until it's generated with contrib/build-plugins-{linux,windows}.sh.
# "-mzlib -r xor"/"-r aes"/"-r rc4" exercise PrecompCrypto.pas (previously with no test):
# CryptoScan1 is a no-op, they only activate by reassigning streams already detected by another
# codec (same as "-r zstd" already did) -> real round-trip on 20_zlib_streams.bin.
# "-mpng" exercises the PNG container (61_png_min.bin, generated in situ, no dependencies).
# "-mpackpng" exercises the packPNG codec (sibling repo YadeWira/packPNG, preflate +
# WebP-lossless) on 62_png_photo.bin -- unlike 61_png_min.bin (pure noise,
# only useful for -mpng which doesn't model pixels), this PNG has a real gradient so
# the image codec has something to gain. Requires libpackpng.so/packpng.dll in the
# repo (not vendored yet, see Phase 6); if missing, DLLLoaded=False and the method runs
# over 0 streams -> trivially reversible, same criterion as preflate/srep when missing.
# "-mpreflate" exercises ReflateDLL/PreflateDLL against the same streams from
# 20_zlib_streams.bin; preflate DOES have a .so in this repo -> real coverage. "-mreflate"
# is left as-is in case that lib is ever added: if missing, it falls back to 0 streams (trivially
# reversible), same criterion as "-dd1" with srep.
# "-mlz4f"/"-mpackjpg"/"-mbrunsli"/"-mpackmp3" depend on OPTIONAL corpus files
# (see gen_corpus.py: they require the python module "lz4", Pillow, and the "lame"
# binary respectively). If missing, those files aren't generated and the method runs over 0
# streams -> trivially reversible, no real coverage until the machine has them.
# NOTE "-mlz4f": the generated LZ4 frame IS detected (magic 0x184D2204) but the
# recompression doesn't reproduce the original frame byte for byte -> it falls back to the safe
# fallback (Streams 0/1, not 1/1). It's still reversible, but doesn't test the codec end to end;
# documented as a known limitation, not fixed in this pass.
# PENDING (not covered here): "-mlz4"/"-mlz4hc" (raw LZ4 block, token byte heuristic
# $F0-$F4 in PrecompLZ4.pas) would need a dedicated generator like
# tests/lzo_gen.c, not a simple frame -> left out of this coverage pass.
# "-mlzma" exercises the new raw-LZMA1 codec (PrecompLZMA.pas, statically-linked LZMA
# SDK) on 63_lzma_alone.bin (stdlib 'lzma', always available -- no optional-tool
# caveat). Covers both header variants: known uncompressed size, and the
# unknown-size/end-marker form real "xz --format=lzma" output actually uses.
METHODS=("" "-mzlib" "-mzlib+zstd" "-mzlib -dd" "-mzlib -dd1" "-mzlib -r zstd" \
  "-mzlib -r xor" "-mzlib -r aes" "-mzlib -r rc4" "-mlzo1x" "-mwavpack" "-mflac" \
  "-mpng" "-mpackpng" "-mpreflate" "-mreflate" "-mlz4f" "-mpackjpg" "-mbrunsli" \
  "-mpackmp3" "-mlzma")

fail=0; pass=0; err=0
echo "== ytool regression =="

# 1) build (unless NO_BUILD) -------------------------------------------------
if [ "${NO_BUILD:-0}" != "1" ]; then
  echo "-- building ytool (linux) --"
  NATIVE_LOG="$(bash contrib/build-native-linux.sh 2>&1)" \
    || { echo "native build FAILED:"; echo "$NATIVE_LOG"; exit 3; }
  mkdir -p .fpcout
  FPC_LOG="$(fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
    -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
    -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -Fucontrib/LZMADelphi \
    -oytool ytool.dpr 2>&1)" \
    || { echo "fpc compilation FAILED:"; echo "$FPC_LOG"; exit 3; }
fi
[ -x "$XTOOL" ] || { echo "binary does not exist $XTOOL"; exit 3; }

# 2) corpus -----------------------------------------------------------------
python3 tests/gen_corpus.py "$CORPUS" >/dev/null || { echo "gen_corpus FAILED"; exit 3; }
# lzo1x: if gcc + liblzo2 are present, compiles the generator and creates a DETECTABLE
# lzo1x stream (covers the lzo codec, which previously had no test). If missing, it's skipped
# and -mlzo1x runs on the rest of the corpus (0 streams -> literal -> still reversible).
if command -v gcc >/dev/null 2>&1 && \
   gcc -O2 tests/lzo_gen.c -o "$WORK/lzo_gen" -l:liblzo2.so.2 >/dev/null 2>&1; then
  "$WORK/lzo_gen" 200000 "$CORPUS/50_lzo1x.bin" >/dev/null 2>&1 \
    && echo "-- lzo: 50_lzo1x.bin generated (lzo1x codec covered) --"
fi
if [ "${FULL:-0}" = "1" ] && [ -f "$ROOT/test-files2.tar" ]; then
  echo "-- FULL: adding slice of test-files2.tar (300MB) --"
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
    # Exit codes are checked, not discarded. Without this a precomp or decode
    # that ABORTS is indistinguishable from one that produced non-reversible
    # output: both just fail the cmp below and get reported as "no reversible",
    # sending you looking for a codec bug when the real event was the run dying.
    # That ambiguity cost a full investigation once already (an intermittent
    # "-mzlib -dd1" failure that could not be reproduced afterwards, with no
    # record of whether either command had even succeeded).
    "$XTOOL" precomp $m "$f" "$pmp" >"$WORK/precomp.log" 2>&1; prc=$?
    "$XTOOL" decode "$pmp" "$outf" >"$WORK/decode.log" 2>&1; drc=$?
    pmpsz=$(stat -c%s "$pmp" 2>/dev/null || echo 0)
    if [ "$prc" -ne 0 ] || [ "$drc" -ne 0 ]; then
      res="*** ERROR precomp=$prc decode=$drc ***"; fail=$((fail+1)); err=$((err+1))
    elif cmp -s "$f" "$outf"; then
      res="OK"; pass=$((pass+1))
    else
      res="*** FAIL ***"; fail=$((fail+1))
    fi
    # Preserve the exact artifacts of any failure. An intermittent one is only
    # diagnosable if the .pmp that produced it still exists afterwards.
    if [ "$res" != "OK" ]; then
      fdir="$FAILDIR/$(printf '%s' "${bn}_${m:-literal}" | tr -c 'A-Za-z0-9._-' '_')"
      mkdir -p "$fdir"
      cp -f "$f" "$fdir/input.bin" 2>/dev/null
      [ -s "$pmp" ] && cp -f "$pmp" "$fdir/out.pmp" 2>/dev/null
      [ -s "$outf" ] && cp -f "$outf" "$fdir/decoded.bin" 2>/dev/null
      cp -f "$WORK/precomp.log" "$WORK/decode.log" "$fdir/" 2>/dev/null
      { echo "method: ${m:-<literal>}"; echo "precomp_rc: $prc"; echo "decode_rc: $drc"
        echo "input_size: $insz"; echo "pmp_size: $pmpsz"
        echo "date: $(date -Is)"; echo "loadavg: $(cat /proc/loadavg 2>/dev/null)"
      } > "$fdir/context.txt" 2>/dev/null
      echo "   [artefactos del fallo guardados -> $fdir]" >&2
    fi
    if [ "$insz" -gt 0 ] && [ "$pmpsz" -gt 0 ]; then
      ratio=$(awk "BEGIN{printf \"%.3f\", $pmpsz/$insz}")
    else
      ratio="-"
    fi
    printf "%-26s %-14s %10s %10s %8s  %s\n" "$bn" "${m:-<literal>}" "$insz" "$pmpsz" "$ratio" "$res"
  done
done

echo "-- resumen: $pass OK, $fail FAIL (de los cuales $err por exit code != 0) --"
[ "$err" -gt 0 ] && echo "AVISO: $err caso(s) abortaron; eso NO es un fallo de reversibilidad. Artefactos en $FAILDIR/"
[ "$fail" -eq 0 ] && { echo "REGRESION: PASS (reversibilidad bit-exacta en todo el corpus)"; exit 0; } \
                  || { echo "REGRESION: FALLO ($fail round-trips no reversibles)"; exit 1; }
