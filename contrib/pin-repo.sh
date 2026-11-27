# Helper compartido: deja un checkout EXACTAMENTE en la revision pedida.
#
# Se sourcea desde los build-*.sh:
#   . "$(dirname "$0")/pin-repo.sh"
#   pin_repo https://github.com/lz4/lz4 "$CSRC/lz4" "$LZ4_REF"
#
# Existe porque el patron `[ -d "$dir" ] || git clone --branch <ver>` deja el
# pin como texto muerto: si el directorio ya existe a otra version, el clone
# se saltea en silencio y el build usa lo que hubiera ahi.
#
# Eso no es hipotetico. El liblz4.dll publicado en v0.9.8 se construyo desde
# lz4 1.10.0 aunque el script pedia v1.9.4, porque build-native-linux.sh
# clonaba antes al mismo $CSRC/lz4 sin --branch y ganaba la carrera. La misma
# guarda dejo contrib/.csrc/packJPG clavado en v5.0d cuando el pin ya decia
# v5.0f, y hubo que borrarlo a mano.
#
# Ese skew importa: entre lz4 1.9.4 y 1.10.0, LZ4HC_CLEVEL_MIN paso de 3 a 2
# (lib/lz4hc.h:47), asi que el nivel 2 -- el primer candidato que prueba la
# busqueda de nivel de PrecompLZ4 -- es un algoritmo distinto en cada version.
# Medido: bloques de largo identico y bytes distintos, que pasan el gate de
# tamano de PrecompLZ4.pas:599 y se escriben mal sin excepcion.
#
# Preferir un SHA sobre un tag: un tag se puede mover, un SHA no.

pin_repo() {
  pr_url="$1"; pr_dir="$2"; pr_ref="$3"
  pr_name="$(basename "$pr_dir")"

  if [ -d "$pr_dir/.git" ]; then
    pr_have="$(git -C "$pr_dir" rev-parse HEAD 2>/dev/null || echo none)"
    pr_want="$(git -C "$pr_dir" rev-parse --verify -q "${pr_ref}^{commit}" 2>/dev/null || echo none)"
    if [ "$pr_have" != none ] && [ "$pr_have" = "$pr_want" ]; then
      echo "   pin OK: $pr_name @ $pr_ref"
      return 0
    fi
    echo "   pin: $pr_name esta en ${pr_have} pero se pidio $pr_ref -- corrigiendo"
    git -C "$pr_dir" remote set-url origin "$pr_url" 2>/dev/null \
      || git -C "$pr_dir" remote add origin "$pr_url"
  else
    echo "   pin: clonando $pr_name @ $pr_ref"
    rm -rf "$pr_dir"
    mkdir -p "$pr_dir"
    git -C "$pr_dir" init -q .
    git -C "$pr_dir" remote add origin "$pr_url"
  fi

  # GitHub acepta fetch de un SHA suelto; si el servidor no lo permite,
  # caer al tag y despues a un fetch completo.
  git -C "$pr_dir" fetch -q --depth 1 origin "$pr_ref" 2>/dev/null \
    || git -C "$pr_dir" fetch -q --depth 1 origin "refs/tags/$pr_ref:refs/tags/$pr_ref" 2>/dev/null \
    || git -C "$pr_dir" fetch -q origin
  git -C "$pr_dir" checkout -q --detach FETCH_HEAD 2>/dev/null \
    || git -C "$pr_dir" checkout -q --detach "$pr_ref"

  pr_got="$(git -C "$pr_dir" rev-parse HEAD)"

  # Si el ref pedido era un SHA, verificar que efectivamente quedamos ahi.
  # Sin esto un fallback silencioso volveria a dejar el pin como sugerencia.
  case "$pr_ref" in
    *[!0-9a-f]*) : ;;                      # no es hex puro -> era un tag
    ???????*)
      case "$pr_got" in
        "$pr_ref"*) : ;;
        *) echo "   ERROR: $pr_name quedo en $pr_got, se pidio $pr_ref" >&2
           return 1 ;;
      esac ;;
  esac

  # Si el repo trae submodulos, sincronizarlos al commit pedido. No-op cuando
  # no hay .gitmodules, que es el caso de todos los deps de hoy -- brunsli se
  # clonaba con --recursive pero no declara ninguno.
  if [ -f "$pr_dir/.gitmodules" ]; then
    git -C "$pr_dir" submodule update --init --recursive --depth 1 >/dev/null 2>&1 \
      || echo "   aviso: submodulos de $pr_name no se pudieron sincronizar" >&2
  fi

  echo "   pin: $pr_name @ $pr_got"
}

