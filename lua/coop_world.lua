-- Jericho co-op: world state. Each machine runs its own copy of the level; story effects
-- (doors, levers, objects switched on or off, radio chats, scheduled steps) come from the
-- level's MapCallbacks, which only the host runs. The host sends every top-level callback
-- call to the clients, which replay it with the same scripts:
--   cb|<callback>|<triggered entity>|<arg>|<arg>|...   host -> clients
--   use|<callback>|<arg>|...                            client -> host (the client used an object)
-- During a replay the client still drops enemies, saves and level changes (the host sends
-- those itself), and never switches its own player to another body.
-- "Is this the player?" checks accept any body a human holds, not only the host's.
CoopWorld = {}
local W = CoopWorld
W.depth = 0
W.SEP = "|"

local function encode(v)
  local t = type(v)
  if t == "string" then return "s" .. string.gsub(v, "|", "\1") end
  if t == "number" then return "n" .. tostring(v) end
  if t == "boolean" then return v and "b1" or "b0" end
  return "-"
end

local function decode(s)
  local k, v = string.sub(s, 1, 1), string.sub(s, 2)
  if k == "s" then return (string.gsub(v, "\1", "|")) end
  if k == "n" then return tonumber(v) end
  if k == "b" then return v == "1" end
  return nil
end

-- A human holds this body (the host's own, or a client's).
function W.isHuman(name)
  local e = name and Game.GetEntity(name)
  if not e then return false end
  return e.UsrControl == 0 or Coop.ownerOf(name) ~= nil
end

-- AreaTriggers.IsPlayer(id, Name): vanilla accepts only UsrControl == 0, i.e. the host's
-- body; clients' bodies are network-driven (-1) there.
function W.installIsPlayer()
  if W.isPlayerInstalled or not AreaTriggers or not AreaTriggers.IsPlayer then return end
  W.isPlayerInstalled = true
  W.origIsPlayer = AreaTriggers.IsPlayer
  AreaTriggers.IsPlayer = function(id, Name)
    if not Coop.inSession() then return W.origIsPlayer(id, Name) end
    local nam = W.replaying and W.replayTriggered or Game.GetTriggeredEntity(id)
    if Name ~= nil and nam ~= Name then return false end
    return W.isHuman(nam) or (CoopClaim and CoopClaim.acceptsAI(nam)) or false
  end
end

function W.installHost()
  if W.installed or not MapCallbacks then return end
  W.installed = true
  local n = 0
  for name, f in pairs(MapCallbacks) do
    if type(f) == "function" then
      n = n + 1
      MapCallbacks[name] = function(...)
        W.depth = W.depth + 1
        if W.depth == 1 then W.send(name, ...) end
        local r = {pcall(f, ...)}
        W.depth = W.depth - 1
        if not r[1] then
          Coop.log("callback " .. name .. " error: " .. tostring(r[2]))
          return nil
        end
        return unpack(r, 2)
      end
    end
  end
  Coop.log("world: " .. n .. " map callbacks replicated")
end

