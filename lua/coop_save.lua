-- Jericho co-op: progress and checkpoints, kept apart from the player's single-player
-- profile (Documents\Codemasters\Clive Barker's Jericho\Profile.CBJericho).
--
-- The game keeps a level's progress in "save vars" (engine state that survives level
-- loads). Single player copies them into the profile (Game.SoftSaveAutoSave) and writes the
-- profile to disk (Game.HardSaveGame). In a session neither happens:
--   * checkpoints go to coop:checkpoint.txt, the start of each level to coop:save.txt
--     (native/coop_net.c, Net.CoopFile); "load checkpoint" reads them back;
--   * the profile is not written; config values the campaign changes (visited levels,
--     weapon modes, save slot markers) are snapshotted when the session starts and put back
--     when it ends, so single player continues exactly where it was;
--   * every level load the host starts carries its save vars to the clients ("sv|..."
--     before "level|..."), so a restart or a checkpoint is the same state everywhere;
--     "cp" tells the clients a checkpoint was reached.
--
-- File format (text, one record per line, fields separated by tabs, %XX escapes):
--   JCOOPSAVE  1
--   level      <LevelName>
--   weapons    <UsrWeaponConfig>
--   visited    <comma separated levels reached in co-op>
--   v          <s|n|b>  <name>  <value>        one save var

CoopSave = CoopSave or {}
local CS = CoopSave
local cfg = Coop.cfg

CS.SAVE = "coop:save.txt"
CS.CHECKPOINT = "coop:checkpoint.txt"
CS.PROGRESS = "coop:progress.txt"
-- Config values (Game.Get/Set) the campaign scripts change on the way.
CS.PROTECTED = {"VisitedLevels", "SaveSlotUsed", "SaveGameSlot", "UsrWeaponConfig", "GameSkill"}

