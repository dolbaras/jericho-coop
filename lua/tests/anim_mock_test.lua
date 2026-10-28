-- Offline check of coop_anim.lua (downed puppets fall, one revive, one-shots) with stub engine tables.
-- Run: lua tests/anim_mock_test.lua  (from mod/lua)
local clock = 100
local logs = {}
Net = {CoopTime = function() return clock end}
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end}
local revFn = {}
Team = {AssignReviveFunction = function(e) e.ArrowCanUse = 1 end,
        RemoveReviveFunction = function(e) e.ArrowCanUse = 0 end}
local ACTS = {Agony = 1, AgonyInit = 1, AgonyEnd = 1, Agony2 = 1, Agony2Init = 1, Agony2End = 1, HitStrong = 1, Hit = 1,
              Reload = 1, Relax = 1, Run = 1}
Act = {GetClass = function(n) return {GetAct = function(self, a) return ACTS[a] and {} or nil end} end}

dofile("coop_anim.lua")
local A = CoopAnim

local function body(name) return {Name = name, ActCtrl = "", Life = 100, Action = "Relax", Invulnerable = 0} end
local function step(dt) clock = clock + dt end

-- 1. the owner is down: the puppet (Life already 0, standing) goes into agony, once, with its variant
local e = body("Church"); e.Life = 0
local st = {life = 0, action = "Agony2"}
A.sync(e, "Church", st)
assert(e.Action == "Agony2Init" and e.DefLoop == "Agony2", "variant of the owner: " .. tostring(e.Action))
assert(e.ArrowCanUse == 1, "revive function")
e.Action = "Agony2"                        -- the init action ran into its loop
A.sync(e, "Church", st); step(1); A.sync(e, "Church", st)
assert(e.Action == "Agony2" and A.downs == 1, "not put down again")

-- 2. the engine killed it itself: left alone
local e2 = body("Black"); e2.Life = 0; e2.Action = "AgonyInit"
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

print("anim mock test: OK")
