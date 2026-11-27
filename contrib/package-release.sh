#!/usr/bin/env bash
# Arma los paquetes de release y se niega a producirlos si algo no cierra.
#
# Existe porque cada release hasta ahora se armo a mano, y cada uno se llevo su
# incidente. Los chequeos de abajo no son ceremonia: cada uno corresponde a algo
# que efectivamente se publico roto.
#
#   binario rancio        winbuild.ps1 salia 0 aunque fpc fallara y no borraba
#                         la salida anterior -> se publico un .exe de la semana
#                         previa. Chequeo: cada artefacto mas nuevo que su fuente.
#   DLL que no cargaba    packjpg_dll.dll compilada con -posix importaba
#                         libwinpthread-1.dll, ausente en Windows de fabrica ->
#                         LoadLibrary fallaba con 126 y el codec quedaba mudo.
#                         Chequeo: tabla de imports contra una lista permitida.
#   DLL faltante          liblz4.dll nunca se empaqueto -> -mlz4/-mlz4hc/-mlz4f
#                         muertos en Windows desde siempre. Chequeo: manifiesto
#                         explicito, falta uno y aborta.
#   directorio duplicado  los zips salieron con ytool-windows-x64/ytool-windows-x64/.
#                         Chequeo: un solo nivel de anidamiento.
#   README desactualizado decia omega-srep v1.0.1 con el binario reportando 1.0.5,
#                         y que lz4 iba compilado adentro "sin DLL" con la DLL al
#                         lado. Chequeo: cruzar lo que dice contra lo que hay.
#   codec mudo            un codec que no hace nada pasa todos los round-trips,
#                         porque un almacenamiento literal es reversible.
#                         Chequeo: suite en modo ESTRICTO + engagement medido
#                         sobre el paquete ya extraido.
#
# Uso:
#   contrib/package-release.sh <outdir> [--x86] [--win-bin <dir-con-ytool.exe-y-ytool-x86.exe>]
#
# --x86 tambien arma ytool-linux-x86.tar.gz con contrib/build-linux-x86.sh
# (hace falta FPC386=<FPC 3.2.2 i386-linux>, y ZLIB32 si no hay lib32z1-dev).
#
# Sin --win-bin arma solo Linux. Los binarios de Windows no se pueden construir
# desde aca (hace falta FPC nativo en Windows), asi que se pasan ya compilados y
# el script los valida igual que a los propios.
set -uo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "== $* =="; }
ok()   { echo "   ok: $*"; }

[ $# -ge 1 ] || die "uso: $0 <outdir> [--win-bin <dir>]"
OUT="$1"; shift
WINBIN=""
X86=0
while [ $# -gt 0 ]; do
  case "$1" in
    --win-bin) WINBIN="${2:-}"; shift 2 ;;
    --x86) X86=1; shift ;;
    *) die "argumento desconocido: $1" ;;
  esac
done

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
mkdir -p "$OUT" || die "no se puede crear $OUT"
OUT="$(cd "$OUT" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Manifiesto explicito. Si un artefacto no esta aca no viaja, y si esta y falta
# el script aborta -- que es como se detecta una DLL que nadie empaqueto.
LINUX_FILES="ytool libzstd.so libbrunsli.so libfast-lzma2.so libpja.so libpreflate.so libFLAC.so libwavpack.so osrep"
# Programas que viajan junto a ytool.exe en los zips (OSREP para -ddo, MIT)
WIN_EXES="osrep"
WIN_DLLS="pja brunsli libFLAC_dynamic wavpackdll preflate_dll fast-lzma2 libzstd"

# DLLs del sistema que Windows trae de fabrica. Cualquier otra cosa en la tabla
# de imports es una dependencia que el usuario no tiene.
# Todas viven en System32 en cualquier Windows soportado. La lista se amplia
# solo con DLLs que efectivamente vienen con el sistema -- agregar aca lo que
# sea que aparezca vaciaria el chequeo de contenido.
WIN_ALLOWED_IMPORTS="KERNEL32.dll USER32.dll msvcrt.dll ADVAPI32.dll SHELL32.dll ole32.dll OLEAUT32.dll VERSION.dll WS2_32.dll GDI32.dll COMDLG32.dll SHLWAPI.dll bcrypt.dll RPCRT4.dll IMM32.dll WINMM.dll ntdll.dll USERENV.dll psapi.dll dbghelp.dll wsock32.dll CRYPT32.dll SECUR32.dll NETAPI32.dll"

