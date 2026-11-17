#!/usr/bin/env bash
# Provisionne les ressources Azure de Quiz App, publie les images et déploie
# le frontend et le backend sur Azure Container Apps.
#
# Étapes :
#   1. vérifications du poste, de l'abonnement et des secrets ;
#   2. groupe de ressources ;
#   3. Azure Container Registry (ACR) ;
#   4. construction des images frontend et backend ;
#   5. publication dans ACR avec un tag traçable (commit Git) ;
#   6. environnement Azure Container Apps ;
#   7. application backend (accès interne uniquement) ;
#   8. application frontend (accès public en HTTPS) ;
#   9. test de /health à travers le frontend.
#
# Usage :
#   scripts/deploy.sh
#
# Prérequis : Azure CLI connecté (az login), Docker, Git, et le fichier .env.azure
# (voir .env.azure.example). Le script est réexécutable : une ressource déjà
# présente est conservée, une application existante est mise à jour.
#
# Secrets : ils sont lus dans .env.azure (non versionné) et transmis à Azure comme
# secrets Container Apps. Aucun secret n'est écrit dans ce script ni affiché.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config.sh
source "$ROOT/scripts/config.sh"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

# Lit une variable dans le fichier de secrets, sans exécuter son contenu.
# Une variable d'environnement déjà définie est prioritaire (utile en CI).
read_secret() {
  local name="$1" value="${!1:-}"
  if [ -z "$value" ] && [ -f "$ROOT/$AZURE_ENV_FILE" ]; then
    value="$(grep -E "^${name}=" "$ROOT/$AZURE_ENV_FILE" | tail -n 1 | cut -d= -f2- || true)"
  fi
  # Retire d'éventuels guillemets autour de la valeur (format de certains fournisseurs).
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "$value"
}

app_exists() {
  az containerapp show --name "$1" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1
}

# ---------- 1. Vérifications ----------
step "Vérifications"

command -v az >/dev/null     || fail "Azure CLI (az) est introuvable."
command -v docker >/dev/null || fail "Docker est introuvable."
command -v git >/dev/null    || fail "Git est introuvable."

SUBSCRIPTION="$(az account show --query name -o tsv 2>/dev/null)" \
  || fail "Azure CLI n'est pas connecté. Lancer : az login"
echo "Abonnement           : $SUBSCRIPTION"
echo "Groupe de ressources : $RESOURCE_GROUP"
echo "Région               : $LOCATION"
echo "Registre             : $ACR_NAME"
echo "Environnement        : $ACA_ENV"

# Secrets du backend. Les valeurs par défaut du code (admin123, change-this-secret)
# sont publiques : le déploiement est refusé si un secret manque.
ADMIN_USERNAME_VALUE="$(read_secret ADMIN_USERNAME)"
ADMIN_PASSWORD_VALUE="$(read_secret ADMIN_PASSWORD)"
JWT_SECRET_VALUE="$(read_secret JWT_SECRET)"
RESEND_API_KEY_VALUE="$(read_secret RESEND_API_KEY)"
DATABASE_URL_VALUE="$(read_secret DATABASE_URL)"

[ -n "$ADMIN_USERNAME_VALUE" ] || fail "ADMIN_USERNAME est absent de $AZURE_ENV_FILE."
[ -n "$ADMIN_PASSWORD_VALUE" ] || fail "ADMIN_PASSWORD est absent de $AZURE_ENV_FILE."
[ -n "$JWT_SECRET_VALUE" ]     || fail "JWT_SECRET est absent de $AZURE_ENV_FILE."
[ -n "$RESEND_API_KEY_VALUE" ] || fail "RESEND_API_KEY est absent de $AZURE_ENV_FILE (valeur factice acceptée)."
case "$ADMIN_PASSWORD_VALUE" in changeme|admin123) fail "ADMIN_PASSWORD a encore une valeur d'exemple." ;; esac
case "$JWT_SECRET_VALUE" in change-this-*) fail "JWT_SECRET a encore une valeur d'exemple." ;; esac

if [ -n "$DATABASE_URL_VALUE" ]; then
  echo "Base de données      : DATABASE_URL fournie"
else
  echo "Base de données      : aucune (DATABASE_URL vide, voir jalon 5)"
fi

# Tag des images : identifiant court du commit Git.
# Le suffixe -dirty signale des modifications non commitées.
GIT_SHA="$(git -C "$ROOT" rev-parse HEAD)"
IMAGE_TAG="${IMAGE_TAG:-$(git -C "$ROOT" rev-parse --short=7 HEAD)}"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  IMAGE_TAG="$IMAGE_TAG-dirty"
  echo "Attention : modifications non commitées, le tag sera $IMAGE_TAG"
fi
echo "Tag des images       : $IMAGE_TAG"

# Les services Azure doivent être activés une fois sur l'abonnement.
for namespace in Microsoft.ContainerRegistry Microsoft.App Microsoft.OperationalInsights; do
  STATE="$(az provider show --namespace "$namespace" --query registrationState -o tsv)"
  if [ "$STATE" != "Registered" ]; then
    step "Activation du service $namespace sur l'abonnement"
    az provider register --namespace "$namespace" --wait
  fi
done

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

# ---------- 6. Environnement Container Apps ----------
step "Environnement Container Apps $ACA_ENV"
if az containerapp env show --name "$ACA_ENV" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "L'environnement existe déjà."
else
  # --logs-destination none : pas d'espace Log Analytics (payant). Les journaux
  # restent consultables en direct avec "az containerapp logs show".
  # --environment-mode : option de l'extension "containerapp" d'Azure CLI
  # (az extension add --name containerapp). Voir ACA_ENV_MODE dans config.sh.
  az containerapp env create --name "$ACA_ENV" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" --logs-destination none \
    --environment-mode "$ACA_ENV_MODE" \
    --query "{nom:name, region:location, mode:properties.environmentMode, etat:properties.provisioningState}" -o table