function W.send(name, ...)
  local args = {...}
  local trig = ""
  if type(args[2]) == "number" then
    local ok, nam = pcall(Game.GetTriggeredEntity, args[2])
    if ok and nam then trig = nam end
  end
  local parts = {"cb", name, trig}
  for i = 1, math.max(#args, 3) do parts[#parts + 1] = encode(args[i]) end
  Net.CoopSend(-1, 1, table.concat(parts, W.SEP))
  W.sent = (W.sent or 0) + 1
end

-- A use callback run for another player (replayed on a client, or run on the host for a
-- client's use) plays its first-person animation on this machine's own arms otherwise
-- (MakeFP.LaunchFpsAnm(0, "TKCombo1Hit1"): Black's telekinesis on everyone's view).
function W.installFPAnm()
  if W.fpAnmInstalled or not MakeFP or not MakeFP.LaunchFpsAnm then return end
  W.fpAnmInstalled = true
  local orig = MakeFP.LaunchFpsAnm
  MakeFP.LaunchFpsAnm = function(id, ...)
    local u = W.forUser
    if id == 0 and u and Coop.SQUAD_SET[u] and not Coop.isLocalBody(u) then return end
    return orig(id, ...)
  end
end

-- The cool use of an object (MakeFP.CoolUse: Delgado's light door o191, levers, valves) locks the user
-- (IgnoreUsrControl, Invulnerable), pins its body with MoveMePosAng and links its model to the
-- object's node; the first-person animation it then plays ends all of that. Replayed for a body
-- another machine drives (its UsrControl is -1: no first-person view here, LaunchFpsAnm(-1) finds no
-- user), the animation never plays and the pin stays: the engine put the puppet back at the place it
-- had when the callback ran, every second frame, for the rest of the level (perpetual snap storms of
-- the same body, 500-1000 snaps per run, Delgado at the light door of Rom_Outskirts; the owner's
-- minute-long storms). A puppet takes only the object's half of it: the object plays its action.
function W.installCoolUse()
  if W.coolUseInstalled or not MakeFP or not MakeFP.CoolUse or Coop.cfg.cooluse == false then return end
  W.coolUseInstalled = true
  local orig = MakeFP.CoolUse
  MakeFP.CoolUse = function(ent, obj, entAct, objAct, node, ...)
    if type(ent) == "string" and Coop.inSession() and Coop.isPuppet(ent) then
      local o = type(obj) == "string" and Game.GetEntity(obj)
      if o and objAct and objAct ~= "" then pcall(function() o.Action = objAct end) end
      W.coolUsePuppets = (W.coolUsePuppets or 0) + 1
      Coop.log(string.format("world: cool use of %s by the puppet %s: only the object acts (%s)", tostring(obj), ent, tostring(objAct)))
      return
    end
    return orig(ent, obj, entAct, objAct, node, ...)
  end
end

function W.installClient()
  if W.installed then return end
  W.installed = true
  -- A replay must not move this player into another body (forced story switches are
  -- decided per human elsewhere).
  if Team and Team.SwitchSoldier then
    local orig = Team.SwitchSoldier
    Team.SwitchSoldier = function(...)
      if W.replaying then return false end
      return orig(...)
    end
  end
end

-- Client: the guarded callback (coop_enemies guard) was called by this machine's engine.
-- If it is the local player using an object, the host must run it.
function W.onLocalCallback(name, ...)
  local usr = select(1, ...)
  if type(usr) == "string" and Coop.isLocalBody(usr) then
    local parts = {"use", name}
    local args = {...}
    for i = 1, math.max(#args, 3) do parts[#parts + 1] = encode(args[i]) end
    Net.CoopSend(0, 1, table.concat(parts, W.SEP))
    Coop.log("world: use " .. name .. " by " .. usr .. " sent to host")
  end
end

local function splitMsg(data)
  local t = {}
  for item in string.gmatch(data .. W.SEP, "([^|]*)|") do t[#t + 1] = item end
  return t
end

function W.replay(name, trig, args)
  local f = MapCallbacks and MapCallbacks[name]
  if not f then return end
  W.replaying, W.replayTriggered = true, trig ~= "" and trig or nil
  Coop.replay = true
  local origTrig = Game.GetTriggeredEntity
  Game.GetTriggeredEntity = function(id) return W.replayTriggered or origTrig(id) end
  W.forUser = type(args[1]) == "string" and args[1] or nil
  local ok, err = pcall(f, unpack(args, 1, args.n))
  W.forUser = nil
  Game.GetTriggeredEntity = origTrig
  Coop.replay = false
  W.replaying, W.replayTriggered = false, nil
  W.replayed = (W.replayed or 0) + 1
  if not ok then Coop.log("world: replay " .. name .. " error: " .. tostring(err)) end
end

function W.onMessage(peer, f, data)
  local kind = f[1]
  if W.onObjectMessage and W.onObjectMessage(peer, f) then return true end
  if kind ~= "cb" and kind ~= "use" then return false end
  local t = splitMsg(data)
  if kind == "cb" and Coop.isClient() then
    local args = {n = #t - 3}
    for i = 4, #t do args[i - 3] = decode(t[i]) end
    W.replay(t[2], t[3], args)
  elseif kind == "use" and Coop.isHost() then
    local f2 = MapCallbacks and MapCallbacks[t[2]]
    local args = {n = #t - 2}
    for i = 3, #t do args[i - 2] = decode(t[i]) end
    -- Only the body this peer holds may use objects in its name.
    if f2 and type(args[1]) == "string" and Coop.heldBy(args[1], peer) then
      Coop.log("world: " .. args[1] .. " (peer " .. peer .. ") uses " .. t[2])
      W.forUser = args[1]
      local ok, err = pcall(f2, unpack(args, 1, args.n))
      W.forUser = nil
      if not ok then Coop.log("world: use " .. t[2] .. " error: " .. tostring(err)) end
    end
  end
  return true
end

function W.install()
  if not Coop.inSession() or Coop.level == "levels/menu" then return end
  W.installIsPlayer()
  if Coop.isHost() then W.installHost() elseif Coop.isClient() then W.installClient() end
end

function W.report()
  local doors, dead = 0, 0
  for _ in pairs(W.doors or {}) do doors = doors + 1 end
  for _ in pairs(W.dead or {}) do dead = dead + 1 end
  local props = 0
  for _ in pairs(W.props or {}) do props = props + 1 end
  return string.format("world: sent=%d replayed=%d doors=%d dead=%d digest_misses=%d props=%d moved_sent=%d moved_set=%d prop_errors=%d",
    W.sent or 0, W.replayed or 0, doors, dead, W.digestMisses or 0, props, W.propsSent or 0, W.propsSet or 0, W.propErrors or 0)
end

------------------------------------------------------------------------------
-- Doors and breakable objects (fork MAK-PIVO/jericho-coop, 2026-10-20). Map callbacks cover most story doors, but
-- doors are also opened by level init, scenes, enemy scripts (psichiccommander) and object
-- deaths (wwii_britishbomb), and an object broken by one player's shot broke on that
-- machine only. Approach taken from the earlier JerichoCoop mod (70_world.lua,
-- 68_world_digest.lua), on this mod's messages:
--   door|<name>|1/0        host -> clients: a door's state (the host decides doors)
--   kill|<name>            both ways: a physics object's Life reached 0; the receiver sets
--                          Life = 0 and the engine plays the object's own death (pieces,
--                          sound, a lamp going dark, level OnDeath callbacks)
--   wd|<count>|<sum>       host -> clients every 10 s: digest of doors and dead objects
--   wdneed                 client -> host after two differing digests in a row
--   wstate|D:name+;K:name  host -> one client: every door and dead object (catch-up, resend)
--   blk|<name>|1/0         host -> clients: an invisible blocker's collision (B: in wstate)
--   mv|name,x,y,z,ax,ay,az;...  map props moved (pushed, thrown, knocked over) that came to
--                          rest: from the machine that moved them to the host, which sets
--                          them and sends them on; also to a peer that joins
------------------------------------------------------------------------------
W.doors = {}      -- name -> true open / false closed, as set on this machine
W.objects = {}    -- name -> last seen alive (physics objects created with Life)
W.dead = {}       -- name -> true: killed here or on another machine
W.DIGEST_EVERY = 10
-- Invisible blockers (InvisibleBlocker and other map objects the level's scripts switch with
-- bMapCollision): the host's state on every machine. The scripts that switch them off often
-- run at the end of a team chat or an AI walk of the player's own body, which a client's copy
-- may not finish: the client met walls nobody else had (alk_tomb Block1/Block2/Bloquer0, the
-- owner's Steam test: "everyone passes, the client walks into a wall in the arches").
W.blockers = {}   -- name -> collision on (as last seen / sent)
W.OBJECT_POLL = 0.25

local function now() return Net.CoopTime() end

-- A map prop, not a part of a character's ragdoll ("Bip ..." bones are PxBodyPhysics too; setting
-- their Life killed a squad member's body part in a test) nor a piece a break leaves (each
-- machine makes its own).
-- Only the map's own props: the level's object list (MapPhysicObjects, kept after the level
-- made them), its DM_Physic_ dummies and "OB_..." ones. Other physics bodies are made by
-- characters' scripts (Delgado's reload throws "BoE_Delgado_..." parts) on one machine only.
function W.mapNames()
  if W.mapNameSet then return W.mapNameSet end
  local set = {}
  local list = MapPhysicObjects and MapPhysicObjects.PhysicObjects
  if type(list) == "table" then
    for _, desc in pairs(list) do
      if type(desc) == "table" then
        for _, kv in ipairs(desc) do
          if type(kv) == "table" and kv[1] == "Name" and type(kv[2]) == "string" then set[kv[2]] = true end
        end
      end
    end
  end
  W.mapNameSet = set
  return set
end

function W.isProp(name)
  if type(name) ~= "string" or #name >= 64 or string.find(name, "Bip", 1, true) or
     string.find(string.lower(name), "piece", 1, true) then
    return false
  end
  return W.mapNames()[name] or string.sub(name, 1, 3) == "OB_" or string.sub(name, 1, 10) == "DM_Physic_"
end

function W.trackObject(o)
  local ok, name, life = pcall(function() return o.Name, tonumber(o.Life) end)
  if ok and W.isProp(name) and life and life > 0 then
    W.objects[name] = true
  end
end

function W.installObjects()
  if W.objectsInstalled or not PhysicsObj or not PhysicsObj.OpenDoor then return end
  W.objectsInstalled = true
  for _, fn in ipairs({"OpenDoor", "CloseDoor"}) do
    local orig, open = PhysicsObj[fn], fn == "OpenDoor"
    PhysicsObj[fn] = function(name, ...)
      if type(name) == "string" and W.doors[name] ~= open then
        W.doors[name] = open
        if Coop.isHost() and Coop.inSession() then Net.CoopSend(-1, 1, "door|" .. name .. "|" .. (open and 1 or 0)) end
      end
      return orig(name, ...)
    end
    W["orig" .. fn] = orig
  end
  if PhysicsObj.CreateObj then
    local origCreate = PhysicsObj.CreateObj
    PhysicsObj.CreateObj = function(...)
      local o = origCreate(...)
      if o then W.trackObject(o) end
      return o
    end
  end
  -- Objects the map created before this ran.
  local e, n = Game.GetFirst(), 0
  while e ~= nil do
    -- Check the type before reading Life: reading a missing property makes the engine log
    -- an error per read (coop_enemies.lua isEnemy). Physics props are PxBodyPhysics.
    -- Only the map's props ("OB_..."): other physics bodies are parts of characters
    -- (ragdolls); setting their Life killed a squad member's body part in a test.
    -- Any name: the levels' crates, barrels, bottles, chairs, lamps are "Pedro548" and the
    -- like, and only "OB_..." ones were tracked before 0.2.3 (a box broken on one machine
    -- stayed whole on the other, owner's report).
    local ok, body = pcall(function() return e:IsType("PxBodyPhysics") end)
    if ok and body and W.isProp(e.Name) then
      local before = W.objects[e.Name]
      W.trackObject(e)
      if W.objects[e.Name] and not before then n = n + 1 end
      W.trackProp(e)
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  local m = 0
  for _ in pairs(W.props) do m = m + 1 end
  Coop.log("world: doors and objects tracked (" .. n .. " breakable, " .. m .. " movable props on the map)")
  W.findBlockers()
end

-- The map's objects created with a bMapCollision of their own (MapPhysicObjects keeps the
-- level's object list after creating them).
function W.findBlockers()
  local list = MapPhysicObjects and MapPhysicObjects.PhysicObjects
  local n = 0
  if type(list) ~= "table" then return end
  for _, desc in pairs(list) do
    local name, coll
    if type(desc) == "table" then
      for _, kv in ipairs(desc) do
        if type(kv) == "table" then
          if kv[1] == "Name" then name = kv[2] elseif kv[1] == "bMapCollision" then coll = kv[2] end
        end
      end
    end
    if type(name) == "string" and coll ~= nil and Game.GetEntity(name) then
      local ok, on = pcall(function() return Game.GetEntity(name).bMapCollision end)
      if ok and on ~= nil then
        W.blockers[name] = on and true or false
        n = n + 1
      end
    end
  end
  if n > 0 then Coop.log("world: " .. n .. " blockers followed") end
end

function W.setBlocker(name, on)
  W.blockers[name] = on
  local e = Game.GetEntity(name)
  if not e then return false end
  local ok, cur = pcall(function() return e.bMapCollision end)
  if ok and cur ~= on then
    pcall(function() e.bMapCollision = on end)
    Coop.log("world: blocker " .. name .. (on and " on" or " off") .. " as on the host")
    return true
  end
  return false
end

-- Host: a blocker switched by the level's scripts here.
function W.pollBlockers()
  for name, was in pairs(W.blockers) do
    local e = Game.GetEntity(name)
    local ok, on = pcall(function() return e and e.bMapCollision end)
    if ok and on ~= nil and (on and true or false) ~= was then
      W.blockers[name] = on and true or false
      Net.CoopSend(-1, 1, "blk|" .. name .. "|" .. (on and 1 or 0))
      Coop.log("world: blocker " .. name .. (on and " on" or " off"))
    end
  end
end

-- A door's real state (PhysicsObj.OpenDoor sets Action "Open", it then reads "Opened").
function W.doorOpen(name)
  local e = Game.GetEntity(name)
  if not e then return nil end
  local a = tostring(e.Action)
  return a == "Open" or a == "Opened"
end

-- Client: rejoin the squad. The story shuts ways behind whoever goes first (alk_bunker_01's
-- entrance blocker and door, alk_city's collapsing columns); a player still behind was locked
-- out ("everyone passes, the client does not", owner's Steam test). Where it cannot be told
-- which side a closing door leaves a player on, the player decides: after a door or blocker
-- shuts near them while they are away from the host's body, or after REJOIN_FAR_TIME seconds
-- far from it, a hint offers to hold T (or both pad sticks pressed: Back opens the game's
-- character help) to be put next to the host's body.
W.REJOIN_NEAR_DOOR = 3000   -- the closing within this of the player
W.REJOIN_AWAY = 600         -- the player this far from the host's body
W.REJOIN_FAR = 2500         -- far from the host's body ...
W.REJOIN_FAR_TIME = 30      -- ... for this long: the hint too
W.REJOIN_HOLD = 1.5
W.REJOIN_KEY = 0x54         -- T
W.REJOIN_PAD = {64, 128}    -- XInput left and right stick pressed, together
W.REJOIN_TEXT = {en = "Cut off from the squad?\nHold T (pad: both sticks) to rejoin it",
                 ru = "Отстали от отряда?\nУдерживайте T (геймпад: оба стика), чтобы вернуться"}

function W.hostBodyPos()
  for name, p in pairs(Coop.owners) do
    if p == 0 then
      local st = Coop.remote and Coop.remote[name]
      if st and st.x then return V3D(st.x, st.y, st.z), name end
      local e = Game.GetEntity(name)
      if e then return e.Pos, name end
    end
  end
end

local function flatDist(a, b)
  local dx, dz = a.x - b.x, a.z - b.z
  return math.sqrt(dx * dx + dz * dz)
end

-- A door or blocker the host shut: the hint if it is near this player and the host's body away.
function W.onShut(what)
  if not Coop.isClient() or Coop.cfg.rejoin == false then return end
  local d, u = Game.GetEntity(what), Game.UsrEntity(0)
  local h = W.hostBodyPos()
  if not d or not u or not h then return end
  if flatDist(u.Pos, d.Pos) < W.REJOIN_NEAR_DOOR and flatDist(u.Pos, h) > W.REJOIN_AWAY then
    W.rejoinUntil = Net.CoopTime() + 60
    Coop.log("world: " .. what .. " shut near " .. u.Name .. ", away from the host: rejoin offered")
  end
end

function W.updateRejoin()
  if not Coop.isClient() or Coop.cfg.rejoin == false then return end
  local t = Net.CoopTime()
  local u = Game.UsrEntity(0)
  local h, hostName = W.hostBodyPos()
  local busy = (Scene and Scene.IsPlaying) or not u or not h or (u.Life or 0) <= 0 or Coop.storyDriven[u.Name] or
               (CoopSpirit and CoopSpirit.active)
  local dist = (not busy) and flatDist(u.Pos, h) or 0
  if busy or dist < W.REJOIN_AWAY then
    W.farSince, W.rejoinHeld = nil, nil
    if not busy and dist < W.REJOIN_AWAY then W.rejoinUntil = nil end
    if W.rejoinShown then Coop.textBlockHide("CoopRejoin") W.rejoinShown = nil end
    return
  end
  if dist > W.REJOIN_FAR then
    W.farSince = W.farSince or t
    if t - W.farSince > W.REJOIN_FAR_TIME and not W.rejoinUntil then
      W.rejoinUntil = t + 3600
      Coop.log(string.format("world: %s far from the host's body for %d s: rejoin offered", u.Name, W.REJOIN_FAR_TIME))
    end
  else
    W.farSince = nil
  end
  if not W.rejoinUntil or t > W.rejoinUntil then
    if W.rejoinShown then Coop.textBlockHide("CoopRejoin") W.rejoinShown = nil end
    return
  end
  local lang = Coop.lang()
  local text = W.REJOIN_TEXT[lang] or W.REJOIN_TEXT.en
  Coop.textBlock("CoopRejoin", Coop.enc(text, lang), {y = 360, color = Color(255, 220, 140, 255)})
  W.rejoinShown = true
  local key = Net.CoopKey and Net.CoopKey(W.REJOIN_KEY) == 1
  local ok, buttons = pcall(Net.CoopKey, -1, 0)
  local pad = ok
  for _, bit in ipairs(W.REJOIN_PAD) do
    pad = pad and math.floor((tonumber(buttons) or 0) / bit) % 2 == 1
  end
  if key or pad then
    W.rejoinHeld = W.rejoinHeld or t
    if t - W.rejoinHeld >= W.REJOIN_HOLD then
      local back2 = V3D(u.Pos.x - h.x, 0, u.Pos.z - h.z)
      local l = math.max(1, math.sqrt(back2.x * back2.x + back2.z * back2.z))
      Coop.notePos(u.Name, "world.rejoin")
      u.Pos = h + V3D(back2.x / l * 90, 30, back2.z / l * 90)
      pcall(Game.SetOnFloor, u.Name)
      W.rejoins = (W.rejoins or 0) + 1
      Coop.log(string.format("world: %s rejoined %s (was %.0f away)", u.Name, tostring(hostName), dist))
      W.rejoinUntil, W.rejoinHeld, W.farSince = nil, nil, nil
      Coop.textBlockHide("CoopRejoin")
      W.rejoinShown = nil
    end
  else
    W.rejoinHeld = nil
  end
end

-- Diagnostics (coop.lua, a vertical snap storm): the doors, blockers and lift-like props of the map
-- as they stand here, in one line. Cheap enough for a rate-limited log line, not for a frame.
function W.context()
  local t, n = {}, 0
  for name, open in pairs(W.doors) do
    n = n + 1
    if n <= 10 then
      t[#t + 1] = string.format("door %s=%s/real %s", name, open and "open" or "shut", tostring(W.doorOpen(name)))
    end
  end
  n = 0
  for name, on in pairs(W.blockers) do
    n = n + 1
    if n <= 10 then t[#t + 1] = "blk " .. name .. "=" .. (on and "on" or "off") end
  end
  n = 0
  for name in pairs(W.mapNames()) do
    local l = string.lower(name)
    if n < 6 and (string.find(l, "lift", 1, true) or string.find(l, "elev", 1, true) or
                  string.find(l, "platform", 1, true) or string.find(l, "cage", 1, true)) then
      local e = Game.GetEntity(name)
      if e then
        n = n + 1
        local ok, a, y = pcall(function() return tostring(e.Action), e.Pos.y end)
        t[#t + 1] = string.format("lift %s act=%s y=%.0f", name, ok and a or "?", ok and y or 0)
      end
    end
  end
  return #t > 0 and table.concat(t, "; ") or "no doors, blockers or lifts"
end

-- Diagnostics: the doors and blockers within R units (flat) of a place, nearest first, with the
-- state this machine has for them (blockers: on = collides), e.g. around a body that is stuck.
function W.near(pos, R)
  local list = {}
  local function add(kind, name, state)
    local e = Game.GetEntity(name)
    local ok, p = pcall(function() return e and e.Pos end)
    if ok and p then
      local d = math.sqrt((p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2)
      if d <= (R or 800) then list[#list + 1] = {d = d, text = string.format("%s %s=%s %.0fu dy=%.0f", kind, name, state, d, p.y - pos.y)} end
    end
  end
  for name, open in pairs(W.doors) do add("door", name, W.doorOpen(name) and "open" or "shut") end
  for name, on in pairs(W.blockers) do
    local ok, live = pcall(function() return Game.GetEntity(name).bMapCollision end)
    add("blk", name, (ok and live ~= nil and live or on) and "on" or "off")
  end
  table.sort(list, function(a, b) return a.d < b.d end)
  local t = {}
  for i = 1, math.min(#list, 8) do t[i] = list[i].text end
  return #t > 0 and table.concat(t, "; ") or "none near"
end

function W.setDoor(name, open)
  W.doors[name] = open
  if W.doorOpen(name) == open then return end
  -- A door the level has deleted here (cru_river deletes StonesRiver 3 s after opening it) cannot
  -- be opened again: PhysicsObj.OpenDoor read a nil object, 62 errors in the owner's log.
  if not Game.GetEntity(name) then
    if not W.doorGone then W.doorGone = {} end
    if not W.doorGone[name] then
      W.doorGone[name] = true
      Coop.log("world: door " .. name .. " is gone here, not replayed")
    end
    return
  end
  local f = open and W.origOpenDoor or W.origCloseDoor
  if f then
    local ok, err = pcall(f, name)
    if not ok then Coop.log("world: door " .. name .. " error: " .. tostring(err)) end
  end
end

function W.killObject(name)
  if W.dead[name] then return end
  W.dead[name] = true
  W.objects[name] = nil
  local e = Game.GetEntity(name)
  if e then pcall(function() if (tonumber(e.Life) or 0) > 0 then e.Life = 0 end end) end
end

-- Every tick: objects whose Life reached 0 here.
function W.pollObjects()
  if now() < (W.nextPoll or 0) then return end
  W.nextPoll = now() + W.OBJECT_POLL
  for name in pairs(W.objects) do
    local e = Game.GetEntity(name)
    local ok, life = pcall(function() return e and tonumber(e.Life) end)
    -- (a prop that breaks may be deleted at once, its pieces left: gone is broken too; the
    -- host's broken skeleton stayed whole on the client before, props test 0.2.3)
    if (not e or (ok and life and life <= 0)) and not W.dead[name] then
      W.dead[name] = true
      W.objects[name] = nil
      Net.CoopSend(Coop.isHost() and -1 or 0, 1, "kill|" .. name)
    end
  end
end

-- Map props that can be moved (pushed, thrown, knocked over): where the host has them once
-- they rest. Before 0.2.3 each machine moved its own copies (a crate one player pushed stood
-- elsewhere for the others). Not kinematic ones (animated, doors) nor jointed ones (chains,
-- hanging lamps): those go back to where they hang.
W.props = {}       -- name -> {x, y, z} where the host last said (or where it started)
W.PROP_POLL = 1
W.PROP_MOVED = 30  -- units from where it was said before
W.PROP_REST = 2    -- units it may move between two polls and still be at rest
function W.trackProp(e)
  local ok, kin, pos = pcall(function() return tonumber(e.Kinematic) or 0, e.Pos end)
  if not ok or kin ~= 0 or not pos or W.doors[e.Name] ~= nil then return end
  W.props[e.Name] = {pos.x, pos.y, pos.z}
end

local function propLine(name, e)
  local p, a = e.Pos, e.Ang
  return string.format("%s,%.0f,%.0f,%.0f,%.1f,%.1f,%.1f", name, p.x, p.y, p.z, a.x, a.y, a.z)
end

local function sendLines(peer, lines)
  local part, size = {}, 0
  for _, l in ipairs(lines) do
    part[#part + 1] = l
    size = size + #l + 1
    if size > 900 then
      Net.CoopSend(peer, 1, "mv|" .. table.concat(part, ";"))
      part, size = {}, 0
    end
  end
  if #part > 0 then Net.CoopSend(peer, 1, "mv|" .. table.concat(part, ";")) end
end

-- Every second: props that moved here away from where they were said to be and now rest (a
-- client's own player pushes props on its machine only: the host's copy of that body passes
-- through them).
function W.pollProps()
  if now() < (W.nextPropPoll or 0) then return end
  W.nextPropPoll = now() + W.PROP_POLL
  W.lastPropPos = W.lastPropPos or {}
  local lines = {}
  for name, said in pairs(W.props) do
    local e = Game.GetEntity(name)
    local ok, p = pcall(function() return e and e.Pos end)
    if not e or W.dead[name] then
      W.props[name], W.lastPropPos[name] = nil, nil
    elseif ok and p then
      local last = W.lastPropPos[name]
      W.lastPropPos[name] = {p.x, p.y, p.z}
      local dx, dy, dz = p.x - said[1], p.y - said[2], p.z - said[3]
      if last and dx * dx + dy * dy + dz * dz > W.PROP_MOVED * W.PROP_MOVED then
        local rx, ry, rz = p.x - last[1], p.y - last[2], p.z - last[3]
        if rx * rx + ry * ry + rz * rz < W.PROP_REST * W.PROP_REST then
          W.props[name] = {p.x, p.y, p.z, moved = true}
          lines[#lines + 1] = propLine(name, e)
        end
      end
    end
  end
  if #lines > 0 then
    sendLines(Coop.isHost() and -1 or 0, lines)
    W.propsSent = (W.propsSent or 0) + #lines
  end
end

-- Every prop the host has moved, to a peer that joins.
function W.sendProps(peer)
  local lines = {}
  for name, said in pairs(W.props) do
    local e = said.moved and Game.GetEntity(name)
    if e then lines[#lines + 1] = propLine(name, e) end
  end
  if #lines > 0 then sendLines(peer, lines) end
end

-- Props on their way to the place the host said (W.applyProps): per frame, a smooth step over TWEEN_TIME.
W.tweens = {}
W.TWEEN_TIME = 0.4    -- seconds
W.TWEEN_MAX = 800     -- units: beyond that the prop is put there at once
function W.cfgTween() return Coop.cfg.proptween ~= false end

local function lerpDeg(a, b, u)
  return a + ((b - a + 180) % 360 - 180) * u
end

function W.frame(t)
  if next(W.tweens) == nil then return end
  for name, w in pairs(W.tweens) do
    local e = Game.GetEntity(name)
    local u = (t - w.t0) / W.TWEEN_TIME
    if not e or W.dead[name] then
      W.tweens[name] = nil
    else
      local done = u >= 1
      if done then u = 1 end
      local k = u * u * (3 - 2 * u)   -- ease in and out
      local ok = pcall(function()
        e.Pos = V3D(w.x0 + (w.x1 - w.x0) * k, w.y0 + (w.y1 - w.y0) * k, w.z0 + (w.z1 - w.z0) * k)
        e.Ang = V3D(lerpDeg(w.ax0, w.ax1, k), lerpDeg(w.ay0, w.ay1, k), lerpDeg(w.az0, w.az1, k))
      end)
      if done or not ok then W.tweens[name] = nil end
    end
  end
end

-- Another machine's places for props, where they are not already; they are where they were
-- said to be from now on (not sent back as moved here).
function W.applyProps(text)
  for item in string.gmatch(text or "", "[^;]+") do
    local name, x, y, z, ax, ay, az = string.match(item, "^(.-),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
    local e = name and not W.dead[name] and Game.GetEntity(name)
    if e then
      x, y, z = tonumber(x), tonumber(y), tonumber(z)
      if W.props[name] then W.props[name] = {x, y, z, moved = true} end
      if W.lastPropPos then W.lastPropPos[name] = nil end
      local ok = pcall(function()
        local p = e.Pos
        local dx, dy, dz = p.x - x, p.y - y, p.z - z
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 > W.PROP_MOVED * W.PROP_MOVED then
          if W.cfgTween() and d2 < W.TWEEN_MAX * W.TWEEN_MAX then
            -- a prop the host moved is carried to its place, not popped there (the client sees it at rest
            -- somewhere else first, as its own physics left it)
            local a = e.Ang
            W.tweens[name] = {x0 = p.x, y0 = p.y, z0 = p.z, ax0 = a.x, ay0 = a.y, az0 = a.z,
                              x1 = x, y1 = y, z1 = z, ax1 = tonumber(ax), ay1 = tonumber(ay), az1 = tonumber(az), t0 = now()}
          else
            e.Pos = V3D(x, y, z)
            e.Ang = V3D(tonumber(ax), tonumber(ay), tonumber(az))
          end
          W.propsSet = (W.propsSet or 0) + 1
        end
      end)
      if not ok then W.propErrors = (W.propErrors or 0) + 1 end
    end
  end
end

function W.entries()
  local t = {}
  for name, open in pairs(W.doors) do
    local real = W.doorOpen(name)
    if real == nil then real = open end
    t[#t + 1] = "D:" .. name .. (real and "+" or "-")
  end
  for name in pairs(W.dead) do t[#t + 1] = "K:" .. name end
  for name, on in pairs(W.blockers) do
    -- (as it is here: a level script of this machine may have switched it since)
    local e = Game.GetEntity(name)
    local ok, live = pcall(function() return e and e.bMapCollision end)
    if ok and live ~= nil then on = live and true or false end
    t[#t + 1] = "B:" .. name .. (on and "+" or "-")
  end
  table.sort(t)
  return t
end

-- Entry count and a 31-bit hash (exact in Lua 5.1 numbers).
function W.digest(t)
  local text, sum = table.concat(t, ";"), 5381
  for i = 1, #text do sum = (sum * 33 + string.byte(text, i)) % 2147483647 end
  return #t, sum
end

function W.sendState(peer)
  local t = W.entries()
  Net.CoopSend(peer, 1, "wstate|" .. table.concat(t, ";"))
  W.sendProps(peer)
  Coop.log("world: state sent to peer " .. peer .. " (" .. #t .. " entries)")
end

function W.applyState(text)
  local host, fixed = {}, 0
  for item in string.gmatch(text or "", "[^;]+") do
    host[item] = true
    local kind, name, sign = string.match(item, "^(%a):(.-)([%+%-]?)$")
    if kind == "D" and (W.doorOpen(name) ~= (sign == "+") or W.doors[name] ~= (sign == "+")) then
      if W.doorOpen(name) ~= (sign == "+") then fixed = fixed + 1 end
      W.setDoor(name, sign == "+")
    elseif kind == "K" and not W.dead[name] then
      W.killObject(name)
      fixed = fixed + 1
    elseif kind == "B" and W.setBlocker(name, sign == "+") then
      fixed = fixed + 1
    end
  end
  local extra, here = {}, {}
  for _, item in ipairs(W.entries()) do
    here[item] = true
    if not host[item] then extra[#extra + 1] = item end
  end
  -- (what the host has and this machine still lacks after applying it: the other half of a mismatch)
  local lacking = {}
  for item in pairs(host) do
    if not here[item] then lacking[#lacking + 1] = item end
  end
  table.sort(lacking)
  Coop.log("world: host state applied, " .. fixed .. " fixed" ..
    (#extra > 0 and (", only here: " .. table.concat(extra, " ")) or "") ..
    (#lacking > 0 and (", only on the host: " .. table.concat(lacking, " ")) or ""))
end

function W.update()
  if not Coop.inSession() or Coop.level == "levels/menu" then return end
  W.installObjects()
  W.installFPAnm()
  W.installCoolUse()
  W.pollObjects()
  if Coop.isHost() and Coop.cfg.syncblockers ~= false then W.pollBlockers() end
  if Coop.cfg.syncprops ~= false then W.pollProps() end
  local okr, errr = pcall(W.updateRejoin)
  if not okr and (W.rejoinErrors or 0) < 3 then
    W.rejoinErrors = (W.rejoinErrors or 0) + 1
    Coop.log("world: rejoin error " .. tostring(errr))
  end
  if Coop.isHost() and now() >= (W.nextDigest or now() + W.DIGEST_EVERY) then
    local entries = W.entries()
    local n, sum = W.digest(entries)
    if sum ~= W.lastSum and (W.changeShown or 0) < 30 then
      W.changeShown = (W.changeShown or 0) + 1
      Coop.log("world: entries changed (" .. n .. "): " .. string.sub(table.concat(entries, " "), 1, 1200))
    end
    W.lastSum = sum
    Net.CoopSend(-1, 1, "wd|" .. n .. "|" .. sum)
    W.nextDigest = now() + W.DIGEST_EVERY
  elseif Coop.isHost() and not W.nextDigest then
    W.nextDigest = now() + W.DIGEST_EVERY
  end
end

-- Messages of this part; returns true when handled.
function W.onObjectMessage(peer, f)
  local kind = f[1]
  -- Messages queued while this machine loaded the level are handled before the first tick:
  -- the door wrappers must exist first, or a door would be recorded open but stay shut.
  if kind == "door" or kind == "kill" or kind == "wstate" or kind == "wd" or kind == "blk" or kind == "mv" then W.installObjects() end
  if kind == "mv" then
    if Coop.cfg.syncprops ~= false then
      local text = string.sub(table.concat(f, "|"), 4)
      if Coop.isClient() and peer == 0 then
        W.applyProps(text)
      elseif Coop.isHost() and peer ~= 0 then
        W.applyProps(text)
        Net.CoopSend(-1, 1, "mv|" .. text)
      end
    end
    return true
  end
  if kind == "door" and Coop.isClient() then
    W.setDoor(f[2], f[3] == "1")
    if f[3] ~= "1" then W.onShut(f[2]) end
  elseif kind == "blk" and Coop.isClient() then
    if Coop.cfg.syncblockers ~= false then W.setBlocker(f[2], f[3] == "1") end
    if f[3] == "1" then W.onShut(f[2]) end
  elseif kind == "kill" then
    if Coop.isHost() then
      if not W.dead[f[2]] then Net.CoopSend(-1, 1, "kill|" .. f[2]) end
    elseif peer ~= 0 then
      return true
    end
    W.killObject(f[2])
  elseif kind == "wd" and Coop.isClient() then
    local n, sum = W.digest(W.entries())
    if n == tonumber(f[2]) and sum == tonumber(f[3]) then
      W.mismatch = 0
    else
      W.mismatch = (W.mismatch or 0) + 1
      W.digestMisses = (W.digestMisses or 0) + 1
      Coop.log("world: digest differs (host " .. tostring(f[2]) .. " entries, here " .. n .. ")")
      -- (what this machine has, a few times: to compare with the host's "entries changed" lines)
      if (W.digestShown or 0) < 12 then
        W.digestShown = (W.digestShown or 0) + 1
        Coop.log("world: entries here: " .. string.sub(table.concat(W.entries(), " "), 1, 1200))
      end
      if W.mismatch >= 2 then
        W.mismatch = 0
        Net.CoopSend(0, 1, "wdneed")
      end
    end
  elseif kind == "wdneed" and Coop.isHost() then
    W.sendState(peer)
  elseif kind == "wstate" and Coop.isClient() then
    W.applyState(f[2])
  else
    return false
  end
  return true
end

-- Texts of the other languages (Coop.addLangs).
Coop.addLangs(W.REJOIN_TEXT, "CoopWorld.REJOIN_TEXT")
