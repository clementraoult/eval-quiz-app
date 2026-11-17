# Preuves du jalon 3 : Azure CLI et ACR

Ressources créées le 17/11/2026 avec Azure CLI, par [scripts/deploy.sh](../../scripts/deploy.sh).
La documentation du jalon est dans [docs/13-azure-acr.md](../../docs/13-azure-acr.md).
Les sorties ci-dessous ne contiennent ni identifiant d'abonnement ni jeton.

| Élément à montrer | Preuve | Résultat |
|---|---|---|
| Ressources créées avec Azure CLI | [01-deploy.txt](01-deploy.txt) | Exécution complète de `scripts/deploy.sh` (création du registre, build, publication), code de sortie 0 |
| Groupe de ressources et registre | [02-ressources.txt](02-ressources.txt) | `rg-quiz-app` et le registre `clemanas`, niveau Basic, en `francecentral` |
| Images présentes avec des tags identifiables | [03-images.txt](03-images.txt) | `quiz-backend:a47334d` et `quiz-frontend:a47334d`, le tag étant le commit Git |
| Registre privé | [04-acces.txt](04-acces.txt) | `docker pull` refusé sans authentification, accepté après `az acr login` |

## Remarques

- Le registre a d'abord été créé sous le nom `quizappclem`, puis recréé sous le nom `clemanas`, celui du groupe.
  Un registre ACR ne peut pas être renommé : l'ancien a été supprimé, et `scripts/deploy.sh` relancé avec le nouveau nom.
  Les sorties de ce dossier sont celles du registre `clemanas`.
- Le nom souhaité, `clem_anas`, est refusé par Azure : un nom de registre ne contient que des lettres minuscules et des chiffres.
- Lors de la toute première exécution, des images avaient été publiées avec le suffixe `-dirty` : le dépôt contenait alors un fichier non commité.
  Elles ont été supprimées et le script relancé depuis un dépôt propre.
- Restrictions de l'abonnement étudiant constatées : cinq régions autorisées seulement, et service ACR à activer avant la première utilisation.
