-- Jericho co-op: side instances in one session (the Lost Patrol, docs/story/act3-splits.md
-- option B). Some players leave the main group's level for their own level instance with
-- its own authority (a "second host"); they stay connected to the session host, which
-- relays their messages. Every other module keeps using Net.CoopSend/CoopRecv as before:
-- this layer wraps them so that, inside a side instance,
--   * the instance authority is the logical host (Coop.isHost(), peer 0 for its members);
--   * "to the host" and "to everyone" reach that authority / its instance only;
--   * the session host (the hub) relays, and keeps sending main-instance traffic to the
--     main instance only.
-- Wire format (hub <-> side-instance machines):
--   ~r|<target>|<reliable>|<payload>   member -> hub: deliver to target (-1 = its instance)
--   ~f|<from>|<payload>                hub -> member: payload from a real peer id
--                                      (~join / ~leave as payload: synthetic events)
--   ~c|split|<auth>|<ids>|<level>      hub -> the leaving players: start the instance
--   ~c|main|<level>                    hub -> side authority: the main group changed level
--   ~c|merge|<level>                   hub -> side players: back into the main instance
-- Persistent state (COOP_CFG): inst ("trio" on side machines), instAuth (real id of the
-- side authority), netRole (real network role), instOf ("id,id" side members, on the hub).

CoopInst = CoopInst or {}
local I = CoopInst
local cfg = Coop.cfg

I.raw = I.raw or {send = Net.CoopSend, recv = Net.CoopRecv, status = Net.CoopStatus}
local raw = I.raw

function I.isHub() return (cfg.netRole or cfg.role) == "host" end
function I.inSide() return cfg.inst ~= nil end

-- Hub: real peer ids in the side instance.
function I.sideMembers()
  local set = {}
  for id in string.gmatch(cfg.instOf or "", "%d+") do set[tonumber(id)] = true end
  return set
end

