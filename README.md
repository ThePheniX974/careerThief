# Career Thief BlackMarket

Ce mod transforme le gameplay en mode carrière:

- vol de voiture au regard (touche `K`)
- livraison vers un point `BlackMarket` (docks par défaut)
- création d’une annonce marketplace locale
- réception d’offres clients et vente

## Boucle de gameplay

1. Regarder une voiture et appuyer sur `K` pour lancer le vol
2. La police est alertée immédiatement
3. Conduire la voiture volée jusqu’au `dropoff` (docks)
4. Si vitesse et intégrité sont valides, l’annonce est créée
5. Attendre les offres, puis accepter/refuser depuis le panneau BlackMarket
6. Vente validée → paiement crédité

## Règles anti-exploit

- Impossible de voler son véhicule joueur
- Cooldown après chaque vol
- Échec mission si le véhicule volé est trop éloigné/perdu
- Livraison refusée si:
  - vitesse trop élevée au dépôt
  - intégrité sous le seuil minimum

## Configuration

Le fichier `careerThief_config.json` pilote tout l’équilibrage:

- `targeting`: distance/cône de ciblage
- `theft`: cooldown, durée recherché, distance max de suivi
- `dropoff`: points de livraison (docks), rayon, vitesse max, intégrité mini
- `marketplace`: marge prix et fréquence des offres
- `debug.debugMode`: active les logs `[CareerThief][INFO]`

## Intégration police

Le module utilise l’API native BeamNG:

- `gameplay_police`
- `gameplay_traffic`

Avec fallback legacy sur `career_modules_lawEnforcement` si nécessaire.

## Fichiers importants

- `lua/ge/extensions/career/modules/thief.lua`: logique de vol + mission + marketplace
- `careerThief_config.json`: équilibrage et points de dropoff
- `ui/modules/apps/careerThief/app.js`: contrôleur UI
- `ui/modules/apps/careerThief/app.html`: HUD + panneau BlackMarket
- `ui/modules/apps/careerThief/app.css`: style du HUD
