-- Jericho co-op: story scripts written for one player (docs/usrentity-audit.md).
--
-- Scripted walks (AIGen.GoAndAction, mechanism M1b): the story walks a squad member
-- somewhere and continues when it arrives (Black to a telekinesis door, Church to the
-- Brandenburg altar...). A body held by a remote player is a puppet on the host (AI off,
-- position from the network), so it never arrived and the story stopped. Now the host takes
-- the body for the walk: its AI walks it, the owner's machine shows it walking (its input
-- locked, the body following the host), and control goes back on arrival.
-- What the walk does on arrival (open a door, start a scene) runs on the host; clients
-- run the same arrival function when the host says the walk is over, so local effects
-- (doors, FX, actions) happen on every machine.
--   sdrive|<char>|1   host -> all: the host's AI drives <char> (story walk)
--   sdrive|<char>|0   host -> all: back to its owner
--   sdone|<char>      host -> all: a story walk of <char> arrived

CoopStory = CoopStory or {}
local St = CoopStory
local cfg = Coop.cfg

-- Host: start or end a story walk of a remote-owned body.
function St.drive(name, on)
  if (Coop.storyDriven[name] or false) == on then return end
  Coop.storyDriven[name] = on or nil
  -- Back to the player: forget their last state from before the walk, or the body would be
  -- pulled back there until their machine sends a new one.
  if not on then Coop.remote[name] = nil end
  local e = Game.GetEntity(name)
  if on and e and e.oAI then
    e.InCtrl_Walk, e.InCtrl_Str = 0, 0
    e.oAI.bEnable = true
  end
  Net.CoopSend(-1, 1, "sdrive|" .. name .. "|" .. (on and 1 or 0))
  Coop.log("story: " .. name .. (on and " walked by the host" or " back to its player"))
end

function St.installWalks()
  if not AIGen or not AIGen.GoAndAction or St.walkHooked == AIGen then return end
  St.walkHooked = AIGen
  local orig = AIGen.GoAndAction
  AIGen.GoAndAction = function(nameEnt, pos, posEnd, funcExec, velocity)
    if not Coop.inSession() then return orig(nameEnt, pos, posEnd, funcExec, velocity) end
    if Coop.isHost() then
      local remote = Coop.isRemoteOwned(nameEnt)
      if remote then St.drive(nameEnt, true) end
      local done = function(ent, ...)
        if remote then St.drive(nameEnt, false) end
        Net.CoopSend(-1, 1, "sdone|" .. nameEnt)
        if funcExec then return funcExec(ent, ...) end
      end
      return orig(nameEnt, pos, posEnd, done, velocity)
    end
    -- Client (story code replayed, or run by MapInit): the arrival function waits for the
    -- host's sdone. This machine's own body walks here only if the host does not walk it
    -- (a "the player walks" step, run on every machine): decided after WAIT seconds.
    St.pending[nameEnt] = {func = funcExec, args = {nameEnt, pos, posEnd, funcExec, velocity},
                           t = Net.CoopTime(), mine = nameEnt == Coop.localChar()}
  end
  St.origWalk = orig
  -- Scripts may end a walk early with its arrival function cleared
  -- (sum_ziggurat_04 ForcePlayerToWatchScene): the body goes back to its player then too.
  local origEnd = AIGen.GoAndAction_GoToEndEvent
  AIGen.GoAndAction_GoToEndEvent = function(ent, ...)
    local r = {origEnd(ent, ...)}
    if Coop.isHost() and ent and Coop.storyDriven[ent.Name] and not ent.oAI.uData.DoGoAndAction then
      St.drive(ent.Name, false)
    end
    return unpack(r)
  end
end

St.WAIT = 0.6
St.pending = {}

function St.clientWalks()
  local now = Net.CoopTime()
  for name, p in pairs(St.pending) do
    if p.mine and not p.started and now - p.t > St.WAIT and not Coop.storyDriven[name] then
      p.started = true
      St.pending[name] = nil
      St.origWalk(unpack(p.args, 1, 5))
    elseif now - p.t > 120 then
      St.pending[name] = nil   -- the host never finished it (level changed, scene...)
    end
  end
end

function St.onDone(name)
  local p = St.pending[name]
  if not p then return end
  St.pending[name] = nil
  local e = Game.GetEntity(name)
  if p.func and e then
    local ok, err = pcall(p.func, e)
    if not ok then Coop.log("story: arrival of " .. name .. " error: " .. tostring(err)) end
  end
end