step "preflight"
command -v fpc  >/dev/null || die "falta fpc"
command -v tar  >/dev/null || die "falta tar"
command -v zip  >/dev/null || die "falta zip"
command -v strings >/dev/null || die "falta strings (binutils)"
[ -n "$WINBIN" ] && { command -v objdump >/dev/null || die "falta objdump (hace falta para revisar imports de las DLL)"; }
if [ -n "$(git status --porcelain 2>/dev/null | grep -v '^??')" ]; then
  echo "   aviso: hay cambios sin commitear; el paquete no va a corresponder a ningun commit"
fi
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo desconocido)"
ok "commit $COMMIT"

step "build linux"
bash contrib/build-native-linux.sh  >/dev/null 2>&1 || die "build-native-linux.sh fallo"
bash contrib/build-plugins-linux.sh >/dev/null 2>&1 || die "build-plugins-linux.sh fallo"
mkdir -p .fpcout
fpc -Mdelphi -Sg -O2 -FU.fpcout -Fucompat -Fucommon -Fuprecompressor -Fuio \
    -Fuimports -Fusources -Fucontrib/mORMot -Fucontrib/LZ4Delphi -Fucontrib/ZSTD4Delphi \
    -Fucontrib/XXHASH4Delphi -Fucontrib/ParseExpression -Fucontrib/LZMADelphi -Fucontrib/StaticLibs \
    -oytool ytool.dpr >/dev/null 2>&1 || die "fpc fallo"
ok "construido"

step "frescura: cada artefacto mas nuevo que la fuente mas nueva"
NEWEST_SRC="$(find . -name '*.pas' -o -name '*.dpr' 2>/dev/null | grep -v '/\.csrc/' | xargs ls -t 2>/dev/null | head -1)"
[ -n "$NEWEST_SRC" ] || die "no se encontro ninguna fuente"
for f in $LINUX_FILES; do
  [ -f "$f" ] || die "falta el artefacto $f (esta en el manifiesto pero no en el arbol)"
done
[ ytool -nt "$NEWEST_SRC" ] || die "ytool es mas viejo que $NEWEST_SRC -- binario rancio"
ok "ytool mas nuevo que $NEWEST_SRC"

step "suite de regresion en modo ESTRICTO"
# Sin ALLOW_MISSING_CODECS a proposito: aca SI se le exige a cada codec que
# procese streams. Ese opt-out existe para CI, que no construye plugins.
if ! bash tests/regression.sh > "$STAGE/regression.log" 2>&1; then
  tail -25 "$STAGE/regression.log" >&2
  die "la suite fallo -- no se empaqueta"
fi
grep -q 'codec muerto' "$STAGE/regression.log" && \
  grep -q '0 por codec muerto' "$STAGE/regression.log" || die "la suite no reporto el conteo de codecs muertos"
tail -2 "$STAGE/regression.log" | sed 's/^/   /'
ok "suite verde en estricto"

step "README linux: cruzar lo que dice contra lo que hay"
RM_LINUX="$ROOT/contrib/release-notes/README.linux.txt"
[ -f "$RM_LINUX" ] || die "falta $RM_LINUX"
# srep no se empaqueta: SREP 3.93a es "All rights reserved" (THIRD_PARTY.md).
grep -q "srep" "$RM_LINUX" || die "el README linux no explica que srep no viene incluido"
ok "README linux revisado"

