#!/usr/bin/env bash
# Paramètres communs aux scripts Azure. Aucun secret ici.
# Chaque valeur peut être remplacée par une variable d'environnement :
#   ACR_NAME=autrenom scripts/deploy.sh

# Groupe de ressources : contient toutes les ressources Azure du projet.
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-quiz-app}"

# Région. L'abonnement Azure for Students n'autorise que quelques régions :
#   az policy assignment list --query "[].parameters.listOfAllowedLocations.value" -o tsv
LOCATION="${LOCATION:-francecentral}"

# Registre de conteneurs. Le nom est unique dans tout Azure :
# 5 à 50 caractères, lettres minuscules et chiffres uniquement.
ACR_NAME="${ACR_NAME:-clemanas}"

# Niveau de service du registre : Basic est le moins cher.
ACR_SKU="${ACR_SKU:-Basic}"

# Dépôts d'images dans le registre
BACKEND_REPO="${BACKEND_REPO:-quiz-backend}"
FRONTEND_REPO="${FRONTEND_REPO:-quiz-frontend}"

# ---------- Azure Container Apps ----------

# Environnement : réseau et frontière communs aux applications.
ACA_ENV="${ACA_ENV:-env-quiz-app}"

# Mode de l'environnement. Sans cette option, Azure CLI crée un environnement
# "Express", qui refuse l'accès TCP interne dont le backend a besoin
# (erreur ExpressTcpIngressNotSupported).
ACA_ENV_MODE="${ACA_ENV_MODE:-WorkloadProfiles}"

# Nom des applications. Le backend DOIT s'appeler "backend" : nginx le joint
# par ce nom (server backend:3007 dans nginx/nginx.conf), comme en local.
BACKEND_APP="${BACKEND_APP:-backend}"
FRONTEND_APP="${FRONTEND_APP:-frontend}"

# Ports d'écoute dans les conteneurs
BACKEND_PORT="${BACKEND_PORT:-3007}"
FRONTEND_PORT_INTERNAL="${FRONTEND_PORT_INTERNAL:-8080}"

# Ressources par réplica : le minimum proposé par Container Apps.
APP_CPU="${APP_CPU:-0.25}"
APP_MEMORY="${APP_MEMORY:-0.5Gi}"

# Nombre de réplicas.
# Backend : 1 au minimum, pour que nginx le trouve toujours prêt (pas de démarrage à froid).
# Frontend : 0 au minimum, il s'éteint sans visite et se rallume à la première requête.
BACKEND_MIN_REPLICAS="${BACKEND_MIN_REPLICAS:-1}"
BACKEND_MAX_REPLICAS="${BACKEND_MAX_REPLICAS:-1}"
FRONTEND_MIN_REPLICAS="${FRONTEND_MIN_REPLICAS:-0}"
FRONTEND_MAX_REPLICAS="${FRONTEND_MAX_REPLICAS:-2}"

# Fichier local des secrets du cloud, jamais versionné (voir .env.azure.example).
AZURE_ENV_FILE="${AZURE_ENV_FILE:-.env.azure}"