fi

# ---------- 7. Backend ----------
step "Application $BACKEND_APP"

# Les valeurs sensibles sont stockées comme secrets Container Apps ; les variables
# d'environnement du conteneur y font référence avec secretref:<nom>.
BACKEND_SECRETS=(
  "admin-password=$ADMIN_PASSWORD_VALUE"
  "jwt-secret=$JWT_SECRET_VALUE"
  "resend-api-key=$RESEND_API_KEY_VALUE"
)
BACKEND_ENV=(
  "ADMIN_USERNAME=$ADMIN_USERNAME_VALUE"
  "ADMIN_PASSWORD=secretref:admin-password"
  "JWT_SECRET=secretref:jwt-secret"
  "RESEND_API_KEY=secretref:resend-api-key"
)
if [ -n "$DATABASE_URL_VALUE" ]; then
  BACKEND_SECRETS+=("database-url=$DATABASE_URL_VALUE")
  BACKEND_ENV+=("DATABASE_URL=secretref:database-url")
fi

if app_exists "$BACKEND_APP"; then
  echo "L'application existe : mise à jour des secrets et de l'image."
  az containerapp secret set --name "$BACKEND_APP" --resource-group "$RESOURCE_GROUP" \
    --secrets "${BACKEND_SECRETS[@]}" -o none
  az containerapp update --name "$BACKEND_APP" --resource-group "$RESOURCE_GROUP" \
    --image "$BACKEND_IMAGE" --set-env-vars "${BACKEND_ENV[@]}" \
    --query "{nom:name, revision:properties.latestRevisionName, etat:properties.provisioningState}" -o table
else
  # --registry-identity system : l'application reçoit une identité managée, à laquelle
  #   Azure CLI donne le rôle AcrPull sur le registre. Aucun mot de passe de registre.
  # --ingress internal : joignable uniquement depuis l'environnement, jamais depuis Internet.
  # --transport tcp + --exposed-port : le backend est joint sur backend:3007, exactement
  #   comme en local, sans modifier nginx/nginx.conf.
  az containerapp create --name "$BACKEND_APP" --resource-group "$RESOURCE_GROUP" \
    --environment "$ACA_ENV" \
    --image "$BACKEND_IMAGE" \
    --registry-server "$ACR_SERVER" --registry-identity system \
    --ingress internal --transport tcp \
    --target-port "$BACKEND_PORT" --exposed-port "$BACKEND_PORT" \
    --cpu "$APP_CPU" --memory "$APP_MEMORY" \
    --min-replicas "$BACKEND_MIN_REPLICAS" --max-replicas "$BACKEND_MAX_REPLICAS" \
    --secrets "${BACKEND_SECRETS[@]}" \
    --env-vars "${BACKEND_ENV[@]}" \
    --query "{nom:name, revision:properties.latestRevisionName, etat:properties.provisioningState}" -o table
fi

# ---------- 8. Frontend ----------
step "Application $FRONTEND_APP"
if app_exists "$FRONTEND_APP"; then
  echo "L'application existe : mise à jour de l'image."
  az containerapp update --name "$FRONTEND_APP" --resource-group "$RESOURCE_GROUP" \
    --image "$FRONTEND_IMAGE" \
    --query "{nom:name, revision:properties.latestRevisionName, etat:properties.provisioningState}" -o table
else
  # --ingress external : seule application exposée sur Internet. Azure fournit le
  #   certificat HTTPS et redirige le HTTP vers HTTPS.
  az containerapp create --name "$FRONTEND_APP" --resource-group "$RESOURCE_GROUP" \
    --environment "$ACA_ENV" \
    --image "$FRONTEND_IMAGE" \
    --registry-server "$ACR_SERVER" --registry-identity system \
    --ingress external --transport auto \
    --target-port "$FRONTEND_PORT_INTERNAL" \
    --cpu "$APP_CPU" --memory "$APP_MEMORY" \
    --min-replicas "$FRONTEND_MIN_REPLICAS" --max-replicas "$FRONTEND_MAX_REPLICAS" \
    --query "{nom:name, revision:properties.latestRevisionName, etat:properties.provisioningState}" -o table
fi

# ---------- 9. Vérification ----------
FRONTEND_FQDN="$(az containerapp show --name "$FRONTEND_APP" --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv)"
FRONTEND_URL="https://$FRONTEND_FQDN"

step "Test de $FRONTEND_URL/health (navigateur -> frontend -> backend)"
STATUS=000
for attempt in $(seq 1 12); do
  STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$FRONTEND_URL/health" || true)"
  [ "$STATUS" = "200" ] && break
  echo "Tentative $attempt : HTTP $STATUS, nouvelle tentative dans 10 s"
  sleep 10
done

echo
echo "Images déployées : tag $IMAGE_TAG"
echo "Application      : $FRONTEND_URL"
if [ "$STATUS" = "200" ]; then
  echo "Santé du backend : HTTP 200 $(curl -s --max-time 20 "$FRONTEND_URL/health")"
else
  echo "Santé du backend : HTTP $STATUS"
  fail "Le backend ne répond pas à travers le frontend. Voir : az containerapp logs show --name $BACKEND_APP --resource-group $RESOURCE_GROUP"
fi
