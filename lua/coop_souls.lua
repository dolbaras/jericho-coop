-- Jericho co-op: who the players are in the story (docs/story/player-souls.md, owner 2026-10-23).
-- In the original the player is Ross's soul, which moves between the squad's bodies after his
-- death. In a session:
--   * seat 1 (the host) is Ross's soul and seat 2 (the first client, or the host's split screen
--     player when there is no client) is Jones's astral projection: both switch bodies freely;
--   * seats 3-4 are the squad members themselves: they keep their body. They still move when
--     they have to (joining, the story takes their character, a downed body with no Rawlings to
--     revive it, no body left: the spirit).
--   * Act 1: Ross is alive, nobody switches (the original's Ross cannot either); the switching
--     starts after the Conversation at the big gates, where Jones says his projection can do
--     what Ross does now.
--   * Jones held (not in the level: the Lost Patrol; switched off or taken by the story: the
--     ziggurat's possession, the cage): seat 2's projection is cut until he is free again.
-- Only the player's own choices are refused: the squad menu (Team.SetIdChar shows a body only
-- when its OnSelect is Team.SwitchSoldier) and aiming at a squad member (Team.SwitchCharacter).
-- Every forced move goes straight to Team.SwitchSoldier and is left alone.
CoopSouls = CoopSouls or {}
local S = CoopSouls
local cfg = Coop.cfg

S.HINT_GAP = 6      -- s between two hints of the same kind
S.told = {}

S.TEXT = {
  en = {fixed = "Only Ross's soul and Jones's projection move between bodies: you are %s",
        act1 = "Ross is alive: nobody moves between bodies yet",
        cut = "Jones is held: your projection is cut, you stay in this body",
        back = "Jones is free: your projection reaches the squad again",
        ross = "You are Ross's soul: you move between the squad's bodies",
        jones = "You are Jones's astral projection: you move between the squad's bodies",
        keep = "You are %s: you keep this body",
        gates = "Jones: \"Ross isn't the only one now. My projection can take any of you too.\""},
  ru = {fixed = "Переселяться между телами могут только душа Росса и проекция Джонса: вы — %s",
        act1 = "Росс жив: пока никто не переселяется между телами",
        cut = "Джонс схвачен: ваша проекция оборвалась, вы остаётесь в этом теле",
        back = "Джонс свободен: ваша проекция снова достаёт до отряда",
        ross = "Вы — душа Росса: вы переселяетесь между бойцами отряда",
        jones = "Вы — астральная проекция Джонса: вы переселяетесь между бойцами отряда",
        keep = "Вы — %s: вы остаётесь в этом теле",
        gates = "Джонс: «Теперь не только Росс так умеет. Моя проекция тоже может войти в любого из вас.»"},
}

local function text(key)
  local lang = Coop.lang()
  return Coop.enc((S.TEXT[lang] or S.TEXT.en)[key] or S.TEXT.en[key], lang)
end

local function charName(n)
  local s = n and Game.GetLangStr(n)
  if not s or s == "" then return n or "?" end
  return s
end

-- Host first, the clients in the order they joined, split screen players after them (the
-- order of the squad leaders, coop_squad.lua).
local function rank(id)
  if id == 0 then return 0 end
  if id < Coop.P2 then return id end
  return 100 + id
end

-- The session's players (owner ids), seat 1 first.
function S.seats()
  local ids, seen = {}, {}
  local function add(id)
    id = tonumber(id)
    if id and not seen[id] then seen[id] = true ids[#ids + 1] = id end
  end
  for peer in string.gmatch(cfg.seats or "", "(%d+):[^;]*") do add(peer) end
  for _, id in pairs(Coop.owners or {}) do add(id) end
  table.sort(ids, function(a, b) return rank(a) < rank(b) end)
  return ids
end

-- "ross", "jones" or "fixed" (nil: not in a session).
function S.role(id)
  if id == nil or not Coop.inSession() then return nil end
  -- (the Lost Patrol's side instance runs its authority as a host: its own seat counts)
  if cfg.inst and id == 0 and cfg.instAuth then id = cfg.instAuth end
  for i, x in ipairs(S.seats()) do
    if x == id then
      if i == 1 then return "ross" elseif i == 2 then return "jones" end
      return "fixed"
    end
  end
  return "fixed"
end

-- Jones away (not in the level, switched off: the Lost Patrol's main branch, the cage) or
-- taken by the story (the possession, coop_story.lua St.EVICT). Not the game's switch locks
-- (Team.UnavaliablePlayers): those only keep single-player switching on the story's track.
function S.jonesHeld()
  local e = Game.GetEntity("Jones")
  if not e or e.bActive == false then return true end
  if CoopStory and CoopStory.taken and CoopStory.taken("Jones") then return true end
  return false
end

-- May the player with owner id `id` switch bodies by their own choice? false + the reason.
function S.mayChoose(id)
  if not Coop.inSession() or cfg.souls == false then return true end
  if Coop.actOne() then return false, "act1" end
  local r = S.role(id)
  if r == "fixed" then return false, "fixed" end
  if r == "jones" and S.jonesHeld() then return false, "cut" end
  return true
end

function S.tell(key, ...)
  local now = Net.CoopTime()
  if (S.told[key] or -99) + S.HINT_GAP > now then return end
  S.told[key] = now
  local s = text(key)
  if select("#", ...) > 0 then s = string.format(s, ...) end
  pcall(Scorer.SetMsgText, s, Game.GetTime() + 5)
end

-- (other: the body greyed out in the squad menu; none for the aiming switch)
local function refused(why, body, other)
  if why == "fixed" then S.tell("fixed", charName(body)) else S.tell(why) end
  local key = why .. ":" .. tostring(body) .. ":" .. tostring(other)
  S.logged = S.logged or {}
  if not S.logged[key] then
    S.logged[key] = true
    Coop.log("souls: " .. tostring(body) .. " may not switch by choice (" .. why .. ")"
      .. (other and (", " .. other .. " greyed out in the squad menu") or ""))
  end
end

function S.install()
  if S.installed or not Team or not Team.SetIdChar or not Team.SwitchCharacter then return end
  S.installed = true
  -- The squad menu: other bodies stay shown, greyed out (no OnSelect) when this player may not
  -- choose them. The menu's fields can only be written from Lua (reading one is an engine error),
  -- so the vanilla test for a selectable body is repeated here.
  local origSet = Team.SetIdChar
  Team.SetIdChar = function(e, idvar, Text, Name, ...)
    local r = origSet(e, idvar, Text, Name, ...)
    if e and Name ~= e.Name and Team.IsPlayerAvaliable(Name) then
      local ok, why = S.mayChoose(Coop.ownerOf(e.Name))
      if not ok then
        e[idvar .. "OnSelect"] = ""
        refused(why, e.Name, Name)
      end
    end
    return r
  end
  -- Aiming at a squad member and pressing the switch key (a usable object still works).
  local origChar = Team.SwitchCharacter
  Team.SwitchCharacter = function(EntityName, ...)
    local e = Game.GetEntity(EntityName)
    if e and (e.AutoSelectedEntity or "") == "" and Team.Icons and Team.Icons[e.SelectedEntity or ""] then
      -- (the same key vaults a low wall first, as vanilla Team.SwitchCharacter does)
      if Soldier and Soldier.HurdleJump and Soldier.HurdleJump(e) then return end
      local ok, why = S.mayChoose(Coop.ownerOf(EntityName))
      if not ok then
        refused(why, EntityName)
        return
      end
    end
    return origChar(EntityName, ...)
  end
  -- Jones's line once the squad knows Ross is in them (wwii_biggates' Conversation).
  if Scene and Scene.EndOfScene then
    local origEnd = Scene.EndOfScene
    Scene.EndOfScene = function(...)
      local r = origEnd(...)
      if string.find(Coop.level, "wwii_biggates") and string.find(tostring(Scene.LastSceneName), "Conversation") then
        S.gatesT = Net.CoopTime() + 2
      end
      return r
    end
  end
end

-- The local players' owner ids (user 0, and the split screen player).
local function mine()
  local t = {}
  if Coop.myId() then t[#t + 1] = Coop.myId() end
  if CoopSplit and CoopSplit.on and CoopSplit.owner then t[#t + 1] = CoopSplit.owner end
  return t
end

-- A downed player of seats 3-4 does not move into another body while Rawlings can revive
-- them (coop_team.lua).
function S.waitsDowned(name)
  if not Coop.inSession() or cfg.souls == false or S.role(Coop.ownerOf(name)) ~= "fixed" then return false end
  local raw = Game.GetEntity("Rawlings")
  if name == "Rawlings" or not raw or raw.bActive == false or (raw.Life or 0) <= 0 then return false end
  -- (not walked or taken by the story, and on this player's side of a story split)
  if Coop.storyDriven and Coop.storyDriven.Rawlings then return false end
  if CoopStory and CoopStory.taken and CoopStory.taken("Rawlings") then return false end
  if CoopSplits and CoopSplits.sameSide and not CoopSplits.sameSide(name, "Rawlings") then return false end
  return true
end

-- Once a second: the role hint (once per level, after Act 1), the projection cut and back.
function S.update()
  if not Coop.inSession() or Coop.level == "levels/menu" or cfg.souls == false then return end
  S.install()
  local now = Net.CoopTime()
  if now < (S.next or 0) then return end
  S.next = now + 1
  -- (after the squad's own hint at the level's start, coop_squad.lua)
  S.startT = S.startT or now
  if (Scene and Scene.IsPlaying) or now < S.startT + 10 or Coop.actOne() then return end
  if S.gatesT and now >= S.gatesT then
    S.gatesT = nil
    S.tell("gates")
    S.roleSaid = now + 6
    return
  end
  if (S.roleSaid or 0) > now then return end
  for _, id in ipairs(mine()) do
    local r = S.role(id)
    -- (per seat: a split screen player on this PC may have another role than user 0)
    S.saidRole = S.saidRole or {}
    if r and S.saidRole[id] ~= r then
      S.saidRole[id] = r
      S.roleSaid = now + 6
      local body
      for name, o in pairs(Coop.owners or {}) do if o == id then body = name end end
      if r == "fixed" then S.tell("keep", charName(body or Coop.localChar())) else S.tell(r) end
      Coop.log("souls: seat " .. id .. " role " .. r)
      return
    end
    if r == "jones" then
      -- (the same for 3 s: a body switched off for a moment, a teleport, is not a cut)
      local held = S.jonesHeld()
      if held ~= S.heldSeen then S.heldSeen, S.heldN = held, 0 end
      S.heldN = (S.heldN or 0) + 1
      if S.held ~= held and (S.held == nil or S.heldN >= 3) then
        local first = S.held == nil
        S.held = held
        Coop.log("souls: Jones " .. (held and "held, projection cut" or "free"))
        if held then
          S.tell("cut")
          -- (the end of an astral projection, Jones.SwitchSoldier / AstralCamera; not when a
          -- level starts with Jones away)
          if not first then
            pcall(Scorer.Fade, 0, Color(0, 0, 0, 255), Color(0, 0, 0, 0), 0.5)
            pcall(Sound.Play, "PODERJONES_END", 1)
          end
        elseif not first then
          S.tell("back")
        end
      end
    end
  end
end

-- Texts of the other languages (Coop.addLangs).
Coop.addLangs(S.TEXT, "CoopSouls.TEXT")
