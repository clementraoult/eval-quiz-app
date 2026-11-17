# 13 - Azure CLI et Azure Container Registry (Jalon 3)

Création des ressources Azure avec Azure CLI et publication des images dans Azure Container Registry (ACR).
Les sorties de commandes sont dans [preuves/J3/](../preuves/J3/).

## 1. Vérification préalable de l'abonnement (J0)

| Point vérifié | Commande | Résultat |
|---|---|---|
| Abonnement actif | `az account show` | Azure for Students, état `Enabled` |
| Régions autorisées | `az policy assignment list` | `francecentral`, `italynorth`, `spaincentral`, `norwayeast`, `austriaeast` |
| Service ACR activé | `az provider show --namespace Microsoft.ContainerRegistry` | `NotRegistered` au départ, activé par le script |
| Service Container Apps activé | `az provider show --namespace Microsoft.App` | `Registered` |
| Nom du registre disponible | `az acr check-name --name quizappclem` | Disponible |

Restrictions constatées sur l'abonnement étudiant :

- **Régions.** Une stratégie Azure n'autorise que cinq régions. Créer une ressource ailleurs échoue avec l'erreur `RequestDisallowedByAzure`. Le projet utilise `francecentral`.
- **Fournisseurs de ressources.** Un service doit être activé sur l'abonnement avant sa première utilisation (`az provider register`). Le script le fait pour ACR.

## 2. Ressources créées

| Ressource | Nom | Paramètres |
|---|---|---|
| Groupe de ressources | `rg-quiz-app` | Région `francecentral` |
| Registre de conteneurs | `quizappclem` (`quizappclem.azurecr.io`) | Niveau `Basic`, compte administrateur désactivé, accès anonyme désactivé |

Choix :

- **Un groupe de ressources dédié.** Toutes les ressources du projet y sont regroupées : une seule commande suffit à tout supprimer.
- **Niveau Basic.** Le moins cher, 10 Gio de stockage inclus. Les deux images occupent environ 97 Mo.
- **Compte administrateur désactivé.** Ce compte est un identifiant unique avec un mot de passe partagé, qu'il faudrait stocker quelque part. L'accès passe par l'identité Azure de la personne ou du service : `az acr login` échange cette identité contre un jeton valable 3 heures.
- **Registre privé.** Sans authentification, `docker pull` est refusé (`authentication required`).

## 3. Scripts

| Script | Rôle |
|---|---|
| [scripts/config.sh](../scripts/config.sh) | Paramètres communs : groupe de ressources, région, nom du registre. Aucun secret |
| [scripts/deploy.sh](../scripts/deploy.sh) | Crée les ressources, construit les images et les publie |
| [scripts/destroy.sh](../scripts/destroy.sh) | Supprime le groupe de ressources et tout son contenu |

### Prérequis

- Azure CLI connecté à l'abonnement : `az login`.
- Docker et Git.
- Être dans une région autorisée par l'abonnement (voir `scripts/config.sh`).

### Déploiement

```bash
scripts/deploy.sh
```

Étapes du script :

1. Vérifie les outils, la connexion Azure, et calcule le tag des images.
2. Active le service ACR sur l'abonnement si nécessaire.
3. Crée le groupe de ressources.
4. Crée le registre, s'il n'existe pas déjà.
5. Construit les images du frontend et du backend.
6. Connecte Docker au registre (`az acr login`) et publie les images.
7. Affiche les tags présents dans le registre.

Le script est réexécutable : une ressource déjà présente est conservée.
Les paramètres se changent par variable d'environnement, par exemple `ACR_NAME=autrenom scripts/deploy.sh`.

L'image de la base n'est pas publiée : dans le cloud, le backend utilisera un PostgreSQL externe (jalon 5).

### Nettoyage

```bash
scripts/destroy.sh
```

Opération sensible et irréversible : le registre et toutes ses images sont supprimés.
Le script liste les ressources concernées, puis demande de taper le nom du groupe de ressources pour confirmer.
L'option `--yes` supprime la confirmation, pour un usage automatisé.

## 4. Tags des images

| Image | Tag | Origine du tag |
|---|---|---|
| `quizappclem.azurecr.io/quiz-backend` | `6820d93` | Identifiant court du commit Git |
| `quizappclem.azurecr.io/quiz-frontend` | `6820d93` | Identifiant court du commit Git |

- Le tag est l'identifiant du commit qui a produit l'image : on sait exactement quel code tourne.
- Le tag `latest` n'est pas utilisé : il ne dit rien du contenu et change à chaque publication.
- Si le dépôt contient des modifications non commitées, le script ajoute le suffixe `-dirty` au tag, pour ne pas faire passer une image pour le reflet exact d'un commit.
- Chaque image porte aussi le label `org.opencontainers.image.revision`, avec l'identifiant complet du commit.

## 5. Sécurité

| Mesure | Mise en œuvre |
|---|---|
| Aucun secret dans les scripts ni dans le dépôt | L'authentification repose sur la session `az login` de l'utilisateur |
| Pas de mot de passe de registre | Compte administrateur désactivé, jeton temporaire via `az acr login` |
| Registre privé | Accès anonyme désactivé, vérifié par un `docker pull` sans authentification |
| Images analysées avant publication | Mêmes Dockerfiles que ceux scannés au [jalon 2](12-securite-images.md) |
| Suppression protégée | `destroy.sh` exige une confirmation explicite |

## 6. Coûts

| Ressource | Facturation |
|---|---|
| Groupe de ressources | Gratuit |
| Registre ACR Basic | Tarif fixe par jour, tant que le registre existe, même vide |

Le registre est la seule ressource payante à ce stade. Il consomme les crédits de l'abonnement étudiant en continu.
Il doit rester en place pour les jalons 4 et 6. Après la soutenance, `scripts/destroy.sh` supprime tout.

## 7. Suite

Au jalon 4, `deploy.sh` sera complété pour créer l'environnement Azure Container Apps et les deux applications, qui tireront leurs images de ce registre.
