-- SMOD (SkacikPL's mod pack, loose scripts + autoexec.lua) next to co-op.
--
-- Found at run time (one build for both). What it changes and why it matters here is in
-- work\smod-analysis.md; in short:
--   * Its new texts are hard-coded English: shown in the game's language here (menu
--     labels in the option tables themselves, since debug entries find their action by
--     matching the item's text with the table).
--   * In a session every machine plays by the same rules: SMOD's damage/health
--     multipliers, ironman, the checkpoint heal, slow motion in the squad menu, its pause
--     and time scale, and the debug/cheat menus of the pause menu would give each player
--     their own rules or stop the world for everyone. They are set to the game's own
--     values (its looks - FOV, lights, flashlight, crosshair, recoil - and jump stay).
--   * Its Weapons.DoDamage wrapper drops the result (explosions never blow bodies apart)
--     and errors on head hits without a body multiplier: in a session the game's own runs.

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

-- The game's own values for what SMOD's autoexec.lua sets.
Sm.VANILLA = {
  DAMAGEMULTIPLIER = 1, HEADSHOTMULTIPLIER = 1, AISQUADDAMAGERECEIVEDMULT = 1,
  HEALTHMULTIPLIER = 1, IRONMAN = false, TEAMMENUSLOWMO = false,
}

function Sm.applyRules()
  for k, v in pairs(Sm.VANILLA) do
    if _G[k] ~= nil then _G[k] = v end
  end
  if Weapons then
    Weapons.DamageMultiplier, Weapons.ExplosiveMultiplier = 1, 1
    Weapons.MeleeDamageMultiplier, Weapons.PlayerMeleeMultiplier = 1, 1
    -- The game's own damage, with its result (SMOD's wrapper returns nothing).
    if Weapons.DoDamageOrig and not Sm.damageFixed then
      Sm.damageFixed = true
      Weapons.DoDamage = function(...) return Weapons.DoDamageOrig(...) end
    end
  end
  if Team and Team.SetMaxHealth and not Sm.healFixed then
    Sm.healFixed = true
    Team.SetMaxHealth = function() end   -- no checkpoint heal (the host's only)
  end
  -- Squad health: SquadCfg took HEALTHMULTIPLIER when the level loaded.
  local mult = Sm.loadedHealth
  if mult and mult ~= 1 and not Sm.healthFixed and Act and Act.GetClass then
    Sm.healthFixed = true
    for _, name in ipairs(Coop.SQUAD) do
      local cls = Act.GetClass(name)
      if cls and cls.Life then
        cls.Life = cls.Life / mult
        local e = Game.GetEntity(name)
        if e and e.Life and e.Life > cls.Life then e.Life = cls.Life end
      end
    end
    Coop.log("SMOD: squad health back to the game's own (x" .. mult .. " undone)")
  end
end

function Sm.installRules()
  if Sm.rulesInstalled then return end
  Sm.rulesInstalled = true
  Sm.loadedHealth = _G.HEALTHMULTIPLIER
  Sm.applyRules()
  -- autoexec.lua runs again during the level (and on the next load): rules again after it.
  local origDofile = dofile
  _G.dofile = function(path, ...)
    local r = {origDofile(path, ...)}
    if type(path) == "string" and string.find(string.lower(path), "autoexec") then
      local ok, err = pcall(Sm.applyRules)
      if not ok then Coop.log("smod rules error: " .. tostring(err)) end
    end
    return unpack(r)
  end
  -- SMOD's pause and time scale would stop or speed the world for everyone.
  if QuickConsole then
    for _, fn in ipairs({"pause", "actionpause", "timescale"}) do
      if QuickConsole[fn] then QuickConsole[fn] = function() Coop.log("SMOD: " .. fn .. " is off in a session") end end
    end
  end
  Coop.log("SMOD found: the game's own rules for the session")
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
