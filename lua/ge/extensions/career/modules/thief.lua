-- Career Thief Module
-- Fichier: lua/ge/extensions/career/modules/thief.lua
-- Métier de voleur de pièces en mode carrière BeamNG
--
-- Gameplay :
--   1. Regardez une pièce sur un véhicule (raycast caméra, cône serré).
--   2. Appuyez sur K (configurable) → QTE barre de timing démarre sur la pièce visée.
--   3. Appuyez à nouveau sur K pour saisir la barre au bon moment.
--   4. Succès → pièce transférée dans "My Parts" (inventaire natif BeamNG).
--   5. Succès OU échec → police immédiatement alertée.

local M = {}

-- ── Configuration ─────────────────────────────────────────────────────────────
local cfg = {
  maxDistance        = 9.0,    -- portée max du raycast caméra (m)
  maxCamAngleDeg     = 18.0,   -- demi-angle max entre rayon cam et centre véhicule (° fallback)
  vehicleHitRadius   = 2.4,    -- rayon englobant approximatif d'une voiture pour tester le rayon
  qteDuration        = 4.0,
  qteCursorSpeed     = 0.55,
  qteSuccessZone     = 0.18,
  cooldownAfterSteal = 5.0,
  cooldownAfterFail  = 3.0,
  wantedDuration     = 120.0,
  targetUpdateHz     = 6,
  debugMode          = false, -- N'affecte QUE le niveau INFO. WARN/ERROR restent toujours visibles.
}

-- ── Logger explicite ──────────────────────────────────────────────────────────
-- Tous les messages commencent par [CareerThief] pour filtrage facile dans F10.
local function logInfo(msg)
  if cfg.debugMode then
    print("[CareerThief][INFO]  " .. tostring(msg))
  end
end
local function logWarn(msg)
  print("[CareerThief][WARN]  " .. tostring(msg))
end
local function logError(msg)
  print("[CareerThief][ERROR] " .. tostring(msg))
end

-- ── Catalogue des pièces volables ─────────────────────────────────────────────
-- zone = { lon=F|M|R, side=L|C|R, vert=H|M|L } projection normalisée dans la demi-bbox du véhicule.
-- slot  = nom de slot Jbeam standard BeamNG (pour détacher via partmgmt / partInventory).
local PARTS = {
  -- AVANT (lon=F)
  { id="hood",       name="Capot moteur",       value=230, slot="hood",        zone={lon="F", side="C", vert="H"} },
  { id="bumperF",    name="Pare-chocs avant",   value=145, slot="bumper_F",    zone={lon="F", side="C", vert="L"} },
  { id="headlightL", name="Phare gauche",       value=95,  slot="headlight_L", zone={lon="F", side="L", vert="M"} },
  { id="headlightR", name="Phare droit",        value=95,  slot="headlight_R", zone={lon="F", side="R", vert="M"} },
  { id="fenderFL",   name="Aile avant gauche",  value=100, slot="fender_L",    zone={lon="F", side="L", vert="H"} },
  { id="fenderFR",   name="Aile avant droite",  value=100, slot="fender_R",    zone={lon="F", side="R", vert="H"} },
  { id="wheel_fl",   name="Roue avant gauche",  value=185, slot="wheel_FL",    zone={lon="F", side="L", vert="L"} },
  { id="wheel_fr",   name="Roue avant droite",  value=185, slot="wheel_FR",    zone={lon="F", side="R", vert="L"} },

  -- MILIEU (lon=M)
  { id="mirrorL",    name="Rétroviseur gauche", value=50,  slot="mirror_L",    zone={lon="M", side="L", vert="H"} },
  { id="mirrorR",    name="Rétroviseur droit",  value=50,  slot="mirror_R",    zone={lon="M", side="R", vert="H"} },
  { id="sideL",      name="Bas de caisse gauche", value=75,slot="skirt_L",     zone={lon="M", side="L", vert="L"} },
  { id="sideR",      name="Bas de caisse droit",  value=75,slot="skirt_R",     zone={lon="M", side="R", vert="L"} },
  { id="doorL",      name="Portière gauche",    value=140, slot="door_L",      zone={lon="M", side="L", vert="M"} },
  { id="doorR",      name="Portière droite",    value=140, slot="door_R",      zone={lon="M", side="R", vert="M"} },
  { id="antenna",    name="Antenne",            value=35,  slot="antenna",     zone={lon="M", side="C", vert="H"} },

  -- ARRIÈRE (lon=R)
  { id="trunk",      name="Coffre / Hayon",     value=200, slot="tailgate",    zone={lon="R", side="C", vert="H"} },
  { id="bumperR",    name="Pare-chocs arrière", value=115, slot="bumper_R",    zone={lon="R", side="C", vert="L"} },
  { id="exhaust",    name="Silencieux",         value=90,  slot="exhaust",     zone={lon="R", side="C", vert="M"} },
  { id="wheel_rl",   name="Roue arrière gauche",value=165, slot="wheel_RL",    zone={lon="R", side="L", vert="L"} },
  { id="wheel_rr",   name="Roue arrière droite",value=165, slot="wheel_RR",    zone={lon="R", side="R", vert="L"} },
}

