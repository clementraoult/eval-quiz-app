# 12 - Sécurité des images (Jalon 2)

Analyse des vulnérabilités des images de Quiz App avec Trivy, corrections appliquées et vulnérabilités résiduelles.
Les rapports bruts sont dans [preuves/J2/](../preuves/J2/).

## 1. Méthode

| Élément | Choix |
|---|---|
| Outil | Trivy 0.76.2, lancé en conteneur, image épinglée par digest |
| Date des scans | 17/11/2026 |
| Périmètre | Les trois images de la stack locale : frontend, backend, base |
| Type d'analyse | Vulnérabilités des paquets système (Alpine) et des dépendances applicatives (Node.js, binaires Go) |
| Script | [scripts/scan-trivy.sh](../scripts/scan-trivy.sh) |

```bash
scripts/scan-trivy.sh initial quiz-backend:initial quiz-frontend:initial
scripts/scan-trivy.sh final
```

Le script exporte chaque image avec `docker save` et la fait analyser depuis ce fichier.
Le socket Docker n'est jamais monté dans le conteneur Trivy : le monter reviendrait à lui donner les droits root sur le poste.

Le script écrit un rapport complet par image, puis relance Trivy avec `--severity CRITICAL --exit-code 1`.
Il se termine en erreur si une vulnérabilité CRITICAL est trouvée. C'est la règle qui sera reprise dans la CI (jalon 6).

## 2. État initial

Images du jalon 1, conservées sous le tag `initial`. Pour la base, l'état initial est l'image officielle `postgres:18.7-alpine3.24`, utilisée telle quelle au jalon 1.

| Image | CRITICAL | HIGH | MEDIUM | LOW | Inconnue | Total |
|---|---|---|---|---|---|---|
| Frontend | 1 | 12 | 4 | 44 | 0 | **61** |
| Backend | 0 | 6 | 15 | 1 | 0 | **22** |
| Base | 1 | 25 | 31 | 3 | 2 | **62** |

Le contrôle bloquant échoue sur le frontend et sur la base (une CRITICAL chacun).

### Origine des vulnérabilités

| Image | Composant vulnérable | Nombre | Exemples |
|---|---|---|---|
| Frontend | Paquets Alpine de l'image de base `nginx-unprivileged` (Alpine 3.24.2) | 61 | `brotli-libs` (CRITICAL, CVE-2026-111497), `curl`, `libcurl`, `libexpat`, `libxslt`, `musl`, `zlib` |
| Backend | npm, embarqué dans l'image Node (`/usr/local/lib/node_modules/npm`) | 19 | `undici`, `brace-expansion`, `ip-address` |
| Backend | Dépendances de l'application (`/app/node_modules`) | 2 | `glob`, `minimatch` |
| Backend | Paquet Alpine | 1 | `zlib` |
| Base | Binaire `gosu`, compilé avec Go 1.24.6 | 62 | bibliothèque standard Go (CRITICAL, CVE-2025-68121) |

Trois constats :

- **Le code de l'application n'est presque pas en cause.** Sur 145 vulnérabilités, 2 viennent des dépendances de Quiz App. Le reste vient des images de base et des outils qu'elles embarquent.
- **Une image épinglée vieillit.** Le frontend est épinglé par digest sur une image construite avec Alpine 3.24.2. Depuis, des correctifs ont été publiés : toutes ses vulnérabilités ont un correctif disponible.
- **Les outils inutiles à l'exécution sont une source de vulnérabilités.** npm dans le backend et `gosu` dans la base ne servent pas une fois le service démarré.

## 3. Corrections

| # | Image | Correction | Justification | Effet |
|---|---|---|---|---|
| 1 | Frontend | `apk upgrade --no-cache` | Applique les correctifs Alpine publiés depuis la construction de l'image de base | 61 vulnérabilités corrigées, dont la CRITICAL |
| 2 | Frontend | Suppression de `curl` | Inutile à l'exécution ; le `HEALTHCHECK` utilise `wget` de BusyBox | Moins d'outils pour un attaquant |
| 3 | Backend | Suppression de npm, npx, corepack et yarn | Le conteneur lance `node server.js` : aucun gestionnaire de paquets n'est nécessaire | 19 vulnérabilités supprimées, dont les 6 HIGH |
| 4 | Backend | `apk upgrade --no-cache` | Correctif de `zlib` | 1 vulnérabilité corrigée |
| 5 | Base | Suppression de `gosu` et démarrage direct avec `USER postgres` | `gosu` ne sert qu'à passer de root à `postgres` au démarrage. En démarrant directement en `postgres`, il devient inutile | 62 vulnérabilités supprimées, dont la CRITICAL |
| 6 | Base | `apk upgrade --no-cache` | Préventif : aucun paquet Alpine vulnérable au moment du scan | |
| 7 | Les trois | Suppression du gestionnaire de paquets `apk` | Rien ne doit être installé dans un conteneur en fonctionnement | Moins d'outils pour un attaquant |