local function esc(s)
  return (string.gsub(tostring(s), "[%%\t\n\r|]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function unesc(s)
  return (string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function split(line)
  local out = {}
  for x in string.gmatch(line .. "\t", "([^\t]*)\t") do out[#out + 1] = unesc(x) end
  return out
end

------------------------------------------------------------------------------
-- Save vars <-> text
------------------------------------------------------------------------------

function CS.encodeVars()
  local lines = {}
  local svo = Game.GetFirstVarObj()
  while svo ~= nil do
    local v = svo.Value
    local t = type(v) == "number" and "n" or type(v) == "boolean" and "b" or "s"
    if v ~= nil then lines[#lines + 1] = "v\t" .. t .. "\t" .. esc(svo.Name) .. "\t" .. esc(tostring(v)) end
    svo = svo.oNext
  end
  return lines
end

-- Replace the engine's save vars with the "v" records of a decoded file.
function CS.applyVars(rec)
  Game.DelSaveVars("")
  local n = 0
  for _, f in ipairs(rec.vars) do
    local t, name, value = f[1], f[2], f[3]
    Game.CreateSaveVar(name, "")
    local svo = Game.GetSaveVarObj(name)
    if svo then
      if t == "n" then svo.Value = tonumber(value) or 0
      elseif t == "b" then svo.Value = value == "true"
      else svo.Value = value end
      n = n + 1
    end
  end
  return n
end

function CS.encode(level)
  local lines = {"JCOOPSAVE\t1", "level\t" .. esc(level or Game.GetSaveVar("LevelName") or ""),
                 "weapons\t" .. esc(Game.Get("UsrWeaponConfig") or "")}
  for _, l in ipairs(CS.encodeVars()) do lines[#lines + 1] = l end
  return table.concat(lines, "\n")
end

function CS.decode(text)
  if not text or string.sub(text, 1, 9) ~= "JCOOPSAVE" then return nil end
  local rec = {vars = {}}
  for line in string.gmatch(text, "[^\n]+") do
    local f = split(line)
    if f[1] == "v" then rec.vars[#rec.vars + 1] = {f[2], f[3], f[4]}
    elseif f[1] == "level" then rec.level = f[2]
    elseif f[1] == "weapons" then rec.weapons = f[2] end
  end
  return rec
end

-- Load a decoded record into the engine (before Game.LoadLevel).
function CS.apply(rec)
  local n = CS.applyVars(rec)
  if rec.weapons and rec.weapons ~= "" then Game.Set("UsrWeaponConfig", rec.weapons) end
  if rec.level and rec.level ~= "" then Game.SetSaveVar("LevelName", rec.level) end
  Coop.log("save: applied " .. n .. " vars, level " .. tostring(rec.level))
end

function CS.write(file, level)
  if not Net.CoopFile then return false end
  local ok = Net.CoopFile(file, "w", CS.encode(level)) == 1
  Coop.log("save: wrote " .. file .. " level=" .. tostring(level) .. " ok=" .. tostring(ok))
  return ok
end

function CS.read(file)
  return Net.CoopFile and CS.decode(Net.CoopFile(file, "r")) or nil
end

------------------------------------------------------------------------------
-- Progress (levels reached in co-op, for the chapter list)
------------------------------------------------------------------------------

function CS.visited()
  local text = Net.CoopFile and Net.CoopFile(CS.PROGRESS, "r") or nil
  local list, set = {}, {}
  for line in string.gmatch(text or "", "[^\n]+") do
    local f = split(line)
    if f[1] == "visited" then
      for name in string.gmatch(f[2] or "", "[^,]+") do
        local k = string.lower(name)
        if not set[k] then set[k] = true list[#list + 1] = k end
      end
    end
  end
  return list, set
end

function CS.addVisited(level)
  if not Net.CoopFile or not level or string.lower(level) == "menu" then return end
  local list, set = CS.visited()
  local k = string.lower(level)
  if set[k] then return end
  list[#list + 1] = k
  Net.CoopFile(CS.PROGRESS, "w", "JCOOPSAVE\t1\nvisited\t" .. esc(table.concat(list, ",")))
end

------------------------------------------------------------------------------
-- Session start / end: protect the single-player profile
------------------------------------------------------------------------------

-- Called when a session starts (lobby launch, test start). Remembered in COOP_CFG, which
-- survives level loads.
function CS.beginSession()
  if cfg.snap then return end
  local parts = {}
  for _, k in ipairs(CS.PROTECTED) do
    parts[#parts + 1] = esc(k) .. "\t" .. esc(Game.Get(k))
  end
  cfg.snap = table.concat(parts, "\n")
  Coop.log("save: session snapshot of " .. #parts .. " config values")
end

-- Back in single player: put the profile values back and let the game save them.
function CS.endSession()
  if not cfg.snap then return end
  local n = 0
  for line in string.gmatch(cfg.snap, "[^\n]+") do
    local f = split(line)
    if f[1] and f[1] ~= "" then
      local old = Game.Get(f[1])
      Game.Set(f[1], type(old) == "number" and (tonumber(f[2]) or 0) or (f[2] or ""))
      n = n + 1
    end
  end
  cfg.snap = nil
  Game.DelSaveVars("")
  Game.SoftSaveConfig()
  Coop.log("save: session over, restored " .. n .. " config values")
end

------------------------------------------------------------------------------
-- Hooks (installed in every level; active only in a session)
------------------------------------------------------------------------------

function CS.installHooks()
  if not SaveGame or CS.hooked == SaveGame then return end
  CS.hooked = SaveGame

  -- Checkpoint: same as SaveGame.SaveWaypoint without the profile copy.
  local origSaveWaypoint = SaveGame.SaveWaypoint
  SaveGame.SaveWaypoint = function(idWaypoint, FileName, ...)
    if not Coop.inSession() then return origSaveWaypoint(idWaypoint, FileName, ...) end
    Game.SetSaveVar(init.LevelName .. ".Spawn.Point", "" .. idWaypoint)
    SaveGame.SaveLocalEntityValues()
    if Coop.isHost() then
      CS.write(CS.CHECKPOINT, string.sub(init.LevelFile, 8))
      Net.CoopSend(-1, 1, "cp")
    end
  end

  local origCan = SaveGame.bCanLoadWaypoint
  SaveGame.bCanLoadWaypoint = function(...)
    if not Coop.inSession() then return origCan(...) end
    return CS.read(CS.CHECKPOINT) ~= nil or CS.read(CS.SAVE) ~= nil
  end

  -- "Load last checkpoint" (game over, pause menu): the co-op checkpoint, else the level
  -- start. SaveGame.LoadLevel then carries the vars to the clients.
  local origLoadWaypoint = SaveGame.LoadWaypoint
  SaveGame.LoadWaypoint = function(...)
    if not Coop.inSession() then return origLoadWaypoint(...) end
    local rec = CS.read(CS.CHECKPOINT) or CS.read(CS.SAVE)
    if not rec or not rec.level then
      Coop.log("save: no checkpoint, restarting the level")
      return SaveGame.Restart()
    end
    CS.apply(rec)
    SaveGame.LoadLevel(rec.level)
  end

  -- Writing the profile: never during a session. Level changes go on at once (the
  -- callback is what HardSaveGame would call after writing).
  local origHard = SaveGame.HardSaveGame
  SaveGame.HardSaveGame = function(...)
    if not Coop.inSession() then return origHard(...) end
    if AfterSaveCallbackFunc == SaveGame.LoadLevel and Coop.isHost() then
      CS.levelStart(AfterSaveCallbackParam)
    end
    SaveGame.AfterSaveCallback()
    return 0
  end

  -- Levels reached in co-op unlock co-op chapters (VisitedLevels itself is restored when
  -- the session ends).
  local origVisited = SaveGame.CheckVisitedLevels
  SaveGame.CheckVisitedLevels = function(LevelName, addTo, ...)
    if Coop.inSession() and addTo then CS.addVisited(LevelName) end
    return origVisited(LevelName, addTo, ...)
  end

  -- Quitting the game from a session: leave the profile values as they were.
  if Game.Exit and not CS.origExit then
    CS.origExit = Game.Exit
    Game.Exit = function(...)
      if Coop.inSession() then pcall(CS.endSession) end
      return CS.origExit(...)
    end
  end
end

-- A new level starts (story transition): this is the co-op "continue" point. The vars
-- were just reset by SaveGame.NewLevelNow; the checkpoint of the old level is dropped.
function CS.levelStart(level)
  if not level or string.lower(level) == "menu" then return end
  Game.SetSaveVar("LevelName", level)
  CS.write(CS.SAVE, level)
  if Net.CoopFile then Net.CoopFile(CS.CHECKPOINT, "w", "") end
  CS.addVisited(level)
end

------------------------------------------------------------------------------
-- Host -> clients
------------------------------------------------------------------------------

-- Host: before every level load it starts, so the clients load the same state.
function CS.sendVars(level)
  if not Coop.isHost() then return end
  Net.CoopSend(-1, 1, "sv|" .. esc(CS.encode(level)))
end

function CS.onMessage(peer, f)
  if f[1] == "cp" and Coop.isClient() then
    -- The host reached a checkpoint (SaveGame.AutoSaveWaypoint runs there only): the same
    -- hint here, and the squad's ammo refill for the body this machine drives.
    Scorer.SetMsgText(Game.GetLangStr("Hint_Checkpoint"), Game.GetTime() + 3)
    if Team and Team.SetMaxAmmo then pcall(Team.SetMaxAmmo) end
    return true
  end
  if f[1] ~= "sv" or not Coop.isClient() or peer ~= 0 then return false end
  local rec = CS.decode(unesc(f[2] or ""))
  if rec then
    CS.pending = rec
    Coop.log("save: host vars for " .. tostring(rec.level) .. " (" .. #rec.vars .. ")")
  end
  return true
end

-- Client, right before it loads the level the host named.
function CS.applyPending()
  if CS.pending then
    CS.apply(CS.pending)
    CS.pending = nil
  end
end

CS.installHooks()
