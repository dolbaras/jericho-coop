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
clock = clock + 1
A.driveFire(p, "Black", {})
assert(p.owc.Shot == 0 and p.owc.SecondWeaponTrigger == 0, "nothing held")

-- 3. the old behaviour is a switch
Coop.cfg.puppetsecond = false
clock = clock + 5
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

-- 7. a firing puppet keeps its magazines loaded (a pistol of 6 rounds, a launcher of 1), a silent one is left alone
local function slotsOf(a, b) return {[0] = a, [1] = b} end
local function mag(load, max, loaded, supply) return {oType = {AmmoLoad = load, MaxAmmoSupply = max}, AmmoLoaded = loaded, AmmoSupply = supply} end
local sl = slotsOf(mag(25, 1000, 0, 800), mag(6, 50, 0, 3))
local pd = {Name = "Delgado", owc = {Shot = 0}, oWeapCtrl = {Slot = function(self, i) return sl[i] end}}
clock = clock + 1
A.driveFire(pd, "Delgado", {shot = 0, sec = false})
assert(sl[0].AmmoLoaded == 0 and sl[1].AmmoLoaded == 0, "a puppet that does not fire is not touched")
A.driveFire(pd, "Delgado", {shot = 0, sec = true})
assert(sl[0].AmmoLoaded == 25 and sl[1].AmmoLoaded == 6, "loaded while the second trigger is held")
assert(sl[0].AmmoSupply == 800 and sl[1].AmmoSupply == 50, "a low supply is refilled, a high one left: " .. sl[1].AmmoSupply)
sl[1].AmmoLoaded = 0
A.driveFire(pd, "Delgado", {shot = 1})
assert(sl[1].AmmoLoaded == 0, "looked at again only after 0.2 s")
clock = clock + 0.25
A.driveFire(pd, "Delgado", {shot = 1})
assert(sl[1].AmmoLoaded == 6, "refilled again")
-- a single-round launcher is refilled when empty, a magazine with rounds left is not
local sg = slotsOf(mag(5, 50, 3, 50), mag(1, 10, 0, 10))
local pb = {Name = "Black", owc = {Shot = 0}, oWeapCtrl = {Slot = function(self, i) return sg[i] end}}
clock = clock + 1
A.driveFire(pb, "Black", {sec = true})
assert(sg[0].AmmoLoaded == 3 and sg[1].AmmoLoaded == 1, "grenade launcher reloaded, the sniper's 3 rounds kept")
-- a blade (no magazine) and the switch
local sw = slotsOf(mag(45, 500, 45, 500), mag(0, 0, 0, 0))
local pch = {Name = "Church", owc = {Shot = 0}, oWeapCtrl = {Slot = function(self, i) return sw[i] end}}
clock = clock + 1
A.driveFire(pch, "Church", {shot = 1})
assert(sw[1].AmmoLoaded == 0 and sw[1].AmmoSupply == 0, "the sabre has no magazine")
Coop.cfg.puppetammo = false
sl[1].AmmoLoaded = 0; clock = clock + 1
A.driveFire(pd, "Delgado", {shot = 1})
assert(sl[1].AmmoLoaded == 0, "cfg.puppetammo=false")
Coop.cfg.puppetammo = nil

-- 8. which third-person reload a first-person reload is (Delgado has Reload0 only; Rawlings' fragmenting loads are ReloadE)
local function cls(...)
  local have = {}
  for _, n in ipairs({...}) do have[n] = true end
  return {GetAct = function(self, n) return have[n] and {} or nil end}
end
assert(A.reloadAction("Delgado", cls("Reload0", "DuckReload0"), "", nil, "02") == "Reload0", "Delgado's pistol")
assert(A.reloadAction("Black", cls("Reload", "Reload0"), "", nil, "02") == "Reload0", "Black's grenade launcher")
assert(A.reloadAction("Black", cls("Reload", "Reload0"), "", nil, "01") == "Reload", "Black's sniper")
assert(A.reloadAction("Jones", cls("Reload", "Reload0"), "", nil, "02") == "Reload0", "Jones' shotgun")
assert(A.reloadAction("Cole", cls("Reload"), "", nil, "02") == "Reload", "Cole has one reload")
assert(A.reloadAction("Rawlings", cls("Reload", "Reload0", "ReloadE"), "", nil, "02") == "Reload", "Rawlings' left pistol is a plain reload")
assert(A.reloadAction("Rawlings", cls("Reload", "Reload0", "ReloadE"), "2", nil, "01") == "ReloadE", "fragmenting load")
assert(A.reloadAction("Church", cls("Reload"), "", nil, "02") == "Reload", "Church")

print("fire mock test ok")

-- 5. a short pull is played to its end: the trigger stays down through the Init action and a moment of the loop (live: Delgado's Bull)
clock = clock + 10
A.driveFire(body("Delgado"), "Delgado", {})   -- (the earlier tests left this body's trigger down)
local d = body("Delgado")
d.Action = "Relax0"
A.driveFire(d, "Delgado", {shot = 1, sec = true})
assert(d.owc.Shot == 1 and d.owc.SecondWeaponTrigger == 1)
clock = clock + 0.1; d.Action = "Shot0Init"
A.driveFire(d, "Delgado", {shot = 0, sec = false})   -- the owner let go after 0.1 s
assert(d.owc.Shot == 1 and d.owc.SecondWeaponTrigger == 1, "the pull is kept down while the Init plays")
clock = clock + 0.3; d.Action = "Shot0Init"
A.driveFire(d, "Delgado", {shot = 0, sec = false})
assert(d.owc.Shot == 1 and d.ForceAction == "Shot0", "the pistol's wind-up is cut short after 0.3 s")
d.ForceAction = nil; clock = clock + 1.1
clock = clock + 0.1; d.Action = "Shot0"
A.driveFire(d, "Delgado", {shot = 0, sec = false})
assert(d.owc.Shot == 1, "first frames of the loop: the shot is confirmed")
clock = clock + 0.4; d.Action = "Shot0"
A.driveFire(d, "Delgado", {shot = 0, sec = false})
assert(d.owc.Shot == 0 and d.owc.SecondWeaponTrigger == 0, "let go after the grace")
-- a body that never enters the Init is not held for ever
clock = clock + 10
A.driveFire(body("Black"), "Black", {}); clock = clock + 5; A.driveFire(body("Black"), "Black", {})   -- (earlier tests)
local f = body("Black")
f.Action = "Relax"
A.driveFire(f, "Black", {shot = 1})
clock = clock + 0.2; A.driveFire(f, "Black", {})
assert(f.owc.Shot == 1, "held for the first 0.35 s")
clock = clock + 0.3; A.driveFire(f, "Black", {})
assert(f.owc.Shot == 0, "released when no Init follows")
-- a stuck Init lets go after 3 s
clock = clock + 10
A.driveFire(body("Delgado"), "Delgado", {})
local g = body("Delgado")
g.Action = "Shot0Init"
A.driveFire(g, "Delgado", {shot = 1})
clock = clock + 3.2; A.driveFire(g, "Delgado", {})
assert(g.owc.Shot == 0, "3 s at most")
-- the switch
Coop.cfg.puppetholdshot = false
clock = clock + 10
A.driveFire(body("Delgado"), "Delgado", {})
local h = body("Delgado"); h.Action = "Shot0Init"
A.driveFire(h, "Delgado", {shot = 1}); clock = clock + 0.1; A.driveFire(h, "Delgado", {})
assert(h.owc.Shot == 0, "cfg.puppetholdshot=false: the owner's trigger only")
print("fire mock test ok (hold)")
