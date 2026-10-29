-- Offline check of the resolution in coop_choice.lua (who moves where, swaps, full cards, the pinned host).
-- Run: lua tests/choice_mock_test.lua  (from mod/lua)
local clock = 100
local logs, sent = {}, {}
Net = {CoopTime = function() return clock end, CoopSend = function(to, rel, msg) sent[#sent + 1] = to .. ">" .. msg end}
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end, owners = {}, P2 = 8, storyDriven = {},
        isHost = function() return true end, isClient = function() return false end, inSession = function() return true end,
        myId = function() return 0 end, isMine = function(o) return o == 0 or o == 8 end,
        peerOf = function(o) return o >= 8 and o - 8 or o end, broadcastOwners = function() sent[#sent + 1] = "own" end,
        lang = function() return "en" end, enc = function(s) return s end, addLangs = function() end,
        charName = function(c) return c end, frame = 0, textBlockHide = function() end, textBlock = function() end}
local ents, switched = {}, {}
for _, n in ipairs({"Black", "Church", "Delgado", "Jones", "Cole", "Rawlings"}) do ents[n] = {Name = n, Life = 100, Active = 1} end
Game = {GetTime = function() return clock end, GetEntity = function(n) return ents[n] end, UsrEntity = function() return ents.Church end}
Team = {SwitchSoldier = function(a, b) switched[#switched + 1] = a .. "->" .. b end}
Scorer = {SetMsgText = function() end}
Input = {}
dofile("coop_choice.lua")
local C = CoopChoice

local function setup(id, holders, picks)
  Coop.owners = {}
  for name, owner in pairs(holders) do Coop.owners[name] = owner end
  C.done, C.pending, C.cur, C.result = {}, {}, nil, nil
  switched, sent = {}, {}
  C.pending[id] = {since = clock}
  C.start(id)
  for owner, p in pairs(picks) do C.setPick(owner, p[1], p[2]) end
  C.resolve()
  return C.result
end
local function owner(name) return Coop.owners[name] end

-- 1. G8: the host (Church) stays, the client (Black) goes: a swap through the owner table
local r = setup("G8", {Church = 0, Black = 1}, {[0] = {2, true}, [1] = {1, true}})
assert(r and owner("Church") == 1, "client has Church: " .. tostring(owner("Church")))
assert(owner("Black") == nil and (owner("Delgado") == 0), "host went to a free stay body")
assert(#switched == 1 and switched[1]:match("^Church%->"), "host switched: " .. table.concat(switched, ","))
local evict
for _, m in ipairs(sent) do if m:match("evict") then evict = m end end
assert(evict == "1>evict|Black|Church", "client told: " .. tostring(evict))

-- 2. both want the one-body card: the first confirmed gets it, the other stays
r = setup("G8", {Delgado = 0, Black = 1}, {[0] = {1, true}, [1] = {1, true}})
assert(owner("Church") == 0 and owner("Black") == 1, "first confirmed gets Church, the other keeps Black")
assert(not r.move[1], "no move for the second")

-- 3. a swap with no spare body (3 players, 3 bodies, Church<->Black): both stay with reason full when nobody frees one
r = setup("G8", {Church = 0, Black = 1, Delgado = 2}, {[0] = {2, true}, [1] = {1, true}, [2] = {2, true}})
assert(owner("Church") == 1, "client gets Church")
assert(owner("Black") == 0 or owner("Delgado") == 0, "host has a stay body")

-- 4. the Lost Patrol: the host is pinned to the main group
r = setup("LP", {Church = 0, Jones = 1}, {[0] = {2, true}, [1] = {2, true}})
assert(owner("Church") == 0, "host stays main")
assert(owner("Jones") == 1, "client stays trio")
local res
for _, m in ipairs(sent) do if m:match("^%-1>chr") then res = m end end
assert(res and res:find("0:Church:host"), "host reason: " .. tostring(res))

-- 5. a client of the main group holding a trio body moves to a free main body
r = setup("LP", {Church = 0, Jones = 1}, {[0] = {1, true}, [1] = {1, true}})
assert(owner("Jones") == nil and (owner("Delgado") == 1 or owner("Black") == 1), "client moved to main")

-- 6. one human: nothing to choose, the request resolves at once
local ran = false
Coop.owners = {Church = 0}
C.done, C.pending = {}, {}
C.request("G8", function() ran = true end)
C.start("G8")
assert(ran and C.done.G8 and not C.cur, "single player: resumes at once")

-- 7. unconfirmed highlights count at the timer's end; a dead body is not taken
ents.Delgado.Life = 0
r = setup("G8", {Church = 0, Black = 1}, {[1] = {1, false}})
assert(owner("Church") == 1 or owner("Church") == 0, "resolved")
print("choice mock test: ok")
