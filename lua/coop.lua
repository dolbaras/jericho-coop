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
--   hello|<wantedChar>|<nick>|<version>     client -> host, reliable
--   welcome|<peerId>|<level>|<char>         host -> client, reliable
--   own|<char>=<peer>,...                   host -> all, reliable (ownership table)
--   claim|<char>                            client -> host, reliable (player switched)
--   s|<char>|x|y|z|yaw|pitch|walk|str|sprint|life|action|shot   state, unreliable

Coop = {}
Coop.VERSION = "0.2.1"      -- players must have the same (lobby check); tools/package.ps1 checks it
Coop.cfg = COOP_CFG
Coop.level = string.lower(Game.GetLevelPath())
Coop.SQUAD = {"Jones", "Cole", "Delgado", "Church", "Rawlings", "Black"}
Coop.SQUAD_SET = {}
for _, name in ipairs(Coop.SQUAD) do Coop.SQUAD_SET[name] = true end
Coop.TICK = 0.05
Coop.SEND_EVERY = 1        -- ticks between state messages (20 Hz)
Coop.SNAP_DIST = 250       -- units; puppet is teleported beyond this error
Coop.FOLLOW = 0.9          -- fraction of the error to the interpolated place removed per 0.05 s
Coop.FOLLOW_Y = 40         -- units; height is left to the engine (floor) below this error
-- Other bodies are drawn a little in the past, between two received states (snapshot
-- interpolation): the delay covers the send interval plus the network's jitter (fork
-- MAK-PIVO/jericho-coop: 107-201 visible jumps a minute of a running puppet before, 1.5-4.5 after).
Coop.INTERP_MIN = 0.07     -- seconds
Coop.INTERP_MAX = 0.25
Coop.EXTRAP_MAX = 0.2      -- seconds a body keeps moving on its last velocity when states stop
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

-- A squad body by name for the per-frame loops: a body the level does not have is not looked
-- up again for a second (the engine writes a log line for every lookup of a missing entity).
Coop.absent = {}
function Coop.squadEnt(name)
  local now = Net.CoopTime()
  if (Coop.absent[name] or 0) > now then return nil end
  local e = Game.GetEntity(name)
  if not e then Coop.absent[name] = now + 1 end
  return e
end

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
-- A squad member's name in the game's language (language file keys Church, Cole...: "Черч").
function Coop.charName(id)
  local s = id and Game.GetLangStr(id)
  if not s or s == "" or string.find(s, "^%?") then s = id end
  return s
end

-- Centred text that may need several lines (Scorer text items do not break lines: one long
-- line runs off 4:3 screens and SMOD-sized fonts). The game's own Scorer.SplitString breaks it
-- by the font's real width, one item per line (name, name.."#2", ...), as Menu.TextMultiline
-- does. CentralText centres on the item's current X, so X is put back first each time or
-- every change of the text moves it further left.
Coop.TEXT_WIDTH = 520
function Coop.setCentered(it, text, x)
  if it.Text ~= text then
    it.Text = text
    it.X = x or 320
    it.CentralText = 1
  end
end

-- opts: x, y (first line), font, color, effect, step (between lines), width.
function Coop.textBlock(name, text, opts)
  opts = opts or {}
  local font = opts.font or (Menu and Menu.SmallFont) or "ScrapMedium"
  -- Explicit breaks ("\n") first, then the font's width for each part.
  local lines = {}
  for part in string.gmatch(text .. "\n", "([^\n]*)\n") do
    local split
    if Scorer.SplitString and part ~= "" then
      local ok, r = pcall(Scorer.SplitString, part, font, opts.width or Coop.TEXT_WIDTH)
      if ok and type(r) == "table" and #r > 0 then split = r end
    end
    for _, l in ipairs(split or {part}) do lines[#lines + 1] = l end
  end
  local n = 0
  for k, line in ipairs(lines) do
    n = k
    local key = k == 1 and name or (name .. "#" .. k)
    local it = Scorer.GetItem(0, key)
    if not it then
      it = Scorer.NewItem(0, key, "Text")
      it.Font = font
      it.Effect = opts.effect or "Shadow"
    end
    it.Y = (opts.y or 240) + (k - 1) * (opts.step or 24)
    Coop.setCentered(it, line, opts.x)
    if opts.color then it.Color = opts.color end
    it.Visible = 1
  end
  Coop.textBlockHide(name, n + 1)
end

-- Hides the block's lines from line `from` on (1 = all of it).
function Coop.textBlockHide(name, from)
  local k = from or 1
  while true do
    local it = Scorer.GetItem(0, k == 1 and name or (name .. "#" .. k))
    if not it then
      if k > 8 then break end
    else
      it.Visible = 0
    end
    k = k + 1
  end
end

function Coop.cleanNick(s)
  s = string.gsub(tostring(s or ""), "[^%w _%-92-­]", "")
  return string.sub(s, 1, 16)
end

-- "ru" when the game's own strings are Russian (cp1251), else "en".
function Coop.lang()
  if cfg.lang then return cfg.lang end   -- tests: the other language on this install
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

-- A second player on the same PC (split screen, coop_split.lua) is an owner of its own:
-- the machine's peer id + P2, so every owner still holds one body.
Coop.P2 = 8

-- The machine (peer) an owner id plays on.
function Coop.peerOf(owner)
  if owner and owner >= Coop.P2 then return owner - Coop.P2 end
  return owner
end

-- Owners that play on this machine: its player, and its split screen player.
function Coop.isMine(owner)
  return owner ~= nil and Coop.myId() ~= nil and Coop.peerOf(owner) == Coop.myId()
end

-- A body this machine plays: its player's, or its split screen player's (coop_split.lua).
function Coop.isLocalBody(name)
  return name ~= nil and (name == Coop.localChar() or Coop.isMine(Coop.owners[name]))
end

-- True when a message from this peer may act for this body: its own, or its machine's split
-- screen player's (that one's owner id is peer + P2, its messages come from the peer).
function Coop.heldBy(name, peer)
  local o = Coop.owners[name or ""]
  return o ~= nil and Coop.peerOf(o) == peer
