-- Offline check of coop_addon.lua (SMOD Add-ons next to co-op): detection, the third-person toggle guard, session rules.
-- Run: lua tests/addon_mock_test.lua  (from mod/lua)
local logs = {}
local session = false
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end, level = "levels/alk_city"}
Coop.inSession = function() return session end
local u = {Name = "Cole", Life = 50, oActCtrl = {}, owc = {UseFPS = 1}}
local cam = "MainCam"
Game = {UsrEntity = function() return u end, GetCam = function() return cam end}

dofile("coop_addon.lua")
local Ad = CoopAddon

-- 1. without the add-ons nothing is found and nothing is touched
assert(not Ad.present() and #Ad.markers() == 0)
Ad.update()
assert(rawget(_G, "ToggleFPSView") == nil)

-- 2. with them (the globals their autoexec.lua defines): found by the markers, toggles wrapped
local calls = 0
_G.ToggleFPSView = function()
  calls = calls + 1
  u.owc.UseFPS = (u.owc.UseFPS ~= 0) and 0 or 1
end
local origCls = {CamDist = 75}
_G.SwitchViewOTS = function()
  calls = calls + 1
  if u.owc.UseFPS ~= 0 then u.owc.UseFPS = 0; origCls.CamDist = 300 else u.owc.UseFPS = 1; origCls.CamDist = 75 end
end
Team = {ReviveCooldownTime = 30}
assert(Ad.present())
local m = table.concat(Ad.markers(), ",")
assert(string.find(m, "view") and string.find(m, "revive"), m)
Ad.install()
assert(_G.ToggleFPSView ~= nil and Ad.wrapped.ToggleFPSView == _G.ToggleFPSView, "wrapped")
local w1 = _G.ToggleFPSView
Ad.install()
assert(_G.ToggleFPSView == w1, "wrapped once")

-- 3. third person where it is fine; back again; tracked
_G.ToggleFPSView()
assert(u.owc.UseFPS == 0 and Ad.tpOn and calls == 1, "to third person")
_G.ToggleFPSView()
assert(u.owc.UseFPS == 1 and not Ad.tpOn and calls == 2, "and back")

-- 4. refused where the first-person view is needed (the toggle itself is not called)
local function refused(why, setup, undo)
  setup()
  local before = calls
  _G.ToggleFPSView()
  assert(u.owc.UseFPS == 1 and calls == before, "refused: " .. why)
  undo()
end
CoopSplit = {on = true}
refused("split screen", function() end, function() CoopSplit = nil end)
Scene = {IsPlaying = true}
refused("scene", function() end, function() Scene = {IsPlaying = false} end)
refused("downed", function() u.Life = 0 end, function() u.Life = 50 end)
refused("camera", function() cam = "AstralCam" end, function() cam = "MainCam" end)
refused("no body", function() u.oActCtrl = nil end, function() u.oActCtrl = {} end)
session = true
Coop.cfg.addontp = false
refused("switched off in a session", function() end, function() Coop.cfg.addontp = nil end)
session = false
Coop.cfg.addontp = false
_G.ToggleFPSView(); assert(u.owc.UseFPS == 0, "the switch rules a session only"); _G.ToggleFPSView()
Coop.cfg.addontp = nil
assert(Ad.refused >= 6)

-- 5. in third person when a scene begins: back by the add-ons' own toggle (its camera distance comes back), within a frame
_G.SwitchViewOTS()
assert(u.owc.UseFPS == 0 and Ad.tpOn and origCls.CamDist == 300)
Scene = {IsPlaying = true}
Ad.update()
assert(u.owc.UseFPS == 1 and not Ad.tpOn and origCls.CamDist == 75, "put back with the add-ons' own toggle: " .. origCls.CamDist)
Scene = {IsPlaying = false}
-- the same for a split screen that starts, and a downed player
_G.ToggleFPSView()
CoopSplit = {on = true}
Ad.update()
assert(u.owc.UseFPS == 1, "split screen starts: first person")
CoopSplit = nil
_G.ToggleFPSView(); u.Life = 0
Ad.update()
assert(u.owc.UseFPS == 1, "downed: first person"); u.Life = 50
-- a body switch resets the game's own flag: tracked off, nothing forced
_G.ToggleFPSView()
u.owc.UseFPS = 1
Ad.update()
assert(not Ad.tpOn)
-- the toggle redefined by a later autoexec.lua run: wrapped again
_G.ToggleFPSView = function() calls = calls + 100 end
Ad.frame = 14
Ad.update()
assert(Ad.wrapped.ToggleFPSView == _G.ToggleFPSView and _G.ToggleFPSView ~= w1, "re-wrapped after autoexec")

-- 6. session rules: slow motions off, the F8 toggle off; outside a session left alone
_G.JONESDEATHSLOWMO = true
AstralCamera = {SlowMoFactor = 0.35}
local deact = 0
_G.JonesSlowMo = {Active = true, Deactivate = function() deact = deact + 1 end}
local qte = 0
_G.ToggleEasyQTE = function() qte = qte + 1 end
Ad.frame = 14; Ad.update()
assert(_G.JONESDEATHSLOWMO == true and AstralCamera.SlowMoFactor == 0.35, "no session: untouched")
_G.ToggleEasyQTE(); assert(qte == 1, "outside a session the toggle works")
session = true
Ad.frame = 14; Ad.update()
assert(_G.JONESDEATHSLOWMO == false and AstralCamera.SlowMoFactor == 1 and deact == 1, "session: slow motions off")
_G.ToggleEasyQTE(); assert(qte == 1, "session: no easy QTE")
Coop.cfg.addonqte = true
_G.ToggleEasyQTE(); assert(qte == 2, "cfg.addonqte: kept")
Coop.cfg.addonqte = nil
Coop.cfg.addonslowmo = true
_G.JONESDEATHSLOWMO = true; AstralCamera.SlowMoFactor = 0.35
Ad.frame = 14; Ad.update()
assert(_G.JONESDEATHSLOWMO == true and AstralCamera.SlowMoFactor == 0.35, "cfg.addonslowmo: kept")
-- the menu level of a session: untouched
Coop.cfg.addonslowmo = nil
Coop.level = "levels/menu"
Ad.frame = 14; Ad.update()
assert(_G.JONESDEATHSLOWMO == true, "menu level")

print("addon mock test: OK")
