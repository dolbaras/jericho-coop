-- Jericho co-op: downed players and revives (owner's rule: only Rawlings revives, as in
-- the original game).
--
-- Vanilla: a downed player is moved into another living squad member after a delay
-- (Team.CheckGameOver); with nobody left the game is over. Rawlings (AI or player) revives
-- downed bodies (Team.CurePlayer -> Team.RevivePlayer). Team.CanCure only accepts bodies
-- held by AI.
--
-- Co-op:
--   * A downed body is downed on every machine (its puppet is put into agony), so Rawlings
--     wherever he runs can see and revive it.
--   * A revive done on a machine that does not own the body is sent to its owner:
--       revive|name    to the host from clients, to the owner from the host
--   * A downed player moves only into a free living body (one no other human holds). With
--     none free they stay down and wait for Rawlings; there is no local game over.
--   * The host ends the game when every human is down and no free living body is left:
--       gameover|      host -> clients; the host then runs the normal checkpoint reload.

CoopTeam = {}
local T = CoopTeam
-- Bodies a story keeps down on purpose (Rawlings shot in wwii_pillboxes, coop_splits G4):
-- their player stays in them instead of moving to another body.
T.holdDowned = {}

local function fromHost(fn, ...)
  Coop.fromHost = true
  local ok, a = pcall(fn, ...)
  Coop.fromHost = false
  if not ok then Coop.log("team error: " .. tostring(a)) end
  return a
end

-- Revive a body this machine owns, bypassing the "AI bodies only" rule of Team.CanCure.
function T.reviveLocal(e)
  local origCan = Team.CanCure
  Team.CanCure = function(obj) return Team.IsPlayerDead(obj.Name) end
  local ok = fromHost(T.origRevive, e)
  Team.CanCure = origCan
  Coop.log("revived " .. e.Name .. " -> " .. tostring(ok))
end

function T.isLocallyOwned(name)
  local o = Coop.ownerOf(name)
  if Coop.isHost() then return o == nil or Coop.isMine(o) end
  return Coop.isMine(o)
end

function T.install()
  if T.installed or not Team or not Team.RevivePlayer then return end
  T.installed = true

  T.origRevive = Team.RevivePlayer
  Team.RevivePlayer = function(obj, ...)
    local r = T.origRevive(obj, ...)
    if r and obj and not Coop.fromHost and not T.isLocallyOwned(obj.Name) then
      local owner = Coop.ownerOf(obj.Name)
      local to = Coop.isHost() and Coop.peerOf(owner) or 0   -- (a split screen player 2: its machine)
      Net.CoopSend(to, 1, "revive|" .. obj.Name)
      Coop.log("revive of " .. obj.Name .. " sent to peer " .. tostring(to))
    end
    return r
  end

  -- Vanilla switches the downed player into the next living soldier or ends the game.
  local origCheck = Team.CheckGameOver
  Team.CheckGameOver = function(name, valuez)
    local usr = Game.GetEntity(name)
    if not usr or usr.UsrControl ~= 0 or usr.Life > 0 then return origCheck(name, valuez) end
    if T.holdDowned[name] then
      Coop.log("downed: " .. name .. " is held down by the story")
      return
    end
    local order = {"Black", "Church", "Rawlings", "Jones", "Cole", "Delgado"}
    if Team.isWithTheTeam() then
      for _, other in ipairs(order) do
        local e = Game.GetEntity(other)
        if other ~= name and e and e.Life > 0 and not Coop.isRemoteOwned(other)
           and Team.SwitchSoldier(name, other) then
          Coop.log("downed: " .. name .. " -> moved into " .. other)
          return
        end
      end
    end
    Coop.log("downed: " .. name .. " waits for Rawlings")
    T.down = true
  end

  -- On clients only the host may end the game.
  if Coop.isClient() then
    T.origGameOver = Team.GameOver
    Team.GameOver = function(...)
      if Coop.fromHost then return T.origGameOver(...) end
    end
  end
