#!/usr/bin/env bash
# Makes the reference .ytp files of one PUBLISHED ytool release.
#
#   tests/golden/make.sh <version> <dir with that release's ytool> <corpus dir>
#
# <dir> is the unpacked release package (ytool-linux-x64/ from the GitHub release,
# not a rebuild: the point is what that version really wrote). <corpus dir> is what
# tests/gen_corpus.py writes. Output: tests/golden/<version>/<case>.ytp, and the
# originals in tests/golden/inputs/ (copied once; the corpus depends on the Python,
# Pillow and lz4 of the machine that makes it, so the originals are kept, not rebuilt).
#
# tests/regression.sh decodes every tests/golden/*/*.ytp with the ytool under test
# and compares it with its original: a release must keep decoding what earlier
# releases wrote (docs/ROADMAP-1.0.0.md, point 4). A case a version cannot make
# (a codec it did not have yet) is skipped and said so.
set -u
VER="$1"; BIN="$(cd "$2" && pwd)/ytool"; CORPUS="$(cd "$3" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/$VER"; IN="$HERE/inputs"
mkdir -p "$OUT" "$IN"
[ -x "$BIN" ] || { echo "no ytool at $BIN"; exit 2; }

# case name | input file | options
CASES='
empty|01_empty.bin|-mzlib
tiny_literal|03_tiny_text.bin|
zlib_nol|22_raw_deflate.bin|-mzlib
zlib_l3|20_zlib_streams.bin|-mzlib -l3
preflate_l3|20_zlib_streams.bin|-mpreflate -l3
zlib_many_t4_l3|21_zlib_many.bin|-mzlib -t4 -l3
raw_deflate_l3|22_raw_deflate.bin|-mzlib -l3
dedup_l3|23_dup_streams.bin|-mzlib -dd -l3
dedup_osrep_l3|23_dup_streams.bin|-mzlib -ddo -l3
mixed_l3|24_zlib_mixed.bin|-mzlib -l3
libdeflate_l3|25_libdeflate.bin|-mlibdeflate -l3
lzip_l3|26_lzip.bin|-mlzip -l3
png_l3|61_png_min.bin|-mpng -l3
lzma_l3|63_lzma_alone.bin|-mlzma -l3
pja_j2k_l3|64_jpeg2000.bin|-mpja -l3
pja_jpeg_l3|71_jpeg_min.bin|-mpja -l3
brunsli_l3|71_jpeg_min.bin|-mbrunsli -l3
flac_l3|60_wav_pcm.bin|-mflac -l3
wavpack_l3|60_wav_pcm.bin|-mwavpack -l3
lz4f_l3|70_lz4f.bin|-mlz4f -l3
lz4f_64k_l3|74_lz4f_64k.bin|-mlz4f -l3
lz4f_fast_l3|75_lz4f_fast.bin|-mlz4f -l3
zstd_l3|77_zstd_nocheck.bin|-mzstd -l3
'
made=0; skipped=0
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
while IFS='|' read -r name file opts; do
  [ -n "$name" ] || continue
  src="$CORPUS/$file"
  [ -f "$src" ] || { echo "   skip $name: $file not in the corpus"; skipped=$((skipped+1)); continue; }
  [ -f "$IN/$file" ] || cp "$src" "$IN/$file"
  cmp -s "$src" "$IN/$file" || { echo "   skip $name: $file differs from inputs/$file"; skipped=$((skipped+1)); continue; }
  rm -f "$W/o.ytp" "$W/o.out"
  # shellcheck disable=SC2086
  ( cd "$W" && "$BIN" precomp $opts "$IN/$file" o.ytp > log 2>&1 ) || { echo "   skip $name: $VER cannot ($(tail -1 "$W/log"))"; skipped=$((skipped+1)); continue; }
  # the release itself has to decode it, or it is not a reference
  ( cd "$W" && "$BIN" decode o.ytp o.out > /dev/null 2>&1 ) && cmp -s "$IN/$file" "$W/o.out" \
    || { echo "   skip $name: $VER does not decode its own file"; skipped=$((skipped+1)); continue; }
  # a codec the release lacked processes nothing: say it (the file is still kept,
  # it is a valid file of that version)
  st=$(tr '\r' '\n' < "$W/log" | grep -oE "Streams: [0-9]+ / [0-9]+" | tail -1)
  cp "$W/o.ytp" "$OUT/$name.ytp"
  echo "$name|$file|$opts|$st" >> "$W/manifest"
  made=$((made+1))
done <<< "$CASES"
sort "$W/manifest" > "$OUT/MANIFEST"
echo "$VER: $made files, $skipped skipped -> $OUT"