La correction 5 a un effet supplémentaire : le conteneur de la base ne démarre plus en root.
Les cinq capacités Linux qu'il gardait au jalon 1 (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`) ont été retirées du `docker-compose.yml`. Les trois services tournent désormais avec `cap_drop: ALL`.

La base a maintenant son propre [Dockerfile](../database/Dockerfile). Le schéma `init.sql` y est copié, à la place du montage utilisé au jalon 1.

### Vérifications après correction

| Vérification | Résultat |
|---|---|
| Les trois services démarrent et sont `healthy` | Oui |
| Données du jalon 1 toujours présentes (même volume) | Oui |
| Initialisation de la base sur un volume neuf, sans root ni capacité | Oui, les trois tables sont créées |
| `/health` à travers nginx | 200 |
| `npm`, `apk`, `curl`, `gosu` absents des conteneurs | Oui |
| La base de paquets Alpine est toujours lisible par Trivy | Oui : `/lib/apk/db/installed` est conservé, les versions corrigées y figurent |

Le dernier point compte : supprimer la liste des paquets installés ferait disparaître les vulnérabilités du rapport sans les corriger.
Ici, seul l'outil `apk` est supprimé. Trivy détecte toujours Alpine et ses paquets, et le total à zéro est réel.

## 4. État final

| Image | CRITICAL | HIGH | MEDIUM | LOW | Total | Avant |
|---|---|---|---|---|---|---|
| Frontend | 0 | 0 | 0 | 0 | **0** | 61 |
| Backend | 0 | 0 | 2 | 0 | **2** | 22 |
| Base | 0 | 0 | 0 | 0 | **0** | 62 |

Le contrôle bloquant passe sur les trois images : aucune CRITICAL, aucune HIGH.

| Image | Taille avant | Taille après |
|---|---|---|
| Frontend | 91 Mo | 104 Mo |
| Backend | 269 Mo | 269 Mo |
| Base | 434 Mo | 440 Mo |

Les images ne rétrécissent pas, le frontend grossit même.
Une couche Docker ne fait qu'ajouter : les fichiers supprimés ou remplacés restent dans les couches de l'image de base.
L'objectif de ces corrections est le contenu du système de fichiers final, pas la taille.

## 5. Vulnérabilités résiduelles

| CVE | Paquet | Sévérité | Nature | Correctif disponible |
|---|---|---|---|---|
| CVE-2026-118773 | `glob` 10.5.0 | MEDIUM | Déni de service | `glob` 14.0.2 |
| CVE-2026-118764 | `minimatch` 9.0.9 | MEDIUM | Déni de service par motif forgé | `minimatch` 11.0.1 |

### Pourquoi elles ne sont pas corrigées

Ces deux paquets ne sont pas des dépendances directes du backend. Ils arrivent par cette chaîne :

```
resend 2.1.0
└── @react-email/render
    └── pretty
        └── js-beautify
            ├── glob 10.5.0
            └── editorconfig
                └── minimatch 9.0.9
```

- Le correctif demande un saut de version majeure (`glob` 10 vers 14, `minimatch` 9 vers 11). L'imposer avec un `overrides` npm risquerait de casser `js-beautify`, qui n'est pas prévu pour ces versions.
- La voie propre serait de mettre à jour `resend`, dépendance directe du backend. C'est une évolution du code applicatif, hors du périmètre de la mission.

### Pourquoi le risque est accepté

- **Sévérité moyenne**, et impact limité à la disponibilité : pas de fuite de données ni d'exécution de code.
- **Code non atteint.** `glob` et `minimatch` servent à `js-beautify` pour chercher des fichiers de configuration sur disque. Le backend envoie à Resend un HTML déjà construit (`resend.emails.send({ html })`) : il ne passe pas par le rendu React Email. Aucune donnée venant d'un utilisateur n'atteint ces fonctions.
- **Conteneur contraint** : système de fichiers en lecture seule, limites de mémoire, de CPU et de nombre de processus. Un déni de service resterait cantonné au conteneur du backend, qui redémarre automatiquement.

Action recommandée à l'équipe de développement : mettre à jour `resend` vers une version qui ne dépend plus de `js-beautify`.

## 6. Limites et suite

- Un scan reflète la base de vulnérabilités du jour. Une image à zéro aujourd'hui aura des vulnérabilités connues demain, sans avoir changé. Les images doivent être reconstruites et rescannées régulièrement.
- `apk upgrade` rend le build moins reproductible : deux constructions à des dates différentes n'installent pas les mêmes correctifs. C'est accepté ici, la priorité étant de ne pas livrer de vulnérabilité corrigée en amont. Les images de base restent épinglées par digest.
- Trivy ne voit que les vulnérabilités connues des composants. Il ne remplace pas les protections d'exécution (lecture seule, capacités retirées, limites), décrites dans le [lancement local](11-lancement-local.md).
- Au jalon 6, ce scan sera exécuté par la CI sur chaque Pull Request, et une CRITICAL bloquera la fusion.
