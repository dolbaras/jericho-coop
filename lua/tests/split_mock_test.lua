-- Offline checks of coop_split.lua (tester report 2026-11-06): the first-person models' ids while
-- player 2's code runs (Sp.withRealIds inside Sp.asUser1), and player 2's HUD following the game's
-- HUD switches (Menu.bShowAim/bShowAmmo/bShowTeamStatus, the desert's tutorial).
-- Run: lua tests/split_mock_test.lua  (from mod/lua)
local logs = {}
local function V(x, y) return {x = x, y = y} end
V2D = V
local ents = {}
local function ent(name, t) t.Name = name ents[name] = t return t end
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end, SQUAD = {"Black", "Church"}, frame = 0, storyDriven = {},
        inSession = function() return true end, isHost = function() return true end, isClient = function() return false end}
local cams = {[0] = "MainCam", [1] = "CoopCam1"}
Game = {
  UsrEntity = function(i) if i == 0 then return ents.Black elseif i == 1 then return ents.Church end end,
  GetEntity = function(n) return ents[n] end,
  GetCam = function(i) return cams[i] end,
  SetCam = function(i, n) cams[i] = n end,
  AddScheduledFunc = function() end,
  GetTime = function() return 10 end,
  Get = function() return nil end,
  Set = function() end,
}
Input = {GetActionSet = function() return "Walk" end, SetActionSet = function() end, Rumble = function() end}
Net = {CoopKey = function() end, CoopTime = function() return 10 end}
-- scorer items per user
local items = {[0] = {}, [1] = {}}
Scorer = {
  Clear = function(id) items[id] = {} end,
  NewItem = function(id, name) local it = {Name = name} items[id][name] = it return it end,
  GetItem = function(id, name) return items[id] and items[id][name] end,
  SetMsgText = function() end,
}
-- the game's Menu.ShowScorer, as far as these switches go (scripts/menu/menu.lua)
Menu = {bShowAim = true, bShowAmmo = true, bShowTeamStatus = true}
function Menu.ShowScorer()
  Scorer.Clear(0)
  Scorer.NewItem(0, "Msg", "Msg")
  if Menu.bShowAmmo then Scorer.NewItem(0, "Ammo", "Ammo") end
  Scorer.NewItem(0, "Selector", "Selector")
  if Menu.bShowTeamStatus then Scorer.NewItem(0, "TeamStatus", "TeamStatus") end
  if Menu.bShowAim then Scorer.NewItem(0, "Aim", "Aim") end
end

dofile("coop_split.lua")
local Sp = CoopSplit

ent("Black", {UsrControl = 0, Life = 100})
ent("Church", {UsrControl = 1, Life = 100, IgnoreUsrControl = 0})
local f0 = ent("0FP_Black", {id = 3})   -- player 1's arms hidden from the view drawn next
local f1 = ent("1FP_Church", {id = 1})
ent("CoopCam1", {MainTarget = "Church"})
Sp.on, Sp.char, Sp.shownFor = true, "Church", 0

