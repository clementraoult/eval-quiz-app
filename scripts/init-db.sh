#!/usr/bin/env bash
# Initialise le schéma de la base PostgreSQL externe (Neon ou compatible).
#
# Dans le cloud, rien n'exécute database/init.sql automatiquement : le mécanisme
# /docker-entrypoint-initdb.d n'existe que dans l'image Docker locale.
# Ce script applique donc le schéma à la base désignée par DATABASE_URL.
#
# Usage :
#   scripts/init-db.sh
#
# Prérequis : Docker, et DATABASE_URL renseignée dans .env.azure
# (ou fournie en variable d'environnement).
#
# Le script est réexécutable : si les tables existent déjà, il ne modifie rien.
# La chaîne de connexion n'est jamais affichée ni écrite sur la ligne de commande.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config.sh
source "$ROOT/scripts/config.sh"

# Client psql : la même image PostgreSQL épinglée que pour la base locale.
PSQL_IMAGE="postgres:18.7-alpine3.24@sha256:b6972e1115a4ff8eba5d7f7d19184926d1e16d7d1136ae1e1a7ebf286da0f015"

fail() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

command -v docker >/dev/null || fail "Docker est introuvable."

# Variable d'environnement prioritaire, sinon lecture dans .env.azure.
if [ -z "${DATABASE_URL:-}" ] && [ -f "$ROOT/$AZURE_ENV_FILE" ]; then
  DATABASE_URL="$(grep -E '^DATABASE_URL=' "$ROOT/$AZURE_ENV_FILE" | tail -n 1 | cut -d= -f2- || true)"
fi
# Retire d'éventuels guillemets autour de la valeur (format de certains fournisseurs).
DATABASE_URL="${DATABASE_URL:-}"
DATABASE_URL="${DATABASE_URL%\"}"; DATABASE_URL="${DATABASE_URL#\"}"
DATABASE_URL="${DATABASE_URL%\'}"; DATABASE_URL="${DATABASE_URL#\'}"
[ -n "${DATABASE_URL:-}" ] || fail "DATABASE_URL est vide. La renseigner dans $AZURE_ENV_FILE."
export DATABASE_URL

case "$DATABASE_URL" in
  postgres://*|postgresql://*) ;;
  *) fail "DATABASE_URL doit commencer par postgres:// ou postgresql://" ;;
esac

# Connexion chiffrée obligatoire.
case "$DATABASE_URL" in
  *sslmode=require*|*sslmode=verify-full*|*sslmode=verify-ca*) ;;
  *) fail "DATABASE_URL doit imposer TLS : ajouter ?sslmode=require à la fin." ;;
esac

# psql tourne dans un conteneur. "-e DATABASE_URL" transmet la variable sans
# faire apparaître sa valeur dans la commande ni dans la liste des processus.
psql() {
  docker run --rm -i -e DATABASE_URL "$PSQL_IMAGE" \
    sh -c 'exec psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"' psql "$@"
}

step "Connexion à la base"
psql -Atc "select 'Serveur : ' || split_part(version(), ' on ', 1) || ', base : ' || current_database()"
psql -c '\conninfo' | grep -i -E 'ssl|tls|chiffr|protocol|cipher' \
  || fail "La connexion n'est pas chiffrée."

step "Schéma"
if [ "$(psql -Atc "select to_regclass('public.users') is not null")" = "t" ]; then
  echo "Les tables existent déjà : schéma non modifié."
else
  echo "Application de database/init.sql (dans une seule transaction)"
  psql --single-transaction -f - < "$ROOT/database/init.sql"
fi

step "Tables présentes"
psql -c '\dt'
