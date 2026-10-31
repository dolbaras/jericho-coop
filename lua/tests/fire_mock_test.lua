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

-- 5. fire modes: read from the slots, applied to a puppet no more than every 0.25 s, only when they differ
local j = body("Jones")
j.Weap_Slot00ShootMode, j.Weap_Slot01ShootMode = 1, 2
assert(A.stateModes(j) == "1-2-", "modes of a machine gun body: " .. A.stateModes(j))
assert(A.stateModes({Name = "Black"}) == "----", "unreadable modes")
local pj = body("Jones")
pj.Weap_Slot00ShootMode, pj.Weap_Slot01ShootMode = 2, 2
A.driveFire(pj, "Jones", {shot = 1, modes = "0-2-"})
assert(pj.Weap_Slot00ShootMode == 0 and pj.Weap_Slot01ShootMode == 2, "semi mode taken")
pj.Weap_Slot00ShootMode = 2
A.driveFire(pj, "Jones", {shot = 1, modes = "0-2-"})
assert(pj.Weap_Slot00ShootMode == 2, "not looked at again within 0.25 s")
clock = clock + 0.3
A.driveFire(pj, "Jones", {shot = 1, modes = "0-2-"})
assert(pj.Weap_Slot00ShootMode == 0, "looked at again")
Coop.cfg.puppetmodes = false
pj.Weap_Slot00ShootMode = 2; clock = clock + 1
A.driveFire(pj, "Jones", {shot = 1, modes = "0-2-"})
assert(pj.Weap_Slot00ShootMode == 2, "cfg.puppetmodes=false")
Coop.cfg.puppetmodes = nil

-- 6. Rawlings' pistol load: the game's own setters run on the slot
local slots = {[0] = {ShotReloadPrefix = ""}, [1] = {ShotReloadPrefix = "2"}}
local rw = {Name = "Rawlings", owc = {Shot = 0}, oWeapCtrl = {Slot = function(self, i) return slots[i] end}}
rw.Weap_Slot00ShootMode, rw.Weap_Slot01ShootMode = 2, 2
Rawlings = {
  SetStandard = function(slt) slt.ShotReloadPrefix = "" end,
  SetFragment = function(slt) slt.ShotReloadPrefix = "2" end,
  SetExplosive = function(slt) slt.ShotReloadPrefix = "3" end,
}
assert(A.stateModes(rw) == "2022", "Rawlings modes, slot 1 holds the fragmenting load: " .. A.stateModes(rw))
local prw = {Name = "Rawlings", owc = {Shot = 0}, oWeapCtrl = {Slot = function(self, i) return slots[i] end}}
slots[0].ShotReloadPrefix, slots[1].ShotReloadPrefix = "", ""
clock = clock + 1
A.driveFire(prw, "Rawlings", {shot = 1, modes = "2320"})
assert(slots[0].ShotReloadPrefix == "3" and slots[1].ShotReloadPrefix == "", "explosive on slot 0, standard on slot 1")
clock = clock + 1
A.driveFire(prw, "Rawlings", {shot = 1, modes = "2022"})
assert(slots[0].ShotReloadPrefix == "" and slots[1].ShotReloadPrefix == "2", "switched back and to fragmenting")
-- another body never gets the pistol load
local pc = body("Cole"); pc.oWeapCtrl = {Slot = function(self, i) return slots[i] end}
clock = clock + 1
A.driveFire(pc, "Cole", {shot = 1, modes = "2320"})
assert(slots[0].ShotReloadPrefix == "" and slots[1].ShotReloadPrefix == "2", "pistol load is Rawlings' only")

print("fire mock test ok")
