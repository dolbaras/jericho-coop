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
    return W.isHuman(nam)
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
  if type(usr) == "string" and usr == Coop.localChar() then
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
    if f2 and type(args[1]) == "string" and Coop.ownerOf(args[1]) == peer then
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
  return string.format("world: sent=%d replayed=%d", W.sent or 0, W.replayed or 0)
end
