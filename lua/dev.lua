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

-- 'guard': stand, fire at the nearest enemy, never die (story line tests: the waves and
-- steps of a line run with nobody at the controls).
function Coop.botGuard()
  if Coop.level == "levels/menu" then return end
  local usr = Game.UsrEntity(0)
  if not usr or Coop.frame < 40 then return end
  usr.Invulnerable = 1
  if usr.Life < 50 then usr.Life = 100 end
  -- G3: the hacker's place is at the console.
  local g3 = CoopSplits and CoopSplits.G3
  local atConsole = g3 and g3.hacking and MapInit.ColePos
  if atConsole then
    local d = usr.Pos - MapInit.ColePos
    if d.x * d.x + d.z * d.z > 100 * 100 then
      usr.Pos = MapInit.ColePos
      if not Coop.guardAtConsole then Coop.log("guard: at the console") end
      Coop.guardAtConsole = true
    end
  end
  -- A downed squad member is revived (a player would walk over and press use), not while
  -- the console needs this player.
  if not atConsole and Coop.frame % 90 == 0 and Team and Team.CurePlayer then
    for _, name in ipairs(Coop.SQUAD) do
      local m = Game.GetEntity(name)
      if m and m ~= usr and m.bActive and (m.Life or 1) <= 0 and Team.CanCure(m) then
        usr.Pos = m.Pos + V3D(80, 0, 0)
        Coop.log("guard: revives " .. name .. ": " .. tostring(Team.CurePlayer(usr, m)))
        break
      end
    end
  end
  local p, best, bestD = usr.Pos, nil, nil
  local e = Game.GetFirst()
  while e ~= nil do
    if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive then
      local d = e.Pos - p
      local dist = math.sqrt(d.x * d.x + d.z * d.z)
      if dist < 2500 and (not bestD or dist < bestD) then best, bestD = e, dist end
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  if not best then
    if Coop.guardFiring then usr.IgnoreUsrControl, usr.owc.Shot, Coop.guardFiring = 0, 0, nil end
    return
  end
  Coop.guardFiring = true
  usr.IgnoreUsrControl = 1
  local d = best.Pos - p
  local yaw = math.deg(math.atan2(-d.x, -d.z))
  usr.Ang = V3D(0, yaw, 0)
  usr.ViewAng = V3D(0, yaw, 0)
  usr.InCtrl_Walk = 0
  usr.owc.Shot = (Coop.frame % 30 < 20) and 1 or 0
  if Coop.frame % 120 == 0 then
    Coop.log(string.format("guard fires at %s %.0f units, life %.0f", best.Name, bestD, best.Life))
  end
end

if cfg.bot == "guard" then Coop.bot = Coop.botGuard end

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

-- 'pitch': calibrate head-bone pitch against the view: ViewAng.x 30, 0, -30 (positive looks
-- up, the lighttest of 2026-10-20 showed) and log the head forward axis and camera angles.
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
-- Once per session: the host rewrites cfg.level on every level change, so trigfired (kept in the
-- boot line) stops the next level from firing a scene that is not there.
if cfg.exp == "trigger" and (Coop.isHost() or cfg.role == "solo") and Coop.level ~= "levels/menu"
    and not cfg.trigfired and (not cfg.level or Coop.level == "levels/" .. string.lower(cfg.level)) then
  local function resolve(name)
    if MapCallbacks and MapCallbacks[name] then return MapCallbacks[name], true end
    local ok, fn = pcall(loadstring("return " .. name))
    if ok and type(fn) == "function" then return fn, false end
  end
  function Coop.dev()
    if Coop.devTriggered then return end   -- once (a scene it starts must not start again)
    -- Fire cfg.trigat ticks after the first client reported the level loaded (solo: after start).
    if not Coop.devReadyFrame then
      if cfg.role == "solo" or cfg.waitpeers == 0 or (CoopEnemies and CoopEnemies.catchupSent) then Coop.devReadyFrame = Coop.frame end
      return
    end
    -- Wait for a level-start scene to finish (a scene started on top of it breaks both).
    if Scene and Scene.IsPlaying then Coop.devReadyFrame = Coop.frame return end
    if Coop.frame == Coop.devReadyFrame + (cfg.trigat or 100) then
      Coop.devTriggered = true
      cfg.trigfired = true
      Coop.rearm()
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

-- 'gamelang': switch the game's own texts in the menu (e.g. 'German'), as the language screen
-- does; with lang='en' this shows the English mod next to Latin-script game strings.
if cfg.gamelang and Coop.level == "levels/menu" then
  Game.SetLanguage(cfg.gamelang)
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
      elseif cfg.menutest == "lobby" then
        CoopMenu.HostSetup(); CoopMenu.NextLevel(); CoopMenu.CreateSession()
        if cfg.menuready then CoopMenu.ToggleReady() end
        for _ = 1, cfg.menup2 or 0 do CoopMenu.NextP2() end
        -- menufake=n: n more seats shown (layout of a full lobby), long nicknames, SMOD on all.
        for k = 1, cfg.menufake or 0 do
          local chars = {"Black", "Church", "Cole"}
          CoopMenu.seats[#CoopMenu.seats + 1] = {peer = k, char = chars[k], ready = k % 2 == 1, nick = "Longnickname" .. k .. "xyz"}
          CoopMenu.smodPeers[k] = true
        end
        if cfg.menufake then CoopMenu.refreshLobby() end
        for k = 0, 4 do
          local it = Scorer.GetItem(0, "CoopLine" .. k)
          if it then Coop.log(string.format("menutest: CoopLine%d Y=%s Pos=%s,%s", k, tostring(it.Y), tostring(it.Pos and it.Pos.x), tostring(it.Pos and it.Pos.y))) end
        end
        for _, nm in ipairs({"Itm1", "DoExit", "Title"}) do
          local it = Scorer.GetItem(0, nm)
          if it then Coop.log(string.format("menutest: %s Y=%s", nm, tostring(it.Y))) end
        end
      elseif cfg.menutest == "settings" then CoopMenu.HostSetup(); CoopMenu.CreateSession(); CoopMenu.Settings()
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
    if cfg.menufake and Coop.frame == MENU_WAIT + 50 then
      for k = 0, 4 do
        local it = Scorer.GetItem(0, "CoopLine" .. k)
        if it then Coop.log(string.format("menutest later: CoopLine%d Y=%s Pos.y=%s", k, tostring(it.Y), tostring(it.Pos and it.Pos.y))) end
      end
    end
    -- 'menufocus': move the focus over the first N items, 40 ticks each (the focused item
    -- is drawn wider: every line has to fit while it has the focus).
    if cfg.menufocus and Coop.frame > MENU_WAIT and (Coop.frame - MENU_WAIT) % 40 == 0 then
      local i = (Coop.frame - MENU_WAIT) / 40 % cfg.menufocus + 1
      if Scorer.GetItem(0, "Itm" .. i) then Scorer.SetDefault(0, "Itm" .. i); Coop.log("menufocus Itm" .. i) end
    end
    -- 'showflow' (host) / 'showjoin' (client): the lobby flow slowly, for a showcase video:
    -- one step every cfg.showgap ticks (default 45).
    local gap = cfg.showgap or 45
    local k = (Coop.frame - MENU_WAIT) / gap
    if cfg.menutest == "showflow" and k >= 0 and k == math.floor(k) then
      if k == 0 then CoopMenu.HostSetup()
      elseif k == 1 then CoopMenu.levelIndex = CoopMenu.indexOf(cfg.menulevel or "Alk_Desert") or 1; CoopMenu.CreateSession()
      elseif k == 3 then CoopMenu.Settings()
      elseif k == 4 then CoopMenu.CycleQTE()
      elseif k == 5 then CoopMenu.Lobby()
      elseif k == 6 then CoopMenu.ToggleReady()
      end
    end
    if cfg.menutest == "showflow" and k > 7 and CoopMenu.screen == "lobby" and CoopMenu.sub ~= "settings" and
       #CoopMenu.seats >= 2 and CoopMenu.allReady() and not Coop.devShowStarted then
      Coop.devShowStarted = Coop.frame
    end
    if Coop.devShowStarted and Coop.frame == Coop.devShowStarted + gap then CoopMenu.Start() end
    if cfg.menutest == "showjoin" and k >= 0 and k == math.floor(k) then
      if k == 0 then CoopMenu.JoinSetup()
      elseif k == 1 then CoopMenu.Connect()
      elseif k == 3 then local me = CoopMenu.seatOf(CoopMenu.myPeer()); if me and not me.ready then CoopMenu.ToggleReady() end
      end
    end
    if cfg.menutest == "flowjoin" and Coop.frame > MENU_WAIT and cfg.myId and CoopMenu.screen == "lobby" then
      local me = CoopMenu.seatOf(CoopMenu.myPeer())
      if me and not me.ready and Coop.frame % 20 == 0 then CoopMenu.ToggleReady() end
      -- menup2=n: this machine's second player (split screen), n steps through the list.
      if me and cfg.menup2 and not Coop.devP2Set and Coop.frame % 20 == 10 then
        Coop.devP2Set = true
        for _ = 1, cfg.menup2 do CoopMenu.NextP2() end
      end
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

-- 'trigseq': story steps one after another (host), e.g. the G8 test:
--   trigseq={{'MapCallbacks.TriggerEscalada_0',100,'Church','TriggerEscalada'},{'MapCallbacks.TriggerBloodWar_3',900},...}
-- each item: function path, ticks after the previous step, then its arguments.
if cfg.trigseq and Coop.isHost() and Coop.level ~= "levels/menu" then
  local prevSeq = Coop.dev
  local step, nextAt = 1, nil
  function Coop.dev()
    if prevSeq then prevSeq() end
    local item = cfg.trigseq[step]
    if not item then return end
    if Scene and Scene.IsPlaying and not cfg.seqinscene then return end
    nextAt = nextAt or (Coop.frame + (item[2] or 100))
    if Coop.frame < nextAt then return end
    step, nextAt = step + 1, nil
    local ok, fn = pcall(loadstring("return " .. item[1]))
    Coop.log("trigseq " .. (step - 1) .. ": " .. item[1] .. (ok and fn and "" or " (not found)"))
    if ok and type(fn) == "function" then
      local r, err = pcall(fn, unpack(item, 3))
      if not r then Coop.log("trigseq error: " .. tostring(err)) end
    end
  end
end

-- 'menuprobe': log the main menu camera and props (for placing a character in the menu).
if cfg.menuprobe and Coop.level == "levels/menu" then
  local prevProbe = Coop.dev
  function Coop.dev()
    if prevProbe then prevProbe() end
    if Coop.frame ~= 60 then return end
    for _, n in ipairs({"MainMenuCamera", "CAMERA", "PIEL"}) do
      local e = Game.GetEntity(n)
      if e then
        Coop.log(string.format("menuprobe %s pos=%s ang=%s", n, Coop.v3(e.Pos), Coop.v3(e.Ang)))
        if e.camPos then Coop.log("menuprobe " .. n .. " camPos=" .. Coop.v3(e.camPos) .. " camAng=" .. Coop.v3(e.camAng)) end
      end
    end
  end
end

-- 'charprobe': log the squad's bodies (exists, active, life, place) after the level start.
if cfg.charprobe and Coop.level ~= "levels/menu" then
  local prevChar = Coop.dev
  function Coop.dev()
    if prevChar then prevChar() end
    if Coop.frame ~= 80 then return end
    for _, n in ipairs({"Jones", "Cole", "Delgado", "Church", "Rawlings", "Black", "Ross"}) do
      local e = Game.GetEntity(n)
      if e then
        Coop.log(string.format("charprobe %s active=%s Active=%s life=%s pos=%s", n, tostring(e.bActive), tostring(e.Active), tostring(e.Life), Coop.v3(e.Pos)))
      else
        Coop.log("charprobe " .. n .. " missing")
      end
    end
  end
end

-- 'trioprobe': create Jones next to the player (CoopPatrol.createBody) and switch into him.
if cfg.trioprobe and Coop.level ~= "levels/menu" then
  local prevTrio = Coop.dev
  function Coop.dev()
    if prevTrio then prevTrio() end
    local usr = Game.UsrEntity(0)
    if Coop.frame == 100 and usr and CoopPatrol then
      local e = CoopPatrol.createBody("Jones", usr.Pos + V3D(150, 0, 0), usr.Ang.y)
      Coop.log("trioprobe: Jones " .. tostring(e ~= nil))
    elseif Coop.frame == 200 and usr then
      Coop.log("trioprobe: switch " .. tostring(Team.SwitchSoldier(usr.Name, "Jones")))
    elseif Coop.frame == 400 then
      local j = Game.GetEntity("Jones")
      Coop.log("trioprobe: me=" .. tostring(Coop.localChar()) .. " jones life=" .. tostring(j and j.Life) ..
               " pos=" .. tostring(j and Coop.v3(j.Pos)) .. " fp=" .. tostring(j and j.oFPSEntity ~= nil))
    end
  end
end

-- 'langprobe': log game strings by key (cfg.langkeys = {'Key1', ...}) in the menu.
if cfg.langprobe and Coop.level == "levels/menu" then
  local prevLang = Coop.dev
  function Coop.dev()
    if prevLang then prevLang() end
    if Coop.frame ~= 40 then return end
    for i = 0, 8 do
      local k = "Extra_" .. i .. "_Main_Title"
      Coop.log("langprobe " .. k .. " = " .. tostring(Game.GetLangStr(k)))
    end
  end
end

-- 'spriteprobe': three copies of a picture with different Scale.y (how sprites are sized).
if cfg.spriteprobe and Coop.level == "levels/menu" then
  local prevSpr = Coop.dev
  function Coop.dev()
    if prevSpr then prevSpr() end
    if Coop.frame ~= 60 then return end
    for i, sy in ipairs({100, 50, 30}) do
      local it = Scorer.NewItem(0, "SprProbe" .. i, "Sprite")
      it.Unit = 1
      it.File = "2D/Menu/Extra_2_Picture_0.bmp"
      it.Pos = V2D(40 + (i - 1) * 140, 40)
      it.Scale = V2D(100, sy)
      it.Pivot = V2D(0, 0)
      it.Color = Color(255, 255, 255, 255)
    end
    Coop.log("spriteprobe placed")
  end
end

-- 'chain': one story step per level, run once when that level has been up for the given ticks
-- (host): chain={{'Cru_River',300,'Scene.PlayFP','BridgeCollapses'},{'Cru_Labyrinth',900,'SaveGame.LoadLevel','Cru_Sewers'}}
if cfg.chain and Coop.isHost() and Coop.level ~= "levels/menu" then
  local prevChain = Coop.dev
  local item
  for _, it in ipairs(cfg.chain) do
    if Coop.level == "levels/" .. string.lower(it[1]) then item = it end
  end
  function Coop.dev()
    if prevChain then prevChain() end
    if not item or Coop.frame ~= (item[2] or 300) then return end
    local ok, fn = pcall(loadstring("return " .. item[3]))
    Coop.log("chain: " .. item[1] .. " -> " .. item[3] .. "(" .. tostring(item[4]) .. ")")
    if ok and type(fn) == "function" then
      local r, err = pcall(fn, item[4])
      if not r then Coop.log("chain error: " .. tostring(err)) end
    end
  end
end

-- 'pausetest' (host): open the pause menu at that tick, log whether game time goes on, close it.
if cfg.pausetest and Coop.level ~= "levels/menu" then
  local prevPause = Coop.dev
  function Coop.dev()
    if prevPause then prevPause() end
    if Coop.frame == cfg.pausetest then
      Coop.devPauseT = Game.GetTime()
      pcall(Menu.Init)
      Coop.log("pausetest: menu open, time speed " .. tostring(Game.GetTimeSpeed()))
    elseif Coop.frame == cfg.pausetest + 100 and Coop.devPauseT then
      Coop.log(string.format("pausetest: game time went on %.1f s in 5 s of menu, speed %s",
        Game.GetTime() - Coop.devPauseT, tostring(Game.GetTimeSpeed())))
      pcall(Menu.BackToGame, 0, "")
    end
  end
end

-- 'skiptest' (every machine): 3 s into the first scene, press skip once.
if cfg.skiptest and Coop.level ~= "levels/menu" then
  local prevSkipT = Coop.dev
  function Coop.dev()
    if prevSkipT then prevSkipT() end
    if Coop.devSkipped or not (Scene and Scene.IsPlaying) then return end
    Coop.devSceneSeen = Coop.devSceneSeen or Coop.frame
    if Coop.frame - Coop.devSceneSeen == 60 + (Coop.isHost() and 0 or 60) then
      Coop.devSkipped = true
      Coop.log("skiptest: skip pressed in " .. tostring(Scene.SceneName))
      pcall(Scene.AbortScene)
    end
  end
end

-- 'campaignstep' (host): after that many ticks in each level, end it the real way
-- (SaveGame.NewLevelNow to the next campaign level), through to Sum_End.
if cfg.campaignstep and Coop.isHost() and Coop.level ~= "levels/menu" then
  local ORDER = {"Alk_Desert", "Alk_Tomb", "Alk_Bunker_00", "Alk_City", "Alk_Bunker_01", "Alk_Final",
    "WWII_BigGates", "WWII_PillBoxes", "WWII_Mosque", "WWII_Mosque_Inside", "WWII_Vigil", "WWII_Vigil_Inside",
    "WWII_Brandenburg", "Cru_River", "Cru_Labyrinth", "Cru_Sewers", "Cru_Keep", "Cru_Catacomb", "Cru_Chapel",
    "Rom_Outskirts", "Rom_Caldarium", "Rom_Tepidarium", "Rom_Palace_01", "Rom_Palace_02", "Rom_Coloseum",
    "Rom_Chamber", "Sum_Ziggurat_01", "Sum_Ziggurat_02", "Sum_Ziggurat_03", "Sum_Ziggurat_04",
    "Sum_Ziggurat_Meat", "Sum_Ziggurat_05", "Sum_End"}
  local nextLevel
  for i, l in ipairs(ORDER) do
    if Coop.level == "levels/" .. string.lower(l) then nextLevel = ORDER[i + 1] end
  end
  local prevCamp = Coop.dev
  function Coop.dev()
    if prevCamp then prevCamp() end
    if nextLevel and Coop.frame == cfg.campaignstep then
      Coop.log("campaign: " .. Coop.level .. " -> " .. nextLevel)
      local ok, err = pcall(SaveGame.NewLevelNow, nextLevel)
      if not ok then Coop.log("campaign error: " .. tostring(err)) end
    end
  end
end

-- 'autokeys' (tests): these virtual keys count as held (test windows never get input),
-- e.g. autokeys={69} holds E for the struggle (G15), the captive (G6), prayers (G4).
if cfg.autokeys and Net.CoopKey and not Coop.devKeysWrapped then
  Coop.devKeysWrapped = true
  local origKey = Net.CoopKey
  local held = {}
  for _, vk in ipairs(cfg.autokeys) do held[vk] = true end
  Net.CoopKey = function(vk)
    if held[vk] then return 1 end
    return origKey(vk)
  end
end

-- 'curetest' (host): when Rawlings' soul is back (G4), the host's body revives him.
if cfg.curetest and Coop.level == "levels/wwii_pillboxes" then
  local prevCure = Coop.dev
  function Coop.dev()
    if prevCure then prevCure() end
    if Coop.devCured or not (CoopSplits and CoopSplits.G4 and CoopSplits.G4.arrived) then return end
    local usr, raw = Game.UsrEntity(0), Game.GetEntity("Rawlings")
    if usr and raw and raw.Life <= 0 then
      Coop.devCured = true
      usr.Pos = raw.Pos + V3D(80, 0, 0)
      Coop.log("curetest: cure " .. tostring(Team.CurePlayer(usr, raw)))
    end
  end
end

-- 'fpsprobe': every 50 ticks log the player's first-person weapon model (the view model can
-- go missing after a level-start switch).
if cfg.fpsprobe and Coop.level ~= "levels/menu" then
  local prev = Coop.dev
  function Coop.dev()
    if prev then prev() end
    if Coop.frame % 50 ~= 0 then return end
    local usr = Game.UsrEntity(0)
    if not usr then Coop.log("fpsprobe: no usr") return end
    local fp = usr.oFPSEntity
    local w = usr.oWeapCtrl and usr.oWeapCtrl.oActual
    Coop.log(string.format("fpsprobe: %s fps=%s act=%s vis=%s active=%s weap=%s set=%s block=%s aim=%s ctrl=%s",
      usr.Name, tostring(fp and fp.Name), tostring(fp and fp.Action), tostring(fp and fp.bObjectVisible),
      tostring(fp and fp.Active), tostring(w and w.oType and w.oType.Name), tostring(w and w.oType and w.oType.FPAnmSet),
      tostring(usr.owc and usr.owc.BlockShot), tostring(Menu and Menu.bShowAim), tostring(usr.IgnoreUsrControl)))
  end