end

-- Every frame: puppets follow their owner's downed/alive state.
function T.syncPuppetLife(e, st)
  if not st.life then return end
  if st.life <= 0 and e.Life > 0 then
    e.Invulnerable = 0
    e.Life = 0
  elseif st.life > 0 and e.Life <= 0 and Team.IsPlayerDead(e.Name) then
    -- The owner was revived on its machine.
    fromHost(T.origRevive, e)
  elseif st.life > 0 and e.Life > 0 and math.abs(e.Life - st.life) >= 1 then
    -- Alive: the owner's life, so Rawlings' heal and his curse's life feed see who is hurt.
    e.Life = st.life
  end
end

-- Host, once a second: game over when every human is down and no free body is alive.
function T.checkWipe()
  if not Coop.isHost() then return end
  local humans, down = 0, 0
  for name, peer in pairs(Coop.owners) do
    local e = Game.GetEntity(name)
    local st = Coop.remote[name]
    local life = peer == 0 and e and e.Life or (st and st.life) or (e and e.Life) or 0
    humans = humans + 1
    if life <= 0 then down = down + 1 end
  end
  if humans == 0 or down < humans then return end
  for _, name in ipairs(Coop.SQUAD) do
    local e = Game.GetEntity(name)
    if e and e.Life > 0 and Coop.ownerOf(name) == nil then return end
  end
  if T.gameOverSent then return end
  T.gameOverSent = true
  Coop.log("team wipe: game over")
  Net.CoopSend(-1, 1, "gameover|")
  Team.GameOverValue = true
  local usr = Game.UsrEntity(0)
  Team.GameOver(usr and usr.Name == "Ross")
end

function T.onMessage(peer, f)
  local kind = f[1]
  if kind == "revive" then
    local e = Game.GetEntity(f[2] or "")
    if not e then return true end
    if Coop.isHost() and not T.isLocallyOwned(e.Name) then
      Net.CoopSend(Coop.peerOf(Coop.ownerOf(e.Name)), 1, "revive|" .. e.Name)   -- forward to the owner
    elseif e.UsrControl == 0 then
      T.reviveLocal(e)
      T.down = false
    else
      fromHost(T.origRevive, e)
    end
    return true
  elseif kind == "time" then
    local x = tonumber(f[2]) or 1
    if T.origSetTime then T.applyTime(x) end
    if Coop.isHost() then Net.CoopSend(-1, 1, "time|" .. x) end
    return true
  elseif kind == "gameover" and Coop.isClient() then
    Coop.log("host: game over")
    Team.GameOverValue = true
    local usr = Game.UsrEntity(0)
    fromHost(Team.GameOver, usr and usr.Name == "Ross")
    return true
  end
  return false
end

