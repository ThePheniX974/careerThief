local M = {}
local PROGRESSION_SAVE_FILE = "careerThief_progression.json"
local CUSTOM_DROPOFFS_FILE = "careerThief_dropoffs.json"
local customDropoffs = {}

local cfg = {
  targeting = {
    maxDistance = 11.0,
    maxCamAngleDeg = 22.0,
    vehicleHitRadius = 2.8
  },
  theft = {
    cooldownAfterSteal = 10.0,
    cooldownAfterFailOrCancel = 300.0,
    wantedDuration = 150.0,
    maxTrackedVehicleDistance = 65.0,
    baseSuccessChance = 0.55
  },
  dropoff = {
    minIntegrity = 0.45,
    maxDropoffSpeed = 6.0,
    locations = {
      {
        id = "docks",
        name = "Docks",
        pos = { x = -413.9, y = -115.2, z = 5.4 },
        radius = 22.0
      }
    }
  },
  marketplace = {
    priceMultiplierMin = 0.82,
    priceMultiplierMax = 1.18,
    offerMinDelay = 30.0,
    offerMaxDelay = 65.0,
    offerMinFactor = 0.68,
    offerMaxFactor = 1.08
  },
  progression = {
    maxLevel = 10,
    xpRewards = {
      theftSuccess = 25,
      dropoffComplete = 40,
      saleComplete = 65
    },
    levelThresholds = { 100, 240, 420, 640, 900, 1220, 1600, 2050, 2575, 3200 },
    levelBonuses = {
      ["0"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.0, instantStealChance = 0.0, policeAvoidOnFail = 0.0 },
      ["1"] = { priceFinalBonus = 0.10, theftSuccessBonus = 0.0, instantStealChance = 0.0, policeAvoidOnFail = 0.0 },
      ["2"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.05, instantStealChance = 0.0, policeAvoidOnFail = 0.0 },
      ["3"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.0, instantStealChance = 0.02, policeAvoidOnFail = 0.0 },
      ["4"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.0, instantStealChance = 0.02, policeAvoidOnFail = 0.0 },
      ["5"] = { priceFinalBonus = 0.05, theftSuccessBonus = 0.0, instantStealChance = 0.0, policeAvoidOnFail = 0.0 },
      ["6"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.03, instantStealChance = 0.02, policeAvoidOnFail = 0.0 },
      ["7"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.0, instantStealChance = 0.02, policeAvoidOnFail = 0.0 },
      ["8"] = { priceFinalBonus = 0.06, theftSuccessBonus = 0.0, instantStealChance = 0.0, policeAvoidOnFail = 0.0 },
      ["9"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.04, instantStealChance = 0.02, policeAvoidOnFail = 0.0 },
      ["10"] = { priceFinalBonus = 0.0, theftSuccessBonus = 0.0, instantStealChance = 0.02, policeAvoidOnFail = 0.25 }
    }
  },
  debug = {
    debugMode = false
  }
}

-- ── Logger explicite ──────────────────────────────────────────────────────────
-- Tous les messages commencent par [CareerThief] pour filtrage facile dans F10.
local function logInfo(msg)
  if cfg.debug.debugMode then
    print("[CareerThief][INFO]  " .. tostring(msg))
  end
end

local function logWarn(msg)
  print("[CareerThief][WARN]  " .. tostring(msg))
end

local function logError(msg)
  print("[CareerThief][ERROR] " .. tostring(msg))
end

-- Logger flow principal (touche, QTE, mission). Toujours visible.
local function logFlow(tag, msg)
  print("[CareerThief][" .. tostring(tag) .. "] " .. tostring(msg))
end

-- ── État interne ──────────────────────────────────────────────────────────────
local state = {
  active = false,
  cooldown = 0.0,
  wanted = false,
  wantedTimer = 0.0,
  uiTick = 0.0,
  mission = nil,
  qte = nil,  -- { active, vehId, vehicleName, duration, elapsed, cursorPos, direction, speed, targetMin, targetMax }
  nav = {
    hasRoute = false,
    method = nil,
    retryTimer = 0.0
  },
  market = {
    listing = nil,
    lastOffer = nil
  },
  soldVehicleIds = {},
  pendingSoldDespawn = nil,
  progression = {
    level = 0,
    xp = 0,
    nextLevelXp = 100,
    bonuses = {
      priceFinalBonus = 0.0,
      theftSuccessBonus = 0.0,
      instantStealChance = 0.0,
      policeAvoidOnFail = 0.0
    }
  }
}

-- ── Utilitaires mathématiques ─────────────────────────────────────────────────
local function sendUI(data)
  guihooks.trigger("careerThief_update", data)
end

local function toVec3(pos)
  if not pos then return nil end
  if vec3 then
    return vec3(pos.x, pos.y, pos.z)
  end
  return { x = pos.x, y = pos.y, z = pos.z }
end