function St.onMessage(peer, f)
  if f[1] == "ev" then
    St.onEvent(peer, f)
    return true
  end
  if f[1] == "gv" and Coop.isHost() then
    local char = St.VARS[f[2] or ""]
    if char and Coop.heldBy(char, peer) then Game.Set(f[2], tonumber(f[3]) or f[3]) end
    return true
  end
  if f[1] == "evict" and Coop.isClient() then
    St.onEvict(f)
    return true
  end
  if f[1] == "sdone" and Coop.isClient() then
    St.onDone(f[2])
    return true
  end
  if f[1] ~= "sdrive" or not Coop.isClient() or peer ~= 0 then return false end
  local name, on = f[2], f[3] == "1"
  Coop.storyDriven[name] = on or nil
  if Coop.isLocalBody(name) then   -- (its split screen player's too)
    local usr = Game.GetEntity(name)
    if usr then
      usr.IgnoreUsrControl = on and 1 or 0
      -- The player cannot fight back while the story walks their body (vanilla walks happen
      -- between fights, but leftovers or a fast player can still be around).
      St.walkInvul = St.walkInvul or {}
      if on then
        St.walkInvul[name] = St.walkInvul[name] or usr.Invulnerable or 0
        usr.Invulnerable = 1
      elseif St.walkInvul[name] then
        usr.Invulnerable = St.walkInvul[name]
        St.walkInvul[name] = nil
      end
    end
    Coop.log("story: my body " .. (on and "walked by the host" or "back to me"))
  end
  return true
end

------------------------------------------------------------------------------
-- "The player is X" (mechanism M1). Story checks compare Game.UsrEntity(0) with a
-- character; in a session "the player" is whichever human holds that character. During a
-- wrapped call UsrEntity(0) resolves to:
--   char = "Church"   that character, if any human holds it (else vanilla: the local body)
--   attacker = 2      the attacker named by argument 2, if a human holds it
--   triggered = 2     the body that entered the area trigger (argument 2 = Playerid), if human
--   pick = function   custom choice
-- clientNoop: do nothing on clients (story steps the host decides and replicates);
-- clientNoSwitch: on clients run it without its forced Team.SwitchSoldier.
------------------------------------------------------------------------------

local function humanBody(name)
  local e = name and Game.GetEntity(name)
  if e and CoopWorld and CoopWorld.isHuman(name) then return e end
end

St.AS = {
  -- wwii_biggates: blood ward tutorial gates the next enemy group (and Cole's door).
  {"MapInit", "TestWard", char = "Church", level = "wwii_biggates"},
  -- wwii_pillboxes: Rawlings tutorial group.
  {"MapInit", "ActivateBigFuckerGroup", char = "Rawlings", level = "wwii_pillboxes"},
  -- rom_outskirts: CenturiansTale starts as soon as a human holds Rawlings.
  {"MapInit", "BeginPlayScene", char = "Rawlings", level = "rom_outskirts", clientNoop = true},
  -- cru_labyrinth: the last speech plays when Black looks at the prisoner; the bridge hitter
  -- takes damage only from the right side of the chasm (the attacker's, not the host's).
  {"MapCallbacks", "TriggerLastScene_0", char = "Black", level = "cru_labyrinth"},
  {"MapCallbacks", "bridgeBHitter4_1", attacker = 2, level = "cru_labyrinth"},
  -- rom_chamber: any player entering starts the walk to Vicus.
  {"MapCallbacks", "AreaTrigger43_0", triggered = 2, level = "rom_chamber"},
  -- sum_ziggurat_02: the vortex leaves only Black playable; vanilla switches "the player" to
  -- him on every machine. Clients must not grab Black for themselves.
  {"MapInit", "Init", level = "sum_ziggurat_02", clientNoSwitch = true},
  {"MapCallbacks", "trigDisableBlack_0", char = "Black", level = "sum_ziggurat_02"},
  -- sum_ziggurat_04: the squad walks to the urn; the fight goes on when "the player"
  -- arrives, and only Black, Delgado or Jones count (as the host's Rawlings it never did).
  {"MapInit", "ReposSquad", level = "sum_ziggurat_04", pick = function()
    for _, n in ipairs({"Black", "Delgado", "Jones"}) do
      if humanBody(n) then return humanBody(n) end
    end
    return Game.GetEntity("Black")
  end},
  -- sum_end: the blood rune locks and switches "the player" unless it is Church.
  {"EvilFirstBorn", "DrawBloodRune", char = "Church"},
  -- sum_ziggurat_03: Jones' astral touch uncovers Ninlil.
  {"SummerianNINLIL", "Use", char = "Jones"},
  -- Story objects and bosses that react only to "the player's" hits.
  {"PhysicsObj", "BritishBombOnDamage", attacker = 2},
  {"Gladiador", "OnDamage", attacker = 2},
  {"PuppetGod", "OnDamage", attacker = 2},
  {"SummerianNANNA", "OnDamage", attacker = 2},
  {"SummerianUTU", "OnDamage", attacker = 2},
}

function St.asPlayer(entity, fn, ...)
  if not entity then return fn(...) end
  local orig = Game.UsrEntity
  Game.UsrEntity = function(id)
    if id == 0 then return entity end
    return orig(id)
  end
  local r = {pcall(fn, ...)}
  Game.UsrEntity = orig
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2)
end

-- Which of our wrappers a function already carries (a function may get both kinds).
St.kinds = setmetatable({}, {__mode = "k"})

function St.hasKind(f, kind)
  return St.kinds[f] ~= nil and St.kinds[f][kind] == true
end

function St.markKind(w, inner, kind)
  local k = {[kind] = true}
  for x in pairs(St.kinds[inner] or {}) do k[x] = true end
  St.kinds[w] = k
end

function St.installAs()
  for _, spec in ipairs(St.AS) do
    local tbl = (not spec.level or Coop.level == "levels/" .. spec.level) and _G[spec[1]]
    local f = tbl and tbl[spec[2]]
    if type(f) == "function" and not St.hasKind(f, "as") then
      local orig = f
      local w = function(...)
        if not Coop.inSession() then return orig(...) end
        if spec.clientNoop and Coop.isClient() then return end
        if spec.clientNoSwitch and Coop.isClient() then
          local sw = Team.SwitchSoldier
          Team.SwitchSoldier = function() return false end
          local r = {pcall(orig, ...)}
          Team.SwitchSoldier = sw
          if not r[1] then error(r[2], 0) end
          return unpack(r, 2)
        end
        local who
        if spec.pick then who = spec.pick(...)
        elseif spec.char then who = humanBody(spec.char)
        elseif spec.attacker then who = humanBody((select(spec.attacker, ...)))
        elseif spec.triggered then
          local ok, nam = pcall(Game.GetTriggeredEntity, (select(spec.triggered, ...)))
          if CoopWorld and CoopWorld.replaying then nam = CoopWorld.replayTriggered end
          who = ok and humanBody(nam) or nil
        end
        return St.asPlayer(who, orig, ...)
      end
      St.markKind(w, orig, "as")
      tbl[spec[2]] = w
    end
  end
end

-- sum_end: the First Born incapacitates every squad member who is not "the player" in first
-- person; the final kill needs that player to be Church with the blood rune active. A body
-- a remote human holds is a player too (its first-person state is on its own machine).
function St.installFirstBorn()
  local fb = EvilFirstBorn
  if not fb or not fb.IncapacitateSch or St.fbHooked == fb then return end
  St.fbHooked = fb
  local orig = fb.IncapacitateSch
  fb.IncapacitateSch = function(tgtName, ...)
    if not (Coop.inSession() and Coop.isHost() and Coop.isRemoteOwned(tgtName)) then return orig(tgtName, ...) end
    fb.EndFXAura(tgtName, tgtName)
    if tgtName == "Church" and Game.Get("RuneBloodActive") == 1 then
      fb.EndFXAura(tgtName, "EvilFB")
      fb.KillFirstBornScene()
      return
    end
    Game.AddScheduledFunc(Game.GetTime() + 0.1, "IncapacitateSquadMember", "EvilFirstBorn.IncapacitateSch", tgtName)
  end
end

------------------------------------------------------------------------------
-- Character powers that drive the story (mechanism M3). They run on the machine of the
-- player who uses them; the host must run them too, and every other machine as well (their
-- copies of the level script keep hints and local state):
--   ev|<n>|<origin peer>|<args>   to the host (from a client), then from the host to all
-- char: only the holder of that character may send it; attacker: the argument naming the
-- character; once: the vanilla caller clears the slot before calling (a one-shot callback),
-- so a receiver clears it too.
--   gv|<name>|<value>             client -> host: a game variable a power set (St.VARS)
------------------------------------------------------------------------------

St.EVENTS = {
  {"Church", "callOnWard", char = "Church", once = true},          -- wwii_biggates ward
  {"ThreadsChurch", "OnWardCallback", char = "Church"},            -- cru_sewers ward
  {"SummerianNINLIL", "Use", char = "Jones"},                      -- sum_ziggurat_03
  {"PhysicsObj", "BritishBombOnDamage", attacker = 2},             -- wwii_mosque_inside
}
St.VARS = {RuneBloodActive = "Church"}

local function enc(v)
  local t = type(v)
  if t == "string" then return "s" .. string.gsub(v, "[|;]", "") end
  if t == "number" then return "n" .. tostring(v) end
  if t == "boolean" then return v and "b1" or "b0" end
  if t == "userdata" then
    local ok, x = pcall(function() return v.x end)
    if ok and x then return string.format("v%.1f,%.1f,%.1f", v.x, v.y, v.z) end
  end
  return "-"
end

local function dec(s)
  local k, v = string.sub(s, 1, 1), string.sub(s, 2)
  if k == "s" then return v end
  if k == "n" then return tonumber(v) end
  if k == "b" then return v == "1" end
  if k == "v" then
    local x, y, z = string.match(v, "([^,]+),([^,]+),([^,]+)")
    return V3D(tonumber(x), tonumber(y), tonumber(z))
  end
end

function St.eventChar(spec, args)
  if spec.char then return spec.char end
  if spec.attacker then return args[spec.attacker] end
end

function St.sendEvent(i, origin, args)
  local parts = {"ev", i, origin}
  for k = 1, args.n or #args do parts[#parts + 1] = enc(args[k]) end
  local msg = table.concat(parts, "|")
  if Coop.isHost() then Net.CoopSend(-1, 1, msg) else Net.CoopSend(0, 1, msg) end
end

function St.installEvents()
  for i, spec in ipairs(St.EVENTS) do
    local tbl = _G[spec[1]]
    local f = tbl and tbl[spec[2]]
    if type(f) == "function" and not St.hasKind(f, "ev") then
      local orig = f
      local w = function(...)
        if Coop.inSession() and not St.fromNet then
          local args = {n = select("#", ...), ...}
          -- Only the machine of the character's holder reports it.
          if Coop.isLocalBody(St.eventChar(spec, args)) then St.sendEvent(i, Coop.myId(), args) end
        end
        return orig(...)
      end
      St.markKind(w, orig, "ev")
      tbl[spec[2]] = w
    end
  end
end

function St.onEvent(peer, f)
  local i, origin = tonumber(f[2]), tonumber(f[3])
  local spec = i and St.EVENTS[i]
  if not spec or origin == Coop.myId() then return end
  local args = {n = #f - 3}
  for k = 4, #f do args[k - 3] = dec(f[k]) end
  if Coop.isHost() then
    -- From a client: only the holder of the character may report its power.
    if not Coop.heldBy(St.eventChar(spec, args), peer) then return end
    St.sendEvent(i, origin, args)   -- to every client (the origin skips it)
  end
  local tbl = _G[spec[1]]
  local fn = tbl and tbl[spec[2]]
  if type(fn) ~= "function" then return end
  if spec.once then tbl[spec[2]] = nil end
  Coop.log("story: " .. spec[1] .. "." .. spec[2] .. " from peer " .. tostring(origin))
  St.fromNet = true
  local ok, err = pcall(fn, unpack(args, 1, args.n))
  St.fromNet = false
  if not ok then Coop.log("story: event error: " .. tostring(err)) end
end

-- Client: watch the variables a local power sets and pass changes to the host.
function St.watchVars()
  St.varSeen = St.varSeen or {}
  for name, char in pairs(St.VARS) do
    local v = Game.Get(name)
    if v ~= St.varSeen[name] then
      St.varSeen[name] = v
      if Coop.isLocalBody(char) then Net.CoopSend(0, 1, "gv|" .. name .. "|" .. tostring(v)) end
    end
  end
end

------------------------------------------------------------------------------
-- rom_caldarium fire (AreaTriggers.EnterFireArea): only Delgado survives the flames; any
-- other body that walks in burns. Vanilla burns "the player" (UsrEntity(0)) on every machine
-- that runs the trigger, so in a session it killed the wrong bodies everywhere. Now the body
-- that entered burns, on the machine that controls it (its owner; the host for AI bodies),
-- and Delgado's burn damage runs where Delgado is controlled.
------------------------------------------------------------------------------

-- This machine controls the body: it is its own, or it is AI-held and this is the host.
function St.controls(name)
  if Coop.isLocalBody(name) then return true end
  return Coop.isHost() and Coop.ownerOf(name) == nil
end

function St.installFire()
  local at = AreaTriggers
  if not at or not at.EnterFireArea or St.fireHooked == at then return end
  St.fireHooked = at
  local orig = at.EnterFireArea
  at.EnterFireArea = function(TriggerName, Playerid, ExtraData)
    if not Coop.inSession() then return orig(TriggerName, Playerid, ExtraData) end
    local name = CoopWorld and CoopWorld.replaying and CoopWorld.replayTriggered or Game.GetTriggeredEntity(Playerid)
    if Coop.isHost() then at.StartSoloMision() end
    if not name or not St.controls(name) then return end
    if name ~= "Delgado" then
      Coop.log("story: " .. name .. " walked into the fire")
      Game.AddScheduledFunc(Game.GetTime() + 0.5, "PlayerBurnOnFire", "CoopStory.burn", name)
    else
      Game.AddScheduledFunc(Game.GetTime() + 0.5, "DelgadoBurnDamage", "AreaTriggers.DelgadoBurnDamage", TriggerName)
    end
  end
end

function St.burn(name)
  local e = Game.GetEntity(name)
  if e and St.controls(name) then e.Life = 0 end
end

------------------------------------------------------------------------------
-- Story takes a character away: Jones possessed in sum_ziggurat_01 (marked unavailable in
-- Team.UnavaliablePlayers, then walked off by the AI). Vanilla switches "the player" out of
-- it by script; a remote player holding it is moved by the host to a free body, or becomes
-- a spirit when there is none (coop_spirit.lua). Tutorial locks also use
-- UnavaliablePlayers but only limit single-player switching: humans keep those bodies.
--   evict|<char>|<new char or "">   host -> the holder
------------------------------------------------------------------------------

St.EVICT = {["levels/sum_ziggurat_01"] = {Jones = true}}

function St.taken(name)
  local lv = St.EVICT[Coop.level]
  return lv ~= nil and lv[name] == true and Team and Team.UnavaliablePlayers and Team.UnavaliablePlayers[name] == true
end

function St.freeBody(except)
  for _, name in ipairs(CoopMenu and CoopMenu.CHAR_ORDER or Coop.SQUAD) do
    local e = Game.GetEntity(name)
    if name ~= except and e and (e.Life or 0) > 0 and e.Active ~= 0 and e.bActive ~= false and
       Coop.owners[name] == nil and not (Team.UnavaliablePlayers and Team.UnavaliablePlayers[name]) then
      return name
    end
  end
end

function St.evictCheck()
  if not St.EVICT[Coop.level] then return end
  for name in pairs(St.EVICT[Coop.level]) do
    if St.taken(name) and Coop.isRemoteOwned(name) then
      local peer = Coop.owners[name]
      Coop.owners[name] = nil
      local target = St.freeBody(name)
      if target then Coop.owners[target] = peer end
      Coop.broadcastOwners()
      Net.CoopSend(Coop.peerOf(peer), 1, "evict|" .. name .. "|" .. (target or ""))
      Coop.log("story: " .. name .. " is taken by the story; peer " .. peer .. " -> " .. tostring(target))
    end
  end
end

function St.onEvict(f)
  local name, target = f[2], f[3]
  -- This machine's split screen player (coop_split.lua).
  if CoopSplit and CoopSplit.on and CoopSplit.char == name then
    CoopSplit.moveOut(target ~= "" and target or nil)
    return
  end
  if Coop.localChar() ~= name then return end
  Coop.log("story: the story takes " .. name .. ", moving to " .. (target ~= "" and target or "spirit"))
  if target and target ~= "" and Team and Team.SwitchSoldier then
    Coop.cfg.char = target
    Team.SwitchSoldier(name, target)
  end
end

-- cru_chapel: the squad gathers around Maltheus; AI on/off and moves apply to AI bodies only
-- (a remote player's body is driven by its owner).
function St.installChapel()
  if Coop.level ~= "levels/cru_chapel" or not MapInit or not MapInit.MemberOnOff or St.chapelHooked == MapInit then return end
  St.chapelHooked = MapInit
  local orig = MapInit.MemberOnOff
  MapInit.MemberOnOff = function(name, ...)
    if Coop.inSession() and Coop.isRemoteOwned(name) then return end
    return orig(name, ...)
  end
end

function St.update()
  St.installWalks()
  St.installAs()
  St.installEvents()
  St.installFire()
  St.installChapel()
  if Coop.isHost() then
    St.installFirstBorn()
    if Coop.frame % 20 == 0 then St.evictCheck() end
  end
  if Coop.isClient() then
    St.clientWalks()
    St.watchVars()
  end
end