-- ── État interne ──────────────────────────────────────────────────────────────
local state = {
  active          = false,
  targetVehId     = nil,
  targetHitPos    = nil,
  targetPart      = nil,
  qteRunning      = false,
  qteElapsed      = 0.0,
  qteCursorPos    = 0.0,
  cooldown        = 0.0,
  wanted          = false,
  wantedTimer     = 0.0,
  targetTimer     = 0.0,
  stolenParts     = {},  -- [vehicleId] = { [partId]=true }
  apiHealthy      = false, -- career_modules_partInventory détectée ?
  apiFunctions    = {},    -- liste des fonctions exposées (pour diagnostic)
}

-- ── Utilitaires mathématiques ─────────────────────────────────────────────────
local function sendUI(data)
  guihooks.trigger("careerThief_update", data)
end

local function vecDot(a, b)
  return a.x*b.x + a.y*b.y + a.z*b.z
end

local function vecLen(v)
  return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
end

local function vecSub(a, b)
  return { x=a.x-b.x, y=a.y-b.y, z=a.z-b.z }
end

-- Produit vectoriel (retourne un table {x,y,z})
local function vecCross(a, b)
  return {
    x = a.y*b.z - a.z*b.y,
    y = a.z*b.x - a.x*b.z,
    z = a.x*b.y - a.y*b.x,
  }
end

-- ── Découverte de l'API native career_modules_partInventory ──────────────────
local function discoverPartInventoryAPI()
  state.apiHealthy   = false
  state.apiFunctions = {}

  if not career_modules_partInventory then
    logError("career_modules_partInventory introuvable. Cette API n'existe que si un mode carrière BeamNG 0.32+ est actif.")
    logError("Vérifie que tu es bien dans une partie CARRIÈRE et non en mode libre/scenario.")
    return false
  end

  for k, v in pairs(career_modules_partInventory) do
    if type(v) == "function" then
      table.insert(state.apiFunctions, k)
    end
  end
  table.sort(state.apiFunctions)

  state.apiHealthy = true
  logInfo("API career_modules_partInventory détectée - fonctions exposées :")
  logInfo("  " .. table.concat(state.apiFunctions, ", "))
  return true
end