local function setDropoffNavigation(dropoff)
  if not dropoff or not dropoff.pos then return false end
  local p = dropoff.pos
  -- Version fiable: on garde strictement les coords du dropoff configuré.
  -- Pas de getTerrainHeight (retours incohérents sur certaines versions).
  local navPos = { x = p.x, y = p.y, z = (p.z or 0) + 1.0 }

  local payload = {
    -- Certaines versions lisent x/y/z, d'autres payload.pos
    x = navPos.x, y = navPos.y, z = navPos.z,
    pos = { x = navPos.x, y = navPos.y, z = navPos.z },
    radius = dropoff.radius or 20,
    name = dropoff.name or "Dropoff"
  }

  local okAny = false
  local methods = {}

  local function callNav(label, fn)
    local ok, err = pcall(fn)
    logFlow("NAV", string.format("%s ok=%s err=%s", label, tostring(ok), tostring(err)))
    if ok then
      okAny = true
      methods[#methods + 1] = label
    end
  end

  -- UI hooks (certains builds écoutent SetWaypoint, d'autres SetRoute)
  callNav("guihooks.SetWaypoint", function()
    guihooks.trigger("SetWaypoint", payload)
  end)
  callNav("guihooks.SetRoute", function()
    guihooks.trigger("SetRoute", payload)
  end)

  -- APIs freeroam (quand disponibles)
  if freeroam_bigMapMode and type(freeroam_bigMapMode.setOnlyTarget) == "function" then
    callNav("freeroam_bigMapMode.setOnlyTarget(vec3)", function()
      freeroam_bigMapMode.setOnlyTarget(toVec3(navPos))
    end)
    callNav("freeroam_bigMapMode.setOnlyTarget(table)", function()
      freeroam_bigMapMode.setOnlyTarget({ x = navPos.x, y = navPos.y, z = navPos.z })
    end)
    callNav("freeroam_bigMapMode.setOnlyTarget(xyz)", function()
      freeroam_bigMapMode.setOnlyTarget(navPos.x, navPos.y, navPos.z)
    end)
  end
  if freeroam_bigMapMode and type(freeroam_bigMapMode.setNavFocus) == "function" then
    callNav("freeroam_bigMapMode.setNavFocus", function()
      freeroam_bigMapMode.setNavFocus(toVec3(navPos))
    end)
  end
  if freeroam_bigMapMode and type(freeroam_bigMapMode.navigateTo) == "function" then
    callNav("freeroam_bigMapMode.navigateTo", function()
      freeroam_bigMapMode.navigateTo(toVec3(navPos))
    end)
  end

  state.nav.hasRoute = okAny
  state.nav.method = table.concat(methods, ", ")
  logFlow("NAV", string.format(
    "dropoff='%s' raw=(%.1f, %.1f, %.1f) nav=(%.1f, %.1f, %.1f) methods=[%s]",
    tostring(dropoff.name or "Dropoff"),
    p.x, p.y, p.z or 0,
    navPos.x, navPos.y, navPos.z,
    state.nav.method
  ))

  return okAny
end

local function clearDropoffNavigation()
  state.nav.hasRoute = false
  state.nav.method = nil
  state.nav.retryTimer = 0.0
  -- Nettoyage best-effort sur APIs possibles.
  pcall(function()
    if freeroam_bigMapMode and type(freeroam_bigMapMode.clearRoute) == "function" then
      freeroam_bigMapMode.clearRoute()
    end
  end)
  pcall(function()
    guihooks.trigger("ClearWaypoint")
  end)
  pcall(function()
    guihooks.trigger("ClearRoute")
  end)
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

local function vecCross(a, b)
  return {
    x = a.y*b.z - a.z*b.y,
    y = a.z*b.x - a.x*b.z,
    z = a.x*b.y - a.y*b.x,
  }
end

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

local function rayOBBIntersectOffset(camPos, camFwd, vPos, vFwd, vRight, vUp, center, halfExtents, maxT)
  -- Centre effectif = vPos + offset_local (exprimé en repère véhicule)
  local worldCenter = {
    x = vPos.x + center.x*vFwd.x + center.y*vRight.x + center.z*vUp.x,
    y = vPos.y + center.x*vFwd.y + center.y*vRight.y + center.z*vUp.y,
    z = vPos.z + center.x*vFwd.z + center.y*vRight.z + center.z*vUp.z,
  }
  return rayOBBIntersect(camPos, camFwd, worldCenter, vFwd, vRight, vUp, halfExtents, maxT)
end

local function raycastVehicleFromCamera()
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

  local bestId, bestT = nil, cfg.targeting.maxDistance
  local vehNames = scenetree.findClassObjects("BeamNGVehicle") or {}
  if #vehNames == 0 then return nil end

  for _, name in ipairs(vehNames) do
    local obj = scenetree.findObject(name)
    if obj and obj:getID() ~= playerId then
      local g = getVehicleGeometry(obj)
      if g then
        local d = vecSub(g.center, camPos)
        local tProj = vecDot(d, camFwd)
        if tProj > -2.0 and tProj < cfg.targeting.maxDistance + 4.0 then
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
          local tHit = rayOBBIntersectOffset(camPos, camFwd, g.center, g.fwd, g.right, g.up, centerOffset, half, cfg.targeting.maxDistance)
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

local function getVehicleDisplayName(vehObj)
  if not vehObj then return "Vehicule inconnu" end
  local okName, jbeam = pcall(function() return vehObj:getJBeamFilename() end)
  if okName and jbeam and jbeam ~= "" then
    return tostring(jbeam):gsub("%.jbeam", "")
  end
  return "Vehicule " .. tostring(vehObj:getID())
end

local function alertPolice(pursuitKind)
  -- pursuitKind:
  --   "success" -> vol reussi, poursuite legere (1-2 unites)
  --   "fail"    -> vol rate, poursuite lourde (3-6 unites)
  pursuitKind = pursuitKind or "success"
  local minUnits = pursuitKind == "fail" and 3 or 1
  local maxUnits = pursuitKind == "fail" and 6 or 2
  local wantedUnits = math.random(minUnits, maxUnits)
  local offenseScore = pursuitKind == "fail" and (1200 + wantedUnits * 260) or (420 + wantedUnits * 140)

  state.wanted      = true
  state.wantedTimer = cfg.theft.wantedDuration

  local playerVehId = be and be:getPlayerVehicleID(0)
  local alerted = false

  if playerVehId and playerVehId >= 0 and gameplay_police and gameplay_traffic then
    -- Aligner le temps d'évasion du système de poursuite natif sur notre wantedDuration
    if gameplay_police.setPursuitVars then
      pcall(gameplay_police.setPursuitVars, {
        evadeTime = cfg.theft.wantedDuration,
        desiredPoliceUnits = wantedUnits
      })
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
        trafficVeh:triggerOffense({ key = "vehicleTheft", value = "stolenVehicle", score = offenseScore })
      end)
      if okOff then
        logInfo("Infraction 'vehicleTheft' enregistree sur pursuit (score +" .. tostring(offenseScore) .. ").")
        alerted = true
      else
        logWarn("triggerOffense('partTheft') a échoué.")
      end
    elseif trafficVeh and trafficVeh.pursuit then
      -- Plan B : pousser directement addScore (même effet sans le tag d'infraction)
      trafficVeh.pursuit.addScore = (trafficVeh.pursuit.addScore or 0) + offenseScore
      logInfo("pursuit.addScore bumpe de +" .. tostring(offenseScore) .. " (triggerOffense indisponible).")
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

  sendUI({
    type = "wantedStart",
    duration = cfg.theft.wantedDuration,
    policeUnits = wantedUnits,
    pursuitKind = pursuitKind
  })
  return wantedUnits
end

local function getVehicleIntegrity(vehObj)
  if not vehObj then return 0.0 end
  local okDamage, damage = pcall(function() return vehObj:getDamage() end)
  if okDamage and damage then
    local normalized = math.min(1.0, math.max(0.0, damage / 3000.0))
    return 1.0 - normalized
  end
  return 0.8
end

local function estimateVehicleValue(vehObj, integrity)
  local base = 14000
  local okMass, mass = pcall(function() return vehObj:getInitialNodeMass() end)
  if okMass and mass and mass > 0 then
    base = base + (mass * 3.8)
  end
  local randomFactor = math.random(88, 112) / 100
  return math.floor(base * math.max(0.35, integrity) * randomFactor)
end

local function getClosestDropoff(pos)
  local best = nil
  local bestDist = math.huge
  for _, d in ipairs(cfg.dropoff.locations) do
    local delta = vecSub(pos, d.pos)
    local dist = vecLen(delta)
    if dist < bestDist then
      bestDist = dist
      best = d
    end
  end
  return best, bestDist
end

local function scheduleNextOffer(listing)
  listing.nextOfferTimer = math.random(
    math.floor(cfg.marketplace.offerMinDelay * 1000),
    math.floor(cfg.marketplace.offerMaxDelay * 1000)
  ) / 1000
end

local function randomRange(minValue, maxValue)
  return minValue + (maxValue - minValue) * math.random()
end

local function getBonusForLevel(level)
  local key = tostring(level)
  return cfg.progression.levelBonuses[key] or { priceFinalBonus = 0.0, theftSuccessBonus = 0.0, instantStealChance = 0.0, policeAvoidOnFail = 0.0 }
end

local function recomputeCumulativeBonuses(level)
  local b = { priceFinalBonus = 0.0, theftSuccessBonus = 0.0, instantStealChance = 0.0, policeAvoidOnFail = 0.0 }
  local maxLevel = math.min(level, cfg.progression.maxLevel)
  for i = 0, maxLevel do
    local lb = getBonusForLevel(i)
    b.priceFinalBonus = b.priceFinalBonus + (lb.priceFinalBonus or 0.0)
    b.theftSuccessBonus = b.theftSuccessBonus + (lb.theftSuccessBonus or 0.0)
    b.instantStealChance = b.instantStealChance + (lb.instantStealChance or 0.0)
    b.policeAvoidOnFail = b.policeAvoidOnFail + (lb.policeAvoidOnFail or 0.0)
  end
  return b
end

local function clamp01(v)
  return math.max(0.0, math.min(1.0, v or 0.0))
end

local function getNextLevelXp(level)
  local idx = level + 1
  if idx <= cfg.progression.maxLevel then
    return cfg.progression.levelThresholds[idx] or cfg.progression.levelThresholds[#cfg.progression.levelThresholds]
  end
  return cfg.progression.levelThresholds[#cfg.progression.levelThresholds]
end

local function recomputeProgression(emitFeedback)
  if emitFeedback == nil then emitFeedback = true end
  local level = 0
  for idx, threshold in ipairs(cfg.progression.levelThresholds) do
    if state.progression.xp >= threshold then
      level = idx
    else
      break
    end
  end
  level = math.min(level, cfg.progression.maxLevel)
  local levelChanged = level ~= state.progression.level
  state.progression.level = level
  state.progression.nextLevelXp = getNextLevelXp(level)
  state.progression.bonuses = recomputeCumulativeBonuses(level)
  if emitFeedback and levelChanged then
    sendUI({
      type = "feedback",
      level = "success",
      message = "Niveau BlackMarket " .. tostring(level),
      sub = "Nouveaux avantages debloques"
    })
  end
end

local function saveProgression()
  local payload = {
    xp = math.max(0, math.floor(state.progression.xp or 0)),
    savedAt = os.time()
  }
  local ok, err = pcall(function()
    -- NOTE: certaines builds BeamNG n'aiment pas le 3e argument "pretty".
    jsonWriteFile(PROGRESSION_SAVE_FILE, payload)
  end)
  if not ok then
    logWarn("Sauvegarde progression impossible: " .. tostring(err))
  end
end

local function loadProgression()
  local ok, data = pcall(function()
    return jsonReadFile(PROGRESSION_SAVE_FILE)
  end)
  if not ok or type(data) ~= "table" then
    return false
  end
  local xp = math.max(0, math.floor(tonumber(data.xp) or 0))
  state.progression.xp = xp
  recomputeProgression(false)
  logFlow("PROGRESSION", "Chargee depuis fichier: xp=" .. tostring(xp) .. " level=" .. tostring(state.progression.level))
  return true
end

local function addCustomDropoffToConfig(d)
  if type(d) ~= "table" or type(d.pos) ~= "table" then return false end
  d.id = tostring(d.id or ("drop_" .. tostring(os.time())))
  d.name = tostring(d.name or "Dropoff")
  d.radius = tonumber(d.radius) or 22.0
  local pos = {
    x = tonumber(d.pos.x),
    y = tonumber(d.pos.y),
    z = tonumber(d.pos.z)
  }
  if not (pos.x and pos.y and pos.z) then return false end

  for _, existing in ipairs(cfg.dropoff.locations or {}) do
    if existing.id == d.id then
      return false
    end
  end

  table.insert(cfg.dropoff.locations, {
    id = d.id,
    name = d.name,
    pos = pos,
    radius = d.radius
  })
  return true
end

local function saveCustomDropoffs()
  local payload = { locations = customDropoffs }
  local ok, err = pcall(function()
    -- NOTE: éviter le 3e argument "pretty" (peut déclencher des erreurs
    -- silencieuses/err=nil selon le wrapper console).
    jsonWriteFile(CUSTOM_DROPOFFS_FILE, payload)
  end)
  if not ok then
    logWarn("Sauvegarde des dropoffs custom impossible: " .. tostring(err))
    return false
  end
  return true
end

local function loadCustomDropoffs()
  local ok, data = pcall(function()
    return jsonReadFile(CUSTOM_DROPOFFS_FILE)
  end)
  if not ok or type(data) ~= "table" then
    customDropoffs = {}
    return
  end

  local list = data.locations
  if type(list) ~= "table" then
    customDropoffs = {}
    return
  end

  customDropoffs = {}
  local added = 0
  for _, d in ipairs(list) do
    local copy = {
      id = d.id,
      name = d.name,
      pos = d.pos,
      radius = d.radius
    }
    table.insert(customDropoffs, copy)
    if addCustomDropoffToConfig(copy) then
      added = added + 1
    end
  end
  if added > 0 then
    logFlow("NAV", "Dropoffs custom charges: +" .. tostring(added))
  end
end

local function exportDropoffsToConfigFile()
  local okRead, baseCfg = pcall(function()
    return jsonReadFile("careerThief_config.json")
  end)
  if not okRead or type(baseCfg) ~= "table" then
    return false, "Impossible de lire careerThief_config.json"
  end

  if type(baseCfg.dropoff) ~= "table" then
    baseCfg.dropoff = {}
  end
  baseCfg.dropoff.minIntegrity = baseCfg.dropoff.minIntegrity or cfg.dropoff.minIntegrity
  baseCfg.dropoff.maxDropoffSpeed = baseCfg.dropoff.maxDropoffSpeed or cfg.dropoff.maxDropoffSpeed

  local locations = {}
  for _, d in ipairs(cfg.dropoff.locations or {}) do
    if d and d.pos then
      locations[#locations + 1] = {
        id = tostring(d.id or ("drop_" .. tostring(#locations + 1))),
        name = tostring(d.name or "Dropoff"),
        pos = {
          x = tonumber(d.pos.x) or 0,
          y = tonumber(d.pos.y) or 0,
          z = tonumber(d.pos.z) or 0
        },
        radius = tonumber(d.radius) or 22.0
      }
    end
  end

  baseCfg.dropoff.locations = locations

  local okWrite, errWrite = pcall(function()
    jsonWriteFile("careerThief_config.json", baseCfg)
  end)
  if not okWrite then
    return false, "Ecriture impossible: " .. tostring(errWrite)
  end

  return true, "Export OK (" .. tostring(#locations) .. " dropoff(s))"
end

local function sendProgressionUI()
  sendUI({
    type = "progressionUpdate",
    level = state.progression.level,
    maxLevel = cfg.progression.maxLevel,
    xp = state.progression.xp,
    nextLevelXp = state.progression.nextLevelXp,
    bonuses = state.progression.bonuses
  })
end

local function addXp(amount, reason)
  local gain = math.max(0, math.floor(amount or 0))
  if gain <= 0 then return end
  state.progression.xp = state.progression.xp + gain
  recomputeProgression()
  -- Sync avec la skill native de l'écran Career > Skills (style RLS).
  pcall(function()
    if career_modules_playerAttributes and type(career_modules_playerAttributes.addAttributes) == "function" then
      career_modules_playerAttributes.addAttributes(
        { ["careerSkills-blackmarket"] = gain },
        { tags = { "gameplay", "careerThief", "skills" }, label = "BlackMarket XP" }
      )
      logFlow("SKILL", "addAttributes careerSkills-blackmarket +" .. tostring(gain))
    end
  end)
  -- Fallback explicite: certaines versions acceptent mieux addAttribute().
  pcall(function()
    if career_modules_playerAttributes and type(career_modules_playerAttributes.addAttribute) == "function" then
      career_modules_playerAttributes.addAttribute("careerSkills-blackmarket", gain)
      logFlow("SKILL", "addAttribute careerSkills-blackmarket +" .. tostring(gain))
    end
  end)
  saveProgression()
  sendUI({
    type = "xpGain",
    amount = gain,
    reason = reason or "action"
  })
end

local function creditPlayerMoney(amount, reason)
  local amt = math.max(0, math.floor(amount or 0))
  if amt <= 0 then return false end
  reason = reason or "blackmarketSale"

  local function readMoney()
    local v = nil
    pcall(function()
      if career_modules_playerAttributes and type(career_modules_playerAttributes.getAttributeValue) == "function" then
        v = career_modules_playerAttributes.getAttributeValue("money")
      end
    end)
    if type(v) ~= "number" then
      pcall(function()
        if career_modules_playerAttributes and type(career_modules_playerAttributes.getAttributes) == "function" then
          local t = career_modules_playerAttributes.getAttributes()
          if type(t) == "table" then
            v = t.money
          end
        end
      end)
    end
    return v
  end

  local before = readMoney()

  local candidates = {
    -- Méthode la plus fiable en carrière récente: addAttributes avec méta transaction.
    function()
      if career_modules_playerAttributes and type(career_modules_playerAttributes.addAttributes) == "function" then
        return career_modules_playerAttributes.addAttributes(
          { money = amt },
          { tags = { "gameplay", "careerThief" }, label = "BlackMarket sale" }
        )
      end
    end,
    function()
      if career_modules_playerAttributes and type(career_modules_playerAttributes.addAttribute) == "function" then
        return career_modules_playerAttributes.addAttribute("money", amt)
      end
    end,
    function()
      if career_modules_inventory and type(career_modules_inventory.addMoney) == "function" then
        return career_modules_inventory.addMoney(amt, reason)
      end
    end
  }

  for i, fn in ipairs(candidates) do
    local ok, ret = pcall(fn)
    local after = readMoney()
    if ok and (ret ~= false) then
      logFlow("MONEY", string.format(
        "Credit attempt method#%d ok ret=%s amount=%d moneyBefore=%s moneyAfter=%s",
        i, tostring(ret), amt, tostring(before), tostring(after)
      ))
      if type(before) == "number" and type(after) == "number" and after < before + amt then
        -- la méthode a répondu OK mais l'argent n'a pas bougé comme attendu, on continue.
      else
        return true
      end
    else
      logFlow("MONEY", "Method#" .. tostring(i) .. " failed ok=" .. tostring(ok) .. " ret=" .. tostring(ret))
    end
  end

  -- Dernier filet: commande GE brute équivalente à la console système.
  local rawCmd = string.format(
    "if career_modules_playerAttributes and career_modules_playerAttributes.addAttributes then career_modules_playerAttributes.addAttributes({money=%d}, {tags={'gameplay','careerThief'}, label='BlackMarket sale'}) end",
    amt
  )
  local okRaw = pcall(function() queueGameEngineLua(rawCmd) end)
  local afterRaw = readMoney()
  logFlow("MONEY", string.format(
    "Raw GE credit ok=%s amount=%d moneyBefore=%s moneyAfter=%s",
    tostring(okRaw), amt, tostring(before), tostring(afterRaw)
  ))
  if type(before) == "number" and type(afterRaw) == "number" then
    if afterRaw >= before + amt then
      return true
    end
  end
  logWarn("Aucune methode de credit argent n'a fonctionne.")
  return false
end

local function despawnSoldVehicle(vehId)
  if not vehId then return end
  state.soldVehicleIds[vehId] = true

  local playerVeh = be and be:getPlayerVehicle(0) or nil
  if playerVeh and playerVeh:getID() == vehId then
    -- Évite le retour brutal à un point safe si on supprime la voiture alors
    -- que le joueur est encore dedans.
    state.pendingSoldDespawn = vehId
    logFlow("MISSION", "Despawn differe: joueur encore dans le vehicule vendu (id=" .. tostring(vehId) .. ").")
    return
  end

  pcall(function()
    if gameplay_traffic and type(gameplay_traffic.removeTraffic) == "function" then
      gameplay_traffic.removeTraffic(vehId)
    end
  end)

  local obj = be and be:getObjectByID(vehId) or nil
  if not obj then return end
  local ok = pcall(function() obj:delete() end)
  if not ok then
    pcall(function()
      obj:queueLuaCommand("if obj and obj.delete then obj:delete() end")
    end)
  end
end

local function createListingFromMission(mission)
  local askFactor = randomRange(cfg.marketplace.priceMultiplierMin, cfg.marketplace.priceMultiplierMax)
  local askPrice = math.floor(mission.estimatedValue * askFactor)
  local listing = {
    id = tostring(os.time()) .. "_" .. tostring(math.random(100, 999)),
    vehicleId = mission.vehicleId,
    vehicleName = mission.vehicleName,
    baseValue = mission.estimatedValue,
    askingPrice = askPrice,
    integrity = mission.integrity,
    heatPenalty = mission.heatPenalty,
    status = "listed",
    nextOfferTimer = 0.0
  }
  scheduleNextOffer(listing)
  return listing
end

local function pushMissionUI()
  if not state.mission then
    local nearEligibleTarget = false
    local nearbyName = ""
    local target = raycastVehicleFromCamera()
    if target and target.vehId then
      local okEligible = false
      okEligible = select(1, isVehicleEligible(target.vehId))
      if okEligible then
        nearEligibleTarget = true
        local obj = be:getObjectByID(target.vehId)
        nearbyName = getVehicleDisplayName(obj)
      end
    end

    sendUI({
      type = "idle",
      wanted = state.wanted,
      wantedTime = state.wantedTimer,
      cooldown = state.cooldown,
      hasTarget = nearEligibleTarget,
      targetVehicleName = nearbyName
    })
    return
  end

  sendUI({
    type = "missionUpdate",
    status = state.mission.status,
    vehicleName = state.mission.vehicleName,
    dropoffName = state.mission.dropoff and state.mission.dropoff.name or "",
    distanceToDropoff = state.mission.distanceToDropoff or 0,
    integrity = state.mission.integrity or 1,
    speed = state.mission.speed or 0,
    wanted = state.wanted,
    wantedTime = state.wantedTimer
  })
end

local function isVehicleEligible(targetVehId)
  if not targetVehId then return false, "Aucun vehicule cible" end
  if state.soldVehicleIds[targetVehId] then
    return false, "Vehicule deja vendu"
  end
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then return false, "Vehicule joueur introuvable" end
  if playerVeh:getID() == targetVehId then
    return false, "Tu ne peux pas voler ton vehicule"
  end
  return true, nil
end

local function startTheftMission(targetVehId, opts)
  opts = opts or {}
  logFlow("MISSION", string.format(
    "startTheftMission | vehId=%s | noPolice=%s",
    tostring(targetVehId), tostring(opts.noPolice and true or false)
  ))
  local targetVeh = be:getObjectByID(targetVehId)
  if not targetVeh then
    logFlow("MISSION", "-> vehicule introuvable, abort.")
    sendUI({ type = "feedback", level = "fail", message = "Vehicule introuvable", sub = "" })
    return
  end

  local playerVeh = be:getPlayerVehicle(0)
  local playerPos = playerVeh and playerVeh:getPosition() or nil
  local dropoff = cfg.dropoff.locations[1]
  if playerPos then
    local nearest = getClosestDropoff({ x = playerPos.x, y = playerPos.y, z = playerPos.z })
    if nearest then dropoff = nearest end
  end

  local integrity = getVehicleIntegrity(targetVeh)
  local baseValue = estimateVehicleValue(targetVeh, integrity)
  local heatPenalty = state.wanted and 0.86 or 1.0
  local est = math.floor(baseValue * heatPenalty)

  state.mission = {
    status = "stolen",
    vehicleId = targetVehId,
    vehicleName = getVehicleDisplayName(targetVeh),
    dropoff = dropoff,
    integrity = integrity,
    estimatedValue = est,
    heatPenalty = heatPenalty,
    distanceToDropoff = 0,
    speed = 0
  }
  -- Temporaire: cooldown désactivé entre les vols.
  state.cooldown = 0

  -- Prendre possession du véhicule volé : désactiver l'IA traffic + téléporter
  -- le joueur dans le siège conducteur. Sinon la voiture reste contrôlée par le
  -- système de traffic IA et le joueur ne peut pas la conduire.
  do
    -- 1) Retirer le véhicule du pool de traffic IA
    if gameplay_traffic and type(gameplay_traffic.removeTraffic) == "function" then
      local okRm, errRm = pcall(gameplay_traffic.removeTraffic, targetVehId)
      if okRm then
        logFlow("MISSION", "-> traffic IA retire (gameplay_traffic.removeTraffic OK).")
      else
        logFlow("MISSION", "-> gameplay_traffic.removeTraffic echoue : " .. tostring(errRm))
      end
    else
      logFlow("MISSION", "-> gameplay_traffic.removeTraffic indisponible, skip.")
    end

    -- 2) Désactiver l'AI côté VLUA (mode 'disabled')
    local okAi = pcall(function()
      targetVeh:queueLuaCommand("if ai and ai.setMode then ai.setMode('disabled') end")
    end)
    if okAi then
      logFlow("MISSION", "-> ai.setMode('disabled') envoye au vehicule.")
    end

    -- 3) Téléporter le joueur dans le véhicule volé (siège 0 = conducteur)
    local okEnter, errEnter = pcall(function()
      be:enterVehicle(0, targetVeh)
    end)
    if okEnter then
      logFlow("MISSION", "-> be:enterVehicle OK, joueur transfere dans le vehicule vole.")
    else
      logFlow("MISSION", "-> be:enterVehicle echoue : " .. tostring(errEnter))
    end
  end

  -- Police déclenchée uniquement si pas de flag noPolice (QTE réussi = vol discret).
  if not opts.noPolice then
    local units = alertPolice("success")
    sendUI({
      type = "feedback",
      level = "warn",
      message = "Police alertee",
      sub = tostring(units) .. " voiture(s) en poursuite"
    })
  end

  addXp(cfg.progression.xpRewards.theftSuccess, "vol_reussi")
  sendUI({
    type = "theftStarted",
    vehicleName = state.mission.vehicleName,
    dropoffName = dropoff.name,
    estimatedValue = est
  })
  state.mission.status = "enRouteToDropoff"
  setDropoffNavigation(dropoff)
  state.nav.retryTimer = 0.0
  logFlow("MISSION", string.format(
    "-> mission demarree | veh='%s' | dropoff='%s' | integrity=%.2f | est=%d",
    state.mission.vehicleName, dropoff.name, integrity, est
  ))
  pushMissionUI()
end

local function tryFinalizeDropoff()
  if not state.mission or state.mission.status ~= "enRouteToDropoff" then return end
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then return end
  if playerVeh:getID() ~= state.mission.vehicleId then
    return
  end

  if state.mission.distanceToDropoff > state.mission.dropoff.radius then
    return
  end

  if state.mission.speed > cfg.dropoff.maxDropoffSpeed then
    sendUI({
      type = "feedback",
      level = "warn",
      message = "Ralentis pour livrer",
      sub = "Vitesse max: " .. tostring(cfg.dropoff.maxDropoffSpeed) .. " m/s"
    })
    return
  end

  if state.mission.integrity < cfg.dropoff.minIntegrity then
    sendUI({
      type = "feedback",
      level = "fail",
      message = "Vehicule trop endommage",
      sub = "Integrite minimale: " .. math.floor(cfg.dropoff.minIntegrity * 100) .. "%"
    })
    return
  end

  state.mission.status = "listed"
  clearDropoffNavigation()
  state.market.listing = createListingFromMission(state.mission)
  state.market.lastOffer = nil
  addXp(cfg.progression.xpRewards.dropoffComplete, "dropoff_valide")
  sendUI({
    type = "listingCreated",
    vehicleName = state.market.listing.vehicleName,
    askingPrice = state.market.listing.askingPrice,
    integrity = state.market.listing.integrity
  })
end

local function spawnOffer(listing)
  local factor = randomRange(cfg.marketplace.offerMinFactor, cfg.marketplace.offerMaxFactor)
  local offered = math.floor(listing.askingPrice * factor)
  local offer = {
    offerId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    buyer = "Client " .. tostring(math.random(12, 398)),
    amount = offered,
    askingPrice = listing.askingPrice
  }
  state.market.lastOffer = offer
  sendUI({
    type = "offerUpdate",
    buyer = offer.buyer,
    amount = offer.amount,
    askingPrice = listing.askingPrice
  })
end

local function updateMarketplace(dtReal)
  local listing = state.market.listing
  if not listing or listing.status ~= "listed" then return end
  listing.nextOfferTimer = listing.nextOfferTimer - dtReal
  if listing.nextOfferTimer <= 0 then
    spawnOffer(listing)
    scheduleNextOffer(listing)
  end
end

local function updateMissionState()
  if not state.mission then return end
  if state.mission.status ~= "enRouteToDropoff" then return end

  local playerVeh = be:getPlayerVehicle(0)
  local trackedVeh = be:getObjectByID(state.mission.vehicleId)
  if not playerVeh or not trackedVeh then
    clearDropoffNavigation()
    state.mission = nil
    state.market.listing = nil
    state.market.lastOffer = nil
    sendUI({ type = "feedback", level = "fail", message = "Mission annulee", sub = "Vehicule perdu" })
    return
  end

  local trackedPos = trackedVeh:getPosition()
  local playerPos = playerVeh:getPosition()
  local delta = vecSub({ x = trackedPos.x, y = trackedPos.y, z = trackedPos.z }, { x = playerPos.x, y = playerPos.y, z = playerPos.z })
  local separation = vecLen(delta)
  if separation > cfg.theft.maxTrackedVehicleDistance then
    clearDropoffNavigation()
    state.mission = nil
    state.market.listing = nil
    state.market.lastOffer = nil
    sendUI({ type = "feedback", level = "fail", message = "Mission echouee", sub = "Vehicule trop eloigne" })
    return
  end

  local dropPos = state.mission.dropoff.pos
  local dropDelta = vecSub({ x = trackedPos.x, y = trackedPos.y, z = trackedPos.z }, dropPos)
  state.mission.distanceToDropoff = vecLen(dropDelta)
  local vel = trackedVeh:getVelocity()
  state.mission.speed = vecLen({ x = vel.x, y = vel.y, z = vel.z })
  state.mission.integrity = getVehicleIntegrity(trackedVeh)
  tryFinalizeDropoff()
end

local function clearGameplayState()
  state.cooldown = 0
  state.wanted = false
  state.wantedTimer = 0
  clearDropoffNavigation()
  state.mission = nil
  state.qte = nil
  state.market.listing = nil
  state.market.lastOffer = nil
  state.soldVehicleIds = {}
  state.pendingSoldDespawn = nil
end

local function applyFailOrCancelCooldown(reasonLabel)
  -- Temporaire: cooldown désactivé entre les vols.
  state.cooldown = 0
  sendUI({
    type = "feedback",
    level = "warn",
    message = "Pas de cooldown (temporaire)",
    sub = tostring(reasonLabel or "echec")
  })
end

-- ── QTE (Quick Time Event) ────────────────────────────────────────────────────
-- Barre horizontale avec un curseur qui fait l'aller-retour. Le joueur doit
-- ré-appuyer K quand le curseur est dans la zone cible (verte). Succès → vol
-- discret, aucune police. Échec ou timeout → police + cooldown.

local function getQTEConfig()
  -- Plus le niveau BlackMarket est élevé, plus la zone cible est large et le
  -- curseur lent, pour récompenser la progression.
  local lvl = state.progression.level or 0
  local lvlRatio = math.min(1.0, lvl / math.max(1, cfg.progression.maxLevel))

  local baseZoneWidth = 0.22                 -- 22% de la barre au niveau 0
  local zoneWidth     = baseZoneWidth + lvlRatio * 0.16   -- jusqu'à 38% au niveau max

  local baseSpeed = 1.15                      -- aller simple en ~0.87s
  local speed     = baseSpeed - lvlRatio * 0.35           -- 0.80 au niveau max

  local duration  = 4.5                       -- timeout global du QTE

  local zoneStart = math.random() * (1.0 - zoneWidth)
  return {
    duration   = duration,
    speed      = speed,
    targetMin  = zoneStart,
    targetMax  = zoneStart + zoneWidth,
  }
end

local function startQTE(vehId, vehicleName)
  local qcfg = getQTEConfig()
  state.qte = {
    active      = true,
    vehId       = vehId,
    vehicleName = vehicleName or "Vehicule",
    duration    = qcfg.duration,
    elapsed     = 0.0,
    cursorPos   = 0.0,
    direction   = 1,
    speed       = qcfg.speed,
    targetMin   = qcfg.targetMin,
    targetMax   = qcfg.targetMax,
  }
  sendUI({
    type        = "qteStart",
    duration    = qcfg.duration,
    targetMin   = qcfg.targetMin,
    targetMax   = qcfg.targetMax,
    vehicleName = vehicleName,
  })
  logFlow("QTE", string.format(
    "START | vehId=%s | vehName='%s' | zone=[%.3f..%.3f] (%.1f%%) | speed=%.2f | duration=%.1fs",
    tostring(vehId), tostring(vehicleName),
    qcfg.targetMin, qcfg.targetMax, (qcfg.targetMax - qcfg.targetMin) * 100,
    qcfg.speed, qcfg.duration
  ))
end

-- Forward decl pour que updateQTE puisse appeler validateQTE.
local failQTE
local validateQTE

local function updateQTE(dt)
  local q = state.qte
  if not q or not q.active then return end
  q.elapsed = q.elapsed + dt
  if q.elapsed >= q.duration then
    failQTE("timeout")
    return
  end
  -- Aller-retour linéaire (0→1→0→1…)
  q.cursorPos = q.cursorPos + q.direction * q.speed * dt
  if q.cursorPos >= 1.0 then
    q.cursorPos = 1.0
    q.direction = -1
  elseif q.cursorPos <= 0.0 then
    q.cursorPos = 0.0
    q.direction = 1
  end
  sendUI({
    type      = "qteUpdate",
    cursorPos = q.cursorPos,
    timeLeft  = math.max(0.0, q.duration - q.elapsed),
  })
  -- Log périodique (~1x/seconde) pour confirmer que le QTE tourne et voir la
  -- progression du curseur.
  q._nextLogAt = q._nextLogAt or 0
  if q.elapsed >= q._nextLogAt then
    logFlow("QTE", string.format(
      "RUN   | cursor=%.3f | elapsed=%.2fs | timeLeft=%.2fs",
      q.cursorPos, q.elapsed, q.duration - q.elapsed
    ))
    q._nextLogAt = q.elapsed + 1.0
  end
end

validateQTE = function ()
  local q = state.qte
  if not q or not q.active then return end
  local hit = q.cursorPos >= q.targetMin and q.cursorPos <= q.targetMax
  q.active = false
  sendUI({
    type      = "qteEnd",
    success   = hit,
    cursorPos = q.cursorPos,
  })
  logFlow("QTE", string.format(
    "CHECK | cursor=%.3f | zone=[%.3f..%.3f] | hit=%s | elapsed=%.2fs",
    q.cursorPos, q.targetMin, q.targetMax, tostring(hit), q.elapsed
  ))

  if hit then
    logFlow("QTE", "-> HIT : lancement mission sans police.")
    sendUI({
      type    = "feedback",
      level   = "success",
      message = "Vol discret reussi",
      sub     = "Aucun temoin, la police n'a rien vu"
    })
    startTheftMission(q.vehId, { noPolice = true })
  else
    logFlow("QTE", "-> MISS : police alertee + cooldown.")
    applyFailOrCancelCooldown("qte_rate")
    local failUnits = alertPolice("fail")
    sendUI({
      type    = "feedback",
      level   = "fail",
      message = "Vol rate",
      sub     = tostring(failUnits) .. " voitures de police en poursuite"
    })
  end
  state.qte = nil
end

failQTE = function (reason)
  local q = state.qte
  if not q or not q.active then return end
  q.active = false
  sendUI({
    type    = "qteEnd",
    success = false,
    reason  = reason,
  })
  logFlow("QTE", string.format(
    "FAIL  | reason=%s | cursor=%.3f | elapsed=%.2fs/%.2fs",
    tostring(reason), q.cursorPos or -1, q.elapsed or -1, q.duration or -1
  ))
  applyFailOrCancelCooldown("qte_" .. tostring(reason or "timeout"))
  local failUnits = alertPolice("fail")
  sendUI({
    type    = "feedback",
    level   = "fail",
    message = reason == "timeout" and "Temps ecoule" or "Vol rate",
    sub     = tostring(failUnits) .. " voitures de police en poursuite"
  })
  state.qte = nil
end

local function cancelQTE()
  if state.qte then
    state.qte.active = false
    sendUI({ type = "qteEnd", success = false, reason = "cancel" })
    state.qte = nil
  end
end

function M.onTheftKeyPressed()
  logFlow("KEY", string.format(
    "Touche K pressee. state.active=%s | qte=%s | mission=%s | cooldown=%.1f | wanted=%s",
    tostring(state.active),
    (state.qte and state.qte.active) and "ON" or "off",
    (state.mission and state.mission.status) or "none",
    state.cooldown or 0,
    tostring(state.wanted)
  ))

  -- Si le module est inactif, on tente une auto-réactivation au lieu de return
  -- silencieux. Ça évite le symptôme "j'appuie K et rien ne se passe" quand
  -- l'activation de carrière a été ratée (reloadUI, reload extension, etc.).
  if not state.active then
    if detectCareerActive() then
      logFlow("KEY", "-> Module inactif mais carriere active : auto-reactivation.")
      doActivate("auto-activation via onTheftKeyPressed")
      sendUI({
        type = "feedback",
        level = "warn",
        message = "Module reactive",
        sub = "Reessaie maintenant"
      })
    else
      logFlow("KEY", "-> Aucune carriere active, appui ignore.")
      sendUI({
        type = "feedback",
        level = "fail",
        message = "Mode carriere inactif",
        sub = "Lance une carriere pour voler"
      })
    end
    return
  end

  -- QTE en cours ? Alors K = validation du QTE, pas une nouvelle tentative.
  if state.qte and state.qte.active then
    logFlow("KEY", string.format(
      "-> QTE actif : validation. cursorPos=%.3f zone=[%.3f..%.3f] timeLeft=%.2fs",
      state.qte.cursorPos, state.qte.targetMin, state.qte.targetMax,
      math.max(0, state.qte.duration - state.qte.elapsed)
    ))
    validateQTE()
    return
  end

  if state.mission and state.mission.status == "enRouteToDropoff" then
    local playerVeh = be:getPlayerVehicle(0)
    local missionVeh = be:getObjectByID(state.mission.vehicleId)
    local inMissionVeh = playerVeh and missionVeh and (playerVeh:getID() == missionVeh:getID())

    if missionVeh and not inMissionVeh then
      logFlow("KEY", "-> Mission en cours : tentative de remonter dans le vehicule vole.")
      pcall(function()
        missionVeh:queueLuaCommand("if ai and ai.setMode then ai.setMode('disabled') end")
      end)
      local okEnter, errEnter = pcall(function()
        be:enterVehicle(0, missionVeh)
      end)
      if okEnter then
        sendUI({
          type = "feedback",
          level = "success",
          message = "Remontee dans le vehicule",
          sub = "Direction " .. state.mission.dropoff.name
        })
      else
        logFlow("KEY", "-> Echec re-entree missionVeh : " .. tostring(errEnter))
        sendUI({
          type = "feedback",
          level = "fail",
          message = "Impossible de remonter",
          sub = "Rapproche-toi du vehicule et reessaie"
        })
      end
    else
      logFlow("KEY", "-> Mission en cours (livraison) : deja dans le vehicule.")
      sendUI({
        type = "feedback",
        level = "warn",
        message = "Livraison en cours",
        sub = "Amene le vehicule au " .. state.mission.dropoff.name
      })
    end
    return
  end

  if state.cooldown > 0 then
    logFlow("KEY", string.format("-> Cooldown actif %.1fs, appui ignore.", state.cooldown))
    sendUI({
      type = "feedback",
      level = "warn",
      message = "Cooldown actif",
      sub = tostring(math.ceil(state.cooldown)) .. "s"
    })
    return
  end

  logFlow("KEY", "-> Raycast depuis la camera...")
  local target = raycastVehicleFromCamera()
  if not target then
    logFlow("KEY", "-> Raycast : aucune voiture trouvee dans le viseur.")
    sendUI({ type = "feedback", level = "warn", message = "Aucune cible", sub = "Regarde une voiture a voler" })
    return
  end
  logFlow("KEY", string.format("-> Raycast : cible vehId=%s dist=%.2fm", tostring(target.vehId), target.dist or -1))

  local okEligible, reason = isVehicleEligible(target.vehId)
  if not okEligible then
    logFlow("KEY", "-> Cible inelligible : " .. tostring(reason))
    sendUI({ type = "feedback", level = "warn", message = "Vol impossible", sub = reason or "" })
    return
  end

  -- Chance de vol instantané (bonus niveau élevé) : on saute le QTE.
  local bonuses = state.progression.bonuses
  local instantChance = clamp01(bonuses.instantStealChance)
  local instantRoll = math.random()
  logFlow("KEY", string.format(
    "-> Check vol instantane : chance=%.3f roll=%.3f => %s",
    instantChance, instantRoll, instantRoll <= instantChance and "HIT" or "miss"
  ))
  if instantRoll <= instantChance then
    sendUI({
      type    = "feedback",
      level   = "success",
      message = "Vol instantane",
      sub     = "Bonus niveau applique"
    })
    startTheftMission(target.vehId, { noPolice = true })
    return
  end

  -- Démarre le mini-jeu QTE. Le joueur doit ré-appuyer K dans la zone verte.
  local targetVeh = be:getObjectByID(target.vehId)
  local vehicleName = targetVeh and getVehicleDisplayName(targetVeh) or "Vehicule"
  logFlow("KEY", "-> Demarrage du QTE sur '" .. vehicleName .. "'")
  startQTE(target.vehId, vehicleName)
  sendUI({
    type    = "feedback",
    level   = "warn",
    message = "Appuie K dans la zone !",
    sub     = vehicleName
  })
end

function M.acceptBestOffer()
  local listing = state.market.listing
  local offer = state.market.lastOffer
  if not listing or not offer then
    sendUI({ type = "feedback", level = "warn", message = "Aucune offre active", sub = "" })
    return
  end

  local priceBonus = 1.0 + (state.progression.bonuses.priceFinalBonus or 0.0)
  local payout = math.floor(offer.amount * priceBonus)
  local paid = creditPlayerMoney(payout, "blackmarketSale")

  listing.status = "sold"
  if state.mission then state.mission.status = "sold" end
  sendUI({
    type = "saleComplete",
    vehicleName = listing.vehicleName,
    amount = payout,
    buyer = offer.buyer
  })
  addXp(cfg.progression.xpRewards.saleComplete, "vente_finalisee")
  if listing.vehicleId then
    despawnSoldVehicle(listing.vehicleId)
  elseif state.mission and state.mission.vehicleId then
    despawnSoldVehicle(state.mission.vehicleId)
  end
  if not paid then
    sendUI({
      type = "feedback",
      level = "warn",
      message = "Paiement a verifier",
      sub = "Le credit argent n'a pas ete confirme"
    })
  end
  state.market.lastOffer = nil
  state.market.listing = nil
  clearDropoffNavigation()
  state.mission = nil
end

function M.rejectOffer()
  if not state.market.lastOffer then
    sendUI({ type = "feedback", level = "warn", message = "Aucune offre active", sub = "" })
    return
  end
  state.market.lastOffer = nil
  sendUI({ type = "feedback", level = "warn", message = "Offre refusee", sub = "En attente d'une nouvelle offre" })
end

function M.cancelListing()
  if not state.market.listing then
    sendUI({ type = "feedback", level = "warn", message = "Aucune annonce", sub = "" })
    return
  end
  state.market.listing = nil
  state.market.lastOffer = nil
  clearDropoffNavigation()
  state.mission = nil
  applyFailOrCancelCooldown("annulation")
  sendUI({ type = "feedback", level = "warn", message = "Annonce retiree", sub = "Vehicule retire du BlackMarket" })
end

function M.onUpdate(dtReal, dtSim, dtRaw)
  if not state.active then return end

  if state.pendingSoldDespawn then
    local playerVeh = be and be:getPlayerVehicle(0) or nil
    if (not playerVeh) or playerVeh:getID() ~= state.pendingSoldDespawn then
      local id = state.pendingSoldDespawn
      state.pendingSoldDespawn = nil
      logFlow("MISSION", "Execution despawn differe vehicule vendu id=" .. tostring(id))
      despawnSoldVehicle(id)
    end
  end

  if state.cooldown > 0 then
    state.cooldown = math.max(0.0, state.cooldown - dtReal)
  end
  if state.wantedTimer > 0 then
    state.wantedTimer = math.max(0.0, state.wantedTimer - dtReal)
    if state.wantedTimer <= 0 then
      state.wanted = false
      sendUI({ type = "wantedEnd" })
    end
  end

  updateQTE(dtReal)
  updateMissionState()
  updateMarketplace(dtReal)

  -- Certains écrans (ex: big map) nettoient les markers. On repose
  -- périodiquement le waypoint tant que la mission de livraison est active.
  if state.mission and state.mission.status == "enRouteToDropoff" then
    state.nav.retryTimer = (state.nav.retryTimer or 0.0) + dtReal
    if state.nav.retryTimer >= 2.5 then
      state.nav.retryTimer = 0.0
      setDropoffNavigation(state.mission.dropoff)
    end
  else
    state.nav.retryTimer = 0.0
  end

  state.uiTick = state.uiTick + dtReal
  if state.uiTick >= 0.25 then
    state.uiTick = 0
    pushMissionUI()
    local listing = state.market.listing
    if listing then
      sendUI({
        type = "marketState",
        hasListing = true,
        vehicleName = listing.vehicleName,
        askingPrice = listing.askingPrice,
        integrity = listing.integrity,
        offerIn = listing.nextOfferTimer
      })
    else
      sendUI({ type = "marketState", hasListing = false })
    end
    if state.market.lastOffer then
      sendUI({
        type = "offerUpdate",
        buyer = state.market.lastOffer.buyer,
        amount = state.market.lastOffer.amount,
        askingPrice = state.market.lastOffer.askingPrice
      })
    end
    sendProgressionUI()
  end
end

local function applyConfigOverrides(raw)
  if type(raw) ~= "table" then return end
  if raw.targeting then
    cfg.targeting.maxDistance = raw.targeting.maxDistance or cfg.targeting.maxDistance
    cfg.targeting.maxCamAngleDeg = raw.targeting.maxCamAngleDeg or cfg.targeting.maxCamAngleDeg
    cfg.targeting.vehicleHitRadius = raw.targeting.vehicleHitRadius or cfg.targeting.vehicleHitRadius
  end
  if raw.theft then
    cfg.theft.cooldownAfterSteal = raw.theft.cooldownAfterSteal or cfg.theft.cooldownAfterSteal
    cfg.theft.cooldownAfterFailOrCancel = raw.theft.cooldownAfterFailOrCancel or cfg.theft.cooldownAfterFailOrCancel
    cfg.theft.wantedDuration = raw.theft.wantedDuration or cfg.theft.wantedDuration
    cfg.theft.maxTrackedVehicleDistance = raw.theft.maxTrackedVehicleDistance or cfg.theft.maxTrackedVehicleDistance
    cfg.theft.baseSuccessChance = raw.theft.baseSuccessChance or cfg.theft.baseSuccessChance
  end
  if raw.dropoff then
    cfg.dropoff.minIntegrity = raw.dropoff.minIntegrity or cfg.dropoff.minIntegrity
    cfg.dropoff.maxDropoffSpeed = raw.dropoff.maxDropoffSpeed or cfg.dropoff.maxDropoffSpeed
    if type(raw.dropoff.locations) == "table" and #raw.dropoff.locations > 0 then
      cfg.dropoff.locations = raw.dropoff.locations
    end
  end
  if raw.marketplace then
    cfg.marketplace.priceMultiplierMin = raw.marketplace.priceMultiplierMin or cfg.marketplace.priceMultiplierMin
    cfg.marketplace.priceMultiplierMax = raw.marketplace.priceMultiplierMax or cfg.marketplace.priceMultiplierMax
    cfg.marketplace.offerMinDelay = raw.marketplace.offerMinDelay or cfg.marketplace.offerMinDelay
    cfg.marketplace.offerMaxDelay = raw.marketplace.offerMaxDelay or cfg.marketplace.offerMaxDelay
    cfg.marketplace.offerMinFactor = raw.marketplace.offerMinFactor or cfg.marketplace.offerMinFactor
    cfg.marketplace.offerMaxFactor = raw.marketplace.offerMaxFactor or cfg.marketplace.offerMaxFactor
  end
  if raw.progression then
    cfg.progression.maxLevel = raw.progression.maxLevel or cfg.progression.maxLevel
    if raw.progression.xpRewards then
      cfg.progression.xpRewards.theftSuccess = raw.progression.xpRewards.theftSuccess or cfg.progression.xpRewards.theftSuccess
      cfg.progression.xpRewards.dropoffComplete = raw.progression.xpRewards.dropoffComplete or cfg.progression.xpRewards.dropoffComplete
      cfg.progression.xpRewards.saleComplete = raw.progression.xpRewards.saleComplete or cfg.progression.xpRewards.saleComplete
    end
    if type(raw.progression.levelThresholds) == "table" and #raw.progression.levelThresholds > 0 then
      cfg.progression.levelThresholds = raw.progression.levelThresholds
    end
    if type(raw.progression.levelBonuses) == "table" then
      cfg.progression.levelBonuses = raw.progression.levelBonuses
    end
  end
  if raw.debug then
    cfg.debug.debugMode = raw.debug.debugMode and true or false
  end
end

local function loadConfig()
  local ok, fileCfg = pcall(function()
    return jsonReadFile("careerThief_config.json")
  end)
  if ok and fileCfg then
    applyConfigOverrides(fileCfg)
    return
  end
  logWarn("Impossible de charger careerThief_config.json, utilisation des valeurs par defaut.")
end

local function doActivate(reason)
  clearGameplayState()
  state.active = true
  print("[CareerThief][INFO]  ===== Activation mode carriere (" .. tostring(reason) .. ") =====")
  discoverPoliceAPI()
  sendUI({ type = "moduleReady", mode = "blackmarket" })
  sendProgressionUI()
end

function M.onCareerModulesActivated()
  doActivate("onCareerModulesActivated")
end

function M.onCareerDeactivated()
  state.active = false
  clearGameplayState()
  sendUI({ type = "hide" })
end

M.onCareerActive = M.onCareerModulesActivated
M.onCareerModuleActivated = M.onCareerModulesActivated

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
  loadConfig()
  if detectCareerActive() and not state.active then
    doActivate("onExtensionLoaded + carriere deja active")
  end
end

function M.printPlayerPos()
  local veh = be and be:getPlayerVehicle(0)
  if not veh then
    return "Aucun vehicule joueur."
  end
  local p = veh:getPosition()
  local msg = string.format("PlayerPos x=%.3f y=%.3f z=%.3f", p.x, p.y, p.z)
  logFlow("DEBUG", msg)
  return msg
end

function M.setDropoffHere()
  local veh = be and be:getPlayerVehicle(0)
  if not veh then
    return "Aucun vehicule joueur."
  end
  local p = veh:getPosition()
  if not cfg.dropoff.locations or not cfg.dropoff.locations[1] then
    return "Aucun dropoff configure."
  end

  cfg.dropoff.locations[1].pos = { x = p.x, y = p.y, z = p.z }
  local d = cfg.dropoff.locations[1]
  logFlow("NAV", string.format("Dropoff recale sur position joueur: (%.2f, %.2f, %.2f)", p.x, p.y, p.z))

  if state.mission and state.mission.dropoff then
    state.mission.dropoff.pos = { x = p.x, y = p.y, z = p.z }
    setDropoffNavigation(state.mission.dropoff)
    sendUI({
      type = "feedback",
      level = "success",
      message = "Dropoff recale",
      sub = "Waypoint mis a jour"
    })
  else
    setDropoffNavigation(d)
  end

  return string.format("Dropoff mis a jour: x=%.2f y=%.2f z=%.2f", p.x, p.y, p.z)
end

function M.addDropoffHere(name)
  local ok, result = pcall(function()
    if not cfg.dropoff then cfg.dropoff = {} end
    if type(cfg.dropoff.locations) ~= "table" then cfg.dropoff.locations = {} end
    if type(customDropoffs) ~= "table" then customDropoffs = {} end

    local veh = be and be:getPlayerVehicle(0)
    if not veh then
      return "Aucun vehicule joueur."
    end
    local p = veh:getPosition()
    if not p then
      return "Position joueur introuvable."
    end

    local label = tostring(name or "")
    if label == "" then
      label = "BlackMarket " .. tostring(#customDropoffs + 1)
    end
    local id = "custom_" .. tostring(os.time()) .. "_" .. tostring(math.random(100, 999))
    local radius = (cfg.dropoff.locations[1] and cfg.dropoff.locations[1].radius) or 22.0

    local d = {
      id = id,
      name = label,
      pos = { x = tonumber(p.x) or 0, y = tonumber(p.y) or 0, z = tonumber(p.z) or 0 },
      radius = tonumber(radius) or 22.0
    }

    table.insert(customDropoffs, d)
    local added = addCustomDropoffToConfig(d)
    if not added then
      return "Impossible d'ajouter ce dropoff."
    end

    local saved = saveCustomDropoffs()
    logFlow("NAV", string.format("Nouveau dropoff ajoute: %s (%.2f, %.2f, %.2f)", label, d.pos.x, d.pos.y, d.pos.z))
    -- Retour simple (string) pour éviter tout souci de sérialisation console.
    return string.format("Dropoff ajoute (%s) saved=%s", label, tostring(saved))
  end)

  if not ok then
    logError("addDropoffHere a echoue: " .. tostring(result))
    return "Erreur addDropoffHere: " .. tostring(result)
  end
  return result
end

function M.listDropoffs()
  local out = {}
  for i, d in ipairs(cfg.dropoff.locations or {}) do
    out[#out + 1] = string.format("%d) %s [%s] @ %.1f, %.1f, %.1f r=%.1f",
      i, tostring(d.name), tostring(d.id), d.pos.x or 0, d.pos.y or 0, d.pos.z or 0, d.radius or 0)
  end
  local msg = table.concat(out, "\n")
  logFlow("NAV", "Dropoffs:\n" .. msg)
  return msg
end

function M.removeDropoff(ref)
  local ok, result = pcall(function()
    if type(cfg.dropoff) ~= "table" then cfg.dropoff = {} end
    if type(cfg.dropoff.locations) ~= "table" then cfg.dropoff.locations = {} end
    if type(customDropoffs) ~= "table" then customDropoffs = {} end

    local n = #cfg.dropoff.locations
    if n == 0 then
      return "Aucun dropoff a supprimer."
    end

    local idx = nil
    local needleNum = tonumber(ref)
    if needleNum then
      local i = math.floor(needleNum)
      if i >= 1 and i <= n then
        idx = i
      end
    end

    if not idx and ref ~= nil then
      local needle = tostring(ref):lower()
      for i, d in ipairs(cfg.dropoff.locations) do
        local id = tostring(d.id or ""):lower()
        local name = tostring(d.name or ""):lower()
        if id == needle or name == needle then
          idx = i
          break
        end
      end
    end

    if not idx then
      return "Introuvable. Utilise index, id ou nom exact."
    end

    if n <= 1 then
      return "Refus: garder au moins 1 dropoff."
    end

    local removed = table.remove(cfg.dropoff.locations, idx)
    if not removed then
      return "Suppression echouee."
    end

    customDropoffs = {}
    for _, d in ipairs(cfg.dropoff.locations) do
      local id = tostring(d.id or "")
      if id:match("^custom_") then
        customDropoffs[#customDropoffs + 1] = {
          id = d.id,
          name = d.name,
          pos = d.pos,
          radius = d.radius
        }
      end
    end
    saveCustomDropoffs()

    local msg = string.format("Dropoff supprime: %s [%s]", tostring(removed.name), tostring(removed.id))
    logFlow("NAV", msg)
    return msg
  end)

  if not ok then
    logError("removeDropoff a echoue: " .. tostring(result))
    return "Erreur removeDropoff: " .. tostring(result)
  end
  return result
end

function M.removeDropoffAt(index)
  local i = tonumber(index)
  if not i then
    return "Index invalide."
  end
  return M.removeDropoff(math.floor(i))
end

function M.removeLastDropoff()
  if type(cfg.dropoff) ~= "table" or type(cfg.dropoff.locations) ~= "table" then
    return "Aucun dropoff configure."
  end
  local n = #cfg.dropoff.locations
  if n <= 1 then
    return "Refus: garder au moins 1 dropoff."
  end
  return M.removeDropoff(n)
end

function M.exportDropoffsToConfig()
  local ok, msg = exportDropoffsToConfigFile()
  if ok then
    logFlow("NAV", msg .. " vers careerThief_config.json")
    return msg
  end
  logWarn("Export dropoffs config echoue: " .. tostring(msg))
  return "Export echoue: " .. tostring(msg)
end

function M.forceActivate()
  doActivate("forceActivate (console)")
  return "Career Thief BlackMarket actif."
end

local function init()
  math.randomseed(os.time())
  loadConfig()
  loadCustomDropoffs()
  state.progression.xp = 0
  recomputeProgression(false)
  loadProgression()
  logInfo("Extension Career Thief BlackMarket chargee.")
end

init()

return M
