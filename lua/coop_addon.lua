-- SMOD Add-ons next to co-op.
--
-- "SMOD Add-ons" (nexusmods.com/clivebarkersjericho/mods/11, by PHM2D) is a set of loose scripts on top of SMOD (by SkacikPL): a third
-- person view (keys P / O: owc.UseFPS = 0), third-person versions of the squad's powers, a jump, sprint and dodge layouts, revive
-- cooldowns, other balance numbers, AI patches... This file is the co-op side of it; the analysis (what the add-ons change, which of
-- ours it touches, decisions, the live test plan) is notes/smod-addons11-analysis.md. The add-ons' files are never shipped or
-- copied by this mod: it works on the player's own installed ones, and finds them at run time.
--
-- Credit: SkacikPL (SMOD), PHM2D (SMOD Add-ons). Their authors allowed this mod to be made compatible with theirs and to borrow ideas
-- (relayed by the project owner, 2026-10-31); everything here is written for this mod.
--
-- What this does:
--   * Finds the add-ons (Ad.present, Ad.markers) and tells the lobby ("[SMOD+]" next to a player, coop_menu.lua).
--   * The third-person toggle (_G.ToggleFPSView, _G.SwitchViewOTS) is refused where the mod needs the first-person view: split screen
--     (both halves are built for first-person arms), a scene (own-eyes cutscenes put the camera at the body's eyes), a downed player
--     (the spectator camera), a camera that is not the body's own. A player in third person when one of these begins is put back
--     into first person, by the add-ons' own toggle so that its camera distance and field of view are restored too.
--   * In a session the add-ons' slow motions (Jones near death, the astral camera) are off, like SMOD's squad-menu slow motion
--     (coop_smod.lua): they would slow one machine's world only. Its F8 "easy QTE" toggle is off too (the lobby decides the QTEs).
--   * The rest is in the other modules: the events of Rawlings' third-person curse are guarded on puppets (coop_anim.lua
--     PUPPET_EVENTS), the third-person actions a player in that view plays (Spell, TKHit, ShotH_GH, Special1, Shot1Init...) reach
--     the other machines as the body's action (CoopAnim.ONESHOT).
-- Switches (Coop.cfg): addontp = false (no third-person view in a session at all), addonslowmo = true (keep the add-ons' slow motions),
-- addonqte = true (keep the F8 toggle).

local Ad = {}
CoopAddon = Ad
local cfg = Coop.cfg

-- What marks the add-ons at run time (global names their scripts define; none of them exists in the game or in SMOD 1.0.3).
Ad.MARKERS = {
  {"view", function() return type(rawget(_G, "SwitchViewOTS")) == "function" or type(rawget(_G, "ToggleFPSView")) == "function" end},
  {"revive", function() return Team ~= nil and Team.ReviveCooldownTime ~= nil end},
  {"aipatch", function() return type(rawget(_G, "AIPatch")) == "table" end},
  {"gait", function() return type(rawget(_G, "GaitToggle")) == "table" end},
  {"recoil", function() return type(rawget(_G, "RecoilKick")) == "table" end},
}

function Ad.markers()
  local out = {}
  for _, m in ipairs(Ad.MARKERS) do
    local ok, v = pcall(m[2])
    if ok and v then out[#out + 1] = m[1] end
  end
  return out
end

-- The view toggle or the revive cooldown is enough: they exist in every version of the add-ons (1.1, 2026-10-16, and later ones are
-- expected to keep them; a version that renames them is found by the other markers).
function Ad.present()
  return #Ad.markers() > 0
end

------------------------------------------------------------------------------
-- Third-person view
------------------------------------------------------------------------------

Ad.tpOn = false      -- this machine's player is in third person through the add-ons' toggle
Ad.tpFn = nil        -- the add-ons' own toggle function that did it (the way back)
Ad.wrapped = {}
Ad.refused = 0

local function userBody()
  local ok, u = pcall(Game.UsrEntity, 0)
  return ok and u or nil
end

local function useFPS(u)
  local ok, v = pcall(function() return u.owc.UseFPS end)
  return ok and tonumber(v) or nil
end

-- Why the first-person view is needed now (nil: third person is fine).
function Ad.blocked()
  if cfg.addontp == false and Coop.inSession() then return "off" end
  if CoopSplit and CoopSplit.on then return "split screen" end
  if Scene and Scene.IsPlaying then return "scene" end
  local u = userBody()
  if not u or u.oActCtrl == nil then return "no body" end
  if (u.Life or 0) <= 0 then return "downed" end
  local ok, cam = pcall(Game.GetCam, 0)
  if ok and cam ~= "MainCam" then return "camera " .. tostring(cam) end
  return nil
end

-- Wrap one of the add-ons' toggles (defined in autoexec.lua, which runs again several times a level: looked at every few frames).
function Ad.wrapToggle(name)
  local f = rawget(_G, name)
  if type(f) ~= "function" or Ad.wrapped[name] == f then return end
  local w = function(...)
    local u = userBody()
    local fps = u and useFPS(u)
    if fps ~= nil and fps ~= 0 then   -- first person now: this press goes to third person
      local why = Ad.blocked()
      if why then
        Ad.refused = Ad.refused + 1
        if Ad.refused <= 5 or cfg.animlog then Coop.log("addon: third person refused (" .. why .. ")") end
        return
      end
    end
    local r = {f(...)}
    local u2 = userBody()
    local now = u2 and useFPS(u2)
    Ad.tpOn = now == 0
    Ad.tpFn = Ad.tpOn and f or nil
    return unpack(r)
  end
  Ad.wrapped[name] = w
  rawset(_G, name, w)
end

-- Back into first person (by the add-ons' own toggle when it did the switch: its camera distance and field of view come back too).
function Ad.forceFP(why)
  local u = userBody()
  Ad.tpOn = false
  local fn = Ad.tpFn
  Ad.tpFn = nil
  if not u or useFPS(u) ~= 0 then return end
  if fn then pcall(fn) end
  u = userBody()
  if u and useFPS(u) == 0 then pcall(function() u.owc.UseFPS = 1 end) end
  Coop.log("addon: third person left (" .. tostring(why) .. ")")
end

-- Every frame while the player is in third person; a body switch resets it by itself (the game's switch sets InCtrl_UseFPS = 1).
function Ad.checkView()
  if not Ad.tpOn then return end
  local u = userBody()
  if not u or useFPS(u) ~= 0 then Ad.tpOn, Ad.tpFn = false, nil return end
  local why = Ad.blocked()
  if why then Ad.forceFP(why) end
end

------------------------------------------------------------------------------
-- Session rules
------------------------------------------------------------------------------

-- Slow motion the add-ons add: Game.SetTimeSpeed from autoexec.lua (Jones near death) and from AstralCamera.Start. The mod's hook
-- (coop_team.lua installTime) treats a call from those files as the machine's own: on the host it slows the simulation for all, on a
-- client the player's own world only, which then runs apart from the host's. Off in a session (like the squad menu's, coop_smod.lua).
function Ad.applyRules()
  if not Coop.inSession() or Coop.level == "levels/menu" then return end
  if cfg.addonslowmo ~= true then
    if rawget(_G, "JONESDEATHSLOWMO") then
      _G.JONESDEATHSLOWMO = false
      local js = rawget(_G, "JonesSlowMo")
      if type(js) == "table" and js.Active and type(js.Deactivate) == "function" then pcall(js.Deactivate, userBody()) end
      Coop.log("addon: Jones' near-death slow motion off for the session")
    end
    if AstralCamera and type(AstralCamera.SlowMoFactor) == "number" and AstralCamera.SlowMoFactor ~= 1 then
      AstralCamera.SlowMoFactor = 1
      Coop.log("addon: astral slow motion off for the session")
    end
  end
end

-- F8 (autoexec.lua ToggleEasyQTE) sets this machine's QTEMode to "always win" and back: the QTEs of a session follow the lobby.
function Ad.wrapQTE()
  local f = rawget(_G, "ToggleEasyQTE")
  if type(f) ~= "function" or Ad.wrapped.ToggleEasyQTE == f then return end
  local w = function(...)
    if Coop.inSession() and Coop.level ~= "levels/menu" and cfg.addonqte ~= true then
      Ad.qteRefused = (Ad.qteRefused or 0) + 1
      if Ad.qteRefused <= 3 then Coop.log("addon: the easy-QTE toggle is off in a session (the lobby's QTE setting rules)") end
      return
    end
    return f(...)
  end
  Ad.wrapped.ToggleEasyQTE = w
  rawset(_G, "ToggleEasyQTE", w)
end

------------------------------------------------------------------------------

function Ad.install()
  if not Ad.present() then return end
  if not Ad.logged then
    Ad.logged = true
    Coop.log("SMOD add-ons found: " .. table.concat(Ad.markers(), ",") .. " (SMOD " .. tostring(rawget(_G, "SMODVERSION")) .. ")")
  end
  Ad.wrapToggle("ToggleFPSView")
  Ad.wrapToggle("SwitchViewOTS")
  Ad.wrapQTE()
end

-- From Coop.update, every frame.
function Ad.update()
  if Ad.tpOn then
    local ok, err = pcall(Ad.checkView)
    if not ok and not Ad.viewError then Ad.viewError = true Coop.log("addon view error: " .. tostring(err)) end
  end
  Ad.frame = (Ad.frame or 0) + 1
  if Ad.frame % 15 ~= 0 then return end
  local ok, err = pcall(function()
    Ad.install()
    if Ad.present() then Ad.applyRules() end
  end)
  if not ok and not Ad.error then Ad.error = true Coop.log("addon error: " .. tostring(err)) end
end

local ok, err = pcall(Ad.install)
if not ok then Coop.log("addon error: " .. tostring(err)) end
