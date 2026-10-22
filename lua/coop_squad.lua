-- Jericho co-op: who leads the AI squad members ("Follow me" / "Hold position").
-- The game has one player: its area manager moves both fire teams, Alpha (Jones, Cole, Delgado)
-- and Omega (Church, Rawlings, Black), around that player's area, so in a session every AI member
-- ran after the host and a client's orders did nothing (owner, 0.2.2). Here each team has a
-- leader among the players:
--   * Act 1 while Ross lives: Ross's player leads everyone (the original's commander).
--   * Otherwise each team is led by the first player in order (host, the first client, the
--     others, split screen players after them) whose character is in it; a team without a
--     player in it is led by the first player who leads nothing yet, else by the host. So two
--     players lead one team each, a third and fourth lead none.
--   * Split up (a story split, a branch): an AI member far from its leader and near another
--     player follows that player instead, until it is with its leader again.
-- The host runs the AI: members whose leader is not its own player get the game's helpers in
-- their leader's area (as the game does for its own player) instead of the area manager's.
-- Orders: only the leader's order moves a team; others are told who leads it.
--   sqo|<team>|follow/hold    client -> host: the order of a team this player leads
CoopSquad = CoopSquad or {}
local Q = CoopSquad
local cfg = Coop.cfg

Q.TEAMS = {"Alpha", "Omega"}
Q.POLL = 1          -- s between leader and helper updates
Q.APART = 5000      -- units: a member this far from its leader ...
Q.CLOSE = 3000      -- ... and this near another player follows that one (and back under it)
Q.CHASE = 450       -- units from its leader: runs after it (the game's chase of its own player)
Q.CHASE_MIN = 200   -- the chase keeps it this far from its leader (the game's own near chase) ...
Q.CHASE_MAX = 350   -- ... to this
Q.leaderOf = {}     -- AI member -> owner id of the player it follows
Q.mode = {}         -- "<owner id>:<team>" -> "hold" (follow when absent)
Q.areaOf = {}       -- AI member -> name of the area its helper was taken in
Q.told = {}

Q.TEXT = {
  en = {lead = "You lead %s: %s", all = "The whole squad follows you", ross = "The squad follows Ross",
        other = "%s follows %s: the orders for it are that player's"},
  ru = {lead = "Вы командуете группой %s: %s", all = "Весь отряд следует за вами", ross = "Отряд следует за Россом",
        other = "%s следует за %s: приказы ей отдаёт этот игрок"},
}

local function text(key)
  local lang = Coop.lang()
  return Coop.enc((Q.TEXT[lang] or Q.TEXT.en)[key] or Q.TEXT.en[key], lang)
end

local function rank(id)
  if id == 0 then return 0 end
  if id < Coop.P2 then return id end
  return 100 + id
end

local function teamOf(name)
  local e = Game.GetEntity(name)
  local ok, t = pcall(function() return e and e.oAI and e.oAI.Team end)
  if ok and (t == "Alpha" or t == "Omega") then return t end
  return nil
end

local function teamName(t)
  local s = Game.GetLangStr(t .. "_Team")
  if not s or s == "" then return t end
  return s
end

local function charName(n)
  local s = Game.GetLangStr(n)
  if not s or s == "" then return n end
  return s
end

local function alive(e)
  return e and (e.Life or 0) > 0 and e.bActive ~= false and e.Active ~= 0
end

local function dist(a, b)
  return (a.Pos - b.Pos):mod2D()
end

-- The players (owner id -> body), first in order first.
function Q.players()
  local t = {}
  for name, id in pairs(Coop.owners or {}) do
    local e = Game.GetEntity(name)
    if alive(e) then t[#t + 1] = {id = id, name = name, e = e} end
  end
  table.sort(t, function(a, b) return rank(a.id) < rank(b.id) end)
  return t
end

-- Every AI member's leader (owner id); nil: one player or none (the game as it is).
function Q.assign()
  local players = Q.players()
  local result = {}
  if #players < 2 then return result, players end
  local byId = {}
  for _, p in ipairs(players) do byId[p.id] = p end
  local members = {}
  for _, n in ipairs(Coop.SQUAD) do
    local e = Coop.squadEnt(n)
    if alive(e) and Coop.ownerOf(n) == nil then members[#members + 1] = n end
  end
  local ross = Coop.actOne() and Game.GetEntity("Ross")
  if alive(ross) then
    local lead = Coop.ownerOf("Ross") or players[1].id
    for _, n in ipairs(members) do result[n] = lead end
    return result, players, "ross"
  end
  local teamLead = {}
  for _, p in ipairs(players) do
    local t = teamOf(p.name)
    if t and teamLead[t] == nil then teamLead[t] = p.id end
  end
  for _, t in ipairs(Q.TEAMS) do
    if teamLead[t] == nil then
      for _, p in ipairs(players) do
        local leads = false
        for _, other in pairs(teamLead) do if other == p.id then leads = true end end
        if not leads then teamLead[t] = p.id break end
      end
      teamLead[t] = teamLead[t] or players[1].id
    end
  end
  for _, n in ipairs(members) do
    local lead = teamLead[teamOf(n) or "Alpha"]
    local e = Game.GetEntity(n)
    local cur = Q.leaderOf[n]
    -- Split up: with the player it is near (kept until close to its team's leader again).
    if cur ~= nil and cur ~= lead and byId[cur] and byId[lead] and dist(e, byId[lead].e) > Q.CLOSE then
      lead = cur
    elseif byId[lead] and dist(e, byId[lead].e) > Q.APART then
      local best, bestD
      for _, p in ipairs(players) do
        local d = dist(e, p.e)
        if d < Q.CLOSE and (not bestD or d < bestD) then best, bestD = p.id, d end
      end
      if best then lead = best end
    end
    result[n] = lead
  end
  return result, players
end

local function myIds()
  local t = {[Coop.myId() or -1] = true}
  if CoopSplit and CoopSplit.on and CoopSplit.owner then t[CoopSplit.owner] = true end
  return t
end

-- The leader of a team as this machine sees it (the leader of its AI members).
function Q.teamLeader(team)
  for n, id in pairs(Q.leaderOf) do
    if teamOf(n) == team then return id end
  end
  return nil
end

function Q.bodyOfOwner(id)
  for name, o in pairs(Coop.owners or {}) do
    if o == id then return name end
  end
end

------------------------------------------------------------------------------
-- Host: the members led by another player than its own get helpers in that player's area.
------------------------------------------------------------------------------

function Q.remoteLed(name)
  local id = Q.leaderOf[name]
  return id ~= nil and id ~= 0
end

function Q.follow(name, force)
  local e = Game.GetEntity(name)
  local leadName = Q.bodyOfOwner(Q.leaderOf[name])
  local lead = leadName and Game.GetEntity(leadName)
  if not alive(e) or not lead or not e.oAI or e.oAI.bEnable == false then return end
  if Coop.storyDriven and Coop.storyDriven[name] then return end
  local okBusy, busy = pcall(function() return e.oAI.uData.DoGoAndAction end)
  if okBusy and busy then return end
  if Q.mode[Q.leaderOf[name] .. ":" .. (teamOf(name) or "")] == "hold" then return end
  -- In a fight the member fights (the game's own combat AI); else it runs after its leader as
  -- the game keeps members near its own player (a chase, kept between CHASE_MIN and CHASE_MAX).
  -- Helpers in the leader's area did not do: areas are big, and one shared with the host's
  -- player sent the members back to it (squad test 0.2.3).
  local okA, attacked = pcall(AIMemberSquad.UnderAttack, e)
  if okA and attacked and not force then return end
  if dist(e, lead) <= Q.CHASE then return end
  local okS, state, obj = pcall(function() return e.oAI.State, e.oAI.ObjectiveDin end)
  if force or not okS or state ~= CHASE_WITHOUT_ACTION_CHAR or obj ~= lead.Name then
    local ok, err = pcall(function()
      e.AI_DistMinChase = Q.CHASE_MIN
      e.AI_DistMaxChase = Q.CHASE_MAX
      AI.SetStateChar(CHASE_WITHOUT_ACTION_CHAR, e.Name, lead.Name, 1)
    end)
    if not ok and not Q.followError then
      Q.followError = true
      Coop.log("squad: chase for " .. name .. " error " .. tostring(err))
    end
  end
end

-- "Hold position": a member still running after its leader stops where it is.
function Q.hold(name)
  local e = Game.GetEntity(name)
  local ok, state = pcall(function() return e.oAI.State end)
  if ok and state == CHASE_WITHOUT_ACTION_CHAR then pcall(AI.SetStateChar, STATIC_CHAR, name) end
end

-- A team's order by its leader (owner id): every member it leads follows or holds.
function Q.order(lead, team, mode)
  Q.mode[lead .. ":" .. team] = mode == "hold" and "hold" or nil
  for n, id in pairs(Q.leaderOf) do
    if id == lead and teamOf(n) == team then
      if mode == "hold" then Q.hold(n) else Q.follow(n, true) end
    end
  end
end

function Q.installHost()
  if Q.hostInstalled or not AIMemberSquad then return end
  Q.hostInstalled = true
  for _, fn in ipairs({"ExecuteOrder", "OnChangeAdvancePlayerTeam", "OnChangeAdvanceSecondTeam"}) do
    local orig = AIMemberSquad[fn]
    if type(orig) == "function" then
      AIMemberSquad[fn] = function(ent, ...)
        if Coop.inSession() and ent and Q.remoteLed(ent.Name) then
          Q.follow(ent.Name, true)
          return
        end
        return orig(ent, ...)
      end
    end
  end
  -- "Follow me" up close: the game's chase of its own player, not for members led by another.
  if AISquadTeam and AISquadTeam.Chase then
    local origChase = AISquadTeam.Chase
    AISquadTeam.Chase = function(team, ent, withOtherAction)
      if not Coop.inSession() or not team then return origChase(team, ent, withOtherAction) end
      local held = {}
      local memb = team.oFirst
      while memb ~= nil do
        local e = memb.oEnt
        if e and Q.remoteLed(e.Name) and e.oAI then held[#held + 1] = e end
        memb = team:oNext(memb)
      end
      local r = {pcall(origChase, team, ent, withOtherAction)}
      for _, e in ipairs(held) do Q.follow(e.Name, false) end
      if not r[1] then error(r[2], 0) end
    end
  end
end

------------------------------------------------------------------------------
-- Orders: only the leader's move a team.
------------------------------------------------------------------------------

-- The teams an order function is for, as this machine's player sees them.
local function orderTeams(kind, entityName)
  local own = teamOf(entityName or (Game.UsrEntity(0) and Game.UsrEntity(0).Name) or "")
  local other = own == "Alpha" and "Omega" or "Alpha"
  if kind == "main" then return {own} end
  if kind == "side" then return {other} end
  return {own, other}
end

function Q.tell(key, ...)
  local s = string.format(text(key), ...)
  pcall(Scorer.SetMsgText, s, Game.GetTime() + 4)
end

-- An order by this machine's player: true when it may go on (this player leads the team).
function Q.mayOrder(team, mode)
  if not Coop.inSession() then return true end
  local lead = Q.teamLeader(team)
  if lead == nil then return true end
  if myIds()[lead] then
    if Coop.isHost() then
      Q.order(lead, team, mode)
    else
      Net.CoopSend(0, 1, "sqo|" .. team .. "|" .. mode)
    end
    return true
  end
  local who = Q.bodyOfOwner(lead)
  Q.tell("other", teamName(team), charName(who or "?"))
  return false
end

function Q.installOrders()
  if Q.ordersInstalled or not Team or not Team.ActiveFollow then return end
  Q.ordersInstalled = true
  local wraps = {
    ActiveFollow = {"main", "follow", "OrdersMain"}, ActiveHold = {"main", "hold", "OrdersMain"},
    SupportFollow = {"side", "follow", "OrdersSide"}, SupportHold = {"side", "hold", "OrdersSide"},
    FollowMeOrder = {"both", "follow"}, HoldPositionOrder = {"both", "hold"},
  }
  for fn, w in pairs(wraps) do
    local orig = Team[fn]
    if type(orig) == "function" then
      Team[fn] = function(EntityName, ...)
        if not Coop.inSession() then return orig(EntityName, ...) end
        local ok = false
        for _, t in ipairs(orderTeams(w[1], EntityName)) do
          if Q.mayOrder(t, w[2]) then ok = true end
        end
        if ok then return orig(EntityName, ...) end
        if w[3] and Team[w[3]] then pcall(Team[w[3]], EntityName) end   -- the menu as it was
      end
    end
  end
end

function Q.onMessage(peer, f)
  if f[1] ~= "sqo" then return false end
  if Coop.isHost() then
    local team, mode = f[2], f[3]
    local lead = Q.teamLeader(team)
    if lead ~= nil and Coop.peerOf(lead) == peer then
      Coop.log("squad: " .. team .. " " .. mode .. " by peer " .. peer)
      Q.order(lead, team, mode)
    end
  end
  return true
end

------------------------------------------------------------------------------

-- Who this machine's player leads, said once per level and when it changes.
function Q.say(kind)
  local mine = myIds()
  local led, teams = {}, {}
  for n, id in pairs(Q.leaderOf) do
    if mine[id] then
      led[#led + 1] = charName(n)
      local t = teamOf(n)
      if t then teams[t] = true end
    end
  end
  table.sort(led)
  local key = kind .. ":" .. table.concat(led, ",")
  if Q.told.last == key then return end
  Q.told.last = key
  if kind == "ross" and not mine[Coop.ownerOf("Ross") or -1] then
    Q.tell("ross")
  elseif teams.Alpha and teams.Omega then
    Q.tell("all")
  elseif #led > 0 then
    Q.tell("lead", teamName(teams.Alpha and "Alpha" or "Omega"), table.concat(led, ", "))
  end
end

function Q.update()
  if not Coop.inSession() or Coop.level == "levels/menu" or cfg.squadlead == false then return end
  local now = Net.CoopTime()
  if now < (Q.next or 0) then return end
  Q.next = now + Q.POLL
  Q.installOrders()
  if Coop.isHost() then Q.installHost() end
  local result, players, kind = Q.assign()
  for n, id in pairs(result) do
    if Q.leaderOf[n] ~= id then
      Coop.log("squad: " .. n .. " follows " .. tostring(Q.bodyOfOwner(id)) .. " (" .. id .. ")")
      Q.areaOf[n] = nil
    end
  end
  Q.leaderOf = result
  if Coop.isHost() then
    for n in pairs(result) do
      if Q.remoteLed(n) then Q.follow(n, false) end
    end
  end
  if #players >= 2 and (Coop.frame or 0) > 60 then Q.say(kind or "teams") end
end

-- Texts of the other languages (Coop.addLangs).
Coop.addLangs(Q.TEXT, "CoopSquad.TEXT")
