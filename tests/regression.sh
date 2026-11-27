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
# ytool looks for srep and osrep next to itself, so that is where to check
XDIR="$(cd "$(dirname "$XTOOL")" && pwd)"
# the binary by an absolute path, for tests that run it from another folder
# (CI gives XTOOL=./ytool.exe)
XABS="$XDIR/$(basename "$XTOOL")"
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
# "-mzlib -dd1" exercises EXTERNAL dedup (srep64/srep.exe); if the binary isn't present,
# StoreDD silently falls back to -1 (in-memory dedup) -> still reversible, just with
# less real coverage until it's generated with contrib/build-plugins-{linux,windows}.sh.
# "-mzlib -r xor"/"-r aes"/"-r rc4" exercise PrecompCrypto.pas (previously with no test):
# CryptoScan1 is a no-op, they only activate by reassigning streams already detected by another
# codec (same as "-r zstd" already did) -> real round-trip on 20_zlib_streams.bin.
# "-mpng" exercises the PNG container (61_png_min.bin, generated in situ, no dependencies).
# "-mpreflate" exercises PreflateDLL against the same streams from 20_zlib_streams.bin.
# (-mpackpng, -mpackmp3 and -mreflate were removed in 0.9.9a.)
# "-mlz4f"/"-mpja"/"-mbrunsli" depend on OPTIONAL corpus files (see gen_corpus.py:
# they require the python module "lz4" and Pillow; 64_jpeg2000.bin also needs Pillow
# built with OpenJPEG). If missing, those files aren't generated and the method runs over 0
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
  "-mpng" "-mpreflate" "-mlz4f" "-mzstd" "-mpja" "-mbrunsli" "-mlzma")

fail=0; pass=0; err=0; dead=0
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
# 75_lz4f_fast.bin must come from the lz4 ytool loads (see gen_corpus.py).
if [ -f "$ROOT/liblz4.so" ]; then export LZ4_LIB="$ROOT/liblz4.so"; else unset LZ4_LIB; fi
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

# ── Cobertura real de codecs ──────────────────────────────────────────────────
# Pares (archivo, metodo) que TIENEN que procesar al menos un stream. Sin esto
# la suite no prueba nada sobre los codecs: cuando un codec no esta disponible
# o no logra recomprimir, ytool guarda el stream literal, y guardar literal es
# perfectamente reversible -- asi que los 399 casos pasan igual. Medido: con
# los 6 plugins .so borrados, la suite daba "399 OK, 0 FAIL, REGRESION: PASS".
# Tres bugs reales se escaparon exactamente asi (packjpg que no cargaba, lz4f
# que no re-encodeaba frames con checksum, y liblz4.dll que nunca se empaqueto
# para Windows dejando -mlz4/-mlz4hc/-mlz4f muertos).
#
# Son MINIMOS (>=1), no igualdades: un bump de codec puede cambiar
# legitimamente cuantos streams detecta, y un umbral exacto se rompe con una
# mejora en vez de con una regresion. Los conteos medidos hoy estan al lado
# como referencia, no como condicion.

# -mreflate NO esta en la lista de arriba, y no es un olvido: necesita
# RAW2HIF_DLL.DLL y HIF2RAW_DLL.DLL, que ningun script de este repo construye y
# de las que no hay fuente abierta conocida. Sin ellas ReflateDLL.DLLLoaded es
# falso, el codec queda deshabilitado y Scan1 sale sin mirar nada: da 0 / 0
# sobre los mismos streams deflate donde -mzlib y -mpreflate dan 6 / 6.
# Tenerlo en la lista solo agregaba 27 casos que no ejercitan nada. Esta en la
# misma categoria que jojpeg y oodle, que el README ya declara no incluidos.
#
# LIMITE CONOCIDO -- este assert NO corre en Windows. El contador de streams se
# lee de la salida de ytool, y en Windows esa salida va directo a la consola:
# no la captura ni PowerShell redirigiendo, ni cmd.exe redirigiendo a archivo
# (probadas las dos; solo se obtiene el banner). Por eso los smoke tests de
# Windows verifican engagement comparando el tamano del .ytp contra el que
# produce un codec que no puede matchear -- un almacenamiento literal pesa
# entrada+~50 bytes, uno enganchado no. Es equivalente en poder pero hay que
# hacerlo a mano; si alguien encuentra como capturar esa salida, este assert
# se puede activar tambien alla y conviene hacerlo.
# 2026-11-26: desde la CLI nueva la salida redirigida SI se captura en Windows
# (ya no va por WriteConsole), asi que este assert ya se puede activar alla.
CODEC_EXPECT="
20_zlib_streams.bin|-mzlib|6
20_zlib_streams.bin|-mpreflate|6
21_zlib_many.bin|-mzlib|200
21_zlib_many.bin|-mpreflate|200
22_raw_deflate.bin|-mzlib|1
23_dup_streams.bin|-mzlib|90
30_over_chunk_20m.bin|-mzlib|498
60_wav_pcm.bin|-mwavpack|1
60_wav_pcm.bin|-mflac|1
61_png_min.bin|-mpng|1
62_png_photo.bin|-mpng|1
63_lzma_alone.bin|-mlzma|1
70_lz4f.bin|-mlz4f|1
73_lz4f_crc.bin|-mlz4f|1
74_lz4f_64k.bin|-mlz4f|1
75_lz4f_fast.bin|-mlz4f|1
76_zstd_levels.bin|-mzstd|4
77_zstd_nocheck.bin|-mzstd|1
50_lzo1x.bin|-mlzo1x|1
71_jpeg_min.bin|-mpja|1
71_jpeg_min.bin|-mbrunsli|1
64_jpeg2000.bin|-mpja|2
"

# Escape valvula para la UNICA configuracion donde no tener codecs es
# esperado: el job Windows de CI compila ytool.exe pero no cruza ninguna DLL
# de plugin. Es opt-out explicito y ruidoso a proposito -- si algun dia se
# activa por accidente, se ve en el log.
: "${ALLOW_MISSING_CODECS:=0}"
if [ "$ALLOW_MISSING_CODECS" = "1" ]; then
  echo "AVISO: ALLOW_MISSING_CODECS=1 -- no se exige que ningun codec procese streams."
  echo "       Esta corrida NO prueba que los codecs funcionen, solo reversibilidad."
fi


# Segunda señal: etapas del pipeline. CODEC_EXPECT de arriba solo ve la PRIMERA
# etapa -- "Streams: X / Y" cuenta lo que hizo el detector de streams y nada
# mas. Una etapa posterior que muera es invisible ahi: escondiendo srep64,
# "-mzlib -dd1" seguia reportando "Streams: 90 / 90", exit 0, sin una sola
# linea de error, y el .ytp cambiaba 76 bytes. El assert de arriba daba verde
# con el dedup externo muerto.
#
# La señal se encontro diferenciando una corrida sana contra una rota (metodo
# general: no adivinar cual es la señal, romperlo y mirar el diff). La linea
# de resumen de tamaños lleva una etapa por transformacion aplicada:
#   -mzlib        Size: A >> B                 -> 1
#   -mzlib -dd    Size: A >> B >> C            -> 2
#   -mzlib -dd1   Size: A >> B >> C >> D       -> 3
# Es independiente del contenido: da igual sobre datos aleatorios que sobre
# streams reales, asi que la expectativa va por metodo, no por archivo.
STAGE_EXPECT="
-mzlib -dd|2
-mzlib -dd1|3
"

expected_stages() {
  [ "$ALLOW_MISSING_CODECS" = "1" ] && { echo 0; return; }
  printf '%s\n' "$STAGE_EXPECT" | while IFS='|' read -r sm sn; do
    [ "$sm" = "$1" ] && { echo "$sn"; return; }
  done | head -1
}

