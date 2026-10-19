-- Jericho co-op: per-level entry point (loaded by boot.lua on every level).
--
-- Model: the host runs the real game (AI, enemies, story scripts). Every human controls
-- one squad member. Each side sends the state of the body it controls 20 times a second;
-- the host also sends the state of every squad member, so on a client all bodies except
-- its own follow the host. Bodies driven from the network are "puppets": AI off, moved
-- through the engine's own character control (InCtrl_Walk / InCtrl_Str), with a position
-- snap when they drift too far.
--
-- Messages (text, fields separated by "|"):
--   hello|<wantedChar>                      client -> host, reliable
--   welcome|<peerId>|<level>|<char>         host -> client, reliable
--   own|<char>=<peer>,...                   host -> all, reliable (ownership table)
--   claim|<char>                            client -> host, reliable (player switched)
--   s|<char>|x|y|z|yaw|pitch|walk|str|sprint|life|action|shot   state, unreliable

Coop = {}
Coop.cfg = COOP_CFG
Coop.level = string.lower(Game.GetLevelPath())
Coop.SQUAD = {"Jones", "Cole", "Delgado", "Church", "Rawlings", "Black"}
Coop.SQUAD_SET = {}
for _, name in ipairs(Coop.SQUAD) do Coop.SQUAD_SET[name] = true end
Coop.TICK = 0.05
Coop.SEND_EVERY = 1        -- ticks between state messages (20 Hz)
Coop.SNAP_DIST = 150       -- units; puppet is teleported beyond this error
Coop.NUDGE_DIST = 10       -- units; below this the puppet is left alone
Coop.NUDGE = 0.25          -- fraction of the error removed per tick
Coop.owners = {}           -- char name -> peer id (0 = host)
Coop.remote = {}           -- char name -> latest received state
Coop.storyDriven = {}      -- char name -> true while a story walk drives it (coop_story.lua)
Coop.frame = 0

local cfg = Coop.cfg

function Coop.log(s)
  Net.CoopLog(s)
end

local function v3(v)
  if not v then return "nil" end
  return string.format("%.0f,%.0f,%.0f", v.x, v.y, v.z)
end
Coop.v3 = v3

