-- Offline check of the spectator's switching inputs (coop_spectate.lua): one switch per press whichever inputs fire,
-- nothing held at death switches, no switch while a menu is open.
-- Run: lua tests/spectate_mock_test.lua  (from mod/lua)
local clock = 100
local held, axes, actionSet = {}, {}, "Walk"
Net = {CoopTime = function() return clock end,
       CoopKey = function(vk, n) if vk == -1 then return nil end return held[vk] and 1 or 0 end}
V3D = function(x, y, z) return {x = x, y = y, z = z} end
Color = function(...) return {...} end
Input = {GetInputState = function(set, action) return axes[action] or 0 end, GetActionSet = function() return actionSet end}
local function ent(name, x) return {Name = name, Life = 100, Active = 1, bActive = true, Pos = V3D(x, 0, 0), Ang = V3D(0, 0, 0)} end
local ents = {Black = ent("Black", 0), Church = ent("Church", 100), Cole = ent("Cole", 200), CoopSpecCam = {Name = "CoopSpecCam"}}
ents.Black.Life = 0
Game = {UsrEntity = function() return ents.Black end, GetEntity = function(n) return ents[n] end, GetCam = function() return "MainCam" end,
        SetCam = function() end, CreateEntity = function() return ents.CoopSpecCam end, Get = function() return 0 end}
Scorer = {GetItem = function() return nil end}
local logs = {}
Coop = {cfg = {}, owners = {Black = 0, Church = 1, Cole = 2}, log = function(s) logs[#logs + 1] = s end, inSession = function() return true end,
        lang = function() return "en" end, enc = function(s) return s end, addLangs = function() end, charName = function(n) return n end,
        textBlock = function() end, textBlockHide = function() end}
CoopTeam = {down = true}
dofile("coop_spectate.lua")
local S = CoopSpectate

local function target() return S.target end
local function tick(dt) clock = clock + (dt or 0.05); return S.update() end
local KEY_D, KEY_A, KEY_FIRE = S.KEY_D, S.KEY_A, S.KEY_FIRE

-- entry with fire held (a shot being held at death): no switch until released and pressed again
held[KEY_FIRE] = true; axes.MainShot = 1
tick()
local first = target()
assert(first == "Church", "starts at the nearest: " .. tostring(first))
for _ = 1, 10 do tick() end
assert(target() == first, "a fire held at death switches nothing")
held[KEY_FIRE] = nil; axes.MainShot = 0
tick(); tick(0.4)
held[KEY_FIRE] = true; axes.MainShot = 1
tick()
assert(target() ~= first, "a new press switches")
held[KEY_FIRE] = nil; axes.MainShot = 0
tick(0.5)

-- one press of D: the key edge now, the strafe axis passing 0.6 a frame later: one switch
local before = target()
held[KEY_D] = true
tick()
local after1 = target()
assert(after1 ~= before, "D switches")
axes.StrafeRight = 1
tick()
assert(target() == after1, "the axis a frame later does not switch again")
held[KEY_D] = nil; axes.StrafeRight = 0
tick(0.5)

-- two inputs inside the gap: one switch; after the gap the next press counts
local b2 = target()
held[S.KEY_NEXT] = true; tick()
local a2 = target()
assert(a2 ~= b2, "arrow switches")
held[S.KEY_NEXT] = nil; held[KEY_A] = true
tick(0.1)
assert(target() == a2, "a second input within the gap is dropped")
held[KEY_A] = nil; tick(0.4)
held[KEY_A] = true; tick()
assert(target() == b2, "after the gap the next press switches (back)")
held[KEY_A] = nil; tick(0.4)

-- a menu / ESC overlay: a left click there is no switch, and one held when it closes switches nothing
local b3 = target()
actionSet = "Menu"
held[KEY_FIRE] = true; axes.MainShot = 1
tick(); tick()
assert(target() == b3, "no switch while a menu is open")
actionSet = "Walk"
tick(); tick(0.4)
assert(target() == b3, "a click held while the menu closed switches nothing")
held[KEY_FIRE] = nil; axes.MainShot = 0
tick(0.4)
held[KEY_FIRE] = true; axes.MainShot = 1
tick()
assert(target() ~= b3, "a fresh click after that switches")
print("spectate mock test: ok")
