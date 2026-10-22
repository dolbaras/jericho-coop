-- SMOD (SkacikPL's mod pack, loose scripts + autoexec.lua) next to co-op.
--
-- Found at run time (one build for both). What it changes and why it matters here is in
-- the private notes (games\jericho\notes\smod-analysis.md); in short:
--   * Its new texts are hard-coded English: shown in the game's language here (menu
--     labels in the option tables themselves, since debug entries find their action by
--     matching the item's text with the table).
--   * In a session every machine plays by the same rules: the host's SMOD values (damage,
--     head hits, AI squadmates' damage, health, ironman, checkpoint heal) when every player
--     has SMOD and the host keeps them on, else the game's own (Sm.applyRules). Slow motion
--     in the squad menu, its pause and time scale, and the debug/cheat menus of the pause
--     menu stay off: they would stop the world for everyone or act on one machine only.
--     Its looks (FOV, lights, flashlight, crosshair, recoil) are each player's own.
--   * Its jump is shown on the other machines (jump|...), see Sm.installJump.
--   * Its Weapons.DoDamage wrapper drops the result (explosions never blow bodies apart)
--     and errors on head hits without a body multiplier: in a session the game's own runs,
--     with head hits from Sm.headshot.

local Sm = {}
CoopSmod = Sm
local cfg = Coop.cfg

function Sm.present()
  return _G.FOVOVERRIDE ~= nil or (Weapons ~= nil and Weapons.DoDamageOrig ~= nil)
end

------------------------------------------------------------------------------
-- Texts
------------------------------------------------------------------------------

-- en -> ru (UTF-8 here, cp1251 on screen).
Sm.RU = {
  ["Cheats"] = "Читы",
  ["Quick debug"] = "Быстрая отладка",
  ["Debug"] = "Отладка",
  ["Debug Menu"] = "Меню отладки",
  ["Change Level"] = "Сменить уровень",
  ["PAUSED"] = "ПАУЗА",
  ["SMOD by SkacikPL\nhttps://www.skacikpl.pl"] = "SMOD от SkacikPL\nhttps://www.skacikpl.pl",
  ["Created by SkacikPL"] = "Автор: SkacikPL",
  ["About SMOD"] = "О SMOD",
  ["Queue screenshot in one second"] = "Снимок экрана через секунду",
  ["Toggle third person"] = "Вид от третьего лица",
  ["All God Mode"] = "Бессмертие всем",
  ["Reequip"] = "Перевооружить",
  ["Free"] = "Свободная камера",
  ["Render Info"] = "Инфо рендера",
  ["Shadows"] = "Тени",
  ["QTE status"] = "Режим QTE",
  ["Particle FX"] = "Частицы",
  ["Game Version"] = "Версия игры",
  ["Quad Damage"] = "Четверной урон",
  ["Unlock Historic"] = "Открыть главы",
  ["Unlock Pictures"] = "Открыть арт",
  ["Hide Scorer"] = "Скрыть HUD",
  ["All Bonus Codes"] = "Все коды бонусов",
  ["Kill All"] = "Убить всех",
  ["Debug Level"] = "Отладочный уровень",
  ["Console"] = "Консоль",
}

function Sm.ru()
  return Coop.lang and Coop.lang() == "ru"
end

function Sm.tr(s)
  if type(s) ~= "string" or not Sm.ru() then return s end
  local t = Sm.RU[s]
  return t and Coop.cp1251(t) or s
end

-- Option tables the debug menus are built from (translated in place, once per level).
function Sm.translateTables()
  if not Sm.ru() or not Menu then return end
  for _, list in ipairs({Menu.LoDebugOptions, Menu.DebugOptionsInt}) do
    if type(list) == "table" and not list.coopTr then
      list.coopTr = true
      for _, o in ipairs(list) do
        if type(o) == "table" then o[1] = Sm.tr(o[1]) end
      end
    end
  end
end

-- Menu entries SMOD adds to the main and pause menus, by their action.
Sm.ENTRY = {["MainMenu.StartBonusCodes"] = "Cheats", ["Menu.LoDebugMenu"] = "Quick debug", ["Menu.DebugMenuInt"] = "Debug"}

function Sm.installMenus()
  if Sm.menusInstalled or not Menu or not Menu.VerticalMenu then return end
  Sm.menusInstalled = true
  local origVertical = Menu.VerticalMenu
  Menu.VerticalMenu = function(title, options, ...)
    Sm.translateTables()
    if type(options) == "table" then
      local kept = {}
      for _, o in ipairs(options) do
        local en = type(o) == "table" and Sm.ENTRY[o[2]]
        -- In a game of the session no cheats or debug: they act on one machine only.
        if not (en and Coop.inSession() and Coop.level ~= "levels/menu") then
          if en and o[1] == en then o[1] = Sm.tr(en) end
          kept[#kept + 1] = o
        end
      end
      if #kept ~= #options then
        for i = #options, 1, -1 do options[i] = nil end
        for i, o in ipairs(kept) do options[i] = o end
      end
    end
    local r = {origVertical(Sm.tr(title), options, ...)}
    -- SMOD's menus leave the game's "Paused" label up in the main menu.
    if Coop.level == "levels/menu" then
      local p = Scorer.GetItem(0, "FuckingPaused")
      if p then p.Visible = 0 end
    end
    return unpack(r)
  end
  if Scorer and Scorer.PopUpMessage then
    local origPop = Scorer.PopUpMessage
    Scorer.PopUpMessage = function(id, x, y, text, ...)
      return origPop(id, x, y, Sm.tr(text), ...)
    end
  end
end

------------------------------------------------------------------------------
-- Session rules
------------------------------------------------------------------------------

-- What SMOD's autoexec.lua sets that changes the game's rules. A session plays by one set of
-- values on every machine: the host's SMOD values when every player has SMOD and the host
-- chose so (cfg.smod, sent with the lobby's start), else the game's own.
--   dmg  DAMAGEMULTIPLIER           squad weapon and melee damage (Weapons.*Multiplier)
--   hs   HEADSHOTMULTIPLIER         head hits (body-part exponent; see Sm.headshot)
--   ai   AISQUADDAMAGERECEIVEDMULT  damage AI squadmates take (applied by the host)
--   hp   HEALTHMULTIPLIER           squad health (SquadCfg)
--   iron IRONMAN                    no health regeneration (but Rawlings)
-- The checkpoint heal comes with SMOD's rules; squad-menu slow motion, SMOD's pause and
-- time scale stay off in every session (they would stop or slow the world for everyone).
Sm.VANILLA = {dmg = 1, hs = 1, ai = 1, hp = 1, iron = false}

-- This machine's own SMOD values (in the menu, before any session rules).
function Sm.ownValues()
  return {dmg = tonumber(_G.DAMAGEMULTIPLIER) or 1, hs = tonumber(_G.HEADSHOTMULTIPLIER) or 1,
          ai = tonumber(_G.AISQUADDAMAGERECEIVEDMULT) or 1, hp = tonumber(_G.HEALTHMULTIPLIER) or 1,
          iron = _G.IRONMAN == true}
end

function Sm.encode(v)
  return string.format("%g,%g,%g,%g,%d", v.dmg, v.hs, v.ai, v.hp, v.iron and 1 or 0)
end

function Sm.decode(s)
  local d, h, a, p, i = string.match(tostring(s or ""), "^([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+),([01])$")
  if not d then return nil end
  return {dmg = tonumber(d), hs = tonumber(h), ai = tonumber(a), hp = tonumber(p), iron = i == "1"}
end

-- The session's SMOD rules, or nil for the game's own.
function Sm.rules()
  return Coop.inSession() and Sm.decode(cfg.smod) or nil
end

-- A head hit with a body multiplier: SMOD's multiplier on that exponent, for the part hit
-- now (SMOD's own wrapper read the previous hit's part and failed without a multiplier).
function Sm.headshot(To, From, BodyMultiplier)
  local r = Sm.rules()
  if not r or r.hs == 1 or BodyMultiplier == nil or not To or not To.SetLastBodyPiece then return BodyMultiplier end
  To:SetLastBodyPiece(From)
  local piece = To.oWeapHit and To.oWeapHit.oBodyPiece
  local part = piece and piece.oRagDollDamagePart
  if part and part.Name and string.find(string.lower(part.Name), "head") then
    return BodyMultiplier * r.hs
  end
  return BodyMultiplier
end

-- Regeneration as SquadCfg/the character scripts give it: none with ironman; Delgado gets
-- the common steps with SMOD (the game gives him the Easy step on every difficulty).
Sm.REGEN_CHARS = {"Jones", "Cole", "Delgado", "Church", "Black", "Ross"}

function Sm.setRegen(iron, smodRules)
  local c = SquadCfg and SquadCfg.Common
  if not c or not Act or not Act.GetClass then return end
  for _, name in ipairs(Sm.REGEN_CHARS) do
    local ac = Act.GetClass(name)
    if ac then
      if iron then
        ac.RegenStepEasy, ac.RegenStep, ac.RegenStepHard = math.huge, math.huge, math.huge
      elseif name == "Delgado" and not smodRules then
        ac.RegenStepEasy, ac.RegenStep, ac.RegenStepHard = c.RegenStepEasy, c.RegenStepEasy, c.RegenStepEasy
      else
        ac.RegenStepEasy, ac.RegenStep, ac.RegenStepHard = c.RegenStepEasy, c.RegenStep, c.RegenStepHard
      end
    end
  end
end

function Sm.applyRules()
  local r = Sm.rules() or Sm.VANILLA
  _G.DAMAGEMULTIPLIER, _G.HEADSHOTMULTIPLIER, _G.AISQUADDAMAGERECEIVEDMULT = r.dmg, r.hs, r.ai
  _G.HEALTHMULTIPLIER, _G.IRONMAN = r.hp, r.iron
  if _G.TEAMMENUSLOWMO ~= nil then _G.TEAMMENUSLOWMO = false end
  if Weapons then
    Weapons.DamageMultiplier, Weapons.ExplosiveMultiplier = r.dmg, r.dmg
    Weapons.MeleeDamageMultiplier, Weapons.PlayerMeleeMultiplier = r.dmg, r.dmg
    -- The game's own damage, with its result (SMOD's wrapper returns nothing); head hits
    -- and AI squadmates' damage are applied by coop_enemies.lua with Sm.headshot and r.ai.
    if Weapons.DoDamageOrig and not Sm.damageFixed then
      Sm.damageFixed = true
      Weapons.DoDamage = function(...) return Weapons.DoDamageOrig(...) end
    end
  end
  -- The checkpoint heal: SMOD's rules only. The host's checkpoint heals the bodies it runs;
  -- clients heal their own on the host's checkpoint message (coop_save.lua).
  if Team and Team.SetMaxHealth and not Sm.healOrig then Sm.healOrig = Team.SetMaxHealth end
  if Team and Sm.healOrig then
    Team.SetMaxHealth = function(...) if Sm.rules() then return Sm.healOrig(...) end end
  end
  -- Squad health: SquadCfg took this machine's HEALTHMULTIPLIER when the level loaded.
  local mult = Sm.loadedHealth or 1
  if mult ~= r.hp and not Sm.healthFixed and Act and Act.GetClass then
    Sm.healthFixed = true
    for _, name in ipairs(Coop.SQUAD) do
      local cls = Act.GetClass(name)
      if cls and cls.Life then
        cls.Life = cls.Life / mult * r.hp
        local e = Game.GetEntity(name)
        if e and e.Life and e.Life > cls.Life then e.Life = cls.Life end
      end
    end
    Coop.log(string.format("SMOD: squad health x%g (was x%g)", r.hp, mult))
  end
  Sm.setRegen(r.iron, Sm.rules() ~= nil)
end

-- Client on the host's checkpoint (SMOD's rules): its own body back to full health.
function Sm.checkpointHeal()
  if not Sm.rules() then return end
  local usr = Game.UsrEntity(0)
  local cls = usr and usr.oActCtrl and usr.oActCtrl.oActClass
  if cls and cls.Life and usr.Life > 0 then usr.Life = cls.Life end
end

------------------------------------------------------------------------------
-- Jump
------------------------------------------------------------------------------

-- SMOD's jump (_G.Jump, the walk/run key) only lifts this machine's body: the others see it
-- through jump|<char>|<vel.y>, which gives their copy of the body the same push. Any game
-- shows it (only the velocity is needed), with or without SMOD.
function Sm.installJump()
  -- autoexec.lua defines _G.Jump again each time it runs: wrapped again after it.
  if type(_G.Jump) ~= "function" or _G.Jump == Sm.jumpWrapper then return end
  local origJump = _G.Jump
  Sm.jumpWrapper = function(...)
    local usr = Game.UsrEntity(0)
    local before = usr and usr.Vel and usr.Vel.y or 0
    local r = {origJump(...)}
    local after = usr and usr.Vel and usr.Vel.y or 0
    if Coop.inSession() and usr and after > before + 100 then
      Net.CoopSend(Coop.isHost() and -1 or 0, 1, string.format("jump|%s|%.0f", usr.Name, after))
    end
    return unpack(r)
  end
  _G.Jump = Sm.jumpWrapper
end

function Sm.installRules()
  if Sm.rulesInstalled then return end
  Sm.rulesInstalled = true
  Sm.loadedHealth = tonumber(_G.HEALTHMULTIPLIER) or 1
  Sm.applyRules()
  Sm.installJump()
  -- autoexec.lua runs again during the level (and on the next load): rules again after it.
  local origDofile = dofile
  _G.dofile = function(path, ...)
    local r = {origDofile(path, ...)}
    if type(path) == "string" and string.find(string.lower(path), "autoexec") then
      local ok, err = pcall(Sm.applyRules)
      if not ok then Coop.log("smod rules error: " .. tostring(err)) end
      pcall(Sm.installJump)
    end
    return unpack(r)
  end
  -- SMOD's pause and time scale would stop or speed the world for everyone.
  if QuickConsole then
    for _, fn in ipairs({"pause", "actionpause", "timescale"}) do
      if QuickConsole[fn] then QuickConsole[fn] = function() Coop.log("SMOD: " .. fn .. " is off in a session") end end
    end
  end
  local r = Sm.rules()
  Coop.log("SMOD found: " .. (r and ("the host's SMOD rules " .. Sm.encode(r)) or "the game's own rules") .. " for the session")
end

-- Outside a session SMOD's own pause stays; its text in the game's language.
function Sm.installPauseText()
  if Sm.pauseInstalled or not QuickConsole or not QuickConsole.pause then return end
  Sm.pauseInstalled = true
  local orig = QuickConsole.pause
  QuickConsole.pause = function(...)
    local r = {orig(...)}
    local it = Scorer.GetItem(0, "PauseText")
    if it and it.Text == "PAUSED" then it.Text = Sm.tr("PAUSED") end
    return unpack(r)
  end
end

function Sm.install()
  if not Sm.present() then return end
  Sm.installMenus()
  Sm.translateTables()
  if Coop.inSession() and Coop.level ~= "levels/menu" then Sm.installRules() else Sm.installPauseText() end
end

local ok, err = pcall(Sm.install)
if not ok then Coop.log("smod error: " .. tostring(err)) end
