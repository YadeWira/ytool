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

PAT='because|due to|root cause|the reason is|caused by|explains why|it is caused|porque|causa raiz'
RANGE="${1:-}"

if [ -n "$RANGE" ]; then
  DIFF=$(git diff "$RANGE" --unified=0 -- '*.pas' '*.dpr' '*.sh' '*.ps1' '*.md' '*.py' 2>/dev/null)
else
  DIFF=$(git diff --cached --unified=0 -- '*.pas' '*.dpr' '*.sh' '*.ps1' '*.md' '*.py' 2>/dev/null)
  [ -z "$DIFF" ] && DIFF=$(git diff --unified=0 -- '*.pas' '*.dpr' '*.sh' '*.ps1' '*.md' '*.py' 2>/dev/null)
fi

HITS=$(printf '%s\n' "$DIFF" | grep '^+' | grep -v '^+++' | grep -inE "$PAT" || true)

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
