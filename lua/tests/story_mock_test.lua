-- Offline check of coop_story.lua wrappers with stub engine tables.
-- Run: lua tests/story_mock_test.lua (from mod/lua)
local sent = {}
local ents = {Church = {Name = "Church"}, Black = {Name = "Black"}, Rawlings = {Name = "Rawlings"}}
local me = ents.Black
Game = {
  UsrEntity = function(i) return me end,
  GetEntity = function(n) return ents[n] end,
  Get = function() return 0 end, Set = function() end, GetTime = function() return 0 end,
  AddScheduledFunc = function() end,
}
Net = {CoopSend = function(peer, rel, msg) sent[#sent + 1] = msg end, CoopTime = function() return 0 end}
V3D = function(x, y, z) return {x = x, y = y, z = z} end
Coop = {cfg = {}, frame = 1, level = "levels/wwii_biggates", storyDriven = {}, remote = {}, log = function() end,
  inSession = function() return true end, isHost = function() return true end,
  isClient = function() return false end, myId = function() return 0 end,
  localChar = function() return me.Name end,
  owners = {Church = 1, Black = 0},
  ownerOf = function(n) return Coop.owners[n] end,
  isRemoteOwned = function(n) return Coop.owners[n] ~= nil and Coop.owners[n] ~= 0 end,
  addLangs = function() end,
  isLocalBody = function(n) return n ~= nil and (n == me.Name or Coop.owners[n] == 0) end,
  heldBy = function(n, peer) local o = Coop.owners[n or ""] return o ~= nil and o == peer end}
CoopWorld = {isHuman = function(n) return Coop.owners[n] ~= nil end}
MapInit = {}
local seen
function MapInit.TestWard() seen = Game.UsrEntity(0).Name end
SummerianNINLIL = {Use = function() seen = Game.UsrEntity(0).Name end}
dofile("coop_story.lua")
local St = CoopStory
St.update(); local w1 = MapInit.TestWard; local u1 = SummerianNINLIL.Use
St.update(); St.update()
assert(MapInit.TestWard == w1, "TestWard rewrapped")
assert(SummerianNINLIL.Use == u1, "Use rewrapped")
MapInit.TestWard(); assert(seen == "Church", "TestWard sees " .. tostring(seen))
assert(Game.UsrEntity(0).Name == "Black", "UsrEntity restored")
Coop.owners.Church = nil
MapInit.TestWard(); assert(seen == "Black", "vanilla when Church is AI: " .. tostring(seen))
-- Jones held by nobody: Use sees the host body; no event sent (host is not Jones)
SummerianNINLIL.Use("Jones", "Ninlil"); assert(seen == "Black")
assert(#sent == 0, "unexpected send " .. tostring(sent[1]))
-- host is Church: ward callback event goes to all
me = ents.Church; Coop.owners = {Church = 0}
Church = {callOnWard = function() seen = "ward" end}
St.update()
local f = Church.callOnWard; Church.callOnWard = nil; f()
assert(seen == "ward" and sent[1] and string.find(sent[1], "^ev|1|0"), "ward event: " .. tostring(sent[1]))
-- receiving a client's event on the host: must come from Church's owner
sent = {}; Coop.owners = {Church = 2}; Church.callOnWard = function() seen = "ward2" end
St.onEvent(2, {"ev", "1", "2"})
assert(seen == "ward2" and Church.callOnWard == nil and #sent == 1, "host relay")
seen = nil; Church.callOnWard = function() seen = "bad" end
St.onEvent(3, {"ev", "1", "3"}); assert(seen == nil, "non-owner event accepted")
-- sdone matching: an unrelated sdone (look-at step, another body's walk) leaves a player-step arrival
-- pending; the host's player-step sdone ("p|x|z") releases the one with its destination
local arrived = {}
St.pending = {Black = {func = function() arrived[#arrived + 1] = "a" end, args = {"Black", V3D(10, 0, 20)}, playerStep = true, t = 0}}
St.onDone("Church")
assert(#arrived == 0 and St.pending.Black, "unrelated sdone released a player step")
St.onDone("Ross", nil, nil, nil)
assert(#arrived == 0 and St.pending.Black, "sdone without the player-step flag released it")
St.pending.Cole = {func = function() arrived[#arrived + 1] = "b" end, args = {"Cole", V3D(500, 0, 500)}, playerStep = true, t = 0}
ents.Cole = {Name = "Cole"}
St.onDone("Ross", "p", "10", "20")
assert(#arrived == 1 and arrived[1] == "a" and not St.pending.Black and St.pending.Cole, "player-step sdone matched by destination")
St.onDone("Ross", "p", "9999", "9999")
assert(#arrived == 2 and not St.pending.Cole, "no destination matches: the pending player steps are released")
-- the host's message carries the flag only for a step that walks the player
MapInit.player = {Name = "Church"}
assert(St.doneMsg("Church", V3D(10, 0, 20)) == "sdone|Church|p|10|20", St.doneMsg("Church", V3D(10, 0, 20)))
assert(St.doneMsg("Black", V3D(10, 0, 20)) == "sdone|Black")
MapInit.player = nil
print("story mock test ok")
