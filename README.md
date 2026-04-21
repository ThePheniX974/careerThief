# Career Thief – Mod BeamNG Drive

Ajoute le métier de **voleur de pièces** au mode carrière de BeamNG.  
Approchez un véhicule, tentez de voler une pièce via un QTE, et fuyez la police !

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
│  Approchez-vous d'un véhicule garé (< 9 m, dans votre cône frontal) │
│                           ↓                                          │
│       Le prompt s'affiche : "K – VOLER [nom de la pièce]"           │
│                           ↓                                          │
│           Appuyez sur K → QTE barre de timing démarre               │
│                           ↓                                          │
│     Appuyez à nouveau sur K au bon moment (zone verte centrale)      │
│                           ↓                                          │
│   ✓ SUCCÈS : pièce volée, argent crédité, police alertée             │
│   ✗ ÉCHEC  : police alertée quand même, cooldown court               │
└──────────────────────────────────────────────────────────────────────┘
```

### Règles importantes
- La **police est alertée immédiatement** qu'on réussisse ou qu'on échoue
- Chaque pièce ne peut être volée **qu'une seule fois** par véhicule
- Le badge **RECHERCHÉ** reste affiché pendant 2 minutes (configurable)
- Un **cooldown** empêche le spam de tentatives

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
│   │   └── thief.lua                            ← Module carrière (logique)
│   └── core/input/actions/
│       └── careerThief_actions.json             ← Binding de la touche
└── ui/modules/apps/careerThief/
    ├── app.html                                 ← Interface HUD
    ├── app.js                                   ← Contrôleur AngularJS
    └── app.css                                  ← Styles visuels
```

---

## Débogage

Pour activer les logs dans la console GE-Lua (F10) :

Dans `lua/ge/extensions/career/modules/thief.lua`, ligne 18 :
```lua
debugMode = true,
```

Ou dans `careerThief_config.json` :
```json
"debug": { "debugMode": true }
```

---

## Compatibilité

- **BeamNG Drive** 0.32+ (API career modules)
- Compatible avec les mods de carrière existants (RLS Career Overhaul, etc.)
- L'intégration police fonctionne si `career_modules_lawEnforcement` est disponible
- Fallback gracieux si les APIs ne sont pas disponibles

---

## Problèmes connus

| Problème | Solution |
|----------|----------|
| Le prompt ne s'affiche pas | Vérifiez que vous êtes en mode carrière ET que la touche est assignée |
| L'argent ne s'ajoute pas | Version BeamNG trop ancienne (< 0.32) – le mod fonctionne mais sans crédit |
| La police ne spawn pas | `career_modules_lawEnforcement` absent – état UI seulement |
| QTE trop difficile/facile | Ajustez `cursorSpeed` et `successZone` dans le config JSON |
