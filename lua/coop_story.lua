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
  elseif not on and e and e.oAI and Coop.isRemoteOwned(name) then
    -- (the AI walked on until the player's next state came, audit 0.2.2 A16)
    e.oAI.bEnable = false
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
      local walk = function()
        if remote then St.drive(nameEnt, true) end
        local done = function(ent, ...)
          if remote then St.drive(nameEnt, false) end
          Net.CoopSend(-1, 1, "sdone|" .. nameEnt)
          if funcExec then return funcExec(ent, ...) end
        end
        return orig(nameEnt, pos, posEnd, done, velocity)
      end
      -- A step that only turns a human's body toward something (its destination is where the
      -- body stands: wwii_pillboxes' conversation looks at each speaker) is no turn for its
      -- player and no AI drive: the player looks themselves, the story goes on at once.
      if remote and St.isLookAt(nameEnt, pos) then
        Coop.log("story: " .. nameEnt .. " looks (left to its player)")
        Net.CoopSend(-1, 1, "sdone|" .. nameEnt)
        if funcExec then
          local ok, err = pcall(funcExec, Game.GetEntity(nameEnt))
          if not ok then Coop.log("story: arrival of " .. nameEnt .. " error: " .. tostring(err)) end
        end
        return
      end
      -- A body a human holds: its player's turn first (St.startTurn), the walk if they do not.
      -- (only another machine's body: a step that walks "the player" runs on every machine for
      -- its own body, and the host's own body walks as before)
      if remote and St.startTurn(nameEnt, pos, posEnd, funcExec, walk) then return end
      return walk()
    end
    -- Client (story code replayed, or run by MapInit): the arrival function waits for the
    -- host's sdone. This machine's own body walks here only if the host does not walk it
    -- (a "the player walks" step, run on every machine): decided after WAIT seconds.
    if nameEnt == Coop.localChar() and St.isLookAt(nameEnt, pos) then
      -- (its own body only turns: no AI walk under the player, owner's Steam test)
      St.orient(nameEnt, posEnd)
      if funcExec then
        local ok, err = pcall(funcExec, Game.GetEntity(nameEnt))
        if not ok then Coop.log("story: arrival of " .. nameEnt .. " error: " .. tostring(err)) end
      end
      return
    end
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
St.LOOK_AT = 120      -- a walk whose destination is this close to the body: a look-at
St.FAR_WALK = 1500    -- this machine's own body walked by its AI from farther: starts nearer

function St.isLookAt(name, pos)
  local e = Game.GetEntity(name)
  if not e or not pos or not pos.x then return false end
  local dx, dz = pos.x - e.Pos.x, pos.z - e.Pos.z
  return dx * dx + dz * dz < St.LOOK_AT * St.LOOK_AT
end

function St.orient(name, target)
  local e = Game.GetEntity(name)
  if not e or not target or not target.x then return end
  local d = target - e.Pos
  local yaw = math.deg(math.atan2(-d.x, -d.z))
  e.Ang = V3D(0, yaw, 0)
  e.ViewAng = V3D(0, yaw, 0)
end

function St.clientWalks()
  local now = Net.CoopTime()
  for name, p in pairs(St.pending) do
    local turned = St.turnFor and St.turnFor[name] and now - St.turnFor[name] < St.TURN_TIME + 5
    if turned then p.started = true end
    if p.mine and not p.started and now - p.t > St.WAIT and not Coop.storyDriven[name] then
      p.started = true
      St.pending[name] = nil
      -- A step that walks "the player" runs on every machine for its own body; this player may
      -- be anywhere: a long AI drag across the level under them becomes a short walk.
      local e, dest = Game.GetEntity(name), p.args[2]
      if e and dest and dest.x then
        local dx, dz = dest.x - e.Pos.x, dest.z - e.Pos.z
        if dx * dx + dz * dz > St.FAR_WALK * St.FAR_WALK then
          e.Pos = dest
          pcall(Game.SetOnFloor, name)
          Coop.log(string.format("story: my body put at its walk's end (%.0f away)", math.sqrt(dx * dx + dz * dz)))
        end
      end
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
  if f[1] == "sturn" and Coop.isClient() then
    local x, y, z, secs = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]) or 0
    -- (only this character's turn: another's start or end leaves ours alone)
    local mine = St.myTurn and St.myTurn.name == f[2]
    if mine then St.myTurn = nil end
    if secs > 0 and x and Coop.isLocalBody(f[2]) then
      St.myTurn = {name = f[2], pos = V3D(x, y, z), deadline = Net.CoopTime() + secs}
      -- The same step replayed here would walk this body by its AI in a moment: the player
      -- walks it (its arrival function still runs at the host's sdone).
      local p = St.pending[f[2]]
      if p then p.started = true end
      St.turnFor = St.turnFor or {}
      St.turnFor[f[2]] = Net.CoopTime()
      -- A replayed step may have locked this body ("the player" stands still for the walk):
      -- the turn is the player's to walk (rom_chamber, sum_ziggurat_04, alk_bunker_01...).
      local u = Game.GetEntity(f[2])
      if u and u.IgnoreUsrControl == 1 and not Coop.storyDriven[f[2]] then
        u.IgnoreUsrControl = 0
        Coop.log("story: lock on my body lifted for my turn")
      end
    end
    if secs <= 0 and mine then St.clearTurnText() end
    return true
  end
  if f[1] == "sturndone" and Coop.isHost() then
    if St.turns[f[2] or ""] and Coop.heldBy(f[2], peer) then St.finishTurn(f[2], "its player") end
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
-- clientRun: on clients run this function instead (given the original and the arguments).
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
  -- wwii_pillboxes: the player who came to the vantage point is walked until they see the
  -- psychic commander, then the enemies come. Replayed on a client it locked the client's own
  -- body and dragged it there wherever it was (re-steered every 0.1 s): only the radio line.
  {"MapInit", "StartLichtScene", level = "wwii_pillboxes", clientRun = function()
    for _, n in ipairs({{"Church", "0"}, {"Delgado", "2"}, {"Rawlings", "0"}}) do
      local e = Game.GetEntity(n[1])
      if e and (e.Life or 0) > 0 then
        TeamTalk.RadioTalkDelayed(n[1], "View_EnemyHigh", nil, n[2], 0, 1, 5)
        return
      end
    end
  end},
  -- sum_ziggurat_01: Jones is possessed; vanilla switches "the player" out of Jones on every
  -- machine a few seconds later (outside the replay). The host moves Jones's player out.
  {"MapInit", "StartJonesPossession", level = "sum_ziggurat_01", clientNoSwitch = true},
  -- alk_bunker_01: Ross walks to Rawlings with "the player" locked until he arrives; on a
  -- client that locked its own body. And Rawlings is put at his start, a client's too.
  {"MapInit", "GoToRawlings", level = "alk_bunker_01", clientRun = function()
    AIGen.GoAndAction("Ross", V3D(500, 130, -1000), V3D(652, 33, -850), MapInit.OnRossArrived, 0.5)
  end},
  {"MapInit", "OnRossArrived", level = "alk_bunker_01", clientRun = function(orig, ...)
    local r = Coop.isLocalBody("Rawlings") and Game.GetEntity("Rawlings")
    local keep = r and r.Pos
    local res = {pcall(orig, ...)}
    if keep then r.Pos = keep end
    if not res[1] then error(res[2], 0) end
    return unpack(res, 2)
  end},
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
        if spec.clientRun and Coop.isClient() then return spec.clientRun(orig, ...) end
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

------------------------------------------------------------------------------
-- A story action of a body a human holds (Black's telekinesis on the prologue's rubble...):
-- the story walked that body there by the host's AI and did it for the player, whose own
-- power did nothing (owner's Steam test, 0.2.1). Now its player gets the turn: go to the spot
-- and use a power there (or just stand there a moment); the story then goes on as after the
-- AI's walk. Only if they do not within TURN_TIME does the AI walk the body as before.
-- Lobby option "character actions" = "ai" keeps the old way.
--   sturn|<char>|x|y|z|<seconds>   host -> all (0 seconds: over)
--   sturndone|<char>               the body's machine -> host
------------------------------------------------------------------------------
St.TURN_TIME = 25
St.TURN_NEAR = 320
St.TURN_STAND = 2
St.turns = {}
St.TEXT = {
  en = {turn = "%s: go to the marked place (%d m) and use your power there\nor wait - the squad does it in %d s",
        here = "%s: use your power now (or wait a moment)"},
  ru = {turn = "%s: подойдите к месту (%d м) и примените там способность\nили ждите - отряд сделает это через %d с",
        here = "%s: примените способность (или подождите секунду)"},
}

function St.startTurn(name, pos, posEnd, funcExec, walk)
  if (Coop.cfg.actmode or "players") == "ai" or Coop.cfg.storyturn == false then return false end
  St.turns[name] = {pos = pos, posEnd = posEnd, func = funcExec, walk = walk,
                    deadline = Net.CoopTime() + St.TURN_TIME}
  Net.CoopSend(-1, 1, string.format("sturn|%s|%.0f|%.0f|%.0f|%d", name, pos.x, pos.y, pos.z, St.TURN_TIME))
  if name == Coop.localChar() then
    St.myTurn = {name = name, pos = pos, deadline = Net.CoopTime() + St.TURN_TIME}
  end
  Coop.log("story: " .. name .. "'s player gets the turn")
  return true
end

-- Host: the player did it (who), or the time is up (nil: the AI walks).
function St.finishTurn(name, who)
  local turn = St.turns[name]
  if not turn then return end
  St.turns[name] = nil
  Net.CoopSend(-1, 1, "sturn|" .. name .. "|0|0|0|0")
  if name == Coop.localChar() then
    St.myTurn = nil
    St.clearTurnText()
  end
  if who then
    Coop.log("story: " .. name .. "'s action done by " .. who)
    local ent = Game.GetEntity(name)
    Net.CoopSend(-1, 1, "sdone|" .. name)
    if turn.func and ent then
      local ok, err = pcall(turn.func, ent)
      if not ok then Coop.log("story turn error: " .. tostring(err)) end
    end
  else
    Coop.log("story: " .. name .. "'s player did not come, the AI walks")
    turn.walk()
  end
end

function St.clearTurnText()
  if St.turnText then
    St.turnText = nil
    pcall(Scorer.SetMsgText, "", 0)
  end
end

local function turnText(key, ...)
  local lang = Coop.lang()
  local s = string.format((St.TEXT[lang] or St.TEXT.en)[key], ...)
  return lang == "ru" and Coop.cp1251(s) or s
end

-- The body's own machine: the hint, and done once the body is there and uses a power (or
-- stands there a moment).
function St.updateMyTurn()
  local turn = St.myTurn
  if not turn then return end
  local now = Net.CoopTime()
  local u = Game.GetEntity(turn.name)
  if now > turn.deadline + 1 or not u or (u.Life or 0) <= 0 or Coop.storyDriven[turn.name] then
    St.myTurn = nil
    St.clearTurnText()
    return
  end
  local d = (u.Pos - turn.pos):mod2D()
  local who = Coop.charName and Coop.charName(turn.name) or turn.name
  if d > St.TURN_NEAR then
    turn.since = nil
    if Coop.frame % 10 == 0 then
      St.turnText = true
      pcall(Scorer.SetMsgText, turnText("turn", who, math.floor(d / 100 + 0.5),
        math.max(0, math.floor(turn.deadline - now))), Game.GetTime() + 2)
    end
    return
  end
  turn.since = turn.since or now
  if Coop.frame % 10 == 0 then
    St.turnText = true
    pcall(Scorer.SetMsgText, turnText("here", who), Game.GetTime() + 2)
  end
  local fp = u.FPSEntity and u.FPSEntity ~= "" and Game.GetEntity(u.FPSEntity)
  local fpa = fp and tostring(fp.Action) or ""
  local power = string.find(fpa, "Special") or string.find(fpa, "Spell") or string.find(fpa, "Hack") or
                string.find(fpa, "Ababanili") or string.find(fpa, "TK")
  if power or now - turn.since > St.TURN_STAND then
    St.myTurn = nil
    St.clearTurnText()
    if Coop.isHost() then
      St.finishTurn(turn.name, "its player")
    else
      Net.CoopSend(0, 1, "sturndone|" .. turn.name)
    end
  end
end

function St.update()
  St.installWalks()
  St.installAs()
  St.installEvents()
  St.installFire()
  St.installChapel()
  St.updateMyTurn()
  if Coop.isHost() then
    local now = Net.CoopTime()
    for name, turn in pairs(St.turns) do
      local e = Game.GetEntity(name)
      if now > turn.deadline or not e or (e.Life or 0) <= 0 or
         not (Coop.isRemoteOwned(name) or name == Coop.localChar()) then
        St.finishTurn(name, nil)
      end
    end
    St.installFirstBorn()
    if Coop.frame % 20 == 0 then St.evictCheck() end
  end
  if Coop.isClient() then
    St.clientWalks()
    St.watchVars()
  end
end