end

-- True when another human controls this body.
function Coop.isRemoteOwned(name)
  local o = Coop.owners[name]
  return o ~= nil and not Coop.isMine(o)
end

-- Bodies the players of this machine control (user 0, and user 1 in split screen).
function Coop.isLocalPlayer(name)
  if name == nil then return false end
  if name == Coop.localChar() then return true end
  return CoopSplit ~= nil and CoopSplit.on and CoopSplit.char == name
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
  -- The flashlight is the player's own (one camera light per game): on while its timer runs.
  local usr = Game.UsrEntity(0)
  local flash = usr and usr.Name == e.Name and (tonumber(Game.Get("FPSFlashLightTimeOn")) or 0) > 0
  if CoopSplit and CoopSplit.on and CoopSplit.char == e.Name then flash = CoopSplit.flash end
  Coop.stateSeq = (Coop.stateSeq or 0) + 1
  -- The weapon slot in hand: 0/1 the weapons, 2/3 a power used as a weapon (Delgado's fire
  -- arm, Church's blade...). The puppet takes the same slot, so it shows and fires that.
  local wc = e.oWeapCtrl
  local slot = wc and tonumber(wc.iSlot) or -1
  return string.format("s|%s|%.0f|%.0f|%.0f|%.1f|%.1f|%.2f|%.2f|%d|%.0f|%s|%d|%d|%d|%.3f|%d",
    e.Name, p.x, p.y, p.z, a.y, va.x, e.InCtrl_Walk or 0, e.InCtrl_Str or 0,
    e.InCtrl_Sprint or 0, e.Life or 0, tostring(e.Action), shot > 0.5 and 1 or 0, flash and 1 or 0,
    Coop.stateSeq, Net.CoopTime(), slot)
end

function Coop.sendStates()
  if Coop.isHost() then
    for _, name in ipairs(Coop.SQUAD) do
      local e = Coop.squadEnt(name)
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
    local p2 = CoopSplit and CoopSplit.on and CoopSplit.body()
    if p2 then Net.CoopSend(0, 0, Coop.stateOf(p2)) end
  end
end

------------------------------------------------------------------------------
-- Puppets
------------------------------------------------------------------------------

-- Which bodies this machine drives from the network.
function Coop.isPuppet(name)
  -- A story walk (coop_story.lua): the host's AI walks the body, everyone else follows it.
  if Coop.storyDriven and Coop.storyDriven[name] then return not Coop.isHost() end
  if Coop.isLocalPlayer(name) then return false end
  if Coop.isHost() then return Coop.isRemoteOwned(name) end
  return Coop.isClient() and cfg.myId ~= nil
end

-- Root motion: locomotion actions (UseDisp = 1) move a body by their animation. On a puppet
-- that moved it a second time on top of the network position, unevenly from frame to frame
-- (fork MAK-PIVO/jericho-coop, from the earlier JerichoCoop mod). A puppet's current action
-- plays without displacement. Action objects are shared by the bodies of a class: the actions
-- this machine's players are playing (player 1, and player 2 in split screen) keep theirs.
Coop.rootMotion = {}   -- "class:action" -> {class, action, value} original UseDisp

local function actionKey(e)
  local ok, cls, act, obj = pcall(function()
    local a = e.oActCtrl.oAction
    return e.oActCtrl.oActClass.Name, a.Name, a
  end)
  if not ok or type(cls) ~= "string" or type(act) ~= "string" then return nil end
  return cls .. ":" .. act, cls, act, obj
end

local function restoreRootMotion(rec)
  pcall(function()
    local c = Act and Act.GetClass and Act.GetClass(rec.class)
    local a = c and c:GetAct(rec.action)
    if a and tonumber(a.UseDisp) ~= rec.value then a.UseDisp = rec.value end
  end)
end

function Coop.suppressRootMotion(e, localKeys)
  local key, cls, act, obj = actionKey(e)
  if not key then return end
  local rec = Coop.rootMotion[key]
  if not rec then
    local v = tonumber(obj.UseDisp)
    if v == nil then return end
    rec = {class = cls, action = act, value = v}
    Coop.rootMotion[key] = rec
  end
  -- Turns rotate the body through their displacement: left alone.
  if (localKeys and localKeys[key]) or string.find(act, "Turn", 1, true) then
    restoreRootMotion(rec)
  elseif tonumber(obj.UseDisp) ~= 0 then
    pcall(function() obj.UseDisp = 0 end)
  end
end

-- The actions this machine's players are playing: their root motion put back every frame.
function Coop.keepLocalRootMotion()
  local keys = {}
  local bodies = {Game.UsrEntity(0)}
  if CoopSplit and CoopSplit.on and CoopSplit.body then bodies[2] = CoopSplit.body() end
  for _, b in pairs(bodies) do
    local key = b and actionKey(b)
    if key then
      keys[key] = true
      local rec = Coop.rootMotion[key]
      if rec then restoreRootMotion(rec) end
    end
  end
  return keys
end

function Coop.restoreAllRootMotion()
  for _, rec in pairs(Coop.rootMotion) do restoreRootMotion(rec) end
end

function Coop.releasePuppet(e)
  e.InCtrl_Walk = 0
  e.InCtrl_Str = 0
  if e.owc then e.owc.Shot = 0 end
  if e.oAI then e.oAI.bEnable = true end
  -- Back to the engine: collision on, and actions move bodies again.
  if Coop.puppetNoCollide and Coop.puppetNoCollide[e.Name] ~= nil then
    pcall(function() e.bIgnoreCollision = Coop.puppetNoCollide[e.Name] end)
    Coop.puppetNoCollide[e.Name] = nil
  end
  Coop.restoreAllRootMotion()
end

-- History of a body's states for interpolation (Coop.hist[name]): ordered by the sender's
-- clock (st.rt); out-of-order and repeated states are dropped (a relay may reorder
-- unreliable messages). Returns false for a dropped state.
Coop.hist = Coop.hist or {}
function Coop.pushState(name, st, interval)
  local h = Coop.hist[name]
  local now = st.t
  if not st.rt then st.rt = now end   -- a sender without times: its receive time
  if h and h.n > 0 then
    local last = h[h.n]
    -- A new sender (owner change, restarted level): start over.
    if st.rt < last.rt - 2 or st.rt > last.rt + 5 then h = nil end
  end
  if not h then
    h = {n = 0, jit = 0, interval = interval or Coop.TICK}
    Coop.hist[name] = h
  end
  if h.n > 0 and st.rt <= h[h.n].rt then
    Coop.stale = (Coop.stale or 0) + 1
    return false
  end
  -- Clock offset: the smallest (local - sender) time seen lately is the least delayed state;
  -- it may creep up 1 ms per state so a drifting clock is followed.
  local off = now - st.rt
  if not h.off or off < h.off then h.off = off else h.off = h.off + 0.001 end
  h.jit = h.jit * 0.9 + (off - h.off) * 0.1
  h.n = h.n + 1
  h[h.n] = st
  -- About two seconds.
  if h.n > 48 then
    table.remove(h, 1)
    h.n = h.n - 1
  end
  return true
end

local function lerpAngle(a, b, u)
  return a + ((b - a + 180) % 360 - 180) * u
end

-- Where a body should be drawn now: interpolated between the two states around
-- (now - delay) on the sender's clock, or carried on its last velocity for a short while.
function Coop.puppetTarget(name, now)
  local h = Coop.hist[name]
  if not h or h.n == 0 then return nil end
  local delay = math.max(Coop.INTERP_MIN, math.min(Coop.INTERP_MAX, h.interval * 1.4 + 2 * h.jit))
  local rr = now - h.off - delay
  local a, b = h[1], h[h.n]
  if rr <= a.rt then
    return {x = a.x, y = a.y, z = a.z, yaw = a.yaw, pitch = a.pitch or 0, st = a}
  end
  if rr >= b.rt then
    local p = h.n > 1 and h[h.n - 1]
    local ext = math.min(rr - b.rt, Coop.EXTRAP_MAX)
    if not p or b.rt - p.rt <= 0 or ext <= 0 then
      return {x = b.x, y = b.y, z = b.z, yaw = b.yaw, pitch = b.pitch or 0, st = b}
    end
    local k = ext / (b.rt - p.rt)
    return {x = b.x + (b.x - p.x) * k, y = b.y, z = b.z + (b.z - p.z) * k,
            yaw = b.yaw, pitch = b.pitch or 0, st = b}
  end
  local i = h.n - 1
  while i > 1 and h[i].rt > rr do i = i - 1 end
  a, b = h[i], h[i + 1]
  local u = (rr - a.rt) / math.max(b.rt - a.rt, 1e-3)
  return {
    x = a.x + (b.x - a.x) * u, y = a.y + (b.y - a.y) * u, z = a.z + (b.z - a.z) * u,
    yaw = lerpAngle(a.yaw, b.yaw, u), pitch = (a.pitch or 0) + ((b.pitch or 0) - (a.pitch or 0)) * u,
    st = u < 0.5 and a or b,
  }
end

-- A puppet takes the weapon slot its owner holds (oWeapCtrl.iDesiredSlot, the way the
-- characters' scripts switch). Slots 2/3 are powers used as weapons: the scripts point the
-- main and second weapon at them too (delgado.lua PressSpecial), and back to 0/1 after.
function Coop.syncSlot(e, slot)
  local wc = e.oWeapCtrl
  -- The owner's engine accepted this slot for the same body, so the puppet has it too; a
  -- slot out of range would stop the engine (WeaponCtrl.cpp:180 "i>=0 && i<nSlots").
  if not wc or not slot or slot < 0 or slot > 3 or slot ~= math.floor(slot) then return end
  local ok = pcall(function()
    if tonumber(wc.iSlot) == slot or tonumber(wc.iDesiredSlot) == slot then return end
    wc.iDesiredSlot = slot
    if slot >= 2 then
      wc.idMainWeapon, wc.idSecondWeapon = slot, slot
    elseif tonumber(wc.idMainWeapon) and tonumber(wc.idMainWeapon) >= 2 then
      wc.idMainWeapon, wc.idSecondWeapon = 0, 1
    end
    Coop.log("puppet " .. e.Name .. " takes weapon slot " .. slot)
  end)
  if not ok then Coop.slotErrors = (Coop.slotErrors or 0) + 1 end
end

function Coop.drivePuppets(dt)
  -- Scenes freeze and hide the squad (Scene.HideChars); puppets resume afterwards.
  if Scene and Scene.IsPlaying then return end
  -- FOLLOW is the share of the error removed per 0.05 s; scale it to this frame's length.
  local follow = 1 - (1 - Coop.FOLLOW) ^ (math.min(dt, 0.25) / 0.05)
  local now = Net.CoopTime()
  local localKeys = Coop.keepLocalRootMotion()
  Coop.puppetNoCollide = Coop.puppetNoCollide or {}
  for _, name in ipairs(Coop.SQUAD) do
    local e = Coop.squadEnt(name)
    local st = Coop.remote[name]
    if e and st and CoopTeam and Coop.isPuppet(name) then CoopTeam.syncPuppetLife(e, st) end
    if e and e.Life and e.Life > 0 then
      local tg = Coop.isPuppet(name) and st and Coop.puppetTarget(name, now)
      if tg then
        if e.oAI and e.oAI.bEnable then e.oAI.bEnable = false end
        -- The network places this body: colliding with the local player or other soldiers
        -- made them shove each other and the body shook (fork MAK-PIVO/jericho-coop).
        if Coop.puppetNoCollide[name] == nil then
          local ok, was = pcall(function() return e.bIgnoreCollision end)
          Coop.puppetNoCollide[name] = ok and was or false
          pcall(function() e.bIgnoreCollision = true end)
        end
        Coop.suppressRootMotion(e, localKeys)
        local pos = e.Pos
        local dx, dy, dz = tg.x - pos.x, tg.y - pos.y, tg.z - pos.z
        local err = math.sqrt(dx * dx + dz * dz)
        if err > Coop.SNAP_DIST or math.abs(dy) > Coop.SNAP_DIST then
          e.Pos = V3D(tg.x, tg.y, tg.z)
          Coop.snaps = (Coop.snaps or 0) + 1
        else
          -- The body walks on its own inputs (animation, collision); this keeps it on the
          -- interpolated path every frame, without a dead zone that would make it jump.
          -- Height stays with the engine (floor contact) unless it is clearly off.
          local y = math.abs(dy) > Coop.FOLLOW_Y and pos.y + dy * follow or pos.y
          e.Pos = V3D(pos.x + dx * follow, y, pos.z + dz * follow)
        end
        e.Ang = V3D(0, tg.yaw, 0)
        e.ViewAng = V3D(tg.pitch, tg.yaw, 0)
        -- Firing through the body's own control makes the engine play the shot (sound,
        -- flash, animation); damage from puppet shots is dropped in coop_enemies.lua.
        -- Shots use the newest state (no added delay), movement inputs the drawn one.
        if e.owc then e.owc.Shot = st.shot or 0 end
        Coop.syncSlot(e, st.slot)
        e.InCtrl_Walk = tg.st.walk
        e.InCtrl_Str = tg.st.str
        e.InCtrl_Sprint = tg.st.sprint
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

-- Other players' flashlights: the game has one camera-bound flashlight (the local player's),
-- so another player's beam is a spot light at their body's weapon, aimed with their view.
-- How a SpotLight takes its settings (dev.lua 'lighttest', 2026-10-20): Ang (0,0,0) points
-- down, (90 + view pitch, yaw, 0) along the view (pitch up is positive); the cone works only
-- with a projector texture (else it lights all around); bLightOverShoot adds a second spot
-- the opposite way; Del takes effect on the next frame.
Coop.FLASH_NODE = "NodePosHierarchy_DF_Burst_A"

