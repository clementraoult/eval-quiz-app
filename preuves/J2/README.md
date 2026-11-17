# Preuves du jalon 2 : sécurité des images

Scans réalisés le 17/11/2026 avec Trivy 0.76.2.
Le rapport complet, avec la justification des corrections et des vulnérabilités résiduelles, est dans [docs/12-securite-images.md](../../docs/12-securite-images.md).

## Rapports Trivy

| Image | Avant | Après |
|---|---|---|
| Frontend | [scan-initial-frontend.txt](scan-initial-frontend.txt) : 61, dont 1 CRITICAL | [scan-final-frontend.txt](scan-final-frontend.txt) : 0 |
| Backend | [scan-initial-backend.txt](scan-initial-backend.txt) : 22, dont 6 HIGH | [scan-final-backend.txt](scan-final-backend.txt) : 2 MEDIUM |
| Base | [scan-initial-db.txt](scan-initial-db.txt) : 62, dont 1 CRITICAL | [scan-final-db.txt](scan-final-db.txt) : 0 |

## Commandes utilisées

```bash
# État initial : images du jalon 1, conservées sous le tag "initial"
docker tag quiz-backend:local quiz-backend:initial
docker tag quiz-frontend:local quiz-frontend:initial
scripts/scan-trivy.sh initial quiz-backend:initial quiz-frontend:initial
# -> code de sortie 1 : CRITICAL dans quiz-frontend:initial

# Après corrections des Dockerfiles
docker compose up -d --build
scripts/scan-trivy.sh final
# -> code de sortie 0 : aucune CRITICAL
```

L'état initial de la base est le scan de l'image officielle `postgres:18.7-alpine3.24`, utilisée sans modification au jalon 1.

## Corrections, en résumé

| Image | Correction |
|---|---|
| Frontend | `apk upgrade`, suppression de `curl` et de `apk` |
| Backend | Suppression de npm, npx, corepack, yarn et `apk`, `apk upgrade` |
| Base | Suppression de `gosu`, démarrage direct en utilisateur `postgres`, suppression de `apk` |