# Arma ytool-linux-<arch>.tar.gz desde <dir> (donde estan ytool y sus .so) y
# prueba el paquete ya extraido: engagement, no solo round-trip.
package_linux() { # arch dir
  local arch="$1" src="$2"
  step "armar tarball linux $arch"
  local D="$STAGE/ytool-linux-$arch"; mkdir -p "$D"
  for f in $LINUX_FILES; do
    [ -f "$src/$f" ] || die "falta $src/$f"
    cp "$src/$f" "$D/"
  done
  cp "$RM_LINUX" "$D/README.txt"
  chmod +x "$D/ytool"
  ( cd "$STAGE" && tar czf "$OUT/ytool-linux-$arch.tar.gz" "ytool-linux-$arch" ) || die "tar fallo"
  local DEPTH
  DEPTH="$(tar tzf "$OUT/ytool-linux-$arch.tar.gz" | awk '{n=gsub("/","/",$0); print n}' | sort -u | tr '\n' ' ')"
  [ "$DEPTH" = "1 " ] || die "el tarball tiene anidamiento '$DEPTH', se esperaba un solo nivel"
  ok "ytool-linux-$arch.tar.gz ($(stat -c %s "$OUT/ytool-linux-$arch.tar.gz") bytes, un nivel)"

  step "smoke del paquete linux $arch ya extraido: engagement, no solo round-trip"
  local EX="$STAGE/extract-$arch"; mkdir -p "$EX"
  tar xzf "$OUT/ytool-linux-$arch.tar.gz" -C "$EX"
  P="$EX/ytool-linux-$arch"
  FAILED=0
  smoke pja     71_jpeg_min.bin
  smoke brunsli 71_jpeg_min.bin
  smoke lz4f    74_lz4f_64k.bin
  smoke lz4f    75_lz4f_fast.bin
  smoke zstd    76_zstd_levels.bin
  smoke zlib    20_zlib_streams.bin
  smoke preflate 20_zlib_streams.bin
  # -ddo con el osrep del paquete: ida y vuelta, y que osrep haya corrido (una
  # etapa mas en el resumen de tamanos que sin -ddo)
  if [ -f "$CORPUS/23_dup_streams.bin" ]; then
    cp "$CORPUS/23_dup_streams.bin" "$P/in.bin"
    local st0 st1
    st0=$( cd "$P" && ./ytool precomp -mzlib in.bin a.ytp 2>&1 | grep -o '>>' | wc -l )
    st1=$( cd "$P" && ./ytool precomp -mzlib -ddo in.bin o.ytp 2>&1 | grep -o '>>' | wc -l )
    ( cd "$P" && ./ytool decode o.ytp back.bin >/dev/null 2>&1 )
    if cmp -s "$P/in.bin" "$P/back.bin" && [ "$st1" -gt "$st0" ]; then
      echo "   ok: -ddo con el osrep del paquete ($st1 etapas)"
    else
      echo "   FALLA -ddo con el osrep del paquete (etapas $st0 -> $st1)"; FAILED=1
    fi
    rm -f "$P"/in.bin "$P"/a.ytp "$P"/o.ytp "$P"/back.bin
  fi
  [ "$FAILED" = 0 ] || die "el smoke del paquete linux $arch fallo"
}

CORPUS="$STAGE/corpus"
# Como en tests/regression.sh: 75_lz4f_fast.bin tiene que salir del lz4 que
# ytool carga. Sin LZ4_LIB lo escribe el modulo de python, otra version de lz4,
# y el modo rapido de cada version da bytes distintos: el smoke fallaba por eso.
if [ -f "$ROOT/liblz4.so" ]; then export LZ4_LIB="$ROOT/liblz4.so"; else unset LZ4_LIB; fi
python3 tests/gen_corpus.py "$CORPUS" >/dev/null 2>&1 || die "no se pudo generar el corpus"
smoke() { # codec archivo
  local m="$1" f="$2"
  [ -f "$CORPUS/$f" ] || { echo "   (sin material para -m$m, salteado)"; return; }
  cp "$CORPUS/$f" "$P/in.bin"
  ( cd "$P" && ./ytool precomp "-m$m" in.bin real.ytp >/dev/null 2>&1
                ./ytool precomp -mflac in.bin lit.ytp  >/dev/null 2>&1
                ./ytool decode real.ytp back.bin       >/dev/null 2>&1 )
  local r l rt
  r="$(stat -c %s "$P/real.ytp" 2>/dev/null || echo 0)"
  l="$(stat -c %s "$P/lit.ytp"  2>/dev/null || echo 0)"
  cmp -s "$P/in.bin" "$P/back.bin" && rt=ok || rt=MISMATCH
  rm -f "$P"/real.ytp "$P"/lit.ytp "$P"/back.bin "$P"/in.bin
  if [ "$rt" != ok ]; then echo "   FALLA -m$m sobre $f: round-trip $rt"; FAILED=1; return; fi
  # Un almacenamiento literal pesa lo mismo que el de un codec que no matchea.
  if [ "$r" = "$l" ]; then echo "   FALLA -m$m sobre $f: no engancho (pmp=$r == literal=$l)"; FAILED=1; return; fi
  printf '   ok: -m%-9s %-20s pmp=%-8s literal=%s\n' "$m" "$f" "$r" "$l"
}

package_linux x64 "$ROOT"

if [ "$X86" = 1 ]; then
  step "build linux x86"
  bash contrib/build-linux-x86.sh > "$STAGE/build-x86.log" 2>&1 || { tail -15 "$STAGE/build-x86.log" >&2; die "build-linux-x86.sh fallo"; }
  [ build-x86/ytool -nt "$NEWEST_SRC" ] || die "build-x86/ytool es mas viejo que $NEWEST_SRC"
  ok "construido"
  # Un host x86-64 suele no tener libz de 32 bits instalada: la que se uso
  # para enlazar sirve para correr el smoke.
  [ -n "${ZLIB32:-}" ] && export LD_LIBRARY_PATH="$ZLIB32${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  package_linux x86 "$ROOT/build-x86"
fi

if [ -z "$WINBIN" ]; then
  step "listo (solo linux)"
  ls -1 "$OUT" | sed 's/^/   /'
  echo "   para los zips de Windows: volver a correr con --win-bin <dir>"
  exit 0
