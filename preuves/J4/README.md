# Preuves du jalon 4 : frontend et backend dans Azure Container Apps

Déploiement réalisé le 17/11/2026 par [scripts/deploy.sh](../../scripts/deploy.sh).
La documentation du jalon est dans [docs/14-azure-container-apps.md](../../docs/14-azure-container-apps.md).
Les sorties ne contiennent ni identifiant d'abonnement, ni valeur de secret. Les adresses IP des clients sont masquées dans les journaux.

**Application en ligne :** https://frontend.salmonwave-d76adf8c.francecentral.azurecontainerapps.io

| Élément à montrer | Preuve | Résultat |
|---|---|---|
| Déploiement avec Azure CLI | [01-deploy.txt](01-deploy.txt) | Création des deux applications, test `/health` en 200, code de sortie 0 |
| Deux applications configurées | [02-ressources.txt](02-ressources.txt) | `frontend` et `backend` en cours d'exécution dans `env-quiz-app` |
| Images tirées d'ACR | [03-images-registre.txt](03-images-registre.txt) | Images `clemanas.azurecr.io/...:27bad84`, identité managée avec le rôle `AcrPull` |
| Variables et secrets | [04-configuration-backend.txt](04-configuration-backend.txt) | Les valeurs sensibles sont des références à des secrets |
| État des révisions | [05-revisions.txt](05-revisions.txt) | Une révision active et saine par application, backend sans redémarrage |
| Journaux des révisions | [06-journaux.txt](06-journaux.txt) | `Server running on port 3007`, requêtes `/health` en 200 dans nginx |
| Ingress du frontend et test de `/health` | [07-tests.txt](07-tests.txt) | HTTPS en 200, HTTP redirigé, backend injoignable depuis Internet |
| Diagnostic sans base de données | [08-diagnostic-sans-base.txt](08-diagnostic-sans-base.txt) | Le backend démarre et répond ; seules les routes SQL échouent (500) |

## Test de `/health`

```
$ curl -i https://frontend.salmonwave-d76adf8c.francecentral.azurecontainerapps.io/health
HTTP/2 200
content-type: application/json; charset=utf-8
{"status":"ok"}
```

La requête traverse toute la chaîne : Internet, ingress Azure en HTTPS, nginx du frontend, puis backend sur `backend:3007`.
Elle ne fait aucune requête à PostgreSQL.

## Remarques

- `01-deploy.txt` est la sortie de la seconde exécution du script. La première a échoué à la création du backend :
  l'environnement avait été créé en mode Express, qui refuse l'accès TCP (`ExpressTcpIngressNotSupported`).
  L'environnement a été recréé en mode `WorkloadProfiles` et le script corrigé.
- Le démarrage du backend sans PostgreSQL est validé expérimentalement : voir `08-diagnostic-sans-base.txt`.
  La dépendance qui bloque réellement le démarrage est `RESEND_API_KEY`.
