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
-- slot     = mot-clé principal recherché (tolérant : underscores, casse, position).
-- slotAlts = mots-clés alternatifs essayés si le principal ne matche rien.
local PARTS = {
  -- AVANT (lon=F)
  { id="hood",       name="Capot moteur",       value=230, slot="hood",
    slotAlts={"bonnet"}, zone={lon="F", side="C", vert="H"} },
  { id="bumperF",    name="Pare-chocs avant",   value=145, slot="bumper_F",
    slotAlts={"bumperF","frontbumper","bumper_front"}, zone={lon="F", side="C", vert="L"} },
  { id="headlightL", name="Phare gauche",       value=95,  slot="headlight_L",
    slotAlts={"headlightL","light_L"}, zone={lon="F", side="L", vert="M"} },
  { id="headlightR", name="Phare droit",        value=95,  slot="headlight_R",
    slotAlts={"headlightR","light_R"}, zone={lon="F", side="R", vert="M"} },
  { id="fenderFL",   name="Aile avant gauche",  value=100, slot="fender_L",
    slotAlts={"fenderL","wing_L"}, zone={lon="F", side="L", vert="H"} },
  { id="fenderFR",   name="Aile avant droite",  value=100, slot="fender_R",
    slotAlts={"fenderR","wing_R"}, zone={lon="F", side="R", vert="H"} },
  -- Pour les roues, on utilise 2 tokens (wheel + FL) qui matchent toutes les
  -- variantes BeamNG : wheel_F_L, wheel_FL, wheelhub_FL, etc. Sur les véhicules
  -- simplifiés (simple_traffic), les slots L/R n'existent pas, on tombe sur
  -- wheels_F/wheels_R (une seule pièce par essieu) via les slotAlts.
  { id="wheel_fl",   name="Roue avant gauche",  value=185, slot="wheel FL",
    slotAlts={"wheel F L","tire FL","tire F L","wheels_F","wheels F"},
    zone={lon="F", side="L", vert="L"} },
  { id="wheel_fr",   name="Roue avant droite",  value=185, slot="wheel FR",
    slotAlts={"wheel F R","tire FR","tire F R","wheels_F","wheels F"},
    zone={lon="F", side="R", vert="L"} },

  -- MILIEU (lon=M)
  -- Rétroviseurs : sur simple_traffic il n'y a qu'une seule pièce 'mirrors'
  -- pour les deux côtés, d'où le fallback.
  { id="mirrorL",    name="Rétroviseur gauche", value=50,  slot="mirror_L",
    slotAlts={"mirrorL","mirrors"}, zone={lon="M", side="L", vert="H"} },
  { id="mirrorR",    name="Rétroviseur droit",  value=50,  slot="mirror_R",
    slotAlts={"mirrorR","mirrors"}, zone={lon="M", side="R", vert="H"} },
  { id="sideL",      name="Bas de caisse gauche", value=75,slot="skirt_L",
    slotAlts={"skirtL","rocker_L"}, zone={lon="M", side="L", vert="L"} },
  { id="sideR",      name="Bas de caisse droit",  value=75,slot="skirt_R",
    slotAlts={"skirtR","rocker_R"}, zone={lon="M", side="R", vert="L"} },
  { id="doorL",      name="Portière gauche",    value=140, slot="door_L",
    slotAlts={"doorL","door_FL"}, zone={lon="M", side="L", vert="M"} },
  { id="doorR",      name="Portière droite",    value=140, slot="door_R",
    slotAlts={"doorR","door_FR"}, zone={lon="M", side="R", vert="M"} },
  { id="antenna",    name="Antenne",            value=35,  slot="antenna",
    slotAlts={"aerial"}, zone={lon="M", side="C", vert="H"} },

  -- ARRIÈRE (lon=R)
  { id="trunk",      name="Coffre / Hayon",     value=200, slot="tailgate",
    slotAlts={"trunk","boot","hatch"}, zone={lon="R", side="C", vert="H"} },
  { id="bumperR",    name="Pare-chocs arrière", value=115, slot="bumper_R",
    slotAlts={"bumperR","rearbumper","bumper_rear"}, zone={lon="R", side="C", vert="L"} },
  { id="exhaust",    name="Silencieux",         value=90,  slot="exhaust",
    slotAlts={"muffler","tailpipe"}, zone={lon="R", side="C", vert="M"} },
  { id="wheel_rl",   name="Roue arrière gauche",value=165, slot="wheel RL",
    slotAlts={"wheel R L","tire RL","tire R L","wheels_R","wheels R"},
    zone={lon="R", side="L", vert="L"} },
  { id="wheel_rr",   name="Roue arrière droite",value=165, slot="wheel RR",
    slotAlts={"wheel R R","tire RR","tire R R","wheels_R","wheels R"},
    zone={lon="R", side="R", vert="L"} },
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

-- Récupère le "vrai" centre géométrique du véhicule et ses demi-extents.
-- vPos (obj:getPosition()) correspond à l'origine du jbeam, souvent décalée
-- par rapport au centre de la carrosserie. On préfère le centre de l'OOBB
-- qui lui est géométriquement centré sur la carrosserie.
local function getVehicleGeometry(obj)
  local okPos, vPos = pcall(function() return obj:getPosition() end)
  local okFwd, vFwd = pcall(function() return obj:getDirectionVector() end)
  local okUp,  vUp  = pcall(function() return obj:getDirectionVectorUp() end)
  if not (okPos and vPos and okFwd and vFwd and okUp and vUp) then return nil end

  local vRight = vecCross(vFwd, vUp)
  local halfLen, halfWid, halfHgt = 2.3, 1.0, 0.8
  local center = vPos  -- fallback : position brute du véhicule

  local okBB, bb = pcall(function() return obj:getSpawnWorldOOBB() end)
  if okBB and bb then
    local okHe, he = pcall(function() return bb:getHalfExtents() end)
    if okHe and he then
      halfLen = math.max(he.x, 0.5)
      halfWid = math.max(he.y, 0.5)
      halfHgt = math.max(he.z, 0.3)
    end
    -- Le centre de l'OBB corrige le décalage origine-jbeam -> centre carrosserie
    local okCtr, ctr = pcall(function() return bb:getCenter() end)
    if okCtr and ctr then
      center = { x=ctr.x, y=ctr.y, z=ctr.z }
    end
  end

  return {
    center   = center,
    fwd      = vFwd,
    up       = vUp,
    right    = vRight,
    halfLen  = halfLen,
    halfWid  = halfWid,
    halfHgt  = halfHgt,
  }
end

-- ── Raycast depuis la caméra du jeu ──────────────────────────────────────────
-- Test rayon-OBB : on projette le rayon caméra dans le repère local du
-- véhicule (où l'OBB devient une AABB alignée) puis on fait un slab test.
-- C'est beaucoup plus précis que l'ancien test sphérique, qui englobait des
-- points bien au-dessous/à côté du véhicule.
local function rayOBBIntersect(camPos, camFwd, vPos, vFwd, vRight, vUp, halfExtents, maxT)
  -- Origine du rayon en local véhicule
  local rel = vecSub(camPos, vPos)
  local ro = {
    x = vecDot(rel, vFwd),
    y = vecDot(rel, vRight),
    z = vecDot(rel, vUp),
  }
  -- Direction du rayon en local véhicule
  local rd = {
    x = vecDot(camFwd, vFwd),
    y = vecDot(camFwd, vRight),
    z = vecDot(camFwd, vUp),
  }
  local h = { x=halfExtents.x, y=halfExtents.y, z=halfExtents.z }

  local tMin, tMax = -math.huge, math.huge
  for _, axis in ipairs({"x","y","z"}) do
    local o, dir, half = ro[axis], rd[axis], h[axis]
    if math.abs(dir) < 1e-6 then
      -- rayon parallèle à cet axe : le point d'origine doit être dans la tranche
      if o < -half or o > half then return nil end
    else
      local t1 = (-half - o) / dir
      local t2 = ( half - o) / dir
      if t1 > t2 then t1, t2 = t2, t1 end
      if t1 > tMin then tMin = t1 end
      if t2 < tMax then tMax = t2 end
      if tMin > tMax then return nil end
    end
  end
  -- tMin = première entrée dans la boîte, tMax = sortie
  if tMax < 0.5 then return nil end            -- intégralement derrière la caméra
  local tHit = math.max(tMin, 0.5)              -- si cam déjà dans la boîte, prend 0.5 mini
  if tHit > maxT then return nil end
  return tHit
end

-- Variante du rayOBB : la boîte peut avoir un centre offset local (pour
-- remonter la base de la voiture au-dessus du sol et éviter les faux positifs
-- quand on regarde par terre).
local function rayOBBIntersectOffset(camPos, camFwd, vPos, vFwd, vRight, vUp, center, halfExtents, maxT)
  -- Centre effectif = vPos + offset_local (exprimé en repère véhicule)
  local worldCenter = {
    x = vPos.x + center.x*vFwd.x + center.y*vRight.x + center.z*vUp.x,
    y = vPos.y + center.x*vFwd.y + center.y*vRight.y + center.z*vUp.y,
    z = vPos.z + center.x*vFwd.z + center.y*vRight.z + center.z*vUp.z,
  }
  return rayOBBIntersect(camPos, camFwd, worldCenter, vFwd, vRight, vUp, halfExtents, maxT)
end

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

  local fLen = vecLen(camFwd)
  if fLen < 0.0001 then
    logWarn("Direction caméra dégénérée (longueur nulle).")
    return nil
  end
  camFwd = { x=camFwd.x/fLen, y=camFwd.y/fLen, z=camFwd.z/fLen }

  local playerVeh = be:getPlayerVehicle(0)
  local playerId  = playerVeh and playerVeh:getID() or -1

  local bestId, bestT = nil, cfg.maxDistance
  local vehNames = scenetree.findClassObjects("BeamNGVehicle") or {}
  if #vehNames == 0 then return nil end

  for _, name in ipairs(vehNames) do
    local obj = scenetree.findObject(name)
    if obj and obj:getID() ~= playerId then
      local g = getVehicleGeometry(obj)
      if g then
        local d = vecSub(g.center, camPos)
        local tProj = vecDot(d, camFwd)
        if tProj > -2.0 and tProj < cfg.maxDistance + 4.0 then
          -- On rétrécit la boîte par le bas pour ignorer le dessous du
          -- véhicule (regarder par terre sous la voiture ne doit pas compter).
          local bottomCut = math.min(0.35, g.halfHgt * 0.40)
          local halfHgtClip = g.halfHgt - bottomCut
          -- Centre effectif remonté de bottomCut/2 pour que la boîte clippée
          -- soit centrée sur la moitié haute du véhicule.
          local centerOffset = { x = 0, y = 0, z = bottomCut }
          local half = {
            x = g.halfLen + 0.05,
            y = g.halfWid + 0.10,
            z = halfHgtClip + 0.10,
          }
          local tHit = rayOBBIntersectOffset(camPos, camFwd, g.center, g.fwd, g.right, g.up, centerOffset, half, cfg.maxDistance)
          if tHit and tHit < bestT then
            bestT  = tHit
            bestId = obj:getID()
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

  local g = getVehicleGeometry(veh)
  if not g then
    logWarn("pickPartFromHit: impossible de récupérer la géométrie du véhicule " .. tostring(vehId))
    return nil
  end

  -- Vecteur hit - centre géométrique du véhicule (centre OBB), projeté sur les
  -- axes locaux. Utiliser getCenter() plutôt que getPosition() corrige le
  -- décalage origine-jbeam qui faisait que le capot était classé en "milieu".
  local rel  = vecSub(hitPos, g.center)
  local xLoc = vecDot(rel, g.fwd)   / g.halfLen  -- avant/arrière (-1..+1)
  local yLoc = vecDot(rel, g.right) / g.halfWid  -- gauche/droite
  local zLoc = vecDot(rel, g.up)    / g.halfHgt  -- bas/haut

  -- Rejet des hits clairement sous la voiture : faux positifs du sol qui
  -- pourraient traverser la légère marge verticale de l'OBB.
  if zLoc < -0.85 then
    logInfo(string.format("Hit rejete : sous la voiture (zLoc=%.2f)", zLoc))
    return nil
  end

  local lon  = (xLoc >  0.33) and "F" or ((xLoc < -0.33) and "R" or "M")
  local side = (yLoc >  0.33) and "R" or ((yLoc < -0.33) and "L" or "C")
  local vert = (zLoc >  0.33) and "H" or ((zLoc < -0.33) and "L" or "M")

  logInfo(string.format("Hit projete : lon=%s side=%s vert=%s (xLoc=%.2f yLoc=%.2f zLoc=%.2f)",
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

-- ── Détachement visuel via beamstate.breakBreakGroup (VLUA) ──────────────────
-- Les pièces du JBeam sont retenues par des "beams" groupés via breakGroup.
-- Casser ces beams fait tomber physiquement la pièce de la voiture.
-- On essaie plusieurs noms candidats car la convention varie selon le véhicule
-- (ex: "hood", "bonnet", "hood_L", "simple_traffic_fullsize_hood_break").
local function detachPartVisually(vehId, catalogPart)
  if not vehId or not catalogPart then return false end
  local veh = be:getObjectByID(vehId)
  if not veh then
    logWarn("detachPartVisually: vehicule " .. tostring(vehId) .. " introuvable.")
    return false
  end

  -- Construit la liste de candidats : slot principal + slotAlts + variantes
  -- communes (lowercase, sans underscores, avec _break).
  local candidates = { catalogPart.slot }
  if catalogPart.slotAlts then
    for _, alt in ipairs(catalogPart.slotAlts) do table.insert(candidates, alt) end
  end
  -- Dédoublonnage + variantes
  local seen, final = {}, {}
  for _, c in ipairs(candidates) do
    for _, variant in ipairs({ c, c:lower(), c:lower():gsub("[_%s]", ""), c .. "_break", c:lower() .. "_break" }) do
      if not seen[variant] then
        seen[variant] = true
        table.insert(final, variant)
      end
    end
  end

  -- On sérialise la liste dans la commande VLUA
  local listStr = "{"
  for _, n in ipairs(final) do listStr = listStr .. string.format("%q,", n) end
  listStr = listStr .. "}"

  local cmd = string.format([[
    local ok, err = pcall(function()
      local names = %s
      if not beamstate then return end
      local broken = 0
      for _, name in ipairs(names) do
        if beamstate.breakBreakGroup then
          local pre = beamstate.beamstate and beamstate.beamstate.brokenBeams or 0
          beamstate.breakBreakGroup(name)
          broken = broken + 1
        end
      end
      obj:queueGameEngineLua(string.format(
        "print('[CareerThief][INFO]  VLUA detach: %%d breakGroups tentes sur veh %d')",
        broken))
    end)
    if not ok then
      obj:queueGameEngineLua("print('[CareerThief][WARN]  VLUA detach echoue: '..tostring('" .. tostring(err) .. "'))")
    end
  ]], listStr, vehId)

  veh:queueLuaCommand(cmd)
  logInfo(string.format("Commande de detachement envoyee : %d candidats sur vehicule %d",
    #final, vehId))
  return true
end

-- ── Construction d'une pièce valide pour career_modules_partInventory ────────
-- La fonction native addPartToInventory(part) attend un objet part complet tel que
-- produit par addPartFromTree() dans partInventory.lua (BeamNG 0.32+) :
--   { name, value, description, partCondition, tags, vehicleModel,
--     location, containingSlot, partPath, mainPart }
--
-- Comme on vole sur un véhicule de TRAFFIC (pas dans career_modules_inventory),
-- on doit reconstruire cet objet à la main en lisant la partsTree du véhicule
-- cible via core_vehicle_manager.getVehicleData(vehObjId).
--
-- catalogPart.slot est un mot-clé de zone (hood, fender_L, door_R, wheel_FL,
-- bumper_F, ...) qu'on mappe à un nœud réel de la partsTree en matchant le
-- path ou le chosenPartName.
-- Normalise une chaîne pour comparaison tolérante (casse, underscores, tirets).
local function normalizeSlotStr(s)
  if not s then return "" end
  return s:lower():gsub("[_%-%s]", "")
end

-- Découpe un mot-clé catalog en tokens (ex: "wheel_FL" -> {"wheel","fl"}).
local function tokenizeSlotKeyword(keyword)
  local tokens = {}
  for tok in keyword:gmatch("[%w]+") do
    if #tok > 0 then table.insert(tokens, tok:lower()) end
  end
  return tokens
end

-- Collecte tous les nœuds ayant un chosenPartName dans la partsTree.
local function collectAllPartNodes(tree)
  local nodes = {}
  local function walk(node)
    if not node then return end
    if node.chosenPartName and node.chosenPartName ~= "" then
      table.insert(nodes, node)
    end
    if node.children then
      for _, child in pairs(node.children) do walk(child) end
    end
  end
  walk(tree)
  return nodes
end

-- Dump lisible des nœuds pour aider au debug quand un slot est introuvable.
local function dumpPartsTree(tree, maxLines)
  local nodes = collectAllPartNodes(tree)
  local lines = {}
  for i, n in ipairs(nodes) do
    if i > (maxLines or 80) then
      table.insert(lines, "  ... (" .. (#nodes - i) .. " autres)")
      break
    end
    table.insert(lines, string.format("  [%d] path='%s' chosenPartName='%s'",
      i, tostring(n.path), tostring(n.chosenPartName)))
  end
  return table.concat(lines, "\n")
end

-- Cherche un nœud correspondant à un slot catalogue, avec matching tolérant :
--   1. tous les tokens du keyword doivent apparaître dans path ou chosenPartName
--   2. comparaison casse-insensible, sans underscores/tirets
--   3. en cas d'égalité, préférence au match sur path le plus court
local function findNodeForCatalogSlot(tree, slotKeyword)
  if not tree or not slotKeyword then return nil end

  local tokens = tokenizeSlotKeyword(slotKeyword)
  if #tokens == 0 then return nil end

  local nodes = collectAllPartNodes(tree)
  local bestNode, bestScore = nil, -1

  for _, node in ipairs(nodes) do
    local normPath = normalizeSlotStr(node.path)
    local normPart = normalizeSlotStr(node.chosenPartName)
    local haystack = normPath .. "|" .. normPart

    local allMatch = true
    local score = 0
    for _, tok in ipairs(tokens) do
      local tokNorm = normalizeSlotStr(tok)
      if not haystack:find(tokNorm, 1, true) then
        allMatch = false
        break
      end
      -- bonus si le token apparaît dans le chosenPartName (plus spécifique)
      if normPart:find(tokNorm, 1, true) then score = score + 2 end
      if normPath:find(tokNorm, 1, true) then score = score + 1 end
    end

    if allMatch then
      -- pénalité selon la longueur totale (plus court = plus spécifique)
      score = score - math.floor(#haystack / 50)
      if score > bestScore then
        bestScore = score
        bestNode = node
      end
    end
  end

  return bestNode
end

local function buildPartObject(vehObj, catalogPart)
  if not vehObj then return nil, "vehObj nil" end

  local okData, vehicleData = pcall(function()
    return extensions.core_vehicle_manager.getVehicleData(vehObj:getID())
  end)
  if not okData or not vehicleData then
    return nil, "getVehicleData KO"
  end

  local partsTree = vehicleData.config and vehicleData.config.partsTree
  if not partsTree then
    return nil, "partsTree absent"
  end

  -- On essaie d'abord le slot principal, puis les alternatives (slotAlts).
  local candidates = { catalogPart.slot }
  if catalogPart.slotAlts then
    for _, alt in ipairs(catalogPart.slotAlts) do table.insert(candidates, alt) end
  end

  local node
  for _, kw in ipairs(candidates) do
    node = findNodeForCatalogSlot(partsTree, kw)
    if node then
      logInfo(string.format("Slot catalogue '%s' -> noeud path='%s' part='%s'",
        tostring(kw), tostring(node.path), tostring(node.chosenPartName)))
      break
    end
  end

  if not node then
    logError(string.format("Aucun mot-cle du catalogue n'a matche la partsTree (essaye: %s).",
      table.concat(candidates, ", ")))
    logError("Dump des noeuds disponibles (path / chosenPartName) :")
    print(dumpPartsTree(partsTree, 120))
    return nil, "slot '" .. tostring(catalogPart.slot) .. "' introuvable dans partsTree"
  end

  -- Description JBeam : optionnelle, on la récupère si jbeamIO est dispo
  local description = "Pièce volée (" .. catalogPart.name .. ")"
  local okJbeam, jbeamIO = pcall(require, "jbeam/io")
  if okJbeam and jbeamIO and vehicleData.ioCtx then
    local availableParts = jbeamIO.getAvailableParts(vehicleData.ioCtx)
    if availableParts and availableParts[node.chosenPartName] then
      description = availableParts[node.chosenPartName]
    end
  end

  local jbeamFile
  pcall(function() jbeamFile = vehObj:getJBeamFilename() end)

  -- partCondition minimaliste : pièce en parfait état (on vient de la voler donc neuf)
  local partCondition = {
    integrityValue = 1.0,
    visualValue    = 1.0,
    odometer       = 0,
  }

  local containingSlot = node.path or "/"
  local part = {
    name           = node.chosenPartName,
    value          = catalogPart.value or 100,
    description    = description,
    partCondition  = partCondition,
    tags           = { "stolen", "careerThief" },
    vehicleModel   = jbeamFile or "unknown",
    location       = 0, -- 0 = stockée dans l'inventaire (pas installée sur un véhicule)
    containingSlot = containingSlot,
    partPath       = containingSlot .. node.chosenPartName,
    mainPart       = (containingSlot == "/"),
  }

  return part
end

-- ── Ajout à l'inventaire natif My Parts ──────────────────────────────────────
-- Signatures réellement exposées par BeamNG 0.32+ (vérifiées via le dump F10) :
--   addPartToInventory(part)    -- insère une pièce dans l'inventaire
--   generateAndGetPartsFromVehicle(inventoryId) -- pour véhicules du joueur seulement
--   getInventory()              -- renvoie toute la table
-- On construit l'objet part manuellement puis on appelle addPartToInventory.
-- Fallback sur les anciennes signatures au cas où l'API évoluerait.
local function addToMyParts(catalogPart, sourceVehId)
  local api = career_modules_partInventory
  if not api then
    logError("career_modules_partInventory indisponible au moment du vol.")
    sendUI({ type = "inventoryUnavailable", reason = "no_api" })
    return false
  end

  -- Voie principale : addPartToInventory(part) avec part construit depuis la partsTree
  if type(api.addPartToInventory) == "function" then
    local vehObj = be:getObjectByID(sourceVehId)
    local part, buildErr = buildPartObject(vehObj, catalogPart)
    if part then
      local ok, err = pcall(api.addPartToInventory, part)
      if ok then
        logInfo(string.format("Pièce ajoutée via addPartToInventory(part) : name=%s slot=%s value=%d",
          part.name, part.containingSlot, part.value))
        return true
      end
      logWarn("addPartToInventory a levé une erreur : " .. tostring(err))
    else
      logWarn("Construction de l'objet part impossible : " .. tostring(buildErr))
      logWarn("  → On tente quand même les signatures legacy ci-dessous.")
    end
  end

  -- Cascade legacy (versions antérieures ou forks)
  local tried = { "addPartToInventory(part construit)" }
  local function tryFn(fnName, ...)
    table.insert(tried, fnName)
    if type(api[fnName]) ~= "function" then return false end
    local ok, err = pcall(api[fnName], ...)
    if ok then
      logInfo("Pièce ajoutée à My Parts via " .. fnName .. "() (legacy)")
      return true
    end
    logWarn("Appel legacy " .. fnName .. "() a levé une erreur : " .. tostring(err))
    return false
  end

  if tryFn("movePartFromVehicleToInventory", sourceVehId, catalogPart.slot) then return true end
  if tryFn("movePartToInventory",            sourceVehId, catalogPart.slot) then return true end
  if tryFn("addPartFromVehicle",             sourceVehId, catalogPart.slot) then return true end
  if tryFn("addPart", catalogPart.slot, { name = catalogPart.name, value = catalogPart.value, condition = 1.0 }) then return true end
  if tryFn("addInventoryPart", { slot = catalogPart.slot, name = catalogPart.name, value = catalogPart.value }) then return true end
  if tryFn("addItemToInventory", { slot = catalogPart.slot, name = catalogPart.name, value = catalogPart.value }) then return true end

  logError("Aucune méthode d'ajout n'a réussi.")
  logError("  Tentées : " .. table.concat(tried, ", "))
  logError("  Exposées par l'API : " .. table.concat(state.apiFunctions, ", "))
  logError("  → Vérifie la structure de buildPartObject() dans thief.lua")
  sendUI({ type = "inventoryUnavailable", reason = "no_signature" })
  return false
end

-- ── Vérifie qu'une pièce catalogue existe réellement sur un véhicule donné ──
-- Retourne (found:boolean, nodeInfo:string|nil). Ne construit pas l'objet part,
-- se contente de chercher un nœud qui match le slot ou un des slotAlts.
local function canStealFromVehicle(vehObj, catalogPart)
  if not vehObj or not catalogPart then return false end
  local okData, vehicleData = pcall(function()
    return extensions.core_vehicle_manager.getVehicleData(vehObj:getID())
  end)
  if not okData or not vehicleData then return false end
  local partsTree = vehicleData.config and vehicleData.config.partsTree
  if not partsTree then return false end

  local candidates = { catalogPart.slot }
  if catalogPart.slotAlts then
    for _, alt in ipairs(catalogPart.slotAlts) do table.insert(candidates, alt) end
  end
  for _, kw in ipairs(candidates) do
    local node = findNodeForCatalogSlot(partsTree, kw)
    if node then
      return true, string.format("path='%s' part='%s'", tostring(node.path), tostring(node.chosenPartName))
    end
  end
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
  -- Règle : la police n'est alertée QUE sur échec (curseur hors zone ou
  -- timeout). Un vol réussi reste discret, même si l'ajout à l'inventaire
  -- échoue techniquement (bug API, pas faute du joueur).
  if state.qteRunning then
    local pos     = state.qteCursorPos
    local half    = cfg.qteSuccessZone / 2.0
    local success = (pos >= 0.5 - half) and (pos <= 0.5 + half)

    state.qteRunning = false

    if success and state.targetVehId and state.targetPart then
      local vehId = state.targetVehId
      local part  = state.targetPart

      -- Transférer dans My Parts (inventaire natif)
      local added = addToMyParts(part, vehId)

      if added then
        -- Marquer la pièce comme volée sur ce véhicule (évite le re-vol)
        state.stolenParts[vehId] = state.stolenParts[vehId] or {}
        state.stolenParts[vehId][part.id] = true

        -- Détachement visuel (best-effort, indépendant de l'inventaire) :
        -- casse les breakGroups JBeam correspondants → la pièce tombe.
        detachPartVisually(vehId, part)

        state.cooldown = cfg.cooldownAfterSteal
        sendUI({ type="qteSuccess", partName=part.name, value=part.value, cursorPos=pos })
        logInfo(string.format("SUCCES discret - %s ajoutee a My Parts (valeur indicative %d, curseur=%.2f)", part.name, part.value, pos))
      else
        -- Bug technique (API inventaire) : on n'alerte pas la police, ce n'est
        -- pas la faute du joueur. Simple cooldown d'échec.
        state.cooldown = cfg.cooldownAfterFail
        sendUI({ type="qteFail", cursorPos=pos, reason="inventory_failed" })
        logWarn("QTE reussi mais ajout a My Parts echoue (probleme API) -> vol annule, police NON alertee.")
      end
    else
      -- Échec du curseur : la police est alertée.
      state.cooldown = cfg.cooldownAfterFail
      alertPolice()
      sendUI({ type="qteFail", cursorPos=pos })
      logWarn(string.format("QTE ECHEC - curseur=%.3f hors zone [%.3f..%.3f]. Police alertee.",
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

  -- Cas 4bis : précheck que la pièce existe vraiment sur ce véhicule.
  -- Sans ça, le joueur peut réussir le QTE pour rien (ex: antenne sur simple_traffic)
  -- et se faire prendre en flag par la police alors que le vol est impossible.
  local targetVehObj = be:getObjectByID(tgt.vehId)
  local existsOnVeh, nodeInfo = canStealFromVehicle(targetVehObj, tgt.part)
  if not existsOnVeh then
    sendUI({
      type     = "alreadyStolen",   -- réutilise le canal feedback jaune
      partName = tgt.part.name .. " (absente sur ce vehicule)",
    })
    logWarn(string.format("Piece '%s' (slot='%s') absente sur ce vehicule, QTE annule.",
      tgt.part.name, tgt.part.slot))
    return
  else
    logInfo(string.format("Precheck OK - piece '%s' trouvee : %s", tgt.part.name, nodeInfo or ""))
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
local function doActivate(reason)
  state.active      = true
  state.qteRunning  = false
  state.cooldown    = 0.0
  state.wantedTimer = 0.0
  state.wanted      = false
  state.targetTimer = 0.0

  print("[CareerThief][INFO]  ===== Activation mode carriere (" .. tostring(reason) .. ") =====")
  discoverPartInventoryAPI()
  discoverPoliceAPI()
  sendUI({ type="moduleReady", apiHealthy=state.apiHealthy })
end

function M.onCareerModulesActivated()
  doActivate("onCareerModulesActivated")
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

-- Détection "active" : au chargement (ou reload Lua), on vérifie si la carrière
-- tourne déjà (le hook onCareerModulesActivated n'est pas réémis dans ce cas).
local function detectCareerActive()
  local ok, career = pcall(function() return career_career end)
  if not ok or not career then return false end
  if type(career.isActive) == "function" then
    local ok2, active = pcall(career.isActive)
    if ok2 and active then return true end
  end
  if career.tutorialStage ~= nil or career.saveSlot ~= nil then
    return true
  end
  return false
end

function M.onExtensionLoaded()
  if detectCareerActive() and not state.active then
    doActivate("onExtensionLoaded + carriere deja active")
  end
end

-- Commande console de dépannage : jouable depuis F10 via `career_modules_thief.forceActivate()`
function M.forceActivate()
  doActivate("forceActivate (console)")
  return "Career Thief active."
end

-- ── Initialisation de l'extension ─────────────────────────────────────────────
local function init()
  math.randomseed(os.time())
  logInfo("Extension Career Thief chargée - en attente du mode carrière.")
end

init()

return M
