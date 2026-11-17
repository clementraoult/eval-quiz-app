# Preuves : sous-domaine personnalisé et HTTPS

Fonctionnalité avancée facultative, réalisée le 17/11/2026.
La documentation est dans [docs/18-nom-de-domaine.md](../../docs/18-nom-de-domaine.md).

**Application :** https://g09.labformation.fr

| Élément | Preuve | Résultat |
|---|---|---|
| Enregistrements DNS, domaine rattaché, certificat managé | [01-dns-azure.txt](01-dns-azure.txt) | CNAME et TXT en place, liaison `SniEnabled`, certificat `Succeeded` |
| HTTPS et certificat | [02-https.txt](02-https.txt) | `/health` en 200, HTTP redirigé, certificat valide émis pour `g09.labformation.fr` |

Les enregistrements DNS ont été créés par le formateur, qui gère la zone `labformation.fr`.