-- 1. Player 2's code sees the real ids of both models, the engine's lookups included; put back after.
local seen = {}
Sp.asUser1(function()
  seen.id0, seen.id1 = f0.id, f1.id
  seen.usr0 = Game.UsrEntity(0) and Game.UsrEntity(0).Name   -- (the remap is on: player 2's)
end)
assert(seen.usr0 == "Church", "remap on inside: " .. tostring(seen.usr0))
assert(seen.id0 == 0, "player 1's model has id 0 inside: " .. tostring(seen.id0))
assert(seen.id1 == 1, "player 2's model has id 1 inside: " .. tostring(seen.id1))
assert(f0.id == 3 and f1.id == 1, "ids put back: " .. tostring(f0.id) .. " " .. tostring(f1.id))
-- the other frame (player 2's model hidden)
f0.id, f1.id = 0, 3
Sp.asUser1(function() seen.id0, seen.id1 = f0.id, f1.id end)
assert(seen.id0 == 0 and seen.id1 == 1, "second frame inside: " .. tostring(seen.id0) .. " " .. tostring(seen.id1))
assert(f0.id == 0 and f1.id == 3, "second frame put back")
-- player 1's code (no remap) as before
f0.id, f1.id = 3, 1
assert(Sp.withRealIds(function() return f0.id * 10 + f1.id end) == 1, "player 1's code: ids 0 and 1")
assert(f0.id == 3 and f1.id == 1, "player 1's code: put back")
-- the old behaviour (cfg.splitidfix = false): player 2's model was taken for player 1's
Coop.cfg.splitidfix = false
Sp.asUser1(function() seen.id0, seen.id1 = f0.id, f1.id end)
assert(seen.id1 == 0 and seen.id0 == 3, "old behaviour reproduced: " .. tostring(seen.id0) .. " " .. tostring(seen.id1))
Coop.cfg.splitidfix = nil
assert(f0.id == 3 and f1.id == 1, "old behaviour: put back")

-- 2. Player 2's HUD follows the game's switches (the desert starts with them off).
Menu.bShowAim, Menu.bShowAmmo, Menu.bShowTeamStatus = false, false, false
Sp.shownFor = nil
Sp.buildHud()
assert(Scorer.GetItem(1, "Selector") and not Scorer.GetItem(1, "Aim") and not Scorer.GetItem(1, "Ammo"), "built without aim and ammo")
assert(not Scorer.GetItem(0, "Selector"), "scorer 0 untouched")
local n = #logs
Sp.checkHud()
assert(#logs == n, "nothing changed: no rebuild")
Menu.bShowAim, Menu.bShowAmmo = true, true   -- MapInit.TestTap: Menu.ShowScorer(0) for user 0 only
Sp.checkHud()
assert(Scorer.GetItem(1, "Aim") and Scorer.GetItem(1, "Ammo") and not Scorer.GetItem(1, "TeamStatus"), "rebuilt with aim and ammo")
assert(string.find(logs[#logs], "built again", 1, true), "logged: " .. tostring(logs[#logs]))
-- not while player 2's camera is a power's (the ghost bullet...): later
Menu.bShowTeamStatus = true
cams[1] = "GhostBulletCam"
Sp.checkHud()
assert(not Scorer.GetItem(1, "TeamStatus"), "no rebuild while another camera is player 2's")
cams[1] = "CoopCam1"
Sp.checkHud()
assert(Scorer.GetItem(1, "TeamStatus"), "rebuilt once the camera is back")
-- a lost HUD (no Selector) comes back as before
Scorer.Clear(1)
Sp.checkHud()
assert(Scorer.GetItem(1, "Selector") and string.find(logs[#logs], "HUD back", 1, true), "HUD back: " .. tostring(logs[#logs]))

-- 3. A switch puts the new body into its rest action, as the game's own switch does for user 0
-- (team.lua SwitchSoldier -> Team.ResetUsrAnim); not a revive in the same body; off with the switch.
local resets = {}
Team = {ResetUsrAnim = function(t) resets[#resets + 1] = t.Name t.ForceAction = "Relax" end}
ent("Rawlings", {UsrControl = -1, Life = 100, Action = "ShelterDown", oAI = {bEnable = true}})
ent("Cole", {UsrControl = -1, Life = 100, Action = "Combo1Hit1", oAI = {bEnable = true}})
ents.Church.oAI = {bEnable = false}
assert(Sp.takeBody("Rawlings", "Church"), "switch")
assert(ents.Rawlings.ForceAction == "Relax" and resets[1] == "Rawlings", "rest action: " .. tostring(ents.Rawlings.ForceAction))
assert(ents.Rawlings.UsrControl == 1 and ents.Rawlings.oAI.bEnable == false, "taken")
assert(ents.Church.UsrControl == -1 and ents.Church.oAI.bEnable == true, "left")
resets = {}
assert(Sp.takeBody("Rawlings"), "same body")
assert(#resets == 0, "a revive in the same body keeps its getting up")
Coop.cfg.p2resetanim = false
assert(Sp.takeBody("Cole", "Rawlings"), "switch, reset off")
assert(#resets == 0 and ents.Cole.ForceAction == nil, "cfg.p2resetanim = false: as before")
Coop.cfg.p2resetanim = nil

print("split_mock_test: all passed")
