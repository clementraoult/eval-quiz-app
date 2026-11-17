# Preuves du jalon 3 : Azure CLI et ACR

Ressources créées le 17/11/2026 avec Azure CLI, par [scripts/deploy.sh](../../scripts/deploy.sh).
La documentation du jalon est dans [docs/13-azure-acr.md](../../docs/13-azure-acr.md).
Les sorties ci-dessous ne contiennent ni identifiant d'abonnement ni jeton.

| Élément à montrer | Preuve | Résultat |
|---|---|---|
| Ressources créées avec Azure CLI | [01-deploy.txt](01-deploy.txt) | Exécution complète de `scripts/deploy.sh`, code de sortie 0 |
| Groupe de ressources et registre | [02-ressources.txt](02-ressources.txt) | `rg-quiz-app` et le registre `quizappclem`, niveau Basic, en `francecentral` |
| Images présentes avec des tags identifiables | [03-images.txt](03-images.txt) | `quiz-backend:6820d93` et `quiz-frontend:6820d93`, le tag étant le commit Git |
| Registre privé | [04-acces.txt](04-acces.txt) | `docker pull` refusé sans authentification, accepté après `az acr login` |

## Remarques

- `01-deploy.txt` est la sortie d'une seconde exécution du script, d'où la ligne « Le registre existe déjà ».
  La date de création du registre figure dans `02-ressources.txt`. Cette seconde exécution montre que le script est réexécutable.
- Une première exécution avait publié des images avec le tag `6820d93-dirty` : le dépôt contenait alors un fichier non commité.
  Ces images ont été supprimées du registre et le script relancé depuis un dépôt propre.
- Restrictions de l'abonnement étudiant constatées : cinq régions autorisées seulement, et service ACR à activer avant la première utilisation.
