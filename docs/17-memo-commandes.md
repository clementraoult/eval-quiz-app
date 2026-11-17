# 17 - Mémo des commandes

Aide-mémoire pour exploiter, diagnostiquer et modifier Quiz App, en local et sur Azure.
Toutes les commandes se lancent depuis la racine du dépôt.

## 1. Où se trouve quoi

| Je veux modifier... | Fichier |
|---|---|
| Une question de quiz | `questions_docker.js`, `questions_devops.js`, etc. |
| L'image du frontend | `Dockerfile` (racine) |
| L'image du backend | `backend/Dockerfile` |
| L'image de la base locale | `database/Dockerfile` |
| Le schéma de la base | `database/init.sql` |
| Le reverse proxy, le port d'écoute de nginx | `nginx/nginx.conf` |
| Les services locaux, ports, volumes, limites | `docker-compose.yml` |
| Les secrets locaux | `.env` (non versionné), modèle `.env.example` |
| Les secrets du cloud | `.env.azure` (non versionné), modèle `.env.azure.example` |
| Les noms des ressources Azure, les réplicas | `scripts/config.sh` |
| Le déploiement Azure | `scripts/deploy.sh` |
| Les contrôles sur Pull Request | `.github/workflows/ci.yml` |
| Le déploiement automatique | `.github/workflows/cd.yml` |

| Valeur utile | |
|---|---|
| Application locale | http://localhost:8087 |
| Application en ligne | https://frontend.salmonwave-d76adf8c.francecentral.azurecontainerapps.io |
| Groupe de ressources | `rg-quiz-app` |
| Registre | `clemanas.azurecr.io` |
| Environnement Container Apps | `env-quiz-app` |
| Applications | `frontend` (public), `backend` (interne, port 3007) |

## 2. Docker Compose en local

```bash
docker compose config -q                 # valider le fichier (silencieux si correct)
docker compose up -d --build             # construire et démarrer
docker compose up -d --build frontend    # reconstruire un seul service
docker compose ps                        # état et santé des services
docker compose logs -f backend           # journaux en direct (Ctrl+C pour quitter)
docker compose logs --tail 50 db         # 50 dernières lignes
docker compose restart backend           # redémarrer un service
docker compose stop                      # arrêter sans supprimer
docker compose down                      # supprimer conteneurs et réseau, GARDER les données
docker compose down -v                   # supprimer aussi le volume : données PERDUES
```

Entrer dans un conteneur ou y lancer une commande :

```bash
docker compose exec backend sh                      # shell dans le backend
docker compose exec backend env | sort              # variables d'environnement (contient des secrets)
docker compose exec frontend cat /etc/nginx/conf.d/default.conf
docker compose exec frontend ls /usr/share/nginx/html/assets
```

## 3. Base de données

```bash
# Console SQL dans la base locale
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# Une requête directe
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"'
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select * from users"'
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select count(*) from quiz_results"'
```

Dans `psql` : `\dt` liste les tables, `\d users` décrit une table, `\q` quitte.

```bash
docker volume ls | grep quiz-app             # le volume des données
docker volume inspect quiz-app_pgdata        # son emplacement sur le poste
scripts/init-db.sh                           # créer les tables sur la base cloud (Neon)
```

Rappels :

- `init.sql` n'est exécuté qu'au premier démarrage, sur un volume vide.
- Pour réappliquer un `init.sql` modifié en local : `docker compose down -v`, puis `up -d --build`.

## 4. Images et sécurité

```bash
docker build -t quiz-backend:test ./backend    # construire une image seule
docker build -t quiz-frontend:test .
docker images | grep quiz                      # images et tailles
docker history quiz-backend:local              # couches d'une image
docker image inspect quiz-backend:local --format '{{.Config.User}}'   # utilisateur par défaut

scripts/scan-trivy.sh final                              # scanner les trois images locales
scripts/scan-trivy.sh test quiz-backend:test             # scanner une image précise
```

Le script sort en erreur (code 1) si une vulnérabilité CRITICAL est trouvée.
Les rapports sont dans `preuves/J2/scan-<étiquette>-<service>.txt`.

Vérifier les protections d'un conteneur en fonctionnement :

