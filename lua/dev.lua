-- Development helpers, loaded when COOP_CFG.dev is set.
--   cfg.bot = 'circle'      the local body runs in a circle through its own control inputs
--   cfg.exp = 'framehook'   compare OnRenderDebug calls with scheduler ticks under slow time

local cfg = Coop.cfg

function Coop.botCircle()
  if Coop.level == "levels/menu" then return end
  local usr = Game.UsrEntity(0)
  if not usr or Coop.frame < 60 then return end
  -- Wait for the client's switch to its assigned body.
  if Coop.isClient() and cfg.char and usr.Name ~= cfg.char then return end
  local yaw = (Coop.frame * 4) % 360
  -- Device input overwrites InCtrl_* of the user's body every frame unless ignored.
  usr.IgnoreUsrControl = 1
  usr.Ang = V3D(0, yaw, 0)
  usr.InCtrl_Walk = 1
  if Coop.frame % 100 == 0 then
    Coop.log("bot " .. usr.Name .. " pos=" .. Coop.v3(usr.Pos) .. " yaw=" .. yaw ..
             " ang=" .. Coop.v3(usr.Ang) .. " act=" .. tostring(usr.Action))
  end
end

if cfg.bot == "circle" then Coop.bot = Coop.botCircle end

-- 'wander': run forward, turn when blocked; log the path so the headless bot can replay
-- a route that respects the level's collision ("path|t|x|y|z|yaw|walk" lines).
function Coop.botWander()
  if Coop.level == "levels/menu" then return end
  local usr = Game.UsrEntity(0)
  if not usr or Coop.frame < 40 then return end
  if Coop.isClient() and cfg.char and usr.Name ~= cfg.char then return end
  local W = Coop.wander
  if not W then
    W = {yaw = usr.Ang.y, t0 = Net.CoopTime(), last = usr.Pos, stuck = 0}
    Coop.wander = W
  end
  usr.IgnoreUsrControl = 1
  local p = usr.Pos
  -- Fight: face the nearest living enemy within range and fire in bursts.
  if cfg.botfire then
    local best, bestD
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive then
        local d = e.Pos - p
        local dist = math.sqrt(d.x * d.x + d.z * d.z)
        if dist < 2500 and (not bestD or dist < bestD) then best, bestD = e, dist end
      end
      e = Game.GetEntity(e.NextInSlot)
    end
    if best then
      local d = best.Pos - p
      local yaw = math.deg(math.atan2(-d.x, -d.z))
      usr.Ang = V3D(0, yaw, 0)
      usr.ViewAng = V3D(0, yaw, 0)
      usr.InCtrl_Walk = 0
      usr.owc.Shot = (Coop.frame % 30 < 20) and 1 or 0
      if Coop.frame % 40 == 0 then
        Coop.log(string.format("bot fires at %s %.0f units, life %.0f", best.Name, bestD, best.Life))
      end
      return
    end
    usr.owc.Shot = 0
  end
  local moved = math.sqrt((p.x - W.last.x) ^ 2 + (p.z - W.last.z) ^ 2)
  W.last = p
  if moved < 5 then W.stuck = W.stuck + 1 else W.stuck = 0 end
  if W.stuck >= 4 then
    W.yaw = (W.yaw + 90 + math.random(0, 90)) % 360
    W.stuck = 0
  elseif Coop.frame % 60 == 0 then
    W.yaw = (W.yaw + math.random(-40, 40)) % 360
  end
  usr.Ang = V3D(0, W.yaw, 0)
  usr.InCtrl_Walk = 1
  Coop.log(string.format("path|%.2f|%.0f|%.0f|%.0f|%.1f|1", Net.CoopTime() - W.t0, p.x, p.y, p.z, W.yaw))
end

if cfg.bot == "wander" then Coop.bot = Coop.botWander end

