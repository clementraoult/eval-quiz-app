# 11 - Lancement local avec Docker Compose

Procédure pour construire et faire tourner Quiz App sur un poste, avec les trois services : `frontend`, `backend` et `db`.
Les choix techniques sont expliqués dans l'[analyse préalable](10-analyse-j1.md).

## Prérequis

- Docker Engine avec le plugin Compose (`docker compose version`).
- Le port 8087 libre sur le poste, ou un autre port défini dans `.env`.

Node.js et PostgreSQL ne sont pas nécessaires sur le poste : tout tourne dans les conteneurs.

## Fichiers de conteneurisation

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image du frontend : build Vite, puis nginx non-root sur le port 8080 |
| `.dockerignore` | Contexte de build du frontend |
| `backend/Dockerfile` | Image du backend : Node.js, utilisateur `node`, `tini` |
| `backend/.dockerignore` | Contexte de build du backend |
| `backend/package-lock.json` | Versions exactes des dépendances, exigé par `npm ci` |
| `nginx/nginx.conf` | Configuration nginx, port d'écoute passé de 80 à 8080 |
| `docker-compose.yml` | Les trois services, le réseau, le volume et les restrictions de sécurité |
| `.env.example` | Modèle de configuration, sans valeur réelle |

## 1. Configuration

```bash
cp .env.example .env
```

Remplacer ensuite dans `.env` les valeurs `changeme` par des valeurs générées :

```bash
openssl rand -hex 16    # POSTGRES_PASSWORD, ADMIN_PASSWORD
openssl rand -hex 32    # JWT_SECRET
```

| Variable | Obligatoire | Remarque |
|---|---|---|
| `POSTGRES_USER`, `POSTGRES_DB` | Oui | |
| `POSTGRES_PASSWORD` | Oui | Alphanumérique : `@ : / #` casseraient l'URL de connexion |
| `RESEND_API_KEY` | Oui | Valeur factice acceptée, le backend ne démarre pas sans elle |
| `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `JWT_SECRET` | Oui | Remplacent les valeurs par défaut publiques du code |
| `FROM_EMAIL` | Non | |
| `FRONTEND_PORT` | Non | 8087 par défaut |

Si une variable obligatoire manque, `docker compose` refuse de démarrer et indique laquelle.
Le fichier `.env` est exclu de Git par `.gitignore`.

## 2. Construction et démarrage

```bash
docker compose config -q        # valide le fichier (n'affiche rien si tout est correct)
docker compose up -d --build    # construit les deux images puis démarre les trois services
docker compose ps               # les trois services doivent être "healthy"
```

Ordre de démarrage imposé par `depends_on` : `db` puis `backend` puis `frontend`.
Chaque service attend que le précédent soit en bonne santé.

Ne pas utiliser `docker compose config` sans `-q` dans une capture : la commande affiche les secrets.

## 3. Accès

| Page | Adresse |
|---|---|
| Quiz | http://localhost:8087 |
| Administration | http://localhost:8087/gestion-quiz |
| Santé du backend, via nginx | http://localhost:8087/health |

L'administration utilise `ADMIN_USERNAME` et `ADMIN_PASSWORD` du fichier `.env`.

## 4. Vérifications

```bash
# Chaîne frontend -> backend
curl -i http://localhost:8087/health

# Tables créées par database/init.sql
docker compose exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"'

# Journaux
docker compose logs -f backend
```

Avec une clé Resend factice, les journaux du backend affichent `API key is invalid` après chaque quiz.
C'est attendu : l'email n'est pas envoyé, le résultat est bien enregistré.

## 5. Persistance des données

Les données PostgreSQL sont dans le volume nommé `quiz-app_pgdata`, monté sur `/var/lib/postgresql`.

```bash
docker compose down      # supprime les conteneurs et le réseau, garde le volume
docker compose up -d     # les données sont toujours présentes
```

`database/init.sql` n'est exécuté qu'au premier démarrage, quand le volume est vide.
Les journaux de `db` indiquent ensuite `Skipping initialization`.

## 6. Cycle de vie

| Commande | Effet |
|---|---|
| `docker compose up -d --build` | Construit et démarre |
| `docker compose ps` | État des services |
| `docker compose logs -f <service>` | Journaux en continu |
| `docker compose stop` / `start` | Arrête ou relance sans supprimer |
| `docker compose restart <service>` | Redémarre un service |
| `docker compose down` | Supprime conteneurs et réseau, **garde les données** |
| `docker compose down -v` | Supprime aussi le volume : **toutes les données sont perdues** |

Après une modification de `database/init.sql`, le nouveau schéma n'est appliqué qu'après `docker compose down -v`.

## 7. Mesures de sécurité appliquées

| Mesure | frontend | backend | db |
|---|---|---|---|
| Image de base épinglée (tag précis et digest) | Oui | Oui | Oui |
| Utilisateur non-root | UID 101 | `node` (UID 1000) | `postgres` après initialisation |
| Port publié sur le poste | 8087 | Aucun | Aucun |
| Système de fichiers en lecture seule | Oui, `/tmp` en mémoire | Oui | Non, la base écrit sur disque |
| `no-new-privileges` | Oui | Oui | Oui |
| Capacités Linux | Toutes retirées | Toutes retirées | 5 conservées pour l'initialisation |
| Limites mémoire, CPU, processus | Oui | Oui | Oui |
| Vérification de santé | Page d'accueil | `/health` | `pg_isready` |

L'analyse des vulnérabilités des images (Trivy) fait l'objet du jalon 2.

## 8. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `... doit être défini dans .env` | Variable obligatoire absente | Compléter `.env` |
| `backend` redémarre en boucle, `Missing API key` | `RESEND_API_KEY` vide | Mettre une valeur, même factice |
| `frontend` s'arrête, `host not found in upstream "backend:3007"` | Le service `backend` n'existe pas sur le réseau | Lancer toute la stack avec `docker compose up -d` |
| `port is already allocated` | Port 8087 déjà utilisé | Changer `FRONTEND_PORT` dans `.env` |
| Erreur 500 à l'inscription, `relation "users" does not exist` | Volume initialisé sans le schéma | `docker compose down -v` puis `up -d` (efface les données) |
| `Trop de tentatives d'inscription` | Limite de 5 inscriptions par 15 minutes et par adresse IP | Attendre, ou `docker compose restart backend` |
