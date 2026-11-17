# Image du frontend : fichiers statiques construits par Vite, servis par nginx.

# ---------- Étape 1 : build (jetée à la fin) ----------
# Tag précis + digest : l'image de base ne peut pas changer à notre insu.
FROM node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS build

WORKDIR /app

# Dépendances d'abord : cette couche reste en cache tant que les deux fichiers ne changent pas.
COPY package.json package-lock.json ./
RUN npm ci

# Sources (filtrées par .dockerignore), puis compilation vers dist/.
# Les questionnaires questions_*.js sont intégrés au build à cette étape.
COPY . .
RUN npm run build


# ---------- Étape 2 : image finale ----------
# nginx-unprivileged : nginx officiel prévu pour tourner sans root (UID 101).
FROM nginxinc/nginx-unprivileged:1.31-alpine3.24@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e

# Durcissement de l'image :
# - apk upgrade : correctifs de sécurité Alpine publiés depuis l'image de base ;
# - suppression de curl et du gestionnaire de paquets apk, inutiles à l'exécution.
# Passage temporaire en root, seul moment où c'est nécessaire.
USER root
RUN apk upgrade --no-cache \
  && apk del --no-cache curl \
  && apk --purge del apk-tools

# Configuration du serveur : fichiers statiques + reverse proxy vers le backend.
# Elle remplace le default.conf de l'image.
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

# Seul le site compilé est copié : ni Node, ni node_modules, ni sources.
# Les fichiers appartiennent à root : nginx (UID 101) peut les lire, pas les modifier.
COPY --from=build /app/dist /usr/share/nginx/html

# Utilisateur non-root (déjà le défaut de l'image, rendu explicite)
USER 101

# Port non privilégié : un utilisateur non-root ne peut pas écouter sur 80.
EXPOSE 8080

# Vérifie que nginx sert la page d'accueil (ne dépend pas du backend).
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/ || exit 1