function Coop.puppetLights()
  if cfg.puppetlights == false then return end
  local scene = Scene and Scene.IsPlaying
  for _, name in ipairs(Coop.SQUAD) do
    local id = "CoopFlash" .. name
    -- Looked up only once made (the engine logs every lookup of a missing entity).
    Coop.flashLights = Coop.flashLights or {}
    local light = Coop.flashLights[name] and Game.GetEntity(id)
    local e = Coop.squadEnt(name)
    local st = Coop.remote[name]
    -- A split screen player's body (coop_split.lua) is driven here, its flashlight too.
    local p2 = CoopSplit and CoopSplit.on and CoopSplit.char == name
    local on = not scene and e and e.Life > 0 and
               (p2 and CoopSplit.flash or (st and st.flash and Coop.isPuppet(name)))
    if on then
      local pos = e[Coop.FLASH_NODE] or (e.Pos + V3D(0, 150, 0))
      local va = p2 and e.ViewAng
      local ang = va and V3D(va.x + 90, va.y, 0) or V3D((st.pitch or 0) + 90, st.yaw or 0, 0)
      if not light then
        light = PhysicsObj.CreateObj(id, "SpotLight", pos, ang, false)
        Coop.flashLights[name] = true
        light.LightConeInner00 = 15
        light.LightConeOuter00 = 32
        light.LightRange00 = 1400
        light.LightIntens00 = 1
        light.LightColor00 = V4D(255, 245, 225, 255)
        -- The flashlight's own texture (lights.ini Light20; SMOD sets FPSFlashLightTexture).
        light.bLightProjEnable00 = true
        local tex = tonumber(Game.Get("FPSFlashLightTexture"))
        light.ProjID00 = (tex and tex > 0) and tex or 20
        light.bLightOverShoot00 = false
        light.LightAttStart00 = 0
        light.LightDotAtt00 = 0.5
        light.LightDirVector00 = V4D(0, 0, 0, 0)
        light.bLightShadow00 = (tonumber(Game.Get("FPSFlashLightShadows")) or 0) ~= 0
        light.LightShadowMapBias00 = 1
        light.LightQualityDist00 = 2000
        light.bLightSectorEnable00 = true
        Coop.log("flashlight of " .. name .. " on")
      else
        light.Pos = pos
        light.Ang = ang
      end
    elseif light then
      light:Del()
      Coop.flashLights[name] = nil
      Coop.log("flashlight of " .. name .. " off")
    end
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
  if CoopPowers and CoopPowers.onMessage(peer, f, data) then return end
  if kind == "s" then
    local name = f[2]
    -- Only the owner (or the host for unowned bodies) may drive a body.
    local owner = Coop.owners[name]
    if Coop.isHost() and Coop.peerOf(owner) ~= peer then return end
    local st = {
      x = tonumber(f[3]), y = tonumber(f[4]), z = tonumber(f[5]),
      yaw = tonumber(f[6]), pitch = tonumber(f[7]),
      walk = tonumber(f[8]), str = tonumber(f[9]), sprint = tonumber(f[10]),
      life = tonumber(f[11]), action = f[12], shot = tonumber(f[13]) or 0, flash = f[14] == "1",
      raw = data, t = Net.CoopTime(), seq = tonumber(f[15]), rt = tonumber(f[16]), slot = tonumber(f[17]),
    }
    if not st.x or not st.z then return end
    if Coop.pushState(name, st) then Coop.remote[name] = st end
  elseif kind == "jump" then
    -- Another player jumped (SMOD's jump, coop_smod.lua): the same push for their body here.
    local name = f[2]
    if Coop.isHost() then
      if Coop.peerOf(Coop.owners[name]) ~= peer then return end
      Net.CoopSend(-1, 1, data)
    end
    local e = Game.GetEntity(name)
    local vy = tonumber(f[3])
    if e and vy and Coop.isPuppet(name) and e.Life > 0 and e.Vel then
      local v = e.Vel
      e.Vel = V3D(v.x, vy, v.z)
      Coop.lastJump = {name = name, y = e.Pos.y, peak = e.Pos.y, frame = Coop.frame}
    end
  elseif kind == "hello" and Coop.isHost() then
    if f[4] ~= Coop.VERSION then   -- another co-op version (before 0.2: no field)
      Coop.log("hello from " .. peer .. " with version " .. tostring(f[4]) .. ": refused")
      Net.CoopClose(peer)
      return
    end
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
  elseif kind == "claim2" and Coop.isHost() then
    -- A client's split screen player (coop_split.lua) holds this body now ("" none).
    local name, id = f[2] or "", peer + Coop.P2
    local unav = name ~= "" and CoopStory and CoopStory.taken and CoopStory.taken(name)
    if not unav and (name == "" or not Coop.isRemoteOwned(name) or Coop.owners[name] == id) then
      for n, p in pairs(Coop.owners) do
        if p == id then Coop.owners[n] = nil end
      end
      if name ~= "" then Coop.owners[name] = id end
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
    Net.CoopSend(0, 1, "hello|" .. tostring(cfg.char or cfg.want or "") .. "|" .. Coop.cleanNick(cfg.nick) .. "|" ..
      Coop.VERSION)
  end
end

function Coop.onLeave(peer)
  Coop.log("peer " .. peer .. " left")
  for name, p in pairs(Coop.owners) do
    if Coop.peerOf(p) == peer then   -- (its split screen player 2 too: owner peer + Coop.P2)
      Coop.owners[name] = nil
      local e = Game.GetEntity(name)
      if e then Coop.releasePuppet(e) end
    end
  end
  if Coop.isHost() then
    Coop.broadcastOwners()
    -- A player who left is no longer expected at the next level start (CoopEnemies gate).
    if cfg.seats then
      local seats = {}
      for item in string.gmatch(cfg.seats, "[^;]+") do
        -- (with the player's split screen player 2, peer + Coop.P2)
        if Coop.peerOf(tonumber(string.match(item, "^(%d+):"))) ~= peer then seats[#seats + 1] = item end
      end
      cfg.seats = table.concat(seats, ";")
      Net.CoopSend(-1, 1, "seats|" .. cfg.seats)
      Coop.rearm()
    end
  end
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
  -- A story line alone (coop_storysolo.lua): its character, even where the level starts with
  -- that body put away (Alk_City: Alpha is hidden until Omega reaches it).
  if cfg.storyline and cfg.char then
    local e = Game.GetEntity(cfg.char)
    if e then
      if e.bActive == false then e.bActive = true end
      return cfg.char
    end
  end
  for _, name in ipairs({cfg.char, cfg.seatChar}) do
    if name ~= "Ross" and Coop.freeFor(name) then return name end
  end
  for _, name in ipairs(CoopMenu and CoopMenu.CHAR_ORDER or Coop.SQUAD) do
    if Coop.freeFor(name) then return name end
  end
end

-- A player left without a body: a first-person scene skipped in its first moments (the host
-- skips the opening of the desert at once in tests; a fast unanimous skip can too) ended on a
-- client now and then (1 run in 15 before 0.2.1, a few more since the client keeps its own
-- scene chains) with the characters the scene hid (Scene.HideChars: Active 0, TimeSpeed 0)
-- never shown again, the player's body among them. Once no scene or scene camera is up for
-- 2 s: the game's own Scene.UnhideChars, and the body taken back as the game's switch does.
Coop.NOBODY_WAIT = 2
function Coop.reclaimBody()
  if Coop.level == "levels/menu" or Game.UsrEntity(0) ~= nil then Coop.noBodySince = nil return end
  if (Scene and Scene.IsPlaying) or Game.GetEntity("InterpolusCamera") or Game.GetEntity("Cameraman") then
    Coop.noBodySince = nil
    return
  end
  local now = Net.CoopTime()
  Coop.noBodySince = Coop.noBodySince or now
  if now - Coop.noBodySince < Coop.NOBODY_WAIT then return end
  Coop.noBodySince = nil
  if Scene and Scene.UnhideChars and Scene.HidenChars and next(Scene.HidenChars) then
    pcall(Scene.UnhideChars)
    Scene.HidenChars = {}
    Coop.log("no body after a scene: the scene's hidden characters shown again")
  end
  local name = cfg.char
  if not name or (Coop.owners[name] ~= nil and not Coop.isMine(Coop.owners[name])) then
    for n, p in pairs(Coop.owners) do
      if p == Coop.myId() then name = n break end
    end
  end
  local t = name and Game.GetEntity(name)
  if not t or (t.Life or 0) <= 0 or t.UsrControl == 1 then return end
  if t.Active == 0 then t.Active = 1 end
  if t.TimeSpeed == 0 then t.TimeSpeed = 1 end
  t.UsrControl = 0
  t.InCtrl_UseFPS = 1
  t.InCtrl_ResetSlot = 1
  if t.oAI then t.oAI.bEnable = false end
  pcall(t.ResetControl, t)
  local cam = Game.GetEntity("MainCam")
  if cam then
    Game.SetCam(0, "MainCam")
    cam.MainTarget, cam.Target = name, name
  end
  if Input.GetActionSet() ~= "Walk" then Input.SetActionSet("Walk") end
  if Team and Team.ResetUsrAnim then pcall(Team.ResetUsrAnim, t) end
  Coop.log("no body after a scene: " .. name .. " taken back")
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
  if not Coop.lastFrame then Coop.log("first frame hook") end
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
  if CoopStorySolo then
    local ok, err = pcall(CoopStorySolo.update)
    if not ok and (Coop.storyErrors or 0) < 5 then
      Coop.storyErrors = (Coop.storyErrors or 0) + 1
      Coop.log("story solo error: " .. tostring(err))
    end
  end
  if CoopSplit and CoopSplit.on then
    local ok, err = pcall(CoopSplit.frame)
    if not ok and (Coop.splitErrors or 0) < 5 then
      Coop.splitErrors = (Coop.splitErrors or 0) + 1
      Coop.log("split error: " .. tostring(err))
    end
  end
  if Coop.inSession() then
    Coop.drivePuppets(dt)
    if CoopPowers then
      local okp, errp = pcall(CoopPowers.frame, now)
      if not okp and (Coop.powerErrors or 0) < 5 then
        Coop.powerErrors = (Coop.powerErrors or 0) + 1
        Coop.log("powers error: " .. tostring(errp))
      end
    end
    local ok, err = pcall(Coop.puppetLights)
    if not ok and (Coop.lightErrors or 0) < 5 then
      Coop.lightErrors = (Coop.lightErrors or 0) + 1
      Coop.log("puppet light error: " .. tostring(err))
    end
  end
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
    -- Step from the previous tick, not from now: at 30 fps "now + TICK" ticked every other
    -- frame (15 Hz, logs 0.2.1). After a long frame (loading) the schedule restarts from now.
    -- (fork MAK-PIVO/jericho-coop)
    Coop.nextTick = math.max((Coop.nextTick or now) + Coop.TICK, now - Coop.TICK)
    Coop.rearm()
    Coop.update()
  end
end

-- Control lock watchdog (fork MAK-PIVO/jericho-coop, from the earlier JerichoCoop mod). Stock
-- story scripts lock the player (IgnoreUsrControl = 1) and unlock later, often from a scheduled
-- map callback; on a client those callbacks are the host's, and a script line that errors there
-- (it reads something only the host has) never reaches its unlock: the player was left without
-- control. A lock nobody in this mod holds is released after 12 s, on clients only (the host's
-- story releases its own locks: a 12 s release cut a Brandenburg cinematic short).
Coop.LOCK_LIMIT = 12

function Coop.modHoldsControl()
  if not Coop.isClient() then return true end
  local me = Coop.localChar() or ""
  if Coop.storyDriven and Coop.storyDriven[me] then return true end
  if Scene and Scene.IsPlaying then return true end
  if CoopEnemies and CoopEnemies.curtain then return true end
  if CoopSpirit and CoopSpirit.active then return true end
  -- Menus, astral projections, a squad switch's travel: not the "Walk" set.
  if Input and Input.GetActionSet and Input.GetActionSet() ~= "Walk" then return true end
  -- Split screen: player 1 driven from their pad during player 2's astral projection.
  if CoopSplit and CoopSplit.drives and next(CoopSplit.drives) then return true end
  if cfg.storyline then return true end
  local sp = CoopSplits
  if sp and sp.G6 and sp.G6.holding then return true end
  if sp and sp.G15 and sp.G15.struggle and not (sp.G15.freed or {})[me] then return true end
  local ok, grab = pcall(function() return QTE and QTE.InGame and QTE.InGame.Blocked end)
  if ok and grab then return true end
  return cfg.bot ~= nil
end

function Coop.controlWatchdog()
  local usr = Game.UsrEntity(0)
  if not usr or usr.IgnoreUsrControl ~= 1 or Coop.modHoldsControl() then
    Coop.lockSince = nil
    return
  end
  local now = Net.CoopTime()
  Coop.lockSince = Coop.lockSince or now
  if now - Coop.lockSince > Coop.LOCK_LIMIT then
    usr.IgnoreUsrControl = 0
    Coop.lockSince = nil
    Coop.log("control lock on " .. tostring(usr.Name) .. " released after " .. Coop.LOCK_LIMIT .. " s")
  end
end

function Coop.update()
  Coop.frame = Coop.frame + 1
  if Coop.inSession() then
    local ok, err = pcall(Coop.reclaimBody)
    if not ok and (Coop.reclaimErrors or 0) < 3 then
      Coop.reclaimErrors = (Coop.reclaimErrors or 0) + 1
      Coop.log("reclaim error: " .. tostring(err))
    end
  end
  -- (in split screen coop_split.lua runs it per view, unless the screen is whole for a scene)
  if CoopRoss and not (CoopSplit and CoopSplit.on and CoopSplit.shownFor ~= nil) and Coop.level ~= "levels/menu" then
    local ok, err = pcall(CoopRoss.update)
    if not ok and (Coop.rossErrors or 0) < 5 then
      Coop.rossErrors = (Coop.rossErrors or 0) + 1
      Coop.log("ross error: " .. tostring(err))
    end
  end
  if CoopSplit and not CoopSplit.on and Coop.frame >= 10 then
    local ok, err = pcall(CoopSplit.autoStart)
    if not ok then Coop.log("split start error: " .. tostring(err)) end
  end
  -- SMOD (autoexec.lua, re-run every level) slows the whole world while the squad menu is
  -- open: in a session that would slow one machine only.
  -- Lobby option: QTEs pass by themselves on every machine (the game's own QTEMode 2; its
  -- bonus codes set QTEMode again on every level load).
  if cfg.qte == "auto" and Coop.inSession() and Coop.level ~= "levels/menu" and Game.Get("QTEMode") ~= 2 then
    Game.Set("QTEMode", 2)
  end
  if _G.TEAMMENUSLOWMO and Coop.inSession() then
    _G.TEAMMENUSLOWMO = false
    Coop.log("SMOD: squad menu slow motion off for the session")
  end
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
      if CoopWorld then
        CoopWorld.install()
        local ok, err = pcall(CoopWorld.update)
        if not ok and (Coop.worldErrors or 0) < 5 then
          Coop.worldErrors = (Coop.worldErrors or 0) + 1
          Coop.log("world error: " .. tostring(err))
        end
      end
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
    if Coop.level ~= "levels/menu" then pcall(Coop.controlWatchdog) end
    if Coop.level ~= "levels/menu" and CoopPowers then
      local okp, errp = pcall(CoopPowers.update)
      if not okp and (Coop.powerErrors or 0) < 5 then
        Coop.powerErrors = (Coop.powerErrors or 0) + 1
        Coop.log("powers error: " .. tostring(errp))
      end
    end
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
    local e = Coop.squadEnt(name)
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
  -- (test sessions over Steam: the lobby too)
  if cfg.net == "steam" and Net.CoopSteam then Coop.log("steam host: " .. tostring(Net.CoopSteam("host", "4"))) end
elseif cfg.auto and Coop.isClient() and string.find(status, "role=none") then
  if cfg.steamjoin and Net.CoopSteam then
    -- (test sessions over Steam: the host's lobby id)
    Coop.log("client start (steam): " .. tostring(Net.CoopSteam("join", tostring(cfg.steamjoin))))
  else
    Coop.log("client start: " .. Net.CoopJoin(cfg.addr or "127.0.0.1", cfg.port or 28100))
  end
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
  ok, err = pcall(dofile, COOP_DIR .. "coop_powers.lua")
  if not ok then Coop.log("powers load error: " .. tostring(err)) end
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
  if cfg.storyline then
    ok, err = pcall(dofile, COOP_DIR .. "coop_storysolo.lua")
    if not ok then Coop.log("story solo load error: " .. tostring(err)) end
  end
end
-- SMOD next to co-op (texts, the same rules for everyone): menu and levels alike.
do
  local ok, err = pcall(dofile, COOP_DIR .. "coop_smod.lua")
  if not ok then Coop.log("smod load error: " .. tostring(err)) end
  -- Split screen in one game: off at every load, on again in a level with a player 2.
  ok, err = pcall(dofile, COOP_DIR .. "coop_split.lua")
  if not ok then Coop.log("split load error: " .. tostring(err)) end
  -- Act 1: Ross's body for the other players (split screen and session alike).
  ok, err = pcall(dofile, COOP_DIR .. "coop_ross.lua")
  if not ok then Coop.log("ross load error: " .. tostring(err)) end
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
