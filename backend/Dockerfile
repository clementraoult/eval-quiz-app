# ---------- Étape 1 : installation des dépendances ----------
# Tag précis + digest : l'image de base ne peut pas changer à notre insu.
# Node 24 est la version LTS active ; Alpine donne une image minimale.
FROM node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS deps

WORKDIR /app

# Seuls les fichiers de dépendances sont copiés ici : tant qu'ils ne changent pas,
# Docker réutilise le cache de cette couche et ne relance pas npm.
COPY package.json package-lock.json ./

# npm ci installe exactement les versions du package-lock.json.
# --omit=dev : pas de dépendances de développement dans l'image.
RUN npm ci --omit=dev


# ---------- Étape 2 : image d'exécution ----------
FROM node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5

# Active les optimisations de production d'Express
ENV NODE_ENV=production

WORKDIR /app

# Durcissement de l'image (une seule couche) :
# - apk upgrade : correctifs de sécurité Alpine publiés depuis l'image de base ;
# - tini : mini processus d'init qui sera le processus n°1 du conteneur. Sous Linux,
#   le PID 1 ignore SIGTERM s'il n'a pas prévu de le traiter, et server.js ne le
#   traite pas : sans tini, docker stop attend 10 s puis force l'arrêt ;
# - suppression de npm, npx, corepack et yarn : inutiles pour exécuter server.js,
#   ils portaient la majorité des vulnérabilités relevées par Trivy ;
# - suppression du gestionnaire de paquets apk : rien ne doit être installé à l'exécution.
RUN apk upgrade --no-cache \
  && apk add --no-cache tini \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
            /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
            /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-* \
  && apk --purge del apk-tools

# Les fichiers appartiennent à root : l'utilisateur node peut les lire, pas les modifier.
COPY --from=deps /app/node_modules ./node_modules
COPY package.json server.js ./

# Utilisateur non-root fourni par l'image officielle (UID 1000)
USER node

# Port d'écoute par défaut du backend (process.env.PORT || 3007)
EXPOSE 3007

# /health ne dépend pas de la base : vérifie que le processus Node répond.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:3007/health || exit 1

# tini (PID 1) transmet les signaux à node, lancé directement, sans npm ni shell.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
