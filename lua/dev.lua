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
