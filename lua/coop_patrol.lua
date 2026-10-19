-- Jericho co-op: "The Lost Patrol" (docs/story/act3-splits.md, owner's choice: the full
-- version with a second host). When the bridge collapses in cru_river, Jones, Cole and
-- Rawlings are lost until the chapel. Their players choose: join the main group (take a free
-- body there) or stay with the trio. The trio plays its own levels in a side instance
-- (coop_inst.lua) while the main group plays on; the main group's level changes drive it:
--   main group in cru_labyrinth  -> trio T1 "Below the Bridge"     (cru_river, riverbed)
--   main group in cru_sewers/keep -> trio T2 "The Children's Crypt" (cru_catacomb)
--   main group in cru_catacomb   -> trio T3 "The Inquisitorium"     (cru_chapel, no rescue scene)
--   main group in cru_chapel     -> merge: everyone in the main chapel, TheRescue plays
-- Each segment can be cut at any moment by the main group's progress: the children close
-- in, the screen goes dark, the next segment starts.
--   lpc|                     hub -> all: the bridge is falling, trio players choose
--   lpr|<1 main / 2 trio>    player -> hub

CoopPatrol = CoopPatrol or {}
local LP = CoopPatrol
local cfg = Coop.cfg

LP.TRIO = {Jones = true, Cole = true, Rawlings = true}
LP.MAIN = {"Delgado", "Church", "Black"}
LP.CHOICE_TIME = 20
-- Main group level -> the trio's segment level.
LP.SEGMENT = {Cru_Labyrinth = "Cru_River", Cru_Sewers = "Cru_Catacomb", Cru_Keep = "Cru_Catacomb",
              Cru_Catacomb = "Cru_Chapel"}

LP.TEXT = {
  en = {
    choose = "The bridge is falling. 1 - join the main group,  2 - THE LOST PATROL: stay with the lost (%d)",
    t1 = "Below the Bridge. Jones, Cole and Rawlings wake in the blood river.",
    t2 = "The Children's Crypt. They wake among small coffins.",
    t3 = "The Inquisitorium. The children dragged them under the chapel.",
    taken = "The children close in...",
  },
  ru = {
    choose = "Мост рушится. 1 - к основной группе,  2 - ПОТЕРЯННЫЙ ПАТРУЛЬ: остаться с пропавшими (%d)",
    t1 = "Под мостом. Джонс, Коул и Роулингс приходят в себя в кровавой реке.",
    t2 = "Детская крипта. Они очнулись среди маленьких гробов.",
    t3 = "Инквизиторий. Дети утащили их под часовню.",
    taken = "Дети смыкаются вокруг...",
  },
}

function LP.text(key)
  local lang = Coop.lang()
  local s = (LP.TEXT[lang] or LP.TEXT.en)[key] or LP.TEXT.en[key] or key
  return lang == "ru" and Coop.cp1251(s) or s
end

------------------------------------------------------------------------------
-- The choice (every machine for its own player; the hub collects)
------------------------------------------------------------------------------

function LP.offer()
  local me = Coop.localChar()
  if Coop.isHost() or not me or not LP.TRIO[me] then return end   -- the host stays (campaign save)
  LP.choice = {untilT = Net.CoopTime() + LP.CHOICE_TIME}
end