```bash
docker compose exec backend id                 # utilisateur (doit être node, pas root)
docker inspect quiz-app-backend-1 --format 'lecture seule={{.HostConfig.ReadonlyRootfs}} capacités retirées={{.HostConfig.CapDrop}} mémoire={{.HostConfig.Memory}}'
```

## 5. Tests rapides

```bash
# Local
curl -i http://localhost:8087/health
curl -I http://localhost:8087/

# En ligne
curl -i https://frontend.salmonwave-d76adf8c.francecentral.azurecontainerapps.io/health

# Inscription (écrit en base)
curl -X POST http://localhost:8087/api/users \
  -H 'Content-Type: application/json' \
  -d '{"firstname":"Test","email":"test@example.com"}'
```

`/health` ne teste pas la base. Pour prouver que la base répond, faire une inscription.
L'inscription est limitée à 5 par quart d'heure et par adresse IP.

## 6. Azure

```bash
az login                                   # se connecter
az account show -o table                   # abonnement actif
az resource list -g rg-quiz-app -o table   # toutes les ressources du projet
```

### Applications Container Apps

```bash
az containerapp list -g rg-quiz-app -o table
az containerapp show -n backend -g rg-quiz-app --query properties.runningStatus -o tsv

# Journaux
az containerapp logs show -n backend  -g rg-quiz-app --tail 50
az containerapp logs show -n frontend -g rg-quiz-app --follow

# Révisions : une par déploiement, avec son image
az containerapp revision list -n backend -g rg-quiz-app --all \
  --query "[].{revision:name, active:properties.active, image:properties.template.containers[0].image, sante:properties.healthState}" -o table

# Redémarrer la révision active
az containerapp revision restart -n backend -g rg-quiz-app --revision <nom-de-la-révision>

# Variables et secrets du backend (noms seulement)
az containerapp show -n backend -g rg-quiz-app --query "properties.template.containers[0].env" -o table
az containerapp secret list -n backend -g rg-quiz-app -o table
```

### Registre

```bash
az acr repository list -n clemanas -o table
az acr repository show-tags -n clemanas --repository quiz-backend --detail --orderby time_desc -o table
az acr login -n clemanas                   # connecter Docker au registre (jeton de 3 heures)
```

### Scripts du projet

```bash
scripts/deploy.sh              # tout créer ou mettre à jour, puis tester /health
scripts/init-db.sh             # créer les tables sur la base cloud
scripts/setup-github-oidc.sh   # accès du pipeline GitHub à Azure
scripts/destroy.sh             # TOUT supprimer sur Azure (demande confirmation)
```

## 7. Git et GitHub

```bash
git checkout main && git pull              # repartir d'un main à jour
git checkout -b feature/ma-modif           # nouvelle branche
git status                                 # fichiers modifiés
git diff                                   # détail des modifications
git add <fichier> && git commit -m "..."
git push -u origin feature/ma-modif

# Pull Request vers main DU FORK (jamais vers le dépôt du formateur)
gh pr create --repo clementraoult/eval-quiz-app --base main --fill
gh pr checks <numéro> --repo clementraoult/eval-quiz-app     # état de la CI
gh pr merge <numéro> --repo clementraoult/eval-quiz-app --merge
```

Exécutions GitHub Actions :

```bash
gh run list --repo clementraoult/eval-quiz-app
gh run view <id> --repo clementraoult/eval-quiz-app
gh run view <id> --repo clementraoult/eval-quiz-app --log-failed
gh run watch <id> --repo clementraoult/eval-quiz-app
gh workflow run cd.yml --ref main --repo clementraoult/eval-quiz-app   # redéployer main
```

Pour redéployer, lancer le CD sur `main`. Relancer une ancienne exécution redéploie son ancien commit.

## 8. Modifications courantes

### Modifier une question de quiz

1. `git checkout main && git pull && git checkout -b feature/question`
2. Modifier le texte dans `questions_docker.js`. Si la bonne réponse change, modifier aussi `correct`, qui doit être identique à une des `answers`.
3. Tester en local : `docker compose up -d --build frontend`, puis http://localhost:8087
4. `git add`, `git commit`, `git push`, puis ouvrir la Pull Request.
5. Après la CI et la fusion, le CD reconstruit et déploie le frontend.

Les questions sont compilées dans l'image du frontend : sans reconstruction, rien ne change.

