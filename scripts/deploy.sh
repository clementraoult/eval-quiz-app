#!/usr/bin/env bash
# Provisionne les ressources Azure de Quiz App et publie les images.
#
# Étapes couvertes (jalon 3) :
#   1. vérifications du poste et de l'abonnement ;
#   2. groupe de ressources ;
#   3. Azure Container Registry (ACR) ;
#   4. construction des images frontend et backend ;
#   5. publication dans ACR avec un tag traçable (commit Git).
#
# Usage :
#   scripts/deploy.sh
#
# Prérequis : Azure CLI connecté (az login), Docker, dépôt Git.
# Le script est réexécutable : une ressource déjà présente est conservée.
# Aucun secret n'est lu ni écrit par ce script.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config.sh
source "$ROOT/scripts/config.sh"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

# ---------- 1. Vérifications ----------
step "Vérifications"

command -v az >/dev/null     || fail "Azure CLI (az) est introuvable."
command -v docker >/dev/null || fail "Docker est introuvable."
command -v git >/dev/null    || fail "Git est introuvable."

SUBSCRIPTION="$(az account show --query name -o tsv 2>/dev/null)" \
  || fail "Azure CLI n'est pas connecté. Lancer : az login"
echo "Abonnement         : $SUBSCRIPTION"
echo "Groupe de ressources : $RESOURCE_GROUP"
echo "Région             : $LOCATION"
echo "Registre           : $ACR_NAME"

# Tag des images : identifiant court du commit Git.
# Le suffixe -dirty signale des modifications non commitées.
GIT_SHA="$(git -C "$ROOT" rev-parse HEAD)"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$ROOT" rev-parse --short=7 HEAD)}"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  IMAGE_TAG="$IMAGE_TAG-dirty"
  echo "Attention : modifications non commitées, le tag sera $IMAGE_TAG"
fi
echo "Tag des images     : $IMAGE_TAG"

# Le service ACR doit être activé une fois sur l'abonnement.
STATE="$(az provider show --namespace Microsoft.ContainerRegistry --query registrationState -o tsv)"
if [ "$STATE" != "Registered" ]; then
  step "Activation du service Microsoft.ContainerRegistry sur l'abonnement"
  az provider register --namespace Microsoft.ContainerRegistry --wait
fi

# ---------- 2. Groupe de ressources ----------
step "Groupe de ressources $RESOURCE_GROUP"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" \
  --query "{nom:name, region:location, etat:properties.provisioningState}" -o table

# ---------- 3. Registre ACR ----------
step "Registre $ACR_NAME"
if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Le registre existe déjà."
else
  # --admin-enabled false : pas de compte administrateur à mot de passe partagé.
  # L'accès passe par l'identité Azure de la personne ou du service qui se connecte.
  az acr create --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" --sku "$ACR_SKU" --admin-enabled false \
    --query "{nom:name, serveur:loginServer, sku:sku.name, admin:adminUserEnabled}" -o table
fi
ACR_SERVER="$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)"
echo "Serveur : $ACR_SERVER"

# ---------- 4. Construction des images ----------
BACKEND_IMAGE="$ACR_SERVER/$BACKEND_REPO:$IMAGE_TAG"
FRONTEND_IMAGE="$ACR_SERVER/$FRONTEND_REPO:$IMAGE_TAG"

# Les labels OCI relient l'image au commit qui l'a produite.
step "Construction de $BACKEND_IMAGE"
docker build \
  --label "org.opencontainers.image.revision=$GIT_SHA" \
  --label "org.opencontainers.image.title=$BACKEND_REPO" \
  -t "$BACKEND_IMAGE" "$ROOT/backend"

step "Construction de $FRONTEND_IMAGE"
docker build \
  --label "org.opencontainers.image.revision=$GIT_SHA" \
  --label "org.opencontainers.image.title=$FRONTEND_REPO" \
  -t "$FRONTEND_IMAGE" "$ROOT"

# ---------- 5. Publication dans ACR ----------
step "Connexion de Docker au registre"
# az acr login échange l'identité Azure contre un jeton temporaire (3 heures)
# enregistré pour docker push. Aucun mot de passe n'est stocké dans le script.
az acr login --name "$ACR_NAME"

step "Publication des images"
docker push "$BACKEND_IMAGE"
docker push "$FRONTEND_IMAGE"

step "Images présentes dans le registre"
for repo in "$BACKEND_REPO" "$FRONTEND_REPO"; do
  az acr repository show-tags --name "$ACR_NAME" --repository "$repo" \
    --detail --orderby time_desc \
    --query "[].{depot:'$repo', tag:name, digest:digest, date:createdTime}" -o table
done

echo
echo "Terminé. Images publiées avec le tag $IMAGE_TAG."