-- ── Découverte de l'API police (native BeamNG, étendue par RLS) ──────────────
-- Diagnostic au démarrage. Non bloquant : si absent, alertPolice() fera un log et
-- se contentera d'afficher l'état wanted dans le HUD.
local function discoverPoliceAPI()
  local essentials = { "setPursuitMode", "setupPursuitGameplay", "setPursuitVars", "getPursuitData" }
  if not gameplay_police then
    logWarn("gameplay_police introuvable - la police ne pourra pas être alertée par le système natif.")
    return false
  end

  local missing = {}
  for _, fn in ipairs(essentials) do
    if type(gameplay_police[fn]) ~= "function" then
      table.insert(missing, fn)
    end
  end

  if #missing > 0 then
    logWarn("gameplay_police présent mais il manque : " .. table.concat(missing, ", "))
  else
    logInfo("API gameplay_police OK (setPursuitMode, setupPursuitGameplay, setPursuitVars, getPursuitData).")
  end

  if not gameplay_traffic or type(gameplay_traffic.getTrafficData) ~= "function" then
    logWarn("gameplay_traffic.getTrafficData introuvable - impossible d'inscrire le joueur comme suspect.")
    return false
  end
  logInfo("API gameplay_traffic OK (getTrafficData disponible).")
  return #missing == 0
end

-- ── Raycast depuis la caméra du jeu ──────────────────────────────────────────
-- Retourne { vehId, hitPos, dist } ou nil si rien de valable n'est touché.
local function raycastCamera()
  if not core_camera then
    logWarn("core_camera introuvable - raycast impossible.")
    return nil
  end

  local camPos = core_camera.getPosition()
  local camFwd = core_camera.getForward()
  if not camPos or not camFwd then
    logWarn("core_camera.getPosition()/getForward() a retourné nil - raycast annulé.")
    return nil
  end

  -- Normaliser la direction (safety)
  local fLen = vecLen(camFwd)
  if fLen < 0.0001 then
    logWarn("Direction caméra dégénérée (longueur nulle).")
    return nil
  end
  camFwd = { x=camFwd.x/fLen, y=camFwd.y/fLen, z=camFwd.z/fLen }

  local playerVeh = be:getPlayerVehicle(0)
  local playerId  = playerVeh and playerVeh:getID() or -1

  local bestId, bestT, bestVc = nil, cfg.maxDistance, nil
  local vehNames = scenetree.findClassObjects("BeamNGVehicle") or {}

  if #vehNames == 0 then
    -- Pas de warn : scène sans véhicules, c'est normal au spawn
    return nil
  end

  for _, name in ipairs(vehNames) do
    local obj = scenetree.findObject(name)
    if obj and obj:getID() ~= playerId then
      local ok, vc = pcall(function() return obj:getPosition() end)
      if ok and vc then
        local d = vecSub(vc, camPos)
        local tProj = vecDot(d, camFwd)
        if tProj > 0.5 and tProj < cfg.maxDistance then
          local rayPt = { x=camPos.x+tProj*camFwd.x, y=camPos.y+tProj*camFwd.y, z=camPos.z+tProj*camFwd.z }
          local perp  = vecLen(vecSub(vc, rayPt))
          if perp < cfg.vehicleHitRadius and tProj < bestT then
            bestT  = tProj
            bestId = obj:getID()
            bestVc = vc
          end
        end
      end
    end
  end

  if not bestId then return nil end

  local hitPos = { x=camPos.x+bestT*camFwd.x, y=camPos.y+bestT*camFwd.y, z=camPos.z+bestT*camFwd.z }
  return { vehId=bestId, hitPos=hitPos, dist=bestT }
end

