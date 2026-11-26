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