function LP.updateChoice()
  local c = LP.choice
  local it = Scorer.GetItem(0, "CoopPatrol")
  if not c then
    if it then it.Visible = 0 end
    return
  end
  local left = math.ceil(c.untilT - Net.CoopTime())
  local pick
  if Net.CoopKey(0x31) == 1 then pick = 1 elseif Net.CoopKey(0x32) == 1 or left <= 0 then pick = 2 end
  if cfg.lpchoice then pick = cfg.lpchoice end   -- tests
  if pick then
    LP.choice = nil
    if it then it.Visible = 0 end
    Net.CoopSend(0, 1, "lpr|" .. pick)
    Coop.log("patrol: chose " .. (pick == 2 and "the Lost Patrol" or "the main group"))
    return
  end
  if not it then
    it = Scorer.NewItem(0, "CoopPatrol", "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(255, 220, 160, 255)
    it.Effect = "Shadow"
    it.Pos = V2D(320, 90)
  end
  it.Text = string.format(LP.text("choose"), math.max(left, 0))
  it.CentralText = 1
  it.Visible = 1
end

------------------------------------------------------------------------------
-- Hub: decide at the bridge, drive the segments with the main group's levels, merge
------------------------------------------------------------------------------

LP.chosen = LP.chosen or {}

function LP.installHub()
  if LP.hubHooked or not SaveGame or not SaveGame.LoadLevel then return end
  LP.hubHooked = true
  local orig = SaveGame.LoadLevel
  SaveGame.LoadLevel = function(name, ...)
    if Coop.isHost() and not cfg.inst and name then LP.hubMainLevel(name) end
    return orig(name, ...)
  end
  -- The bridge scene: ask the trio's players.
  if Scene and Scene.PlayFP then
    local origFP = Scene.PlayFP
    Scene.PlayFP = function(class, ...)
      if class == "BridgeCollapses" and Coop.inSession() and Coop.isHost() and not LP.asked then
        LP.asked = true
        Net.CoopSend(-1, 1, "lpc|")
      end
      return origFP(class, ...)
    end
  end
end

function LP.hubMainLevel(name)
  if name == "Cru_Labyrinth" and (cfg.patrol or "") ~= "" and (cfg.instOf or "") == "" then
    local ids = {}
    for id in string.gmatch(cfg.patrol, "%d+") do ids[#ids + 1] = tonumber(id) end
    table.sort(ids)
    cfg.patrol = nil
    CoopInst.startSide("trio", ids[1], ids, "Cru_River")
  elseif name == "Cru_Chapel" and (cfg.instOf or "") ~= "" then
    CoopInst.merge("Cru_Chapel")
  elseif (cfg.instOf or "") ~= "" then
    CoopInst.tellMainLevel(name)
  end
end

------------------------------------------------------------------------------
-- Side instance (the trio): segments
------------------------------------------------------------------------------

-- Called on every trio machine right before it loads its first segment.
function LP.onSplit()
  if cfg.role == "host" then LP.prepare("Cru_River", 3) end
end

-- Authority: start a segment level at a given spawn point (its vars travel to the members
-- with the level change, coop_save.lua).
function LP.prepare(level, spawn)
  Game.DelSaveVars("")
  local var = "level." .. string.lower(level) .. ".Spawn.Point"
  Game.CreateSaveVar(var, tostring(spawn))
  Game.SetSaveVar(var, tostring(spawn))
  Game.SetSaveVar("LevelName", level)
end

-- Authority: the main group moved on; cut the segment and start the next one.
function LP.sideMainLevel(name)
  local nextLevel = LP.SEGMENT[name]
  if not nextLevel or not cfg.inst or cfg.role ~= "host" then return end
  if string.lower("levels/" .. nextLevel) == Coop.level then return end
  Coop.log("patrol: main group in " .. name .. ", trio moves to " .. nextLevel)
  Net.CoopSend(-1, 1, "lpt|")
  LP.showTaken()
  LP.nextLevel = nextLevel
  Game.AddScheduledFunc(Game.GetTime() + 4, "CoopPatrol", "CoopPatrol.goNext")
end

function LP.goNext()
  if not LP.nextLevel then return end
  LP.prepare(LP.nextLevel, 0)
  CoopInst.loadLevel(LP.nextLevel)
end

function LP.showTaken()
  Scorer.SetMsgText(LP.text("taken"), Game.GetTime() + 5)
  pcall(Scorer.Fade, 0, Color(0, 0, 0, 0), Color(0, 0, 0, 255), 3)
end

-- Every trio machine, each level: hide the main group's bodies, keep the trio's story apart.
function LP.installSide()
  if LP.sideHooked == Coop.level then return end
  LP.sideHooked = Coop.level
  for _, n in ipairs(LP.MAIN) do
    local e = Game.GetEntity(n)
    if e then
      e.bActive = false
      if e.oAI then e.oAI.bEnable = false end
    end
    if Team and Team.UnavaliablePlayers then Team.UnavaliablePlayers[n] = true end
  end
  -- The trio's levels must not move anyone on by their own scripts.
  if SaveGame then
    for _, f in ipairs({"NewLevel", "NewLevelNow"}) do
      local orig = SaveGame[f]
      SaveGame[f] = function(name, ...)
        if cfg.inst then Coop.log("patrol: level change to " .. tostring(name) .. " blocked in the side instance") return end
        return orig(name, ...)
      end
    end
  end
  local seg = Coop.level == "levels/cru_river" and "t1" or Coop.level == "levels/cru_catacomb" and "t2" or
              Coop.level == "levels/cru_chapel" and "t3" or nil
  if seg then Scorer.SetMsgText(LP.text(seg), Game.GetTime() + 8) end
  if seg == "t1" then LP.installT1() elseif seg == "t3" then LP.installT3() end
  Coop.log("patrol: segment " .. tostring(seg) .. " in " .. Coop.level)
end

-- T1 cru_river: the riverbed. Behemoth_03 belongs to Church's QTE: it stays asleep.
function LP.installT1()
  if MapCallbacks and MapCallbacks.Behemoth_00_Group__1 then
    MapCallbacks.Behemoth_00_Group__1 = function()
      local b1, b2 = Game.GetEntity("Behemoth_01_Block_1"), Game.GetEntity("Behemoth_01_Block_2")
      if b1 then b1.bMapCollision = false end
      if b2 then b2.bMapCollision = false end
    end
  end
  if Behemoth and Behemoth.HintsMedalions then
    table.insert(Behemoth.HintsMedalions, {"Cole", "86_L3_Medallions"})
  end
end

-- T3 cru_chapel: the torture chamber, without the rescue scene (the rescue is the merge).
function LP.installT3()
  if MapInit and MapInit.PlayTheRescue then MapInit.PlayTheRescue = function() end end
end

function LP.onMessage(peer, f)
  if f[1] == "lpc" and Coop.isClient() and peer == 0 then
    LP.offer()
    return true
  elseif f[1] == "lpr" and Coop.isHost() and not cfg.inst then
    if f[2] == "2" then
      local ids = {}
      for id in string.gmatch(cfg.patrol or "", "%d+") do if tonumber(id) ~= peer then ids[#ids + 1] = id end end
      ids[#ids + 1] = tostring(peer)
      cfg.patrol = table.concat(ids, ",")
      Coop.rearm()
    end
    Coop.log("patrol: peer " .. peer .. " chose " .. tostring(f[2]))
    return true
  elseif f[1] == "lpt" and cfg.inst and peer == 0 then
    LP.showTaken()
    return true
  end
  return false
end

function LP.update()
  if Coop.level == "levels/menu" then return end
  if cfg.inst then
    LP.installSide()
  elseif Coop.isHost() then
    LP.installHub()
  end
  LP.updateChoice()
end

-- Side machines: the hub's "main group changed level" (coop_inst ~c|main) drives the segments.
function LP.onMainLevel(name)
  if cfg.inst then return LP.sideMainLevel(name) end
end
