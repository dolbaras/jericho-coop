-- Offline check of the fire controls of puppets (coop_anim.lua: second trigger, weapon modes, ammo).
-- Run: lua tests/fire_mock_test.lua  (from mod/lua)
local clock = 100
local logs = {}
Net = {CoopTime = function() return clock end}
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end}
Act = {GetClass = function() return {GetAct = function() return nil end} end}
dofile("coop_anim.lua")
local A = CoopAnim

local function body(name)
  return {Name = name, owc = {Shot = 0, SecondWeaponTrigger = 0}}
end

-- 1. the second trigger of an owner's body is a state field
local b = body("Black")
assert(A.stateFire(b) == "0", "released")
b.owc.SecondWeaponTrigger = 1
assert(A.stateFire(b) == "1", "held")
assert(A.stateFire({Name = "x"}) == "0", "a body without controls")
assert(A.stateFire(setmetatable({}, {__index = function() error("engine") end})) == "0", "an unreadable field is 0")

-- 2. a puppet gets both triggers from the drawn state, and lets go of the second one
local p = body("Black")
A.driveFire(p, "Black", {shot = 0, sec = true})
assert(p.owc.Shot == 0 and p.owc.SecondWeaponTrigger == 1, "grenade launcher fired with the second trigger")
A.driveFire(p, "Black", {shot = 1, sec = false})
assert(p.owc.Shot == 1 and p.owc.SecondWeaponTrigger == 0, "main trigger only")
A.driveFire(p, "Black", {})
assert(p.owc.Shot == 0 and p.owc.SecondWeaponTrigger == 0, "nothing held")

-- 3. the old behaviour is a switch
Coop.cfg.puppetsecond = false
local q = body("Delgado")
A.driveFire(q, "Delgado", {shot = 1, sec = true})
assert(q.owc.Shot == 1 and q.owc.SecondWeaponTrigger == 0, "cfg.puppetsecond=false leaves the second trigger alone")
Coop.cfg.puppetsecond = nil

-- 4. a body without owc does nothing
A.driveFire({Name = "Cole"}, "Cole", {shot = 1, sec = true})

print("fire mock test ok")
