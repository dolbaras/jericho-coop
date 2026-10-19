-- Jericho co-op: story splits (docs/coop-story-extensions.md, docs/story/*-splits.md).
-- Where the story sends one character on alone, the players whose characters stay behind
-- choose: take the character who goes on (if no human holds it), or stay and play their own
-- line. Lines built so far:
--   G8 cru_sewers "Hold the gate": Church climbs alone; Black and Delgado stay active below
--      and hold the jumpers' hall against waves (the level's own generators, re-armed) in
--      three phases that follow Church's progress, until Church opens the door.
--
-- Messages:
--   spc|<split>|<target>     host -> all: choose (shown to the players the split leaves behind)
--   spn|<text key>|<chars>   host -> all: objective text for the players holding <chars>

CoopSplits = CoopSplits or {}
local Sp = CoopSplits
local cfg = Coop.cfg

Sp.TEXT = {
  en = {
    choose = "%s goes on alone.  1 - take %s,  2 - stay with your own (%d)",
    hold1 = "Hold the hall: the noise of the fight brings the Templars back.",
    hold2 = "Second wave! Hold until Church opens the door.",
    hold3 = "They come from below! Keep Church's way back open.",
    held = "The door is open. Church is back.",
  },
  ru = {
    choose = "%s идёт дальше один.  1 - перейти в %s,  2 - остаться своим персонажем (%d)",
    hold1 = "Удерживайте зал: шум боя вернул тамплиеров.",
    hold2 = "Вторая волна! Держитесь, пока Чёрч не откроет дверь.",
    hold3 = "Они лезут снизу! Не дайте отрезать Чёрчу путь назад.",
    held = "Дверь открыта. Чёрч вернулся.",
  },
}
Sp.CHOICE_TIME = 20

function Sp.text(key)
  local lang = Coop.lang()
  local s = (Sp.TEXT[lang] or Sp.TEXT.en)[key] or Sp.TEXT.en[key] or key
  return lang == "ru" and Coop.cp1251(s) or s
end

local function human(name)
  return CoopWorld and CoopWorld.isHuman(name)
end

------------------------------------------------------------------------------
-- Choice at a split (each machine for its own player)
------------------------------------------------------------------------------

Sp.SPLITS = {
  -- split id = {goes on, stays behind}
  G8 = {goes = "Church", stays = {Black = true, Delgado = true}},
}

function Sp.offer(id)
  local s = Sp.SPLITS[id]
  local me = Coop.localChar()
  if not s or not me or not s.stays[me] then return end
  -- The character going on is free: offer it; otherwise there is nothing to choose.
  if Coop.ownerOf(s.goes) ~= nil and Coop.ownerOf(s.goes) ~= Coop.myId() then return end
  Sp.choice = {id = id, target = s.goes, untilT = Net.CoopTime() + Sp.CHOICE_TIME}
  Coop.log("split " .. id .. ": choose " .. s.goes .. " or stay")
end

function Sp.updateChoice()
  local c = Sp.choice
  local it = Scorer.GetItem(0, "CoopSplit")
  if not c then
    if it then it.Visible = 0 end
    return
  end
  local left = math.ceil(c.untilT - Net.CoopTime())
  local pick
  if Net.CoopKey(0x31) == 1 then pick = "take" elseif Net.CoopKey(0x32) == 1 or left <= 0 then pick = "stay" end
  if pick then
    Sp.choice = nil
    if it then it.Visible = 0 end
    Coop.log("split " .. c.id .. ": " .. pick)
    if pick == "take" and Team and Team.SwitchSoldier and Coop.ownerOf(c.target) == nil then
      Team.SwitchSoldier(Coop.localChar(), c.target)
    end
    return
  end
  if not it then
    it = Scorer.NewItem(0, "CoopSplit", "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(255, 220, 160, 255)
    it.Effect = "Shadow"
    it.Pos = V2D(320, 90)
  end
  it.Text = string.format(Sp.text("choose"), c.target, c.target, math.max(left, 0))
  it.CentralText = 1
  it.Visible = 1
end

------------------------------------------------------------------------------
-- Holds: the level's own enemy generators, re-armed (host)
------------------------------------------------------------------------------

Sp.rearmed = {}

-- Make generator group `name` spawn without end, `max` at a time, at its own spawn points.
function Sp.rearm(name, max)
  local g = NPC and NPC.Groups and NPC.Groups[name]
  if not g or not g.uData or not g.uData.spawnPoints then
    Coop.log("split: group " .. name .. " cannot be re-armed")
    return false
  end
  local el = Game.GetEntityList(name)
  if el then el.OnAllDeath = "" end   -- its story callback already ran
  g.uData.isInfinite = true
  g.uData.Stopped = false
  g.uData.wasActivated = true
  g.uData.maxSimultaneousEnemies = max
  Game.DeleteScheduledFuncs(name .. "ActivateNextEnemy")
  for _ = 1, max do EnemyGen.ScheduleActivationOfNextEnemy(name) end
  Sp.rearmed[name] = true
  Coop.log("split: " .. name .. " re-armed, " .. max .. " at a time")
  return true
end

function Sp.stopHolds()
  for name in pairs(Sp.rearmed) do
    pcall(EnemyGen.Stop, name, true)
  end
  Sp.rearmed = {}
end

-- Players below: how many humans hold the staying characters.
function Sp.humansIn(set)
  local n = 0
  for name in pairs(set) do if human(name) then n = n + 1 end end
  return n
end

function Sp.notice(key, chars)
  Net.CoopSend(-1, 1, "spn|" .. key .. "|" .. table.concat(chars, ","))
  Sp.showNotice(key, chars)
end

function Sp.showNotice(key, chars)
  local me = Coop.localChar()
  for _, c in ipairs(chars) do
    if c == me then
      Scorer.SetMsgText(Sp.text(key), Game.GetTime() + 8)
      return
    end
  end
end

function Sp.radio(char, category, n)
  if TeamTalk and TeamTalk.RadioTalk and Game.GetEntity(char) then
    pcall(TeamTalk.RadioTalk, char, category, "Talk", n)
  end
end

------------------------------------------------------------------------------
-- Hooks by name, after the original (host)
------------------------------------------------------------------------------

function Sp.after(path, fn)
  local tname, fname = string.match(path, "^([%w_]+)%.([%w_]+)$")
  local tbl = _G[tname]
  local f = tbl and tbl[fname]
  if type(f) ~= "function" or (Sp.hooked[tbl] and Sp.hooked[tbl][fname] == f) then return end
  local orig = f
  local w = function(...)
    local r = {orig(...)}
    local ok, err = pcall(fn, ...)
    if not ok then Coop.log("split hook " .. path .. " error: " .. tostring(err)) end
    return unpack(r)
  end
  tbl[fname] = w
  Sp.hooked[tbl] = Sp.hooked[tbl] or {}
  Sp.hooked[tbl][fname] = w
end
Sp.hooked = setmetatable({}, {__mode = "k"})

------------------------------------------------------------------------------
-- G8 cru_sewers: "Hold the gate"
------------------------------------------------------------------------------

Sp.G8 = {stays = {Black = true, Delgado = true}, list = {"Black", "Delgado"}}

function Sp.G8phase(n)
  local g = Sp.G8
  local below = Sp.humansIn(g.stays)
  if below == 0 or g.phase == "done" then return end
  g.phase = n
  if Team and Team.ReviveAll then pcall(Team.ReviveAll) end
  Coop.log("split G8: phase " .. n .. ", " .. below .. " player(s) below")
  if n == 1 then
    Sp.rearm("Enemy_Generator_Jumpers", 1 + below)
    Sp.notice("hold1", g.list)
    Sp.radio("Black", "Enemy_Ambush")
  elseif n == 2 then
    Sp.rearm("Enemy_First", 1 + below)
    Sp.notice("hold2", g.list)
    Sp.radio("Delgado", "Under_Heavy_Fire")
  elseif n == 3 then
    Sp.rearm("Enemy_Generator_Jumpers", 2 + below)
    Sp.notice("hold3", g.list)
    Sp.radio("Black", "Help_Omega")
  end
end

function Sp.installG8()
  -- Church starts the climb (use object or area trigger): the choice, then phase 1 when
  -- the scene hands control back.
  local function climb()
    Net.CoopSend(-1, 1, "spc|G8")
    Sp.offer("G8")
    Game.AddScheduledFunc(Game.GetTime() + 12, "CoopSplitG8", "CoopSplits.G8phase", 1)
  end
  Sp.after("MapCallbacks.TriggerEscalada_0", climb)
  Sp.after("MapCallbacks.PlayEscalada", function(_, Playerid)
    if Scene and Scene.IsPlaying then climb() end
  end)
  -- Church enters the ward room: vanilla switches Black and Delgado off; human ones stay.
  Sp.after("MapCallbacks.TriggerBloodWar_3", function()
    for _, n in ipairs(Sp.G8.list) do
      local e = Game.GetEntity(n)
      if e and human(n) then e.bActive = true end
    end
    Sp.G8phase(2)
  end)
  Sp.after("MapCallbacks.BloodWarGroup_0", function() Sp.G8phase(3) end)
  Sp.after("MapCallbacks.TriggerAperturaPuerta_0", function()
    if Sp.G8.phase and Sp.G8.phase ~= "done" then
      Sp.G8.phase = "done"
      Sp.stopHolds()
      Sp.notice("held", Sp.G8.list)
      Coop.log("split G8: held")
    end
  end)
end

------------------------------------------------------------------------------

Sp.LEVELS = {["levels/cru_sewers"] = Sp.installG8}

function Sp.onMessage(peer, f)
  if f[1] == "spc" and Coop.isClient() then
    Sp.offer(f[2])
    return true
  elseif f[1] == "spn" and Coop.isClient() then
    local chars = {}
    for c in string.gmatch(f[3] or "", "[^,]+") do chars[#chars + 1] = c end
    Sp.showNotice(f[2], chars)
    return true
  end
  return false
end

function Sp.update()
  if Coop.isHost() and Sp.LEVELS[Coop.level] and MapCallbacks then Sp.LEVELS[Coop.level]() end
  Sp.updateChoice()
end