end


-- 'smodtest' (any machine, in a level): SMOD in a session. From tick cfg.smodtest: log the
-- rules in force; jump (SMOD's _G.Jump) every 80 ticks four times; switch the flashlight on
-- at +400 and off at +700; with cfg.regentest, halve the body's health at +100 and log it
-- at +400 (no regeneration with ironman).
if cfg.smodtest and Coop.level ~= "levels/menu" then
  local prevSm = Coop.dev
  function Coop.dev()
    if prevSm then prevSm() end
    local t = Coop.frame - cfg.smodtest
    local usr = Game.UsrEntity(0)
    if t < 0 or not usr then return end
    if t == 0 then
      local cls = usr.oActCtrl and usr.oActCtrl.oActClass
      Coop.log(string.format("smodtest: rules=%s dmgmult=%s life=%s/%s regen=%s,%s,%s",
        tostring(CoopSmod and CoopSmod.rules() and CoopSmod.encode(CoopSmod.rules()) or "game"),
        tostring(Weapons and Weapons.DamageMultiplier), tostring(usr.Life), tostring(cls and cls.Life),
        tostring(cls and cls.RegenStepEasy), tostring(cls and cls.RegenStep), tostring(cls and cls.RegenStepHard)))
    end
    if t > 0 and t <= 320 and t % 80 == 0 and type(_G.Jump) == "function" then
      pcall(_G.Jump)
      Coop.log(string.format("smodtest: jump, vel.y %.0f", usr.Vel and usr.Vel.y or 0))
    end
    -- While the flashlight is on: look around (the others' beam has to follow).
    if t > 420 and t < 690 then
      usr.IgnoreUsrControl = 1
      local w = (t - 420) / 270 * 2 * math.pi
      usr.ViewAng = V3D(12 * math.sin(2 * w), (Coop.devYaw0 or usr.ViewAng.y) + 35 * math.sin(w), 0)
      usr.Ang = V3D(0, usr.ViewAng.y, 0)
    elseif t == 420 then
      Coop.devYaw0 = usr.ViewAng.y
    elseif t == 690 then
      usr.IgnoreUsrControl = 0
    end
    if (t == 400 or t == 700) and Soldier and Soldier.FlashlightPress then
      pcall(Soldier.FlashlightPress, usr.Name)
      Coop.log("smodtest: flashlight " .. tostring(Game.Get("FPSFlashLightTimeOn")))
    end
    -- Another player's jump seen here: how high their body went within 1.5 s.
    local j = Coop.lastJump
    if j then
      local pe = Game.GetEntity(j.name)
      if pe then j.peak = math.max(j.peak, pe.Pos.y) end
      if Coop.frame - j.frame >= 22 then
        Coop.log(string.format("smodtest: %s jumped here, rose %.0f", j.name, j.peak - j.y))
        Coop.lastJump = nil
      end
    end
    if cfg.regentest and t == 100 then
      usr.Life = usr.Life * 0.5
      Coop.log("smodtest: life halved to " .. tostring(usr.Life))
    elseif cfg.regentest and t == 400 then
      Coop.log("smodtest: life after 300 ticks " .. tostring(usr.Life))
    end
  end
end

-- 'smodset' (menu): this machine's SMOD settings for a test, e.g. smodset={IRONMAN=true}
-- (autoexec.lua's own values otherwise); set again before the lobby reads them.
if cfg.smodset and Coop.level == "levels/menu" then
  local prevSet = Coop.dev
  function Coop.dev()
    if prevSet then prevSet() end
    if Coop.frame % 50 == 1 then
      for k, v in pairs(cfg.smodset) do _G[k] = v end
    end
  end
end

-- 'lighttest' (single game, in a level): how a SpotLight's Ang turns it. A light 300 units
-- ahead of the player (towards cfg.lightto, default Black), 150 up, one Ang per 60 ticks from
-- tick cfg.lighttest; the last step deletes it (does Del switch it off?).
if cfg.lighttest and Coop.level ~= "levels/menu" then
  local ANGS = cfg.lightangs or {{0, 0, 0}, {0, 90, 0}, {0, 180, 0}, {0, 270, 0}, {45, 0, 0}, {-45, 0, 0}, {0, 0, 45}, {0, 0, -45}}
  local prevLt = Coop.dev
  function Coop.dev()
    if prevLt then prevLt() end
    local t = Coop.frame - cfg.lighttest
    local usr = Game.UsrEntity(0)
    if t < 0 or not usr or t % 60 ~= 0 then return end
    local k = t / 60 + 1
    local old = Game.GetEntity("CoopLightTest" .. (k - 1))
    if old then old:Del() end
    local a = ANGS[k]
    if not a then
      Coop.log("lighttest: deleted, exists after Del: " .. tostring(Game.GetEntity("CoopLightTest" .. (k - 1)) ~= nil))
      return
    end
    local to = Game.GetEntity(cfg.lightto or "Black")
    local d = to and (to.Pos - usr.Pos) or V3D(0, 0, 1)
    local len = math.sqrt(d.x * d.x + d.z * d.z)
    local pos = usr.Pos + V3D(d.x / len * 300, 150, d.z / len * 300)
    local ang = V3D(a[1], a[2], a[3])
    if cfg.lightrel then
      -- From the camera, relative to the view: Ang = (90 + a1, view yaw + a2, a3).
      local cam = Game.GetEntity(Game.GetCam(0))
      pos = cam and cam.camPos or (usr.Pos + V3D(0, 170, 0))
      -- a[4]: hold the view at that pitch (positive looks down) and aim the beam with it.
      if a[4] then usr.IgnoreUsrControl = 1; usr.ViewAng = V3D(a[4], usr.ViewAng.y, 0) end
      ang = V3D(90 - (a[4] or 0) + a[1], usr.ViewAng.y + a[2], a[3])
    end
    local l = PhysicsObj.CreateObj("CoopLightTest" .. k, "SpotLight", pos, ang, false)
    l.LightConeOuter00, l.LightConeInner00, l.LightRange00, l.LightIntens00 = 40, 20, 1200, 3
    l.LightColor00 = V4D(255, 200, 120, 255)
    l.bLightOverShoot00, l.LightAttStart00, l.LightDotAtt00 = cfg.lightover == true, 0, 0.5
    l.bLightShadow00, l.LightShadowMapBias00, l.bLightSectorEnable00 = true, 1, true
    l.bLightEnable00 = true
    l.bLightProjEnable00, l.ProjID00 = true, cfg.lightproj or 20
    l.LightIntens00 = 1.5
    Coop.log(string.format("lighttest: %d Ang=%d,%d,%d at %s (player %s, towards %.0f,%.0f) view=%.0f,%.0f",
      k, a[1], a[2], a[3], Coop.v3(pos), Coop.v3(usr.Pos), d.x / len, d.z / len, usr.ViewAng.x, usr.ViewAng.y))
  end
end

-- 'splitprobe' (single game, in a level): what is left of the engine's own split screen
-- (docs/splitscreen-research.md). Phases of 60 ticks from tick cfg.splitprobe:
--   1 SplitScreen=1; 2 + R_SplitScreen=1, camera index 0; 3 a second FCam "CoopCam1" on Black
--   in user slot 1, camera index 1; 4 camera index switched every frame; 5 Black UsrControl=1
--   (is it Game.UsrEntity(1)?); 6 all back.
if cfg.splitprobe and Coop.level ~= "levels/menu" then
  local prevSp = Coop.dev
  function Coop.dev()
    if prevSp then prevSp() end
    local t = Coop.frame - cfg.splitprobe
    if t < 0 or t % 60 ~= 0 then return end
    local ph = t / 60 + 1
    local black = Game.GetEntity(cfg.splitwho or "Black")
    if ph == 1 then
      Game.Set("SplitScreen", 1)
    elseif ph == 2 then
      Game.Set("R_SplitScreen", 1); Game.Set("R_SplitScreenCamera", 0)
    elseif ph == 3 then
      local c = Game.GetEntity("CoopCam1") or Game.CreateEntity("CoopCam1", "FCam")
      c.CamRot, c.CamAng, c.CamDist, c.Fov = 5, -20, 0, 90
      if black then c.MainTarget = black.Name; c.Target = black.Name end
      Game.SetCam(1, "CoopCam1")
      Game.Set("R_SplitScreenCamera", 1)
    elseif ph == 4 then
      Coop.devFrame = function()
        Coop.devAlt = 1 - (Coop.devAlt or 0)
        Game.Set("R_SplitScreenCamera", Coop.devAlt)
      end
    elseif ph == 5 then
      Coop.devFrame = nil
      Game.Set("R_SplitScreenCamera", 0)
      if black then black.UsrControl = 1 end
    elseif ph == 6 then
      local u1 = Game.UsrEntity(1)
      Coop.log("splitprobe: UsrEntity(1) = " .. tostring(u1 and u1.Name) .. ", GetCam(1) = " .. tostring(Game.GetCam(1)))
      if black then black.UsrControl = -1 end
      Game.Set("SplitScreen", 0); Game.Set("R_SplitScreen", 0)
    end
    if ph <= 6 then
      Coop.log(string.format("splitprobe: phase %d SplitScreen=%s R_SplitScreen=%s cam=%s GetCam0=%s GetCam1=%s",
        ph, tostring(Game.Get("SplitScreen")), tostring(Game.Get("R_SplitScreen")), tostring(Game.Get("R_SplitScreenCamera")),
        tostring(Game.GetCam(0)), tostring(Game.GetCam(1))))
    end
  end
end

-- 'user1test' (single game, JERICHO_PADS=-1,9: the test pad as the game's pad 1): does the
-- engine itself drive a second user's body from pad 2? From tick cfg.user1test Black gets
-- UsrControl 1 and player 1 gets player 0's Joy1 bindings as Joy2; then her state is logged.
if cfg.user1test and Coop.level ~= "levels/menu" then
  local prevU1 = Coop.dev
  function Coop.dev()
    if prevU1 then prevU1() end
    local t = Coop.frame - cfg.user1test
    local b = Game.GetEntity(cfg.splitwho or "Black")
    if t < 0 or not b then return end
    if t == 0 then
      local n = 0
      for _, c in ipairs(Menu.Configurables or {}) do
        for _, act in ipairs({c[2], c[4]}) do
          local before1 = Input.GetDefinedList(1, c[1], act, 0, 0)
          for item in string.gmatch(Input.GetDefinedList(0, c[1], act, 0, 0) or "", "[^,]+") do
            local dev, key = string.match(item, "^%s*(%w+):(.+)$")
            if dev == "Joy1" then Input.AssingEntry("Joy2", key, 1, c[1], act); n = n + 1 end
          end
          Coop.log(string.format("user1test: %s.%s p0=[%s] p1 before=[%s] after=[%s]", c[1], act,
            tostring(Input.GetDefinedList(0, c[1], act, 0, 0)), tostring(before1), tostring(Input.GetDefinedList(1, c[1], act, 0, 0))))
        end
      end
      if b.oAI then b.oAI.bEnable = false end
      b.UsrControl = 1
      Coop.log("user1test: " .. n .. " Joy2 bindings for player 1; UsrEntity(1) = " .. tostring(Game.UsrEntity(1) and Game.UsrEntity(1).Name))
    elseif t % 15 == 0 and t <= 600 then
      Coop.log(string.format("user1test: t=%d pos=%s walk=%s str=%s shot=%s act=%s yaw=%.0f usr1=%s",
        t, Coop.v3(b.Pos), tostring(b.InCtrl_Walk), tostring(b.InCtrl_Str), tostring(b.owc and b.owc.Shot),
        tostring(b.Action), b.Ang.y, tostring(Game.UsrEntity(1) and Game.UsrEntity(1).Name)))
    end
  end
end

-- 'aspectprobe' (single game, in a level): which parameter gives a view twice as wide as
-- high (for a half-height split view). Phases of 60 ticks from tick cfg.aspectprobe.
if cfg.aspectprobe and Coop.level ~= "levels/menu" then
  local PH = {
    {"PhysicalAspectRatio", 3.5556}, {"PhysicalAspectRatio", 1.7778},
    {"CameraViewScaleY", 0.5}, {"CameraViewScaleY", 1},
    {"CameraViewScaleX", 2}, {"CameraViewScaleX", 1},
    {"CameraDefViewAspect", 2.6667}, {"CameraDefViewAspect", 1.3333},
  }
  local prevAp = Coop.dev
  function Coop.dev()
    if prevAp then prevAp() end
    local t = Coop.frame - cfg.aspectprobe
    if t < 0 or t % 60 ~= 0 then return end
    local p = PH[t / 60 + 1]
    if not p then return end
    local before = Game.Get(p[1])
    Game.Set(p[1], p[2])
    Coop.log(string.format("aspectprobe: %d %s %s -> %s", t / 60 + 1, p[1], tostring(before), tostring(Game.Get(p[1]))))
  end
end

-- 'splittest' (single game, JERICHO_PADS=-1,9 or two real pads): local split screen in one
-- game. From tick cfg.splittest Black is user 1 (pad 2) with her own camera, the engine's
-- split HUD and camera slot are on, and the slot switches every frame (native split.c
-- squeezes each frame into its half). cfg.splitflip: the frame shows the other slot.
if cfg.splittest and Coop.level ~= "levels/menu" then
  local prevSt = Coop.dev
  function Coop.dev()
    if prevSt then prevSt() end
    if Coop.frame ~= cfg.splittest then return end
    local b = Game.GetEntity(cfg.splitwho or "Black")
    if not b then return end
    if b.oAI then b.oAI.bEnable = false end
    local usr = Game.UsrEntity(0)
    Coop.log(string.format("splittest: before: %s FPSEntity=%s, %s FPSEntity=%s UseFPS=%s/%s", tostring(usr and usr.Name),
      tostring(usr and usr.FPSEntity), b.Name, tostring(b.FPSEntity), tostring(usr and usr.InCtrl_UseFPS), tostring(b.InCtrl_UseFPS)))
    if cfg.splitfp ~= false and MakeFP and Act.GetClass("FP_" .. b.Name) and not Game.GetEntity("1FP_" .. b.Name) then
      MakeFP.MakeFPObject("FP_" .. b.Name, 1)
    end
    b.UsrControl = 1
    Coop.log(string.format("splittest: after: %s FPSEntity=%s (1FP exists %s)", b.Name, tostring(b.FPSEntity),
      tostring(Game.GetEntity("1FP_" .. b.Name) ~= nil)))
    local c = Game.GetEntity("CoopCam1") or Game.CreateEntity("CoopCam1", "FCam")
    c.CamRot, c.CamAng, c.CamDist, c.Fov = 5, -20, 0, 90
    c.MainTarget, c.Target = b.Name, b.Name
    Game.SetCam(1, "CoopCam1")
    -- User 1's HUD: the engine's own widgets in scorer 1 (as Menu.ShowScorer builds scorer 0).
    if cfg.splithud ~= false then
      Scorer.Clear(1)
      local m = Scorer.NewItem(1, "Msg", "Msg"); m.Pos = V2D(320, 40)
      Scorer.NewItem(1, "Damage", "Damage")
      Scorer.NewItem(1, "Ammo", "Ammo")
      Scorer.NewItem(1, "Selector", "Selector")
      local ts = Scorer.NewItem(1, "TeamStatus", "TeamStatus"); ts.Pos = V2D(48, 36)
      Scorer.NewItem(1, "Aim", "Aim")
    end
    Game.Set("SplitScreen", 1)
    Game.Set("R_SplitScreen", 1)
    if cfg.splitscale then Game.Set("CameraViewScaleY", cfg.splitscale) end
    -- Effects that carry over from the previous frame (another camera's in split screen).
    local FX = {"RT_PixelMotionBlurPower", "RT_MotionBlurValue", "RT_BlurValue", "RT_CloseBlurValue",
      "RT_MonitorViewValue", "MotionBlurFactorBegin", "MotionBlurFactorEnd", "CloseBlurFactorBegin",
      "RT_HDRExposureTime", "RT_HDRMinLuminance", "RT_HDRMaxLuminance", "RT_PixelMotionBlur", "RT_MotionBlur"}
    local vals = {}
    for _, k in ipairs(FX) do vals[#vals + 1] = k .. "=" .. tostring(Game.Get(k)) end
    Coop.log("splittest: fx " .. table.concat(vals, " "))
    for k, v in pairs(cfg.splitfx or {}) do Game.Set(k, v) end
    Coop.devFrame = function()
      local slot = Net.CoopSplit(1)
      if cfg.splitflip then slot = 1 - slot end
      Game.Set("R_SplitScreenCamera", slot)
      Coop.devSplitN = (Coop.devSplitN or 0) + 1
      if Coop.devSplitN <= 16 then Coop.log("splittest: slot " .. slot) end
    end
    Coop.log("splittest: on, UsrEntity(1) = " .. tostring(Game.UsrEntity(1) and Game.UsrEntity(1).Name))
  end
end

-- 'projtest' (in a level): CoopHud.project against Scorer.Get2DPos (main camera, full
-- screen) for the squad's heads, every 30 ticks from tick cfg.projtest, 6 times.
if cfg.projtest and Coop.level ~= "levels/menu" then
  local prevPt = Coop.dev
  function Coop.dev()
    if prevPt then prevPt() end
    local t = Coop.frame - cfg.projtest
    if t < 0 or t > 150 or t % 30 ~= 0 then return end
    local cam = Game.GetEntity(Game.GetCam(0))
    local usr = Game.UsrEntity(0)
    if cam then
      local f1 = V3D(0, 0, 1):rot(cam.camAng)
      Coop.log(string.format("projtest: cam %s pos=%s ang=%s fov=%s fwd(0,0,1)=%.2f,%.2f,%.2f usr view=%s pos=%s",
        cam.Name, Coop.v3(cam.camPos), tostring(cam.camAng and (cam.camAng.x .. "," .. cam.camAng.y .. "," .. cam.camAng.z)),
        tostring(cam.Fov), f1.x, f1.y, f1.z, usr and (usr.ViewAng.x .. "," .. usr.ViewAng.y) or "-", usr and Coop.v3(usr.Pos) or "-"))
    end
    for _, name in ipairs(Coop.SQUAD) do
      local e = Game.GetEntity(name)
      if e and name ~= Coop.localChar() then
        local head = e.Pos + V3D(0, 195, 0)
        local gx, gy = Scorer.Get2DPos(head)
        local out = {}
        for _, fw in ipairs({1, -1}) do
          for _, fh in ipairs({true, false}) do
            CoopHud.FWD, CoopHud.FOV_IS_H = fw, fh
            local x, y = CoopHud.project(Game.GetCam(0), head)
            out[#out + 1] = string.format("%s%s=%s,%s", fw > 0 and "+" or "-", fh and "h" or "v",
              tostring(x and math.floor(x)), tostring(y and math.floor(y)))
          end
        end
        Coop.log(string.format("projtest: %s game=%s,%s %s", name, tostring(gx and math.floor(gx)),
          tostring(gy and math.floor(gy)), table.concat(out, " ")))
      end
    end
  end
end

-- 'ammoprobe' (split screen test): move scorer 0's and 1's Ammo widgets (it.Pos / it.Y) at
-- tick cfg.ammoprobe to see whether the power icons follow.
if cfg.ammoprobe and Coop.level ~= "levels/menu" then
  local prevAm = Coop.dev
  function Coop.dev()
    if prevAm then prevAm() end
    local t = Coop.frame - cfg.ammoprobe
    if t ~= 0 and t ~= 60 then return end
    if t == 0 and cfg.ammoparam then
      for k, v in pairs(cfg.ammoparam) do
        Coop.log("ammoprobe: " .. k .. " was " .. tostring(Game.Get(k)))
        Game.Set(k, v)
      end
    end
    for id = 0, 1 do
      local it = Scorer.GetItem(id, "Ammo")
      if it then
        Coop.log(string.format("ammoprobe: scorer %d Ammo X=%s Y=%s Pos=%s", id, tostring(it.X), tostring(it.Y),
          tostring(it.Pos and (it.Pos.x .. "," .. it.Pos.y))))
        if t == 0 and cfg.ammomove then it.Y = (it.Y or 0) - (cfg.ammody or 120) end
      end
    end
  end
end

-- 'headprobe' (in a level): each squad body's head bone (CoopHud.headPos) against its origin.
if cfg.headprobe and Coop.level ~= "levels/menu" then
  local prevHp = Coop.dev
  function Coop.dev()
    if prevHp then prevHp() end
    if Coop.frame ~= cfg.headprobe then return end
    for _, name in ipairs(Coop.SQUAD) do
      local e = Game.GetEntity(name)
      if e then
        local h = CoopHud.headPos(e)
        Coop.log(string.format("headprobe: %s origin y %.0f plate y %.0f (+%.0f) action %s", name, e.Pos.y, h.y, h.y - e.Pos.y,
          tostring(e.Action)))
      end
    end
  end
end

-- 'inputprobe' (in a level): the input bindings of users 0 and 1 for the astral camera.
if cfg.inputprobe and Coop.level ~= "levels/menu" then
  local prevIp = Coop.dev
  function Coop.dev()
    if prevIp then prevIp() end
    if Coop.frame ~= cfg.inputprobe then return end
    for u = 0, 1 do
      for _, sa in ipairs({{"Walk", "Special"}, {"Walk", "SpecialPlus"}, {"Walk", "PC_Up"}, {"Walk", "Fire"},
                           {"Astral", "Return"}, {"Astral", "GoTo"}, {"Astral", "MoveUp"}, {"Astral", "Fire"}}) do
        local ok, l = pcall(Input.GetDefinedList, u, sa[1], sa[2])
        Coop.log(string.format("inputprobe: user %d %s.%s = %s", u, sa[1], sa[2], tostring(ok and l or ("err " .. tostring(l)))))
      end
    end
  end
end

-- 'astrallog' (in a level): log the astral camera's callbacks and the action set (vanilla timing).
if cfg.astrallog and Coop.level ~= "levels/menu" then
  local prevAl = Coop.dev
  function Coop.dev()
    if prevAl then prevAl() end
    if not Coop.astralHooked and AstralCamera then
      Coop.astralHooked = true
      for _, k in ipairs({"Start", "EndReturn", "InmediateReturn", "InitReturn", "SetFirstPerson", "InitProjection",
                          "EndProjection", "InitZoom", "EndZoom"}) do
        local f = AstralCamera[k]
        if type(f) == "function" then
          AstralCamera[k] = function(...) Coop.log("astrallog: " .. k .. " set=" .. tostring(Input.GetActionSet())) return f(...) end
        end
      end
    end
    local set = Input.GetActionSet()
    if set ~= Coop.astralSet then Coop.astralSet = set; Coop.log("astrallog: action set " .. tostring(set)) end
  end
end

-- 'barriertest' (split screen, player 2 Delgado): Delgado's fire barrier on at tick
-- cfg.barriertest, off 600 ticks later.
if cfg.barriertest and Coop.level ~= "levels/menu" then
  local prevBt = Coop.dev
  function Coop.dev()
    if prevBt then prevBt() end
    local t = Coop.frame - cfg.barriertest
    if t ~= 0 and t ~= 600 then return end
    local e = Game.GetEntity("Delgado")
    if e then e.uData.bProtection = t ~= 0 end
    local f = t == 0 and Delgado.ActivateBarrier or Delgado.DeactivateBarrier
    if e and e.UsrControl == 1 then CoopSplit.asUser1(f) else f() end
    Coop.log("barriertest: " .. (t == 0 and "on" or "off"))
  end
end

-- 'hudprobe' (split screen): a text item in player 2's scorer, logged with player 2's own HUD
-- items every 100 ticks (does the engine hide scorer 1 during player 1's astral projection?).
if cfg.hudprobe and Coop.level ~= "levels/menu" then
  local prevHp = Coop.dev
  function Coop.dev()
    if prevHp then prevHp() end
    if Coop.frame < 200 then return end
    local t = Scorer.GetItem(1, "Probe")
    if not t then
      t = Scorer.NewItem(1, "Probe", "Text", 1)
      t.Font = Menu.SmallFont
      t.Pos = V2D(320, 300)
      t.Color = V4D(255, 64, 64, 255)
    end
    t.Text = "P2 PROBE " .. tostring(Input.GetActionSet())
    if Coop.frame % 100 == 0 then
      local s = {}
      for _, n in ipairs({"Ammo", "Selector", "Aim", "TeamStatus", "Msg", "Probe"}) do
        local it = Scorer.GetItem(1, n)
        s[#s + 1] = n .. "=" .. (it and tostring(it.Visible) or "-")
      end
      Coop.log("hudprobe: set=" .. tostring(Input.GetActionSet()) .. " " .. table.concat(s, " "))
    end
  end
end

-- 'fpslog': frames per real second, logged every 10 s (split HUD cost: with and without
-- JERICHO_SPLITHUD=0, the game's frame cap off).
if cfg.fpslog and Coop.level ~= "levels/menu" then
  local prevFps = Coop.dev
  function Coop.dev()
    if prevFps then prevFps() end
    local now = Net.CoopTime()
    Coop.fpsN = (Coop.fpsN or 0) + 1
    Coop.fpsT0 = Coop.fpsT0 or now
    if now - Coop.fpsT0 >= 10 then
      Coop.log(string.format("fpslog: %.1f fps", Coop.fpsN / (now - Coop.fpsT0)))
      Coop.fpsN, Coop.fpsT0 = 0, now
    end
  end
end

-- 'p2aim' = '<entity>' (split screen): player 2's body (aimwho = 'p1': player 1's, the
-- baseline) stands where it sees the boss's weak spot (aimnode, a bone) and fires at it in
-- bursts from tick 300. Every hit on the boss is logged: attacker, damage, life before and
-- after its OnDamage (the boss scripts count hits only from "the player").
if cfg.p2aim and Coop.level ~= "levels/menu" then
  local prevAim = Coop.dev
  local function shooter()
    if cfg.aimwho == "p1" then return Game.UsrEntity(0) end
    return CoopSplit and CoopSplit.on and CoopSplit.body and CoopSplit.body()
  end
  local function aimPoint(t)
    local ok, v = pcall(function() return cfg.aimnode and t["NodePosHierarchy_" .. cfg.aimnode] end)
    if ok and v then return v end
    if not Coop.aimNodeMissing then
      Coop.aimNodeMissing = true
      Coop.log("p2aim: no node " .. tostring(cfg.aimnode) .. ", aiming " .. tostring(cfg.aimh or 120) .. " above the feet")
    end
    return t.Pos + V3D(0, cfg.aimh or 120, 0)
  end
  function Coop.dev()
    if prevAim then prevAim() end
    local t = Game.GetEntity(cfg.p2aim)
    -- the hit log, outermost (after the co-op story wrapper)
    if t and not Coop.aimHooked then
      -- (aimhook: the boss class's damage callback, e.g. 'Gladiador.OnDamage')
      local fname = cfg.aimhook
      local tname, f
      if type(fname) == "string" then tname, f = string.match(fname, "^([%w_]+)%.([%w_]+)$") end
      local tbl = tname and _G[tname]
      if tbl and type(tbl[f]) == "function" then
        Coop.aimHooked = true
        local orig = tbl[f]
        tbl[f] = function(me, attacker, dmg, ...)
          local e = Game.GetEntity(me)
          local before = e and e.Life
          -- the body part the engine says was hit (the bosses count only their weak spot)
          local part = "-"
          pcall(function()
            local pc = e.oWeapHit.oBodyPiece
            if pc and pc.bIsRagdollPart then part = pc.oRagDollDamagePart.Name end
          end)
          local listed = e and e.uData and e.uData.DamagedParts ~= nil
          local r = {orig(me, attacker, dmg, ...)}
          if me == cfg.p2aim then
            local u = Game.UsrEntity(0)
            Coop.log(string.format("p2aim hit: %s by %s, part %s%s, damage %.1f, life %.1f -> %.1f (player 0 outside: %s)",
              tostring(me), tostring(attacker), part, listed and " (explosion list)" or "", tonumber(dmg) or -1,
              before or -1, e and e.Life or -1, u and u.Name or "-"))
          end
          return unpack(r)
        end
        Coop.log("p2aim: hit log on " .. fname)
      end
    end
    -- the boss fight on (aimgroup: the boss's enemy group, as the level's arena trigger does)
    if cfg.aimgroup and Coop.frame == 250 then
      Coop.log("p2aim: fight on, group " .. cfg.aimgroup .. ": " .. tostring(pcall(NPC.ActivateEnemyGroup, cfg.aimgroup)))
    end
    -- (aimprobe: a hit coming later, outside player 2's own calls - a mine, an explosion:
    -- the boss's damage callback called with player 2 as the attacker and no damage; the hit
    -- log shows who the boss sees as "the player" then)
    if cfg.aimprobe and Coop.frame == 400 and Coop.aimHooked then
      local p2 = CoopSplit and CoopSplit.body and CoopSplit.body()
      local tname, f = string.match(cfg.aimhook or "", "^([%w_]+)%.([%w_]+)$")
      if p2 and tname and _G[tname] then
        Coop.log("p2aim: probe, " .. cfg.aimhook .. " for " .. p2.Name .. " from outside its calls")
        local ok, err = pcall(_G[tname][f], cfg.p2aim, p2.Name, 0)
        if not ok then Coop.log("p2aim: probe error " .. tostring(err)) end
      end
    end
    if Coop.frame < 300 then return end
    local b = shooter()
    if not b or not t then
      if Coop.frame % 300 == 0 then Coop.log("p2aim: no " .. (b and cfg.p2aim or "shooter")) end
      return
    end
    local tgt = aimPoint(t)
    -- a spot 300 units out with a clear line to the weak spot, tried around the boss
    if not Coop.aimSpot or Coop.frame % 120 == 0 then
      Coop.aimSpot = nil
      for k = 0, 11 do
        local a = (k / 12) * 2 * math.pi
        -- (eyes level with the weak spot: a player body's view pitch follows its camera, not
        -- ViewAng, so the shot goes straight ahead)
        local spot = V3D(tgt.x + math.cos(a) * 300, tgt.y - 120, tgt.z + math.sin(a) * 300)
        local eye = spot + V3D(0, 120, 0)
        local hit = Game.TestLine(eye, tgt, "")
        if not hit or (hit - tgt):mod() < 40 then Coop.aimSpot = spot break end
      end
      Coop.aimSpot = Coop.aimSpot or (tgt + V3D(0, 0, 300))
    end
    b.Pos = Coop.aimSpot   -- held there every frame (in the air if need be)
    local eye = b.Pos + V3D(0, 120, 0)
    local d = tgt - eye
    local yaw = math.deg(math.atan2(-d.x, -d.z))
    local flat = math.sqrt(d.x * d.x + d.z * d.z)
    local pitch = -math.deg(math.atan2(d.y, flat))
    b.IgnoreUsrControl = 1
    b.Invulnerable = 1
    b.Ang = V3D(0, yaw, 0)
    b.ViewAng = V3D(pitch, yaw, 0)
    if b.owc then
      if cfg.aimfire2 then
        -- the secondary weapon (Cole's mine launcher): held 1 s of every 3 s
        b.owc.Shot = 0
        b.owc.SecondWeaponTrigger = (Coop.frame % 90 < 30) and 1 or 0
      else
        b.owc.Shot = (Coop.frame % 40 < 25) and 1 or 0
      end
    end
    if Coop.frame % 100 == 0 then
      Coop.log(string.format("p2aim: %s life %.0f (active %s), %s at %.0f units; target %s, boss at %s, shooter at %s, view %s",
        t.Name, t.Life or -1, tostring(t.bActive), b.Name, flat, Coop.v3(tgt), Coop.v3(t.Pos), Coop.v3(b.Pos),
        tostring(b.ViewAng and Coop.v3(b.ViewAng))))
    end
  end
end

-- 'padlog' (split screen): both players' bodies (position, facing, life, weapon) and the action
-- set every 30 ticks (real gamepads: which pad moves whom).
if cfg.padlog and Coop.level ~= "levels/menu" then
  local prevPad = Coop.dev
  function Coop.dev()
    if prevPad then prevPad() end
    -- in the astral set: what the engine reads for "Return" and "MoveUp", both users, every 3 ticks
    if Input.GetActionSet() == "Astral" and Coop.frame % 3 == 0 then
      local function g(a, u) local ok, v = pcall(Input.GetInputState, "Astral", a, u) return ok and tostring(v) or "err" end
      local pad1 = {pcall(Net.CoopKey, -1, 1)}
      local pad0 = {pcall(Net.CoopKey, -1, 0)}
      Coop.log(string.format("padlog astral: Return u0 %s u1 %s, MoveUp u0 %s u1 %s, raw buttons p0 %s p1 %s",
        g("Return", 0), g("Return", 1), g("MoveUp", 0), g("MoveUp", 1), tostring(pad0[2]), tostring(pad1[2])))
    end
    if Coop.frame % 15 ~= 0 then return end
    local function d(e)
      if not e then return "-" end
      local w = "-"
      pcall(function() w = e.oWeapCtrl.oActual.oType.Name end)
      return string.format("%s %s yaw %.0f life %.0f %s", e.Name, Coop.v3(e.Pos), e.Ang and e.Ang.y or 0, e.Life or -1, tostring(w))
    end
    local p2 = CoopSplit and CoopSplit.on and CoopSplit.body and CoopSplit.body()
    local ac = Game.GetEntity("AstralCam")
    Coop.log("padlog: p1 " .. d(Game.UsrEntity(0)) .. " | p2 " .. d(p2) .. " | set " .. tostring(Input.GetActionSet()) ..
      " cam0 " .. tostring(Game.GetCam(0)) .. " cam1 " .. tostring(Game.GetCam(1)) ..
      (ac and (" astralcam " .. Coop.v3(ac.Pos) .. " ang " .. Coop.v3(ac.Ang)) or ""))
  end
end

-- 'bindprobe': the input bindings of users 0 and 1 for the actions Jones's astral projection
-- reads (logged once the split screen is on).
if cfg.bindprobe and Coop.level ~= "levels/menu" then
  local prevBind = Coop.dev
  function Coop.dev()
    if prevBind then prevBind() end
    if Coop.frame ~= 400 then return end
    for _, a in ipairs({{"Walk", "Special"}, {"Walk", "SpecialPlus"}, {"Walk", "Forward"}, {"Walk", "TurnRight"},
                        {"Astral", "Return"}, {"Astral", "GoTo"}, {"Astral", "MoveUp"}, {"Astral", "Forward"},
                        {"Astral", "TurnRight"}, {"Astral", "TurnUp"}}) do
      for u = 0, 1 do
        local ok, v = pcall(Input.GetDefinedList, u, a[1], a[2])
        Coop.log(string.format("bindprobe: user %d %s.%s = %s", u, a[1], a[2], ok and tostring(v) or ("error " .. tostring(v))))
      end
    end
  end
end

-- 'rossprobe': what Ross is made of in a view (act 1): his entity, his FP arms, his class's actions.
if cfg.rossprobe and Coop.level ~= "levels/menu" then
  local prev = Coop.dev
  function Coop.dev()
    if prev then prev() end
    local r = Game.GetEntity("Ross")
    if Coop.frame % 15 == 0 and r then
      local s = Game.GetEntity("CoopRossBody")
      if r.Life ~= Coop.rossLastLife or (s and s.Life ~= Coop.rossBodyLife) then
        Coop.rossLastLife, Coop.rossBodyLife = r.Life, s and s.Life
        Coop.log("rossprobe: life Ross " .. tostring(r.Life) .. " stand-in " .. tostring(s and s.Life) ..
          " jones " .. tostring(Game.GetEntity("Jones") and Game.GetEntity("Jones").Life))
      end
    end
    if Coop.frame % 150 ~= 60 then return end
    if not r then return end
    local function f(k) local ok, v = pcall(function() return r[k] end) return ok and tostring(v) or "?" end
    Coop.log("rossprobe: vis " .. f("bObjectVisible") .. " active " .. f("bActive") .. " action " .. f("Action") ..
      " fps " .. f("FPSEntity") .. " usr0 " .. tostring(Game.UsrEntity(0) and Game.UsrEntity(0).Name))
    for _, n in ipairs({"0FP_Ross", "FP_Ross", "1FP_Ross", "0FP_Jones", "FPRoss"}) do
      local e = Game.GetEntity(n)
      if e then Coop.log("rossprobe: entity " .. n .. " vis " .. tostring(e.bObjectVisible)) end
    end
    local c = Act.GetClass("Ross")
    if c and not Coop.rossActsLogged then
      Coop.rossActsLogged = true
      local have = {}
      for _, n in ipairs({"Relax", "relax", "Walk", "walk", "DuckWalk", "WalkDuck", "Relax0", "DuckRelax", "Sprint", "Run"}) do
        local a = c:GetAct(n)
        if a then have[#have + 1] = n .. "=" .. tostring(a.AnmFilePath) end
      end
      Coop.log("rossprobe: class model " .. tostring(c.ModelFilePath) .. " acts " .. table.concat(have, " "))
    end
  end
end

-- 'faceross': player 2 (split screen), or else this machine's player (a network client), turns
-- toward Ross from tick 200 (act 1: his stand-in in view).
if cfg.faceross and Coop.level ~= "levels/menu" then
  local prevFace = Coop.dev
  function Coop.dev()
    if prevFace then prevFace() end
    if Coop.frame < 200 then return end
    local b = CoopSplit and CoopSplit.on and CoopSplit.body and CoopSplit.body()
    if not b and Coop.isClient() then b = Game.UsrEntity(0) end
    local r = Game.GetEntity("Ross")
    if not b or not r then return end
    local d = r.Pos - b.Pos
    local yaw = math.deg(math.atan2(-d.x, -d.z))
    b.IgnoreUsrControl = 1
    b.Ang = V3D(0, yaw, 0)
    b.ViewAng = V3D(0, yaw, 0)
    if Coop.frame % 100 == 0 then
      local s = Game.GetEntity("CoopRossBody")
      Coop.log(string.format("faceross: Ross at %s (%.0f away), vis %s, stand-in %s active %s", Coop.v3(r.Pos),
        math.sqrt(d.x * d.x + d.z * d.z), tostring(r.bObjectVisible), s and Coop.v3(s.Pos) or "-", tostring(s and s.Active)))
    end
  end
end

-- 'rosshide' (a network client, act 1): this player stands 260 units in front of Ross, facing
-- him; from tick 300 four phases of 240 ticks (below), normal again at 1260; a recording shows
-- which body is drawn when.
if cfg.rosshide and Coop.level ~= "levels/menu" then
  local prevRh = Coop.dev
  function Coop.dev()
    if prevRh then prevRh() end
    local b, r = Game.UsrEntity(0), Game.GetEntity("Ross")
    if not b or not r or Coop.frame < 200 then return end
    -- what stands where Ross is (every 300 ticks outside scenes)
    if Coop.frame % 300 == 150 and not (Scene and Scene.IsPlaying) then
      local e = Game.GetFirst()
      while e ~= nil do
        local ok, d = pcall(function() return (e.Pos - r.Pos):mod() end)
        if ok and d < 150 then
          local function g(k) local ok2, v = pcall(function() return e[k] end) return ok2 and tostring(v) or "?" end
          Coop.log(string.format("rosshide: near %s type %s ctrl %s vis %s active %s act %s d %.0f", e.Name, g("Type"),
            g("ActCtrl"), g("bObjectVisible"), g("Active"), g("Action"), d))
        end
        if e.NextInSlot == "" then break end
        e = Game.GetEntity(e.NextInSlot)
      end
    end
    -- (again every 300 ticks outside scenes: the squad moves after the intro scenes)
    if Coop.frame == 200 or (Coop.frame % 300 == 0 and not (Scene and Scene.IsPlaying)) then
      local y = math.rad(r.Ang.y)
      b.Pos = r.Pos + V3D(-math.sin(y) * 260, 0, -math.cos(y) * 260)
      pcall(Game.SetOnFloor, b.Name)
    end
    local d = r.Pos - b.Pos
    local yaw = math.deg(math.atan2(-d.x, -d.z))
    b.IgnoreUsrControl = 1
    b.Ang = V3D(0, yaw, 0)
    b.ViewAng = V3D(8, yaw, 0)
    -- (rosshide='view': only the view, the mod's own way of showing him)
    local phase = cfg.rosshide ~= "view" and (Coop.frame >= 1260 and 4 or Coop.frame >= 1020 and 3 or
      Coop.frame >= 780 and 2 or Coop.frame >= 540 and 1 or Coop.frame >= 300 and 0) or nil
    local s = Game.GetEntity("CoopRossBody")
    local function f(k) local ok, v = pcall(function() return r[k] end) return ok and tostring(v) or "?" end
    -- phases (rosshide=true): the stand-in 80 units to the side, so both bodies can be told
    -- apart: 0 the mod's way, 1 + Ross's flag written here too, 2 stand-in off, 3 off + written
    if phase and phase < 4 and s then
      s.Pos = r.Pos + V3D(80, 0, 0)
      if phase >= 2 then s.Active = 0 end
    end
    if phase == 1 or phase == 3 then r.bObjectVisible = false end
    if phase ~= Coop.rhPhase then
      Coop.rhPhase = phase
      Coop.log("rosshide: phase " .. tostring(phase) .. " vis " .. f("bObjectVisible") .. " active " .. f("Active") ..
        " stand-in " .. tostring(s and s.Active))
    end
  end
end

-- 'rossbisect' (with rosshide='view', a network client in act 1): CoopRoss.update replaced by
-- parts of it, one more per phase of 240 ticks from 300: 0 Ross's flag only (stand-in off),
-- 1 + the stand-in follows him (off), 2 + the stand-in on, 3 + his action copied; the stand-in
-- 80 units to the side so both can be told apart on a recording.
if cfg.rossbisect and Coop.level ~= "levels/menu" then
  local prevRb = Coop.dev
  function Coop.dev()
    if prevRb then prevRb() end
    if not Coop.rbHooked and CoopRoss and CoopRoss.update then
      Coop.rbHooked = true
      CoopRoss.update = function()
        local e = CoopRoss.body()
        local r = Game.GetEntity("Ross")
        if not e or not r then return end
        local q = Coop.frame >= 1260 and 4 or Coop.frame >= 1020 and 3 or Coop.frame >= 780 and 2 or
          Coop.frame >= 540 and 1 or Coop.frame >= 300 and 0 or -1
        if q < 0 then return end
        if q ~= Coop.rbPhase then Coop.rbPhase = q; Coop.log("rossbisect: phase " .. q) end
        r.bObjectVisible = false
        if q >= 1 then
          e.Pos = r.Pos + V3D(80, 0, 0)
          e.Ang = V3D(0, r.Ang.y, 0)
        end
        local a = q >= 2 and 1 or 0
        if e.Active ~= a then e.Active = a end
        if q >= 3 then
          local act = r.Action
          if act and act ~= Coop.rbAct then
            Coop.rbAct = act
            if Act.GetClass(CoopRoss.NAME):GetAct(act) then e.ForceAction = act; e.ForceDefLoop = act end
          end
        end
      end
    end
  end
end

-- 'hidetest': at tick 250 the characters are hidden as a scene hides them (Scene.HideChars) and
-- left so, as an interrupted scene leaves them (Coop.reclaimBody should bring the player back).
if cfg.hidetest and Coop.level ~= "levels/menu" then
  local prevHide = Coop.dev
  function Coop.dev()
    if prevHide then prevHide() end
    if Coop.frame == 250 and Scene and Scene.HideChars then
      Scene.HideChars()
      local u = Game.UsrEntity(0)
      Coop.log("hidetest: characters hidden, user " .. tostring(u and u.Name))
    end
    if Coop.frame > 250 and Coop.frame % 30 == 0 and Coop.frame < 600 then
      local u = Game.UsrEntity(0)
      Coop.log("hidetest: user " .. tostring(u and u.Name))
    end
  end
end

-- 'bosscall' = '<Class>.<Handler>' (client test): from tick 400, every 100 ticks, the boss
-- class's animation-event handler is called for its entity here, as an event of the host-driven
-- copy would (fork MAK-PIVO: native AI calls of Sumerian bosses crashed clients).
if cfg.bosscall and Coop.level ~= "levels/menu" then
  local prevBoss = Coop.dev
  function Coop.dev()
    if prevBoss then prevBoss() end
    if Coop.frame < 400 or Coop.frame % 100 ~= 0 then return end
    local list = {}
    for x in string.gmatch(cfg.bosscall, "[^;]+") do list[#list + 1] = x end
    Coop.bossCallN = (Coop.bossCallN or 0) + 1
    local call = list[(Coop.bossCallN - 1) % #list + 1]
    local cls, fn = string.match(call, "^([%w_]+)%.([%w_]+)$")
    local e = Game.GetFirst()
    while e do
      local ok, name = pcall(function() return e.oActCtrl.oActClass.Name end)
      if ok and name == cls then
        Coop.log("bosscall: " .. call .. " for " .. e.Name .. " (AI on " .. tostring(e.oAI and e.oAI.bEnable) .. ")")
        local ok2, err = pcall(_G[cls][fn], e.Name, "test", 0)
        Coop.log("bosscall: returned " .. tostring(ok2) .. " " .. tostring(err))
        return
      end
      if e.NextInSlot == "" then break end
      e = Game.GetEntity(e.NextInSlot)
    end
    Coop.log("bosscall: no " .. tostring(cls))
  end
end

-- 'puppetlog' (from the fork MAK-PIVO/jericho-coop): every frame from cfg.puppetlog_from to cfg.puppetlog_to seconds after the
-- level start, log where each puppet is drawn ("pp|time|name|x|y|z|yaw"); tools/puppet_jitter.py
-- turns the lines into smoothness numbers (frame-to-frame jumps, acceleration, turn steps).
if cfg.puppetlog and Coop.level ~= "levels/menu" then
  local prevFrame = Coop.devFrame
  local t0
  Coop.devFrame = function(dt)
    if prevFrame then prevFrame(dt) end
    local now = Net.CoopTime()
    t0 = t0 or now
    local age = now - t0
    if age < (cfg.puppetlog_from or 20) or age > (cfg.puppetlog_to or 60) then return end
    for _, name in ipairs(Coop.SQUAD) do
      local e = Coop.isPuppet(name) and Coop.remote[name] and Coop.squadEnt(name)
      if e and e.Life and e.Life > 0 then
        local p = e.Pos
        Coop.log(string.format("pp|%.4f|%s|%.1f|%.1f|%.1f|%.2f", now, name, p.x, p.y, p.z, e.Ang.y))
      end
    end
    -- Enemies a client draws from the host's snapshots.
    for name in pairs(CoopEnemies and CoopEnemies.targets or {}) do
      local e = Game.GetEntity(name)
      if e and e.Life and e.Life > 0 then
        local p = e.Pos
        Coop.log(string.format("pp|%.4f|E:%s|%.1f|%.1f|%.1f|%.2f", now, name, p.x, p.y, p.z, e.Ang.y))
      end
    end
    -- The player's own body as the reference: how smooth the engine itself moves a body.
    local usr = Game.UsrEntity(0)
    if usr then
      local p = usr.Pos
      Coop.log(string.format("pp|%.4f|own-%s|%.1f|%.1f|%.1f|%.2f", now, usr.Name, p.x, p.y, p.z, usr.Ang.y))
    end
  end
end

-- Tests of the parts taken from the fork MAK-PIVO/jericho-coop (its dev.lua).
-- 'worldtest': doors and object deaths across machines (coop_world.lua). At tick 300 the
-- host opens cfg.door (default Rom_Tepidarium's "puerta final frigi") and kills the first
-- tracked object it finds; at tick 340 the client kills another one. The reports' "world:"
-- part then shows doors/dead on both machines and any digest misses.
if cfg.worldtest and Coop.level ~= "levels/menu" then
  local prevWorld = Coop.dev
  local function killOne(skip)
    for name in pairs(CoopWorld.objects or {}) do
      local e = Game.GetEntity(name)
      if e and name ~= skip and string.sub(name, 1, 3) == "OB_" then
        e.Life = 0
        Coop.log("worldtest: killed " .. name)
        return name
      end
    end
  end
  function Coop.dev()
    if prevWorld then prevWorld() end
    if Coop.isHost() and Coop.frame == 300 then
      local door = cfg.door or "puerta final frigi"
      PhysicsObj.OpenDoor(door)
      Coop.log("worldtest: opened " .. door)
      Coop.worldTestKill = killOne()
    elseif Coop.isClient() and Coop.frame == 340 then
      killOne(Coop.worldTestKill)
    end
    if Coop.frame == 420 then
      local d = Game.GetEntity(cfg.door or "puerta final frigi")
      Coop.log("worldtest: door action " .. tostring(d and d.Action) .. ", " .. CoopWorld.report())
    end
  end
end

-- 'locktest' (client): at tick 300 lock the player's controls as a stuck story script would;
-- Coop.controlWatchdog should release them about 12 s later.
if cfg.locktest and Coop.level ~= "levels/menu" then
  local prevLock = Coop.dev
  function Coop.dev()
    if prevLock then prevLock() end
    local usr = Game.UsrEntity(0)
    if Coop.isClient() and Coop.frame == 300 and usr then
      usr.IgnoreUsrControl = 1
      Coop.log("locktest: controls locked on " .. usr.Name)
    end
  end
end

-- 'qtebot' = 'win' | 'fail' (per machine): stands in for this player's keys in shared story
-- QTEs (coop_scenes.lua), 0.4 s after a prompt starts: 'win' makes this machine's scorer say
-- the sequence is done, 'fail' presses a wrong key's failure. Test windows get no real input.
-- 'qtescene' (host, Rom_Outskirts): plays the Behemoth's death scene (Church, four QTEs) once
-- no scene is playing after tick 300.
if cfg.qtebot and Coop.level ~= "levels/menu" then
  local prevQ = Coop.devFrame
  Coop.devFrame = function(dt)
    if prevQ then prevQ(dt) end
    local q = CoopScenes and CoopScenes.shared and CoopScenes.shared.active
    if not q or q.botDone or Net.CoopTime() - (q.startedAt or 0) < 0.4 then return end
    q.botDone = true
    if cfg.qtebot == "win" then q.botWin = true
    elseif cfg.qtebot == "fail" then pcall(Scorer.QTESequenceFailed) end
    Coop.log("qtebot: " .. tostring(cfg.qtebot) .. " on QTE " .. q.id .. " (" .. tostring(q.sequence) .. ")")
  end
  if Scorer and Scorer.QTEIsSequenceOK and not Coop.qteBotWrapped then
    Coop.qteBotWrapped = true
    local origOK = Scorer.QTEIsSequenceOK
    Scorer.QTEIsSequenceOK = function(...)
      local q = CoopScenes and CoopScenes.shared and CoopScenes.shared.active
      if q and q.botWin then return true end
      return origOK(...)
    end
  end
end
if cfg.qtescene and Coop.isHost() and Coop.level == "levels/rom_outskirts" then
  local prevScene = Coop.dev
  function Coop.dev()
    if prevScene then prevScene() end
    -- After the client has loaded the level and got its catch-up (else the scene runs alone).
    if Coop.qteScenePlayed or Coop.frame < 300 or (Scene and Scene.IsPlaying) then return end
    if not (CoopEnemies and CoopEnemies.catchupSent) then return end
    Coop.qteScenePlayed = true
    Coop.log("qtescene: Behemoth death scene")
    pcall(MapScenes.StartBehemotQTE)
  end
end

-- 'gbtest' (client playing Black): at tick 300 fire the ghost bullet as the power does
-- (ThreadsBlack.CreateGhostBullet); the host logs where its copy flies every 5 ticks.
-- 'abbytest' (client playing Delgado, with 'fight' on the host): from tick 400 turn to the
-- nearest enemy within 2500 and send the Ababanili at it (Ababanili.AbabaniliStart).
-- 'disptest=<hz>' (full screen): the Video settings' rows applied as Accept does
-- (Coop.applyDisplay): that refresh rate at tick 300, Auto at 900, a window at 1200 (restart
-- hint), full screen again at 1300.
if cfg.disptest and Coop.level ~= "levels/menu" then
  local prevDisp = Coop.dev
  local steps = {[300] = {hz = cfg.disptest}, [900] = {hz = 0}, [1200] = {mode = 2}, [1300] = {mode = 1}}
  function Coop.dev()
    if prevDisp then prevDisp() end
    local s = steps[Coop.frame]
    if s then
      local d = Coop.displayState()
      if s.hz then d.hz = s.hz end
      if s.mode then d.mode = s.mode end
      Coop.applyDisplay()
      Coop.log("disptest: tick " .. Coop.frame .. " -> " .. tostring(Net.CoopDisplay("get")))
    end
  end
end

if (cfg.gbtest or cfg.abbytest) and Coop.level ~= "levels/menu" then
  local prevPow = Coop.dev
  function Coop.dev()
    if prevPow then prevPow() end
    local u = Game.UsrEntity(0)
    -- With the 'strafe' bot (standing in front of the host) the bullet goes later, away
    -- from the host, so the host's view follows it.
    local gbAt = cfg.bot == "strafe" and 600 or 300
    if cfg.gbtest and Coop.isClient() and u and Coop.frame == gbAt then
      for name, peer in pairs(Coop.owners) do
        local h = cfg.bot == "strafe" and peer == 0 and Game.GetEntity(name)
        if h then
          local d = u.Pos - h.Pos
          local yaw = math.deg(math.atan2(-d.x, -d.z))
          u.Ang, u.ViewAng = V3D(0, yaw, 0), V3D(0, yaw, 0)
        end
      end
      local ok, o = pcall(ThreadsBlack.CreateGhostBullet, u)
      Coop.log("gbtest: bullet " .. tostring(ok and o and o.Name or o))
    end
    if Coop.isHost() and Coop.frame % 5 == 0 and CoopPowers then
      for owner, c in pairs(CoopPowers.copies) do
        local e = Game.GetEntity(c.name)
        if e then Coop.log(string.format("gbtest: copy of %s at %.0f %.0f %.0f", owner, e.Pos.x, e.Pos.y, e.Pos.z)) end
      end
    end
    if cfg.abbytest and Coop.isClient() and u and Coop.frame >= 400 and not Coop.abbySent and Coop.frame % 20 == 0 then
      local best, bd
      local e = Game.GetFirst()
      while e ~= nil do
        if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive then
          local d = (e.Pos - u.Pos):mod()
          if d < 2500 and (not bd or d < bd) then best, bd = e, d end
        end
        e = Game.GetEntity(e.NextInSlot)
      end
      if best then
        local d = best.Pos - u.Pos
        -- (the spirit takes the target the player looks at, from close enough: 600 units)
        if bd > 700 then
          local k = 600 / bd
          u.Pos = best.Pos - V3D(d.x * k, 0, d.z * k)
          pcall(Game.SetOnFloor, u.Name)
          d = best.Pos - u.Pos
        end
        local yaw = math.deg(math.atan2(-d.x, -d.z))
        local pitch = -math.deg(math.atan2(d.y + 60, math.sqrt(d.x * d.x + d.z * d.z)))
        u.IgnoreUsrControl = 1
        u.Ang = V3D(0, yaw, 0)
        u.ViewAng = V3D(pitch, yaw, 0)
        local ok, r = pcall(Ababanili.AbabaniliStart, u.Name)
        Coop.log("abbytest: at " .. best.Name .. " (" .. math.floor(bd) .. ") -> " .. tostring(ok and (r and r.Name or r) or r))
        if ok and r then Coop.abbySent = true end
      end
    end
  end
end

-- 'tktest' (client playing Black, 'fight' on the host): from tick 400 Black's telekinesis on
-- the first active enemy (Black.ApplyTelePower), once.
-- 'runetest' (client playing Church): at tick 300 Church's blood rune where he stands
-- (ThreadsChurch.ActivatePower); the host logs its rune table every 50 ticks.
if (cfg.tktest or cfg.runetest) and Coop.level ~= "levels/menu" then
  local prevTk = Coop.dev
  function Coop.dev()
    if prevTk then prevTk() end
    local u = Game.UsrEntity(0)
    if cfg.tktest and Coop.isClient() and u and Coop.frame >= 400 and not Coop.tkDone and Coop.frame % 20 == 0 then
      local e = Game.GetFirst()
      while e ~= nil do
        if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive then
          local ok, err = pcall(Black.ApplyTelePower, u, e)
          Coop.log("tktest: on " .. e.Name .. " " .. tostring(ok and "ok" or err))
          Coop.tkDone = true
          break
        end
        e = Game.GetEntity(e.NextInSlot)
      end
    end
    if cfg.runetest and Coop.isClient() and u and Coop.frame == 300 then
      local ok, err = pcall(ThreadsChurch.ActivatePower, u.Name)
      Coop.log("runetest: rune " .. tostring(ok and "ok" or err))
    end
    if cfg.runetest and Coop.isHost() and Coop.frame % 50 == 0 and ThreadsChurch and ThreadsChurch.BloodRuneTable then
      local n = 0
      for _, name in pairs(ThreadsChurch.BloodRuneTable) do if Game.GetEntity(name) then n = n + 1 end end
      if n > 0 then Coop.log("runetest: host has " .. n .. " blood rune(s)") end
    end
  end
end

-- 'rawtest' (client Rawlings, 'fight' on the host; coop_powers.lua Rawlings): the client
-- curses the first active enemy (tick 400+), calms the host's body (500) and heals it (650,
-- the host drops to 30 life at 550), then drops its own life a little (700) so that the
-- host's hits on the cursed enemy (800-860) feed it. Both log life, calm and curses.
if cfg.rawtest and Coop.level ~= "levels/menu" then
  local prevRaw = Coop.dev
  local function hostBody()
    for name, peer in pairs(Coop.owners) do
      if peer == 0 then return Game.GetEntity(name) end
    end
  end
  local function cursed()
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.uData and e.uData.IsCursed then return e end
      e = Game.GetEntity(e.NextInSlot)
    end
  end
  function Coop.dev()
    if prevRaw then prevRaw() end
    local u = Game.UsrEntity(0)
    if not u then return end
    local f = Coop.frame
    if Coop.isClient() then
      if f >= 400 and not Coop.rawCursed and f % 20 == 0 then
        local e = Game.GetFirst()
        while e ~= nil do
          if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive then
            local ok, err = pcall(WeaponsRawlings.Curse, u, e)
            Coop.log("rawtest: curse " .. e.Name .. " " .. tostring(ok and "ok" or err))
            Coop.rawCursed = true
            break
          end
          e = Game.GetEntity(e.NextInSlot)
        end
      end
      local h = hostBody()
      if f == 500 and h then
        local ok, err = pcall(WeaponsRawlings.Calm, u, h)
        Coop.log("rawtest: calm " .. h.Name .. " " .. tostring(ok and "ok" or err))
      end
      if f == 650 and h then
        local before = h.Life
        local ok, err = pcall(WeaponsRawlings.Cure, u, h)
        Coop.log("rawtest: heal " .. h.Name .. " puppet life " .. tostring(before) .. " " .. tostring(ok and "ok" or err))
      end
      if f == 700 then u.Life = math.floor(u.oActCtrl.oActClass.Life * 0.8) end
    else
      -- Hurt from tick 550 until a heal lifts the life (the client's heal comes later).
      if f >= 550 and not Coop.rawHealed then
        if Coop.rawLast and u.Life > Coop.rawLast + 10 then
          Coop.rawHealed = true
          Coop.log("rawtest: healed " .. Coop.rawLast .. " -> " .. u.Life)
        else
          u.Life = 30
        end
        Coop.rawLast = u.Life
      end
      local e = cursed()
      if e and f >= 800 and f <= 860 and f % 30 == 0 then
        local ok, err = pcall(Weapons.DoDamage, u, e, 30)
        Coop.log("rawtest: host hits cursed " .. e.Name .. " " .. tostring(ok and "ok" or err))
      end
    end
    if f >= 400 and f % 50 == 0 then
      local e = cursed()
      Coop.log(string.format("rawtest: me=%s life=%s calm=%s cursed=%s", u.Name, tostring(u.Life),
        tostring(u.uData and u.uData.ChamanicCalm), tostring(e and e.Name)))
    end
  end
end

-- 'bosstest' = {'Nanna', 'Bip NANNA Spine2'} (both; the host's 'storycall' brings the boss
-- in): the host makes the boss vulnerable at tick 650; the client hits it on that bone at 800
-- and on another bone at 950, as a shot or blast on that part would (coop_enemies.lua
-- E.hitPart). The host logs the boss's life: only the weak part may take it down.
if cfg.bosstest and Coop.level ~= "levels/menu" then
  local prevBoss = Coop.dev
  local bossName, bone = cfg.bosstest[1], cfg.bosstest[2]
  local function hitOn(b, wantBone)
    local u = Game.UsrEntity(0)
    local map = {}
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("PxBodyPhysics") and e.bIsRagdollPart then
        local owner = Game.GetRagdollPartOwner(e.Name)
        if owner and owner.Name == b.Name then map[#map + 1] = e end
      end
      e = Game.GetEntity(e.NextInSlot)
    end
    for _, part in ipairs(map) do
      local pb = part.oRagDollDamagePart.Name
      if (wantBone and pb == wantBone) or (not wantBone and pb ~= bone) then
        b.uData.DamagedParts = {[part.Name] = {Damage = 50, Damager = u.Name}}
        local ok, err = pcall(Weapons.DoDamage, u, b, 50)
        Coop.log("bosstest: hit " .. b.Name .. " on " .. pb .. " (" .. #map .. " parts) " .. tostring(ok and "ok" or err))
        return
      end
    end
    Coop.log("bosstest: no part " .. tostring(wantBone) .. " on " .. b.Name .. " (" .. #map .. " parts)")
  end
  function Coop.dev()
    if prevBoss then prevBoss() end
    local b = Game.GetEntity(bossName)
    local f = Coop.frame
    if Coop.isHost() then
      if b and f == 650 then b.Invulnerable = 0 end
      if f >= 600 and f % 50 == 0 then
        Coop.log("bosstest: " .. bossName .. " life=" .. tostring(b and b.Life) .. " inv=" .. tostring(b and b.Invulnerable))
      end
    elseif b and (f == 800 or f == 950) then
      hitOn(b, f == 800 and bone or nil)
    end
  end
end

-- 'downtest' (both): the client goes down at tick 400 and, with every free body refused
-- (Team.SwitchSoldier fails while it is down), waits for Rawlings; its camera should follow
-- the host's body (coop_team.lua T.watchPartner). The host revives it at tick 1000.
if cfg.downtest and Coop.level ~= "levels/menu" then
  local prevDown = Coop.dev
  function Coop.dev()
    if prevDown then prevDown() end
    local u = Game.UsrEntity(0)
    if not u then return end
    if Coop.isClient() then
      if Coop.frame == 400 then
        if not Coop.downSwitchWrapped then
          Coop.downSwitchWrapped = true
          local sw = Team.SwitchSoldier
          Team.SwitchSoldier = function(a, b, ...)
            local me = Game.UsrEntity(0)
            if me and me.Life <= 0 then return false end
            return sw(a, b, ...)
          end
        end
        u.Invulnerable = 0
        u.Life = 0
        Coop.log("downtest: " .. u.Name .. " down")
      end
      if Coop.frame % 50 == 0 and Coop.frame >= 400 then
        local cam = Game.GetEntity("MainCam")
        Coop.log("downtest: life=" .. tostring(u.Life) .. " cam=" .. tostring(Game.GetCam(0)) .. " target=" .. tostring(cam and cam.MainTarget))
      end
    elseif Coop.frame == 1000 then
      for name, peer in pairs(Coop.owners) do
        local e = peer ~= 0 and Game.GetEntity(name)
        if e then Coop.log("downtest: revive " .. name .. " " .. tostring(Team.RevivePlayer(e))) end
      end
    end
  end
end

-- 'watch' (host): every frame the host's body turns to the first client's puppet, so a
-- recording (run_pair -Record) shows what the client does from the host's side.
if cfg.watch and Coop.level ~= "levels/menu" then
  local prevWatch = Coop.dev
  function Coop.dev()
    if prevWatch then prevWatch() end
    local u = Game.UsrEntity(0)
    if not (u and Coop.isHost()) then return end
    for name, peer in pairs(Coop.owners) do
      local e = peer ~= 0 and Game.GetEntity(name)
      if e then
        local d = e.Pos - u.Pos
        local yaw = math.deg(math.atan2(-d.x, -d.z))
        u.Ang = V3D(0, yaw, 0)
        u.ViewAng = V3D(5, yaw, 0)
        return
      end
    end
  end
end

-- 'burntest' (client, 'fight' on the host): from tick 400 set the first active enemy on fire
-- in this player's name, as a firestorm shot would; the host should light its copy.
if cfg.burntest and Coop.isClient() and Coop.level ~= "levels/menu" then
  local prevBurn = Coop.dev
  function Coop.dev()
    if prevBurn then prevBurn() end
    local u = Game.UsrEntity(0)
    if not u or Coop.burnDone or Coop.frame < 400 or Coop.frame % 20 ~= 0 then return end
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive then
        e.FireRemainTime, e.FireDelayTime, e.FireAtenuationFactor, e.Pyromaniac = 5, 0.5, 0, u.Name
        Coop.log("burntest: lit " .. e.Name)
        Coop.burnDone = true
        return
      end
      e = Game.GetEntity(e.NextInSlot)
    end
  end
end


-- 'jonestest' (client playing Jones, 'fight' on the host): from tick 400 Jones goes 500 units
-- from the nearest active enemy and projects (Jones.PressSpecial, as the power's button); then
-- the astral camera's own callbacks: telekinesis on that enemy, later pyrokinesis on another
-- (or the same), then the return. The host's log shows what reached its enemies.
if cfg.jonestest and Coop.isClient() and Coop.level ~= "levels/menu" then
  local prevJones = Coop.dev
  local function nearest(u, skip)
    local best, bd
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive and e.Name ~= skip then
        local d = (e.Pos - u.Pos):mod()
        if not bd or d < bd then best, bd = e, d end
      end
      e = Game.GetEntity(e.NextInSlot)
    end
    return best, bd
  end
  function Coop.dev()
    if prevJones then prevJones() end
    local u = Game.UsrEntity(0)
    local J = Coop.jt
    if not u or Coop.frame < 400 then return end
    if not J then
      local t, d = nearest(u)
      if not t then return end
      local v = t.Pos - u.Pos
      local k = 500 / math.max(d, 1)
      u.Pos = t.Pos - V3D(v.x * k, 0, v.z * k)
      pcall(Game.SetOnFloor, u.Name)
      Coop.jt = {t = t.Name, at = Coop.frame}
      Coop.log("jonestest: next to " .. t.Name)
      return
    end
    local cam = Game.GetEntity("AstralCam")
    local f = Coop.frame - J.at
    local tg = Game.GetEntity(J.t)
    if f <= 10 and tg then
      -- looking at the enemy: the astral camera starts with the body's view and selects it
      local d = tg.Pos + V3D(0, 60, 0) - (u.Pos + V3D(0, 120, 0))
      local yaw = math.deg(math.atan2(-d.x, -d.z))
      local pitch = -math.deg(math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z)))
      u.IgnoreUsrControl = 1
      u.Ang = V3D(0, yaw, 0)
      u.ViewAng = V3D(pitch, yaw, 0)
    end
    if f > 10 and f < 30 and f % 3 == 0 and cam then
      local sel = AstralCamera and AstralCamera.LastSelectedEntity
      local ok1, tk = pcall(function() return cam:CanTK() end)
      local ok2, bn = pcall(function() return cam:CanBurn() end)
      Coop.log("jonestest: selected " .. tostring(sel) .. " CanTK " .. tostring(tk) .. " CanBurn " .. tostring(bn))
      if sel and sel ~= "" and Game.GetEntity(sel) then J.t = sel end
    end
    if f == 10 then
      local ok, err = pcall(Jones.PressSpecial, u.Name)
      Coop.log("jonestest: projection " .. tostring(ok and "on" or err) .. ", set " .. tostring(Input.GetActionSet()))
    elseif f == 30 and cam then
      local ok, can = pcall(function() return cam:CanTK() end)
      local r, err = pcall(Jones.PressTelekinesis, u.Name, u.Name, J.t)
      Coop.log("jonestest: telekinesis on " .. J.t .. " (CanTK " .. tostring(ok and can) .. ") " .. tostring(r and "ok" or err))
    elseif f == 60 and cam then
      local t2 = Game.GetEntity(J.t) or nearest(u, J.t)
      local ok, can = pcall(function() return cam:CanBurn() end)
      local r, err = pcall(Jones.PressPyrokinesis, u.Name, u.Name, t2 and t2.Name)
      Coop.log("jonestest: pyrokinesis on " .. tostring(t2 and t2.Name) .. " (CanBurn " .. tostring(ok and can) .. ") " ..
        tostring(r and "ok" or err) .. ", fire " .. tostring(t2 and t2.FireRemainTime))
    elseif f == 90 then
      u.IgnoreUsrControl = 0
      pcall(Jones.Return)
      Coop.log("jonestest: back, set " .. tostring(Input.GetActionSet()))
    end
  end
end

-- 'jonesreal' (client playing Jones with a real or virtual gamepad, 'fight' on the host): at
-- tick 400 Jones is put 500 units from the nearest active enemy, facing it ("jonesreal: ready");
-- everything after that is the player's input (the test's pad). Logged: the astral bindings,
-- the action set, the astral camera's selection and CanTK/CanBurn/CanProject every 10 ticks
-- while projecting, and each call of the game's own telekinesis/pyrokinesis callbacks.
if cfg.jonesreal and Coop.level ~= "levels/menu" then
  local prevJr = Coop.dev
  local function can(cam, m)
    local ok, v = pcall(function() return cam[m](cam) end)
    return ok and tostring(v) or "?"
  end
  function Coop.dev()
    if prevJr then prevJr() end
    local u = Game.UsrEntity(0)
    if not u then return end
    if not Coop.jrHooked and Jones and AstralCamera then
      Coop.jrHooked = true
      for _, a in ipairs({"Return", "GoTo", "Telekinesis", "Pyrokinesis", "BloodRune"}) do
        local ok, v = pcall(Input.GetDefinedList, 0, "Astral", a)
        Coop.log("jonesreal: binding " .. a .. " = " .. tostring(ok and v or "?"))
      end
      local sel = AstralCamera.ChangeSelectedEntity
      AstralCamera.ChangeSelectedEntity = function(a, b)
        Coop.log("jonesreal: selected '" .. tostring(b) .. "'")
        return sel(a, b)
      end
      for _, k in ipairs({"PressTelekinesis", "PressPyrokinesis"}) do
        local f = Jones[k]
        Jones[k] = function(o, l, tg)
          local cam = Game.GetEntity("AstralCam")
          Coop.log("jonesreal: " .. k .. " owner " .. tostring(o) .. " linked " .. tostring(l) .. " target " ..
            tostring(tg) .. " CanTK " .. (cam and can(cam, "CanTK") or "-") .. " CanBurn " .. (cam and can(cam, "CanBurn") or "-"))
          return f(o, l, tg)
        end
      end
    end
    if Coop.frame == 400 then
      -- the nearest enemy that has another one close by (the second is the telekinesis target
      -- once the projection is in the first)
      local list = {}
      local e = Game.GetFirst()
      while e ~= nil do
        if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive then list[#list + 1] = e end
        e = Game.GetEntity(e.NextInSlot)
      end
      for _, a in ipairs(list) do Coop.log("jonesreal: enemy " .. a.Name .. " at " .. Coop.v3(a.Pos)) end
      local best, bd
      for _, a in ipairs(list) do
        for _, b in ipairs(list) do
          if a ~= b and (a.Pos - b.Pos):mod() < 450 then
            local d = (a.Pos - u.Pos):mod()
            if not bd or d < bd then best, bd = a, d end
          end
        end
      end
      if not best then
        for _, a in ipairs(list) do
          local d = (a.Pos - u.Pos):mod()
          if not bd or d < bd then best, bd = a, d end
        end
      end
      -- jrobj='<entity>': an object to try telekinesis on instead, 300 units away
      local obj = cfg.jrobj and Game.GetEntity(cfg.jrobj)
      if obj then best, bd = obj, (obj.Pos - u.Pos):mod() end
      if best then
        local v = best.Pos - u.Pos
        local k = (obj and 300 or 500) / math.max(bd, 1)
        u.Pos = best.Pos - V3D(v.x * k, 0, v.z * k)
        pcall(Game.SetOnFloor, u.Name)
        local d = best.Pos + V3D(0, 60, 0) - (u.Pos + V3D(0, 120, 0))
        local yaw = math.deg(math.atan2(-d.x, -d.z))
        local pitch = -math.deg(math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z)))
        u.Ang = V3D(0, yaw, 0)
        u.ViewAng = V3D(pitch, yaw, 0)
        Coop.jrTarget = best.Name
        Coop.log("jonesreal: ready, facing " .. best.Name .. " life " .. tostring(best.Life))
      end
    end
    -- jtsend: at tick 450 the message coop_powers sends for a telekinesis push that acted
    -- (pw|jt, the same vector as Jones.PressTelekinesis) on the faced enemy; its position is
    -- logged as the host's snapshots move it
    local J = Game.GetEntity(Coop.jrTarget or "")
    if cfg.jtsend and J and Coop.isClient() then
      if Coop.frame == 450 then
        local f = 1 - (J.Pos - u.Pos):mod() / Jones.TKRange
        local v = (J.Pos - u.Pos):norm() * (Jones.TKPower * 5 * f)
        Net.CoopSend(0, 1, string.format("pw|jt|%s|%s|%.1f|%.1f|%.1f|0", u.Name, J.Name, v.x, v.y, v.z))
        Coop.log("jonesreal: jt sent on " .. J.Name .. " at " .. Coop.v3(J.Pos) .. " push " .. Coop.v3(v))
      elseif Coop.frame == 440 or Coop.frame == 460 or Coop.frame == 480 or Coop.frame == 520 then
        Coop.log("jonesreal: " .. J.Name .. " at " .. Coop.v3(J.Pos) .. " life " .. tostring(J.Life))
      end
    end
    local set = Input.GetActionSet()
    if set ~= Coop.jrSet then Coop.jrSet = set; Coop.log("jonesreal: action set " .. tostring(set)) end
    local cam = Game.GetEntity("AstralCam")
    -- once the projection has gone into an enemy (CanProject 0, CanBurn 1), the view is turned to
    -- the nearest other enemy for 30 ticks ("aimed at"), as a player would aim; the buttons stay
    -- the pad's
    if set == "Astral" and cam and not Coop.jrAim and can(cam, "CanProject") == "0" and can(cam, "CanBurn") == "1" then
      Coop.jrAim = {at = Coop.frame, linked = AstralCamera.LastSelectedEntity}
    end
    local function aim(ent)
      local d = ent.Pos + V3D(0, 60, 0) - cam.Pos
      local yaw = math.deg(math.atan2(-d.x, -d.z))
      local pitch = -math.deg(math.atan2(d.y, math.sqrt(d.x * d.x + d.z * d.z)))
      cam.SphereRot = V3D(pitch, yaw, 0)
      cam.Ang = V3D(-pitch, yaw, 0)
    end
    -- before that, the view is kept on the enemy Jones faced until the camera selects an enemy
    local T = Game.GetEntity(Coop.jrTarget or "")
    if cfg.jraim and set == "Astral" and cam and not Coop.jrAim and T then
      local s = Game.GetEntity(AstralCamera.LastSelectedEntity or "")
      if cfg.jrobj then
        if s ~= T then aim(T) end
      elseif not (s and s:IsType("WalkChar") and s.TgType == "red") then aim(T) end
    end
    local A = Coop.jrAim
    -- (each tick) the moment the selection can be moved by telekinesis, for the pad driver
    local tkNow = set == "Astral" and cam and can(cam, "CanTK") or "0"
    if tkNow ~= Coop.jrTK then
      Coop.jrTK = tkNow
      Coop.log("jonesreal: CanTK " .. tkNow .. " on '" .. tostring(AstralCamera.LastSelectedEntity) .. "'")
      -- the first time: telekinesis on that selection right away, the call the astral camera
      -- makes for the pad's button (a pad press comes too late for a selection that lasts a
      -- few ticks while the view turns)
      local sel = AstralCamera.LastSelectedEntity
      if cfg.jrtk and tkNow == "1" and sel and sel ~= "" and not Coop.jrTKDone then
        Coop.jrTKDone = true
        local linked = (A and A.linked) or u.Name
        local tg = Game.GetEntity(sel)
        Coop.log("jonesreal: telekinesis call on " .. sel .. " from " .. linked .. " type " ..
          tostring(tg and tg.Type) .. " useOnTK " .. tostring(tg and tg.bUseOnTK) .. " pos " .. Coop.v3(tg and tg.Pos))
        local ok, err = pcall(Jones.PressTelekinesis, u.Name, linked, sel)
        Coop.log("jonesreal: telekinesis " .. (ok and "done" or tostring(err)) .. ", pos now " .. Coop.v3(tg and tg.Pos))
      end
    end
    if cfg.jraim and A and set == "Astral" and cam and Coop.frame >= A.at + 30 and Coop.frame < A.at + 60 then
      -- (what Jones.PressTelekinesis can act on: a living enemy or a physics body, within
      -- Jones.TKRange of the body the projection is in; an enemy first)
      local best, bd, kind
      local L = Game.GetEntity(A.linked or "") or cam
      local e = Game.GetFirst()
      while e ~= nil do
        local k = (e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 and e.bActive and 1) or
          (e:IsType("PxBodyPhysics") and 2) or nil
        if k and e.Name ~= A.linked and not (k == 2 and string.find(e.Name, "^Bip ")) then
          local dd = (e.Pos - L.Pos):mod()
          if dd > 50 and dd < Jones.TKRange * 0.9 and (not bd or k < kind or (k == kind and dd < bd)) then
            best, bd, kind = e, dd, k
          end
        end
        e = Game.GetEntity(e.NextInSlot)
      end
      if best then
        aim(best)
        if not A.logged then
          A.logged = true
          Coop.log("jonesreal: aimed at " .. best.Name .. " " .. string.format("%.0f", bd) .. " (in " .. tostring(A.linked) .. ")")
        end
      end
    end
    if set == "Astral" and cam and Coop.frame % 10 == 0 then
      Coop.log("jonesreal: astral sel '" .. tostring(AstralCamera.LastSelectedEntity) .. "' CanTK " .. can(cam, "CanTK") ..
        " CanBurn " .. can(cam, "CanBurn") .. " CanProject " .. can(cam, "CanProject") .. " cam " .. Coop.v3(cam.Pos))
    end
  end
end

-- 'jtwatch' (host): every power message's target is logged for 2 s after it came (position,
-- action, life), to see what a client's telekinesis push did in the host's world.
if cfg.jtwatch and Coop.level ~= "levels/menu" then
  local prevJw = Coop.dev
  function Coop.dev()
    if prevJw then prevJw() end
    if not Coop.jwHooked and CoopPowers and CoopPowers.onPower then
      Coop.jwHooked = true
      local orig = CoopPowers.onPower
      CoopPowers.onPower = function(peer, f, data)
        local t = Game.GetEntity(f[4] or "")
        if t then Coop.jw = {name = t.Name, at = Coop.frame}; Coop.log("jtwatch: " .. tostring(f[2]) .. " on " .. t.Name .. " at " .. Coop.v3(t.Pos)) end
        return orig(peer, f, data)
      end
    end
    local w = Coop.jw
    if w and (Coop.frame - w.at) % 5 == 0 and Coop.frame - w.at <= 60 then
      local t = Game.GetEntity(w.name)
      if t then
        Coop.log("jtwatch: +" .. (Coop.frame - w.at) .. " " .. w.name .. " at " .. Coop.v3(t.Pos) .. " action " ..
          tostring(t.oActCtrl and t.oActCtrl.Action) .. " life " .. tostring(t.Life))
      end
    end
  end
end

-- 'xinprobe': every 15 ticks the four XInput slots as the game reads them (Net.CoopKey(-3):
-- -1 = not connected, else buttons + packet * 65536), to see what Steam's overlay does to pads.
if cfg.xinprobe then
  local prevX = Coop.dev
  function Coop.dev()
    if prevX then prevX() end
    if Coop.frame % 15 ~= 0 then return end
    local r = {pcall(Net.CoopKey, -3)}
    if r[1] then
      Coop.log(string.format("xinprobe: %s %s %s %s set %s", tostring(r[2]), tostring(r[3]), tostring(r[4]),
        tostring(r[5]), tostring(Input.GetActionSet and Input.GetActionSet())))
    end
  end
end

-- Test console (tools/luacon.py; JERICHO_CONSOLE=<udp port> in the test's environment): a Lua
-- chunk sent to that port runs here, between frames, in the game's own Lua; what it prints
-- and returns is sent back. An expression is returned as is ("Game.UsrEntity(0).Name").
if Net.CoopConsole then
  local prevCon = Coop.dev
  function Coop.dev()
    if prevCon then prevCon() end
    for _ = 1, 4 do
      local src = Net.CoopConsole()
      if not src then return end
      local out = {}
      local oldPrint = print
      print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        out[#out + 1] = table.concat(t, "\t")
      end
      local f, err = loadstring("return " .. src, "console")
      if not f then f, err = loadstring(src, "console") end
      local res = f and {pcall(f)} or {false, err}
      print = oldPrint
      if not res[1] then
        out[#out + 1] = "error: " .. tostring(res[2])
      else
        for i = 2, table.maxn(res) do out[#out + 1] = tostring(res[i]) end
      end
      Net.CoopConsole(table.concat(out, "\n"))
    end
  end
end

-- 'splitface' (split screen): every 150 ticks from tick 300 both players look at the next
-- target from 300 units, standing side by side: player 2's body, player 1's body, then each
-- squad member in turn ("splitface: <target>" in the log; a recording shows both halves).
if cfg.splitface and Coop.level ~= "levels/menu" then
  local prevSf = Coop.dev
  function Coop.dev()
    if prevSf then prevSf() end
    local b0 = Game.UsrEntity(0)
    local b1 = CoopSplit and CoopSplit.on and CoopSplit.body and CoopSplit.body()
    if not b0 or not b1 or Coop.frame < 300 then return end
    local list = Coop.sfList
    if not list then
      list = {b1.Name, b0.Name}
      for _, n in ipairs(Coop.SQUAD) do
        local e = Game.GetEntity(n)
        if e and e.Life and e.Life > 0 and n ~= b0.Name and n ~= b1.Name then list[#list + 1] = n end
      end
      Coop.sfList = list
    end
    local k = math.floor((Coop.frame - 300) / 150) % #list + 1
    local t = Game.GetEntity(list[k])
    if not t then return end
    if k ~= Coop.sfK then
      Coop.sfK = k
      -- both 300 units in front of the target, 80 apart; the target faces them
      local y = math.rad(t.Ang.y)
      local fx, fz = -math.sin(y), -math.cos(y)
      local px, pz = fz, -fx
      local mover = {b0, b1}
      for i, b in ipairs(mover) do
        if b ~= t then
          local side = (i == 1) and -40 or 40
          b.Pos = t.Pos + V3D(fx * 200 + px * side, 0, fz * 200 + pz * side)
          pcall(Game.SetOnFloor, b.Name)
        end
      end
      Coop.log("splitface: looking at " .. t.Name .. " (" .. k .. "/" .. #list .. ")")
    end
    for _, b in ipairs({b0, b1}) do
      if b ~= t then
        local d = t.Pos - b.Pos
        local yaw = math.deg(math.atan2(-d.x, -d.z))
        b.IgnoreUsrControl = 1
        b.Ang = V3D(0, yaw, 0)
        b.ViewAng = V3D(5, yaw, 0)
      end
    end
  end
end

-- 'targetprobe' (host, with 'fight'): every 100 ticks, whether coop_enemies.lua's target hook is
-- still in place, how often the game asked for a target, and whom each active enemy attacks
-- (AI_ObjectiveDin) - do enemies ever go for a network player's body?
if cfg.targetprobe and Coop.isHost() and Coop.level ~= "levels/menu" then
  local prevTp = Coop.dev
  Coop.tpCalls = 0
  function Coop.dev()
    if prevTp then prevTp() end
    if not Coop.tpWrapped and AIEnemy and AIEnemy.FindMemb then
      Coop.tpWrapped = true
      for _, fn in ipairs({"FindMemb", "FindMembVisNear", "FindMembRandom", "BehavAttackGen", "DoAttack"}) do
        local orig = AIEnemy[fn]
        if type(orig) == "function" then
          AIEnemy[fn] = function(...)
            Coop.tpCalls = Coop.tpCalls + 1
            Coop.tpLast = fn
            return orig(...)
          end
        end
      end
    end
    if Coop.frame % 100 ~= 0 then return end
    local hooked = CoopEnemies and AIMemberSquad and CoopEnemies.targetingInstalled and
                   debug.getinfo(AIMemberSquad.IsEnable, "S").source
    local targets = {}
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("WalkChar") and e.TgType == "red" and (e.Life or 0) > 0 and e.oAI and e.oAI.bEnable then
        targets[#targets + 1] = e.Name .. ">" .. tostring(e.AI_ObjectiveDin)
      end
      e = Game.GetEntity(e.NextInSlot)
    end
    Coop.log(string.format("targetprobe: IsEnable from %s calls %d last %s rtargets %s | %s", tostring(hooked),
      Coop.tpCalls, tostring(Coop.tpLast), tostring(CoopEnemies.stats.remoteTargets), table.concat(targets, " ")))
  end
end

-- 'hoststep' (host): from tick 300, every 100 ticks the host's body moves 300 units along its
-- facing (does another machine follow a body that is not one of the six, e.g. Act 1's Ross?).
if cfg.hoststep and Coop.isHost() and Coop.level ~= "levels/menu" then
  local prevStep = Coop.dev
  function Coop.dev()
    if prevStep then prevStep() end
    if Coop.frame < 300 or Coop.frame % 100 ~= 0 then return end
    local u = Game.UsrEntity(0)
    if not u then return end
    local y = math.rad(u.Ang.y)
    u.Pos = u.Pos + V3D(-math.sin(y) * 300, 0, -math.cos(y) * 300)
    pcall(Game.SetOnFloor, u.Name)
    Coop.log(string.format("hoststep: %s at %.0f,%.0f", u.Name, u.Pos.x, u.Pos.z))
  end
end

-- 'actlog' (any machine): every change of this player's body action (and its weapon slot),
-- to see which actions a human body plays when it fires, reloads or uses a power.
if cfg.actlog and Coop.level ~= "levels/menu" then
  local prevAct = Coop.dev
  function Coop.dev()
    if prevAct then prevAct() end
    if MakeFP and not Coop.actFpWrapped then
      Coop.actFpWrapped = true
      for _, fn in ipairs({"LaunchFpsAnm", "LaunchFpsAnm2"}) do
        local orig = MakeFP[fn]
        if type(orig) == "function" then
          MakeFP[fn] = function(id, action, value, ...)
            Coop.log("actlog: fp " .. fn .. " " .. tostring(id) .. " " .. tostring(action) .. " " .. tostring(value))
            return orig(id, action, value, ...)
          end
        end
      end
    end
    local u = Game.UsrEntity(0)
    if not u then return end
    local a = tostring(u.Action)
    local wc = u.oWeapCtrl
    local slot = wc and tostring(wc.iSlot) or "-"
    local shot = u.owc and u.owc.Shot or 0
    local fp = Game.GetEntity("0FP_" .. u.Name)
    local fa = fp and tostring(fp.Action) or "-"
    if fa ~= Coop.actFpLast then
      Coop.actFpLast = fa
      Coop.log("actlog: fpaction " .. fa)
    end
    local key = a .. "/" .. slot .. "/" .. (shot > 0.5 and 1 or 0)
    if key ~= Coop.actLast then
      Coop.actLast = key
      Coop.log("actlog: " .. u.Name .. " " .. key)
    end
  end
end

-- 'turntp' (the machine of a body that gets a story turn, coop_story.lua): 3 s after the turn
-- comes the body is moved to the spot (as if its player walked there), then stands.
if cfg.turntp and Coop.level ~= "levels/menu" then
  local prevTurn = Coop.dev
  function Coop.dev()
    if prevTurn then prevTurn() end
    local turn = CoopStory and CoopStory.myTurn
    if not turn then Coop.turnSeen = nil return end
    Coop.turnSeen = Coop.turnSeen or Net.CoopTime()
    if Net.CoopTime() - Coop.turnSeen > 3 and not turn.tp then
      turn.tp = true
      local u = Game.GetEntity(turn.name)
      if u then u.Pos = turn.pos pcall(Game.SetOnFloor, u.Name) end
      Coop.log("turntp: " .. turn.name .. " moved to its turn's spot")
    end
  end
end

-- 'autoplay' (host and clients): a playthrough by the AI, for finding where a player's body
-- cannot go where the game's own AI goes (invisible walls, objects left on one machine).
-- The host walks an AI squad member, the "scout", to the nearest active story trigger it has
-- not reached yet (AIGen.GoAndAction: the level's navigation; triggers to the next level last);
-- every machine's own player body follows the scout's trail with its input fields (turn, walk,
-- sprint) as a person would, and fires at enemies nearby. A body that does not get on along the
-- trail for 2.5 s logs "autoplay: stuck" with what stands around it, then is put further along
-- the trail. Options: autoplay_fire=false, autoplay_scout='Cole'.
if cfg.autoplay and Coop.level ~= "levels/menu" then
  local A = {visited = {}, trail = {}, idx = 1, stuckCells = {}, stucks = 0, reached = 0}
  Coop.autoplayState = A
  local prevAp = Coop.dev

  local function prop(e, k)
    local ok, v = pcall(function() return e[k] end)
    return ok and v or nil
  end

  local function scout()
    local s = A.scout and Game.GetEntity(A.scout)
    if s and (s.Life or 0) > 0 and not Coop.ownerOf(A.scout) and A.scout ~= Coop.localChar() then return s end
    for _, n in ipairs(cfg.autoplay_scout and {cfg.autoplay_scout} or Coop.SQUAD) do
      local e = Game.GetEntity(n)
      if e and (e.Life or 0) > 0 and e.bActive ~= false and e.Active ~= 0 and not Coop.ownerOf(n) and n ~= Coop.localChar() then
        A.scout = n
        Coop.log("autoplay: scout " .. n)
        return e
      end
    end
  end

  local function isTrigger(name)
    return string.find(name, "^AreaTrigger") or string.find(name, "Trigger") or string.find(name, "^New_Level") or
           string.find(name, "^NextLevel")
  end
  local function levelExit(name)
    return string.find(string.lower(name), "level") ~= nil
  end

  local function nextTarget(from)
    local best, bestD
    local e = Game.GetFirst()
    while e ~= nil do
      local n = e.Name
      if n and isTrigger(n) and not A.visited[n] and (A.retryAt[n] or 0) < Net.CoopTime() and prop(e, "bActive") ~= false then
        local p = prop(e, "Pos")
        if p then
          local d = (p - from):mod()
          if levelExit(n) then d = d * 4 + 20000 end
          if not bestD or d < bestD then best, bestD = e, d end
        end
      end
      if e.NextInSlot == "" then break end
      e = Game.GetEntity(e.NextInSlot)
    end
    return best
  end

  -- What stands within 250 units of a body (for a stuck report).
  local function around(p)
    local list = {}
    local e = Game.GetFirst()
    while e ~= nil do
      local q = prop(e, "Pos")
      if q and (q - p):mod() < 250 and e.Name ~= Coop.localChar() then
        list[#list + 1] = string.format("%s(%s,%s)", e.Name, tostring(prop(e, "Type")), tostring(prop(e, "bActive")))
        if #list >= 12 then break end
      end
      if e.NextInSlot == "" then break end
      e = Game.GetEntity(e.NextInSlot)
    end
    return table.concat(list, " ")
  end

  A.usedGates, A.retryAt = {}, {}
  -- The nearest usable gate of this player's character (CoopClaim.gates), within reach.
  local function myGate(u)
    if not (CoopClaim and CoopClaim.gates) then return end
    local best, bestD
    for name, g in pairs(CoopClaim.gates) do
      local o = g.char == u.Name and not A.usedGates[name] and Game.GetEntity(name)
      if o and o.bActive ~= false and o.bArrowCanUse ~= false then
        local d = (o.Pos - u.Pos):mod()
        if d < 6000 and (not bestD or d < bestD) then best, bestD = g, d end
      end
    end
    if best then
      if A.gateLogged ~= best.name then
        A.gateLogged = best.name
        Coop.log(string.format("autoplay: %s goes to %s (%.0f units)", u.Name, best.name, bestD))
      end
      return best, Game.GetEntity(best.name).Pos
    end
  end

  local function nearestEnemy(p)
    local best, bestD
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("WalkChar") and e.TgType == "red" and (e.Life or 0) > 0 and e.bActive ~= false then
        local d = (e.Pos - p):mod()
        if d < 2000 and (not bestD or d < bestD) then best, bestD = e, d end
      end
      if e.NextInSlot == "" then break end
      e = Game.GetEntity(e.NextInSlot)
    end
    return best, bestD
  end

  function Coop.dev()
    if prevAp then prevAp() end
    if Scene and Scene.IsPlaying then return end
    local now = Net.CoopTime()
    local s = scout()
    -- Host: the scout's next walk.
    if Coop.isHost() and s and Coop.frame % 20 == 0 then
      if A.walking and now - A.walkT > 45 then
        Coop.log("autoplay: scout gave up on " .. A.walking)
        A.retryAt[A.walking] = now + 30
        A.walking = nil
      end
      if not A.walking then
        local t = nextTarget(s.Pos)
        if t then
          A.walking, A.walkT = t.Name, now
          local name = t.Name
          local tpos = t.Pos
          local ok, err = pcall(AIGen.GoAndAction, s.Name, tpos, tpos + V3D(0, 0, 50), function(ent)
            if A.walking == name then A.walking = nil end
            local left = ent and (ent.Pos - tpos):mod() or -1
            if left >= 0 and left < 400 then
              A.reached = A.reached + 1
              A.visited[name] = true
            else
              -- (a door or a story action may open the way: tried again later)
              A.retryAt[name] = Net.CoopTime() + 30
            end
            Coop.log(string.format("autoplay: scout %s %s (%.0f units left)", left >= 0 and left < 400 and "reached" or "stopped short of",
              name, left))
          end)
          Coop.log(string.format("autoplay: scout to %s (%.0f units)%s", name, (t.Pos - s.Pos):mod(), ok and "" or (" error " .. tostring(err))))
        end
      end
    end
    if Coop.frame % 200 == 0 then
      local u0 = Game.UsrEntity(0)
      Coop.log(string.format("autoplay: status body %s at %s, scout %s at %s, trail %d/%d, reached %d, stuck %d",
        tostring(u0 and u0.Name), u0 and string.format("%.0f,%.0f", u0.Pos.x, u0.Pos.z) or "-", tostring(s and s.Name),
        s and string.format("%.0f,%.0f", s.Pos.x, s.Pos.z) or "-", A.idx, #A.trail, A.reached, A.stucks))
    end
    -- Every machine: the scout's trail.
    if s and Coop.frame % 5 == 0 then
      local last = A.trail[#A.trail]
      if not last or (s.Pos - last):mod() > 120 then A.trail[#A.trail + 1] = s.Pos end
    end
    -- This player's body follows it.
    local u = Game.UsrEntity(0)
    if not u or (u.Life or 0) <= 0 or Coop.storyDriven[u.Name] then return end
    u.IgnoreUsrControl = 1
    -- As a person plays: the view turns at a hand's speed (not at once), aims before it
    -- shoots, in bursts, a little off; it looks around while it waits.
    local dt = math.min(0.25, math.max(0, now - (A.tickT or now)))
    A.tickT = now
    local function turnTo(yaw, rate, pitch)
      local cur = u.Ang.y
      local diff = (yaw - cur + 540) % 360 - 180
      local step = rate * dt
      if math.abs(diff) > step then diff = diff > 0 and step or -step end
      local y = cur + diff
      u.Ang = V3D(0, y, 0)
      local vp = u.ViewAng and u.ViewAng.x or 0
      u.ViewAng = V3D(vp + ((pitch or 0) - vp) * math.min(1, dt * 4), y, 0)
      return math.abs((yaw - y + 540) % 360 - 180)
    end
    if cfg.autoplay_fire ~= false and Coop.frame % 3 == 0 then A.fireAt = nearestEnemy(u.Pos) end
    local fire = cfg.autoplay_fire ~= false and A.fireAt
    if fire and (fire.Life or 0) > 0 then
      local d = fire.Pos - u.Pos
      A.aimOff = A.aimOff or 0
      if Coop.frame % 45 == 0 then A.aimOff = (math.random() - 0.5) * 6 end
      local off = turnTo(math.deg(math.atan2(-d.x, -d.z)) + A.aimOff, 300, -4)
      u.owc.Shot = (off < 12 and Coop.frame % 40 < 22) and 1 or 0
      u.InCtrl_Walk = 0
      u.InCtrl_Str = (Coop.frame % 120 < 60) and 0.4 or -0.4   -- strafes a little under fire
      A.lastMoveT = now
      return
    end
    u.InCtrl_Str = 0
    u.owc.Shot = 0
    -- A use object only this player's character may use (CoopClaim's gates: Black's
    -- telekinesis, Church's blood seal...): go there and use it, as its player would; the use
    -- goes through the game's own callback (on a client to the host, as a real one does).
    local gate, gatePos = myGate(u)
    if gate then
      local o = Game.GetEntity(gate.name)
      local dg = o.Pos - u.Pos
      if math.sqrt(dg.x * dg.x + dg.z * dg.z) < math.max(120, (gate.radius or 300) * 0.7) then
        A.usedGates[gate.name] = true
        local f = loadstring("return " .. gate.func)
        local okf, fn = pcall(f)
        local okc, err = false, "no function"
        if okf and type(fn) == "function" then okc, err = pcall(fn, u.Name, gate.name, "Use", "") end
        Coop.log("autoplay: " .. u.Name .. " uses " .. gate.name .. " (" .. gate.func .. ")" .. (okc and "" or (" error " .. tostring(err))))
        u.InCtrl_Walk = 0
        return
      end
    end
    while A.trail[A.idx] and (A.trail[A.idx] - u.Pos):mod() < 150 and A.idx < #A.trail do A.idx = A.idx + 1 end
    local tp = gatePos or A.trail[A.idx]
    if not tp or (not gatePos and (tp - u.Pos):mod() < 150) then
      u.InCtrl_Walk = 0
      A.lastMoveT, A.lastPos = now, u.Pos
      -- waiting: looks around
      A.lookBase = A.lookBase or u.Ang.y
      turnTo(A.lookBase + math.sin(now * 0.6) * 45, 60, math.sin(now * 0.4) * 6)
      return
    end
    A.lookBase = nil
    local d = tp - u.Pos
    local dist = math.sqrt(d.x * d.x + d.z * d.z)
    if dist > 4000 then
      u.Pos = tp
      pcall(Game.SetOnFloor, u.Name)
      Coop.log("autoplay: caught up with the trail (teleported)")
      return
    end
    local off = turnTo(math.deg(math.atan2(-d.x, -d.z)), 220, 0)
    -- slows down in a turn, a pace that varies a little, sprints a long way only
    u.InCtrl_Walk = off > 60 and 0.3 or (0.85 + 0.15 * math.sin(now * 0.7))
    u.InCtrl_Sprint = (dist > 900 and off < 20) and 1 or 0
    if A.sideUntil and now < A.sideUntil then u.InCtrl_Str = A.side end
    -- Stuck: no progress along the trail for 2.5 s.
    if not A.lastPos or (u.Pos - A.lastPos):mod() > 60 then
      A.lastPos, A.lastMoveT = u.Pos, now
      if A.sideUntil and now >= A.sideUntil then A.sideUntil = nil end
    elseif now - (A.lastMoveT or now) > 1.5 and not A.sideUntil then
      -- a step aside first, as a person who walked into something does
      A.side = math.random() < 0.5 and 1 or -1
      A.sideUntil = now + 0.8
    elseif now - (A.lastMoveT or now) > 4 then
      A.sideUntil = nil
      local cell = math.floor(u.Pos.x / 300) .. "," .. math.floor(u.Pos.z / 300)
      if not A.stuckCells[cell] then
        A.stuckCells[cell] = true
        A.stucks = A.stucks + 1
        Coop.log(string.format("autoplay: stuck %s at %.0f,%.0f,%.0f heading to %.0f,%.0f | %s", u.Name, u.Pos.x, u.Pos.y,
          u.Pos.z, tp.x, tp.z, around(u.Pos)))
      end
      u.Pos = tp
      pcall(Game.SetOnFloor, u.Name)
      A.lastPos, A.lastMoveT = u.Pos, now
    end
    if Coop.frame % 400 == 0 then
      Coop.log(string.format("autoplay: trail %d/%d, triggers reached %d, stuck spots %d", A.idx, #A.trail, A.reached, A.stucks))
    end
  end
end
