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
ACR_NAME="${ACR_NAME:-quizappclem}"

# Niveau de service du registre : Basic est le moins cher.
ACR_SKU="${ACR_SKU:-Basic}"

# Dépôts d'images dans le registre
BACKEND_REPO="${BACKEND_REPO:-quiz-backend}"
FRONTEND_REPO="${FRONTEND_REPO:-quiz-frontend}"
