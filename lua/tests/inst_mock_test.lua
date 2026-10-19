-- Offline check of coop_inst.lua routing: a hub (peer ids 1, 2, 3 connected), a side
-- instance with authority 2 and member 3, and peer 1 staying in the main instance.
-- Run: lua tests/inst_mock_test.lua (from mod/lua)
local queues = {}            -- machine id -> list of {from, kind, data}
local function deliver(to, from, kind, data)
  queues[to] = queues[to] or {}
  table.insert(queues[to], {from, kind, data})
end

local function machine(id)
  -- id 0 = hub; others are clients (the hub is their peer 0).
  local env = setmetatable({}, {__index = _G})
  env.Net = {
    CoopSend = function(peer, rel, data)
      if id == 0 then
        local targets = peer == -1 and {1, 2, 3} or {peer}
        for _, t in ipairs(targets) do deliver(t, 0, "msg", data) end
      else
        deliver(0, id, "msg", data)
      end
      return 1
    end,
    CoopRecv = function()
      local q = queues[id]
      if not q or #q == 0 then return nil end
      local m = table.remove(q, 1)
      return m[1], m[2], m[3]
    end,
    CoopStatus = function()
      if id == 0 then return "role=host p1:rtt=1 p2:rtt=1 p3:rtt=1 peers=3" end
      return "role=client p0:rtt=1 peers=1"
    end,
  }
  env.Coop = {cfg = {role = id == 0 and "host" or "client", myId = id ~= 0 and id or nil},
              log = function() end, rearm = function() end, owners = {}, broadcastOwners = function() end}
  env.Coop.isHost = function() return env.Coop.cfg.role == "host" end
  env.Game = {LoadLevel = function(l) env.loaded = l end}
  local chunk = assert(loadfile("coop_inst.lua"))
  setfenv(chunk, env)
  chunk()
  return env
end

local hub, m1, m2, m3 = machine(0), machine(1), machine(2), machine(3)
local function drain(env)
  local out = {}
  while true do
    local p, k, d = env.Net.CoopRecv()
    if not p then break end
    out[#out + 1] = {p, k, d}
  end
  return out
end

-- Split: 2 and 3 go to the side instance, 2 is its authority.
hub.CoopInst.startSide("trio", 2, {2, 3}, "Cru_River")
drain(m2) drain(m3)   -- control messages are consumed inside recv
assert(m2.Coop.cfg.role == "host" and m2.Coop.cfg.inst == "trio", "authority role")
assert(m3.Coop.cfg.role == "client" and m3.loaded == nil, "member waits for the authority")
-- (the synthetic joins were consumed above too; queue a fresh exchange)

-- Hub's main broadcast reaches only peer 1.
hub.Net.CoopSend(-1, 1, "s|Delgado")
assert(#drain(m1) == 1, "main peer gets main traffic")
assert(#drain(m2) == 0 and #drain(m3) == 0, "side peers do not get main traffic")

-- Authority broadcasts to its instance: member 3 receives it from "peer 0".
m2.Net.CoopSend(-1, 1, "s|Jones")
local h = drain(hub)   -- the hub relays inside its recv
assert(#h == 0, "relay is not delivered to the hub's own Lua")
local r3 = drain(m3)
assert(#r3 == 1 and r3[1][1] == 0 and r3[1][3] == "s|Jones", "member sees the authority as peer 0")
assert(#drain(m1) == 0, "main peer does not see side traffic")

-- Member sends "to the host": the authority receives it from peer 3.
m3.Net.CoopSend(0, 1, "claim|Cole")
drain(hub)
local r2 = drain(m2)
assert(#r2 == 1 and r2[1][1] == 3 and r2[1][3] == "claim|Cole", "authority gets the member's message")

-- Status: the authority counts its one member; the hub counts only the main peer.
assert(string.find(m2.Net.CoopStatus(), "peers=1"), "authority status")
assert(string.find(hub.Net.CoopStatus(), "peers=1"), "hub status: " .. hub.Net.CoopStatus())

-- Merge: both go back to the main instance and load the chapel.
hub.CoopInst.merge("Cru_Chapel")
drain(m2) drain(m3)
assert(m2.Coop.cfg.inst == nil and m2.Coop.cfg.role == "client", "merge")
hub.Net.CoopSend(-1, 1, "s|all")
assert(#drain(m2) == 1 and #drain(m3) == 1 and #drain(m1) == 1, "everyone back in the main instance")
print("inst mock test ok")
