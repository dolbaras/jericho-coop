-- Jericho co-op: powers seen by the other players. From the fork MAK-PIVO/jericho-coop
-- (MIT), adapted here for split screen players (a client's player 2 has owner id peer + P2).
--
-- Black's ghost bullet (scripts/thread/threadsblack.lua CreateGhostBullet): an entity
-- "GhostBullet" the owner steers every frame with their own input. Its hits already reach
-- the host (Weapons.DoDamage from the owner's body, coop_enemies.lua), the slowed world is
-- shared (coop_team.lua); the bullet itself was seen by its owner only. Now the owner sends
-- where it flies and every other machine shows a passive copy (no steering, no damage),
-- drawn between two received places like the players' bodies:
--   gb|<owner peer>|x|y|z|yaw|pitch|time   owner -> host -> everyone, every tick
--   gbe|<owner peer>                       the bullet is gone
--
-- Delgado's Ababanili (scripts/chars/ababanili.lua): a fire spirit each Delgado body has
-- (hidden until used); AbabaniliStart sends it at a target and its hits are dealt as
-- Delgado's (they reach the host like his shots). On the other machines Delgado's puppet
-- now sends its own spirit at the same target, the way the game's AI Delgado does
-- (oAI.ObjectiveDin), and calls it back when the owner does. That copy's hits only play
-- their sound: damage and burning stay with the owner's.
--   abby|<Delgado body>|<target>   owner -> host -> everyone: the spirit attacks
--   abby|<Delgado body>|           the spirit comes back
CoopPowers = CoopPowers or {}
local P = CoopPowers
P.copies = P.copies or {}   -- owner peer -> {name = visual bullet entity}

local function relay(data)
  if Coop.isHost() then Net.CoopSend(-1, 1, data) else Net.CoopSend(0, 1, data) end
end

-- Who tells the others about a Delgado body's spirit: the machine of its player, and the host for
-- the game's AI Delgado (its Shot1Init event runs AbabaniliStart there; the clients saw neither
-- spirit nor open arm of it).
local function tells(char)
  if P.replaying or not Coop.inSession() then return false end
  if Coop.isLocalPlayer(char.Name) then return true end
  return Coop.isHost() and Coop.ownerOf(char.Name) == nil
end

-- A puppet is not the one to start or call back its spirit: its Shot1Init event (frame 40) did,
-- next to the spirit the abby message sends (two spirits, and the AI call on a body whose AI is off).
local function puppetEvent(char)
  return char and Coop.inSession() and not P.replaying and Coop.isPuppet and Coop.isPuppet(char.Name)
end

------------------------------------------------------------------------------
-- Ghost bullet
------------------------------------------------------------------------------
function P.installBullet()
  if P.bulletInstalled or not ThreadsBlack or not ThreadsBlack.CreateGhostBullet then return end
  P.bulletInstalled = true
  local orig = ThreadsBlack.CreateGhostBullet
  ThreadsBlack.CreateGhostBullet = function(usr, ...)
    local o = orig(usr, ...)
    if o and usr and Coop.inSession() and Coop.isLocalPlayer(usr.Name) then
      P.myBullet = o.Name
      Coop.log("powers: ghost bullet " .. tostring(o.Name))
    end
    return o
  end
end

-- Owner, every tick: where the bullet is, or that it is gone.
function P.sendBullet()
  if not P.myBullet then return end
  local o = Game.GetEntity(P.myBullet)
  local me = Coop.myId() or 0
  if not o then
    P.myBullet = nil
    Net.CoopSend(Coop.isHost() and -1 or 0, 1, "gbe|" .. me)
    return
  end
  local p, a = o.Pos, o.Ang
  Net.CoopSend(Coop.isHost() and -1 or 0, 0, string.format("gb|%d|%.0f|%.0f|%.0f|%.1f|%.1f|%.3f",
    me, p.x, p.y, p.z, a.y, a.x, Net.CoopTime()))
end

function P.onBullet(peer, f, data)
  local owner = tonumber(f[2])
  if not owner or owner == Coop.myId() then return end
  if Coop.isHost() then
    if owner ~= peer then return end   -- only the bullet's owner reports it
    Net.CoopSend(-1, f[1] == "gb" and 0 or 1, data)
  end
  local key = "gb:" .. owner
  local copy = P.copies[owner]
  if f[1] == "gbe" then
    if copy then
      local e = Game.GetEntity(copy.name)
      if e then pcall(function() e:Del() end) end
      Coop.hist[key] = nil
      P.copies[owner] = nil
      Coop.log("powers: ghost bullet of peer " .. owner .. " gone")
    end
    return
  end
  local st = {x = tonumber(f[3]), y = tonumber(f[4]), z = tonumber(f[5]), yaw = tonumber(f[6]),
              pitch = tonumber(f[7]), rt = tonumber(f[8]), t = Net.CoopTime()}
  if not st.x then return end
  if not copy then
    local ok, e = pcall(Game.CreateEntity, "GhostBullet", "WithLife", V3D(st.x, st.y, st.z))
    if not ok or not e then
      Coop.log("powers: ghost bullet copy failed: " .. tostring(e))
      P.copies[owner] = {name = "", failed = true}
      return
    end
    -- A passive copy: nothing steers it, nothing hits it, it hits nothing.
    pcall(function()
      e.OnObjSlot = ""
      e.Invulnerable = 1
      e.bIgnoreCollision = true
      e.TimeSpeed = 10
    end)
    copy = {name = e.Name}
    P.copies[owner] = copy
    Coop.hist[key] = nil
    Coop.log("powers: ghost bullet of peer " .. owner .. " shown as " .. e.Name)
  end
  if copy.failed then return end
  Coop.pushState(key, st, Coop.TICK)
end

-- Every frame: the copies fly between the received places.
function P.frame(now)
  for owner, copy in pairs(P.copies) do
    local e = not copy.failed and Game.GetEntity(copy.name)
    local tg = e and Coop.puppetTarget("gb:" .. owner, now)
    if tg then
      e.Pos = V3D(tg.x, tg.y, tg.z)
      e.Ang = V3D(tg.pitch or 0, tg.yaw, 0)
    end
  end
end

------------------------------------------------------------------------------
-- Ababanili
------------------------------------------------------------------------------
function P.installAbby()
  if P.abbyInstalled or not Ababanili or not Ababanili.AbabaniliStart then return end
  P.abbyInstalled = true
  local origStart, origClose, origHit = Ababanili.AbabaniliStart, Ababanili.AbabaniliClose, Ababanili.AbabaniliHitTarget
  Ababanili.AbabaniliStart = function(name, ...)
    local char = Game.GetEntity(name)
    if char and char:IsType("FP") then char = Game.UsrEntity(char.id) end
    if puppetEvent(char) then
      P.guarded = (P.guarded or 0) + 1
      if P.guarded <= 3 then Coop.log("powers: " .. char.Name .. "'s own AbabaniliStart event dropped (puppet)") end
      return false
    end
    local abby = origStart(name, ...)
    if char and Coop.inSession() and not P.replaying and Coop.cfg.dev then
      Coop.log("powers: AbabaniliStart for " .. char.Name .. ": spirit " .. tostring(abby and abby.Name) .. ", tells " .. tostring(tells(char)))
    end
    if abby and char and tells(char) then
      local ok, tgt = pcall(function() return abby.oAI.oTarget.Name end)
      relay("abby|" .. char.Name .. "|" .. tostring(ok and tgt or ""))
    end
    return abby
  end
  Ababanili.AbabaniliClose = function(name, ...)
    local char = Game.GetEntity(name)
    if char and char:IsType("FP") then char = Game.UsrEntity(char.id) end
    if puppetEvent(char) then return end
    if char and tells(char) then
      relay("abby|" .. char.Name .. "|")
    end
    return origClose(name, ...)
  end
  -- A spirit sent for another player only shows: its owner's machine deals the damage.
  Ababanili.AbabaniliHitTarget = function(ent, tgt, ...)
    local d = Game.GetEntity("Delgado")
    if Coop.inSession() and d and not Coop.isLocalPlayer(d.Name) and Coop.ownerOf(d.Name) ~= nil then
      if tgt and tgt.SndPos then pcall(Sound.PlaySound, tgt.SndPos, "AbabaniliDamage", 0.25) end
      return
    end
    return origHit(ent, tgt, ...)
  end
end

-- The third-person arm opening of the release (Delgado's Shot1Init / DuckShot1Init), for a body
-- whose own action did not play it here (the owner's first-person arms did there, or the AI's
-- Shot1Init is already on its way from the host's state: CoopAnim.ONESHOT).
function P.armOpen(d)
  if Coop.cfg.abbyarm == false then return end
  local act = tostring(d.Action)
  if string.find(act, "^Shot1") or string.find(act, "^DuckShot1") then return end
  local want = string.find(act, "^Duck") and "DuckShot1Init" or "Shot1Init"
  local t = Net.CoopTime()
  if Coop.mirrorT and t - (Coop.mirrorT[d.Name] or -10) < 1.5 then return end
  local ok, cls = pcall(function() return Act.GetClass(d.ActCtrl ~= "" and d.ActCtrl or d.Name) end)
  if not ok or not cls or not cls:GetAct(want) then return end
  d.ForceAction = want
  Coop.mirrorT = Coop.mirrorT or {}
  Coop.mirrorT[d.Name] = t
  Coop.log("powers: " .. d.Name .. " opens his arm (" .. want .. ")")
end

function P.onAbby(peer, f, data)
  local name, tgt = f[2], f[3] or ""
  if Coop.isHost() then
    if not Coop.heldBy(name, peer) then return end
    Net.CoopSend(-1, 1, data)
  end
  if not name or Coop.isLocalPlayer(name) then return end
  local d = Game.GetEntity(name)
  if not d then return end
  P.replaying = true
  local ok, err = pcall(function()
    if tgt ~= "" and Game.GetEntity(tgt) then
      -- The AI path of AbabaniliStart takes the target from oAI.ObjectiveDin.
      local was = d.oAI and d.oAI.ObjectiveDin
      if d.oAI then d.oAI.ObjectiveDin = tgt end
      local abby = Ababanili.AbabaniliStart(name)
      if d.oAI then d.oAI.ObjectiveDin = was or "" end
      if abby then P.armOpen(d) end
    else
      Ababanili.AbabaniliClose(name)
    end
  end)
  P.replaying = false
  Coop.log("powers: " .. name .. "'s Ababanili " .. (tgt ~= "" and ("attacks " .. tgt) or "comes back") ..
    (ok and "" or (" error: " .. tostring(err))))
end

------------------------------------------------------------------------------
-- Powers that act on the world (2026-10-20). They ran on the caster's machine only: on a
-- client a telekinesis push, a burn or Church's rune moved, lit or held that client's copy
-- of an enemy, while the host's enemy, the real one, felt nothing. Now the caster reports
-- the effect and every other machine applies it to its own copy: the host's enemies are
-- pushed, burnt and held by the rune. Damage stays where it was: the caster's hits reach
-- the host as before, and the host still drops damage dealt in a puppet's name, so nothing
-- counts twice.
--   pw|bt|<Black>|<target>                         Black's telekinesis on one target
--   pw|cr|<Church>|<thread>                        Church's rune (blood / fire / world-wide ward)
--   pw|jt|<owner>|<target>|<x>|<y>|<z>|<use>      Jones' astral push (vector) or use of an object
--   pw|jp|<owner>|<target>                         Jones' pyrokinesis
------------------------------------------------------------------------------
local function send(...)
  relay(table.concat({"pw", ...}, "|"))
end

-- before(...), when given, runs before the power: false means it will not act here (Jones's
-- astral camera says CanTK/CanBurn 0), and then nothing is reported either (a client's no-op
-- pushed and lit the host's enemy: network test 0.2.1).
local function wrapPower(tbl, fname, after, before)
  local t = _G[tbl]
  -- Checked every tick: a character's script table is built again when a player takes that
  -- character, which drops a wrapper put on the old one.
  if not t or type(t[fname]) ~= "function" or t[fname] == P["w_" .. tbl .. fname] then return end
  local orig = t[fname]
  local w
  w = function(...)
    -- (split screen wraps the same functions; wrapped again around that, one use is
    -- reported once: the inner wrapper only calls through)
    if P.inPower then return orig(...) end
    local acts = true
    if before then
      local ok, v = pcall(before, ...)
      acts = ok and v ~= false
    end
    P.inPower = true
    local r = {pcall(orig, ...)}
    P.inPower = nil
    if not r[1] then error(r[2], 0) end
    if acts and Coop.inSession() and not P.replaying then
      local ok, err = pcall(after, ...)
      if not ok then Coop.log("powers: " .. tbl .. "." .. fname .. " report error: " .. tostring(err)) end
    end
    return unpack(r, 2, table.maxn(r))
  end
  t[fname] = w
  P["w_" .. tbl .. fname] = w
  P["o_" .. tbl .. fname] = orig
end

function P.installWorldPowers()
  wrapPower("Black", "ApplyTelePower", function(ent, tgt)
    if ent and tgt and Coop.isLocalPlayer(ent.Name) then send("bt", ent.Name, tgt.Name) end
  end)
  wrapPower("ThreadsChurch", "ActivatePower", function(name)
    local c = Game.GetEntity(name)
    if c and Coop.isLocalPlayer(name) then send("cr", name, tostring(c.uData.Thread or "")) end
  end)
  wrapPower("Jones", "PressTelekinesis", function(ownerName, linkedName, targetName)
    local owner, linked, tgt = Game.GetEntity(ownerName), Game.GetEntity(linkedName), Game.GetEntity(targetName)
    if not (owner and tgt and linked and Coop.isLocalPlayer(ownerName)) then return end
    if tgt.bUseOnTK then send("jt", ownerName, targetName, 0, 0, 0, 1) return end
    local f = 1 - (tgt.Pos - linked.Pos):mod() / Jones.TKRange
    if f <= 0 or f >= 1 then return end
    local v = (tgt.Pos - linked.Pos):norm() * (Jones.TKPower * 5 * f)
    send("jt", ownerName, targetName, string.format("%.1f", v.x), string.format("%.1f", v.y), string.format("%.1f", v.z), 0)
  end, function()
    local cam = Game.GetEntity("AstralCam")
    return cam ~= nil and cam:CanTK() ~= 0
  end)
  wrapPower("Jones", "PressPyrokinesis", function(ownerName, linkedName, targetName)
    -- (no target: the body the projection is in burns, and the burn report carries that)
    if Coop.isLocalPlayer(ownerName) and targetName and targetName ~= "" then send("jp", ownerName, targetName) end
  end, function()
    local cam = Game.GetEntity("AstralCam")
    return cam ~= nil and cam:CanBurn() ~= 0
  end)
end

------------------------------------------------------------------------------
-- Rawlings (2026-10-21, scripts/weapons/weaponsrawlings.lua). His powers act on others:
-- Vlad's curse marks an enemy (any squad hit on it then feeds life to a teammate,
-- Weapons.DistributeLife inside the host's damage), Chamanic calm eases a teammate's powers,
-- the heal hands and the ghost heal restore a teammate's life. They ran on the caster's
-- machine only: a client's curse marked its own copy of the enemy, so the host's damage
-- fed nobody, and a heal or a life feed raised the Life of a puppet, which the owner's
-- state put back at once. Now the caster reports the power, the machine that controls the
-- target applies it (its owner; the host for enemies and AI bodies) and every machine shows
-- the aura. The first-person hand effects stay with the caster (no hands on a puppet).
--   pw|rc|<Rawlings>|<enemy>         Vlad's curse
--   pw|rm|<Rawlings>|<teammate>      Chamanic calm
--   pw|rh|<Rawlings>|<teammate>      heal (a downed body comes back through revive|)
--   rl|<enemy>|<teammate>|<amount>   host -> clients: a hit on a cursed enemy fed a teammate
------------------------------------------------------------------------------
P.CURSE_AURA = "EFFECT_RAGDOLL\183RAWLINGSCURSEAURA"

-- This machine casts for that body: its player, or the host for an AI-held one.
function P.casts(name)
  return Coop.isLocalPlayer(name) or (Coop.isHost() and Coop.ownerOf(name) == nil)
end

function P.installRawlings()
  wrapPower("WeaponsRawlings", "Curse", function(ent, tgt)
    if ent and tgt and P.casts(ent.Name) then send("rc", ent.Name, tgt.Name) end
  end)
  wrapPower("WeaponsRawlings", "Calm", function(ent, tgt)
    if ent and tgt and P.casts(ent.Name) then send("rm", ent.Name, tgt.Name) end
  end)
  wrapPower("WeaponsRawlings", "Cure", function(me, tgt)
    if me and tgt and P.casts(me.Name) then send("rh", me.Name, tgt.Name) end
  end)
  if Coop.isHost() then
    -- Keep the teammate DistributeLife picks.
    if Weapons.ChooseLifeReceipt and Weapons.ChooseLifeReceipt ~= P.chooseW then
      local orig = Weapons.ChooseLifeReceipt
      P.chooseW = function(...)
        local r = orig(...)
        P.lastReceipt = r
        return r
      end
      Weapons.ChooseLifeReceipt = P.chooseW
    end
    wrapPower("Weapons", "DistributeLife", function(source, amount)
      local r = P.lastReceipt
      P.lastReceipt = nil
      if source and r and amount then
        Net.CoopSend(-1, 1, string.format("rl|%s|%s|%d", source.Name, r.Name, math.ceil(amount * 0.1)))
      end
    end)
  end
end

function P.curse(t)
  t.uData.IsCursed = true
  local fx = "RawlingsCurseAura_" .. t.Name
  if not FX.IsEffect(P.CURSE_AURA, fx) then FX.BeginEffect(P.CURSE_AURA, fx, t.Name) end
  if Coop.isHost() then Soldier.DoHitStrong(t) end
  Game.AddScheduledFunc(Game.GetTime() + (WeaponsRawlings.CurseDuration or 10), "Uncurse", "WeaponsRawlings.Uncurse", t.Name)
end

-- Client: a teammate fed by a cursed enemy's hit on the host. Its owner adds the life.
function P.onLifeFeed(f)
  local source, r, amount = Game.GetEntity(f[2] or ""), Game.GetEntity(f[3] or ""), tonumber(f[4]) or 0
  if not r then return end
  if Coop.isLocalPlayer(r.Name) and r.Life > 0 then
    r.Life = math.min(r.Life + amount, r.oActCtrl.oActClass.Life)
  end
  if source then pcall(Rawlings.DoVladCurseShotFX, source.Name) end
  pcall(Rawlings.DoVladCurseAlliedFX, r.Name)
  Coop.log("powers: curse fed " .. amount .. " to " .. r.Name .. " life=" .. tostring(r.Life))
end

-- Fire set by this player (Cole's firestorm shots, Delgado's flames, pyrokinesis...): every
-- 5 ticks, enemies burning in this player's name are reported once per burn, and the other
-- machines light their copy for the same time (damage stays with the caster's hits).
--   pw|burn|<caster>|<target>|<time>|<delay>|<attenuation>
P.burning = P.burning or {}
function P.reportBurns()
  if Coop.frame % 5 ~= 0 then return end
  if not Coop.localChar() then return end
  local e = Game.GetFirst()
  while e ~= nil do
    if e:IsType("WalkChar") and e.TgType == "red" and e.Life > 0 then
      local t = tonumber(e.FireRemainTime) or 0
      local me = e.Pyromaniac
      -- (set on fire by this machine's player 1 or split screen player 2)
      if t > 0 and type(me) == "string" and Coop.isLocalPlayer(me) then
        if not P.burning[e.Name] then
          P.burning[e.Name] = true
          send("burn", me, e.Name, string.format("%.2f", t), string.format("%.2f", tonumber(e.FireDelayTime) or 0),
            string.format("%.2f", tonumber(e.FireAtenuationFactor) or 0))
        end
      else
        P.burning[e.Name] = nil
      end
    end
    e = Game.GetEntity(e.NextInSlot)
  end
end

function P.onPower(peer, f, data)
  local kind, caster = f[2], f[3]
  if not caster or Coop.isLocalPlayer(caster) then return end
  if Coop.isHost() then
    if not Coop.heldBy(caster, peer) then return end
    Net.CoopSend(-1, 1, data)
  end
  local c = Game.GetEntity(caster)
  if not c then return end
  P.replaying = true
  local ok, err = pcall(function()
    if kind == "bt" then
      local t = Game.GetEntity(f[4] or "")
      if t and P.o_BlackApplyTelePower then P.o_BlackApplyTelePower(c, t) end
    elseif kind == "cr" then
      c.uData.Thread = (f[4] ~= "" and f[4]) or nil
      if P.o_ThreadsChurchActivatePower then P.o_ThreadsChurchActivatePower(caster) end
    elseif kind == "jt" then
      local t = Game.GetEntity(f[4] or "")
      if t and f[8] == "1" then
        if Coop.isHost() then t:UseMe(c) end   -- an object used by telekinesis: the host's story
      elseif t then
        t:ForcePush(t.Name, V3D(tonumber(f[5]) or 0, tonumber(f[6]) or 0, tonumber(f[7]) or 0), caster)
      end
    elseif kind == "burn" then
      local t = Game.GetEntity(f[4] or "")
      local time = tonumber(f[5]) or 0
      if t and (tonumber(t.FireRemainTime) or 0) < time then
        t.FireRemainTime, t.FireDelayTime, t.FireAtenuationFactor, t.Pyromaniac =
          time, tonumber(f[6]) or 0, tonumber(f[7]) or 0, caster
      end
    elseif kind == "rc" then
      local t = Game.GetEntity(f[4] or "")
      if t and t.Life > 0 then P.curse(t) end
    elseif kind == "rm" then
      local t = Game.GetEntity(f[4] or "")
      if t and P.o_WeaponsRawlingsCalm then P.o_WeaponsRawlingsCalm(c, t) end
    elseif kind == "rh" then
      local t = Game.GetEntity(f[4] or "")
      if t then
        local max = t.oActCtrl.oActClass.Life
        if t.Life > 0 and t.Life < max and (Coop.isLocalPlayer(t.Name) or (Coop.isHost() and Coop.ownerOf(t.Name) == nil)) then
          t.Life = max
        end
        Health.DoCure("PowRawlings", t.Name)
      end
    elseif kind == "jp" then
      local t = Game.GetEntity(f[4] or "")
      if t and (t.FireRemainTime or 0) < Jones.PyroDuration then
        t.FireRemainTime, t.FireDelayTime, t.FireAtenuationFactor, t.Pyromaniac =
          Jones.PyroDuration, Jones.PyroDamageDelay, 1, caster
      end
    end
  end)
  P.replaying = false
  Coop.log("powers: " .. tostring(kind) .. " of " .. caster .. " on " .. tostring(f[4]) .. (ok and "" or (" error: " .. tostring(err))))
end

------------------------------------------------------------------------------
function P.install()
  if not Coop.inSession() or Coop.level == "levels/menu" then return end
  P.installBullet()
  P.installAbby()
  P.installWorldPowers()
  P.installRawlings()
end

function P.update()
  P.install()
  P.sendBullet()
  P.reportBurns()
end

function P.onMessage(peer, f, data)
  local kind = f[1]
  if kind == "gb" or kind == "gbe" then P.onBullet(peer, f, data) return true end
  if kind == "abby" then P.onAbby(peer, f, data) return true end
  if kind == "pw" then P.onPower(peer, f, data) return true end
  if kind == "rl" then
    if Coop.isClient() then P.onLifeFeed(f) end
    return true
  end
  return false
end
