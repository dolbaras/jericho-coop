-- Jericho co-op: host-authoritative enemies, damage and story logic (phase 1).
-- Design: docs/enemies-and-triggers.md section 7. The host simulates enemies, spawns,
-- damage, deaths and story callbacks; clients show enemies as puppets, report their own
-- hits, and only take damage the host sends them.
--
-- Messages (text, "|" separated):
--   e|n,x,y,z,yaw,action,flags;n,...   host -> clients, unreliable, ~10 Hz (flags 1 = active)
--   espawn|name|class|group|x|y|z      host -> clients, reliable (NPC.CreateWithAI)
--   egroup|group                       host -> clients, reliable (NPC.ActivateEnemyGroup)
--   edie|name                          host -> clients, reliable (Weapons.OnCharDeath)
--   pdmg|victim|amount|attacker        host -> owner of victim, reliable
--   hit|enemy|damage|attacker          client -> host, reliable

CoopEnemies = {}
local E = CoopEnemies
E.SNAP_EVERY = 2          -- network ticks between snapshots (20 Hz tick -> 10 Hz)
E.SNAP_DIST = 250         -- units; enemy puppet teleports beyond this
E.NUDGE = 0.3
E.MAX_PACKET = 900        -- bytes per snapshot packet
E.targets = {}            -- client: name -> {x,y,z,yaw,action,active}
E.applied = {}            -- client: name -> last action forced
E.stats = {hitsSent = 0, hitsApplied = 0, pdmgSent = 0, pdmgApplied = 0, dropped = 0,
           spawns = 0, deaths = 0, groups = 0, snapshots = 0, missing = 0}

local function isEnemy(e)
  -- Check the type first: reading TgType on entities without it (triggers, sounds, cameras)
  -- makes the engine log an error per read, which slowed a level down to seconds per frame.
  return e and e:IsType("WalkChar") and e.TgType == "red"
end

-- Run fn with the "this came from the host" flag set, so client guards let it through.
local function fromHost(fn, ...)
  Coop.fromHost = true
  local ok, a, b = pcall(fn, ...)
  Coop.fromHost = false
  if not ok then Coop.log("fromHost error: " .. tostring(a)) end
  return a, b
end
E.fromHost = fromHost

------------------------------------------------------------------------------
-- Host
------------------------------------------------------------------------------

