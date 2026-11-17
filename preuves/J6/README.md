# Preuves du jalon 6 : CI/CD

Exécutions du 17/11/2026 sur le fork `clementraoult/eval-quiz-app`.
La documentation du jalon est dans [docs/16-ci-cd.md](../../docs/16-ci-cd.md).
Les sorties ne contiennent aucun secret. Les identifiants d'abonnement sont masqués.

## J6-A : CI sur Pull Request

| Élément | Preuve |
|---|---|
| Pull Request vers `main` du fork | https://github.com/clementraoult/eval-quiz-app/pull/8 |
| Exécution de la CI | https://github.com/clementraoult/eval-quiz-app/actions/runs/44089128188 |
| Détail des jobs et des étapes | [02-ci-pull-request.txt](02-ci-pull-request.txt) |

Les trois contrôles sont passés : `Build et scan Trivy (backend)`, `Build et scan Trivy (frontend)`, `Test de la stack Docker Compose`.

Une seconde Pull Request (n°9, mise à jour de `resend`) est passée par la même CI :
https://github.com/clementraoult/eval-quiz-app/actions/runs/44091462736

**Restent à produire :** la protection de `main` avec contrôles obligatoires, l'approbation par un second membre, et la démonstration du contrôle Trivy en échec puis réussi.

## J6-B : CD après fusion dans `main`

| Élément | Preuve |
|---|---|
| Accès du pipeline à Azure (OIDC, droits) | [01-acces-azure.txt](01-acces-azure.txt) |
| Exécution du CD après la fusion de la PR n°8 | [03-cd-apres-fusion.txt](03-cd-apres-fusion.txt), https://github.com/clementraoult/eval-quiz-app/actions/runs/44089326525 |
| CD déclenché par la fusion de la PR n°9 | https://github.com/clementraoult/eval-quiz-app/actions/runs/44091809003 |
| Images dans ACR et révisions Container Apps | [04-acr-revisions.txt](04-acr-revisions.txt) |
| Liste des exécutions | [05-executions.txt](05-executions.txt) |

Résultat : chaque fusion dans `main` a publié des images taguées par son commit (`7d2910d`, `3d146de`) et créé une nouvelle révision des deux applications. La version en ligne est la tête de `main`.

## Incidents pendant la mise en place

| Tentative du CD | Résultat | Cause |
|---|---|---|
| 1re (commit `7d2910d`) | Échec à la connexion Azure | Variables du dépôt absentes |
| 2e, relance | Échec à la connexion Azure | Sujet OIDC différent de celui déclaré côté Azure (`AADSTS700213`) |
| 3e, relance | Succès | Lien de confiance corrigé |

Entre-temps, la fusion de la PR n°9 avait déployé le commit `3d146de`.
La relance de l'ancienne exécution a redéployé `7d2910d`, plus ancien.
Un déploiement manuel de `main` a remis en ligne `3d146de` :
https://github.com/clementraoult/eval-quiz-app/actions/runs/44092662687
