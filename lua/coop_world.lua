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
  local ok, err = pcall(f, unpack(args, 1, args.n))
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
      f2(unpack(args, 1, args.n))
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
  return string.format("world: sent=%d replayed=%d doors=%d dead=%d digest_misses=%d", W.sent or 0, W.replayed or 0,
    doors, dead, W.digestMisses or 0)
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

function W.trackObject(o)
  local ok, name, life = pcall(function() return o.Name, tonumber(o.Life) end)
  -- "Bip ..." are the bones of characters' ragdolls (PxBodyPhysics too), not props.
  if ok and type(name) == "string" and life and life > 0 and #name < 64 and string.sub(name, 1, 4) ~= "Bip " then
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
    local ok, body = pcall(function() return e:IsType("PxBodyPhysics") end)
    if ok and body and string.sub(tostring(e.Name), 1, 3) == "OB_" then
      W.trackObject(e)
      n = n + 1
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  Coop.log("world: doors and objects tracked (" .. n .. " objects found on the map)")
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

function W.setDoor(name, open)
  W.doors[name] = open
  if W.doorOpen(name) == open then return end
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
    if not e then
      W.objects[name] = nil
    elseif ok and life and life <= 0 and not W.dead[name] then
      W.dead[name] = true
      W.objects[name] = nil
      Net.CoopSend(Coop.isHost() and -1 or 0, 1, "kill|" .. name)
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
  for name, on in pairs(W.blockers) do t[#t + 1] = "B:" .. name .. (on and "+" or "-") end
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
  local extra = {}
  for _, item in ipairs(W.entries()) do
    if not host[item] then extra[#extra + 1] = item end
  end
  Coop.log("world: host state applied, " .. fixed .. " fixed" ..
    (#extra > 0 and (", only here: " .. table.concat(extra, " ")) or ""))
end

function W.update()
  if not Coop.inSession() or Coop.level == "levels/menu" then return end
  W.installObjects()
  W.pollObjects()
  if Coop.isHost() and Coop.cfg.syncblockers ~= false then W.pollBlockers() end
  if Coop.isHost() and now() >= (W.nextDigest or now() + W.DIGEST_EVERY) then
    local n, sum = W.digest(W.entries())
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
  if kind == "door" or kind == "kill" or kind == "wstate" or kind == "wd" or kind == "blk" then W.installObjects() end
  if kind == "door" and Coop.isClient() then
    W.setDoor(f[2], f[3] == "1")
  elseif kind == "blk" and Coop.isClient() then
    if Coop.cfg.syncblockers ~= false then W.setBlocker(f[2], f[3] == "1") end
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
