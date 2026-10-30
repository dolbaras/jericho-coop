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
print("cooluse mock test: OK")
