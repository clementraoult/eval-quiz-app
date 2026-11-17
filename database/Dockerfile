# Image PostgreSQL du projet : image officielle, durcie, avec le schéma intégré.

# Tag précis + digest : l'image de base ne peut pas changer à notre insu.
FROM postgres:18.7-alpine3.24@sha256:b6972e1115a4ff8eba5d7f7d19184926d1e16d7d1136ae1e1a7ebf286da0f015

# Durcissement :
# - apk upgrade : correctifs de sécurité Alpine publiés depuis l'image de base ;
# - suppression de gosu : ce binaire Go ne sert qu'à passer de root à l'utilisateur
#   postgres au démarrage. Comme le conteneur démarre directement en postgres
#   (USER ci-dessous), il est inutile, et il portait toutes les vulnérabilités
#   relevées par Trivy sur cette image ;
# - suppression du gestionnaire de paquets apk.
RUN apk upgrade --no-cache \
  && rm -f /usr/local/bin/gosu \
  && apk --purge del apk-tools

# Schéma exécuté une seule fois, au premier démarrage sur un volume vide.
COPY init.sql /docker-entrypoint-initdb.d/init.sql

# Utilisateur non-root dès le démarrage (UID 70 dans l'image Alpine)
USER postgres