-- 'fight' (host): activate the enemy groups nearest to the player after a short delay so
-- a test run has combat.
if cfg.exp == "fight" and Coop.isHost() and Coop.level ~= "levels/menu" then
  local FIGHT_AT, GROUPS = cfg.fightat or 120, cfg.groups or 2
  function Coop.dev()
    if Coop.frame ~= FIGHT_AT or not NPC or not NPC.Groups then return end
    local usr = Game.UsrEntity(0)
    local list = {}
    for name, g in pairs(NPC.Groups) do
      local best
      for _, e in ipairs(g) do
        if e.Pos then
          local d = (e.Pos - usr.Pos)
          local dist = math.sqrt(d.x * d.x + d.z * d.z)
          if not best or dist < best then best = dist end
        end
      end
      if best then list[#list + 1] = {name = name, dist = best} end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    for i = 1, math.min(GROUPS, #list) do
      Coop.log(string.format("fight: activate %s (%.0f units)", list[i].name, list[i].dist))
      NPC.ActivateEnemyGroup(list[i].name)
    end
  end
end

-- 'shoot': can a body with AI off be made to fire through its control fields, and does
-- Scorer.Get2DPos project a world point to the screen (for nameplates)?
if cfg.exp == "shoot" and Coop.level ~= "levels/menu" then
  local shots = {}
  local origShot = Weapons.OnShot
  Weapons.OnShot = function(name, ...)
    shots[name] = (shots[name] or 0) + 1
    return origShot(name, ...)
  end
  local fields = {"owc.Shot", "owc.MainWeaponTrigger", "InCtrl_Shot"}
  local function setf(p, field, v)
    if string.sub(field, 1, 4) == "owc." then p.owc[string.sub(field, 5)] = v else p[field] = v end
  end
  function Coop.dev()
    local f = Coop.frame
    local p = Game.GetEntity(cfg.puppet or "Black")
    local usr = Game.UsrEntity(0)
    if not p or not usr then return end
    if f == 80 then
      p.oAI.bEnable = false
      local a, b, c = Scorer.Get2DPos(p.Pos)
      local a2, b2, c2 = Scorer.Get2DPos(usr.Pos + V3D(0, 0, -500))
      Coop.log("Get2DPos(puppet)=" .. tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) ..
               "  Get2DPos(500 ahead?)=" .. tostring(a2) .. "," .. tostring(b2) .. "," .. tostring(c2))
      Coop.log("read owc.Shot=" .. tostring(p.owc.Shot) .. " usr owc.Shot=" .. tostring(usr.owc.Shot) ..
               " FireCounter=" .. tostring(p.oWeapCtrl.FireCounter))
    end
    -- Phase per field: 60 ticks each, aim the body at the player.
    local idx = math.floor((f - 100) / 60) + 1
    if f >= 100 and idx <= #fields then
      local field = fields[idx]
      if (f - 100) % 60 == 0 then
        shots = {}
        Coop.log("phase " .. field)
      end
      local d = usr.Pos - p.Pos
      p.Ang = V3D(0, math.deg(math.atan2(-d.x, -d.z)), 0)
      pcall(setf, p, field, 1)
      if (f - 100) % 60 == 59 then
        pcall(setf, p, field, 0)
        local parts = {}
        for n, c in pairs(shots) do parts[#parts + 1] = n .. "=" .. c end
        Coop.log("after " .. field .. ": shots " .. table.concat(parts, " ") .. " action=" .. tostring(p.Action))
      end
    end
  end
end

-- 'down': the local body drops to 0 life at cfg.downat ticks (downed/revive tests).
if cfg.exp == "down" and Coop.level ~= "levels/menu" then
  function Coop.dev()
    if Coop.frame == (cfg.downat or 200) then
      local usr = Game.UsrEntity(0)
      if usr then
        Coop.log("down test: " .. usr.Name .. " life " .. usr.Life .. " -> 0")
        usr.Invulnerable = 0
        usr.Life = 0
      end
    end
    if Coop.frame % 40 == 0 and Coop.frame > (cfg.downat or 200) then
      local parts = {}
      for _, n in ipairs(Coop.SQUAD) do
        local e = Game.GetEntity(n)
        if e then parts[#parts + 1] = n .. "=" .. string.format("%.0f", e.Life) .. ":" .. tostring(e.Action) end
      end
      Coop.log("lives " .. table.concat(parts, " ") .. " me=" .. tostring(Coop.localChar()))
    end
  end
end

-- 'cure' (host playing Rawlings): revive cfg.cure at cfg.cureat ticks after the client is
-- ready, the way a player's heal action does (Team.CurePlayer).
if cfg.exp == "cure" and Coop.isHost() and Coop.level ~= "levels/menu" then
  function Coop.dev()
    if not Coop.devReadyFrame then
      if CoopEnemies and CoopEnemies.catchupSent then Coop.devReadyFrame = Coop.frame end
      return
    end
    local f = Coop.frame - Coop.devReadyFrame
    local target = Game.GetEntity(cfg.cure or "Black")
    if f == (cfg.cureat or 300) and target then
      local usr = Game.UsrEntity(0)
      usr.Pos = target.Pos + V3D(80, 0, 0)
      local ok = Team.CurePlayer(usr, target)
      Coop.log("cure test: " .. usr.Name .. " heals " .. target.Name .. " (life " .. target.Life .. ") -> " .. tostring(ok))
    end
    if f > 0 and f % 40 == 0 and target then
      Coop.log("cure watch: " .. target.Name .. " life=" .. string.format("%.0f", target.Life) .. " act=" .. tostring(target.Action))
    end
  end
end

-- 'time': client uses Cole's time power for a while; host switches body (soul flight).
-- Both log the world time speed and the TimeSpeed of human-held bodies.
if cfg.exp == "time" and Coop.level ~= "levels/menu" then
  function Coop.dev()
    local usr = Game.UsrEntity(0)
    if not usr then return end
    local f = Coop.frame
    if Coop.isHost() then
      -- Count host ticks from the moment the client is in the level.
      if not Coop.devReadyFrame then
        if CoopEnemies and CoopEnemies.catchupSent then Coop.devReadyFrame = Coop.frame end
        return
      end
      f = f - Coop.devReadyFrame + 180
    end
    if Coop.isClient() then
      if f == 200 then Coop.log("time test: Cole power on") ThreadsCole.InfiniteLoopActive(usr) end
      if f == 300 then Coop.log("time test: Cole power off") ThreadsCole.InfiniteLoopInactive(usr) end
    elseif Coop.isHost() and f == 360 then
      local target = cfg.switchto or "Delgado"
      Coop.log("time test: host switches " .. usr.Name .. " -> " .. target .. " " .. tostring(Team.SwitchSoldier(usr.Name, target)))
    end
    if f % 20 == 0 and f >= 180 and f <= 440 then
      local parts = {}
      for name in pairs(Coop.owners) do
        local e = Game.GetEntity(name)
        if e then parts[#parts + 1] = name .. ":" .. string.format("%.2f", e.TimeSpeed or -1) end
      end
      Coop.log(string.format("time watch: world=%.3f %s cam=%s", Game.GetTimeSpeed(), table.concat(parts, " "),
        tostring(Game.GetCam(0))))
    end
  end
end

-- 'pitch': calibrate head-bone pitch against the view: look down, level, up and log the
-- head forward axis and the main camera's angles.
if cfg.exp == "pitch" and Coop.level ~= "levels/menu" then
  function Coop.dev()
    local usr = Game.UsrEntity(0)
    if not usr or Coop.frame < 100 then return end
    local phase = math.floor((Coop.frame - 100) / 40)
    local pitches = {30, 0, -30}
    local p = pitches[phase + 1]
    if not p then return end
    usr.IgnoreUsrControl = 1
    usr.ViewAng = V3D(p, usr.ViewAng.y, 0)
    if (Coop.frame - 100) % 40 == 30 then
      local node = (usr.Name == "Rawlings") and "Bip Rawllings Head" or ("Bip " .. usr.Name .. " Head")
      local ha = usr["NodeAngHierarchy_" .. node]
      local cam = Game.GetEntity(Game.GetCam(0))
      local fwd = ha and V3D(0, 0, 1):rot(ha)
      Coop.log(string.format("pitch test: ViewAng.x=%d headFwd=%s camAng=%s", p,
        fwd and string.format("%.2f,%.2f,%.2f", fwd.x, fwd.y, fwd.z) or "nil",
        cam and cam.camAng and Coop.v3(cam.camAng) or "nil"))
    end
  end
end

-- 'trigger' (host, or solo for vanilla reference runs): call cfg.trigger after cfg.trigat
-- ticks. A bare name is a map callback (called like the engine does); a dotted name such
-- as "MapInit.PlayConversation" is called with cfg.trigarg; cfg.trigargs (a list) overrides.
if cfg.exp == "trigger" and (Coop.isHost() or cfg.role == "solo") and Coop.level ~= "levels/menu"
    and (not cfg.level or Coop.level == "levels/" .. string.lower(cfg.level)) then
  local function resolve(name)
    if MapCallbacks and MapCallbacks[name] then return MapCallbacks[name], true end
    local ok, fn = pcall(loadstring("return " .. name))
    if ok and type(fn) == "function" then return fn, false end
  end
  function Coop.dev()
    -- Fire cfg.trigat ticks after the first client reported the level loaded (solo: after start).
    if not Coop.devReadyFrame then
      if cfg.role == "solo" or (CoopEnemies and CoopEnemies.catchupSent) then Coop.devReadyFrame = Coop.frame end
      return
    end
    -- Wait for a level-start scene to finish (a scene started on top of it breaks both).
    if Scene and Scene.IsPlaying then Coop.devReadyFrame = Coop.frame return end
    if Coop.frame == Coop.devReadyFrame + (cfg.trigat or 100) then
      local fn, isCallback = resolve(cfg.trigger)
      Coop.log("trigger: " .. cfg.trigger .. (fn and "" or " (not found)"))
      if not fn then return end
      local ok, err
      if cfg.trigargs then ok, err = pcall(fn, unpack(cfg.trigargs))
      elseif isCallback then ok, err = pcall(fn, cfg.trigger, 0, nil)
      else ok, err = pcall(fn, cfg.trigarg) end
      if not ok then Coop.log("trigger error: " .. tostring(err)) end
    end
  end
end

-- 'menutest': open co-op menu screens by script for screenshots (no input needed).
--   root: Co-op menu; host: host setup; lobby: create a session and show the lobby;
--   join: join screen. The main menu is shown first for MENU_WAIT network ticks.
if cfg.menutest and Coop.level == "levels/menu" then
  local MENU_WAIT = cfg.menuwait or 200
  function Coop.dev()
    if Coop.frame == MENU_WAIT and CoopMenu then
      Coop.log("menutest " .. cfg.menutest)
      if cfg.menutest == "main" then MainMenu.MainMenu()
      elseif cfg.menutest == "root" then CoopMenu.Root()
      elseif cfg.menutest == "host" then CoopMenu.HostSetup()
      elseif cfg.menutest == "join" then CoopMenu.JoinSetup()
      elseif cfg.menutest == "lobby" then CoopMenu.HostSetup(); CoopMenu.NextLevel(); CoopMenu.CreateSession()
      elseif cfg.menutest == "flow" then
        -- Whole lobby flow: host continues the co-op save (or starts cfg.menulevel), the
        -- client joins 127.0.0.1; both get ready and the host starts once everyone is.
        CoopMenu.HostSetup()
        if CoopMenu.saved and not cfg.menunew then
          CoopMenu.ContinueSession()
        else
          CoopMenu.levelIndex = CoopMenu.indexOf(cfg.menulevel or "Alk_Desert") or 1
          CoopMenu.CreateSession()
        end
        CoopMenu.ToggleReady()
      elseif cfg.menutest == "flowjoin" then
        CoopMenu.JoinSetup()
        CoopMenu.Connect()
      end
    end
    if cfg.menutest == "flowjoin" and Coop.frame > MENU_WAIT and cfg.myId and CoopMenu.screen == "lobby" then
      local me = CoopMenu.seatOf(CoopMenu.myPeer())
      if me and not me.ready and Coop.frame % 20 == 0 then CoopMenu.ToggleReady() end
    end
    if cfg.menutest == "flow" and Coop.frame > MENU_WAIT and #CoopMenu.seats >= (cfg.waitpeers or 1) + 1 and
       CoopMenu.allReady() and CoopMenu.screen == "lobby" then
      CoopMenu.Start()
    end
  end
end

-- 'savetest': the host reaches a checkpoint at savetest ticks, then loads it 10 s later
-- (both once per run); the client should reload with the host's vars.
if cfg.savetest and Coop.level ~= "levels/menu" then
  local prev = Coop.dev
  function Coop.dev()
    if prev then prev() end
    if not Coop.isHost() then return end
    if Coop.frame == cfg.savetest and not cfg.savedone then
      Game.CreateSaveVar("CoopSaveTest", "")
      Game.SetSaveVar("CoopSaveTest", "marker-" .. Coop.frame)
      -- A real spawn point of this level (Team.CreateMapSpawnPlayers needs one).
      local best = 0
      for _, pos in ipairs(MapSpawnPlayers.Positions or {}) do
        if pos[20] and tonumber(pos[20][2]) and pos[20][2] > best then best = pos[20][2] end
      end
      Coop.log("savetest: spawn point " .. best)
      SaveGame.AutoSaveWaypoint(best)
      cfg.savedone = true
      Coop.log("savetest: checkpoint")
    elseif Coop.frame == cfg.savetest + 200 and cfg.savedone and not cfg.loaddone then
      cfg.loaddone = true
      Coop.rearm()
      Coop.log("savetest: load checkpoint")
      SaveGame.LoadWaypoint()
    end
  end
end
if cfg.savetest and Coop.level ~= "levels/menu" then
  Coop.log("savetest: var CoopSaveTest=" .. tostring(Game.GetSaveVar("CoopSaveTest")) ..
           " level=" .. tostring(Game.GetSaveVar("LevelName")))
end

-- Experiment: is OnRenderDebug called every frame, independent of game time speed?
if cfg.exp == "framehook" and Coop.level ~= "levels/menu" then
  local D = {renders = 0, ticks = 0, t0 = Net.CoopTime(), phase = "normal"}
  Coop.devFrame = D
  function Coop.devOnRender()
    D.renders = D.renders + 1
  end
  Game.Set("OnRenderDebug", "Coop.devOnRender")
  function Coop.dev()
    D.ticks = D.ticks + 1
    local t = Net.CoopTime() - D.t0
    if D.phase == "normal" and t > 10 then
      Coop.log(string.format("normal 10s: renders=%d ticks=%d gametime=%.2f", D.renders, D.ticks, Game.GetTime()))
      D.renders, D.ticks, D.phase, D.t1 = 0, 0, "slow", Net.CoopTime()
      Game.SetTimeSpeed(0.05)
    end
  end
  -- The scheduler stalls under slow time, so check the slow phase from the render hook too.
  local orig = Coop.devOnRender
  function Coop.devOnRender()
    orig()
    if D.phase == "slow" and Net.CoopTime() - D.t1 > 10 then
      Coop.log(string.format("slow 10s: renders=%d ticks=%d gametime=%.2f", D.renders, D.ticks, Game.GetTime()))
      D.phase = "done"
      Game.SetTimeSpeed(1)
    end
  end
end

-- 'fcam': units of FCam.Ang. A test FCam copies the main camera's position and is given
-- the main camera's angles as degrees, then as radians; the engine's resulting view
-- (camAng read back) shows which one matches.
if cfg.exp == "fcam" and Coop.level ~= "levels/menu" then
  function Coop.dev()
    local main = Game.GetEntity("MainCam")
    if not main or not main.camAng or Coop.frame < 100 then return end
    local phase = math.floor((Coop.frame - 100) / 60)
    local modes = {"deg", "rad", "deg_yaw10", "rad_yaw10"}
    local mode = modes[phase + 1]
    local cam = Game.GetEntity("CoopTestCam") or Game.CreateEntity("CoopTestCam", "FCam")
    if not mode then
      if Game.GetCam(0) ~= "MainCam" then Game.SetCam(0, "MainCam") end
      return
    end
    if not Coop.devMainAng then Coop.devMainAng, Coop.devMainPos = main.camAng, main.camPos end
    local a = Coop.devMainAng
    cam.Pos = Coop.devMainPos
    local add = string.find(mode, "yaw10") and 10 or 0
    if string.find(mode, "rad") then
      cam.Ang = V3D(math.rad(a.x), math.rad(a.y + add), math.rad(a.z))
    else
      cam.Ang = V3D(a.x, a.y + add, a.z)
    end
    if Game.GetCam(0) ~= "CoopTestCam" then Game.SetCam(0, "CoopTestCam") end
    if (Coop.frame - 100) % 60 == 40 then
      local f1 = V3D(0, 0, 1):rot(a)
      local f2 = cam.camAng and V3D(0, 0, 1):rot(cam.camAng)
      Coop.log(string.format("fcam %s: main camAng=%s ang=%s set=%s readback=%s camAng=%s fwdMain=%.2f,%.2f,%.2f fwdTest=%s fov=%s/%s",
        mode, Coop.v3(a), tostring(a.x) .. "," .. tostring(a.y), Coop.v3(cam.Ang), tostring(cam.Ang.x) .. "," .. tostring(cam.Ang.y),
        cam.camAng and Coop.v3(cam.camAng) or "nil", f1.x, f1.y, f1.z,
        f2 and string.format("%.2f,%.2f,%.2f", f2.x, f2.y, f2.z) or "nil", tostring(main.Fov), tostring(cam.Fov)))
    end
  end
end

-- 'hide': how to stop rendering one character (cutscene POV from inside its head). Faces a
-- teammate, then hides its head node (bShowNode_), then the whole object (bObjectVisible),
-- then shows it again; the video shows which works.
if cfg.exp == "hide" and Coop.level ~= "levels/menu" then
  function Coop.dev()
    local usr = Game.UsrEntity(0)
    local target = Game.GetEntity(Coop.devHide or "")
    if not target then
      for _, n in ipairs({"Delgado", "Church", "Black", "Cole", "Rawlings"}) do
        local e = Game.GetEntity(n)
        if e and (not usr or usr.Name ~= n) then target = e Coop.devHide = n break end
      end
    end
    if not target or not usr or Coop.frame < 100 then return end
    local d = target.Pos - usr.Pos
    usr.IgnoreUsrControl = 1
    usr.Ang = V3D(0, math.deg(math.atan2(-d.x, -d.z)), 0)
    local node = "bShowNode_Bip " .. target.Name .. " Head"
    local function try(k, v)
      local ok, err = pcall(function() target[k] = v end)
      local ok2, rb = pcall(function() return target[k] end)
      Coop.log(string.format("hide frame %d %s=%s -> %s %s readback %s", Coop.frame, k, tostring(v), tostring(ok), tostring(err), tostring(rb)))
    end
    if Coop.frame == 140 then try(node, false) end
    if Coop.frame == 200 then try(node, true) try("bObjectVisible", false) end
    if Coop.frame == 260 then try("bObjectVisible", true) end
  end
end

-- cfg.qtemode = 2: the engine presses QTE keys itself (the game's own "QTE" cheat), so a
-- bot can pass scene QTEs.
if cfg.qtemode then Game.Set("QTEMode", cfg.qtemode) end

-- Mark scene starts in the log ("scene start <class>"), in vanilla reference runs too, so
-- tools/scene_compare.ps1 can line up the recordings. Held or dropped starts return false.
if Scene and Scene.Play and not Coop.devSceneMark then
  Coop.devSceneMark = true
  local orig = Scene.Play
  Scene.Play = function(class, ...)
    local r = {orig(class, ...)}
    if r[1] ~= false then Coop.log("scene start " .. tostring(class)) end
    return unpack(r)
  end
end

-- 'bones': can Lua pose a body's bones, and how are the first-person arms' bones named?
-- (FP scenes animate only the scene owner's arms; other players see a body that cannot
-- play that animation. If bone angles are writable, the arms' motion can be copied.)
--   frames 100: probe a teammate's arm bones (read)
--   120-260:   write NT_NodeAng_ on its right upper arm; 260-400: write NodeAng_
--   400:       start TheTrap (rom_palace_02); 470: probe the FP actor's bones
if cfg.exp == "bones" and Coop.level == "levels/rom_palace_02" then
  local PARTS = {"Head", "Neck", "Spine", "Spine1", "Pelvis", "R Clavicle", "R UpperArm", "R Forearm", "R Hand",
                 "L Clavicle", "L UpperArm", "L Forearm", "L Hand", "R Finger0", "R Thigh", "R Calf"}
  local function probe(e, prefixes, tag)
    for _, pre in ipairs(prefixes) do
      local found = {}
      for _, part in ipairs(PARTS) do
        local node = pre .. " " .. part
        local ok, a = pcall(function() return e["NodeAng_" .. node] end)
        local ok2, h = pcall(function() return e["NodeAngHierarchy_" .. node] end)
        if (ok and a) or (ok2 and h) then
          found[#found + 1] = string.format("%s[%s|%s]", part, ok and a and Coop.v3(a) or "-", ok2 and h and Coop.v3(h) or "-")
        end
      end
      Coop.log(string.format("bones %s %s '%s': %s", tag, e.Name, pre, #found > 0 and table.concat(found, " ") or "none"))
    end
  end
  function Coop.dev()
    local usr = Game.UsrEntity(0)
    local t = Game.GetEntity(Coop.devBoneT or "")
    if not t and usr then
      for _, n in ipairs({"Church", "Black", "Cole", "Rawlings", "Delgado"}) do
        local e = Game.GetEntity(n)
        if e and n ~= usr.Name then t = e Coop.devBoneT = n break end
      end
    end
    local f = Coop.frame
    if t and f >= 100 and f < 400 and usr then
      local d = t.Pos - usr.Pos
      usr.IgnoreUsrControl = 1
      usr.Ang = V3D(0, math.deg(math.atan2(-d.x, -d.z)), 0)
      if t.oAI then t.oAI.bEnable = false end
    end
    if t and f == 100 then probe(t, {"Bip " .. t.Name, "Bip01", "Bip"}, "body") end
    -- Write variants, 70 ticks each, on the right upper arm (hand position shows the effect):
    --   1 bExtNodeDisabled_ + NodeAng_   2 bExtNodeDisabled_ + NT_NodeAng_
    --   3 NodeAngHierarchy_ (world)      4 bShowNode_ = false (sanity: node props work)
    if t and f >= 120 and f < 400 then
      local node = "Bip " .. t.Name .. " R UpperArm"
      local phase = math.floor((f - 120) / 70) + 1
      local v = V3D(0, 0, 90)
      local ok, err = true, nil
      if phase == 1 then
        ok, err = pcall(function() t["bExtNodeDisabled_" .. node] = true; t["NodeAng_" .. node] = v end)
      elseif phase == 2 then
        ok, err = pcall(function() t["bExtNodeDisabled_" .. node] = true; t["NT_NodeAng_" .. node] = v end)
      elseif phase == 3 then
        ok, err = pcall(function() t["bExtNodeDisabled_" .. node] = false; t["NodeAngHierarchy_" .. node] = v end)
      else
        ok, err = pcall(function() t["bShowNode_" .. node] = false end)
      end
      if (f - 120) % 70 == 5 or (f - 120) % 70 == 60 then
        local h = t["NodePosHierarchy_Bip " .. t.Name .. " R Hand"]
        local la = t["NodeAng_" .. node]
        local ok3, ext = pcall(function() return t["bExtNodeDisabled_" .. node] end)
        Coop.log(string.format("bones phase %d ok=%s err=%s hand=%s local=%s ext=%s", phase, tostring(ok), tostring(err),
          h and Coop.v3(h) or "-", la and Coop.v3(la) or "-", tostring(ext)))
      end
    end
    if t and f == 400 then pcall(function() t["bShowNode_Bip " .. t.Name .. " R UpperArm"] = true end) end
    if f == 400 then
      if usr then usr.IgnoreUsrControl = 0 end
      Coop.log("bones: start TheTrap")
      if MapCallbacks and MapCallbacks.AreaTrigger_3 then pcall(MapCallbacks.AreaTrigger_3, "AreaTrigger_3", 0, nil) end
    end
    if f == 470 or f == 600 then
      local fp = Game.GetEntity("TheTrapFP_Delgado")
      if fp then probe(fp, {"Bip Delgado", "Bip01", "Bip", "FP Delgado", "Bip FP_Delgado", "Bip FP Delgado"}, "fp")
      else Coop.log("bones: no FP actor entity") end
    end
  end
end

-- 'bones2': per-frame bone writes on the head of the nearest teammate, close up, 4 s each:
--   A none, B NodeAngHierarchy_ (world), C NodeAng_ (local), D NT_NodeAng_, E bShowNode_ false,
--   F bExtNodeDisabled_ + NodeAngHierarchy_. Log the head's world position per phase.
if cfg.exp == "bones2" and Coop.level ~= "levels/menu" then
  local PH = {"none", "world", "local", "nt", "hide", "ext+world"}
  function Coop.dev()
    local usr = Game.UsrEntity(0)
    if not usr or Coop.frame < 100 then return end
    if not Coop.devT then
      local best, bd
      for _, n in ipairs(Coop.SQUAD) do
        local e = Game.GetEntity(n)
        if e and n ~= usr.Name then
          local d = e.Pos - usr.Pos
          local dist = math.sqrt(d.x * d.x + d.z * d.z)
          if not bd or dist < bd then best, bd = e, dist end
        end
      end
      if not best then return end
      Coop.devT = best.Name
      Coop.devT0 = Net.CoopTime()
      Coop.log("bones2 target " .. best.Name)
    end
    local t = Game.GetEntity(Coop.devT)
    if t.oAI then t.oAI.bEnable = false end
    -- park the target 150 units in front of the player, facing the player
    local yaw = usr.Ang.y
    local fwd = V3D(-math.sin(math.rad(yaw)), 0, -math.cos(math.rad(yaw)))
    t.Pos = usr.Pos + V3D(fwd.x * 150, 0, fwd.z * 150)
    t.Ang = V3D(0, yaw + 180, 0)
    usr.IgnoreUsrControl = 1
  end
  function Coop.devFrame(dt)
    local t = Game.GetEntity(Coop.devT or "")
    if not t then return end
    local k = math.floor((Net.CoopTime() - Coop.devT0) / 4) + 1
    local ph = PH[k]
    local node = "Bip " .. (t.Name == "Rawlings" and "Rawllings" or t.Name) .. " Head"
    if ph ~= Coop.devPh then
      Coop.devPh = ph
      pcall(function() t["bShowNode_" .. node] = true; t["bExtNodeDisabled_" .. node] = false end)
      local h = t["NodePosHierarchy_" .. node]
      Coop.log("bones2 phase " .. tostring(ph) .. " head=" .. (h and Coop.v3(h) or "-"))
    end
    local v = V3D(0, 0, 90)
    if ph == "world" then pcall(function() t["NodeAngHierarchy_" .. node] = v end)
    elseif ph == "local" then pcall(function() t["NodeAng_" .. node] = v end)
    elseif ph == "nt" then pcall(function() t["NT_NodeAng_" .. node] = v end)
    elseif ph == "hide" then pcall(function() t["bShowNode_" .. node] = false end)
    elseif ph == "ext+world" then pcall(function() t["bExtNodeDisabled_" .. node] = true; t["NodeAngHierarchy_" .. node] = v end)
    end
  end
end

-- 'claimtest' (host): stand next to a character-only object nobody holds the character of
-- (cfg.gate, default TriggerTheAbyss in rom_palace_01, Church-only) and let coop_claim.lua
-- ask for a take-over, then hand it to the AI after the timeout.
if cfg.exp == "claimtest" and Coop.isHost() and Coop.level ~= "levels/menu" then
  function Coop.dev()
    if not Coop.devReadyFrame then
      if CoopEnemies and CoopEnemies.catchupSent then Coop.devReadyFrame = Coop.frame end
      return
    end
    if Coop.frame == Coop.devReadyFrame + 40 then
      local o = Game.GetEntity(cfg.gate or "TriggerTheAbyss")
      local usr = Game.UsrEntity(0)
      if o and usr then
        o.bActive = true
        o.bArrowCanUse = true
        usr.Pos = o.Pos + V3D(250, 0, 0)
        for _, n in ipairs(Coop.SQUAD) do
          local e = Game.GetEntity(n)
          if e then e.Invulnerable = 1 end
        end
        Coop.log("claimtest: host moved next to " .. o.Name .. " at " .. Coop.v3(o.Pos) .. ", squad invulnerable")
      else
        Coop.log("claimtest: no gate " .. tostring(cfg.gate))
      end
    end
  end
end

-- 'lanlog': log what LAN discovery hears (Net.CoopDiscover) every 2 s in the menu.
if cfg.lanlog and Coop.level == "levels/menu" then
  local prev = Coop.dev
  function Coop.dev()
    if prev then prev() end
    if Coop.frame % 40 == 0 and Net.CoopDiscover then Coop.log("lan heard: " .. tostring(Net.CoopDiscover())) end
  end
end

-- 'skipscenes': the host skips every scene (tests that need gameplay after a level's intro).
if cfg.skipscenes and Coop.level ~= "levels/menu" then
  local prevSkip = Coop.dev
  function Coop.dev()
    if prevSkip then prevSkip() end
    if Coop.isHost() and Scene and Scene.IsPlaying and Coop.frame % 10 == 0 and CoopEnemies and CoopEnemies.hostAbort then
      Coop.log("skipscenes: skip " .. tostring(Scene.SceneName))
      pcall(CoopEnemies.hostAbort)
    end
  end
end