function I.connected()
  local ids = {}
  for id in string.gmatch(raw.status(), " p(%d+):") do ids[#ids + 1] = tonumber(id) end
  return ids
end

function I.split()
  return I.inSide() or (I.isHub() and (cfg.instOf or "") ~= "")
end

------------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------------

function I.send(peer, rel, data)
  if not I.split() then return raw.send(peer, rel, data) end
  if I.isHub() then
    if peer == -1 then
      local side = I.sideMembers()
      for _, p in ipairs(I.connected()) do
        if not side[p] then raw.send(p, rel, data) end
      end
      return 1
    end
    return raw.send(peer, rel, data)
  end
  -- A side-instance machine (a client of the hub): everything goes through the hub.
  local target
  if cfg.role == "host" then
    target = peer                                   -- -1 = all members, or a member id
  else
    target = (peer == 0 or peer == -1) and cfg.instAuth or peer
  end
  return raw.send(0, rel, "~r|" .. tostring(target) .. "|" .. (rel or 0) .. "|" .. data)
end

------------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------------

function I.hubRelay(from, data)
  local target, rel, payload = string.match(data, "^~r|(%-?%d+)|(%d)|(.*)$")
  if not target then return end
  target, rel = tonumber(target), tonumber(rel)
  local side = I.sideMembers()
  if not side[from] then return end   -- only side members use the relay
  local out = "~f|" .. from .. "|" .. payload
  if target == -1 then
    for _, p in ipairs(I.connected()) do
      if side[p] and p ~= from then raw.send(p, rel, out) end
    end
  elseif side[target] then
    raw.send(target, rel, out)
  end
end

function I.recv()
  for _ = 1, 400 do
    local peer, kind, data = raw.recv()
    if not peer then return nil end
    if kind == "msg" and string.sub(data, 1, 3) == "~r|" then
      if I.isHub() then I.hubRelay(peer, data) end
    elseif kind == "msg" and string.sub(data, 1, 3) == "~c|" then
      I.onControl(peer, data)
    elseif kind == "msg" and string.sub(data, 1, 3) == "~f|" then
      local from, payload = string.match(data, "^~f|(%d+)|(.*)$")
      from = tonumber(from)
      if from then
        -- The side authority is "the host" (peer 0) for its members.
        if I.inSide() and cfg.role ~= "host" and from == cfg.instAuth then from = 0 end
        if payload == "~join" then return from, "join", "" end
        if payload == "~leave" then return from, "leave", "" end
        return from, "msg", payload
      end
    elseif kind == "leave" and I.isHub() and I.sideMembers()[peer] then
      -- A side member dropped: the hub forgets it and tells the side authority.
      local left = {}
      for id in pairs(I.sideMembers()) do if id ~= peer then left[#left + 1] = id end end
      cfg.instOf = table.concat(left, ",")
      if cfg.instAuthOnHub and cfg.instAuthOnHub ~= peer then raw.send(cfg.instAuthOnHub, 1, "~f|" .. peer .. "|~leave") end
      Coop.rearm()
      return peer, kind, data
    elseif I.inSide() and kind == "msg" then
      -- Plain messages from the hub are main-instance traffic: not for this instance.
    else
      return peer, kind, data
    end
  end
end

function I.status()
  if not I.split() then return raw.status() end
  if I.isHub() then
    local side, n, parts = I.sideMembers(), 0, {"role=host"}
    for _, p in ipairs(I.connected()) do
      if not side[p] then
        n = n + 1
        parts[#parts + 1] = "p" .. p .. ":rtt=0"
      end
    end
    parts[#parts + 1] = "peers=" .. n
    return table.concat(parts, " ")
  end
  if cfg.role == "host" then
    local n = 0
    for _ in string.gmatch(cfg.instIds or "", "%d+") do n = n + 1 end
    return "role=host side=" .. tostring(cfg.inst) .. " peers=" .. math.max(0, n - 1)
  end
  return "role=client side=" .. tostring(cfg.inst) .. " p0:rtt=0 peers=1"
end

------------------------------------------------------------------------------
-- Control
------------------------------------------------------------------------------

-- Hub: send players `ids` (real peer ids, a list) to their own instance in `level`, with
-- `auth` as its authority.
function I.startSide(name, auth, ids, level)
  cfg.instOf = table.concat(ids, ",")
  cfg.instAuthOnHub = auth
  -- Their bodies leave the main instance.
  for _, id in ipairs(ids) do
    for char, p in pairs(Coop.owners) do
      if p == id then Coop.owners[char] = nil end
    end
  end
  Coop.broadcastOwners()
  Coop.rearm()
  local msg = "~c|split|" .. name .. "|" .. auth .. "|" .. table.concat(ids, ",") .. "|" .. level
  for _, id in ipairs(ids) do raw.send(id, 1, msg) end
  -- Members meet their authority (as if it had just connected).
  for _, id in ipairs(ids) do
    if id ~= auth then
      raw.send(id, 1, "~f|" .. auth .. "|~join")
      raw.send(auth, 1, "~f|" .. id .. "|~join")
    end
  end
  Coop.log("inst: " .. name .. " starts in " .. level .. " (authority " .. auth .. ", players " .. cfg.instOf .. ")")
end

-- Hub: the main group changed level; the side authority may move on (CoopPatrol).
function I.tellMainLevel(level)
  if cfg.instAuthOnHub and (cfg.instOf or "") ~= "" then
    raw.send(cfg.instAuthOnHub, 1, "~c|main|" .. level)
  end
end

-- Hub: the side players come back into the main instance (their machines load `level`).
function I.merge(level)
  local ids = {}
  for id in pairs(I.sideMembers()) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do raw.send(id, 1, "~c|merge|" .. level) end
  cfg.instOf, cfg.instAuthOnHub = nil, nil
  Coop.rearm()
  Coop.log("inst: side instance merged back in " .. level)
end

function I.loadLevel(level)
  Coop.rearm()
  if CoopEnemies and CoopEnemies.fromHost then
    CoopEnemies.fromHost(SaveGame.LoadLevel, level)
  else
    Game.LoadLevel("Levels/" .. level)
  end
end

function I.onControl(peer, data)
  local f = {}
  for x in string.gmatch(data .. "|", "([^|]*)|") do f[#f + 1] = x end
  local what = f[2]
  if what == "split" and peer == 0 then
    local myReal = cfg.realId or cfg.myId
    cfg.realId = myReal
    cfg.netRole = cfg.netRole or cfg.role
    cfg.inst = f[3]
    cfg.instAuth = tonumber(f[4])
    cfg.instIds = f[5]
    cfg.role = (myReal == cfg.instAuth) and "host" or "client"
    cfg.owners = nil
    Coop.owners = {}
    cfg.level = f[6]
    Coop.log("inst: joining side instance " .. cfg.inst .. " as " .. cfg.role .. " in " .. f[6])
    if CoopPatrol and CoopPatrol.onSplit then pcall(CoopPatrol.onSplit) end
    I.loadLevel(f[6])
  elseif what == "main" and peer == 0 then
    if CoopPatrol and CoopPatrol.onMainLevel then pcall(CoopPatrol.onMainLevel, f[3]) end
  elseif what == "merge" and peer == 0 then
    Coop.log("inst: back to the main group in " .. f[3])
    cfg.inst, cfg.instAuth, cfg.instIds = nil, nil, nil
    cfg.role = cfg.netRole or "client"
    cfg.myId = cfg.realId or cfg.myId
    cfg.owners = nil
    Coop.owners = {}
    cfg.level = f[3]
    I.loadLevel(f[3])
  end
end

function I.install()
  if I.installed == Net then return end
  I.installed = Net
  raw.send, raw.recv, raw.status = Net.CoopSend, Net.CoopRecv, Net.CoopStatus
  Net.CoopSend = I.send
  Net.CoopRecv = I.recv
  Net.CoopStatus = I.status
end

I.install()