### Changer le port du frontend en local

Dans `.env` : `FRONTEND_PORT=9090`, puis `docker compose up -d`.
Le port du conteneur reste 8080 : seul le port du poste change (`9090:8080`).

### Ajouter une variable d'environnement au backend

| Environnement | Où |
|---|---|
| Local | `environment:` du service `backend` dans `docker-compose.yml`, valeur dans `.env` |
| Azure, variable simple | `az containerapp update -n backend -g rg-quiz-app --set-env-vars NOM=valeur` |
| Azure, secret | `az containerapp secret set -n backend -g rg-quiz-app --secrets nom=valeur`, puis `--set-env-vars NOM=secretref:nom` |

Pour une modification durable sur Azure, l'ajouter aussi dans `scripts/deploy.sh` (tableaux `BACKEND_SECRETS` et `BACKEND_ENV`).

### Changer un secret du cloud

1. Modifier la valeur dans `.env.azure`.
2. `scripts/deploy.sh` : met à jour le secret et crée une nouvelle révision.

Un secret modifié seul n'est pas relu par le conteneur en cours : il faut une nouvelle révision.

### Changer le nombre de réplicas

```bash
az containerapp update -n frontend -g rg-quiz-app --min-replicas 1 --max-replicas 3
```

Durablement : `FRONTEND_MIN_REPLICAS` et `FRONTEND_MAX_REPLICAS` dans `scripts/config.sh`.

### Changer une limite de ressources en local

Dans `docker-compose.yml`, sous `deploy.resources.limits` du service, puis `docker compose up -d`.

### Mettre à jour une image de base

1. Dans le `Dockerfile`, changer le tag et le digest de la ligne `FROM`.
   Récupérer le digest : `docker pull <image:tag>`, puis `docker image inspect <image:tag> --format '{{index .RepoDigests 0}}'`.
2. `docker compose up -d --build`
3. `scripts/scan-trivy.sh final`

### Revenir à la version précédente sur Azure

```bash
# Repérer le tag de l'image précédente
az containerapp revision list -n frontend -g rg-quiz-app --all \
  --query "[].{revision:name, image:properties.template.containers[0].image}" -o table

# Redéployer cette image
az containerapp update -n frontend -g rg-quiz-app --image clemanas.azurecr.io/quiz-frontend:<tag>
```

La méthode propre reste d'annuler le commit (`git revert`) et de passer par une Pull Request.

## 9. Diagnostic

| Symptôme | Commande | Cause fréquente |
|---|---|---|
| Un service ne démarre pas | `docker compose ps` puis `docker compose logs <service>` | |
| `... doit être défini dans .env` | | Variable obligatoire absente du `.env` |
| `backend` en `Restarting`, `Missing API key` | `docker compose logs backend` | `RESEND_API_KEY` vide |
| `frontend` s'arrête, `host not found in upstream "backend:3007"` | `docker compose logs frontend` | Le service `backend` n'existe pas sur le réseau |
| `port is already allocated` | `ss -ltnp \| grep 8087` | Port déjà utilisé : changer `FRONTEND_PORT` |
| Erreur 500 à l'inscription, `relation "users" does not exist` | `docker compose logs backend` | Schéma absent |
| Erreur 500 à l'inscription, `ECONNREFUSED 127.0.0.1:5432` | journaux du backend | `DATABASE_URL` absente |
| Erreur 502 ou 504 sur `/api/...` | journaux du frontend | Backend arrêté ou pas encore prêt |
| `Trop de tentatives d'inscription` | | Limite de 5 par quart d'heure : `docker compose restart backend` |
| Première page lente en ligne | | Démarrage à froid du frontend (0 réplica minimum) |
| La question modifiée n'apparaît pas | `gh run list` | Image du frontend non reconstruite, ou CD pas terminé |
| CI en échec sur Trivy | artefact `trivy-<service>` de l'exécution | Vulnérabilité CRITICAL : mettre à jour l'image de base ou le paquet |
| CD en échec à la connexion Azure | `gh run view <id> --log-failed` | Variables du dépôt ou lien de confiance OIDC |

Ordre de diagnostic conseillé : état des conteneurs (`ps`), journaux (`logs`), test de `/health`, puis test d'une inscription.
