-- Offline check of the resolution in coop_choice.lua (who moves where, swaps, full cards, the pinned host).
-- Run: lua tests/choice_mock_test.lua  (from mod/lua)
local clock = 100
local logs, sent = {}, {}
Net = {CoopTime = function() return clock end, CoopSend = function(to, rel, msg) sent[#sent + 1] = to .. ">" .. msg end}
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end, owners = {}, P2 = 8, storyDriven = {},
        isHost = function() return Coop.role ~= "client" end, isClient = function() return Coop.role == "client" end, inSession = function() return true end,
        myId = function() return 0 end, isMine = function(o) return o == 0 or o == 8 end,
        peerOf = function(o) return o >= 8 and o - 8 or o end, broadcastOwners = function() sent[#sent + 1] = "own" end,
        lang = function() return "en" end, enc = function(s) return s end, addLangs = function() end,
        charName = function(c) return c end, frame = 0, textBlockHide = function() end, textBlock = function() end}
local ents, switched = {}, {}
Coop.role = "host"
for _, n in ipairs({"Black", "Church", "Delgado", "Jones", "Cole", "Rawlings"}) do ents[n] = {Name = n, Life = 100, Active = 1} end
Game = {GetTime = function() return clock end, GetEntity = function(n) return ents[n] end, UsrEntity = function() return ents.Church end}
Team = {SwitchSoldier = function(a, b) switched[#switched + 1] = a .. "->" .. b end}
Scorer = {SetMsgText = function() end}
Color = function(...) return {...} end
Input = {}
dofile("coop_choice.lua")
local C = CoopChoice

local function setup(id, holders, picks)
  Coop.owners = {}
  for name, owner in pairs(holders) do Coop.owners[name] = owner end
  C.reset()
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

-- 8. a pure exchange: Church (host) and Black (client) want each other's group, Delgado is dead (no spare body):
-- both move, through the owner table, evict for the client, one direct switch for the host
ents.Delgado.Life = 0
r = setup("G8", {Church = 0, Black = 1}, {[0] = {2, true}, [1] = {1, true}})
assert(owner("Church") == 1 and owner("Black") == 0, "exchange: Church " .. tostring(owner("Church")) .. " Black " .. tostring(owner("Black")))
assert(r.final[0] == "Black" and r.final[1] == "Church", "result final")
ents.Delgado.Life = 100

-- 9. a second finish inside the result hold does not overwrite the first resume (queue), and both run in order
local order = {}
C.reset()
Coop.owners = {Church = 0, Black = 1}
C.pending.G8 = {since = clock, resume = function() order[#order + 1] = "G8" end}
C.pending.G10 = {since = clock, resume = function() order[#order + 1] = "G10" end}
C.start("G8"); C.setPick(0, 1, true); C.setPick(1, 2, true); C.resolve()
C.start("G10"); C.setPick(0, 1, true); C.setPick(1, 2, true); C.resolve()
assert(#order == 0 and #C.later == 2, "both resumes queued: " .. #C.later)
clock = clock + C.RESULT_HOLD + 1
C.runLater()
assert(order[1] == "G8" and order[2] == "G10", "resumes run in order: " .. table.concat(order, ","))

-- 10. level change: the reset clears done/pending/cur (a replayed split asks again)
C.done.G8 = true; C.pending.G10 = {since = clock}; C.cur = {}
Coop = setmetatable({}, {__index = Coop})   -- a new Coop table, as coop.lua builds at every level load
Coop.level = "levels/cru_sewers"
C.update()
assert(not C.done.G8 and not next(C.pending) and not C.cur, "reset on level change")

-- 11. client gate: holds the call until the host's chd/chr, then runs it (after the hold for a result)
Coop.role = "client"; Coop.cfg.myId = 1
Coop.isClient = function() return true end; Coop.isHost = function() return false end
local calls = 0
local g = C.gate("G8", function(a) calls = calls + a end)
g(1); g(1)
assert(calls == 0 and C.held.G8, "client holds the call")
C.onMessage(0, {"chd", "G8"})
C.runLater()
assert(calls == 1, "client call ran once after chd: " .. calls)
g(5); assert(calls == 6, "after the result the gate lets calls through")
C.reset()
g = C.gate("G8", function(a) calls = calls + a end)
g(1)
C.onMessage(0, {"chr", "G8", "1:Black:moved"})
C.runLater(); assert(calls == 6, "result: the call waits for the explanation to be read")
clock = clock + C.RESULT_HOLD + 0.1
C.runLater(); assert(calls == 7, "then runs")
-- no answer from the host: the held call runs after a while
C.reset()
g = C.gate("G8", function(a) calls = calls + a end)
g(10)
clock = clock + C.TIME + 13
C.heldCheck(); C.runLater()
assert(calls == 17, "timeout releases the held call")
-- a screen of 100 s (the host set another time): the held call waits for it
C.reset()
g = C.gate("G8", function(a) calls = calls + a end)
g(100)
C.scr = {id = "G8", untilT = clock + 100, locals = {}}
clock = clock + 40
C.heldCheck(); C.runLater()
assert(calls == 17, "held while the screen is up")
clock = clock + 80
C.heldCheck(); C.runLater()
assert(calls == 117, "released after the screen's time")
C.scr = nil
Coop.role = "host"; Coop.cfg.myId = nil
Coop.isClient = function() return false end; Coop.isHost = function() return true end

-- 11b. a held replay runs later in the same replay context (the client's guard lets replays through only)
Coop.role = "client"; Coop.cfg.myId = 1
Coop.isClient = function() return true end; Coop.isHost = function() return false end
CoopWorld = {replaying = nil}
C.reset()
local seenReplay, seenTrig
local gr = C.gate("G8", function() seenReplay = Coop.replay; seenTrig = Game.GetTriggeredEntity(1) end, nil, true)
Game.GetTriggeredEntity = function() return "orig" end
gr()   -- not a replay: runs at once (the client's own use reaches its guard)
assert(seenReplay == nil and not C.held.G8, "own call is not held")
Coop.replay = true; CoopWorld.replaying = true; CoopWorld.replayTriggered = "Church"
gr()
Coop.replay = false; CoopWorld.replaying = false; CoopWorld.replayTriggered = nil
assert(C.held.G8 and seenReplay == nil, "replay is held")
C.onMessage(0, {"chd", "G8"}); C.runLater()
assert(seenReplay == true and seenTrig == "Church", "held replay runs in its replay context: " .. tostring(seenReplay) .. tostring(seenTrig))
assert(Coop.replay == false and Game.GetTriggeredEntity(1) == "orig", "context restored")
CoopWorld = nil
Coop.role = "host"; Coop.cfg.myId = nil
Coop.isClient = function() return false end; Coop.isHost = function() return true end

-- 12. chp carries the owner id: a client's split screen player 2 (owner peer + P2) can pick, a forged owner cannot
Coop.owners = {Church = 0, Black = 1, Delgado = 9}
C.reset(); switched, sent = {}, {}
C.pending.G8 = {since = clock}
C.start("G8")
C.onMessage(1, {"chp", "G8", "1", "1", "9"})
assert(C.cur.picks[9].conf and C.cur.picks[9].g == 1, "second local player's pick stored under its owner")
assert(not C.cur.picks[1].conf, "the first player's pick untouched")
C.onMessage(1, {"chp", "G8", "2", "1", "0"})   -- peer 1 claiming the host's owner id: stored under peer 1
assert(not C.cur.picks[0].conf and C.cur.picks[1].conf and C.cur.picks[1].g == 2, "forged owner id ignored")

-- 13. the Lost Patrol: a refused player (full card) stays in his main-group body and is not sent to the trio
dofile("coop_patrol.lua")
cfg = Coop.cfg
Coop.rearm = function() end
Coop.owners = {Church = 0, Jones = 1, Cole = 2}
C.reset()
C.pending.LP = {since = clock}
C.start("LP")
C.setPick(1, 1, true); C.setPick(2, 2, true)   -- peer 1 (holding Jones) asks for the main group, peer 2 for the trio
C.resolve()
CoopPatrol.chosenTrio()
assert(Coop.cfg.patrol == "2", "trio = the players holding a trio body at the end: " .. tostring(Coop.cfg.patrol))
-- a player who asked for the trio but found no free body of it (full) stays in his main-group body
Coop.cfg.patrol = nil
Coop.storyDriven.Cole, Coop.storyDriven.Rawlings = true, true
Coop.owners = {Church = 0, Black = 1, Jones = 2}
C.reset(); C.pending.LP = {since = clock}; C.start("LP")
C.setPick(1, 2, true); C.setPick(2, 2, true); C.resolve()
assert(Coop.owners.Black == 1 and Coop.owners.Jones == 2, "refused player keeps Black")
CoopPatrol.chosenTrio()
assert(Coop.cfg.patrol == "2", "full: only the real trio holder goes to the side instance (old code: want = 1,2): " .. tostring(Coop.cfg.patrol))
Coop.storyDriven.Cole, Coop.storyDriven.Rawlings = nil, nil

-- 14. G6 (level start, three cards): Cole and Rawlings are switched-off props (def.inactive) a player may
-- take; a third player for the gate top finds it full and stays; the sacrifice card is Church's
ents.Cole.bActive, ents.Rawlings.bActive = false, false
r = setup("G6", {Church = 0, Jones = 1, Black = 2, Delgado = 3},
          {[1] = {2, true}, [2] = {2, true}, [3] = {2, true}, [0] = {1, true}})
assert(owner("Cole") == 1 and owner("Rawlings") == 2, "gate top taken by the first two: " .. tostring(owner("Cole")) .. tostring(owner("Rawlings")))
assert(owner("Delgado") == 3 and r.move[3] == nil, "the third finds the gate top full and keeps Delgado")
assert(owner("Church") == 0, "the host keeps Church (sacrifice card)")
local full
for _, m in ipairs(sent) do if m:find("^%-1>chr") then full = m end end
assert(full and full:find("3:Delgado:full"), "reason full: " .. tostring(full))
local evJ
for _, m in ipairs(sent) do if m:find("^1>evict|Jones|Cole") then evJ = m end end
assert(evJ == "1>evict|Jones|Cole|a", "the move into a switched-off body asks for its activation: " .. tostring(evJ))
ents.Cole.bActive, ents.Rawlings.bActive = nil, nil

-- 15. pinned holder (Act 1: Ross): his card is fixed, his own pick is ignored, the others choose freely
ents.Ross = {Name = "Ross", Life = 100, Active = 1}
r = setup("G1A", {Ross = 0, Church = 1, Black = 2}, {[0] = {2, true}, [1] = {2, true}})
assert(owner("Ross") == 0, "Ross's holder stays with Ross")
assert(owner("Church") == nil and (owner("Jones") == 1 or owner("Cole") == 1 or owner("Delgado") == 1), "Church's holder went to Alpha")
assert(owner("Black") == 2, "the unconfirmed player keeps his body")
res = nil
for _, m in ipairs(sent) do if m:find("^%-1>chr") then res = m end end
assert(res:find("0:Ross:pinned"), "pinned reason: " .. res)
assert(C.result.final[0] == "Ross", "pinned keeps Ross")
-- the pinned player is told in the opening message
local chs
C.reset(); switched, sent = {}, {}
Coop.owners = {Ross = 0, Church = 1}
C.pending.G1A = {since = clock}; C.start("G1A")
for _, m in ipairs(sent) do if m:find("^%-1>chs|") then chs = m end end
assert(chs == "-1>chs|G1A|25|0,1|0|1,2", "pinned list and cards in chs: " .. tostring(chs))
assert(C.cur.pinned[0] and C.cur.picks[0].conf, "pinned player is confirmed from the start")

-- 16. G3: a one-body card (Cole at the console): the first confirmed wins, the others defend
r = setup("G3", {Ross = 0, Church = 1, Black = 2}, {[1] = {1, true}, [2] = {1, true}})
assert(owner("Cole") == 1 and owner("Black") == 2 and owner("Church") == nil, "G3: first confirmed hacks")

-- 17. G11, G15, G4: the hero card takes the player out of his body, an exchange when the holder wants out
r = setup("G11", {Black = 0, Jones = 1}, {[0] = {1, true}, [1] = {1, true}})
assert(owner("Church") == 0 and owner("Jones") == 1, "G11: host crosses as Church, client keeps Jones")
r = setup("G15", {Church = 0, Black = 1}, {[0] = {2, true}, [1] = {1, true}})
assert(owner("Church") == 1 and r.final[0] == "Delgado" or r.final[0] == "Rawlings" or r.final[0] == "Black", "G15 exchange")
assert(owner("Church") == 1, "G15: Church's holder left, the other took him")
r = setup("G4", {Church = 0, Cole = 1}, {[0] = {1, true}, [1] = {1, true}})
assert(owner("Rawlings") == 0 and owner("Cole") == 1, "G4: the host walks Rawlings' soul")

-- 18. split screen: two local players (owner 0 and its player 2 = P2); player 2's pad 2 presses its own pick
Coop.owners = {Church = 0, Black = 8, Delgado = 1}
C.reset(); switched, sent = {}, {}
C.pending.G8 = {since = clock}; C.start("G8")
assert(#C.scr.locals == 2 and C.scr.locals[1].owner == 0 and C.scr.locals[2].owner == 8 and C.scr.locals[2].pad == 1, "two local players")
C.localUpdate()
assert(C.press("d1", 2) == 1, "p2 press registered")
C.localUpdate()
assert(C.cur.picks[8].conf and C.cur.picks[8].g == 1 and not C.cur.picks[0].conf, "player 2's digit pick is its own, not player 1's")
assert(C.scr.locals[2].cursor == 1, "p2 cursor")
C.press("right", 1); C.localUpdate()
assert(C.cur.picks[0].g == 2 and not C.cur.picks[0].conf, "player 1 moved to the second card")
C.press("confirm", 1); C.localUpdate()
assert(C.cur.picks[0].conf, "player 1 confirmed")
-- 19. load order of the real game: coop_splits.lua comes BEFORE coop_choice.lua (coop.lua), which builds its own DEFS.
-- The split's hook (G6afterChoice) must still run on every machine when the result is known, and the held start
-- (resume) of every split must run once after the choice.
CoopChoice = nil
V3D = V3D or function(x, y, z) return {x = x, y = y, z = z} end
dofile("coop_splits.lua")
local Sp = CoopSplits
dofile("coop_choice.lua")
C = CoopChoice
assert(Sp.afterChoice and Sp.afterChoice.G6 == Sp.G6afterChoice, "split registers its hook by name")
local spy = {}
for _, fn in ipairs({"G6keepHumans", "setSides", "showNotice"}) do
  Sp[fn] = function(...) spy[#spy + 1] = fn end
end
Sp.G6.free = false
Coop.role = "host"; Coop.cfg.myId = nil
for id, def in pairs(C.DEFS) do
  local g1, g2 = def.groups[1], def.groups[2]
  local human = {}
  Coop.owners = {}
  Coop.owners[g1.chars[1]] = 0
  Coop.owners[g2.chars[1]] = 1
  for _, n in ipairs({"Ross"}) do ents[n] = ents[n] or {Name = n, Life = 100, Active = 1} end
  C.reset(); spy = {}
  local resumed = 0
  C.pending[id] = {since = clock, resume = function() resumed = resumed + 1 end}
  C.start(id)
  C.setPick(1, 2, true); C.setPick(0, 1, true)
  C.resolve()
  if id == "G6" then
    local seen = table.concat(spy, ",")
    assert(seen:find("G6keepHumans") and seen:find("setSides") and seen:find("showNotice"),
           "G6: the split's own code ran after the choice: " .. seen)
  else
    assert(#spy == 0, id .. ": no hook expected, got " .. table.concat(spy, ","))
  end
  assert(resumed == 0, id .. ": start still held during the explanation")
  clock = clock + C.RESULT_HOLD + 1
  C.runLater()
  assert(resumed == 1, id .. ": the held start ran once: " .. resumed)
end
-- a client runs the hook too (chr from the host)
Coop.role = "client"; Coop.cfg.myId = 1
Coop.isClient = function() return true end; Coop.isHost = function() return false end
C.reset(); spy = {}
C.onMessage(0, {"chr", "G6", "1:Jones:keep"})
assert(table.concat(spy, ","):find("showNotice"), "client: the G6 hook ran on chr")
Coop.role = "host"; Coop.cfg.myId = nil
Coop.isClient = function() return false end; Coop.isHost = function() return true end
print("choice mock test: ok")
