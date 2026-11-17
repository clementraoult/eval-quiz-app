# 18 - Sous-domaine personnalisé et HTTPS (fonctionnalité avancée)

Rattachement du sous-domaine attribué par le formateur au frontend Azure Container Apps, avec un certificat HTTPS managé.
Les preuves sont dans [preuves/bonus-domaine/](../preuves/bonus-domaine/).

## 1. Résultat

| Élément | Valeur |
|---|---|
| Adresse de l'application | https://g09.labformation.fr |
| Certificat | Managé par Azure, émis pour `g09.labformation.fr`, valide jusqu'au 17/05/2027 |
| HTTP | Redirigé vers HTTPS (301) |
| Adresse d'origine | `https://frontend.salmonwave-d76adf8c.francecentral.azurecontainerapps.io`, toujours active |

## 2. Répartition des rôles

| Acteur | Action |
|---|---|
| Formateur | Attribue le sous-domaine et crée les enregistrements DNS dans la zone `labformation.fr`, qu'il gère |
| Groupe | Fournit les valeurs des enregistrements, puis rattache le domaine à l'application et fait émettre le certificat |

Le groupe n'a aucun droit sur la zone DNS.

## 3. Enregistrements DNS

| Type | Nom | Valeur | Rôle |
|---|---|---|---|
| CNAME | `g09.labformation.fr` | `frontend.salmonwave-d76adf8c.francecentral.azurecontainerapps.io` | Dirige le trafic vers le frontend |
| TXT | `asuid.g09.labformation.fr` | Identifiant de vérification de l'application | Prouve à Azure que le domaine nous est bien attribué |

L'identifiant de vérification se lit sur l'application :

```bash
az containerapp show --name frontend --resource-group rg-quiz-app \
  --query properties.customDomainVerificationId -o tsv
```

Sans l'enregistrement TXT, Azure refuse d'ajouter le domaine : n'importe qui pourrait sinon rattacher à son application un domaine qui ne lui appartient pas.

## 4. Rattachement et certificat

```bash
# 1. Déclarer le domaine sur l'application (Azure vérifie le TXT)
az containerapp hostname add --name frontend --resource-group rg-quiz-app \
  --hostname g09.labformation.fr

# 2. Faire émettre un certificat managé et l'associer au domaine
az containerapp hostname bind --name frontend --resource-group rg-quiz-app \
  --hostname g09.labformation.fr --environment env-quiz-app --validation-method CNAME
```

Pour ce projet, ces deux opérations ont été réalisées depuis le portail Azure (application `frontend`, **Domaines personnalisés**, puis environnement, **Certificats**).
`scripts/deploy.sh` contient l'équivalent en ligne de commande, exécuté seulement si le domaine n'est pas déjà rattaché (paramètre `CUSTOM_DOMAIN` de `scripts/config.sh`).

Déroulement observé :

| Étape | État |
|---|---|
| Domaine ajouté, sans certificat | Liaison `Disabled` : le domaine ne répond pas encore en HTTPS |
| Certificat demandé | `En attente` pendant quelques minutes : Azure vérifie le CNAME puis fait émettre le certificat |
| Certificat émis | `Succeeded`, liaison `SniEnabled` |

### Certificat managé

- Gratuit, émis par une autorité reconnue (DigiCert), et renouvelé automatiquement par Azure.
- La validation se fait par le CNAME : tant qu'il pointe vers le frontend, le renouvellement fonctionne.
- `SniEnabled` : l'environnement présente le bon certificat selon le nom de domaine demandé par le navigateur.
- Aucune clé privée n'est manipulée par le groupe, ni stockée dans le dépôt.

## 5. Vérifications

| Test | Résultat |
|---|---|
| `curl -i https://g09.labformation.fr/health` | 200, `{"status":"ok"}` |
| Page du quiz | 200 |
| `http://g09.labformation.fr/` | 301 vers HTTPS |
| Certificat présenté | Sujet `g09.labformation.fr`, vérifié sans erreur |

L'application n'a pas eu besoin d'être modifiée : le frontend appelle l'API par une URL relative (`/api`), qui suit le nom de domaine utilisé.

## 6. Effet sur le reste de la chaîne

| Élément | Effet |
|---|---|
| CD GitHub Actions | Aucun : `az containerapp update --image` conserve le domaine et le certificat |
| `scripts/deploy.sh` | Rattache le domaine s'il manque, par exemple après une recréation complète |
| `scripts/destroy.sh` | Supprime l'application et son certificat. Les enregistrements DNS restent chez le formateur |

Après une recréation de l'environnement, le nom du frontend (`frontend.<identifiant>...`) change : il faut alors redemander au formateur de mettre à jour le CNAME. L'identifiant de vérification du TXT, lié à l'abonnement, ne change pas.