fi

step "paquetes windows"
[ -d "$WINBIN" ] || die "no existe $WINBIN"
[ -f "$WINBIN/ytool.exe" ]     || die "falta $WINBIN/ytool.exe"
[ -f "$WINBIN/ytool-x86.exe" ] || die "falta $WINBIN/ytool-x86.exe"
RM_WIN="$ROOT/contrib/release-notes/README.windows.txt"
[ -f "$RM_WIN" ] || die "falta $RM_WIN"

check_imports() { # archivo
  local f="$1" bad=""
  local imports
  # LC_ALL=C obligatorio: objdump traduce sus encabezados, y con la locale del
  # sistema en español 'DLL Name:' no aparece. Sin esto el grep no encuentra
  # nada y el chequeo pasa sin haber mirado.
  imports="$(LC_ALL=C objdump -p "$f" 2>/dev/null | grep -oE 'DLL Name: .*' | sed 's/DLL Name: //' | tr -d '\r')"
  # Un import table ilegible es un fallo, no un aviso. Todo PE valido importa
  # al menos KERNEL32; si no se leyo nada, el que esta roto es el chequeo, y un
  # chequeo roto que devuelve exito es peor que no tenerlo.
  [ -n "$imports" ] || { echo "   FALLA no se pudo leer la tabla de imports de $(basename "$f")"; return 1; }
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    # una DLL del propio paquete es una dependencia legitima
    case " $WIN_DLLS " in *" ${d%.dll} "*) continue ;; esac
    local hit=0
    for a in $WIN_ALLOWED_IMPORTS; do
      [ "$(echo "$d" | tr 'A-Z' 'a-z')" = "$(echo "$a" | tr 'A-Z' 'a-z')" ] && hit=1 && break
    done
    [ "$hit" = 0 ] && bad="$bad $d"
  done <<< "$imports"
  [ -z "$bad" ] || { echo "   FALLA $(basename "$f") importa DLLs que Windows no trae:$bad"; return 1; }
  return 0
}

WFAIL=0
for spec in "x64:" "x86:-x86"; do
  arch="${spec%%:*}"; sfx="${spec#*:}"
  D="$STAGE/ytool-windows-$arch"; rm -rf "$D"; mkdir -p "$D"
  cp "$WINBIN/ytool${sfx}.exe" "$D/ytool.exe"
  for d in $WIN_DLLS; do
    if   [ -f "$ROOT/${d}${sfx}.dll" ]; then cp "$ROOT/${d}${sfx}.dll" "$D/${d}.dll"
    elif [ -z "$sfx" ] && [ -f "$ROOT/${d}.dll" ]; then cp "$ROOT/${d}.dll" "$D/${d}.dll"
    else die "falta la DLL ${d} para $arch (buscada como ${d}${sfx}.dll)"
    fi
  done
  for e in $WIN_EXES; do
    [ -f "$ROOT/${e}${sfx}.exe" ] || die "falta ${e}${sfx}.exe para $arch"
    cp "$ROOT/${e}${sfx}.exe" "$D/${e}.exe"
  done
  cp "$RM_WIN" "$D/README.txt"
  AFAIL=0
  for f in "$D"/*.dll "$D"/*.exe; do check_imports "$f" || AFAIL=1; done
  if [ "$AFAIL" != 0 ]; then
    # No se arma el zip: un paquete con una dependencia que el usuario no tiene
    # es justo el que no queremos que exista y se suba por inercia.
    echo "   $arch NO empaquetado por los imports de arriba"
    WFAIL=1
    continue
  fi
  ( cd "$STAGE" && zip -qr "$OUT/ytool-windows-$arch.zip" "ytool-windows-$arch" ) || die "zip fallo"
  LV="$(unzip -l "$OUT/ytool-windows-$arch.zip" | awk '$4!=""{n=gsub("/","/",$4); print n}' | sort -u | tr '\n' ' ')"
  [ "$LV" = "0 1 " ] || die "el zip $arch tiene anidamiento '$LV', se esperaba '0 1'"
  ok "ytool-windows-$arch.zip ($(stat -c %s "$OUT/ytool-windows-$arch.zip") bytes, un nivel, imports limpios)"
done
[ "$WFAIL" = 0 ] || die "hay DLLs con dependencias que Windows no provee"

step "listo"
echo "   commit: $COMMIT"
ls -1 "$OUT" | sed 's/^/   /'
echo
echo "   NOTA: el engagement de los binarios de Windows NO se verifica aca: correr"
echo "   tests/smoke-windows.cmd en la VM (Windows 10 y 7, x64 y x86) con el corpus"
echo "   de tests/gen_corpus.py y la lista CODEC_EXPECT de tests/regression.sh."
