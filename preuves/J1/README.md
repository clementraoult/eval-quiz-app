# Preuves du jalon 1 : conteneurisation locale

Tests réalisés le 17/11/2026 sur le poste de développement (Ubuntu 26.04, Docker avec BuildKit et Compose).
Les fichiers ci-dessous sont des sorties de commandes réelles. Aucun secret n'y figure.

| Élément à montrer | Preuve | Résultat |
|---|---|---|
| Construction des images | [01-build.txt](01-build.txt) | `quiz-frontend:local` et `quiz-backend:local` construites |
| Démarrage avec Docker Compose | [02-demarrage.txt](02-demarrage.txt) | 3 services `healthy`, processus non-root |
| Communication frontend / backend | [03-communication.txt](03-communication.txt) | `/health` répond 200 à travers nginx ; le backend n'est pas joignable depuis le poste |
| Base PostgreSQL accessible | [04-base.txt](04-base.txt) | Tables `users`, `quiz_results`, `answers` présentes |
| Persistance après recréation | [05-persistance.txt](05-persistance.txt) | Données identiques avant et après `docker compose down` puis `up` |

## Fonctionnalités principales

Parcours testé à travers nginx, sur http://localhost:8087 :

| Action | Requête | Résultat |
|---|---|---|
| Inscription | `POST /api/users` | 201, utilisateur créé |
| Enregistrement d'un résultat | `POST /api/results` | 201, résultat et réponses enregistrés |
| Connexion à l'administration | `POST /api/admin/login` avec le mot de passe du `.env` | 200, jeton reçu |
| Connexion avec le mot de passe par défaut du code (`admin123`) | `POST /api/admin/login` | 401, refusée |
| Consultation des résultats | `GET /api/admin/results` | Le résultat enregistré est listé |

Captures d'écran à ajouter dans ce dossier : page du quiz, résultat d'un quiz, page d'administration.

## Explication du volume

- Les données PostgreSQL sont stockées dans le volume nommé `quiz-app_pgdata`, géré par Docker et indépendant des conteneurs.
- Il est monté sur `/var/lib/postgresql`. Avec PostgreSQL 18, les données sont dans `/var/lib/postgresql/18/docker` (variable `PGDATA` de l'image).
- `docker compose down` supprime les conteneurs et le réseau, pas le volume. Seul `docker compose down -v` le supprime.
- `database/init.sql` n'est exécuté que sur un volume vide. Au second démarrage, les journaux indiquent `Skipping initialization` : le schéma et les données viennent bien du volume.

## Constats faits pendant le jalon

| Constat | Traitement |
|---|---|
| Le backend plante au démarrage sans `RESEND_API_KEY` (`Missing API key`) | Variable rendue obligatoire dans le compose, valeur factice documentée |
| `ADMIN_PASSWORD` et `JWT_SECRET` ont des valeurs par défaut publiques dans le code | Variables rendues obligatoires avec `${VAR:?}` |
| `docker stop` du backend prenait 10 secondes (node en PID 1 ignore `SIGTERM`) | Ajout de `tini` dans l'image : arrêt en 0,2 seconde |
| nginx refuse de démarrer s'il ne résout pas `backend` | Service nommé `backend`, démarrage conditionné à sa bonne santé |
| nginx non-root ne peut pas écouter sur le port 80 | `listen 8080` dans `nginx/nginx.conf` |
| Avec PostgreSQL 18, le volume ne se monte plus sur `/var/lib/postgresql/data` | Montage sur `/var/lib/postgresql`, vérifié avec `PGDATA` |
| `backend/` n'avait pas de `package-lock.json` | Fichier généré et versionné pour des builds reproductibles |