-- ── Conversion d'un hit world → zone locale du véhicule → pièce catalogue ───
local function pickPartFromHit(vehId, hitPos)
  local veh = be:getObjectByID(vehId)
  if not veh then
    logWarn("pickPartFromHit: véhicule id=" .. tostring(vehId) .. " introuvable.")
    return nil
  end

  local okPos, vPos = pcall(function() return veh:getPosition() end)
  local okFwd, vFwd = pcall(function() return veh:getDirectionVector() end)
  local okUp,  vUp  = pcall(function() return veh:getDirectionVectorUp() end)
  if not (okPos and vPos and okFwd and vFwd and okUp and vUp) then
    logWarn("pickPartFromHit: impossible de récupérer pos/orientation du véhicule " .. tostring(vehId))
    return nil
  end

  -- Axes locaux : fwd = +X local, up = +Z local, right = fwd × up
  local vRight = vecCross(vFwd, vUp)

  -- Dimensions approximatives (demi-extents) — BeamNG expose plusieurs méthodes :
  local halfLen, halfWid, halfHgt = 2.3, 1.0, 0.8 -- defaults raisonnables pour une berline
  local okBB, bb = pcall(function() return veh:getSpawnWorldOOBB() end)
  if okBB and bb then
    local okHe, he = pcall(function() return bb:getHalfExtents() end)
    if okHe and he then
      halfLen = math.max(he.x, 0.5)
      halfWid = math.max(he.y, 0.5)
      halfHgt = math.max(he.z, 0.3)
    end
  else
    logInfo("OOBB indisponible pour le véhicule " .. tostring(vehId) .. ", utilisation de dimensions par défaut.")
  end

  -- Vecteur hit - centre véhicule, projeté sur les axes locaux
  local rel  = vecSub(hitPos, vPos)
  local xLoc = vecDot(rel, vFwd)   / halfLen  -- avant/arrière
  local yLoc = vecDot(rel, vRight) / halfWid  -- gauche/droite
  local zLoc = vecDot(rel, vUp)    / halfHgt  -- bas/haut

  local lon  = (xLoc >  0.33) and "F" or ((xLoc < -0.33) and "R" or "M")
  local side = (yLoc >  0.33) and "R" or ((yLoc < -0.33) and "L" or "C")
  local vert = (zLoc >  0.33) and "H" or ((zLoc < -0.33) and "L" or "M")

  logInfo(string.format("Hit projeté : lon=%s side=%s vert=%s (xLoc=%.2f yLoc=%.2f zLoc=%.2f)",
    lon, side, vert, xLoc, yLoc, zLoc))

  -- Recherche d'une pièce catalogue correspondant à cette zone
  local stolen = state.stolenParts[vehId] or {}
  for _, p in ipairs(PARTS) do
    if p.zone.lon == lon and p.zone.side == side and p.zone.vert == vert then
      if stolen[p.id] then
        return { part=p, alreadyStolen=true }
      end
      return { part=p, alreadyStolen=false }
    end
  end

  logInfo(string.format("Aucune pièce du catalogue ne correspond à la zone (lon=%s side=%s vert=%s). Visez une autre partie.",
    lon, side, vert))
  return nil
end

