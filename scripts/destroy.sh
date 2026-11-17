#!/usr/bin/env bash
# Supprime toutes les ressources Azure de Quiz App.
#
# OPÉRATION SENSIBLE ET IRRÉVERSIBLE : le groupe de ressources est supprimé avec
# tout son contenu (registre et images, environnement et applications Container Apps).
# Sauvegarder les preuves avant de lancer ce script.
#
# Usage :
#   scripts/destroy.sh          # demande une confirmation
#   scripts/destroy.sh --yes    # sans confirmation (automatisation)
#
# La base PostgreSQL externe (Neon) n'est pas gérée par ce script.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config.sh
source "$ROOT/scripts/config.sh"

command -v az >/dev/null || { echo "ERREUR : Azure CLI (az) est introuvable." >&2; exit 1; }
az account show >/dev/null 2>&1 || { echo "ERREUR : Azure CLI n'est pas connecté. Lancer : az login" >&2; exit 1; }

if [ "$(az group exists --name "$RESOURCE_GROUP")" != "true" ]; then
  echo "Le groupe de ressources $RESOURCE_GROUP n'existe pas : rien à supprimer."
  exit 0
fi

echo "Abonnement : $(az account show --query name -o tsv)"
echo "Ressources qui seront supprimées dans $RESOURCE_GROUP :"
az resource list --resource-group "$RESOURCE_GROUP" \
  --query "[].{nom:name, type:type, region:location}" -o table

if [ "${1:-}" != "--yes" ]; then
  echo
  read -r -p "Taper le nom du groupe de ressources pour confirmer la suppression : " answer
  if [ "$answer" != "$RESOURCE_GROUP" ]; then
    echo "Confirmation incorrecte : rien n'a été supprimé."
    exit 1
  fi
fi

echo
echo "Suppression de $RESOURCE_GROUP (plusieurs minutes)..."
az group delete --name "$RESOURCE_GROUP" --yes

echo "Terminé : le groupe $RESOURCE_GROUP et tout son contenu sont supprimés."
