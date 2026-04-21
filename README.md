# Career Thief – Mod BeamNG Drive

Ajoute le métier de **voleur de pièces** au mode carrière de BeamNG.
**Regardez** une pièce sur un véhicule garé, lancez le QTE, et envoyez-la directement dans votre inventaire **My Parts** natif — avant que la police ne vous rattrape.

---

## Installation

1. Copiez le dossier `careerThief/` dans :
   ```
   Documents/BeamNG.drive/mods/unpacked/careerThief/
   ```
   **OU** zippez-le et placez `careerThief.zip` dans :
   ```
   Documents/BeamNG.drive/mods/
   ```

2. Lancez BeamNG Drive → **Mods Manager** → activez **Career Thief**

3. Attribuez la touche dans **Options → Contrôles → Gameplay** :
   - Cherchez **"Career Thief – Voler une pièce"**
   - Assignez la touche de votre choix (recommandée : **K**)

4. Lancez une session en mode **Carrière**

---

## Gameplay

```
┌──────────────────────────────────────────────────────────────────────┐
│  Regardez une partie d'un véhicule garé (< 9 m, réticule à l'écran) │
│                           ↓                                          │
│       Le réticule s'illumine + le prompt affiche la pièce ciblée    │
│                           ↓                                          │
│               Appuyez sur K → le QTE barre démarre                  │
│                           ↓                                          │
│     Appuyez à nouveau sur K au bon moment (zone verte centrale)     │
│                           ↓                                          │
│   ✓ SUCCÈS : pièce transférée dans My Parts, police alertée         │
│   ✗ ÉCHEC  : police alertée quand même, cooldown court              │
└──────────────────────────────────────────────────────────────────────┘
```

### Ciblage au regard

Le mod lance un **raycast depuis la caméra** (3e personne, 1re personne, orbite…) jusqu'au véhicule regardé. Le point d'impact est projeté dans le repère local du véhicule et mappé à une pièce selon sa zone (avant/milieu/arrière × gauche/centre/droite × haut/milieu/bas). Le nom de la pièce visée s'affiche en temps réel dans le HUD.

### Règles importantes
- La **police est alertée immédiatement** qu'on réussisse ou qu'on échoue
- Chaque pièce ne peut être volée **qu'une seule fois** par véhicule
- Les pièces volées vont **directement dans votre inventaire My Parts** (celui du garage natif BeamNG) — aucun argent n'est crédité
- Le badge **RECHERCHÉ** reste affiché pendant 2 minutes (configurable)
- Un **cooldown** empêche le spam de tentatives

---

## Inventaire "My Parts"

Les pièces volées sont envoyées dans l'inventaire de pièces **natif BeamNG** (`career_modules_partInventory`), accessible depuis le garage et les menus de carrière. **Aucun inventaire custom** n'est tenu par le mod.

Si `career_modules_partInventory` n'est pas disponible (hors mode carrière, ou version BeamNG < 0.32), le vol est **bloqué** avec un message explicite dans le HUD et la console F10. Ouvrez la console GE-Lua (F10) pour voir les logs `[CareerThief]` détaillés au premier lancement — le mod dump automatiquement les fonctions exposées par l'API d'inventaire pour diagnostic.

---

## Équilibrage

Modifiez `careerThief_config.json` pour ajuster la difficulté :

```json
"qte": {
  "duration"    : 4.0,    ↑ plus de temps pour réagir
  "cursorSpeed" : 0.55,   ↑ curseur plus rapide = plus difficile
  "successZone" : 0.18    ↑ zone plus large = plus facile
}
```

Des **profils prédéfinis** sont disponibles dans le JSON :
`"facile"`, `"normal"`, `"difficile"`, `"expert"`

---

## Structure des fichiers

```
careerThief/
├── info.json                                    ← Infos du mod
├── careerThief_config.json                      ← Configuration équilibrage
├── README.md
├── lua/ge/extensions/
│   ├── career/modules/
│   │   └── thief.lua                            ← Module carrière (logique + raycast + inventaire)
│   └── core/input/actions/
│       └── careerThief_actions.json             ← Binding de la touche
└── ui/modules/apps/careerThief/
    ├── app.html                                 ← Interface HUD
    ├── app.js                                   ← Contrôleur AngularJS
    └── app.css                                  ← Styles visuels
```

---

## Débogage

Tous les messages du mod commencent par `[CareerThief]` dans la console GE-Lua (F10), avec trois niveaux :

- `[CareerThief][INFO]` — info normale (seulement si `debugMode = true`)
- `[CareerThief][WARN]` — alerte non bloquante (toujours affichée)
- `[CareerThief][ERROR]` — erreur bloquante (toujours affichée)

### Activer les logs INFO complets

Dans `careerThief_config.json` :
```json
"debug": { "debugMode": true }
```

ou directement dans `lua/ge/extensions/career/modules/thief.lua`, en haut du fichier :
```lua
debugMode = true,
```

### Que regarder en cas de bug

1. Ouvrez la console **F10** (GE-Lua).
2. Filtrez sur `[CareerThief]`.
3. Au démarrage du mode carrière, vous devriez voir :
   - `[INFO] ===== Career Thief : activation mode carrière =====`
   - `[INFO] API career_modules_partInventory détectée - fonctions exposées : ...`

Si au contraire `[ERROR] career_modules_partInventory introuvable`, l'API n'est pas chargée — vérifiez que vous êtes bien en mode carrière et pas en mode libre ou scénario.

Si un vol échoue avec `[ERROR] Aucune signature d'ajout connue n'a réussi`, la version de BeamNG expose des noms de fonctions différents de ceux essayés. Le log affiche toutes les fonctions réellement exposées — il suffit d'ajouter le bon nom dans `addToMyParts()` dans `thief.lua`.

---

## Compatibilité

- **BeamNG Drive** 0.32+ (requis pour `career_modules_partInventory`)
- Compatible avec les mods de carrière existants (RLS Career Overhaul, etc.)
- L'intégration police fonctionne si `career_modules_lawEnforcement` est disponible (sinon état wanted affiché dans le HUD uniquement)
- Le détachement visuel utilise `partmgmt.setPartsConfig` côté VLUA du véhicule cible

---

## Problèmes connus

| Problème | Solution |
|----------|----------|
| Le réticule ne change pas de couleur | Visez directement le véhicule (< 9 m, dans la vue caméra) |
| `[ERROR] career_modules_partInventory introuvable` | Vous n'êtes pas en mode carrière, ou version BeamNG < 0.32 |
| `[ERROR] Aucune signature d'ajout connue n'a réussi` | Version BeamNG différente : ouvrez F10, lisez les fonctions exposées par l'API, et ajoutez la bonne dans `addToMyParts()` |
| La pièce reste visible sur le véhicule | Le détachement VLUA a échoué, mais la pièce est quand même dans My Parts. Recharge le véhicule pour rafraîchir visuellement. |
| La police ne spawn pas | `career_modules_lawEnforcement` absent – état UI seulement |
| QTE trop difficile/facile | Ajustez `cursorSpeed` et `successZone` dans `careerThief_config.json` |