# lz4_lib32 <lz4 checkout> <out dir>: a copy of lz4's lib/ for a 32-bit
# build whose fast mode writes the same bytes as a 64-bit one. lz4.c picks
# its match finder's hash by register size (LZ4_hash5 on 64-bit, LZ4_hash4
# on 32-bit), so a 32-bit lz4 does not reproduce a fast-mode stream a 64-bit
# lz4 wrote, and a .ytp made on x64 holding one failed to decode on x86.
# reg_t becomes 64 bits everywhere, as lz4 already does for the x32 ABI.
# Measured: 39 settings (fast acceleration 1-1000, HC 1-12, frames) x 8
# inputs, all equal to x86-64; 64-bit builds are unchanged by it.
lz4_lib32() {
  local src="$1/lib" out="$2"
  rm -rf "$out" && mkdir -p "$out" && cp "$src"/*.c "$src"/*.h "$out"/ || return 1
  sed -i 's|^#if defined(__x86_64__)$|#if 1  /* ytool: 64-bit reg_t on 32-bit too (lz4_lib32 in contrib/pin-repo.sh) */|' "$out/lz4.c"
  grep -q 'ytool: 64-bit reg_t' "$out/lz4.c" || { echo "   lz4_lib32: the reg_t line moved; check lz4.c" >&2; return 1; }
}

# fetch_osrep <asset> <dest>: OSREP (github.com/YadeWira/omega-srep, MIT), the
# external deduplicator for -ddo, as released, checked against the SHA-256 of
# that release's SHA256SUMS. Its format v7 (-m6, the default) is frozen, so a
# .ytp made with one release decodes with the later ones.
OSREP_VER="0.0.18"
fetch_osrep() {
  local asset="$1" dest="$2" sum
  case "$asset" in
    osrep-linux-x86_64)       sum=d1a36a9ddf5d4eeb12ecca01e17ef2a73b4eb64cdb61ae154cbee7506a552094 ;;
    osrep-linux-x86)          sum=d19c7831dde49d680c7ea04ac03b583f231236fbd06ee49bfe98c597357c27fb ;;
    osrep-windows-x86_64.exe) sum=b80f0905f80c124d582f4a9624ffb3784346409140ed52348c97ed6d438c1660 ;;
    osrep-windows-x86.exe)    sum=8dcec665d8c774831538e9d43090bc0ed57aceecc91937f2b0563beedd595817 ;;
    *) echo "   fetch_osrep: no pinned sum for $asset" >&2; return 1 ;;
  esac
  echo "==> OSREP $OSREP_VER ($(basename "$dest"))"
  local tmp="$dest.download"
  if curl -sfL -o "$tmp" "https://github.com/YadeWira/omega-srep/releases/download/v${OSREP_VER}/$asset" \
     && echo "$sum  $tmp" | sha256sum -c --status; then
    mv "$tmp" "$dest" && chmod +x "$dest" && echo "   OK -> $(basename "$dest")"
  else
    rm -f "$tmp"; echo "   (OSREP: descarga fallida o SHA-256 distinto)"; return 1
  fi
}

