# Preuves du jalon 5 : PostgreSQL cloud

Tests réalisés le 17/11/2026 sur l'application en ligne, avec une base Neon (PostgreSQL 18.7, AWS Francfort).
La documentation du jalon est dans [docs/15-postgresql-cloud.md](../../docs/15-postgresql-cloud.md).

Les sorties sont expurgées : la chaîne de connexion, le mot de passe et le nom d'hôte de la base n'y figurent pas.

| Élément à montrer | Preuve | Résultat |
|---|---|---|
| Initialisation du schéma | [01-schema.txt](01-schema.txt) | `init.sql` appliqué, trois tables créées |
| Script réexécutable | [01b-schema-seconde-execution.txt](01b-schema-seconde-execution.txt) | Tables déjà présentes, rien n'est modifié |
| Connexion chiffrée | [02-tls.txt](02-tls.txt) | TLS 1.3 ; une connexion sans chiffrement est refusée par le serveur |
| Inscription et résultat | [03-tests-fonctionnels.txt](03-tests-fonctionnels.txt) | `POST /api/users` et `POST /api/results` en 201, résultat visible dans l'administration |
| Persistance | [04-persistance.txt](04-persistance.txt) | Données identiques avant et après la recréation du conteneur du backend |
| Gestion des secrets | [05-secrets-journaux.txt](05-secrets-journaux.txt) | `DATABASE_URL` référence le secret `database-url` ; `.env.azure` exclu de Git |

## Remarques

- `03-tests-fonctionnels.txt` : le message `Results saved and email sent` est celui du code. L'email n'est pas réellement envoyé, la clé Resend étant factice.
- `04-persistance.txt` : deux utilisateurs pour un résultat, une inscription ayant été faite sans terminer de quiz.
- `05-secrets-journaux.txt` : l'avertissement du pilote `pg` sur `sslmode` est informatif. Il confirme que `sslmode=require` est traité comme `verify-full`, donc avec vérification du certificat.
- Captures d'écran à ajouter : inscription et résultat dans le navigateur, page d'administration listant le résultat. Vérifier qu'aucun mot de passe n'y est visible.
