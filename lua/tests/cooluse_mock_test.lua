-- Offline check of CoopWorld.installCoolUse (a puppet only plays the object's action) and Coop.stormRelease/clearPins.
-- Run: lua tests/cooluse_mock_test.lua (from mod/lua)
local logs = {}
local ents = {o191 = {Name = "o191", Action = ""}}
Game = {GetEntity = function(n) return ents[n] end}
Net = {CoopTime = function() return 10 end}
V3D = function(x, y, z) return {x = x, y = y, z = z} end
Coop = {cfg = {}, addLangs = function() end, log = function(s) logs[#logs + 1] = s end, inSession = function() return true end,
  puppets = {Delgado = true}, isPuppet = function(n) return Coop.puppets[n] == true end}
local origCalls = {}
MakeFP = {CoolUse = function(ent, obj, ea, oa, node) origCalls[#origCalls + 1] = ent .. "/" .. obj end}
dofile("coop_world.lua")
CoopWorld.installCoolUse()
local wrapped = MakeFP.CoolUse
CoopWorld.installCoolUse()
assert(MakeFP.CoolUse == wrapped, "wrapped twice")
-- a puppet: the object acts, the original does not run
MakeFP.CoolUse("Delgado", "o191", "OpenLightDoor", "Open", "DF_FPDelgado")
assert(#origCalls == 0, "original ran for a puppet")
assert(ents.o191.Action == "Open", "object did not act: " .. tostring(ents.o191.Action))
assert(CoopWorld.coolUsePuppets == 1 and string.find(logs[#logs], "only the object acts"))
-- a local player: the original runs
MakeFP.CoolUse("Jones", "o191", "OpenLightDoor", "Open", "DF_FPDelgado")
assert(#origCalls == 1 and origCalls[1] == "Jones/o191", "original did not run for the local player")
-- The world digest back-off keys on the residual: a request is not sent while the same difference stays, but a different
-- mismatch (this machine's entries or the host's changed) opens it again
local W = CoopWorld
local sentMsgs = {}
Net.CoopSend = function(to, rel, msg) sentMsgs[#sentMsgs + 1] = msg end
Coop.role = "client"
Coop.isClient = function() return true end
Coop.isHost = function() return false end
local realOpen = {D1 = true}
W.doorOpen = function(n) return realOpen[n] end
W.setDoor = function(n, o) W.doors[n] = o end
W.doors, W.dead, W.blockers = {D1 = true}, {}, {}
W.applyState("D:D1-")
assert(W.residualN == 1 and not W.backoff, "first residual state: no back-off yet")
W.applyState("D:D1-")
assert(W.residualN == 2 and W.backoff and W.nextNeed == 10 + W.NEED_BACKOFF, "the same residual twice: back-off")
-- (as in a real run the host's digest was seen before the state came)
sentMsgs = {}
W.mismatch, W.residualN, W.residualKey, W.backoff, W.nextNeed = 0, 0, nil, nil, nil
W.hostSum = 111
W.applyState("D:D1-"); W.applyState("D:D1-")
assert(W.backoff and W.backoff.host == 111, "back-off remembers the host's digest")
for i = 1, 4 do W.onObjectMessage(0, {"wd", "1", "111"}) end
assert(#sentMsgs == 0, "same residual: no request during the back-off")
-- this machine's entries change (a new door differs): the back-off ends and the request goes out
realOpen.D2 = true; W.doors.D2 = true
for i = 1, 2 do W.onObjectMessage(0, {"wd", "1", "111"}) end
local need
for _, m in ipairs(sentMsgs) do if m == "wdneed" then need = true end end
assert(need and not W.backoff, "a different mismatch opens the requests again")
-- another residual set restarts the count
W.residualN, W.residualKey, W.backoff, W.nextNeed = 0, nil, nil, nil
W.applyState("D:D1-")
W.applyState("D:D1-;D:D2-")
assert(W.residualN == 1 and not W.backoff, "a different residual set is a new first state")
-- a matching digest ends everything
local n, sum = W.digest(W.entries())
W.onObjectMessage(0, {"wd", tostring(n), tostring(sum)})
assert(not W.backoff and W.nextNeed == nil and W.residualN == 0, "match clears the back-off")

-- Blockers on a client: the host's word holds; a stale local flip is set back after the grace period, a flip that agrees
-- with the host's (later) word is not touched
local blocker = {Name = "B1", bMapCollision = true}
Game.GetEntity = function(n) if n == "B1" then return blocker end return ents[n] end
W.blockers = {B1 = false}
W.nextEnforce, W.blockDiff, W.blockEnforced = nil, nil, nil
W.enforceBlockers(100)
W.enforceBlockers(100.3)
assert(blocker.bMapCollision == true, "inside the grace period nothing is touched")
W.enforceBlockers(100.9)
assert(blocker.bMapCollision == false and W.blockEnforced == 1, "a stale local flip is set back after the grace period")
-- the client's own change finishes just before the host's word arrives: the word agrees, nothing is undone
W.blockers = {B1 = false}
W.nextEnforce, W.blockDiff, W.blockEnforced = nil, nil, nil
blocker.bMapCollision = true
W.enforceBlockers(200)
W.setBlocker("B1", true)   -- the host's blk message
W.enforceBlockers(201.5)
assert(blocker.bMapCollision == true and (W.blockEnforced or 0) == 0, "a flip the host's word confirms stands")
print("cooluse mock test: OK")
