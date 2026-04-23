local M = {}

local cfg = {
  targeting = {
    maxDistance = 11.0,
    maxCamAngleDeg = 22.0,
    vehicleHitRadius = 2.8
  },
  theft = {
    cooldownAfterSteal = 10.0,
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

-- ── État interne ──────────────────────────────────────────────────────────────
local state = {
  active = false,
  cooldown = 0.0,
  wanted = false,
  wantedTimer = 0.0,
  uiTick = 0.0,
  mission = nil,
  market = {
    listing = nil,
    lastOffer = nil
  },
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

local function recomputeProgression()
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
  if levelChanged then
    sendUI({
      type = "feedback",
      level = "success",
      message = "Niveau BlackMarket " .. tostring(level),
      sub = "Nouveaux avantages debloques"
    })
  end
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
  sendUI({
    type = "xpGain",
    amount = gain,
    reason = reason or "action"
  })
end

local function createListingFromMission(mission)
  local askFactor = randomRange(cfg.marketplace.priceMultiplierMin, cfg.marketplace.priceMultiplierMax)
  local askPrice = math.floor(mission.estimatedValue * askFactor)
  local listing = {
    id = tostring(os.time()) .. "_" .. tostring(math.random(100, 999)),
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
    sendUI({
      type = "idle",
      wanted = state.wanted,
      wantedTime = state.wantedTimer,
      cooldown = state.cooldown
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
  local playerVeh = be:getPlayerVehicle(0)
  if not playerVeh then return false, "Vehicule joueur introuvable" end
  if playerVeh:getID() == targetVehId then
    return false, "Tu ne peux pas voler ton vehicule"
  end
  return true, nil
end

local function startTheftMission(targetVehId)
  local targetVeh = be:getObjectByID(targetVehId)
  if not targetVeh then
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
  state.cooldown = cfg.theft.cooldownAfterSteal
  local units = alertPolice("success")
  sendUI({
    type = "feedback",
    level = "warn",
    message = "Police alertee",
    sub = tostring(units) .. " voiture(s) en poursuite"
  })
  addXp(cfg.progression.xpRewards.theftSuccess, "vol_reussi")
  sendUI({
    type = "theftStarted",
    vehicleName = state.mission.vehicleName,
    dropoffName = dropoff.name,
    estimatedValue = est
  })
  state.mission.status = "enRouteToDropoff"
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
  state.mission = nil
  state.market.listing = nil
  state.market.lastOffer = nil
  state.progression.level = 0
  state.progression.xp = 0
  state.progression.nextLevelXp = getNextLevelXp(0)
  state.progression.bonuses = recomputeCumulativeBonuses(0)
end

function M.onTheftKeyPressed()
  if not state.active then return end
  if state.mission and state.mission.status == "enRouteToDropoff" then
    sendUI({
      type = "feedback",
      level = "warn",
      message = "Livraison en cours",
      sub = "Amene le vehicule au " .. state.mission.dropoff.name
    })
    return
  end

  if state.cooldown > 0 then
    sendUI({
      type = "feedback",
      level = "warn",
      message = "Cooldown actif",
      sub = tostring(math.ceil(state.cooldown)) .. "s"
    })
    return
  end

  local target = raycastVehicleFromCamera()
  if not target then
    sendUI({ type = "feedback", level = "warn", message = "Aucune cible", sub = "Regarde une voiture a voler" })
    return
  end

  local okEligible, reason = isVehicleEligible(target.vehId)
  if not okEligible then
    sendUI({ type = "feedback", level = "warn", message = "Vol impossible", sub = reason or "" })
    return
  end

  local bonuses = state.progression.bonuses
  local instantChance = clamp01(bonuses.instantStealChance)
  local totalSuccessChance = clamp01(cfg.theft.baseSuccessChance + (bonuses.theftSuccessBonus or 0.0))
  local instantRoll = math.random()
  if instantRoll <= instantChance then
    sendUI({
      type = "feedback",
      level = "success",
      message = "Vol instantane",
      sub = "Bonus niveau applique"
    })
    startTheftMission(target.vehId)
    return
  end

  local successRoll = math.random()
  if successRoll <= totalSuccessChance then
    startTheftMission(target.vehId)
    return
  end

  local avoidRoll = math.random()
  local avoidPolice = avoidRoll <= clamp01(bonuses.policeAvoidOnFail)
  if avoidPolice then
    sendUI({
      type = "feedback",
      level = "warn",
      message = "Vol rate, discret",
      sub = "La police n'a pas ete alertee"
    })
  else
    local failUnits = alertPolice("fail")
    sendUI({
      type = "feedback",
      level = "fail",
      message = "Vol rate",
      sub = tostring(failUnits) .. " voitures de police en poursuite"
    })
  end
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
  if career_modules_playerAttributes and career_modules_playerAttributes.addAttribute then
    pcall(career_modules_playerAttributes.addAttribute, "money", payout)
  elseif career_modules_inventory and career_modules_inventory.addMoney then
    pcall(career_modules_inventory.addMoney, payout, "blackmarketSale")
  end

  listing.status = "sold"
  if state.mission then state.mission.status = "sold" end
  sendUI({
    type = "saleComplete",
    vehicleName = listing.vehicleName,
    amount = payout,
    buyer = offer.buyer
  })
  addXp(cfg.progression.xpRewards.saleComplete, "vente_finalisee")
  state.market.lastOffer = nil
  state.market.listing = nil
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
  state.mission = nil
  sendUI({ type = "feedback", level = "warn", message = "Annonce retiree", sub = "Vehicule retire du BlackMarket" })
end

function M.onUpdate(dtReal, dtSim, dtRaw)
  if not state.active then return end

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

  updateMissionState()
  updateMarketplace(dtReal)

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

function M.forceActivate()
  doActivate("forceActivate (console)")
  return "Career Thief BlackMarket actif."
end

local function init()
  math.randomseed(os.time())
  loadConfig()
  recomputeProgression()
  logInfo("Extension Career Thief BlackMarket chargee.")
end

init()

return M
