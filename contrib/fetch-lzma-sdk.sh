# Sourced by the build-native-*.sh scripts. Fetches the LZMA SDK (Igor Pavlov,
# public domain) that LZMADelphi/lzmadelphi.c compiles, and sets LZMA_SDK_C to
# its C/ directory.
#
# Pinned like pin-repo.sh pins a git checkout: one directory per version, the
# archive checked against its SHA-256, and the version read back from
# 7zVersion.h. The old check was `[ -d lzma-sdk-ref ]`, so an existing
# directory kept whatever version was extracted into it first.
#
# 26.06 since 0.9.9a (was 19.00). Measured with ytool's own parameter grid:
# normal mode (levels 5-9, every lc/lp/pb/fb/dictionary tried) gives the same
# bytes as 19.00; fast mode (levels 0-4) differs, so raw LZMA streams written
# in fast mode by 7-Zip 19 or older no longer reproduce, and those from current
# 7-Zip do. It also brings seven years of decoder fixes, and ytool runs that
# decoder over untrusted input while scanning.
LZMA_SDK_VER="26.06"
LZMA_SDK_URL="https://github.com/ip7z/7zip/releases/download/26.06/lzma2606.7z"
LZMA_SDK_SHA256="1d9da340870b12712e9068be178a4436fbad785486b62aed6e2aa88ea1e3bb65"

fetch_lzma_sdk() {
  local dir="$CSRC/lzma-sdk-$LZMA_SDK_VER"
  if [ ! -f "$dir/C/LzmaEnc.c" ]; then
    local sevenz
    sevenz="$(command -v 7z || command -v 7za || true)"
    if [ -z "$sevenz" ]; then
      echo "ERROR: LZMA SDK $LZMA_SDK_VER missing and no 7z/7za to extract it." >&2
      echo "       Install p7zip (e.g. 'apt install p7zip-full')." >&2
      return 1
    fi
    local arc="$CSRC/lzma-sdk-$LZMA_SDK_VER.7z"
    curl -sfL -o "$arc" "$LZMA_SDK_URL" || { echo "ERROR: download failed: $LZMA_SDK_URL" >&2; return 1; }
    echo "$LZMA_SDK_SHA256  $arc" | sha256sum -c --status \
      || { echo "ERROR: $arc does not match its SHA-256" >&2; rm -f "$arc"; return 1; }
    rm -rf "$dir"; mkdir -p "$dir"
    "$sevenz" x -y -o"$dir" "$arc" >/dev/null || return 1
  fi
  grep -q "MY_VERSION_NUMBERS \"$LZMA_SDK_VER\"" "$dir/C/7zVersion.h" \
    || { echo "ERROR: $dir is not LZMA SDK $LZMA_SDK_VER" >&2; return 1; }
  LZMA_SDK_C="$dir/C"
  echo "   LZMA SDK $LZMA_SDK_VER OK"
}
