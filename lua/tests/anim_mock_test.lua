-- Offline check of coop_anim.lua (downed puppets fall, one revive, one-shots) with stub engine tables.
-- Run: lua tests/anim_mock_test.lua  (from mod/lua)
local clock = 100
local logs = {}
Net = {CoopTime = function() return clock end}
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end}
local revFn = {}
Team = {AssignReviveFunction = function(e) e.ArrowCanUse = 1 end,
        RemoveReviveFunction = function(e) e.ArrowCanUse = 0 end}
Coop.ARM_ACTIONS = {{"^Combo(%d)Hit(%d)$", "x"}, {"^Punch", "Punch"}, {"^Reload", "Reload"}, {"^Spell", "Spell"}, {"^Hack", "Hack"},
  {"^Special_0Init$", "Shot1Init"}, {"^Special", "Special1"}}
Coop.ARM_BY_CHAR = {Black = {["^Special"] = "TKHit"}}
local ACTS = {TKHit = 1, Reequip = 1, ShelterDownInit = 1, ShelterDownEnd = 1, StupidInit = 1, StupidEnd = 1, Shot1Init = 1,
              HitStrong = 1, Agony = 1, AgonyInit = 1, AgonyEnd = 1, Agony2 = 1, Agony2Init = 1, Agony2End = 1, HitStrong = 1, Hit = 1,
              Reload = 1, Relax = 1, Run = 1, Shot1EndAlt = 1, ShotH = 1, DuckShotH = 1}
Act = {GetClass = function(n) return {GetAct = function(self, a) return ACTS[a] and {} or nil end} end}