------------------------------------------------------------------------------
-- Time speed (owner's decision): Cole's time power and Black's ghost bullet slow the
-- world for everyone, but every human-held body is compensated (TimeSpeed = 1/x, as Cole's
-- own body and the bullet are in vanilla), so only enemies and AI slow down. The switch
-- soul-flight slows only its own camera; the world keeps running.
--   time|x     client -> host (a client used a power), host -> clients (apply)
------------------------------------------------------------------------------

function T.compensate(x)
  T.updateCompensation()
end

-- Every tick (from the fork MAK-PIVO/jericho-coop): human-held bodies against the world's
-- real speed (Game.GetTimeSpeed). The game often brings time back by itself (Game.SetTimeFade
-- after the melee shock, 0.25 -> 1 in 0.2 s, weapons.lua FP_HitMeleeTimeShock), never calling
-- SetTimeSpeed(1): a one-off 1/x left the host's player running at 4x after a melee hit.
--   * a shared power (Cole's loop, Black's bullet; T.time < 1): every human body keeps
--     normal speed, as the power's owner does in vanilla;
--   * any other slowdown (melee shock, scenes) is this machine's own: its player slows
--     with the world as in vanilla, other players' puppets keep their speed;
--   * normal time: every body we touched goes back to 1.
T.compensated = T.compensated or {}
function T.updateCompensation()
  local ok, s = pcall(Game.GetTimeSpeed)
  s = ok and tonumber(s) or 1
  local shared = (T.time or 1) < 1
  for name in pairs(Coop.owners or {}) do
    local e = Game.GetEntity(name)
    if e then
      local want = 1
      if s > 0 and s < 0.999 and (shared or not Coop.isLocalPlayer(name)) then want = 1 / s end
      if want ~= 1 or T.compensated[name] then
        if math.abs((tonumber(e.TimeSpeed) or 1) - want) > 0.001 then e.TimeSpeed = want end
        T.compensated[name] = want ~= 1 or nil
      end
    end
  end
end

function T.applyTime(x)
  T.origSetTime(x)
  T.compensate(x)
  T.time = x
end

function T.installTime()
  if T.timeInstalled or not Game.SetTimeSpeed then return end
  T.timeInstalled = true
  T.origSetTime = Game.SetTimeSpeed
  Game.SetTimeSpeed = function(x)
    if not Coop.inSession() or Coop.fromHost then return T.origSetTime(x) end
    local info = debug.getinfo(2, "S")
    local src = string.lower(info and info.source or "")
    if string.find(src, "menu/menu") and x == 0 then
      -- Pause menu: the world goes on for everyone (coop_session.lua).
      return
    end
    if string.find(src, "chars/team") then
      -- Switch soul-flight: slow only the flight camera.
      local cam = Game.GetEntity("Cameraman")
      if cam and x < 1 then cam.TimeSpeed = x end
      return
    end
    if string.find(src, "threadscole") or string.find(src, "threadsblack") then
      if Coop.isHost() then
        T.applyTime(x)
        Net.CoopSend(-1, 1, "time|" .. x)
      else
        Net.CoopSend(0, 1, "time|" .. x)
        T.applyTime(x)
      end
      Coop.log("shared time speed " .. x .. " from " .. src)
      return
    end
    -- Anything else (melee shock, saves, scenes) stays local; on the host it slows the
    -- simulation; other players' puppets keep their speed (T.updateCompensation).
    T.origSetTime(x)
  end
end

------------------------------------------------------------------------------
-- Downed and waiting for Rawlings (owner's rule): the camera follows the nearest living
-- partner. A player waits only when every living body is held by a human, so the partner
-- is another player. Only MainCam's targets change (the old mod's spectator camera); they
-- come back once this player is up again or in another body.
------------------------------------------------------------------------------
function T.partner(usr)
  local best, bestD
  for name in pairs(Coop.owners or {}) do
    local e = name ~= usr.Name and Game.GetEntity(name)
    if e and e.Life > 0 then
      local d = (e.Pos - usr.Pos):mod()
      if not bestD or d < bestD then best, bestD = e, d end
    end
  end
  return best
end

function T.watchPartner()
  local usr = Game.UsrEntity(0)
  local cam = Game.GetCam(0) == "MainCam" and Game.GetEntity("MainCam")
  if T.down and usr and usr.Life <= 0 and cam then
    local p = T.partner(usr)
    if p and cam.MainTarget ~= p.Name then
      T.watchSaved = T.watchSaved or {main = cam.MainTarget, target = cam.Target}
      cam.MainTarget, cam.Target = p.Name, p.Name
      Coop.log("downed: camera follows " .. p.Name)
    end
  elseif T.watchSaved and not (T.down and usr and usr.Life <= 0) then
    local back = Game.GetEntity("MainCam")
    if back then back.MainTarget, back.Target = T.watchSaved.main, T.watchSaved.target end
    T.watchSaved = nil
    T.down = false
    Coop.log("downed: camera back on " .. tostring(usr and usr.Name))
  end
end

function T.update()
  T.install()
  T.installTime()
  T.updateCompensation()
  T.watchPartner()
  if Coop.frame % 20 == 0 then T.checkWipe() end
end