# Devuelve el minimo de streams procesados exigido para (archivo, metodo), o 0.
expected_streams() {
  [ "$ALLOW_MISSING_CODECS" = "1" ] && { echo 0; return; }
  printf '%s\n' "$CODEC_EXPECT" | while IFS='|' read -r ef em en; do
    [ "$ef" = "$1" ] && [ "$em" = "$2" ] && { echo 1; return; }
  done | head -1
}

printf "%-26s %-14s %10s %10s %8s  %s\n" FILE METHOD IN YTP RATIO RESULT
for f in "$CORPUS"/*; do
  bn="$(basename "$f")"
  insz=$(stat -c%s "$f")
  for m in "${METHODS[@]}"; do
    pmp="$WORK/out.ytp"; outf="$WORK/out.bin"
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
    # Cuantos streams proceso realmente el codec (no cuantos detecto).
    # "Streams: X / Y" -> X procesados, Y detectados.
    proc=$(grep -oE "Streams: [0-9]+ / [0-9]+" "$WORK/precomp.log" 2>/dev/null | tail -1 | awk '{print $2}')
    proc="${proc:-0}"
    need=$(expected_streams "$bn" "$m")
    need="${need:-0}"
    stg=$(grep -oE "Size:.*" "$WORK/precomp.log" 2>/dev/null | tail -1 | grep -o ">>" | wc -l)
    stg="${stg:-0}"
    needst=$(expected_stages "$m")
    needst="${needst:-0}"
    if [ "$prc" -ne 0 ] || [ "$drc" -ne 0 ]; then
      res="*** ERROR precomp=$prc decode=$drc ***"; fail=$((fail+1)); err=$((err+1))
    elif ! cmp -s "$f" "$outf"; then
      res="*** FAIL ***"; fail=$((fail+1))
    elif [ "$needst" -ge 1 ] && [ "$stg" -lt "$needst" ]; then
      # Una etapa posterior (dedup) no corrio: el .ytp sale casi igual y el
      # round-trip cierra igual, pero el trabajo no se hizo.
      res="*** ETAPA MUERTA ($stg de $needst etapas) ***"; fail=$((fail+1)); dead=$((dead+1))
    elif [ "$need" -ge 1 ] && [ "$proc" -lt 1 ]; then
      # Reversible pero el codec no hizo nada: guardo todo literal. Es el modo
      # de falla que dejo pasar tres bugs reales.
      res="*** CODEC MUERTO (0 streams procesados) ***"; fail=$((fail+1)); dead=$((dead+1))
    else
      res="OK"; pass=$((pass+1))
    fi
    # Preserve the exact artifacts of any failure. An intermittent one is only
    # diagnosable if the .ytp that produced it still exists afterwards.
    if [ "$res" != "OK" ]; then
      fdir="$FAILDIR/$(printf '%s' "${bn}_${m:-literal}" | tr -c 'A-Za-z0-9._-' '_')"
      mkdir -p "$fdir"
      cp -f "$f" "$fdir/input.bin" 2>/dev/null
      [ -s "$pmp" ] && cp -f "$pmp" "$fdir/out.ytp" 2>/dev/null
      [ -s "$outf" ] && cp -f "$outf" "$fdir/decoded.bin" 2>/dev/null
      cp -f "$WORK/precomp.log" "$WORK/decode.log" "$fdir/" 2>/dev/null
      { echo "method: ${m:-<literal>}"; echo "precomp_rc: $prc"; echo "decode_rc: $drc"
        echo "input_size: $insz"; echo "ytp_size: $pmpsz"
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

# --- -x / -X: extraccion de streams ------------------------------------------
# -X tiene que extraer SOLO los streams cuyo resultado FINAL fue un fallo. Antes
# extraia en cada intento de nivel fallido, asi que un stream que fallaba en l1
# y salia en l6 aparecia como "no procesado": en 24_zlib_mixed.bin daba 5
# archivos donde xtool 0.9.9 da 3. -x tiene que extraer todos los intentados.
XF="$CORPUS/24_zlib_mixed.bin"
if [ -x "$XTOOL" ] && [ -f "$XF" ]; then
  XA="$WORK/x_all"; XU="$WORK/x_unproc"; mkdir -p "$XA" "$XU"
  "$XTOOL" precomp -mzlib -x"$XA" "$XF" "$WORK/x1.ytp" > "$WORK/x1.log" 2>&1
  "$XTOOL" precomp -mzlib -X"$XU" "$XF" "$WORK/x2.ytp" > /dev/null 2>&1
  st=$(tr '\r' '\n' < "$WORK/x1.log" | grep -oE "Streams: [0-9]+ / [0-9]+" | tail -1)
  xp=$(echo "$st" | awk '{print $2}'); xt=$(echo "$st" | awk '{print $4}')
  na=$(ls "$XA" | wc -l); nu=$(ls "$XU" | wc -l)
  same=1
  for f in "$XU"/*; do cmp -s "$f" "$XA/$(basename "$f")" || same=0; done
  if [ -z "$xt" ]; then
    # Windows: la linea "Streams:" va directo a la consola y no se captura (ver
    # el LIMITE CONOCIDO de CODEC_EXPECT). Sin el conteo no hay contra que medir.
    echo "-- -x/-X: omitido, no se pudo leer 'Streams:' (salida no capturable aqui) --"
  elif [ "$xt" -eq 0 ] && [ "${ALLOW_MISSING_CODECS:-0}" = "1" ]; then
    # Sin libreria de zlib (el CI de Windows) no hay streams que extraer. Hasta
    # 2026-11-26 este caso no llegaba aqui: en Windows "Streams:" no se podia
    # capturar y la prueba se omitia arriba.
    echo "-- -x/-X: omitido, zlib no detecto nada ($st) y ALLOW_MISSING_CODECS=1 --"
  elif [ "$na" -eq "$xt" ] && [ "$nu" -eq $((xt - xp)) ] && \
     [ "$nu" -gt 0 ] && [ "$xp" -gt 0 ] && [ "$same" = 1 ]; then
    echo "-- -x/-X: $na extraidos, $nu no procesados ($st) --"; pass=$((pass+1))
  else
    echo "-- *** -x/-X: -x=$na -X=$nu con '$st' (esperado -x=Y, -X=Y-X, -X subconjunto de -x) *** --"
    fail=$((fail+1))
  fi
fi

# --- dos ytool a la vez en la misma carpeta ----------------------------------
# Hasta 0.9.9b el archivo temporal de -dd se llamaba siempre ytool-dd.tmp, en
# el directorio actual: dos precomp con -dd en una carpeta escribian uno en el
# del otro y el .ytp no decodificaba (encontrado corriendo dos suites juntas).
if [ -x "$XTOOL" ] && [ -f "$CORPUS/11_text_8m.bin" ] && [ -f "$CORPUS/23_dup_streams.bin" ]; then
  CC="$WORK/concurrent"; rm -rf "$CC"; mkdir -p "$CC"; cok=1
  ( cd "$CC" && "$XABS" precomp -mzlib -dd "$CORPUS/11_text_8m.bin" a.ytp >/dev/null 2>&1 ) &
  ( cd "$CC" && "$XABS" precomp -mzlib -dd "$CORPUS/23_dup_streams.bin" b.ytp >/dev/null 2>&1 ) &
  wait
  # decode a la vez tambien, desde la misma carpeta (ytool-vm.tmp era fijo)
  ( cd "$CC" && "$XABS" decode a.ytp a.out >/dev/null 2>&1 ) &
  ( cd "$CC" && "$XABS" decode b.ytp b.out >/dev/null 2>&1 ) &
  wait
  cmp -s "$CORPUS/11_text_8m.bin" "$CC/a.out" || cok=0
  cmp -s "$CORPUS/23_dup_streams.bin" "$CC/b.out" || cok=0
  ls "$CC"/*.tmp >/dev/null 2>&1 && cok=0
  if [ "$cok" = 1 ]; then echo "-- dos precomp/decode -dd a la vez en una carpeta: ok --"; pass=$((pass+1))
  else echo "-- *** dos precomp/decode -dd a la vez en una carpeta: fallo *** --"; fail=$((fail+1)); fi
fi

# --- analyze ----------------------------------------------------------------
# Hasta 0.9.9b analyze comparaba el tamano del .ytp, que CRECE cuando un codec
# funciona (guarda los streams desempacados): sobre 200 streams deflate decia
# "No codec improved this file". Ahora compara el tamano despues de -l#. Un
# archivo de texto deflateado tiene que recomendar zlib o preflate, verificado;
# uno aleatorio, ningun codec.
if [ -x "$XTOOL" ] && [ "${ALLOW_MISSING_CODECS:-0}" != "1" ]; then
  python3 - "$WORK" <<'PYEOF'
import random, sys, zlib
random.seed(4); d = sys.argv[1]
words = [''.join(random.choice('abcdefghijklmnop') for _ in range(random.randint(3, 9))) for _ in range(3000)]
out = bytearray()
for i in range(30):
    c = zlib.compress(' '.join(random.choice(words) for _ in range(4000)).encode(), 6)
    out += b'BLOB' + len(c).to_bytes(4, 'little') + c
open(d + '/an_text.bin', 'wb').write(out)
open(d + '/an_rand.bin', 'wb').write(random.randbytes(300000))
PYEOF
  "$XTOOL" analyze -mzlib+preflate+zstd+lz4 -l1 "$WORK/an_text.bin" > "$WORK/an1.log" 2>&1; a1=$?
  "$XTOOL" analyze -mzlib+preflate+zstd+lz4 -l1 "$WORK/an_rand.bin" > "$WORK/an2.log" 2>&1; a2=$?
  if [ $a1 = 0 ] && grep -qE 'Recommended: ytool precomp -m(zlib|preflate)' "$WORK/an1.log" \
     && grep -q 'decodes back byte for byte' "$WORK/an1.log" && [ $a2 = 0 ] \
     && grep -q 'No codec makes this file smaller' "$WORK/an2.log"; then
    echo "-- analyze: recomienda zlib/preflate sobre texto deflateado (verificado), nada sobre aleatorio --"; pass=$((pass+1))
  else
    echo "-- *** analyze: recomendacion equivocada *** --"; sed 's/^/   /' "$WORK/an1.log" "$WORK/an2.log" | tail -20; fail=$((fail+1))
  fi
fi
# -mlz4 sin tamano: el escaner de bloques crudos decodificaba basura sin
# limites (18 s sobre 20 KB con -t>1, mas de 10 minutos sobre 2 MB)
if [ -x "$XTOOL" ] && [ -f "$CORPUS/10_random_2m.bin" ]; then
  S0=$(date +%s); "$XTOOL" precomp -mlz4 -t4 "$CORPUS/10_random_2m.bin" "$WORK/lz4r.ytp" >/dev/null 2>&1; S1=$(date +%s)
  if [ $((S1 - S0)) -le 10 ]; then echo "-- -mlz4 sobre 2 MB aleatorios: $((S1 - S0)) s --"; pass=$((pass+1))
  else echo "-- *** -mlz4 sobre 2 MB aleatorios tardo $((S1 - S0)) s *** --"; fail=$((fail+1)); fi
fi

# --- -ddo: OSREP como dedup externo -----------------------------------------
# Corre si hay un osrep junto a ytool (no viene en el repo; releases de
# YadeWira/omega-srep). Ida y vuelta con y sin -osp, y un .ytp hecho con -ddo
# tiene que pedir osrep al decodificar si falta, no fallar con un error mudo.
if [ -x "$XTOOL" ] && [ -x "$XDIR/osrep" ] && [ -f "$CORPUS/23_dup_streams.bin" ]; then
  DO="$CORPUS/23_dup_streams.bin"; dok=1
  for o in "-ddo" "-ddo -ospm3:l64"; do
    "$XTOOL" precomp -mzlib $o "$DO" "$WORK/do.ytp" >/dev/null 2>&1 && \
      "$XTOOL" decode "$WORK/do.ytp" "$WORK/do.out" >/dev/null 2>&1 && \
      cmp -s "$DO" "$WORK/do.out" || { dok=0; echo "-- *** -ddo [$o]: fallo *** --"; }
  done
  FK="$WORK/noosrep"; rm -rf "$FK"; mkdir -p "$FK"; cp "$XTOOL" "$FK/ytool"; cp "$XDIR"/*.so "$FK/" 2>/dev/null
  "$FK/ytool" decode "$WORK/do.ytp" "$FK/x.out" > "$FK/log" 2>&1 && dok=0
  grep -q 'put "osrep" next to ytool' "$FK/log" || { dok=0; echo "-- *** -ddo sin osrep: sin el mensaje *** --"; }
  if [ "$dok" = 1 ]; then echo "-- -ddo: ida y vuelta (con y sin -osp), y pide osrep si falta --"; pass=$((pass+1)); else fail=$((fail+1)); fi
else
  echo "-- -ddo: omitido (sin osrep junto a ytool) --"
fi

# --- -p (prefetch) en el borde de 4 MB --------------------------------------
# -p8mb fallaba (access violation, exit 1, .ytp de 22 bytes): la mitad de -p es
# la cache de escritura, y con exactamente 4 MB (su bloque) TCacheWriteStream
# escribia en un almacenamiento que no habia creado. 4, 8 y 16 MB, ida y vuelta.
PF="$CORPUS/21_zlib_many.bin"
if [ -x "$XTOOL" ] && [ -f "$PF" ]; then
  pok=1
  for p in 4mb 8mb 16mb; do
    "$XTOOL" precomp -mzlib -p$p "$PF" "$WORK/pf.ytp" >/dev/null 2>&1 && \
      "$XTOOL" decode -p$p "$WORK/pf.ytp" "$WORK/pf.out" >/dev/null 2>&1 && \
      cmp -s "$PF" "$WORK/pf.out" || { pok=0; echo "-- *** -p$p: fallo *** --"; }
  done
  if [ "$pok" = 1 ]; then echo "-- -p4mb/-p8mb/-p16mb: ida y vuelta --"; pass=$((pass+1)); else fail=$((fail+1)); fi
fi

# --- reassign, plugins INI, execute, find/extract/erase/replace -------------
# Estas rutas no tenian una sola prueba y escondian bugs reales (2026-11-25):
# un plugin INI perdia todo stream a -t1 (division por cero), un codec de
# plugin por <stdin>/<stdout> daba access violation en Linux y no producia nada
# en Windows, a -t4 se colgaba (pipes heredados entre hijos), "execute" con un
# programa que no escribe nada guardaba un trozo vacio con exit 0 (datos
# perdidos), y -rA=B se ignoraba. Solo Linux: usa gcc y lee "Streams:".
p3_check() { # nombre condicion-ok
  if [ "$2" = 1 ]; then echo "-- $1: ok --"; pass=$((pass+1))
  else echo "-- *** $1: FALLA *** --"; fail=$((fail+1)); fi
}
p3_streams() { tr '\r' '\n' < "$1" | grep -oE "Streams: [0-9]+ / [0-9]+" | tail -1; }
if [ -x "$XTOOL" ] && [ "$(uname -s)" = Linux ] && command -v gcc >/dev/null; then
  P3="$WORK/p3"; mkdir -p "$P3"
  if gcc -O2 tests/helpers/rle.c -o "$P3/rle" && gcc -O2 tests/helpers/xorer.c -o "$P3/xorer"; then
    # reassign: -rzlib=preflate manda los streams de zlib a preflate (0.9.9:
    # "preflate = 6"); un destino que no puede con ellos no procesa ninguno.
    Z="$CORPUS/20_zlib_streams.bin"
    # Needs libpreflate (the CI does not build the plugins): skipped without it.
    "$XTOOL" precomp -mpreflate -t2 "$Z" /dev/null > "$P3/r0.log" 2>&1
    if [ "$(p3_streams "$P3/r0.log")" = "Streams: 6 / 6" ]; then
      "$XTOOL" precomp -mzlib -rzlib=preflate -t2 "$Z" "$P3/r1.ytp" > "$P3/r1.log" 2>&1
      "$XTOOL" decode "$P3/r1.ytp" "$P3/r1.out" > /dev/null 2>&1
      ok=0; grep -q -- "- preflate = 6 " "$P3/r1.log" && cmp -s "$Z" "$P3/r1.out" && ok=1
      p3_check "reassign -rzlib=preflate (todo a preflate)" $ok
    else
      echo "-- reassign -rzlib=preflate: omitido, preflate no disponible --"
    fi
    "$XTOOL" precomp -mzlib -rzlib=lzo1x -t2 "$Z" "$P3/r2.ytp" > "$P3/r2.log" 2>&1
    "$XTOOL" decode "$P3/r2.ytp" "$P3/r2.out" > /dev/null 2>&1
    ok=0; [ "$(p3_streams "$P3/r2.log")" = "Streams: 0 / 6" ] && cmp -s "$Z" "$P3/r2.out" && ok=1
    p3_check "reassign -rzlib=lzo1x (0 / 6, nada perdido)" $ok

    # -cfgzlib:st<n> (0.9.9): la estrategia de deflate. 24_zlib_mixed.bin tiene
    # un stream Huffman-only: con st2, 0.9.9 procesa solo ese (1 / 8). La
    # estrategia queda en el stream, asi que el decode no necesita la opcion.
    M24="$CORPUS/24_zlib_mixed.bin"
    if [ -f "$M24" ]; then
      "$XTOOL" precomp -mzlib -cfgzlib:st2 -t2 "$M24" "$P3/cf.ytp" > "$P3/cf.log" 2>&1
      "$XTOOL" decode "$P3/cf.ytp" "$P3/cf.out" > /dev/null 2>&1
      ok=0; [ "$(p3_streams "$P3/cf.log")" = "Streams: 1 / 8" ] && cmp -s "$M24" "$P3/cf.out" && ok=1
      p3_check "-cfgzlib:st2 (1 / 8, como 0.9.9)" $ok
    fi

    # -cfgzstd (0.9.9): parametros avanzados. El frame lo escribe la MISMA libzstd
    # que carga ytool (la de al lado del binario, o la del sistema), via ctypes:
    # nivel 9 con hashLog/chainLog/searchLog/minMatch que el nivel solo no da.
    ZL="$ROOT/libzstd.so"; [ -f "$ZL" ] || ZL=libzstd.so.1
    if python3 - "$ZL" "$P3/zc.zst" <<'EOF'
import ctypes, sys
z = ctypes.CDLL(sys.argv[1])
z.ZSTD_createCCtx.restype = ctypes.c_void_p
z.ZSTD_CCtx_setParameter.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
z.ZSTD_compressBound.restype = ctypes.c_size_t
z.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
z.ZSTD_compress2.restype = ctypes.c_size_t
z.ZSTD_compress2.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
z.ZSTD_isError.argtypes = [ctypes.c_size_t]
import random
r = random.Random(7)   # texto irregular: un texto muy repetitivo da el mismo frame con o sin los parametros
w = [bytes(r.choice(b"etaoinshrdlu") for _ in range(r.randint(2, 9))) for _ in range(3000)]
data = b" ".join(r.choice(w) for _ in range(60000))
c = z.ZSTD_createCCtx()
for p, v in [(100, 9), (201, 1), (102, 18), (103, 17), (104, 3), (105, 4)]:
    z.ZSTD_CCtx_setParameter(c, p, v)
cap = z.ZSTD_compressBound(len(data)); out = ctypes.create_string_buffer(cap)
n = z.ZSTD_compress2(c, out, cap, data, len(data))
sys.exit(1 if z.ZSTD_isError(n) else open(sys.argv[2], 'wb').write(out.raw[:n]) and 0)
EOF
    then
      "$XTOOL" precomp -mzstd -t2 "$P3/zc.zst" "$P3/zs0.ytp" > "$P3/zs0.log" 2>&1
      "$XTOOL" precomp -mzstd -cfgzstd:hl18:cl17:sl3:mm4 -t2 "$P3/zc.zst" "$P3/zs1.ytp" > "$P3/zs1.log" 2>&1
      "$XTOOL" decode "$P3/zs1.ytp" "$P3/zs1.out" > /dev/null 2>&1
      ok=0; [ "$(p3_streams "$P3/zs0.log")" = "Streams: 0 / 1" ] && \
        [ "$(p3_streams "$P3/zs1.log")" = "Streams: 1 / 1" ] && cmp -s "$P3/zc.zst" "$P3/zs1.out" && ok=1
      p3_check "-cfgzstd (0 / 1 sin, 1 / 1 con; decode sin la opcion)" $ok
    else
      echo "-- -cfgzstd: omitido, no se pudo escribir el frame con $ZL --"
    fi

    # -b (brute) con zstd y las claves que el formato de 0.9.9a no guardaba.
    # El frame usa los parametros del candidato 1 de la lista barajada de
    # 0.9.9 (wl23 hl27 cl16 sl8 mm4 tl1 st8, sin nivel): -b:n1 tiene que
    # imprimir esa linea exacta y no procesar nada; la linea, pasada a
    # -cfgzstd, procesa el stream (tl y st van como recurso del contenedor) y
    # el decode lo devuelve sin opciones.
    if python3 - "$ZL" "$P3/zb.zst" <<'EOF'
import ctypes, sys, random
z = ctypes.CDLL(sys.argv[1])
z.ZSTD_createCCtx.restype = ctypes.c_void_p
z.ZSTD_CCtx_setParameter.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
z.ZSTD_compressBound.restype = ctypes.c_size_t
z.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
z.ZSTD_compress2.restype = ctypes.c_size_t
z.ZSTD_compress2.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
z.ZSTD_isError.argtypes = [ctypes.c_size_t]
r = random.Random(3)
w = [bytes(r.choice(b"abcdefghijklmnop") for _ in range(r.randint(2, 9))) for _ in range(3000)]
data = b" ".join(r.choice(w) for _ in range(30000))
c = z.ZSTD_createCCtx()
for p, v in zip(range(101, 108), (23, 27, 16, 8, 4, 1, 8)):
    z.ZSTD_CCtx_setParameter(c, p, v)
cap = z.ZSTD_compressBound(len(data)); out = ctypes.create_string_buffer(cap)
n = z.ZSTD_compress2(c, out, cap, data, len(data))
sys.exit(1 if z.ZSTD_isError(n) else open(sys.argv[2], 'wb').write(out.raw[:n]) and 0)
EOF
    then
      ZB_LINE="-cfgzstdwl23:hl27:cl16:sl8:mm4:tl1:st8"
      "$XTOOL" precomp -mzstd -b:n1 "$P3/zb.zst" "$P3/zb0.ytp" > "$P3/zb0.log" 2>&1
      ok=0; grep -qxF -- "$ZB_LINE [1]" "$P3/zb0.log" && \
        [ "$(p3_streams "$P3/zb0.log")" = "Streams: 0 / 1" ] && ok=1
      p3_check "-mzstd -b:n1 halla $ZB_LINE y no procesa nada" $ok
      "$XTOOL" precomp -mzstd "$ZB_LINE" "$P3/zb.zst" "$P3/zb1.ytp" > "$P3/zb1.log" 2>&1
      "$XTOOL" decode "$P3/zb1.ytp" "$P3/zb1.out" > /dev/null 2>&1
      ok=0; [ "$(p3_streams "$P3/zb1.log")" = "Streams: 1 / 1" ] && cmp -s "$P3/zb.zst" "$P3/zb1.out" && ok=1
      p3_check "esa linea en -cfgzstd: 1 / 1 (tl/st en un recurso), decode exacto" $ok
    else
      echo "-- -b zstd: omitido, no se pudo escribir el frame con $ZL --"
    fi

    # Frames como los escribe el CLI de zstd: con un worker (-T1, su defecto),
    # que da otros bytes que zstd de un hilo por encima de un job; y desde un
    # pipe, sin tamano en la cabecera. Ambos se guardaban tal cual. Necesitan
    # una libzstd con ZSTD_MULTITHREAD (la que construye build-plugins-linux.sh).
    if python3 - "$ZL" "$P3" <<'EOF'
import ctypes, sys, random
z = ctypes.CDLL(sys.argv[1]); d = sys.argv[2]
z.ZSTD_createCCtx.restype = ctypes.c_void_p
z.ZSTD_CCtx_setParameter.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
z.ZSTD_CCtx_setParameter.restype = ctypes.c_size_t
z.ZSTD_isError.argtypes = [ctypes.c_size_t]
z.ZSTD_compress2.restype = ctypes.c_size_t
z.ZSTD_compress2.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
class Buf(ctypes.Structure):
    _fields_ = [("p", ctypes.c_void_p), ("size", ctypes.c_size_t), ("pos", ctypes.c_size_t)]
z.ZSTD_compressStream2.restype = ctypes.c_size_t
z.ZSTD_compressStream2.argtypes = [ctypes.c_void_p, ctypes.POINTER(Buf), ctypes.POINTER(Buf), ctypes.c_int]
r = random.Random(11)
w = [bytes(r.choice(b"abcdefghijklmnopqrst") for _ in range(r.randint(2, 9))) for _ in range(5000)]
data = b" ".join(r.choice(w) for _ in range(400000))
c = z.ZSTD_createCCtx()
if z.ZSTD_isError(z.ZSTD_CCtx_setParameter(c, 400, 1)):
    sys.exit(2)
for p, v in ((100, 1), (201, 1)):
    z.ZSTD_CCtx_setParameter(c, p, v)
out = ctypes.create_string_buffer(len(data) + 65536)
n = z.ZSTD_compress2(c, out, len(out), data, len(data))
open(d + "/zmt.zst", "wb").write(out.raw[:n])
c = z.ZSTD_createCCtx()
for p, v in ((100, 19), (201, 1)):
    z.ZSTD_CCtx_setParameter(c, p, v)
src = ctypes.create_string_buffer(data, len(data))
o = Buf(ctypes.cast(out, ctypes.c_void_p), len(out), 0)
i = Buf(ctypes.cast(src, ctypes.c_void_p), len(data), 0)
while i.pos < i.size:
    z.ZSTD_compressStream2(c, ctypes.byref(o), ctypes.byref(i), 0)
e = Buf(None, 0, 0)
while z.ZSTD_compressStream2(c, ctypes.byref(o), ctypes.byref(e), 2) != 0:
    pass
open(d + "/zpipe.zst", "wb").write(out.raw[:o.pos])
EOF
    then
      for zf in zmt zpipe; do
        "$XTOOL" precomp -mzstd "$P3/$zf.zst" "$P3/$zf.ytp" > "$P3/$zf.log" 2>&1
        "$XTOOL" decode "$P3/$zf.ytp" "$P3/$zf.out" > /dev/null 2>&1
        ok=0; [ "$(p3_streams "$P3/$zf.log")" = "Streams: 1 / 1" ] && cmp -s "$P3/$zf.zst" "$P3/$zf.out" && ok=1
        p3_check "zstd como el CLI ($zf): 1 / 1, decode exacto" $ok
      done
    else
      echo "-- zstd -T1/pipe: omitido (libzstd sin ZSTD_MULTITHREAD o sin python) --"
    fi

    # -cfglz4 (0.9.9): ds = favorDecSpeed de lz4f (un frame de nivel 12 con
    # favorDecSpeed=1 solo sale con la opcion) y x/ac = tamano y aceleracion de
    # un bloque lz4 crudo (igual que -mlz4:s/a). Los escribe la misma liblz4.
    L4="$ROOT/liblz4.so"; [ -f "$L4" ] || L4=liblz4.so.1
    if python3 - "$L4" "$P3" <<'EOF'
import ctypes, sys, random
z = ctypes.CDLL(sys.argv[1]); r = random.Random(7)
w = [bytes(r.choice(b"etaoinshrdlu") for _ in range(r.randint(2, 9))) for _ in range(3000)]
data = b" ".join(r.choice(w) for _ in range(40000))
class FI(ctypes.Structure):
    _fields_ = [("bs", ctypes.c_int), ("bm", ctypes.c_int), ("cc", ctypes.c_int), ("ft", ctypes.c_int),
                ("csz", ctypes.c_ulonglong), ("did", ctypes.c_uint), ("bc", ctypes.c_int)]
class P(ctypes.Structure):
    _fields_ = [("fi", FI), ("lvl", ctypes.c_int), ("af", ctypes.c_uint), ("ds", ctypes.c_uint),
                ("r", ctypes.c_uint * 3)]
z.LZ4F_compressFrameBound.restype = ctypes.c_size_t
z.LZ4F_compressFrame.restype = ctypes.c_size_t
z.LZ4F_isError.argtypes = [ctypes.c_size_t]
p = P(); p.lvl = 12; p.ds = 1
cap = z.LZ4F_compressFrameBound(ctypes.c_size_t(len(data)), ctypes.byref(p))
out = ctypes.create_string_buffer(cap)
n = z.LZ4F_compressFrame(out, ctypes.c_size_t(cap), data, ctypes.c_size_t(len(data)), ctypes.byref(p))
if z.LZ4F_isError(ctypes.c_size_t(n)): sys.exit(1)
open(sys.argv[2] + "/ds.lz4", "wb").write(out.raw[:n])
blk = data[:65536]
cap = z.LZ4_compressBound(len(blk)); out = ctypes.create_string_buffer(cap)
n = z.LZ4_compress_fast(blk, out, len(blk), cap, 8)
if n <= 0: sys.exit(1)
open(sys.argv[2] + "/ac.bin", "wb").write(b"HEAD" * 100 + out.raw[:n] + b"TAIL" * 100)
# una aceleracion > 127 (no cabe en los bits de Option): la primera desde 150
# que el scan de lz4 crudo reconoce (primer byte F0..F4) y que comprime
r = random.Random(7)
w = [bytes(r.choice(b"etaoinshrdlu") for _ in range(r.randint(2, 9))) for _ in range(60)]
blk = b" ".join(r.choice(w) for _ in range(30000))[:65536]
cap = z.LZ4_compressBound(len(blk)); out = ctypes.create_string_buffer(cap)
n0 = z.LZ4_compress_fast(blk, out, len(blk), cap, 1); b0 = out.raw[:n0]
for a in range(150, 3000):
    n = z.LZ4_compress_fast(blk, out, len(blk), cap, a)
    if 0xF0 <= out.raw[0] <= 0xF4 and n < 60000 and out.raw[:n] != b0:
        open(sys.argv[2] + "/abig.bin", "wb").write(b"HEAD" * 100 + out.raw[:n] + b"TAIL" * 100)
        break
else:
    sys.exit(1)
EOF
    then
      "$XTOOL" precomp -mlz4f -t2 "$P3/ds.lz4" "$P3/l0.ytp" > "$P3/l0.log" 2>&1
      "$XTOOL" precomp -mlz4f -cfglz4:ds1 -t2 "$P3/ds.lz4" "$P3/l1.ytp" > "$P3/l1.log" 2>&1
      "$XTOOL" decode "$P3/l1.ytp" "$P3/l1.out" > /dev/null 2>&1
      ok=0; [ "$(p3_streams "$P3/l0.log")" = "Streams: 0 / 1" ] && \
        [ "$(p3_streams "$P3/l1.log")" = "Streams: 1 / 1" ] && cmp -s "$P3/ds.lz4" "$P3/l1.out" && ok=1
      p3_check "-cfglz4:ds1 (lz4f favorDecSpeed: 0 / 1 sin, 1 / 1 con)" $ok
      "$XTOOL" precomp -mlz4:s64kb -t2 "$P3/ac.bin" "$P3/a0.ytp" > "$P3/a0.log" 2>&1
      "$XTOOL" precomp -mlz4 -cfglz4:x64kb:ac8 -t2 "$P3/ac.bin" "$P3/a1.ytp" > "$P3/a1.log" 2>&1
      "$XTOOL" decode "$P3/a1.ytp" "$P3/a1.out" > /dev/null 2>&1
      ok=0; [ "$(p3_streams "$P3/a0.log")" = "Streams: 0 / 1" ] && \
        [ "$(p3_streams "$P3/a1.log")" = "Streams: 1 / 1" ] && cmp -s "$P3/ac.bin" "$P3/a1.out" && ok=1
      p3_check "-cfglz4:x64kb:ac8 (bloque lz4 crudo: 0 / 1 sin, 1 / 1 con)" $ok
      # -b (0.9.9): busqueda bruta, no procesa nada; imprime las lineas que
      # reconstruyen cada stream. Sobre los mismos ds.lz4 y ac.bin.
      "$XTOOL" precomp -mlz4f -b -t2 "$P3/ds.lz4" "$P3/b0.ytp" > "$P3/b0.log" 2>&1
      "$XTOOL" precomp -mlz4:s64kb -b -t2 "$P3/ac.bin" "$P3/b1.ytp" > "$P3/b1.log" 2>&1
      ok=0; grep -qx -- '-mlz4f:l12 -cfglz4af0:ds1 \[1\]' "$P3/b0.log" && \
        grep -qx -- '-cfglz4ac8 \[1\]' "$P3/b1.log" && \
        [ "$(p3_streams "$P3/b1.log")" = "Streams: 0 / 1" ] && ok=1
      p3_check "-b (lz4f: l12 ds1; lz4: ac8; sin procesar)" $ok
      "$XTOOL" precomp -mlz4:s64kb -b3 -t2 "$P3/ac.bin" "$P3/b2.ytp" > "$P3/b2.log" 2>&1
      ok=0; grep -qx 'No possible parameters match' "$P3/b2.log" && ok=1
      p3_check "-b3 (3 aceleraciones, 2..4: ninguna coincide)" $ok
      # lo que -b encuentra en un bloque con aceleracion > 127 se usa tal cual:
      # 0 / 1 sin la opcion, 1 / 1 con ella, y decode lo rehace (Resource)
      "$XTOOL" precomp -mlz4:s64kb -b -t2 "$P3/abig.bin" "$P3/b3.ytp" > "$P3/b3.log" 2>&1
      AC=$(grep -m1 -oE '^-cfglz4ac[0-9]+' "$P3/b3.log" | sed 's/^-cfglz4//')
      "$XTOOL" precomp -mlz4:s64kb -t2 "$P3/abig.bin" "$P3/b4.ytp" > "$P3/b4.log" 2>&1
      "$XTOOL" precomp -mlz4 -cfglz4:x64kb:$AC -t2 "$P3/abig.bin" "$P3/b5.ytp" > "$P3/b5.log" 2>&1
      "$XTOOL" decode "$P3/b5.ytp" "$P3/b5.out" > /dev/null 2>&1
      ok=0; [ -n "$AC" ] && [ "${AC#ac}" -gt 127 ] && \
        [ "$(p3_streams "$P3/b4.log")" = "Streams: 0 / 1" ] && \
        [ "$(p3_streams "$P3/b5.log")" = "Streams: 1 / 1" ] && cmp -s "$P3/abig.bin" "$P3/b5.out" && ok=1
      p3_check "-b encuentra -cfglz4$AC (> 127) y con ella 1 / 1, decode exacto" $ok
    else
      echo "-- -cfglz4: omitido, no se pudieron escribir los frames con $L4 --"
    fi

    # zipcrypto (0.8.8): un plugin INI marca un stream cifrado con la clave en
    # un archivo; descifrado, adentro hay deflate que zlib reconstruye a -d1.
    ZD="$P3/plugZ"; mkdir -p "$ZD"
    printf 'secret' > "$ZD/k.key"
    printf '[Stream1]\nName=zc\nCodec=zipcrypto:k.key\nBigEndian=0\nSignature=0x3152435A\nStructure=Signature(4),CSize(4),Stream\nCompressedSize=CSize\nDecompressedSize=CSize\n' > "$ZD/zc.ini"
    python3 - "$P3/zc.bin" "$CORPUS/11_text_8m.bin" <<'EOF'
import random, struct, sys, zlib
crc = []
for i in range(256):
    c = i
    for _ in range(8):
        c = (c >> 1) ^ 0xEDB88320 if c & 1 else c >> 1
    crc.append(c)
k = [0x12345678, 0x23456789, 0x34567890]
def upd(b):
    k[0] = (k[0] >> 8) ^ crc[(k[0] ^ b) & 0xff]
    k[1] = ((k[1] + (k[0] & 0xff)) * 134775813 + 1) & 0xffffffff
    k[2] = (k[2] >> 8) ^ crc[(k[2] ^ (k[1] >> 24)) & 0xff]
for ch in b'secret': upd(ch)
r = random.Random(7)
co = zlib.compressobj(6, zlib.DEFLATED, -15)
plain = bytes(r.getrandbits(8) for _ in range(12)) + co.compress(open(sys.argv[2], 'rb').read()[:150000]) + co.flush()
enc = bytearray()
for p in plain:
    t = (k[2] | 2) & 0xffff
    enc.append(p ^ (((t * (t ^ 1)) >> 8) & 0xff)); upd(p)
open(sys.argv[1], 'wb').write(bytes(r.getrandbits(8) for _ in range(300)) + b'ZCR1' + struct.pack('<I', len(enc)) + bytes(enc) + bytes(r.getrandbits(8) for _ in range(300)))
EOF
    "$XTOOL" precomp -mzc+zlib -d1 -bd"$ZD" -t2 "$P3/zc.bin" "$P3/zc.ytp" > "$P3/zc.log" 2>&1 </dev/null
    "$XTOOL" decode -bd"$ZD" "$P3/zc.ytp" "$P3/zc.out" > /dev/null 2>&1 </dev/null
    ok=0; [ "$(p3_streams "$P3/zc.log")" = "Streams: 2 / 2" ] && cmp -s "$P3/zc.bin" "$P3/zc.out" && ok=1
    p3_check "zipcrypto + zlib a -d1 (2 / 2)" $ok

    # plugins INI: formato de juguete TOY1 + codec externo rle en sus tres formas.
    python3 - "$P3/toy.bin" <<'EOF'
import random, struct, sys
r = random.Random(4); out = bytearray()
def rle(b):
    o = bytearray(); i = 0
    while i < len(b):
        j = i
        while j < len(b) and b[j] == b[i] and j - i < 255: j += 1
        o += bytes([j - i, b[i]]); i = j
    return bytes(o)
for k in range(5):
    raw = b''.join(bytes([r.randrange(97, 123)]) * r.randrange(20, 200) for _ in range(300))
    comp = rle(raw)
    out += bytes(r.getrandbits(8) for _ in range(300))
    out += b'TOY1' + struct.pack('<II', len(comp), len(raw)) + comp
out += bytes(r.getrandbits(8) for _ in range(300))
open(sys.argv[1], 'wb').write(out)
EOF
    for mode in "S:rle d <stdin> <stdout>:rle c <stdin> <stdout>" \
                "F:rle d [filein] [fileout]:rle c [filein] [fileout]" \
                "L:rle L d <library>:rle L c <library>"; do
      m=${mode%%:*}; rest=${mode#*:}; enc=${rest%%:*}; dec=${rest#*:}
      PD="$P3/plug$m"; mkdir -p "$PD"; cp "$P3/rle" "$PD/"
      printf '[Stream1]\nName=toy\nCodec=toyx\nBigEndian=0\nSignature=0x31594F54\nStructure=Signature(4),CSize(4),DSize(4),Stream\nCompressedSize=CSize\nDecompressedSize=DSize\n' > "$PD/toy.ini"
      printf '[toyx]\nEncode=%s\nDecode=%s\n' "$enc" "$dec" > "$PD/$(basename "$XTOOL").ini"
      for t in 1 4; do
        timeout 300 "$XTOOL" precomp -mtoy -bd"$PD" -t$t "$P3/toy.bin" "$P3/t$m$t.ytp" > "$P3/t$m$t.log" 2>&1 </dev/null
        timeout 300 "$XTOOL" decode -bd"$PD" "$P3/t$m$t.ytp" "$P3/t$m$t.out" > /dev/null 2>&1 </dev/null
        ok=0; [ "$(p3_streams "$P3/t$m$t.log")" = "Streams: 5 / 5" ] && cmp -s "$P3/toy.bin" "$P3/t$m$t.out" && ok=1
        p3_check "plugin INI modo $m -t$t (5 / 5)" $ok
      done
      ok=0; cmp -s "$P3/t${m}1.ytp" "$P3/t${m}4.ytp" && ok=1
      p3_check "plugin INI modo $m: mismo .ytp a -t1 y -t4" $ok
    done

    # execute: mismo programa para ir y volver (xor). {filein}/{fileout} no le
    # pasa el nombre, asi que no escribe nada: el trozo tiene que quedar tal
    # cual, no vacio.
    cat "$CORPUS/11_text_8m.bin" "$CORPUS/10_random_2m.bin" > "$P3/ex.bin"
    cp "$P3/xorer" "$(dirname "$XTOOL")/xorer"
    for syn in "xorer {stdin} {stdout}" "xorer [filein] [fileout]" "xorer {filein} {fileout}"; do
      rm -f "$P3/ex.ytp" "$P3/ex.out"
      "$XTOOL" execute -c4mb -t2 "$P3/ex.bin" "$P3/ex.ytp" $syn > /dev/null 2>&1
      "$XTOOL" decode "$P3/ex.ytp" "$P3/ex.out" $syn > /dev/null 2>&1
      ok=0; cmp -s "$P3/ex.bin" "$P3/ex.out" && ok=1
      p3_check "execute '$syn' round-trip" $ok
    done
    rm -f "$(dirname "$XTOOL")/xorer"

    # find / extract / erase / replace sobre los streams de -x del bloque anterior.
    if [ -d "${XA:-}" ] && [ -f "$XF" ]; then
      cp "$XF" "$P3/orig.bin"
      "$XTOOL" find -t1 "$XA" "$P3/orig.bin" "$P3/f1.dat" > /dev/null 2>&1
      "$XTOOL" find -t4 "$XA" "$P3/orig.bin" "$P3/f2.dat" > /dev/null 2>&1
      mkdir -p "$P3/ex_dir"
      "$XTOOL" extract "$P3/f1.dat" "$P3/orig.bin" "$P3/ex_dir" > /dev/null 2>&1
      ok=0; cmp -s "$P3/f1.dat" "$P3/f2.dat" && diff -rq "$XA" "$P3/ex_dir" > /dev/null && ok=1
      p3_check "find reproducible (-t1 == -t4) y extract == -x" $ok
      cp "$XF" "$P3/er.bin"
      "$XTOOL" erase -t2 "$XA" "$P3/er.bin" "$P3/er.dat" > /dev/null 2>&1
      e1=0; cmp -s "$XF" "$P3/er.bin" || e1=1
      "$XTOOL" decode "$P3/er.dat" "$XA" "$P3/er.bin" > /dev/null 2>&1
      ok=0; [ $e1 = 1 ] && cmp -s "$XF" "$P3/er.bin" && ok=1
      p3_check "erase blanquea y decode lo restaura" $ok
      mkdir -p "$P3/new"
      python3 -c "
import os, sys
for f in os.listdir(sys.argv[1]):
    open(os.path.join(sys.argv[2], f), 'wb').write(open(os.path.join(sys.argv[1], f), 'rb').read()[::-1])
" "$XA" "$P3/new"
      cp "$XF" "$P3/rp.bin"
      "$XTOOL" replace -t2 "$XA" "$P3/new" "$P3/rp.bin" "$P3/rp.dat" > /dev/null 2>&1
      e1=0; cmp -s "$XF" "$P3/rp.bin" || e1=1
      "$XTOOL" decode "$P3/rp.dat" "$XA" "$P3/rp.bin" > /dev/null 2>&1
      ok=0; [ $e1 = 1 ] && cmp -s "$XF" "$P3/rp.bin" && ok=1
      p3_check "replace cambia y decode lo restaura" $ok
    fi
  else
    echo "-- reassign/plugins/execute: omitido, no compilaron los helpers --"
  fi
fi

# --- integridad del passthrough literal --------------------------------------
# El digest XTP1 cubria solo los streams. En un .ytp donde ningun codec engancho
# los bytes pasaban de largo sin verificacion: medido, 40 de 40 flips de un byte
# decodificaban con exit 0 y devolvian datos distintos. Un fallo silencioso.
# Este bloque exige lo contrario: un .ytp corrupto tiene que FALLAR el decode.
if [ -x "$XTOOL" ]; then
  IGP="$WORK/ig_src.bin"; IGPMP="$WORK/ig.ytp"; IGOUT="$WORK/ig.out"
  # Entrada sin streams: nada comprimido, todo passthrough literal, que es
  # exactamente el caso que no estaba cubierto.
  python3 -c "
import random, sys
random.seed(20261125)
open('$IGP','wb').write(random.randbytes(200000))
" 2>/dev/null
  if "$XTOOL" precomp -mzlib "$IGP" "$IGPMP" >/dev/null 2>&1 && [ -s "$IGPMP" ]; then
    # control: el .ytp intacto decodifica
    if "$XTOOL" decode "$IGPMP" "$IGOUT" >/dev/null 2>&1 && cmp -s "$IGP" "$IGOUT"; then
      echo "-- integridad: .ytp intacto decodifica --"
    else
      echo "-- *** integridad: el .ytp intacto NO decodifica *** --"
      fail=$((fail+1))
    fi
    # el caso: un byte cambiado en el passthrough tiene que fallar
    python3 -c "
d = bytearray(open('$IGPMP','rb').read())
# lejos de la cabecera, dentro de los datos que nadie proceso
d[len(d)//2] ^= 0xFF
open('$WORK/ig_bad.ytp','wb').write(d)
" 2>/dev/null
    rm -f "$WORK/ig_bad.out"
    # Desde XTP2 (0.9.9b) cada bloque lleva un hash de sus literales: un byte
    # cambiado ahi tiene que fallar, siempre.
    if "$XTOOL" decode "$WORK/ig_bad.ytp" "$WORK/ig_bad.out" >/dev/null 2>&1; then
      echo "-- *** integridad: .ytp corrupto decodifico con exit 0 (SILENCIOSO) *** --"
      fail=$((fail+1))
    else
      echo "-- integridad: .ytp corrupto rechazado --"
      # Ademas de rechazar, no debe dejar el archivo de salida a medias: quien lo
      # ejecute en un script no mira el exit code. Esto si se exige siempre: es
      # barato y es el comportamiento correcto una vez que el rechazo existe.
      if [ -f "$WORK/ig_bad.out" ]; then
        echo "-- *** integridad: el decode fallido dejo un archivo de salida *** --"
        fail=$((fail+1))
      fi
    fi
  else
    echo "-- integridad: (no se pudo generar el .ytp de prueba) --"
  fi
fi

# --- referencias {$L} de las unidades conservadas ----------------------------
# Existe por un fallo real: al recortar mORMot de 976 archivos a 11 se conservaron
# los .pas y se borraron los .obj que esos .pas referencian bajo
# {$ifdef MSWINDOWS}. El build de Linux seguia verde (esa rama no se compila aca)
# y la CI de Windows estuvo tres commits en rojo por dos objetos que faltaban.
# Un build local no puede avalar una rama que nunca compila; esto si.
# Se resuelve en Python porque el patron lleva "$L" literal y escaparlo en bash
# terminaba comparando la cadena equivocada.
if command -v python3 >/dev/null 2>&1; then
  MISSING_L="$(python3 - "$ROOT/contrib/mORMot" <<'PYEOF'
import os, re, sys
root = sys.argv[1]
units = ["SynCommons", "SynCrypto", "SynLZ", "SynTable", "SynKylix",
         "SynFPCTypInfo", "SynFPCLinux", "SynFPCx64MM"]
dead = ("padlock", "deflate.obj", "trees.obj", "SynEcc32O2.obj")
missing = []
for u in units:
    f = os.path.join(root, u + ".pas")
    if not os.path.exists(f):
        continue
    src = open(f, encoding="utf-8", errors="replace").read()
    for ref in re.findall(r"\{\$L\s+([^}]+)\}", src):
        base = os.path.basename(ref.replace("\\", "/"))
        if base.startswith(dead) or ref.replace("\\", "/").startswith("static/"):
            continue
        if not os.path.exists(os.path.join(root, base)):
            missing.append(base)
print(" ".join(sorted(set(missing))))
PYEOF
)"
  if [ -n "$MISSING_L" ]; then
    echo "-- *** mORMot: faltan objetos referenciados:$MISSING_L *** --"
    fail=$((fail+1))
  else
    echo "-- mORMot: objetos de carga diferida presentes --"
  fi
fi

# --- srep: reproducibilidad y metodos -------------------------------------
# La suite de arriba prueba reversibilidad; esto prueba dos propiedades que no
# se ven en un round-trip y que costaron bugs reales:
#   1. -dd<N> con un metodo fuera de rango fallaba con un .ytp de 34 bytes y
#      exit 0. Un error de linea de comandos tiene que ser un error.
#   2. El output de srep no era reproducible (clave VMAC aleatoria). Con -seed
#      dos corridas tienen que dar el MISMO .ytp; sin eso no se puede fijar un
#      archivo por hash ni comparar dos builds.
if [ -x "$XTOOL" ] && [ -f "$XDIR/srep64" -o -f "$XDIR/srep" -o -f "$XDIR/srep.exe" ]; then
  SEED="$(printf 'ab%.0s' $(seq 1 32))"
  SP1="$WORK/rep1.ytp"; SP2="$WORK/rep2.ytp"; SPR="$WORK/rep.out"
  if "$XTOOL" precomp -mzlib -dd3 -seed"$SEED" "$CORPUS/23_dup_streams.bin" "$SP1" >/dev/null 2>&1 \
  && "$XTOOL" precomp -mzlib -dd3 -seed"$SEED" "$CORPUS/23_dup_streams.bin" "$SP2" >/dev/null 2>&1; then
    if cmp -s "$SP1" "$SP2"; then
      echo "-- srep: -seed reproducible --"
    else
      echo "-- srep: *** -seed NO reproducible *** --"
      fail=$((fail+1))
    fi
    if "$XTOOL" decode "$SP1" "$SPR" >/dev/null 2>&1 && cmp -s "$CORPUS/23_dup_streams.bin" "$SPR"; then
      echo "-- srep: round-trip con -seed --"
    else
      echo "-- srep: *** round-trip con -seed fallo *** --"
      fail=$((fail+1))
    fi
  else
    echo "-- srep: (sin helper o -dd3 no soportado, se omiten estas pruebas) --"
  fi
  # Un metodo fuera de rango tiene que fallar, no producir un .ytp vacio.
  if "$XTOOL" precomp -mzlib -dd9 "$CORPUS/23_dup_streams.bin" "$WORK/bad.ytp" >/dev/null 2>&1; then
    echo "-- srep: *** -dd9 (invalido) NO fallo *** --"
    fail=$((fail+1))
  else
    echo "-- srep: -dd9 rechazado --"
  fi
  # srep que falla: hasta 2026-11-26 ytool no miraba su codigo de salida y
  # dejaba un .ytp roto con exit 0. Un srep falso (exit 4, mensaje en stderr)
  # junto a una copia de ytool tiene que dar exit != 0 y el mensaje de srep.
  if [ "$(uname -s)" = Linux ] && [ -f "$XTOOL" ]; then
    FK="$WORK/fakesrep"; rm -rf "$FK"; mkdir -p "$FK"
    cp "$XTOOL" "$FK/ytool"; cp "$XDIR"/*.so "$FK/" 2>/dev/null
    # srep64 is what a 64-bit ytool runs, srep a 32-bit one
    printf '#!/bin/sh\necho "  ERROR! simulated failure" >&2\nexit 4\n' > "$FK/srep64"
    cp "$FK/srep64" "$FK/srep"; chmod +x "$FK/srep64" "$FK/srep"
    # desde $FK: ytool_<pid>_<n>-dd.tmp (la copia que srep lee) va al directorio actual
    if ( cd "$FK" && ./ytool precomp -mzlib -dd3 "$CORPUS/23_dup_streams.bin" o.ytp > log 2>&1 ); then
      echo "-- srep: *** un srep que falla dio exit 0 *** --"; fail=$((fail+1))
    elif grep -q "simulated failure" "$FK/log"; then
      echo "-- srep: un srep que falla hace fallar a precomp, con su mensaje --"
    else
      echo "-- srep: *** fallo sin el mensaje de srep *** --"; fail=$((fail+1))
    fi
    ls "$FK"/*-dd.tmp >/dev/null 2>&1 && { echo "-- srep: *** quedo un -dd.tmp *** --"; fail=$((fail+1)); }
  fi
fi

echo "-- resumen: $pass OK, $fail FAIL ($err por exit code != 0, $dead por codec muerto) --"
[ "$dead" -gt 0 ] && echo "AVISO: $dead caso(s) fueron reversibles pero el codec no proceso NINGUN stream (guardo literal)."
[ "$err" -gt 0 ] && echo "AVISO: $err caso(s) abortaron; eso NO es un fallo de reversibilidad. Artefactos en $FAILDIR/"
[ "$fail" -eq 0 ] && { echo "REGRESION: PASS (reversibilidad bit-exacta en todo el corpus)"; exit 0; } \
                  || { rev=$((fail-err-dead))
       echo "REGRESION: FALLO ($rev no reversibles, $err abortados, $dead con codec muerto)"; exit 1; }
