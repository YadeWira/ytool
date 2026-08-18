#!/usr/bin/env bash
# Lista las frases causales que estas por publicar, para que las mires.
#
# No arregla nada ni bloquea nada: solo hace que la lista aparezca sola en vez
# de depender de que uno se acuerde de revisarla. Nace de un patron medido en
# este repo: afirmar el mecanismo ("es por X") cuando lo unico establecido es
# el disparador ("el sintoma se va si toco X"). Las dos frases son utiles; la
# segunda es la honesta hasta que la primera este probada.
#
# Uso:
#   contrib/check-causal-claims.sh              # cambios staged
#   contrib/check-causal-claims.sh HEAD~1       # un commit
#   contrib/check-causal-claims.sh origin/main  # una rama entera
#
# Por que sobre el DIFF y no sobre el repo: medido aca, el mismo patron da 282
# coincidencias repo-wide (inservible, la mayoria son explicaciones de diseño
# perfectamente validas) y entre 0 y 4 por commit (revisable de un vistazo).
# El chequeo sirve sobre lo que estas por publicar, no sobre todo lo escrito.
set -uo pipefail
cd "$(dirname "$0")/.."

# (1) Frases causales: hablan de una decision TUYA. Casi siempre legitimas --
#     sos la autoridad sobre tu propia decision -- pero son donde se cuela
#     "es por X" cuando solo tenes "el sintoma se va si toco X".
CAUSAL='because|due to|root cause|the reason is|caused by|explains why|it is caused|porque|causa raiz'

# (2) Afirmaciones sobre OTRO sistema: el compilador, el loader, el kernel, una
#     libreria ajena. Eso ya no es una decision tuya, es una afirmacion sobre el
#     mundo, y requiere medicion. Casi ninguna es legitima sin instrumentar.
#     Distincion de packJPG: la regla no es la palabra, es DE QUIEN HABLA la
#     oracion. Por eso (1) da cientos de coincidencias casi todas buenas y (2)
#     da un punado casi todas malas.
#
#     Van las DOS formas gramaticales, porque la del sujeto sola deja pasar la
#     peor. Medido aca: la afirmacion mas daniña que tuvo este repo era
#     "a GCC strict-aliasing miscompile of ...", que no tiene sujeto-verbo --
#     el reclamo esta NOMINALIZADO, metido dentro de un sustantivo. Esa forma
#     es mas grave que la del sujeto: presenta el mecanismo como una cosa que
#     existe y tiene nombre, en vez de como una proposicion que se puede
#     discutir.
COMP='GCC|clang|MSVC|the compiler|the linker|the loader|the kernel|the scheduler|the allocator|the driver|the runtime|glibc|mingw|the optimi[sz]er|the CPU'
# forma sujeto-verbo:  "GCC's optimizations miscompiled", "the loader does not service"
AGENCY_SUBJ="(${COMP})('s)?[^.]{0,40}(miscompil|optimi[sz]e|reorder|inline|elide|strip|assume|ignore|drop|service|schedule)"
# forma nominalizada:  "a GCC miscompile", "a kernel bug", "a loader failure"
AGENCY_NOUN="(a|an|the) (${COMP})[^.]{0,30}(miscompile|bug|failure|quirk|misoptimi[sz]ation|defect)"
PAT="${CAUSAL}|${AGENCY_SUBJ}|${AGENCY_NOUN}"
RANGE="${1:-}"

if [ -n "$RANGE" ]; then
  DIFF=$(git diff "$RANGE" --unified=0 -- '*.pas' '*.dpr' '*.sh' '*.ps1' '*.md' '*.py' 2>/dev/null)
else
  DIFF=$(git diff --cached --unified=0 -- '*.pas' '*.dpr' '*.sh' '*.ps1' '*.md' '*.py' 2>/dev/null)
  [ -z "$DIFF" ] && DIFF=$(git diff --unified=0 -- '*.pas' '*.dpr' '*.sh' '*.ps1' '*.md' '*.py' 2>/dev/null)
fi

# Se buscan las coincidencias sobre las lineas agregadas Y sobre esas mismas
# lineas UNIDAS, y esto no es una mejora marginal: es lo que hace valido al
# chequeo.
#
# El fallo de una busqueda por linea no es uniforme, esta SESGADO hacia lo que
# queres encontrar. Medido sobre los comentarios de este repo: las frases que
# cargan una afirmacion tienen mediana de 241 caracteres (maximo 335), contra
# una linea envuelta de ~76. Osea que un reclamo ocupa tipicamente ~3 lineas y
# una busqueda por linea ve un tercio de el. Contando coincidencias: 46 por
# linea contra 56 uniendo, o sea que 1 de cada 5 solo aparece unida.
#
# La consecuencia practica es que si medis la tasa de aciertos de un chequeo
# por linea te va a dar mejor de lo que realmente es PARA LA CLASE QUE TE
# IMPORTA: las afirmaciones cortas (que suelen ser las banales) entran en una
# linea, las largas con condiciones (que son las que hay que revisar) no.
# El caso que lo destapo: "which GCC's -O2+ strict-aliasing / optimizations
# miscompiled" envuelve exactamente entre el sujeto y el verbo.
ADDED=$(printf '%s\n' "$DIFF" | grep '^+' | grep -v '^+++' || true)
HITS=$(printf '%s\n' "$ADDED" | grep -inE "$PAT" || true)
JOINED=$(printf '%s\n' "$ADDED" | sed 's/^+[[:space:]]*[#/]*[[:space:]]*//' | tr '\n' ' ')
WRAPPED=$(printf '%s\n' "$JOINED" | grep -oiE "$PAT" | sort -u || true)
if [ -n "$WRAPPED" ]; then
  HITS="$HITS
  [tambien, uniendo lineas envueltas]
$(printf '%s\n' "$WRAPPED" | sed 's/^/    /')"
fi

if [ -z "$HITS" ]; then
  echo "sin frases causales en lo que estas por publicar."
  exit 0
fi

echo "Frases causales agregadas -- revisar cada una:"
echo "  -> tenes el mecanismo medido, o solo el disparador?"
echo
printf '%s\n' "$HITS" | sed 's/^/  /'
echo
echo "Si no lo mediste, reescribir como 'el sintoma desaparece si toco X'."
exit 0
