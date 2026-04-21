-- Career Thief Module
-- Fichier: lua/ge/extensions/career/modules/thief.lua
-- Métier de voleur de pièces en mode carrière BeamNG
--
-- Gameplay :
--   1. Approchez un véhicule cible (< maxDistance m, dans le cône frontal)
--   2. Appuyez sur K (configurable) → QTE barre de timing démarre
--   3. Appuyez à nouveau sur K pour saisir la barre au bon moment
--   4. Succès → pièce volée + argent crédité
--   5. Succès OU échec → police immédiatement alertée

local M = {}

-- ── Configuration ─────────────────────────────────────────────────────────────
local cfg = {
  maxDistance        = 9.0,   -- mètres max pour cibler un véhicule
  maxAngleDot        = 0.25,  -- cos(angle) minimum (0.25 ≈ 75°, large pour faciliter)
  qteDuration        = 4.0,   -- secondes disponibles pour le QTE
  qteCursorSpeed     = 0.55,  -- oscillations par seconde (plus haut = plus difficile)
  qteSuccessZone     = 0.18,  -- largeur de la zone verte (0-1, 0.18 = 18%)
  cooldownAfterSteal = 5.0,   -- cooldown en secondes après vol réussi
  cooldownAfterFail  = 3.0,   -- cooldown en secondes après vol raté
  wantedDuration     = 120.0, -- secondes de l'état "recherché"
  targetUpdateHz     = 4,     -- fréquence de mise à jour de la cible (fois/sec)
  debugMode          = false,
}

-- ── Catalogue des pièces volables ─────────────────────────────────────────────
-- w = poids pour la sélection aléatoire (plus haut = plus fréquent)
local PARTS = {
  { id = "wheel_fl",   name = "Roue avant gauche",       value = 185, w = 10 },
  { id = "wheel_fr",   name = "Roue avant droite",       value = 185, w = 10 },
  { id = "wheel_rl",   name = "Roue arrière gauche",     value = 165, w = 10 },
  { id = "wheel_rr",   name = "Roue arrière droite",     value = 165, w = 10 },
  { id = "catalytic",  name = "Pot catalytique",         value = 380, w = 4  },
  { id = "headlightL", name = "Phare gauche",            value = 95,  w = 8  },
  { id = "headlightR", name = "Phare droit",             value = 95,  w = 8  },
  { id = "bumperF",    name = "Pare-chocs avant",        value = 145, w = 7  },
  { id = "bumperR",    name = "Pare-chocs arrière",      value = 115, w = 7  },
  { id = "mirrorL",    name = "Rétroviseur gauche",      value = 50,  w = 6  },
  { id = "mirrorR",    name = "Rétroviseur droit",       value = 50,  w = 6  },
  { id = "hood",       name = "Capot moteur",            value = 230, w = 5  },
  { id = "trunk",      name = "Coffre / Hayon",          value = 200, w = 5  },
  { id = "battery",    name = "Batterie",                value = 130, w = 6  },
  { id = "exhaust",    name = "Silencieux",              value = 90,  w = 5  },
  { id = "fenderFL",   name = "Aile avant gauche",       value = 100, w = 6  },
  { id = "fenderFR",   name = "Aile avant droite",       value = 100, w = 6  },
  { id = "sideL",      name = "Bas de caisse gauche",    value = 75,  w = 4  },
  { id = "sideR",      name = "Bas de caisse droit",     value = 75,  w = 4  },
  { id = "antenna",    name = "Antenne",                 value = 35,  w = 3  },
}

-- ── État interne ──────────────────────────────────────────────────────────────
local state = {
  active          = false,   -- module actif (career mode en cours)
  targetVehId     = nil,     -- ID du véhicule ciblé
  targetPart      = nil,     -- pièce sélectionnée pour le prochain vol
  qteRunning      = false,   -- QTE en cours ?
  qteElapsed      = 0.0,     -- temps écoulé depuis le début du QTE
  qteCursorPos    = 0.0,     -- position actuelle du curseur (0-1)
  cooldown        = 0.0,     -- cooldown restant (secondes)
  wanted          = false,   -- joueur recherché ?
  wantedTimer     = 0.0,     -- temps restant dans l'état recherché
  targetTimer     = 0.0,     -- timer pour la mise à jour de la cible
  stolenParts     = {},      -- [vehicleId] = {partId = true, ...}
}