-- the engine's tables the puppet-event guard wraps, and the entities it asks about
local evCalls = {}
local puppets = {Rawlings = true, Church = true}
Game = {GetEntity = function(n)
  if n == "0FP_Church" then return {Name = n, IsType = function(self, t) return t == "FP" end} end
  return {Name = n, IsType = function() return false end}
end}
Coop.inSession = function() return true end
Coop.isPuppet = function(n) return puppets[n] == true end
WeaponsRawlings = {OnShotHeal = function(n) evCalls[#evCalls + 1] = "heal " .. tostring(n) end,
                   OnDoVladsCourse = function() evCalls[#evCalls + 1] = "vlad" end}
Rawlings = {GhostHealShot = function(n) evCalls[#evCalls + 1] = "ghost " .. tostring(n) end}
Church = {LoseLifeCutting = function(n) evCalls[#evCalls + 1] = "spell " .. tostring(n) end}

dofile("coop_anim.lua")
local A = CoopAnim

local function body(name) return {Name = name, ActCtrl = "", Life = 100, Action = "Relax", Invulnerable = 0} end
local function step(dt) clock = clock + dt end

-- 1. the owner is down: the puppet (Life already 0, standing) goes into agony, once, with its variant
local e = body("Church"); e.Life = 0
local st = {life = 0, action = "Agony2"}
A.sync(e, "Church", st)
assert(e.Action == "Relax", "the engine's own death gets its time first")
step(0.7)
A.sync(e, "Church", st)
assert(e.Action == "Agony2Init" and e.DefLoop == "Agony2", "variant of the owner: " .. tostring(e.Action))
assert(e.ArrowCanUse == 1, "revive function")
e.Action = "Agony2"                        -- the init action ran into its loop
A.sync(e, "Church", st); step(1); A.sync(e, "Church", st)
assert(e.Action == "Agony2" and A.downs == 1, "not put down again")

-- 2. the engine killed it itself: left alone
local e2 = body("Black"); e2.Life = 0; e2.Action = "Relax"
A.sync(e2, "Black", {life = 0, action = "AgonyInit"})
e2.Action = "AgonyInit"; step(1)
A.sync(e2, "Black", {life = 0, action = "AgonyInit"})
assert(e2.Action == "AgonyInit" and e2.ArrowCanUse == nil, "engine's own death untouched")

-- 3. revive: one origRevive call over many frames, then the engine's event gives the life back
local calls = 0
local function origRevive(x) calls = calls + 1; x.ForceAction = "Agony2End"; x.Action = "Agony2End" end
local rst = {life = 100, action = "Relax"}
for i = 1, 30 do A.revive(e, "Church", rst, origRevive); step(0.05) end
assert(calls == 1, "one revive call: " .. calls)
e.Life = 100                               -- Soldier.Revive at the end of the End action
A.sync(e, "Church", rst)
assert(A.state.Church.reviveT == nil and A.state.Church.downT == nil, "state reset after the revive")
-- a second downing later puts it down again
e.Life = 0; e.Action = "Relax"; step(3)
A.sync(e, "Church", {life = 0, action = "Agony"}); step(0.7)
A.sync(e, "Church", {life = 0, action = "Agony"})
assert(e.Action == "AgonyInit", "down again")

-- 4. a revive that never finishes: the life is set
local e4 = body("Cole"); e4.Life = 0; e4.Action = "Agony"
local c4 = 0
local function rv4(x) c4 = c4 + 1 end
for i = 1, 100 do if e4.Life <= 0 then A.revive(e4, "Cole", {life = 80}, rv4) end; step(0.05) end
assert(c4 == 1 and e4.Life == 80, "fallback life: " .. tostring(e4.Life) .. " calls " .. c4)

-- 5. one-shots: played once when the owner's action changes to one, not for locomotion
local e5 = body("Jones")
A.sync(e5, "Jones", {life = 100, action = "Run"})
assert(e5.ForceAction == nil, "locomotion not mirrored")
A.sync(e5, "Jones", {life = 100, action = "HitStrong"})
assert(e5.ForceAction == "HitStrong", "hit mirrored")
e5.ForceAction = nil; e5.Action = "HitStrong"
A.sync(e5, "Jones", {life = 100, action = "HitStrong"})
assert(e5.ForceAction == nil, "not twice for the same action")
step(1)
A.sync(e5, "Jones", {life = 100, action = "Run"}); e5.Action = "Run"
step(1)
A.sync(e5, "Jones", {life = 100, action = "Reload"})
assert(e5.ForceAction == "Reload", "reload mirrored")
-- the first-person arms played it just now (Coop.mirrorArms): not again
local e6 = body("Black")
Coop.mirrorT = {Black = clock - 0.2}
A.sync(e6, "Black", {life = 100, action = "Reload"})
assert(e6.ForceAction == nil, "not over mirrorArms")
-- a class without the action: nothing
local e7 = body("Rawlings")
A.sync(e7, "Rawlings", {life = 100, action = "Hack"})
assert(e7.ForceAction == nil, "unknown to the class")
-- unmapped actions are logged once
A.sync(e7, "Rawlings", {life = 100, action = "Whatever"}); A.sync(e7, "Rawlings", {life = 100, action = "Relax"})
A.sync(e7, "Rawlings", {life = 100, action = "Whatever"})
local n = 0
for _, l in ipairs(logs) do if string.find(l, "Rawlings:Whatever") then n = n + 1 end end
assert(n == 1, "unmapped action logged once: " .. n)

-- 8. states that last: Init on entering, End on leaving, once; the loop in between is the engine's
local e8 = body("Delgado")
A.sync(e8, "Delgado", {life = 100, action = "StupidInit"})
assert(e8.ForceAction == "StupidInit", "dazed starts")
e8.ForceAction = nil; e8.Action = "StupidInit"
A.sync(e8, "Delgado", {life = 100, action = "Stupid"})
assert(e8.ForceAction == nil, "the loop is left to the engine")
step(1)
A.sync(e8, "Delgado", {life = 100, action = "StupidEnd"})
assert(e8.ForceAction == "StupidEnd", "dazed ends with the owner's own End: " .. tostring(e8.ForceAction))
e8.ForceAction = nil
step(1.2)
A.sync(e8, "Delgado", {life = 100, action = "Relax"})
assert(e8.ForceAction == nil, "no second End when the owner leaves the family")
-- an owner that leaves the family without an End action of its own (a cut): the End plays at the latest then
local e8b = body("Delgado"); step(1)
A.sync(e8b, "Delgado", {life = 100, action = "StupidInit"}); e8b.ForceAction = nil
A.sync(e8b, "Delgado", {life = 100, action = "Stupid"})
A.sync(e8b, "Delgado", {life = 100, action = "Run"})
assert(e8b.ForceAction == "StupidEnd", "End when the family is left: " .. tostring(e8b.ForceAction))
-- (a dazed body is held: no walk input from the drawn state; cover is not)
local eh = body("Church"); step(1)
A.sync(eh, "Church", {life = 100, action = "StupidInit"})
local mo = A.moveOverride("Church")
assert(mo and mo.walk == 0 and mo.sprint == 0, "held while dazed")
A.sync(eh, "Church", {life = 100, action = "Relax"})
assert(A.moveOverride("Church") == nil, "free again")
-- cover
local e9 = body("Black")
A.sync(e9, "Black", {life = 100, action = "ShelterDownInit"})
assert(e9.ForceAction == "ShelterDownInit", "cover starts")
assert(A.moveOverride("Black") == nil, "a body in cover walks")
step(1); e9.ForceAction = nil
A.sync(e9, "Black", {life = 100, action = "ShelterDown"})
A.sync(e9, "Black", {life = 100, action = "ShelterDownReload"})
assert(e9.ForceAction == nil, "a reload in cover is no End")
A.sync(e9, "Black", {life = 100, action = "ShelterDownEnd"})
assert(e9.ForceAction == "ShelterDownEnd", "cover ends")
e9.ForceAction = nil
A.sync(e9, "Black", {life = 100, action = "Walk"})
assert(e9.ForceAction == nil, "once")

-- 9. first-person names with a third-person action; what mirrorArms maps is left to it
local e10 = body("Black")
step(1)
A.sync(e10, "Black", {life = 100, action = "Relax", fpa = "01_TKCombo1Hit1"})
assert(e10.ForceAction == "TKHit", "Black's telekinesis combo: " .. tostring(e10.ForceAction))
local e11 = body("Cole"); step(1)
A.sync(e11, "Cole", {life = 100, action = "Relax", fpa = "01_Reequip"})
assert(e11.ForceAction == "Reequip", "reequip")
local e12 = body("Church"); step(1)
A.sync(e12, "Church", {life = 100, action = "Relax", fpa = "01_Reload"})
assert(e12.ForceAction == nil, "reload is mirrorArms'")
A.sync(e12, "Church", {life = 100, action = "Relax", fpa = "01_Mystery"})
local n2 = 0
for _, l in ipairs(logs) do if string.find(l, "Church:Mystery") then n2 = n2 + 1 end end
assert(n2 == 1, "unmapped first-person action logged")
-- Rawlings reviving: the heal gesture; another member's first-person Heal has no twin (nothing played)
local e9r = body("Rawlings"); step(1)
A.sync(e9r, "Rawlings", {life = 100, action = "Relax", fpa = "01_Heal"})
assert(e9r.ForceAction == "ShotH", "Rawlings' revive gesture: " .. tostring(e9r.ForceAction))
local e9c = body("Cole"); step(1)
A.sync(e9c, "Cole", {life = 100, action = "Relax", fpa = "01_Heal"})
assert(e9c.ForceAction == nil, "no twin for the others")
-- 10. Delgado's release (AI body: the action arrives in the host's state)
local e13 = body("Delgado"); step(1)
A.sync(e13, "Delgado", {life = 100, action = "Shot1Init"})
assert(e13.ForceAction == "Shot1Init", "the arm opens")

-- 11. Cole's grenade: the launch event is dropped on a puppet, kept on the machine's own body
local launched = {}
WeaponsCole = {LaunchGrenade = function(name) launched[#launched + 1] = name end}
local ents = {
  Cole = {Name = "Cole", IsType = function() return false end},
  FP_Cole = {Name = "FP_Cole", IsType = function(self, t) return t == "FP" end},
}
Game = {GetEntity = function(n) return ents[n] end}
local puppets = {Cole = true}
Coop.inSession = function() return true end
Coop.isPuppet = function(n) return puppets[n] == true end
A.grenadeInstalled = nil
A.installGrenade()
assert(A.grenadeInstalled and WeaponsCole.LaunchGrenade ~= nil)
WeaponsCole.LaunchGrenade("Cole")
assert(#launched == 0 and A.grenadesDropped == 1, "no second grenade on a puppet")
puppets.Cole = false
WeaponsCole.LaunchGrenade("Cole")
assert(#launched == 1, "own body throws")
puppets.Cole = true
WeaponsCole.LaunchGrenade("FP_Cole")
assert(#launched == 2, "the first-person arms of the own player always throw")
A.installGrenade()    -- a second call does not wrap again
WeaponsCole.LaunchGrenade("Cole")
assert(#launched == 2 and A.grenadesDropped == 2, "still dropped once per call")
Coop.cfg.puppetgrenade = true
WeaponsCole.LaunchGrenade("Cole")
assert(#launched == 3, "switch: old behaviour")
Coop.cfg.puppetgrenade = nil

-- 12. a first-person hurdle runs on the spot for a moment, then the drawn state's inputs again
local eu = body("Jones"); step(1)
A.sync(eu, "Jones", {life = 100, action = "Relax", fpa = "01_Hurdle"})
local mo2 = A.moveOverride("Jones")
assert(mo2 and mo2.walk == 1 and mo2.sprint == 1, "hurdle runs")
step(0.5)
assert(A.moveOverride("Jones") == nil, "and stops")
A.sync(eu, "Jones", {life = 100, action = "Relax", fpa = "01_SkipWall"})
assert(A.moveOverride("Jones").sprint == 0, "a climb walks")

-- 13. Delgado's arm stays open (no spirit arrival): closed after ARM_MAX s, not before; not while the owner's body is in Shot1*
local ed = body("Delgado"); ed.Action = "Shot1"; step(1)
A.sync(ed, "Delgado", {life = 100, action = "Shot1"}); step(A.ARM_MAX + 1)
A.sync(ed, "Delgado", {life = 100, action = "Shot1"})
assert(ed.ForceAction ~= "Shot1EndAlt", "owner still in Shot1: left open")
A.sync(ed, "Delgado", {life = 100, action = "Relax"}); step(2)
A.sync(ed, "Delgado", {life = 100, action = "Relax"})
assert(ed.ForceAction ~= "Shot1EndAlt", "not before ARM_MAX")
step(A.ARM_MAX)
A.sync(ed, "Delgado", {life = 100, action = "Relax"})
assert(ed.ForceAction == "Shot1EndAlt", "closed: " .. tostring(ed.ForceAction))

-- 12. events of a power's twin do not run on a puppet (Rawlings' heal, ghost heal, Vlad's course; Church's spell), do for the rest
puppets.Rawlings, puppets.Church = true, true
Game = {GetEntity = function(n)
  return {Name = n, IsType = function(self, t) return n == "0FP_Church" and t == "FP" end}
end}
local ep = body("Rawlings")
A.sync(ep, "Rawlings", {life = 100, action = "Relax"})     -- (the guard is put on every frame)
WeaponsRawlings.OnShotHeal("Rawlings", "CureGuy", 40)
Rawlings.GhostHealShot("Rawlings")
WeaponsRawlings.OnDoVladsCourse("Rawlings")
Church.LoseLifeCutting("Church")
assert(#evCalls == 0, "dropped on puppets: " .. table.concat(evCalls, ","))
Church.LoseLifeCutting("0FP_Church")                       -- the owner's own first-person arms
WeaponsRawlings.OnShotHeal("Black")                        -- a body that is not a puppet (the local player's, the host's AI)
assert(#evCalls == 2 and evCalls[1] == "spell 0FP_Church" and evCalls[2] == "heal Black", "run for the rest: " .. table.concat(evCalls, ","))
local wrappedHeal = WeaponsRawlings.OnShotHeal
A.sync(ep, "Rawlings", {life = 100, action = "Relax"})
assert(WeaponsRawlings.OnShotHeal == wrappedHeal, "wrapped once")
-- the script table is built again (a player takes the character): wrapped again
Rawlings = {GhostHealShot = function(n) evCalls[#evCalls + 1] = "ghost " .. tostring(n) end}
A.sync(ep, "Rawlings", {life = 100, action = "Relax"})
Rawlings.GhostHealShot("Rawlings")
assert(#evCalls == 2, "a rebuilt table is guarded again")
Coop.cfg.puppetevents = true
Rawlings.GhostHealShot("Rawlings")
assert(#evCalls == 3, "cfg.puppetevents=true: the old behaviour")
Coop.cfg.puppetevents = nil

print("anim mock test: OK")
