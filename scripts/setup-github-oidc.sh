#!/usr/bin/env bash
# Prépare l'accès du pipeline GitHub Actions à Azure, sans mot de passe (OIDC).
#
# Principe : GitHub délivre à chaque exécution un jeton signé qui dit "je suis le
# dépôt X, branche Y". Azure fait confiance à ce jeton pour UNE identité managée,
# qui n'a que les droits nécessaires au déploiement. Aucun secret longue durée
# n'est stocké dans GitHub.
#
# Le script crée :
#   1. une identité managée dédiée au pipeline ;
#   2. un lien de confiance (federated credential) limité au dépôt et à la branche ;
#   3. les droits minimaux : lire le groupe de ressources, pousser des images dans
#      le registre, mettre à jour les deux applications Container Apps.
#
# Usage :
#   scripts/setup-github-oidc.sh
#
# Prérequis : az login avec un compte propriétaire de l'abonnement (attribution de
# rôles), et les ressources créées par scripts/deploy.sh. Le script est réexécutable.
# Les trois identifiants affichés à la fin ne sont pas des secrets.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config.sh
source "$ROOT/scripts/config.sh"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

command -v az >/dev/null || fail "Azure CLI (az) est introuvable."
az account show >/dev/null 2>&1 || fail "Azure CLI n'est pas connecté. Lancer : az login"

# ---------- 1. Identité managée ----------
step "Identité managée $CI_IDENTITY"
if ! az identity show --name "$CI_IDENTITY" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az identity create --name "$CI_IDENTITY" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" -o none
  echo "Identité créée."
else
  echo "L'identité existe déjà."
fi
CLIENT_ID="$(az identity show --name "$CI_IDENTITY" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show --name "$CI_IDENTITY" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)"

# ---------- 2. Lien de confiance avec GitHub ----------
# Le sujet limite la confiance aux exécutions de la branche indiquée de ce dépôt.
# Une Pull Request, une autre branche ou un autre dépôt ne peuvent pas l'utiliser.
SUBJECT="repo:$GITHUB_REPO:ref:refs/heads/$GITHUB_BRANCH"
step "Lien de confiance : $SUBJECT"
az identity federated-credential create \
  --name "github-$GITHUB_BRANCH" \
  --identity-name "$CI_IDENTITY" --resource-group "$RESOURCE_GROUP" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "$SUBJECT" \
  --audiences "api://AzureADTokenExchange" \
  --query "{nom:name, emetteur:issuer, sujet:subject}" -o table

# ---------- 3. Droits minimaux ----------
ACR_ID="$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
BACKEND_ID="$(az containerapp show --name "$BACKEND_APP" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
FRONTEND_ID="$(az containerapp show --name "$FRONTEND_APP" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"

assign() {
  local role="$1" scope="$2" label="$3"
  # L'identité vient d'être créée : son enregistrement peut mettre quelques secondes
  # à se propager, d'où les nouvelles tentatives.
  for attempt in 1 2 3 4 5 6; do
    if az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "$role" --scope "$scope" -o none 2>/dev/null; then
      echo "$role sur $label"
      return 0
    fi
    sleep 10
  done
  fail "Impossible d'attribuer le rôle $role sur $label."
}

step "Droits de l'identité"
RG_ID="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv)"
# Lecture seule sur le groupe : nécessaire à Azure CLI pour retrouver les ressources.
assign "Reader" "$RG_ID" "le groupe de ressources $RESOURCE_GROUP"
assign "AcrPush" "$ACR_ID" "le registre $ACR_NAME"
assign "Container Apps Contributor" "$BACKEND_ID" "l'application $BACKEND_APP"
assign "Container Apps Contributor" "$FRONTEND_ID" "l'application $FRONTEND_APP"

# ---------- 4. Valeurs à déclarer dans GitHub ----------
step "Variables à créer dans GitHub"
echo "Dépôt $GITHUB_REPO : Settings > Secrets and variables > Actions > onglet Variables"
echo
echo "AZURE_CLIENT_ID       = $CLIENT_ID"
echo "AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID = $(az account show --query id -o tsv)"
echo
echo "Ce sont des identifiants, pas des secrets : seuls, ils ne donnent aucun accès."