-- ── Utilitaires ───────────────────────────────────────────────────────────────
local function dbg(msg)
  if cfg.debugMode then
    print("[CareerThief] " .. tostring(msg))
  end
end

local function sendUI(data)
  guihooks.trigger("careerThief_update", data)
end

-- Distance euclidienne entre deux Point3F
local function vecDist(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  local dz = a.z - b.z
  return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- Produit scalaire entre deux vecteurs (normalisés ou non)
local function vecDot(a, b)
  return a.x*b.x + a.y*b.y + a.z*b.z
end

-- Normalise un Point3F, retourne un table {x,y,z}
local function vecNorm(v, len)
  len = len or math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
  if len < 0.0001 then return {x=1, y=0, z=0} end
  return {x = v.x/len, y = v.y/len, z = v.z/len}
end

-- ── Sélection aléatoire pondérée d'une pièce ──────────────────────────────────
local function pickRandomPart(vehId)
  local stolen = state.stolenParts[vehId] or {}
  local pool, totalW = {}, 0
  for _, p in ipairs(PARTS) do
    if not stolen[p.id] then
      table.insert(pool, p)
      totalW = totalW + p.w
    end
  end
  if #pool == 0 then return nil end

  local r = math.random() * totalW
  local cum = 0
  for _, p in ipairs(pool) do
    cum = cum + p.w
    if r <= cum then return p end
  end
  return pool[#pool]
end

-- ── Argent joueur ─────────────────────────────────────────────────────────────
local function addMoney(amount)
  -- API carrière standard (BeamNG 0.32+)
  if career_modules_playerAttributes and career_modules_playerAttributes.addAttribute then
    career_modules_playerAttributes.addAttribute("money", amount)
    dbg("Argent ajouté via playerAttributes : " .. amount)
    return true
  end
  -- Fallback : tentative via career_career
  if career_career and career_career.addMoney then
    career_career.addMoney(amount)
    dbg("Argent ajouté via career_career : " .. amount)
    return true
  end
  dbg("WARN: wallet API introuvable – argent non crédité")
  return false
end

-- ── Alerte police ─────────────────────────────────────────────────────────────
local function alertPolice()
  state.wanted    = true
  state.wantedTimer = cfg.wantedDuration

  -- Tentative via le module law enforcement
  if career_modules_lawEnforcement then
    if career_modules_lawEnforcement.setWantedLevel then
      career_modules_lawEnforcement.setWantedLevel(3)
    elseif career_modules_lawEnforcement.onCrime then
      career_modules_lawEnforcement.onCrime({ type = "vehicleTheft", severity = 3 })
    end
    dbg("Police alertée via lawEnforcement")
  else
    dbg("WARN: career_modules_lawEnforcement introuvable – état wanted UI seulement")
  end

  sendUI({ type = "wantedStart", duration = cfg.wantedDuration })
end

-- ── Appliquer dégâts visuels sur le véhicule volé ────────────────────────────
local function damageTargetVehicle(vehId)
  local veh = be:getObjectByID(vehId)
  if not veh then return end
  -- Commande VLUA : applique des dégâts légers pour simuler le démontage
  veh:queueLuaCommand([[
    if beamstate and beamstate.applyDamage then
      beamstate.applyDamage(35, 0, 0.2, 0)
    end
  ]])
end

-- ── Recherche du véhicule cible ───────────────────────────────────────────────
local function findTargetVehicle()
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then return nil end

  local playerPos = playerVeh:getPosition()
  local playerFwd = playerVeh:getDirectionVector()

  local bestId, bestScore = nil, -1

  -- Itère sur tous les objets BeamNGVehicle dans la scène
  local vehNames = scenetree.findClassObjects("BeamNGVehicle") or {}
  for _, vehName in ipairs(vehNames) do
    local obj = scenetree.findObject(vehName)
    if obj then
      local oid = obj:getID()
      if oid ~= playerVeh:getID() then
        local ok, opos = pcall(function() return obj:getPosition() end)
        if ok and opos then
          -- Calcul distance
          local dist = vecDist(playerPos, opos)

          if dist >= 0.8 and dist <= cfg.maxDistance then
            -- Direction vers la cible
            local dx = opos.x - playerPos.x
            local dy = opos.y - playerPos.y
            local dz = opos.z - playerPos.z
            local dirToObj = vecNorm({x=dx,y=dy,z=dz}, dist)

            -- Produit scalaire avec la direction avant du joueur
            local dot = vecDot(playerFwd, dirToObj)

            if dot >= cfg.maxAngleDot then
              -- Score : distance faible + angle faible = meilleur
              local distScore  = 1.0 - (dist / cfg.maxDistance)
              local angleScore = (dot - cfg.maxAngleDot) / (1.0 - cfg.maxAngleDot)
              local score = distScore * 0.45 + angleScore * 0.55
              if score > bestScore then
                bestScore = score
                bestId    = oid
              end
            end
          end
        end
      end
    end
  end

  return bestId
end

-- ── Calcul de la position du curseur QTE (onde triangulaire) ─────────────────
-- Retourne une valeur entre 0 et 1 oscillant de gauche à droite
local function computeCursorPos(elapsed)
  local period = 1.0 / cfg.qteCursorSpeed  -- secondes par cycle complet
  local t = (elapsed % period) / period    -- 0..1 dans le cycle
  if t < 0.5 then
    return t * 2.0           -- 0 → 1  (va à droite)
  else
    return (1.0 - t) * 2.0  -- 1 → 0  (revient à gauche)
  end
end

-- ── Logique principale : touche de vol appuyée ───────────────────────────────
function M.onTheftKeyPressed()
  if not state.active then return end

  -- ── Cas 1 : QTE en cours → évaluer le résultat ───────────────────────────
  if state.qteRunning then
    local pos     = state.qteCursorPos
    local half    = cfg.qteSuccessZone / 2.0
    local success = (pos >= 0.5 - half) and (pos <= 0.5 + half)

    state.qteRunning = false

    -- Police toujours alertée (succès ET échec)
    alertPolice()

    if success and state.targetVehId and state.targetPart then
      -- Marquer la pièce comme volée sur ce véhicule
      if not state.stolenParts[state.targetVehId] then
        state.stolenParts[state.targetVehId] = {}
      end
      state.stolenParts[state.targetVehId][state.targetPart.id] = true

      addMoney(state.targetPart.value)
      damageTargetVehicle(state.targetVehId)

      state.cooldown = cfg.cooldownAfterSteal

      sendUI({
        type     = "qteSuccess",
        partName = state.targetPart.name,
        value    = state.targetPart.value,
        cursorPos = pos,
      })
      dbg(string.format("SUCCÈS – %s (+%d$) curseur=%.2f", state.targetPart.name, state.targetPart.value, pos))
    else
      state.cooldown = cfg.cooldownAfterFail
      sendUI({
        type      = "qteFail",
        cursorPos = pos,
      })
      dbg(string.format("ÉCHEC – curseur=%.2f zone=[%.2f-%.2f]", pos, 0.5-half, 0.5+half))
    end

    state.targetPart = nil
    return
  end

  -- ── Cas 2 : Cooldown actif ────────────────────────────────────────────────
  if state.cooldown > 0 then
    sendUI({ type = "onCooldown", remaining = state.cooldown })
    return
  end

  -- ── Cas 3 : Pas de cible ──────────────────────────────────────────────────
  local vehId = findTargetVehicle()
  if not vehId then
    sendUI({ type = "noTarget" })
    return
  end

  local part = pickRandomPart(vehId)
  if not part then
    sendUI({ type = "noPartsLeft" })
    return
  end

  -- ── Cas 4 : Lancement du QTE ─────────────────────────────────────────────
  state.targetVehId  = vehId
  state.targetPart   = part
  state.qteRunning   = true
  state.qteElapsed   = 0.0
  state.qteCursorPos = 0.0

  sendUI({
    type        = "qteStart",
    partName    = part.name,
    value       = part.value,
    duration    = cfg.qteDuration,
    successZone = cfg.qteSuccessZone,
  })
  dbg(string.format("QTE démarré – veh=%s pièce=%s", tostring(vehId), part.name))
end

-- ── Boucle principale ─────────────────────────────────────────────────────────
function M.onUpdate(dtReal, dtSim, dtRaw)
  if not state.active then return end

  -- Décompte des timers
  if state.cooldown > 0 then
    state.cooldown = math.max(0.0, state.cooldown - dtReal)
  end

  if state.wantedTimer > 0 then
    state.wantedTimer = math.max(0.0, state.wantedTimer - dtReal)
    if state.wantedTimer <= 0.0 then
      state.wanted = false
      sendUI({ type = "wantedEnd" })
      dbg("Fin de l'état recherché")
    end
  end

  -- ── QTE en cours : mise à jour curseur + timeout ──────────────────────────
  if state.qteRunning then
    state.qteElapsed   = state.qteElapsed + dtReal
    state.qteCursorPos = computeCursorPos(state.qteElapsed)

    if state.qteElapsed >= cfg.qteDuration then
      -- Timeout → échec automatique + police
      state.qteRunning = false
      state.cooldown   = cfg.cooldownAfterFail
      alertPolice()
      sendUI({ type = "qteTimeout" })
      dbg("QTE timeout")
      return
    end

    -- Envoi de la position du curseur à l'UI chaque frame
    sendUI({ type = "qteTick", pos = state.qteCursorPos })
    return
  end

  -- ── Mise à jour périodique de la cible ───────────────────────────────────
  state.targetTimer = state.targetTimer + dtReal
  if state.targetTimer < (1.0 / cfg.targetUpdateHz) then return end
  state.targetTimer = 0.0

  local vehId = findTargetVehicle()
  if vehId then
    local part = pickRandomPart(vehId)
    if part then
      sendUI({
        type       = "targetFound",
        partName   = part.name,
        value      = part.value,
        onCooldown = state.cooldown > 0,
        cooldown   = state.cooldown,
        wanted     = state.wanted,
        wantedTime = state.wantedTimer,
      })
    else
      sendUI({
        type       = "targetExhausted",
        wanted     = state.wanted,
        wantedTime = state.wantedTimer,
      })
    end
  else
    sendUI({
      type       = "idle",
      wanted     = state.wanted,
      wantedTime = state.wantedTimer,
    })
  end
end

-- ── Hooks du système de carrière ──────────────────────────────────────────────
function M.onCareerModulesActivated()
  state.active      = true
  state.qteRunning  = false
  state.cooldown    = 0.0
  state.wantedTimer = 0.0
  state.wanted      = false
  state.targetTimer = 0.0
  math.randomseed(os.time())
  dbg("Module activé (career mode)")
  sendUI({ type = "moduleReady" })
end

function M.onCareerDeactivated()
  state.active     = false
  state.qteRunning = false
  sendUI({ type = "hide" })
  dbg("Module désactivé")
end

-- Alias pour différentes versions de BeamNG
M.onCareerActive             = M.onCareerModulesActivated
M.onCareerModuleActivated    = M.onCareerModulesActivated

-- ── Initialisation de l'extension ─────────────────────────────────────────────
local function init()
  math.randomseed(os.time())
  dbg("Extension chargée – en attente du mode carrière")
end

init()

return M