-- ── Alerte police ─────────────────────────────────────────────────────────────
-- Utilise l'API police NATIVE de BeamNG (gameplay_police + gameplay_traffic),
-- qui est aussi celle que RLS Career Overhaul surcharge et étend.
-- Référence : https://github.com/RLS-Modding/rls_career_overhaul
--   - lua/ge/extensions/overrides/gameplay/police.lua (setPursuitMode, setupPursuitGameplay, setPursuitVars)
--   - lua/ge/extensions/overrides/gameplay/traffic/vehicle.lua (triggerOffense, pursuit.addScore)
--   - lua/ge/extensions/career/modules/enforcement.lua (hook onPursuitAction)
--
-- Stratégie (dans l'ordre) :
--   1. S'assurer que le véhicule joueur est dans gameplay_traffic.
--   2. Enregistrer une infraction « partTheft » via triggerOffense (idiomatique) →
--      déclenche la poursuite automatiquement si le score dépasse les scoreLevels.
--   3. Forcer gameplay_police.setPursuitMode(2, playerVehId) en secours direct.
--   4. Aligner la durée d'évasion sur cfg.wantedDuration via setPursuitVars.
--   5. Fallback legacy pour les versions qui exposent encore career_modules_lawEnforcement.
local function alertPolice()
  state.wanted      = true
  state.wantedTimer = cfg.wantedDuration

  local playerVehId = be and be:getPlayerVehicleID(0)
  local alerted = false

  if playerVehId and playerVehId >= 0 and gameplay_police and gameplay_traffic then
    -- Aligner le temps d'évasion du système de poursuite natif sur notre wantedDuration
    if gameplay_police.setPursuitVars then
      pcall(gameplay_police.setPursuitVars, { evadeTime = cfg.wantedDuration })
    end

    -- S'assurer que le joueur est inscrit dans la traffic data, requis pour qu'une
    -- poursuite puisse être tracée sur lui. gameplay_police.setupPursuitGameplay
    -- le fait proprement (équivalent à gameplay_traffic.insertTraffic + setRole('suspect')).
    local trafficData = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
    if not trafficData[playerVehId] and gameplay_police.setupPursuitGameplay then
      local okSetup, errSetup = pcall(gameplay_police.setupPursuitGameplay, playerVehId, nil, {
        pursuitMode      = 2,
        preventAutoStart = true,
      })
      if okSetup then
        logInfo("setupPursuitGameplay OK pour véhicule joueur " .. tostring(playerVehId))
        trafficData = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
      else
        logWarn("setupPursuitGameplay a échoué : " .. tostring(errSetup))
      end
    end

    -- Voie idiomatique RLS : enregistrer une infraction sur le traffic vehicle.
    -- triggerOffense ajoute 'partTheft' à pursuit.offensesList et bump pursuit.addScore,
    -- ce qui est traité ensuite par gameplay_police.onUpdate (déclenchement automatique
    -- du mode de poursuite selon scoreLevels = {100, 500, 2000}).
    local trafficVeh = trafficData[playerVehId]
    if trafficVeh and type(trafficVeh.triggerOffense) == "function" then
      local okOff = pcall(function()
        trafficVeh:triggerOffense({ key = "partTheft", value = "vehiclePart", score = 600 })
      end)
      if okOff then
        logInfo("Infraction 'partTheft' enregistrée sur pursuit (score +600).")
        alerted = true
      else
        logWarn("triggerOffense('partTheft') a échoué.")
      end
    elseif trafficVeh and trafficVeh.pursuit then
      -- Plan B : pousser directement addScore (même effet sans le tag d'infraction)
      trafficVeh.pursuit.addScore = (trafficVeh.pursuit.addScore or 0) + 600
      logInfo("pursuit.addScore bumpé de +600 (triggerOffense indisponible).")
    end

    -- Coup de grâce : forcer le mode de poursuite actif immédiatement (mode 2 = poursuite).
    -- Ça garantit que la police démarre tout de suite, sans attendre le prochain tick de
    -- gameplay_police.onUpdate ou l'accumulation de score.
    if gameplay_police.setPursuitMode then
      local okMode, errMode = pcall(gameplay_police.setPursuitMode, 2, playerVehId)
      if okMode then
        alerted = true
        logInfo("gameplay_police.setPursuitMode(2, " .. tostring(playerVehId) .. ") - poursuite active.")
      else
        logWarn("gameplay_police.setPursuitMode a échoué : " .. tostring(errMode))
      end
    end

    -- Notifier aussi via le hook, pour que enforcement.lua (RLS) puisse réagir s'il
    -- est chargé. RLS écoute onPursuitAction('start'|'reset'|'evade'|'arrest').
    -- NB: 'start' est normalement déclenché par setPursuitMode lui-même, donc on ne
    -- le rejoue pas ici pour éviter un double-traitement.
  end

  -- Fallback pour les versions anciennes qui exposaient encore career_modules_lawEnforcement
  -- (n'existe plus dans les BeamNG récents ni dans RLS Career Overhaul >= 2.6).
  if not alerted and career_modules_lawEnforcement then
    if career_modules_lawEnforcement.setWantedLevel then
      pcall(career_modules_lawEnforcement.setWantedLevel, 3)
      alerted = true
      logInfo("Fallback legacy : setWantedLevel(3).")
    elseif career_modules_lawEnforcement.onCrime then
      pcall(career_modules_lawEnforcement.onCrime, { type = "vehicleTheft", severity = 3 })
      alerted = true
      logInfo("Fallback legacy : onCrime(vehicleTheft).")
    end
  end

  if not alerted then
    logWarn("Aucune API police disponible (gameplay_police / gameplay_traffic / career_modules_lawEnforcement) - état wanted affiché en HUD uniquement.")
  end

  sendUI({ type = "wantedStart", duration = cfg.wantedDuration })
end

-- ── Détachement visuel sur le véhicule cible via partmgmt VLUA ───────────────
local function detachPartVisually(vehId, slot)
  if not vehId or not slot then return false end
  local veh = be:getObjectByID(vehId)
  if not veh then
    logWarn("detachPartVisually: véhicule " .. tostring(vehId) .. " introuvable.")
    return false
  end

  local cmd = string.format([[
    local ok, err = pcall(function()
      if partmgmt and partmgmt.getConfig then
        local cfg = partmgmt.getConfig()
        if cfg and cfg.parts and cfg.parts[%q] then
          cfg.parts[%q] = ""
          if partmgmt.setPartsConfig then
            partmgmt.setPartsConfig(cfg)
          end
        end
      end
      if beamstate and beamstate.breakAllBreakGroups_withoutExtraSounds then
        beamstate.breakAllBreakGroups_withoutExtraSounds()
      end
    end)
    if not ok then obj:queueGameEngineLua("print('[CareerThief][WARN]  VLUA detach echoue: '..tostring(%q))") end
  ]], slot, slot, "err")
  veh:queueLuaCommand(cmd)
  logInfo("Commande de détachement VLUA envoyée pour slot=" .. slot .. " sur véhicule " .. tostring(vehId))
  return true
end

-- ── Ajout à l'inventaire natif My Parts via cascade pcall ───────────────────
-- Essaie plusieurs signatures connues/probables. Loggue ce qui marche.
-- Retourne true si une signature a réussi, false sinon.
local function addToMyParts(part, sourceVehId)
  local api = career_modules_partInventory
  if not api then
    logError("career_modules_partInventory indisponible au moment du vol. Impossible d'ajouter la pièce à My Parts.")
    sendUI({ type="inventoryUnavailable", reason="no_api" })
    return false
  end

  local tried = {}
  local function tryFn(fnName, ...)
    table.insert(tried, fnName)
    if type(api[fnName]) ~= "function" then return false end
    local ok, err = pcall(api[fnName], ...)
    if ok then
      logInfo("Pièce ajoutée à My Parts via " .. fnName .. "()")
      return true
    end
    logWarn("Appel " .. fnName .. "() a levé une erreur : " .. tostring(err))
    return false
  end

  -- Ordre du plus idéal (déplacement atomique) au plus basique.
  if tryFn("movePartFromVehicleToInventory", sourceVehId, part.slot) then return true end
  if tryFn("movePartToInventory",            sourceVehId, part.slot) then return true end
  if tryFn("addPartFromVehicle",             sourceVehId, part.slot) then return true end
  if tryFn("addPart", part.slot, { name=part.name, value=part.value, condition=1.0 }) then return true end
  if tryFn("addPart", { slot=part.slot, name=part.name, value=part.value }) then return true end
  if tryFn("addInventoryPart", { slot=part.slot, name=part.name, value=part.value }) then return true end
  if tryFn("addItemToInventory", { slot=part.slot, name=part.name, value=part.value }) then return true end

  logError("Aucune signature d'ajout connue n'a réussi.")
  logError("  Signatures tentées : " .. table.concat(tried, ", "))
  logError("  Fonctions réellement exposées par l'API : " .. table.concat(state.apiFunctions, ", "))
  logError("  → Ajoute manuellement la fonction gagnante dans addToMyParts() (thief.lua).")
  sendUI({ type="inventoryUnavailable", reason="no_signature" })
  return false
end

-- ── Calcul de la position du curseur QTE (onde triangulaire) ─────────────────
local function computeCursorPos(elapsed)
  local period = 1.0 / cfg.qteCursorSpeed
  local t = (elapsed % period) / period
  if t < 0.5 then
    return t * 2.0
  else
    return (1.0 - t) * 2.0
  end
end

-- ── Recherche de la cible (vehicule + pièce vue) ─────────────────────────────
local function findTargetAndPart()
  local hit = raycastCamera()
  if not hit then return nil end

  local res = pickPartFromHit(hit.vehId, hit.hitPos)
  if not res then return nil end

  return {
    vehId         = hit.vehId,
    hitPos        = hit.hitPos,
    part          = res.part,
    alreadyStolen = res.alreadyStolen,
  }
end

-- ── Logique principale : touche de vol ───────────────────────────────────────
function M.onTheftKeyPressed()
  if not state.active then
    logWarn("Touche pressée mais module inactif (hors mode carrière).")
    return
  end

  -- Cas 1 : QTE en cours → évaluer
  if state.qteRunning then
    local pos     = state.qteCursorPos
    local half    = cfg.qteSuccessZone / 2.0
    local success = (pos >= 0.5 - half) and (pos <= 0.5 + half)

    state.qteRunning = false
    alertPolice()

    if success and state.targetVehId and state.targetPart then
      local vehId = state.targetVehId
      local part  = state.targetPart

      -- Transférer dans My Parts (inventaire natif)
      local added = addToMyParts(part, vehId)

      if added then
        -- Marquer la pièce comme volée sur ce véhicule (évite le re-vol)
        state.stolenParts[vehId] = state.stolenParts[vehId] or {}
        state.stolenParts[vehId][part.id] = true

        -- Détachement visuel (best-effort, indépendant de l'inventaire)
        detachPartVisually(vehId, part.slot)

        state.cooldown = cfg.cooldownAfterSteal
        sendUI({ type="qteSuccess", partName=part.name, value=part.value, cursorPos=pos })
        logInfo(string.format("SUCCÈS - %s ajoutée à My Parts (valeur indicative %d, curseur=%.2f)", part.name, part.value, pos))
      else
        -- API down : on compte comme un échec, police déjà alertée
        state.cooldown = cfg.cooldownAfterFail
        sendUI({ type="qteFail", cursorPos=pos, reason="inventory_failed" })
        logWarn("QTE réussi mais l'ajout à My Parts a échoué → vol annulé (police quand même alertée).")
      end
    else
      state.cooldown = cfg.cooldownAfterFail
      sendUI({ type="qteFail", cursorPos=pos })
      logWarn(string.format("QTE ÉCHEC - curseur=%.3f hors zone [%.3f..%.3f]. Police alertée.",
        pos, 0.5-half, 0.5+half))
    end

    state.targetPart = nil
    return
  end

  -- Cas 2 : cooldown actif
  if state.cooldown > 0 then
    sendUI({ type="onCooldown", remaining=state.cooldown })
    logInfo(string.format("Cooldown actif : %.1fs restantes.", state.cooldown))
    return
  end

  -- Cas 3 : acquisition cible via raycast caméra
  local tgt = findTargetAndPart()
  if not tgt then
    sendUI({ type="noTarget" })
    logInfo("Aucune pièce volable visée. Raycast sans résultat exploitable.")
    return
  end

  if tgt.alreadyStolen then
    sendUI({ type="alreadyStolen", partName=tgt.part.name })
    logInfo(string.format("Pièce %s déjà volée sur ce véhicule.", tgt.part.name))
    return
  end

  -- Cas 4 : vérifier que l'inventaire natif est dispo avant de lancer le QTE
  if not state.apiHealthy then
    -- Re-tentative de découverte (mode carrière peut-être chargé tardivement)
    discoverPartInventoryAPI()
  end
  if not career_modules_partInventory then
    sendUI({ type="inventoryUnavailable", reason="no_api" })
    logError("Impossible de démarrer le QTE : career_modules_partInventory toujours absent.")
    return
  end

  -- Cas 5 : démarrage du QTE
  state.targetVehId  = tgt.vehId
  state.targetHitPos = tgt.hitPos
  state.targetPart   = tgt.part
  state.qteRunning   = true
  state.qteElapsed   = 0.0
  state.qteCursorPos = 0.0

  sendUI({
    type        = "qteStart",
    partName    = tgt.part.name,
    value       = tgt.part.value,
    duration    = cfg.qteDuration,
    successZone = cfg.qteSuccessZone,
  })
  logInfo(string.format("QTE démarré - veh=%s, pièce=%s, slot=%s, durée=%.1fs, zone=%.2f",
    tostring(tgt.vehId), tgt.part.name, tgt.part.slot, cfg.qteDuration, cfg.qteSuccessZone))
end

-- ── Boucle principale ─────────────────────────────────────────────────────────
function M.onUpdate(dtReal, dtSim, dtRaw)
  if not state.active then return end

  -- Timers
  if state.cooldown > 0 then
    state.cooldown = math.max(0.0, state.cooldown - dtReal)
  end
  if state.wantedTimer > 0 then
    state.wantedTimer = math.max(0.0, state.wantedTimer - dtReal)
    if state.wantedTimer <= 0.0 then
      state.wanted = false
      sendUI({ type="wantedEnd" })
      logInfo("Fin de l'état recherché.")
    end
  end

  -- QTE en cours : mise à jour curseur + timeout
  if state.qteRunning then
    state.qteElapsed   = state.qteElapsed + dtReal
    state.qteCursorPos = computeCursorPos(state.qteElapsed)

    if state.qteElapsed >= cfg.qteDuration then
      state.qteRunning = false
      state.cooldown   = cfg.cooldownAfterFail
      alertPolice()
      sendUI({ type="qteTimeout" })
      logWarn(string.format("QTE TIMEOUT après %.1fs. Police alertée.", cfg.qteDuration))
      return
    end
    sendUI({ type="qteTick", pos=state.qteCursorPos })
    return
  end

  -- Mise à jour périodique de la cible (pour le HUD live)
  state.targetTimer = state.targetTimer + dtReal
  if state.targetTimer < (1.0 / cfg.targetUpdateHz) then return end
  state.targetTimer = 0.0

  local tgt = findTargetAndPart()
  if tgt then
    sendUI({
      type          = "targetFound",
      partName      = tgt.part.name,
      value         = tgt.part.value,
      alreadyStolen = tgt.alreadyStolen,
      onCooldown    = state.cooldown > 0,
      cooldown      = state.cooldown,
      wanted        = state.wanted,
      wantedTime    = state.wantedTimer,
    })
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

  logInfo("===== Career Thief : activation mode carrière =====")
  discoverPartInventoryAPI()
  discoverPoliceAPI()
  sendUI({ type="moduleReady", apiHealthy=state.apiHealthy })
end

function M.onCareerDeactivated()
  state.active     = false
  state.qteRunning = false
  sendUI({ type="hide" })
  logInfo("Module désactivé (mode carrière terminé).")
end

-- Alias pour compatibilité multi-versions
M.onCareerActive          = M.onCareerModulesActivated
M.onCareerModuleActivated = M.onCareerModulesActivated

-- ── Initialisation de l'extension ─────────────────────────────────────────────
local function init()
  math.randomseed(os.time())
  logInfo("Extension Career Thief chargée - en attente du mode carrière.")
end

init()

return M