# build_libdeflate <out> <cc> [flags...]: libdeflate (github.com/ebiggers/
# libdeflate, MIT) as a shared library, for -mlibdeflate. Pinned: its own
# documentation says each version writes other bytes at the same level, so a
# .ytp restores only with the version that made it. v1.26 writes the same
# bytes on x86 and x86-64 (measured, levels 0-12). $CSRC must be set.
LIBDEFLATE_REF="92e6a0db9fa848d742f9eb286c92afc60f2c3dda"   # v1.26
build_libdeflate() {
  local out="$1" cc="$2"; shift 2
  echo "==> libdeflate ($(basename "$out"))"
  pin_repo https://github.com/ebiggers/libdeflate "$CSRC/libdeflate" "$LIBDEFLATE_REF" || return 1
  ( cd "$CSRC/libdeflate" && "$cc" "$@" -shared -O2 -fvisibility=hidden -I. \
      lib/utils.c lib/deflate_compress.c lib/deflate_decompress.c lib/adler32.c \
      lib/crc32.c lib/zlib_compress.c lib/zlib_decompress.c lib/gzip_compress.c \
      lib/gzip_decompress.c lib/x86/cpu_features.c -o "$out" ) \
    && echo "   OK -> $(basename "$out")" || { echo "   (libdeflate fallo)"; return 1; }
}

# build_lzlib <out> <cc> [flags...]: lzlib (nongnu.org/lzip/lzlib.html,
# 2-clause BSD) as a shared library, for -mlzip. A release tarball (lzlib has
# no public git), checked against its SHA-256. lzlib 1.16 rebuilds byte for
# byte what lzip 1.22, 1.24 and 1.26 write at every level, on x86 and x86-64
# (measured). $CSRC must be set.
LZLIB_VER="1.16"
LZLIB_SHA256="203228de911780309dad6813e51541d7ea89469784f01cb661edba080ff1b038"
# fetch_lzo: lzo 2.10 (www.oberhumer.com, GPL-2.0+), the official tarball
# checked against its SHA-256, unpacked in $CSRC/lzo-$LZO_VER. -mlzo1x/-mlzo1c/
# -mlzo2a since 0.9.9f use it built in; before, Linux loaded the system's
# liblzo2.so.2 and Windows an unchecked download.
LZO_VER="2.10"
LZO_SHA256="c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072"
LZO_SRC="lzo1c_rr lzo1x_1 lzo1x_1k lzo1x_1l lzo1x_1o lzo1x_9x lzo1x_d2 lzo1c_9x lzo1c_d2 lzo2a_9x lzo2a_d2 lzo_init lzo_util lzo_ptr lzo_str lzo_crc"
fetch_lzo() {
  local tgz="$CSRC/lzo-$LZO_VER.tar.gz" dir="$CSRC/lzo-$LZO_VER"
  if ! echo "$LZO_SHA256  $tgz" | sha256sum -c --status 2>/dev/null; then
    curl -sL -o "$tgz" "https://www.oberhumer.com/opensource/lzo/download/lzo-$LZO_VER.tar.gz"
    echo "$LZO_SHA256  $tgz" | sha256sum -c --status \
      || { rm -f "$tgz"; echo "   (lzo: descarga fallida o SHA-256 distinto)"; return 1; }
  fi
  [ -d "$dir" ] || tar xzf "$tgz" -C "$CSRC" || return 1
}

# fetch_lzlib: the checked tarball unpacked in $CSRC/lzlib-$LZLIB_VER
fetch_lzlib() {
  local tgz="$CSRC/lzlib-$LZLIB_VER.tar.gz" dir="$CSRC/lzlib-$LZLIB_VER"
  if ! echo "$LZLIB_SHA256  $tgz" | sha256sum -c --status 2>/dev/null; then
    curl -sL -o "$tgz" "https://download.savannah.gnu.org/releases/lzip/lzlib/lzlib-$LZLIB_VER.tar.gz"
    echo "$LZLIB_SHA256  $tgz" | sha256sum -c --status \
      || { rm -f "$tgz"; echo "   (lzlib: descarga fallida o SHA-256 distinto)"; return 1; }
  fi
  [ -d "$dir" ] || tar xzf "$tgz" -C "$CSRC" || return 1
}
build_lzlib() {
  local out="$1" cc="$2"; shift 2
  local dir="$CSRC/lzlib-$LZLIB_VER"
  echo "==> lzlib ($(basename "$out"))"
  fetch_lzlib || return 1
  ( cd "$dir" && "$cc" "$@" -shared -O2 lzlib.c -o "$out" ) \
    && echo "   OK -> $(basename "$out")" || { echo "   (lzlib fallo)"; return 1; }
}