function E.snapshot()
  local parts, size = {}, 0
  local function flush()
    if #parts > 0 then
      Net.CoopSend(-1, 0, "e|" .. table.concat(parts, ";"))
      E.stats.snapshots = E.stats.snapshots + 1
      parts, size = {}, 0
    end
  end
  local e = Game.GetFirst()
  local n = 0
  while e ~= nil do
    if isEnemy(e) and e.Life > 0 and e.bActive then
      local p = e.Pos
      local s = string.format("%s,%.0f,%.0f,%.0f,%.0f,%s,1", e.Name, p.x, p.y, p.z, e.Ang.y, tostring(e.Action))
      parts[#parts + 1] = s
      size = size + #s + 1
      n = n + 1
      if size > E.MAX_PACKET then flush() end
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  flush()
  E.lastCount = n
end

function E.installHost()
  local origCreate = NPC.CreateWithAI
  NPC.CreateWithAI = function(acName, x, y, z, listName, setOnFloor)
    local e = origCreate(acName, x, y, z, listName, setOnFloor)
    if e then
      E.stats.spawns = E.stats.spawns + 1
      Net.CoopSend(-1, 1, string.format("espawn|%s|%s|%s|%.0f|%.0f|%.0f", e.Name, acName, tostring(listName), x, y, z))
    end
    return e
  end

  local origActivate = NPC.ActivateEnemyGroup
  NPC.ActivateEnemyGroup = function(group, ...)
    local var = init.LevelName .. ".EnemyGroup." .. group .. ".Status"
    Game.CreateSaveVar(var, "0")
    local before = Game.GetSaveVar(var)
    local r = origActivate(group, ...)
    if before == "0" and Game.GetSaveVar(var) == "1" then
      E.stats.groups = E.stats.groups + 1
      Net.CoopSend(-1, 1, "egroup|" .. group)
    end
    return r
  end

  local origDeath = Weapons.OnCharDeath
  Weapons.OnCharDeath = function(name, from, ...)
    local e = Game.GetEntity(name)
    if isEnemy(e) then
      E.stats.deaths = E.stats.deaths + 1
      Net.CoopSend(-1, 1, "edie|" .. name)
    end
    return origDeath(name, from, ...)
  end

  local origDamage = Weapons.DoDamage
  E.origDamage = origDamage
  Weapons.DoDamage = function(From, To, Damage, BodyMultiplier)
    -- A remote player's puppet fires for show only; its owner reports real hits.
    if From and Coop.isRemoteOwned(From.Name) and not Coop.applyingRemoteHit then
      E.stats.dropped = E.stats.dropped + 1
      return false
    end
    -- Damage to a body another human controls is applied by its owner.
    if To and Coop.isRemoteOwned(To.Name) and not Coop.applyingRemoteHit then
      local owner = Coop.ownerOf(To.Name)
      E.stats.pdmgSent = E.stats.pdmgSent + 1
      Net.CoopSend(owner, 1, string.format("pdmg|%s|%.2f|%s", To.Name, Damage, From and From.Name or ""))
      return false
    end
    return origDamage(From, To, Damage, BodyMultiplier)
  end
end

-- Cutscenes: the host announces every scene it starts (story callbacks run only there);
-- clients play the same scene locally. First-person scenes bind to Game.UsrEntity(0),
-- so each player sees them from their own character. Chained scenes (NextScene) are
-- started by EndOfScene on every machine and are not forwarded.
E.SCENE_FUNCS = {play = "Play", fp = "PlayFP", fpni = "PlayFPNI", fpnni = "PlayFPNNI"}

-- First-person scenes are animated for one character only (FP_<char>_Play.CM3 in the level
-- archives). Players holding another character watch through that character's eyes and keep
-- their own body where it was (the scene would otherwise move it to the scene's end point).
E.FP_OWNER = {
  helicoptertrip = "Ross", landing = "Ross", thedreamb = "Ross", thedreamc = "Ross",
  murielstale = "Ross", rossdeath = "Ross", blooddoor = "Ross", tombcollapses = "Ross",
  rossdeathb = "Delgado", thetrap = "Delgado", bridgecollapses = "Delgado",
  cruzadersspeech_a = "Delgado", conversation = "Delgado",
  therescue = "Black", cruzadersspeech_b = "Black", apertura = "Black", theenda = "Black",
  theendb = "Black", intotheunknown = "Black", britishcomando = "Black",
  behemothdead = "Church", aperturapuerta = "Church", descensoa = "Church", descensob = "Church",
  escalada = "Church", theabyss = "Church", theendc = "Church", theendd = "Church",
  nazisacrificea = "Church", nazisacrificeb = "Church",
  centurianstale = "Rawlings", rawlingstorture = "Rawlings",
  delgadokillsrawlings = "Cole", pathofsouls = "Cole",
  britishcomandospeech = "Jones",
}

-- Before a first-person scene: remember the local body if it is not the scene's character.
function E.beforeFpScene(class)
  local owner = E.FP_OWNER[string.lower(tostring(class))]
  local usr = Game.UsrEntity(0)
  if owner and usr and usr.Name ~= owner and not E.fpRestore then
    E.fpRestore = {name = usr.Name, pos = usr.Pos, ang = usr.Ang}
    E.fpLabel = owner
  end
end

function E.installFpRestore()
  local orig = Scene.EndOfFpScene
  Scene.EndOfFpScene = function(usr, ...)
    local r = {pcall(orig, usr, ...)}
    local keep = E.fpRestore
    E.fpRestore, E.fpLabel = nil, nil
    if keep then
      local body = Game.GetEntity(keep.name)
      if body then
        body.Pos = keep.pos
        body.Ang = keep.ang
        body.IgnoreUsrControl = 0
      end
      Coop.log("fp scene over: " .. keep.name .. " back in place")
    end
    if not r[1] then Coop.log("EndOfFpScene error: " .. tostring(r[2])) end
    return r[2]
  end
end

-- During a first-person scene seen through someone else's eyes, say whose.
E.EYES = {en = "Through %s's eyes", ru = "\195\235\224\231\224\236\232 %s"}  -- "Глазами %s" (cp1251)
function E.updateSceneLabel()
  local it = Scorer.GetItem(0, "CoopEyes")
  if E.fpLabel and Scene.IsPlaying then
    if not it then
      it = Scorer.NewItem(0, "CoopEyes", "Text")
      it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
      it.Color = Color(230, 230, 230, 255)
      it.Effect = "Shadow"
      it.Pos = V2D(320, 40)
    end
    local lang = (CoopMenu and CoopMenu.lang) or (string.byte(Game.GetLangStr("Menu_ExitGame") or "", 1) or 0) >= 192 and "ru" or "en"
    it.Text = string.format(E.EYES[lang] or E.EYES.en, E.fpLabel)
    it.CentralText = 1
    it.Visible = 1
  elseif it then
    it.Visible = 0
  end
end

-- Level changes (story transitions, restarts) are the host's: it announces the level and
-- clients load the same one. SaveGame.LoadLevel is where every story path ends.
function E.installLevelHost()
  local orig = SaveGame.LoadLevel
  SaveGame.LoadLevel = function(name, ...)
    if name and name ~= "menu" then
      Coop.log("level -> " .. tostring(name))
      Net.CoopSend(-1, 1, "level|" .. tostring(name))
      Coop.cfg.level = name
      Coop.rearm()
    end
    return orig(name, ...)
  end
end

function E.onLevel(name)
  Coop.log("host changes level to " .. tostring(name))
  Coop.cfg.level = name
  Coop.rearm()
  fromHost(SaveGame.LoadLevel, name)
end

-- A failed QTE replays its scene (Scene.ReloadScene -> ReplayScene). Branches are synced
-- (CoopScenes), so every machine replays by itself: let that Play through on clients and
-- do not forward it from the host.
function E.installReplay()
  local orig = Scene.ReplayScene
  if not orig then return end
  Scene.ReplayScene = function(...)
    Coop.log("scene replay " .. tostring((...)))
    E.inReplay = true
    local ok, err = pcall(orig, ...)
    E.inReplay = false
    if not ok then Coop.log("ReplayScene error: " .. tostring(err)) end
  end
end

-- Level-start scenes (the WWII conversation, the chapel rescue, the ending, ...) would play
-- on the host while clients are still loading. The host holds scene starts until every
-- expected player reported the level loaded (lready), at most GATE_TIMEOUT seconds.
-- Expected players: the lobby seats, or cfg.waitpeers in tests.
E.GATE_TIMEOUT = 90
E.readyPeers = {}

function E.expectedPeers()
  if Coop.cfg.waitpeers then return Coop.cfg.waitpeers end
  local n = 0
  for item in string.gmatch(Coop.cfg.seats or "", "[^;]+") do
    if not string.find(item, "^0:") then n = n + 1 end
  end
  return n
end

function E.gateOpen()
  if E.gateOpened then return true end
  local ready = 0
  for _ in pairs(E.readyPeers) do ready = ready + 1 end
  if ready >= E.expectedPeers() or Net.CoopTime() > (E.gateUntil or 0) then
    E.gateOpened = true
    Coop.log(string.format("scene gate open: %d of %d players loaded", ready, E.expectedPeers()))
  end
  return E.gateOpened
end

function E.flushHeldScenes()
  local held = E.heldScenes
  if not held or not E.gateOpen() then return end
  E.heldScenes = nil
  for _, h in ipairs(held) do
    Coop.log("scene " .. h.fname .. " " .. tostring(h.class) .. " released")
    Scene[h.fname](h.class, unpack(h.args))
  end
end

function E.installSceneHost()
  E.installReplay()
  E.gateUntil = Net.CoopTime() + E.GATE_TIMEOUT
  local origEnd = Scene.EndOfScene
  Scene.EndOfScene = function(...)
    E.inEndOfScene = true
    local ok, a, b = pcall(origEnd, ...)
    E.inEndOfScene = false
    if not ok then Coop.log("EndOfScene error: " .. tostring(a)) end
    return a, b
  end
  for mode, fname in pairs(E.SCENE_FUNCS) do
    local orig = Scene[fname]
    Scene[fname] = function(class, ...)
      if not E.inEndOfScene and not E.inReplay and not E.gateOpen() then
        E.heldScenes = E.heldScenes or {}
        table.insert(E.heldScenes, {fname = fname, class = class, args = {...}})
        Coop.log("scene " .. fname .. " " .. tostring(class) .. " held until the players have loaded")
        return false
      end
      -- PlayFP -> PlayFPNI -> Play run in sequence (partly asynchronously) for one scene;
      -- the client repeats that chain itself, so forward only its first call.
      local now = Net.CoopTime()
      local repeated = class == E.lastSceneClass and now - (E.lastSceneTime or 0) < 15
      if mode ~= "play" then E.beforeFpScene(class) end
      if not E.inEndOfScene and not E.inReplay and not repeated then
        Net.CoopSend(-1, 1, "scene|" .. mode .. "|" .. tostring(class))
        E.stats.scenes = (E.stats.scenes or 0) + 1
        E.lastSceneClass, E.lastSceneTime = class, now
      end
      return orig(class, ...)
    end
  end
  local origAbort = Scene.AbortScene
  Scene.AbortScene = function(...)
    Net.CoopSend(-1, 1, "scene|abort|")
    return origAbort(...)
  end
end

function E.installSceneClient()
  E.installReplay()
  local origEnd = Scene.EndOfScene
  Scene.EndOfScene = function(...)
    Coop.log("scene ended " .. tostring(Scene.SceneName))
    E.inEndOfScene = true
    local ok, a, b = pcall(origEnd, ...)
    E.inEndOfScene = false
    if not ok then Coop.log("EndOfScene error: " .. tostring(a)) end
    return a, b
  end
  for mode, fname in pairs(E.SCENE_FUNCS) do
    local orig = Scene[fname]
    E["scene_" .. fname] = orig
    Scene[fname] = function(class, ...)
      if Coop.fromHost or E.inEndOfScene or E.inReplay then
        if mode ~= "play" then E.beforeFpScene(class) end
        return orig(class, ...)
      end
      E.stats.dropped = E.stats.dropped + 1
      return false
    end
  end
  -- Skipping is the host's decision.
  E.sceneAbort = Scene.AbortScene
  Scene.AbortScene = function(...)
    if Coop.fromHost then return E.sceneAbort(...) end
  end
end

function E.onScene(mode, class)
  E.stats.scenes = (E.stats.scenes or 0) + 1
  Coop.log("scene " .. mode .. " " .. tostring(class))
  if mode == "abort" then
    if Scene.IsPlaying then fromHost(Scene.AbortScene) end
    return
  end
  local fname = E.SCENE_FUNCS[mode]
  if fname and Scene[fname] then fromHost(Scene[fname], class) end
end

-- A client finished loading the level: bring it to the host's current enemy state
-- (groups already activated, enemies spawned at runtime). Placed enemies exist on both
-- machines with the same names.
function E.sendCatchup(peer)
  local groups, spawns = 0, 0
  if NPC and NPC.Groups then
    for group in pairs(NPC.Groups) do
      if Game.GetSaveVar(init.LevelName .. ".EnemyGroup." .. group .. ".Status") == "1" then
        Net.CoopSend(peer, 1, "egroup|" .. group)
        groups = groups + 1
      end
    end
  end
  local e = Game.GetFirst()
  while e ~= nil do
    if isEnemy(e) and e.Life > 0 and string.sub(e.Name, 1, 6) == "Enemy_" then
      local p = e.Pos
      Net.CoopSend(peer, 1, string.format("espawn|%s|%s|%s|%.0f|%.0f|%.0f", e.Name, tostring(e.ActCtrl),
        tostring(e.EntityList), p.x, p.y, p.z))
      spawns = spawns + 1
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  Coop.log(string.format("catch-up for peer %d: %d groups, %d spawned enemies", peer, groups, spawns))
  E.catchupSent = true
end

-- A client's hit: apply it as a human's hit (no AI team damage roll).
function E.applyHit(enemyName, damage, attackerName)
  local To = Game.GetEntity(enemyName)
  local From = Game.GetEntity(attackerName)
  if not To or not From or To.Life <= 0 then return end
  local factor = To.uData and To.uData.TeamDamageFactor
  if To.uData then To.uData.TeamDamageFactor = nil end
  Coop.applyingRemoteHit = true
  local ok, err = pcall(E.origDamage, From, To, damage, nil)
  Coop.applyingRemoteHit = false
  if To.uData then To.uData.TeamDamageFactor = factor end
  if not ok then Coop.log("applyHit error: " .. tostring(err)) end
  E.stats.hitsApplied = E.stats.hitsApplied + 1
end

------------------------------------------------------------------------------
-- Client
------------------------------------------------------------------------------

-- Story and spawn logic runs on the host only. Each guard lets calls through while
-- Coop.fromHost is set (the client replaying a host decision).
local function guard(tbl, name)
  local f = tbl and tbl[name]
  if type(f) ~= "function" then return end
  tbl[name] = function(...)
    if Coop.fromHost then return f(...) end
    -- A host callback replayed by coop_world.lua runs the level's own effects here;
    -- enemies, saves and level changes stay dropped (the host sends those itself).
    if Coop.replay and tbl == MapCallbacks then return f(...) end
    if tbl == MapCallbacks and CoopWorld then CoopWorld.onLocalCallback(name, ...) end
    E.stats.dropped = E.stats.dropped + 1
  end
  return f
end

function E.installClient()
  -- Every map callback (area triggers, use actions, scene ends, pulsers).
  local n = 0
  if MapCallbacks then
    for k, v in pairs(MapCallbacks) do
      if type(v) == "function" then guard(MapCallbacks, k) n = n + 1 end
    end
  end
  if AreaTriggers then
    guard(AreaTriggers, "OnEnterPluser")
    guard(AreaTriggers, "OnExitPluser")
  end
  E.origActivate = guard(NPC, "ActivateEnemyGroup")
  E.origCreate = guard(NPC, "CreateWithAI")
  for _, f in ipairs({"ActivateNextEnemy", "ScheduleActivationOfNextEnemy", "Start", "Stop"}) do
    guard(EnemyGen, f)
  end
  for _, f in ipairs({"NewLevel", "NewLevelNow", "AutoSaveWaypoint", "FlagCounter", "LoadLevel",
                      "LoadWaypoint", "Restart"}) do
    guard(SaveGame, f)
  end
  Coop.log("client guards: " .. n .. " map callbacks")

  local origDamage = Weapons.DoDamage
  E.origDamage = origDamage
  Weapons.DoDamage = function(From, To, Damage, BodyMultiplier)
    if Coop.fromHost or not From or not To then
      return origDamage(From, To, Damage, BodyMultiplier)
    end
    if From.Name == Coop.localChar() and isEnemy(To) then
      -- Resolve the body-part multiplier locally (it needs this machine's hit), then
      -- report the final damage to the host instead of applying it.
      local dmg = Damage
      if BodyMultiplier ~= nil then
        To:SetLastBodyPiece(From)
        local piece = To.oWeapHit and To.oWeapHit.oBodyPiece
        if piece then
          local m = piece.oRagDollDamagePart.Damage
          dmg = m > 1 and Damage * m ^ BodyMultiplier or Damage * m
        end
      end
      Net.CoopSend(0, 1, string.format("hit|%s|%.2f|%s", To.Name, dmg, From.Name))
      E.stats.hitsSent = E.stats.hitsSent + 1
      if BodyImpact and BodyImpact.OnShot then pcall(BodyImpact.OnShot, To.Name) end
      return false
    end
    if From:IsType("WalkChar") and (From.TgType == "red" or From.Name ~= Coop.localChar()) then
      -- Enemy damage comes from the host (pdmg); puppets fire for show only.
      E.stats.dropped = E.stats.dropped + 1
      return false
    end
    return origDamage(From, To, Damage, BodyMultiplier)
  end
end

function E.onSnapshot(body)
  for item in string.gmatch(body, "[^;]+") do
    local name, x, y, z, yaw, action, flags = string.match(item, "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]*),(%d+)$")
    if name then
      E.targets[name] = {x = tonumber(x), y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw),
                         action = action, active = flags == "1", t = Net.CoopTime()}
    end
  end
end

-- Every frame on a client: host enemies follow the snapshots; no enemy runs local AI.
function E.driveEnemies(dt)
  local nudge = 1 - (1 - E.NUDGE) ^ (math.min(dt, 0.25) / 0.05)
  local now = Net.CoopTime()
  for name, st in pairs(E.targets) do
    local e = Game.GetEntity(name)
    if not e then
      E.stats.missing = E.stats.missing + 1
      E.targets[name] = nil
    elseif e.Life <= 0 or now - st.t > 2 then
      E.targets[name] = nil   -- dead, or no longer in the host's snapshots
    else
      if st.active and not e.bActive then e.bActive = true end
      if e.oAI and e.oAI.bEnable then e.oAI.bEnable = false end
      local pos = e.Pos
      local dx, dy, dz = pos.x - st.x, pos.y - st.y, pos.z - st.z
      local err = math.sqrt(dx * dx + dz * dz)
      if err > E.SNAP_DIST or math.abs(dy) > E.SNAP_DIST then
        e.Pos = V3D(st.x, st.y, st.z)
      elseif err > 5 then
        e.Pos = V3D(pos.x - dx * nudge, pos.y - dy * nudge, pos.z - dz * nudge)
      end
      e.Ang = V3D(0, st.yaw, 0)
      if st.action ~= "" and st.action ~= E.applied[name] and e.Action ~= st.action
         and not string.find(st.action, "Death") then
        e.ForceAction = st.action
        E.applied[name] = st.action
      end
    end
  end
end

-- Enemies the client knows but the host does not drive must not think either.
function E.freezeLocalEnemies()
  local e = Game.GetFirst()
  while e ~= nil do
    if isEnemy(e) and e.Life > 0 and not E.targets[e.Name] and e.oAI and e.oAI.bEnable then
      e.oAI.bEnable = false
    end
    e = Game.GetEntity(e.NextInSlot)
  end
end

------------------------------------------------------------------------------
-- Dispatch
------------------------------------------------------------------------------

function E.onMessage(peer, f)
  local kind = f[1]
  if kind == "e" and Coop.isClient() then
    E.onSnapshot(f[2] or "")
  elseif kind == "espawn" and Coop.isClient() then
    local name, class, group = f[2], f[3], f[4]
    if not Game.GetEntity(name) and E.origCreate then
      local e = fromHost(NPC.CreateWithAI, class, tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), group)
      if e and e.Name ~= name then e.Name = name end
    end
    E.stats.spawns = E.stats.spawns + 1
  elseif kind == "egroup" and Coop.isClient() then
    fromHost(NPC.ActivateEnemyGroup, f[2])
    E.stats.groups = E.stats.groups + 1
  elseif kind == "edie" and Coop.isClient() then
    local e = Game.GetEntity(f[2])
    if e and e.Life > 0 then
      e.Invulnerable = 0
      e.Life = 0
    end
    E.targets[f[2]] = nil
    E.stats.deaths = E.stats.deaths + 1
  elseif kind == "pdmg" then
    local usr = Game.UsrEntity(0)
    if usr and usr.Name == f[2] then
      local from = Game.GetEntity(f[4]) or usr
      fromHost(E.origDamage, from, usr, tonumber(f[3]), nil)
      E.stats.pdmgApplied = E.stats.pdmgApplied + 1
    end
  elseif kind == "hit" and Coop.isHost() then
    E.applyHit(f[2], tonumber(f[3]), f[4])
  elseif kind == "scene" and Coop.isClient() then
    E.onScene(f[2], f[3])
  elseif kind == "level" and Coop.isClient() then
    E.onLevel(f[2])
  elseif kind == "lready" and Coop.isHost() then
    if string.lower("levels/" .. (f[2] or "")) == Coop.level then
      E.sendCatchup(peer)
      E.readyPeers[peer] = true
    end
  else
    return false
  end
  return true
end

function E.update()
  if Coop.isHost() then
    if Coop.frame % E.SNAP_EVERY == 0 then E.snapshot() end
    E.flushHeldScenes()
  elseif Coop.isClient() then
    -- Tell the host this level is loaded so it sends the current enemy state.
    if not E.readySent and Coop.cfg.myId then
      E.readySent = true
      Net.CoopSend(0, 1, "lready|" .. string.sub(Game.GetLevelPath(), 8))
    end
    if Coop.frame % 10 == 0 then E.freezeLocalEnemies() end
  end
end

function E.report()
  local s = E.stats
  if Coop.isClient() then
    local n = 0
    for _ in pairs(E.targets) do n = n + 1 end
    E.lastCount = "driven:" .. n
  end
  return string.format("enemies=%s hits=%d/%d pdmg=%d/%d spawns=%d groups=%d deaths=%d dropped=%d snaps=%d scenes=%d",
    tostring(E.lastCount or "-"), s.hitsSent, s.hitsApplied, s.pdmgSent, s.pdmgApplied, s.spawns,
    s.groups, s.deaths, s.dropped, s.snapshots, s.scenes or 0)
end

-- Scene hooks go in as soon as this file loads: levels schedule their opening scene for
-- the first game tick (wwii_biggates MapInit.main), before the first co-op tick.
function E.installScenes()
  if E.scenesInstalled or not Scene or not Scene.Play or not Scene.EndOfScene then return end
  if not (Coop.isHost() or Coop.isClient()) then return end
  E.scenesInstalled = true
  if Coop.isHost() then E.installSceneHost() else E.installSceneClient() end
  E.installFpRestore()
  Coop.log("scene hooks installed as " .. tostring(Coop.cfg.role))
end

function E.install()
  if E.installed or not NPC or not Weapons then return end
  E.installed = true
  if Coop.isHost() then E.installHost() elseif Coop.isClient() then E.installClient() end
  E.installScenes()
  if SaveGame and Coop.isHost() then E.installLevelHost() end
  Coop.log("enemies installed as " .. tostring(Coop.cfg.role))
end

E.installScenes()
