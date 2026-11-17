#!/usr/bin/env bash
# Analyse les images locales de Quiz App avec Trivy.
#
# Usage :
#   scripts/scan-trivy.sh <étiquette> [image...]
#
# Exemples :
#   scripts/scan-trivy.sh final
#   scripts/scan-trivy.sh initial quiz-backend:initial quiz-frontend:initial
#
# Les rapports sont écrits dans preuves/J2/scan-<étiquette>-<service>.txt,
# ou dans le dossier indiqué par la variable SCAN_OUTPUT_DIR.
# Le script se termine en erreur si une vulnérabilité CRITICAL est trouvée.
#
# Trivy tourne dans un conteneur. Les images sont exportées avec "docker save" puis
# analysées depuis le fichier : le socket Docker n'est jamais monté dans le conteneur
# Trivy (le monter reviendrait à lui donner les droits root sur le poste).

set -euo pipefail

# Version de Trivy épinglée par digest (0.76.2)
TRIVY_IMAGE="aquasec/trivy@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb"

LABEL="${1:?Usage : $0 <étiquette> [image...]}"
shift || true

if [ "$#" -eq 0 ]; then
  set -- quiz-backend:local quiz-frontend:local quiz-db:local
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Dossier des rapports : preuves/J2 par défaut, remplaçable (utilisé par la CI).
OUT="${SCAN_OUTPUT_DIR:-$ROOT/preuves/J2}"
CACHE="${TRIVY_CACHE_DIR:-$HOME/.cache/trivy}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT" "$CACHE"

trivy() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "$CACHE":/tmp/.cache/trivy \
    -v "$TMP":/img:ro \
    "$TRIVY_IMAGE" "$@"
}

critical=0

for image in "$@"; do
  # quiz-backend:local -> backend
  service="${image%%:*}"
  service="${service##*/}"
  service="${service#quiz-}"
  report="$OUT/scan-$LABEL-$service.txt"

  echo "==> $image"
  docker save "$image" -o "$TMP/$service.tar"

  # Rapport complet, toutes sévérités
  trivy image --input "/img/$service.tar" --scanners vuln --no-progress --quiet \
    --format table > "$report"
  grep -E '^Total:' "$report" || echo "Total: 0"

  # Contrôle bloquant : code de sortie 1 si au moins une CRITICAL
  if ! trivy image --input "/img/$service.tar" --scanners vuln --no-progress --quiet \
      --skip-db-update --severity CRITICAL --exit-code 1 > /dev/null; then
    echo "    ÉCHEC : vulnérabilité CRITICAL dans $image"
    critical=1
  fi

  rm -f "$TMP/$service.tar"
done

echo
echo "Rapports : $OUT/scan-$LABEL-*.txt"
exit "$critical"