local function split(s)
  local t = {}
  for part in string.gmatch(s, "([^|]*)|?") do
    t[#t + 1] = part
  end
  if t[#t] == "" then t[#t] = nil end
  return t
end

-- Nicknames travel inside "|"/";"/":"-separated messages and the boot line (single
-- quotes), so keep letters, digits, space, "_" and "-" (cp1251 letters included).
function Coop.cleanNick(s)
  s = string.gsub(tostring(s or ""), "[^%w _%-92-­]", "")
  return string.sub(s, 1, 16)
end

-- "ru" when the game's own strings are Russian (cp1251), else "en".
function Coop.lang()
  if CoopMenu and CoopMenu.lang then return CoopMenu.lang end
  return (string.byte(Game.GetLangStr("Menu_ExitGame") or "", 1) or 0) >= 192 and "ru" or "en"
end

-- Mod sources are UTF-8; the game's fonts use cp1251.
function Coop.cp1251(s)
  return (string.gsub(s, "([\208\209])([\128-\191])", function(a, b)
    local code = (string.byte(a) - 192) * 64 + (string.byte(b) - 128)
    if code == 0x401 then return "\168" end      -- Ё
    if code == 0x451 then return "\184" end      -- ё
    if code >= 0x410 and code <= 0x44F then return string.char(code - 0x410 + 192) end
    return "?"
  end))
end

function Coop.isHost() return cfg.role == "host" end
function Coop.isClient() return cfg.role == "client" end
function Coop.myId() return Coop.isHost() and 0 or cfg.myId end

-- Keep InitLuaLine equal to the boot line for the current COOP_CFG, so the next level
-- starts with this session's state (peer id, body, owners).
function Coop.rearm()
  local line = COOP_BOOT_LINE()
  if Game.Get("InitLuaLine") ~= line then
    Game.Set("InitLuaLine", line)
  end
end

------------------------------------------------------------------------------
-- Ownership
------------------------------------------------------------------------------

function Coop.ownerOf(name)
  return Coop.owners[name]
end

-- True when another human controls this body.
function Coop.isRemoteOwned(name)
  local o = Coop.owners[name]
  return o ~= nil and o ~= Coop.myId()
end

function Coop.ownString()
  local parts = {}
  for name, peer in pairs(Coop.owners) do
    parts[#parts + 1] = name .. "=" .. peer
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

function Coop.parseOwn(s)
  local t = {}
  for name, peer in string.gmatch(s or "", "(%a+)=(%d+)") do
    t[name] = tonumber(peer)
  end
  return t
end

function Coop.broadcastOwners()
  cfg.owners = Coop.ownString()
  Net.CoopSend(-1, 1, "own|" .. cfg.owners)
end

-- Host: give a joining peer the wanted body if it is free, else the first free one.
function Coop.assign(peer, wanted)
  for name, p in pairs(Coop.owners) do
    if p == peer then Coop.owners[name] = nil end
  end
  -- Tutorial locks (Team.UnavaliablePlayers) limit single-player switching only; a body the
  -- story has taken away (CoopStory.taken) or switched off is not free.
  local function free(name)
    local e = Game.GetEntity(name)
    return e and e.Life > 0 and Coop.owners[name] == nil and e.bActive ~= false and
           not (CoopStory and CoopStory.taken and CoopStory.taken(name))
  end
  local pick = nil
  if wanted and free(wanted) then pick = wanted end
  if not pick then
    for _, name in ipairs(Coop.SQUAD) do
      if free(name) then pick = name break end
    end
  end
  if pick then Coop.owners[pick] = peer end
  return pick
end

-- Players may only switch to bodies no other human controls.
function Coop.wrapTeam()
  if not Team or Coop.teamWrapped then return end
  Coop.teamWrapped = true
  local orig = Team.IsPlayerAvaliable
  Team.IsPlayerAvaliable = function(name, ...)
    if Coop.isRemoteOwned(name) then return false end
    return orig(name, ...)
  end
end

------------------------------------------------------------------------------
-- Local player state
------------------------------------------------------------------------------

function Coop.localChar()
  local usr = Game.UsrEntity(0)
  return usr and usr.Name
end

function Coop.stateOf(e)
  local p, a = e.Pos, e.Ang
  local va = e.ViewAng or a
  local shot = e.owc and e.owc.Shot or 0
  return string.format("s|%s|%.0f|%.0f|%.0f|%.1f|%.1f|%.2f|%.2f|%d|%.0f|%s|%d",
    e.Name, p.x, p.y, p.z, a.y, va.x, e.InCtrl_Walk or 0, e.InCtrl_Str or 0,
    e.InCtrl_Sprint or 0, e.Life or 0, tostring(e.Action), shot > 0.5 and 1 or 0)
end

function Coop.sendStates()
  if Coop.isHost() then
    for _, name in ipairs(Coop.SQUAD) do
      local e = Game.GetEntity(name)
      if e and (not Coop.isRemoteOwned(name) or Coop.storyDriven[name]) then
        Net.CoopSend(-1, 0, Coop.stateOf(e))
      end
    end
    -- Relay remote players' latest states to the other clients.
    for name, st in pairs(Coop.remote) do
      if Coop.isRemoteOwned(name) and not Coop.storyDriven[name] and st.raw then
        Net.CoopSend(-1, 0, st.raw)
      end
    end
  else
    local usr = Game.UsrEntity(0)
    if usr and not Coop.storyDriven[usr.Name] then Net.CoopSend(0, 0, Coop.stateOf(usr)) end
  end
end

------------------------------------------------------------------------------
-- Puppets
------------------------------------------------------------------------------

-- Which bodies this machine drives from the network.
function Coop.isPuppet(name)
  -- A story walk (coop_story.lua): the host's AI walks the body, everyone else follows it.
  if Coop.storyDriven and Coop.storyDriven[name] then return not Coop.isHost() end
  if name == Coop.localChar() then return false end
  if Coop.isHost() then return Coop.isRemoteOwned(name) end
  return Coop.isClient() and cfg.myId ~= nil
end

function Coop.releasePuppet(e)
  e.InCtrl_Walk = 0
  e.InCtrl_Str = 0
  if e.owc then e.owc.Shot = 0 end
  if e.oAI then e.oAI.bEnable = true end
end

function Coop.drivePuppets(dt)
  -- Scenes freeze and hide the squad (Scene.HideChars); puppets resume afterwards.
  if Scene and Scene.IsPlaying then return end
  -- NUDGE is the share of the error removed per 0.05 s; scale it to this frame's length.
  local nudge = 1 - (1 - Coop.NUDGE) ^ (math.min(dt, 0.25) / 0.05)
  for _, name in ipairs(Coop.SQUAD) do
    local e = Game.GetEntity(name)
    local st = Coop.remote[name]
    if e and st and CoopTeam and Coop.isPuppet(name) then CoopTeam.syncPuppetLife(e, st) end
    if e and e.Life and e.Life > 0 then
      if Coop.isPuppet(name) and st then
        if e.oAI and e.oAI.bEnable then e.oAI.bEnable = false end
        local target = V3D(st.x, st.y, st.z)
        local pos = e.Pos
        local d = pos - target
        local err = math.sqrt(d.x * d.x + d.z * d.z)
        if err > Coop.SNAP_DIST or math.abs(d.y) > Coop.SNAP_DIST then
          e.Pos = target
          Coop.snaps = (Coop.snaps or 0) + 1
        elseif err > Coop.NUDGE_DIST then
          -- Pull towards the target a little every frame; the walk animation keeps playing.
          e.Pos = V3D(pos.x - d.x * nudge, pos.y, pos.z - d.z * nudge)
        end
        e.Ang = V3D(0, st.yaw, 0)
        e.ViewAng = V3D(st.pitch or 0, st.yaw, 0)
        -- Firing through the body's own control makes the engine play the shot (sound,
        -- flash, animation); damage from puppet shots is dropped in coop_enemies.lua.
        if e.owc then e.owc.Shot = st.shot or 0 end
        e.InCtrl_Walk = st.walk
        e.InCtrl_Str = st.str
        e.InCtrl_Sprint = st.sprint
        Coop.perr = Coop.perr or {}
        Coop.perr[name] = err
        Coop.errN = (Coop.errN or 0) + 1
        Coop.errSum = (Coop.errSum or 0) + err
        Coop.errMax = math.max(Coop.errMax or 0, err)
      elseif Coop.wasPuppet and Coop.wasPuppet[name] then
        Coop.releasePuppet(e)
      end
    end
  end
  Coop.wasPuppet = {}
  for _, name in ipairs(Coop.SQUAD) do
    if Coop.isPuppet(name) and Coop.remote[name] then Coop.wasPuppet[name] = true end
  end
end

------------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------------

function Coop.onMessage(peer, data)
  local f = split(data)
  local kind = f[1]
  if CoopEnemies and CoopEnemies.onMessage(peer, f) then return end
  if CoopTeam and CoopTeam.onMessage(peer, f) then return end
  if CoopScenes and CoopScenes.onMessage(peer, f) then return end
  if CoopSpirit and CoopSpirit.onMessage(peer, f) then return end
  if CoopWorld and CoopWorld.onMessage(peer, f, data) then return end
  if CoopClaim and CoopClaim.onMessage(peer, f) then return end
  if CoopSave and CoopSave.onMessage(peer, f) then return end
  if CoopStory and CoopStory.onMessage(peer, f) then return end
  if CoopSplits and CoopSplits.onMessage(peer, f) then return end
  if CoopPatrol and CoopPatrol.onMessage(peer, f) then return end
  if kind == "s" then
    local name = f[2]
    -- Only the owner (or the host for unowned bodies) may drive a body.
    local owner = Coop.owners[name]
    if Coop.isHost() and owner ~= peer then return end
    Coop.remote[name] = {
      x = tonumber(f[3]), y = tonumber(f[4]), z = tonumber(f[5]),
      yaw = tonumber(f[6]), pitch = tonumber(f[7]),
      walk = tonumber(f[8]), str = tonumber(f[9]), sprint = tonumber(f[10]),
      life = tonumber(f[11]), action = f[12], shot = tonumber(f[13]) or 0, raw = data, t = Net.CoopTime(),
    }
  elseif kind == "hello" and Coop.isHost() then
    local pick = Coop.assign(peer, f[2])
    -- Without the lobby (late join, tests) the host builds the seat list here.
    local seats = {}
    for item in string.gmatch(cfg.seats or ("0:" .. tostring(Coop.localChar()) .. ":1:" .. Coop.cleanNick(cfg.nick)), "[^;]+") do
      if not string.find(item, "^" .. peer .. ":") then seats[#seats + 1] = item end
    end
    seats[#seats + 1] = peer .. ":" .. tostring(pick) .. ":1:" .. Coop.cleanNick(f[3])
    cfg.seats = table.concat(seats, ";")
    Net.CoopSend(-1, 1, "seats|" .. cfg.seats)
    Coop.log("hello from " .. peer .. " wants " .. tostring(f[2]) .. " -> " .. tostring(pick))
    -- welcome|peer|level|char|x|y|z|yaw : the body's current place lets bots start there.
    local where = ""
    local e = pick and Game.GetEntity(pick)
    if e then
      where = string.format("|%.0f|%.0f|%.0f|%.1f", e.Pos.x, e.Pos.y, e.Pos.z, e.Ang.y)
    end
    Net.CoopSend(peer, 1, "welcome|" .. peer .. "|" .. string.sub(Game.GetLevelPath(), 8) .. "|" .. tostring(pick) .. where)
    Coop.broadcastOwners()
  elseif kind == "claim" and Coop.isHost() then
    local name = f[2]
    -- Bodies the story has taken away (coop_story.lua) cannot be claimed.
    local unav = CoopStory and CoopStory.taken and CoopStory.taken(name)
    if not unav and (not Coop.isRemoteOwned(name) or Coop.owners[name] == peer) then
      for n, p in pairs(Coop.owners) do
        if p == peer then Coop.owners[n] = nil end
      end
      Coop.owners[name] = peer
      Coop.broadcastOwners()
    end
  elseif kind == "welcome" and Coop.isClient() then
    cfg.myId = tonumber(f[2])
    cfg.char = f[4]
    Coop.log("welcome id=" .. f[2] .. " level=" .. f[3] .. " char=" .. f[4])
    if string.lower("levels/" .. f[3]) ~= Coop.level then
      Coop.log("following host to " .. f[3])
      Coop.rearm()   -- carry myId/char into the next level
      Game.LoadLevel("Levels/" .. f[3])
    end
  elseif kind == "seats" and Coop.isClient() then
    cfg.seats = f[2]
  elseif kind == "own" then
    if Coop.isClient() then
      Coop.owners = Coop.parseOwn(f[2])
      cfg.owners = f[2]
    end
  end
end

function Coop.onJoin(peer)
  Coop.log("peer " .. peer .. " connected")
  if Coop.isClient() then
    Net.CoopSend(0, 1, "hello|" .. tostring(cfg.char or cfg.want or "") .. "|" .. Coop.cleanNick(cfg.nick))
  end
end

function Coop.onLeave(peer)
  Coop.log("peer " .. peer .. " left")
  for name, p in pairs(Coop.owners) do
    if p == peer then
      Coop.owners[name] = nil
      local e = Game.GetEntity(name)
      if e then Coop.releasePuppet(e) end
    end
  end
  if Coop.isHost() then Coop.broadcastOwners() end
  if CoopSession then CoopSession.onLeave(peer) end
end

-- In the menu level the lobby (coop_menu.lua) owns the session; tests set cfg.auto to
-- host/join and load a level without the menu.
function Coop.menuMode()
  return CoopMenu ~= nil and Coop.level == "levels/menu" and not cfg.auto
end

function Coop.pump()
  for _ = 1, 200 do
    local peer, kind, data = Net.CoopRecv()
    if not peer then return end
    if Coop.menuMode() then
      if kind == "msg" then
        if not CoopMenu.onMessage(peer, split(data)) then Coop.onMessage(peer, data) end
      elseif kind == "join" then CoopMenu.onJoin(peer)
      elseif kind == "leave" then CoopMenu.onLeave(peer) end
    elseif kind == "msg" then Coop.onMessage(peer, data)
    elseif kind == "join" then Coop.onJoin(peer)
    elseif kind == "leave" then Coop.onLeave(peer) end
  end
end

------------------------------------------------------------------------------
-- Local ownership: keep this machine's body in sync with the session
------------------------------------------------------------------------------

-- Act 1 (Al-Khali): the host is Ross, as in the story (Ross cannot possess anyone until he
-- dies at the end of alk_final); the other players hold squad members. Test sessions that
-- name a character (cfg.auto with cfg.char) keep it.
function Coop.actOne()
  return string.find(Coop.level, "^levels/alk_") ~= nil and Game.GetEntity("Ross") ~= nil
end

-- First-person arms and weapons of a squad member. While Ross leads (Act 1) the game builds
-- only his set (Team.CreateTeam: BuildFP.FP_Chars = {"Ross"}): a player in another body had
-- no view model at all. All six are built at level start, as BuildFP.LoadSet does, in the
-- order the game builds them elsewhere: sounds are cached by file name and later sets load
-- some of theirs only from earlier sets' folders (Rawlings' coger3bb3.wav is in Delgado's
-- and Cole's; loading it from his own folder kills the game), so a character not in the
-- level is built too.
Coop.FP_ORDER = {"Jones", "Delgado", "Cole", "Rawlings", "Church", "Black"}

-- Where a sound a set names may really be: the game loads each file name once per level,
-- from the folder of whichever set or character names it first, and in Act 1 some of
-- those are absent (Delgado's Abanil_Launch.wav is his third-person character's).
Coop.SOUND_DIRS = {"Sounds/FX/"}
for _, n in ipairs({"Ross", "Jones", "Delgado", "Cole", "Rawlings", "Church", "Black"}) do
  table.insert(Coop.SOUND_DIRS, "Sounds/FP/FP_" .. n .. "/")
  table.insert(Coop.SOUND_DIRS, "Sounds/Chars/" .. n .. "/")
end

-- LoadSounds with every ac.AddSoundRes checked first: a file missing from the folder it is
-- asked from kills the game (CheckFailed), so it is taken from a folder that has it, or left out.
function Coop.loadFPSounds(name)
  local real = Act.GetClass("FP_" .. name)
  local getClass, set = Act.GetClass, Game.Set
  local path, missing = "", {}
  -- Game.FileExist looks in the current PathInPackFile folder.
  local proxy = setmetatable({}, {
    __index = function(_, k)
      local v = real[k]
      if type(v) == "function" then return function(_, ...) return v(real, ...) end end
      return v
    end,
    __newindex = function(_, k, v)
      if k ~= "AddSoundRes" or Game.FileExist(v) then real[k] = v return end
      for _, d in ipairs(Coop.SOUND_DIRS) do
        set("PathInPackFile", d)
        if Game.FileExist(v) then
          real.AddSoundRes = v
          set("PathInPackFile", path)
          return
        end
      end
      set("PathInPackFile", path)
      table.insert(missing, v)
    end,
  })
  Act.GetClass = function(n, ...) if n == "FP_" .. name then return proxy end return getClass(n, ...) end
  Game.Set = function(k, v, ...)
    if k == "PathInPackFile" then path = v or "" end
    return set(k, v, ...)
  end
  local ok, err = pcall(_G["FP_" .. name .. "Sound"].LoadSounds, "FP_" .. name)
  Act.GetClass, Game.Set = getClass, set
  if #missing > 0 then Coop.log("first-person set " .. name .. ": no " .. table.concat(missing, ", ")) end
  if not ok then error(err) end
end

function Coop.buildFP(name)
  if Act.GetClass("FP_" .. name) ~= nil then return end
  Game.PreloadLibrary("Scripts/FP/FP_" .. name .. ".lua", "FP_" .. name)
  _G["FP_" .. name].CreateFP()
  Game.PreloadLibrary("Scripts/Sound/FP_" .. name .. "Sound.lua", "FP_" .. name .. "Sound")
  Coop.loadFPSounds(name)
end

function Coop.ensureFP(name)
  if not (name and Coop.SQUAD_SET[name] and Act and Act.GetClass and Game.PreloadLibrary) then return end
  if Act.GetClass("FP_" .. name) ~= nil then return end
  for _, n in ipairs(Coop.FP_ORDER) do
    local ok, err = pcall(Coop.buildFP, n)
    Coop.log("first-person set " .. n .. ": " .. (ok and "built" or tostring(err)))
    if n == name then return end
  end
end

function Coop.installFP()
  if Coop.fpInstalled or not (Team and Team.SwitchSoldier) then return end
  Coop.fpInstalled = true
  if Coop.actOne() then Coop.ensureFP(Coop.FP_ORDER[#Coop.FP_ORDER]) end
  local orig = Team.SwitchSoldier
  Team.SwitchSoldier = function(from, to, ...)
    Coop.ensureFP(to)
    return orig(from, to, ...)
  end
end

-- A body this player may take at level start: in the level and not held by someone else.
function Coop.freeFor(name)
  local owner = name and Coop.owners[name]
  local e = name and Game.GetEntity(name)
  return e ~= nil and e.bActive ~= false and (owner == nil or owner == Coop.myId()) and
         not (CoopStory and CoopStory.taken and CoopStory.taken(name))
end

-- The body to move into when a level starts: the last one held, else the lobby seat, else
-- the first free squad member (a story split may have taken the body away).
function Coop.startChar()
  if Coop.isHost() and Coop.actOne() and not (cfg.auto and cfg.char) then return "Ross" end
  for _, name in ipairs({cfg.char, cfg.seatChar}) do
    if name ~= "Ross" and Coop.freeFor(name) then return name end
  end
  for _, name in ipairs(CoopMenu and CoopMenu.CHAR_ORDER or Coop.SQUAD) do
    if Coop.freeFor(name) then return name end
  end
end

function Coop.updateLocalOwnership()
  local mine = Coop.localChar()
  if not mine then return end
  -- Test option: this player holds no body (a 4th player in a 3-body level), so it becomes
  -- a spirit (coop_spirit.lua).
  if cfg.nobody then
    for n, p in pairs(Coop.owners) do
      if p == Coop.myId() then Coop.owners[n] = nil end
    end
    return
  end
  -- At level start (and after a welcome) move once to the character picked in the lobby;
  -- after that the player switches freely (cfg.char follows the body they hold).
  if not Coop.switchedTo and (Coop.isHost() or cfg.myId) then
    local want = Coop.startChar()
    Coop.switchedTo = want or mine
    if want and mine ~= want then
      -- A tutorial lock on the seat's character must not keep its player out of it.
      local locks = Team and Team.UnavaliablePlayers
      local was = locks and locks[want]
      if locks then locks[want] = nil end
      local ok = Team and Team.SwitchSoldier and Team.SwitchSoldier(mine, want)
      if locks then locks[want] = was end
      Coop.log("switch " .. mine .. " -> " .. want .. " " .. tostring(ok))
      if ok then return end
    end
  end
  if Coop.isHost() then
    if Coop.owners[mine] ~= 0 then
      for n, p in pairs(Coop.owners) do
        if p == 0 then Coop.owners[n] = nil end
      end
      Coop.owners[mine] = 0
      cfg.char = mine
      Coop.broadcastOwners()
    end
  elseif Coop.isClient() and cfg.myId then
    if Coop.owners[mine] ~= cfg.myId and Coop.lastClaim ~= mine then
      Coop.lastClaim = mine
      cfg.char = mine
      Net.CoopSend(0, 1, "claim|" .. mine)
    end
  end
end

------------------------------------------------------------------------------
-- Tick
------------------------------------------------------------------------------

-- The engine calls the OnRenderDebug function every rendered frame, whatever the game
-- time speed (the scheduler follows game time and nearly stops when a scene slows time
-- down). Puppets are driven every frame; network work runs at TICK in real time.
Coop.FRAME_HOOK = "Coop.onFrame"

function Coop.onFrame()
  local now = Net.CoopTime()
  local dt = now - (Coop.lastFrame or now)
  Coop.lastFrame = now
  local ok, err = pcall(Coop.frameUpdate, now, dt)
  if not ok then
    Coop.errors = (Coop.errors or 0) + 1
    if Coop.errors <= 10 then Coop.log("frame error: " .. tostring(err)) end
  end
end

function Coop.inSession()
  return cfg.role == "host" or cfg.role == "client"
end

function Coop.frameUpdate(now, dt)
  if Coop.devFrame then pcall(Coop.devFrame, dt) end
  if Coop.inSession() then Coop.drivePuppets(dt) end
  if CoopHud and Coop.inSession() then
    local ok, err = pcall(CoopHud.update)
    if not ok and (Coop.hudErrors or 0) < 5 then
      Coop.hudErrors = (Coop.hudErrors or 0) + 1
      Coop.log("hud error: " .. tostring(err))
    end
  end
  if CoopEnemies and CoopEnemies.installed and Coop.isClient() then CoopEnemies.driveEnemies(dt) end
  if CoopSpirit and CoopSpirit.active then pcall(CoopSpirit.frame, dt) end
  if CoopEnemies and CoopEnemies.installed and Scene then CoopEnemies.updateSceneLabel() end
  if CoopScenes and Coop.inSession() then
    CoopScenes.install()
    CoopScenes.installQTE()
    local ok, err = pcall(CoopScenes.update, dt)
    if not ok and (Coop.sceneErrors or 0) < 5 then
      Coop.sceneErrors = (Coop.sceneErrors or 0) + 1
      Coop.log("scene POV error: " .. tostring(err))
    end
  end
  if now >= (Coop.nextTick or 0) then
    Coop.nextTick = now + Coop.TICK
    Coop.rearm()
    Coop.update()
  end
end

function Coop.update()
  Coop.frame = Coop.frame + 1
  -- Keep running while unfocused for the length of a session (a paused host would
  -- freeze everyone); outside a session the game behaves as in single player.
  -- Test runs (dev) keep running unfocused in the menu too.
  local bg = (Coop.inSession() or cfg.dev) and 1 or 0
  if bg ~= Coop.bgState and Net.CoopBackground then
    Net.CoopBackground(bg)
    Coop.bgState = bg
  end
  Coop.wrapTeam()
  Coop.pump()
  if CoopEnemies and (Coop.isHost() or Coop.isClient()) then
    CoopEnemies.install()
    if CoopEnemies.installed then
      CoopEnemies.update()
      if CoopWorld then CoopWorld.install() end
    end
  end
  if CoopTeam and Coop.inSession() and Coop.level ~= "levels/menu" then CoopTeam.update() end
  if CoopClaim then
    local ok, err = pcall(CoopClaim.update)
    if not ok and (Coop.claimErrors or 0) < 5 then
      Coop.claimErrors = (Coop.claimErrors or 0) + 1
      Coop.log("claim error: " .. tostring(err))
    end
  end
  if CoopStory and Coop.inSession() then
    local ok, err = pcall(CoopStory.update)
    if not ok and (Coop.storyErrors or 0) < 5 then
      Coop.storyErrors = (Coop.storyErrors or 0) + 1
      Coop.log("story error: " .. tostring(err))
    end
  end
  if CoopPatrol and Coop.inSession() then
    local ok, err = pcall(CoopPatrol.update)
    if not ok and (Coop.patrolErrors or 0) < 5 then
      Coop.patrolErrors = (Coop.patrolErrors or 0) + 1
      Coop.log("patrol error: " .. tostring(err))
    end
  end
  if CoopSplits and Coop.inSession() then
    local ok, err = pcall(CoopSplits.update)
    if not ok and (Coop.splitErrors or 0) < 5 then
      Coop.splitErrors = (Coop.splitErrors or 0) + 1
      Coop.log("splits error: " .. tostring(err))
    end
  end
  if CoopSession and Coop.inSession() then
    local ok, err = pcall(CoopSession.update)
    if not ok and (Coop.sessionErrors or 0) < 5 then
      Coop.sessionErrors = (Coop.sessionErrors or 0) + 1
      Coop.log("session error: " .. tostring(err))
    end
  end
  if CoopSpirit then
    local ok, err = pcall(CoopSpirit.update)
    if not ok and (Coop.spiritErrors or 0) < 5 then
      Coop.spiritErrors = (Coop.spiritErrors or 0) + 1
      Coop.log("spirit error: " .. tostring(err))
    end
  end
  if Coop.inSession() then
    Coop.updateLocalOwnership()
    if Coop.frame % Coop.SEND_EVERY == 0 then Coop.sendStates() end
    if Coop.isHost() and Coop.frame % 40 == 0 then Coop.broadcastOwners() end
  end
  if Coop.menuMode() then CoopMenu.update() end
  if Coop.bot then Coop.bot() end
  if Coop.dev then Coop.dev() end
  if Coop.frame % 100 == 0 then Coop.report() end
end

function Coop.start()
  Game.Set("OnRenderDebug", Coop.FRAME_HOOK)
end

function Coop.report()
  local errAvg = Coop.errN and Coop.errN > 0 and Coop.errSum / Coop.errN or -1
  local parts = {"f=" .. Coop.frame, "me=" .. tostring(Coop.localChar()), "own=" .. Coop.ownString(),
                 Net.CoopStatus(), "snaps=" .. (Coop.snaps or 0),
                 string.format("err_avg=%.0f err_max=%.0f", errAvg, Coop.errMax or -1),
                 CoopEnemies and CoopEnemies.report() or "", CoopWorld and CoopWorld.report() or ""}
  Coop.errN, Coop.errSum, Coop.errMax = 0, 0, 0
  for _, name in ipairs(Coop.SQUAD) do
    local st = Coop.remote[name]
    local e = Game.GetEntity(name)
    if st and e and Coop.isPuppet(name) then
      parts[#parts + 1] = name .. ":err=" .. string.format("%.0f", Coop.perr and Coop.perr[name] or -1) ..
                          ",act=" .. tostring(e.Action)
    end
  end
  Coop.log(table.concat(parts, " "))
end

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------

-- Restore the ownership table carried over from the previous level.
if cfg.owners then Coop.owners = Coop.parseOwn(cfg.owners) end

do
  -- Side instances (the Lost Patrol) wrap the network calls: load before anything sends.
  local ok, err = pcall(dofile, COOP_DIR .. "coop_inst.lua")
  if not ok then Coop.log("inst load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_save.lua")
  if not ok then Coop.log("save load error: " .. tostring(err)) end
end

local status = Net.CoopStatus()
if cfg.auto and Coop.isHost() and string.find(status, "role=none") then
  Coop.log("host start: " .. Net.CoopHost(cfg.port or 28100, 4))
elseif cfg.auto and Coop.isClient() and string.find(status, "role=none") then
  Coop.log("client start: " .. Net.CoopJoin(cfg.addr or "127.0.0.1", cfg.port or 28100))
elseif not cfg.auto and Coop.level == "levels/menu" and not string.find(status, "role=none") then
  -- Back in the main menu after a session: the session is over.
  Net.CoopClose()
  if CoopSave then pcall(CoopSave.endSession) end
  cfg.role, cfg.myId, cfg.char, cfg.owners, cfg.seats, cfg.loaded = nil, nil, nil, nil, nil, nil
  cfg.inst, cfg.instAuth, cfg.instIds, cfg.instOf, cfg.instAuthOnHub, cfg.netRole, cfg.realId = nil, nil, nil, nil, nil, nil, nil
  status = Net.CoopStatus()
end

if Coop.level == "levels/menu" and not cfg.auto then
  local ok, err = pcall(dofile, COOP_DIR .. "coop_menu.lua")
  if not ok then Coop.log("menu error: " .. tostring(err)) end
end
if Coop.level ~= "levels/menu" then
  if Coop.inSession() then
    local okfp, errfp = pcall(Coop.installFP)
    if not okfp then Coop.log("first-person sets error: " .. tostring(errfp)) end
  end
  local ok, err = pcall(dofile, COOP_DIR .. "coop_enemies.lua")
  if not ok then Coop.log("enemies error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_hud.lua")
  if not ok then Coop.log("hud load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_team.lua")
  if not ok then Coop.log("team load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_scenes.lua")
  if not ok then Coop.log("scenes load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_spirit.lua")
  if not ok then Coop.log("spirit load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_world.lua")
  if not ok then Coop.log("world load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_claim.lua")
  if not ok then Coop.log("claim load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_session.lua")
  if not ok then Coop.log("session load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_story.lua")
  if not ok then Coop.log("story load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_splits.lua")
  if not ok then Coop.log("splits load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_patrol.lua")
  if not ok then Coop.log("patrol load error: " .. tostring(err)) end
end
if cfg.dev then pcall(dofile, COOP_DIR .. "dev.lua") end
-- Test sessions start without the lobby: protect the profile from the first level on.
if CoopSave and Coop.inSession() and Coop.level ~= "levels/menu" then CoopSave.beginSession() end

Coop.log("coop.lua loaded level=" .. Coop.level .. " role=" .. tostring(cfg.role) .. " " .. status)

function Coop.menuLoad()
  cfg.loaded = true
  -- Tests: start the level at a given spawn point (checkpoint).
  if cfg.dev and cfg.prespawn then
    local var = "level." .. string.lower(cfg.level) .. ".Spawn.Point"
    Game.CreateSaveVar(var, tostring(cfg.prespawn))
    Game.SetSaveVar(var, tostring(cfg.prespawn))
  end
  Game.Set("InitLuaLine", COOP_BOOT_LINE())
  Coop.log("loading " .. cfg.level)
  Game.LoadLevel("Levels/" .. cfg.level)
end

if Coop.level == "levels/menu" and cfg.auto then
  if Coop.isHost() or cfg.role == "solo" then
    if cfg.level and not cfg.loaded then
      Game.AddScheduledFunc(Game.GetTime() + 0.5, "CoopMenu", "Coop.menuLoad", 0)
    end
  end
  -- Clients wait in the menu for the host's welcome, which names the level to load.
end
Coop.start()
