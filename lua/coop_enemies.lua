-- Jericho co-op: host-authoritative enemies, damage and story logic (phase 1).
-- Design: docs/enemies-and-triggers.md section 7. The host simulates enemies, spawns,
-- damage, deaths and story callbacks; clients show enemies as puppets, report their own
-- hits, and only take damage the host sends them.
--
-- Messages (text, "|" separated):
--   e|n,x,y,z,yaw,action,flags;n,...   host -> clients, unreliable, ~10 Hz (flags 1 = active)
--   espawn|name|class|group|x|y|z      host -> clients, reliable (NPC.CreateWithAI)
--   egroup|group                       host -> clients, reliable (NPC.ActivateEnemyGroup)
--   edie|name|quiet                    host -> clients, reliable (Weapons.OnCharDeath; quiet=1: RemoveNow)
--   pdmg|victim|amount|attacker        host -> owner of victim, reliable
--   hit|enemy|damage|attacker|bone|partdamage   client -> host, reliable (bone: bosses, E.hitPart)

CoopEnemies = {}
local E = CoopEnemies
E.SNAP_EVERY = 1          -- network ticks between snapshots (20 Hz; fork MAK-PIVO/jericho-coop)
E.SNAP_DIST = 250         -- units; enemy puppet teleports beyond this
E.FOLLOW = 0.9            -- share of the error to the interpolated place removed per 0.05 s
E.MAX_PACKET = 900        -- bytes per snapshot packet
E.targets = {}            -- client: name -> {x,y,z,yaw,action,active}
E.applied = {}            -- client: name -> last action forced
E.stats = {hitsSent = 0, hitsApplied = 0, pdmgSent = 0, pdmgApplied = 0, dropped = 0,
           spawns = 0, deaths = 0, groups = 0, snapshots = 0, missing = 0}

local function isEnemy(e)
  -- Check the type first: reading TgType on entities without it (triggers, sounds, cameras)
  -- makes the engine log an error per read, which slowed a level down to seconds per frame.
  return e and e:IsType("WalkChar") and e.TgType == "red"
end

-- Run fn with the "this came from the host" flag set, so client guards let it through.
-- Lobby option "AI squadmates": share of damage they take.
E.AI_SQUAD_DAMAGE = {normal = 1, tough = 0.6, very = 0.3}

local function fromHost(fn, ...)
  Coop.fromHost = true
  local ok, a, b = pcall(fn, ...)
  Coop.fromHost = false
  if not ok then Coop.log("fromHost error: " .. tostring(a)) end
  return a, b
end
E.fromHost = fromHost

------------------------------------------------------------------------------
-- Host
------------------------------------------------------------------------------

-- Enemy toughness for more players (lobby option, docs/coop-ux-research.md 5.8): Life x
-- (1 + k * (humans - 1)), once per enemy, when the host first sees it alive. Bosses too.
E.SCALING = {off = 0, light = 0.15, full = 0.30}
E.scaled = {}

function E.scaleEnemy(e)
  if E.scaled[e.Name] then return end
  E.scaled[e.Name] = true
  local k = E.SCALING[Coop.cfg.scaling or "light"] or 0
  local mult = 1 + k * (E.playerCount() - 1)
  if mult > 1 then
    e.Life = e.Life * mult
    E.stats.scaled = (E.stats.scaled or 0) + 1
  end
end

function E.snapshot()
  local parts, size = {}, 0
  local function flush()
    if #parts > 0 then
      -- e|<host time>|<enemies>: the time lets clients interpolate (Coop.puppetTarget).
      Net.CoopSend(-1, 0, string.format("e|%.3f|", E.snapTime) .. table.concat(parts, ";"))
      E.stats.snapshots = E.stats.snapshots + 1
      parts, size = {}, 0
    end
  end
  local e = Game.GetFirst()
  local n = 0
  E.snapTime = Net.CoopTime()
  local bodies = E.remoteBodies()
  local usr = Game.UsrEntity(0)
  local localBodies = usr and {usr} or {}
  while e ~= nil do
    if isEnemy(e) and e.Life > 0 and e.bActive then
      E.scaleEnemy(e)
      if not E.bombsSent[e.Name] then
        -- marked only once the mask was really sent (uData.bBombs may not exist on the first snapshot)
        if tostring(e.ActCtrl) ~= "CultistaExplosivo" or E.sendBombs(e) then E.bombsSent[e.Name] = true end
      end
      local p = e.Pos
      -- flags: bit 0 active, bit 1 pulling the trigger (the control field a firing body's AI
      -- sets); last field the view pitch, so the puppet's own shot code aims and plays the shot.
      local owc = e.owc
      local firing = owc and (owc.Shot or 0) > 0.5
      -- last field: life as a percentage of the highest the host has seen (the client's copy has its own
      -- scale: toughness settings are applied on the host only)
      local mx = math.max(E.maxLife[e.Name] or 0, e.Life)
      E.maxLife[e.Name] = mx
      local s = string.format("%s,%.0f,%.0f,%.0f,%.0f,%s,%d,%.0f,%d", e.Name, p.x, p.y, p.z, e.Ang.y, tostring(e.Action),
        1 + (firing and 2 or 0) + (E.faded[e.Name] and 4 or 0), e.ViewAng and e.ViewAng.x or 0,
        mx > 0 and math.min(100, math.floor(e.Life / mx * 100 + 0.5)) or 100)
      E.noteBossAction(e)
      if firing then E.stats.shotFlags = (E.stats.shotFlags or 0) + 1 end
      parts[#parts + 1] = s
      size = size + #s + 1
      n = n + 1
      if size > E.MAX_PACKET then flush() end
    elseif bodies[1] and e:IsType("Missile") then
      pcall(E.checkMissile, e, bodies, localBodies)
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  flush()
  E.lastCount = n
end

-- Enemy target choice (scripts/ai/aienemy.lua) only takes squad members whose AI is on
-- (AIMemberSquad.IsEnable = oAI.bEnable). Bodies held by remote players are network-driven
-- with their AI off, so enemies never went for them. While an enemy picks a target, a body
-- a human holds counts as enabled; squad AI elsewhere keeps the real flag.
function E.installTargeting()
  if E.targetingInstalled or not AIMemberSquad or not AIMemberSquad.IsEnable or not AIEnemy then return end
  E.targetingInstalled = true
  local origEnable = AIMemberSquad.IsEnable
  AIMemberSquad.IsEnable = function(ent)
    if E.choosingTarget and ent and Coop.isRemoteOwned(ent.Name) and (ent.Life or 0) > 0 then
      E.stats.remoteTargets = (E.stats.remoteTargets or 0) + 1
      return true
    end
    return origEnable(ent)
  end
  for _, fn in ipairs({"FindMemb", "FindMembVisNear", "FindMembRandom"}) do
    local orig = AIEnemy[fn]
    if type(orig) == "function" then
      AIEnemy[fn] = function(...)
        local was = E.choosingTarget
        E.choosingTarget = true
        local r = {pcall(orig, ...)}
        E.choosingTarget = was
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2)
      end
    end
  end
  Coop.log("enemies may target every human")
end

-- Enemy fire at a body another player holds (bug "enemy fire not seen / not felt by the client",
-- 0.2.7). Such a body is a puppet with collision off: the engine's trace and the melee rays
-- (DrawWeapon) pass through it, so enemies never hit a client (2541 of 2587 shots at the client's
-- body went through it, 0 hits). The host therefore tests the shot's own ray against the body's
-- capsule itself, and a hit goes through the game's own damage path (Weapons.OnShot with the body
-- as target, Weapons.DoDamage), which sends `pdmg` to the owner. The ray is the engine's, with
-- its spread and range, and ends where the engine's trace ended (a wall or another body in front
-- shields the player as in single player); a shot or swing the ray would not have hit still misses.
E.HIT_RADIUS = 27          -- units: capsule radius of a human body (calibrated against the engine, bugfix-028.md)
E.BODY_BOTTOM, E.BODY_TOP = 15, 165   -- capsule axis above the body's Pos
E.shotLogged = 0

local function clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

-- Closest distance between segments AB and CD (Ericson, Real-Time Collision Detection 5.1.9);
-- also the parameter of the closest point on AB.
local function segDist(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz)
  local d1x, d1y, d1z = bx - ax, by - ay, bz - az
  local d2x, d2y, d2z = dx - cx, dy - cy, dz - cz
  local rx, ry, rz = ax - cx, ay - cy, az - cz
  local a = d1x * d1x + d1y * d1y + d1z * d1z
  local e = d2x * d2x + d2y * d2y + d2z * d2z
  local f = d2x * rx + d2y * ry + d2z * rz
  local s, t
  if a <= 1e-9 and e <= 1e-9 then
    s, t = 0, 0
  elseif a <= 1e-9 then
    s, t = 0, clamp01(f / e)
  else
    local c = d1x * rx + d1y * ry + d1z * rz
    if e <= 1e-9 then
      s, t = clamp01(-c / a), 0
    else
      local b = d1x * d2x + d1y * d2y + d1z * d2z
      local den = a * e - b * b
      s = den > 1e-9 and clamp01((b * f - c * e) / den) or 0
      t = (b * s + f) / e
      if t < 0 then
        t, s = 0, clamp01(-c / a)
      elseif t > 1 then
        t, s = 1, clamp01((b - c) / a)
      end
    end
  end
  local px, py, pz = ax + d1x * s - (cx + d2x * t), ay + d1y * s - (cy + d2y * t), az + d1z * s - (cz + d2z * t)
  return math.sqrt(px * px + py * py + pz * pz), s
end

-- Distance from the ray segment (a -> b) to the body's capsule axis, and where along the ray.
function E.rayToBody(ax, ay, az, bx, by, bz, body)
  local p = body.Pos
  return segDist(ax, ay, az, bx, by, bz, p.x, p.y + E.BODY_BOTTOM, p.z, p.x, p.y + E.BODY_TOP, p.z)
end

-- Bodies other players hold that can be hit: alive, awake, not driven by a story line.
function E.remoteBodies()
  local list = {}
  for name in pairs(Coop.owners or {}) do
    if Coop.isRemoteOwned(name) and not (Coop.storyDriven and Coop.storyDriven[name]) then
      local b = Game.GetEntity(name)
      if b and (b.Life or 0) > 0 and b.bActive ~= false and b.Active ~= 0 then list[#list + 1] = b end
    end
  end
  return list
end

local function bump(key, n) E.stats[key] = (E.stats[key] or 0) + (n or 1) end

-- What an enemy's objective is, for the counters: "Local" (a body this machine's player holds),
-- "Remote" (another player's) or "Ai" (a squad member nobody holds).
local function objClass(obj)
  if Coop.isLocalPlayer(obj) then return "Local" end
  if Coop.isRemoteOwned(obj) then return "Remote" end
  return "Ai"
end

-- A shot an enemy fires (Weapons.OnShot(name, target, x, y, z, ...)): counts, and returns the
-- name of a remote body the shot's ray hits when the engine's trace went through it.
function E.noteShot(name, target, x, y, z)
  local from = Game.GetEntity(name)
  if not isEnemy(from) or not x then return end
  bump("eShots")
  local hit = target ~= nil and target ~= ""
  if hit then
    bump("eShotHit")
    if Coop.isRemoteOwned(target) then bump("eShotHitRemote") end
  end
  local a = from.Pos + V3D(0, 130, 0)
  local obj = from.AI_ObjectiveDin
  local body = obj and obj ~= "" and Game.GetEntity(obj)
  local cls = body and objClass(obj)
  -- Reference: how often the engine's own trace hits the human bodies it solidly collides with,
  -- and how often the capsule test would have (calibrates E.HIT_RADIUS; bugfix-028.md).
  if cls == "Local" then
    local d = E.rayToBody(a.x, a.y, a.z, x, y, z, body)
    bump("atLocal")
    if target == obj then bump("hitLocal") end
    for _, r in ipairs({20, 27, 35, 45}) do
      if d < r then bump("geoLocal" .. r) end
    end
  elseif cls == "Remote" then
    bump("eShotAtRemote")
  elseif cls == "Ai" then
    bump("atAi")
    if target == obj then bump("hitAi") end
  end
  -- The shot's ray through a remote body the engine let pass.
  local fixed, fixedD
  if Coop.cfg.remotehit ~= false and Weapons.DoDamage then
    local bestS
    for _, b in ipairs(E.remoteBodies()) do
      if b.Name ~= target then
        local d, s = E.rayToBody(a.x, a.y, a.z, x, y, z, b)
        if d < E.HIT_RADIUS and (not bestS or s < bestS) then fixed, fixedD, bestS = b.Name, d, s end
      end
    end
    if fixed then
      bump("eShotFixed")
      if fixed ~= obj then bump("eShotFixedOther") end
    end
  end
  E.shotLogged = E.shotLogged + 1
  if E.shotLogged <= 30 or E.shotLogged % 50 == 0 then
    Coop.log(string.format("eshot #%d %s (%s) -> %s (%s) target=%s fixed=%s %s", E.shotLogged, name, tostring(from.ActCtrl),
      tostring(obj), tostring(cls), hit and target or "-", tostring(fixed), fixedD and string.format("%.0f", fixedD) or ""))
  end
  return fixed
end

function E.installShotProbe()
  if E.shotProbe or not Weapons or not Weapons.OnShot then return end
  E.shotProbe = true
  local orig = Weapons.OnShot
  Weapons.OnShot = function(name, target, x, y, z, iShot, ...)
    local ok, fixed = pcall(E.noteShot, name, target, x, y, z)
    if not ok then
      if not E.shotProbeError then
        E.shotProbeError = true
        Coop.log("shot probe error: " .. tostring(fixed))
      end
    elseif fixed then
      target = fixed   -- the game's own path: hit sound and impulse on the body, Weapons.DoDamage -> pdmg
    end
    return orig(name, target, x, y, z, iShot, ...)
  end
end

-- Melee: the events of the enemies that swing at a body call o:DrawWeapon(pitch, yaw, reach), a ray
-- that passes through a puppet. When the game's own call hurt nobody, the same ray (the body's
-- view direction, the same reach) is tried against the remote bodies.
-- (a third field: the reach of the ray fix below; none = only the collision window)
E.MELEE = {
  {"WeaponsCultistaMelee", "HookHitEvent", function(o) return o.Action == "ThrownPunch" and 1000 or 400 end},
  {"WeaponsCruzader", "HookHitEvent", function() return 650 end},
  {"WeaponsChildCruzader", "HookHitEvent", function() return 500 end},
  {"WeaponsLegionary", "PushEvent", function() return 300 end},
  {"Behemoth", "DrawAttack"},
  {"EvilFirstBorn", "OnThrowRay"},
}

-- The collision window: a puppet's collision is off, so every ray an enemy casts (o:DrawWeapon in the melee events
-- and the Behemoth's vomit, Game.TestLine) goes through it. For the length of one such event (a synchronous Lua call,
-- no physics step inside) the remote bodies in reach get their collision back, so that the game's own code meets them
-- exactly as it meets any solid body: same rays, same spread, same damage, DoHitStrong and sounds included.
function E.withCollision(fn, ...)
  local saved
  for _, b in ipairs(E.remoteBodies()) do
    local ok, ign = pcall(function() return b.bIgnoreCollision end)
    if ok and ign then
      saved = saved or {}
      saved[#saved + 1] = b
      pcall(function() b.bIgnoreCollision = false end)
    end
  end
  local r = {n = 0}
  local function keep(...) r = {n = select("#", ...), ...} end
  keep(pcall(fn, ...))
  if saved then
    for _, b in ipairs(saved) do pcall(function() b.bIgnoreCollision = true end) end
    bump("windows")
  end
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2, r.n)
end

function E.meleeFix(o, reach, damage)
  local pitch, yaw = math.rad(o.ViewAng.x), math.rad(o.ViewAng.y)
  local a = o.Pos + V3D(0, 100, 0)
  local dx, dy, dz = -math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch)
  local bx, by, bz = a.x + dx * reach, a.y + dy * reach, a.z + dz * reach
  local best, bestS
  for _, b in ipairs(E.remoteBodies()) do
    local d, s = E.rayToBody(a.x, a.y, a.z, bx, by, bz, b)
    if d < E.HIT_RADIUS and (not bestS or s < bestS) then best, bestS = b, s end
  end
  if best then
    bump("mFix")
    Weapons.TempDamage = damage
    Weapons.DoDamage(o, best, damage)
    return best
  end
end

function E.installMelee()
  for _, m in ipairs(E.MELEE) do
    local t, fn, reachOf = _G[m[1]], m[2], m[3]
    local orig = t and t[fn]
    if type(orig) == "function" and not (t.coopMelee and t.coopMelee[fn] == orig) then
      t.coopMelee = t.coopMelee or {}
      t[fn] = function(name, ev, time)
        local o = Game.GetEntity(name)
        if not isEnemy(o) then return orig(name, ev, time) end
        local obj = o.AI_ObjectiveDin
        local cls = obj and obj ~= "" and Game.GetEntity(obj) and objClass(obj)
        E.meleeBy, E.meleeHurt = name, nil
        local r
        if Coop.cfg.window ~= false then
          r = {pcall(E.withCollision, orig, name, ev, time)}
        else
          r = {pcall(orig, name, ev, time)}
        end
        E.meleeBy = nil
        if cls then bump("mSwing" .. cls) end
        if E.meleeHurt then
          if cls then bump("mHit" .. cls) end
        elseif reachOf and Coop.cfg.remotehit ~= false and Coop.cfg.window == false then
          local ok, got = pcall(function() return E.meleeFix(o, reachOf(o), math.floor(tonumber(ev) or 0)) end)
          if ok and got then
            if cls == "Remote" then bump("mHitRemote") end
          elseif not ok and not E.meleeError then
            E.meleeError = true
            Coop.log("melee fix error: " .. tostring(got))
          end
        end
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2)
      end
      t.coopMelee[fn] = t[fn]
    end
  end
end

-- Part state of enemies (bug "bosses and pustule cultists only die on the host", owner's Steam
-- session): the client mirrored position and action only, so a Behemoth's seals and an exploding
-- cultist's pustules stayed as the level created them there (the cultist's set is even random per
-- machine: math.random in CultistaExplosivo.OnCreate). The host reports every part that goes
-- (`epart|enemy|seal|node`, `epart|enemy|bomb|node`) and each cultist's pustule set when it first
-- shows up (`epart|enemy|bombs|10110`, in the order of CultistaExplosivo.Bombs); clients show the
-- same state (E.applyPart), without running the game's own RemoveNode (its life, hint and story
-- side effects belong to the host).
E.PART_FUNCS = {
  {"Behemoth", "RemoveNode", "seal"},
  {"CultistaExplosivo", "RemoveNode", "bomb"},
}
function E.installParts()
  for _, m in ipairs(E.PART_FUNCS) do
    local t, fn, kind = _G[m[1]], m[2], m[3]
    local orig = t and t[fn]
    if type(orig) == "function" and not (t.coopPart and t.coopPart[fn] == orig) then
      t.coopPart = t.coopPart or {}
      t[fn] = function(ent, node, ...)
        local r = orig(ent, node, ...)
        if r and ent and node then
          E.stats.partsSent = (E.stats.partsSent or 0) + 1
          E.stats[kind .. "sGone"] = (E.stats[kind .. "sGone"] or 0) + 1
          Net.CoopSend(-1, 1, string.format("epart|%s|%s|%s", ent.Name, kind, node))
        end
        return r
      end
      t.coopPart[fn] = t[fn]
    end
  end
end

-- The pustule set of an exploding cultist as a 0/1 string.
function E.bombMask(e)
  local b = e.uData and e.uData.bBombs
  if not (b and CultistaExplosivo and CultistaExplosivo.Bombs) then return nil end
  local t = {}
  for i, n in ipairs(CultistaExplosivo.Bombs) do t[i] = b[n] and "1" or "0" end
  return table.concat(t)
end

-- Sent once per enemy when it first shows up in a snapshot (and to a client that loads late).
E.bombsSent = {}
function E.sendBombs(e, peer)
  local mask = E.bombMask(e)
  if mask then
    Net.CoopSend(peer or -1, 1, string.format("epart|%s|bombs|%s", e.Name, mask))
    return true
  end
  return false
end

function E.sendPartCatchup(peer)
  local n = 0
  local e = Game.GetFirst()
  while e ~= nil do
    if isEnemy(e) and e.Life > 0 then
      local cls = tostring(e.ActCtrl)
      if cls == "CultistaExplosivo" then
        E.sendBombs(e, peer)
        n = n + 1
      elseif cls == "Behemoth" and e.uData and e.uData.bSeals then
        for node, whole in pairs(e.uData.bSeals) do
          if whole == false then
            Net.CoopSend(peer, 1, string.format("epart|%s|seal|%s", e.Name, node))
            n = n + 1
          end
        end
      end
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  return n
end

-- Bosses that appear and disappear (the psychic commander "Bitch" of Vigil_Inside; owner's Steam
-- session 0.2.7: only her Disappear ran on the client, she stayed invisible): their model fades are
-- effects started by animation events (NPC.DisolveEntity / NPC.AppearEntity). Position and action
-- travel in 20 Hz unreliable snapshots, so a lost or skipped action left the client's copy faded out
-- for good. Two safeguards: (1) the host tracks which enemies are faded out (E.faded, wrapper on the
-- two NPC functions) and every snapshot carries it (flags bit 2), a client whose copy disagrees for
-- 0.4 s plays the fade itself (E.driveFade); (2) a boss's action change goes out reliably as
-- `eact|name|action` (E.noteBossAction), the client forces it at once.
E.maxLife = {}
E.faded = {}      -- host: enemies faded out by NPC.DisolveEntity
E.fadeSet = {}    -- client: the same, as this machine's own effects left it
E.fadeDiff = {}
E.BOSS_PATTERNS = {"Behemoth", "Maltheus", "Vicus", "Summerian", "PuppetGod", "EvilFirstBorn", "Gladiador",
                   "PsichicCommander", "Arnold", "FirstBorn"}
-- (walking and the like come with the snapshots; only the rest is worth a reliable message)
E.LOCOMOTION = {"^Walk", "^Run", "^Sprint", "Relax", "^Patrol", "Turn", "^Dodge", "^Strafe", "^Back", "^Idle", "^Stand"}
E.bossClass, E.bossAct = {}, {}
function E.isBoss(e)
  local cls = E.bossClass[e.Name]
  if cls == nil then
    cls = false
    local ac = tostring(e.ActCtrl)
    for _, pat in ipairs(E.BOSS_PATTERNS) do
      if string.find(ac, pat, 1, true) then cls = ac break end
    end
    E.bossClass[e.Name] = cls
  end
  return cls
end
function E.noteBossAction(e)
  if not E.isBoss(e) then return end
  local act = tostring(e.Action)
  if E.bossAct[e.Name] == act then return end
  E.bossAct[e.Name] = act
  for _, pat in ipairs(E.LOCOMOTION) do
    if string.find(act, pat) then return end
  end
  E.stats.actsSent = (E.stats.actsSent or 0) + 1
  Net.CoopSend(-1, 1, string.format("eact|%s|%s", e.Name, act))
  if E.stats.actsSent <= 60 then Coop.log(string.format("boss action %s (%s): %s", e.Name, E.bossClass[e.Name], act)) end
end

function E.installFades()
  local function wrap(fn, faded)
    local orig = NPC[fn]
    if type(orig) ~= "function" or (NPC.coopFade and NPC.coopFade[fn] == orig) then return end
    NPC.coopFade = NPC.coopFade or {}
    NPC[fn] = function(name, ...)
      local ent = Game.GetEntity(name)
      if ent and isEnemy(ent) then
        if Coop.isHost() then E.faded[name] = faded else E.fadeSet[name] = faded end
      end
      return orig(name, ...)
    end
    NPC.coopFade[fn] = NPC[fn]
  end
  wrap("DisolveEntity", true)
  wrap("AppearEntity", false)
end

-- Other attacks that never met a puppet (bug "enemy fire not felt by the client", gaps found with
-- the shot test): flames (the engine's line tests pass through a body with collision off), thrown
-- and shot missiles (pilum, crossbow bolt: the missile's collision), and the hit reaction a strong
-- hit plays (Soldier.DoHitStrong acts only on the local player's body). The host tests the same
-- geometry against the remote bodies and sends what the owner's machine has to do.

-- Flame: the flamethrowers (the soldier with the tank, the bunker's burner) follow the flame's path in
-- short segments, each tested by two thin lines (Game.TestLine from WeaponsNaziSoldier/WeaponsPilBox
-- .DoubleLineTest, the second one 100 units higher); the first line that meets a body ends the flame
-- there and the body burns (FireRemainTime). A puppet is not met by such a line. The host's wrapper
-- tests each segment against the capsules of the remote bodies (the same radius as for shots: a thin
-- line against the same collision shape); a body found nearer than where the engine's line ended is
-- handed back as the hit, so the game's own code ends the flame there as for any solid body, and the
-- owner is told (`pfire`) to set the body alight the way the game does.
E.flameSent = {}
E.FLAME_RADII = {27, 45, 60, 80}   -- reference counters only (calibration against the engine's lines on a local body)
function E.humans()
  -- (once per frame) local human bodies and remote ones that can be hit
  if E.humansFrame ~= Coop.frame then
    E.humansFrame = Coop.frame
    E.humansRemote = E.remoteBodies()
    local usr = Game.UsrEntity(0)
    E.humansLocal = usr and (usr.Life or 0) > 0 and {usr} or {}
  end
  return E.humansRemote, E.humansLocal
end

-- Tells the owner of a body that a flame reached it (rate limited: the flame is tested every frame).
function E.flameSend(bodyName, shooter)
  local now = Net.CoopTime()
  if now - (E.flameSent[bodyName] or 0) <= 0.1 then return end
  E.flameSent[bodyName] = now
  local cfg = EnemiesCfg and EnemiesCfg.NaziSoldierB and EnemiesCfg.NaziSoldierB.Flamethrower
  E.stats.flameHits = (E.stats.flameHits or 0) + 1
  Net.CoopSend(Coop.peerOf(Coop.ownerOf(bodyName)), 1, string.format("pfire|%s|%.3f|%.3f|%s", bodyName,
    cfg and cfg.FireDuration or 0.3, cfg and cfg.FireDamageDelay or 0.015, shooter.Name))
  E.pdmgBy = E.pdmgBy or {}
  local kind = tostring(shooter.ActCtrl) .. "(fire)"
  E.pdmgBy[kind] = (E.pdmgBy[kind] or 0) + 1
end

function E.flameLine(orig, a, b, da, db, mask, name, geom)
  local shooter = Game.GetEntity(name)
  if not (shooter and isEnemy(shooter)) then return orig(a, b, da, db, mask, name, geom) end
  -- with the collision window (default) the engine's own lines meet a remote body like any solid one
  local window = Coop.cfg.window ~= false
  local r1, r2
  if window then
    r1, r2 = E.withCollision(orig, a, b, da, db, mask, name, geom)
  else
    r1, r2 = orig(a, b, da, db, mask, name, geom)
  end
  local remote, localB = E.humans()
  bump("flameSegs")
  -- the path of this segment ends where the engine's line stopped (a wall, a body), else at its end
  local engineHit = r1 and r2
  local ex, ey, ez = b.x, b.y, b.z
  if engineHit then ex, ey, ez = r1.x, r1.y, r1.z end
  local o2 = da or V3D(0, 0, 0)
  local function test(body)
    local d1, s1 = E.rayToBody(a.x, a.y, a.z, ex, ey, ez, body)
    local d2, s2 = E.rayToBody(a.x + o2.x, a.y + o2.y, a.z + o2.z, ex + o2.x, ey + o2.y, ez + o2.z, body)
    if d2 < d1 then return d2, s2 end
    return d1, s1
  end
  -- reference: the engine's own lines on this machine's player against the capsule model
  for _, body in ipairs(localB) do
    local d = test(body)
    if d < 400 then
      bump("flameNearLocal")
      if r2 == body.Name then
        bump("flameHitLocal")
        if (E.stats.flameHitLocal or 0) <= 40 then
          Coop.log(string.format("flame: the engine's lines hit %s, capsule distance %.1f, from %s", body.Name, d, name))
        end
      end
      for _, r in ipairs(E.FLAME_RADII) do
        if d < r then bump("flameGeoLocal" .. r) end
      end
    end
  end
  if Coop.cfg.remotehit == false or Coop.cfg.pfire == false then return r1, r2 end
  if window then
    -- the engine met a body held by another player: it burns there
    for _, body in ipairs(remote) do
      local d = test(body)
      if d < 400 then bump("flameNearRemote") end
      if r2 == body.Name then
        bump("flameSegHit")
        E.flameSend(body.Name, shooter)
        if (E.stats.flameSegHit or 0) <= 40 then
          Coop.log(string.format("flame: the engine's lines hit %s, capsule distance %.1f, from %s", body.Name, d, name))
        end
      end
    end
    return r1, r2
  end
  -- window=false: the capsule test of the segment (the lines pass through a puppet)
  local best, bestS
  for _, body in ipairs(remote) do
    local d, s = test(body)
    if d < 400 then
      bump("flameNearRemote")
      for _, r in ipairs(E.FLAME_RADII) do
        if d < r then bump("flameGeoRemote" .. r) end
      end
    end
    if d < E.HIT_RADIUS and (not bestS or s < bestS) then best, bestS = body, s end
  end
  if not best or (engineHit and bestS > 0.97) then return r1, r2 end
  bump("flameSegHit")
  E.flameSend(best.Name, shooter)
  return V3D(a.x + (ex - a.x) * bestS, a.y + (ey - a.y) * bestS, a.z + (ez - a.z) * bestS), best.Name
end

function E.installFlames()
  for _, tn in ipairs({"WeaponsNaziSoldier", "WeaponsPilBox"}) do
    local t = _G[tn]
    local orig = t and t.DoubleLineTest
    if type(orig) == "function" and not (t.coopLine and t.coopLine == orig) then
      local wrapper = function(a, b, da, db, mask, name, geom)
        local r = {pcall(E.flameLine, orig, a, b, da, db, mask, name, geom)}
        if not r[1] then
          if not E.flameError then
            E.flameError = true
            Coop.log("flame fix error: " .. tostring(r[2]))
          end
          return orig(a, b, da, db, mask, name, geom)
        end
        return r[2], r[3]
      end
      t.DoubleLineTest = wrapper
      t.coopLine = wrapper
    end
  end
end

-- (the engine's own hits of a pilum on this machine's player, to compare with the missile test)
function E.installMissileRef()
  local t = WeaponsLegionary
  local orig = t and t.HitPilum
  if type(orig) == "function" and not (t.coopHit and t.coopHit == orig) then
    local wrapper = function(Bullet, x, y, z, Target)
      local usr = Game.UsrEntity(0)
      if Target and usr and Target.Name == usr.Name then bump("missileHitLocal") end
      return orig(Bullet, x, y, z, Target)
    end
    t.HitPilum = wrapper
    t.coopHit = wrapper
  end
  -- (and how many pilums are thrown at whom: hits per throw, remote against local)
  local launch = t and t.LaunchPilum
  if type(launch) == "function" and not (t.coopLaunch and t.coopLaunch == launch) then
    local wrapper = function(name, ...)
      local o = Game.GetEntity(name)
      local obj = o and o.AI_ObjectiveDin
      if obj and obj ~= "" and Game.GetEntity(obj) then bump("pilumThrown" .. objClass(obj)) end
      return launch(name, ...)
    end
    t.LaunchPilum = wrapper
    t.coopLaunch = wrapper
  end
end

-- Missiles (host): once per snapshot every missile an enemy shot is followed from its last place to
-- its place now; through a remote body it hits that body the way its own callback would have.
-- {name prefix, what the missile's own callback does with the body it meets, longest believable step}
-- (blades share one name: positions of two blades are not one path)
E.MISSILES = {
  {"LegionaryPilum", function(m, x, y, z, b) return WeaponsLegionary.HitPilum(m, x, y, z, b) end},
  {"Virote", function(m, x, y, z, b) return WeaponsCruzader.ExplodeVirotus(m, x, y, z, b) end},
  {"FireBall_", function(m, x, y, z, b) return SummerianKI.ExplodeFireBall(m, x, y, z, b) end},
  {"CultistBlade", function(m, x, y, z, b)
    if tostring(m.oParent and m.oParent.ActCtrl) == "Arnold" then return Arnold.HitBlade(m, x, y, z, b) end
    return CultistaVolador.HitBlade(m, x, y, z, b)
  end, 450},
}
E.missilePos = {}
function E.checkMissile(m, bodies, localBodies)
  local kind
  for _, k in ipairs(E.MISSILES) do
    if string.find(m.Name, k[1], 1, true) == 1 then kind = k break end
  end
  if not kind then return end
  local parent = m.oParent
  if not (parent and isEnemy(parent)) then return end
  local p, now = m.Pos, Net.CoopTime()
  local prev = E.missilePos[m.Name]
  E.missilePos[m.Name] = {x = p.x, y = p.y, z = p.z, t = now}
  if not prev or now - prev.t > 0.3 then return end
  if kind[3] then
    local dx, dy, dz = p.x - prev.x, p.y - prev.y, p.z - prev.z
    if dx * dx + dy * dy + dz * dz > kind[3] * kind[3] then return end
  end
  local radius = E.HIT_RADIUS + (m.EmbeddedCapsuleRadius or 0)
  -- reference: the engine's own missile collision against this machine's player
  for _, b in ipairs(localBodies or {}) do
    if E.rayToBody(prev.x, prev.y, prev.z, p.x, p.y, p.z, b) < radius then
      bump("missileNearLocal")
      E.missileNear = E.missileNear or {}
      E.missileNear[m.Name] = now
    end
  end
  for _, b in ipairs(bodies) do
    local d = E.rayToBody(prev.x, prev.y, prev.z, p.x, p.y, p.z, b)
    if d < radius then
      E.stats.missileHits = (E.stats.missileHits or 0) + 1
      E.missilePos[m.Name] = nil
      pcall(kind[2], m, p.x, p.y, p.z, b)
      return
    end
  end
end

-- Ninlil's blood hit hurts only the body at this machine's controls (Game.UsrEntity(0)); the same hit for the bodies
-- other humans hold (the host's wrapper; their owners get `pdmg` and `phit` through the usual paths).
function E.installBloodHit()
  local t = SummerianNINLIL
  local orig = t and t.BloodHit
  if type(orig) == "function" and not (t.coopBlood and t.coopBlood == orig) then
    local wrapper = function(name, ...)
      local ent = Game.GetEntity(name)
      if ent and isEnemy(ent) then
        for _, b in ipairs(E.remoteBodies()) do
          local dx, dz = ent.Pos.x - b.Pos.x, ent.Pos.z - b.Pos.z
          if math.sqrt(dx * dx + dz * dz) < 60 then
            bump("bloodHits")
            Weapons.DoDamage(ent, b, 40)
            Soldier.DoHitStrong(b)
          end
        end
      end
      return orig(name, ...)
    end
    t.BloodHit = wrapper
    t.coopBlood = wrapper
  end
end

-- Hit reaction: Soldier.DoHitStrong plays only on the machine's own player body; the owner of a
-- remote body plays it (`phit`).
function E.installHitStrong()
  if E.hitStrongInstalled or not Soldier or not Soldier.DoHitStrong then return end
  E.hitStrongInstalled = true
  local orig = Soldier.DoHitStrong
  Soldier.DoHitStrong = function(usr, ...)
    if usr and Coop.isRemoteOwned(usr.Name) then
      E.stats.hitStrong = (E.stats.hitStrong or 0) + 1
      Net.CoopSend(Coop.peerOf(Coop.ownerOf(usr.Name)), 1, "phit|" .. usr.Name)
      return
    end
    return orig(usr, ...)
  end
end
E.origHitStrong = nil

function E.installHost()
  E.installTargeting()
  E.installShotProbe()
  E.installMelee()
  E.installParts()
  E.installFades()
  E.installFlames()
  E.installMissileRef()
  E.installBloodHit()
  E.installHitStrong()
  local origCreate = NPC.CreateWithAI
  NPC.CreateWithAI = function(acName, x, y, z, listName, setOnFloor)
    local e = origCreate(acName, x, y, z, listName, setOnFloor)
    if e then
      E.stats.spawns = E.stats.spawns + 1
      Net.CoopSend(-1, 1, string.format("espawn|%s|%s|%s|%.0f|%.0f|%.0f", e.Name, acName, tostring(listName), x, y, z))
    end
    return e
  end

  local origActivate = NPC.ActivateEnemyGroup
  NPC.ActivateEnemyGroup = function(group, ...)
    local var = init.LevelName .. ".EnemyGroup." .. group .. ".Status"
    Game.CreateSaveVar(var, "0")
    local before = Game.GetSaveVar(var)
    local r = origActivate(group, ...)
    if before == "0" and Game.GetSaveVar(var) == "1" then
      E.stats.groups = E.stats.groups + 1
      Net.CoopSend(-1, 1, "egroup|" .. group)
    end
    return r
  end

  local origDeath = Weapons.OnCharDeath
  Weapons.OnCharDeath = function(name, from, ...)
    local e = Game.GetEntity(name)
    if isEnemy(e) then
      E.stats.deaths = E.stats.deaths + 1
      -- who gets the kill: a body another player holds (a client's shots) or one here
      local killer = from and from ~= "" and (type(from) == "string" and from or from.Name)
      if killer and Coop.isRemoteOwned(killer) then
        E.stats.killsRemote = (E.stats.killsRemote or 0) + 1
      elseif killer then
        E.stats.killsLocal = (E.stats.killsLocal or 0) + 1
      end
      -- RemoveNow: removed without a death (EnemyGen.Stop clears its unused pool this way).
      local quiet = e.uData and e.uData.RemoveNow and "1" or ""
      Net.CoopSend(-1, 1, "edie|" .. name .. "|" .. quiet)
    end
    return origDeath(name, from, ...)
  end

  local origDamage = Weapons.DoDamage
  E.origDamage = origDamage
  Weapons.DoDamage = function(From, To, Damage, BodyMultiplier)
    if E.meleeBy and From and From.Name == E.meleeBy then E.meleeHurt = true end   -- (E.installMelee)
    -- A remote player's puppet fires for show only; its owner reports real hits. So does Ross's
    -- stand-in (coop_ross.lua) for the host's Ross.
    if From and (Coop.isRemoteOwned(From.Name) or From.Name == "CoopRossBody") and not Coop.applyingRemoteHit then
      E.stats.dropped = E.stats.dropped + 1
      return false
    end
    -- Damage to a body another human controls is applied by its owner.
    if To and Coop.isRemoteOwned(To.Name) and not Coop.applyingRemoteHit then
      -- One machine per source (audit 0.2.2 A12): damage with no source (a fall...) is the
      -- owner's own, where the body really is; anything with a source comes from here.
      if not From and Coop.cfg.hazardlocal ~= false then
        E.stats.dropped = E.stats.dropped + 1
        return false
      end
      local owner = Coop.ownerOf(To.Name)
      E.stats.pdmgSent = E.stats.pdmgSent + 1
      -- by source kind: a shooter's class, or what else hurt (diagnostics)
      local kind = From and (isEnemy(From) and tostring(From.ActCtrl) or "other") or "none"
      E.pdmgBy = E.pdmgBy or {}
      E.pdmgBy[kind] = (E.pdmgBy[kind] or 0) + 1
      -- the shooter's place travels too: the owner's copy of it may lag or not exist yet
      local fp = From and From.Pos
      Net.CoopSend(Coop.peerOf(owner), 1, string.format("pdmg|%s|%.2f|%s|%.0f|%.0f|%.0f", To.Name, Damage,
        From and From.Name or "", fp and fp.x or 0, fp and fp.y or 0, fp and fp.z or 0))
      return false
    end
    -- AI squadmates take less damage if the host chose so in the lobby.
    if To and Coop.SQUAD_SET[To.Name] and Coop.ownerOf(To.Name) == nil and Damage then
      Damage = Damage * E.aiSquadFactor()
    end
    if CoopSmod then BodyMultiplier = CoopSmod.headshot(To, From, BodyMultiplier) end
    return origDamage(From, To, Damage, BodyMultiplier)
  end
end

-- The lobby's "AI squadmates" choice; left as in the game, SMOD's value when the session
-- plays by SMOD's rules (coop_smod.lua).
function E.aiSquadFactor()
  local mode = Coop.cfg.aisquad or "normal"
  if mode ~= "normal" then return E.AI_SQUAD_DAMAGE[mode] or 1 end
  local r = CoopSmod and CoopSmod.rules()
  return r and r.ai or 1
end

-- Cutscenes: the host announces every scene it starts (story callbacks run only there);
-- clients play the same scene locally. First-person scenes bind to Game.UsrEntity(0),
-- so each player sees them from their own character. Chained scenes (NextScene) are
-- started by EndOfScene on every machine and are not forwarded.
E.SCENE_FUNCS = {play = "Play", fp = "PlayFP", fpni = "PlayFPNI", fpnni = "PlayFPNNI"}

-- First-person scenes are animated for one character only (FP_<char>_Play.CM3 in the level
-- archives). Players holding another character watch through that character's eyes and keep
-- their own body where it was (the scene would otherwise move it to the scene's end point).
E.FP_OWNER = {
  helicoptertrip = "Ross", landing = "Ross", thedreamb = "Ross", thedreamc = "Ross",
  murielstale = "Ross", rossdeath = "Ross", blooddoor = "Ross", tombcollapses = "Ross",
  rossdeathb = "Delgado", thetrap = "Delgado", bridgecollapses = "Delgado",
  cruzadersspeech_a = "Delgado", conversation = "Delgado",
  therescue = "Black", cruzadersspeech_b = "Black", apertura = "Black", theenda = "Black",
  theendb = "Black", intotheunknown = "Black", britishcomando = "Black",
  behemothdead = "Church", aperturapuerta = "Church", descensoa = "Church", descensob = "Church",
  escalada = "Church", theabyss = "Church", theendc = "Church", theendd = "Church",
  nazisacrificea = "Church", nazisacrificeb = "Church",
  centurianstale = "Rawlings", rawlingstorture = "Rawlings",
  delgadokillsrawlings = "Cole", pathofsouls = "Cole",
  britishcomandospeech = "Jones",
}

-- Before a first-person scene: remember the local body if it is not the scene's character.
function E.beforeFpScene(class)
  local owner = E.FP_OWNER[string.lower(tostring(class))]
  local usr = Game.UsrEntity(0)
  if owner and usr and usr.Name ~= owner and not E.fpRestore then
    E.fpRestore = {name = usr.Name, pos = usr.Pos, ang = usr.Ang, owner = owner}
    E.fpLabel = owner
    -- The game now walks this body to the scene's camera, maybe across the map, with the
    -- view on it: black until the scene starts (E.installFpRestore fades it in).
    Scorer.Clear(0)   -- no HUD on the black (the scene clears it anyway)
    E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 255), 0.1)
    E.fpBlackT = Game.GetTime()
  end
end

-- The game glides the camera for 0.25 s between the player's view and the scene's (start
-- and end of a first-person scene). From a body that is not the scene's character that
-- flies it across the map: cut instead.
local function cutInterpolation(camint)
  Game.SetCam(0, camint[1].TgtCam)
  camint:Del()
  Scene.SkipRenderDo()
end

-- Some first-person scenes get their own end callback from the level (BehemothDead,
-- NaziSacrificeA...), so Scene.EndOfFpScene never runs for them: when nothing plays any
-- more, finish what it would have (body back in place, caption off).
function E.finishFpLeftover()
  if Scene.IsPlaying then return end
  local keep = E.fpRestore
  E.fpRestore, E.fpLabel, E.fpLabelPlay, E.fpBlackT = nil, nil, nil, nil
  if not keep then return end
  local body = Game.GetEntity(keep.name)
  if body then
    local d = keep.pos and body.Pos - keep.pos
    local moved = d and d.x * d.x + d.y * d.y + d.z * d.z > 2500
    body.Pos, body.Ang = keep.pos, keep.ang
    body.IgnoreUsrControl = 0
    if moved then E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 0), 0.6) end
  end
  Coop.log("fp scene over (level's own end): " .. keep.name .. " back in place")
end

-- A scene played straight through a character's eyes (Scene.Play with CameraFrom FP_<X>:
-- the torture, a speech chained after another scene) moves nobody, but is still seen
-- through someone else's eyes: the same caption, until the scene ends.
function E.labelPlayScene(class)
  local owner = E.FP_OWNER[string.lower(tostring(class))]
  local usr = Game.UsrEntity(0)
  local mine = (usr and usr.Name) or Coop.cfg.char   -- no user entity inside a scene
  if owner and mine ~= owner and not E.fpLabel then
    E.fpLabel, E.fpLabelPlay = owner, true
  end
end

function E.installFpRestore()
  local orig = Scene.EndOfFpScene
  local origLaunch = Scene.LauchFromFP
  if origLaunch then
    Scene.LauchFromFP = function(...)
      local origInterp = Scene.SetInterpolCam
      local cut = E.fpRestore ~= nil
      if cut and origInterp then Scene.SetInterpolCam = cutInterpolation end
      local r = {pcall(origLaunch, ...)}
      Scene.SetInterpolCam = origInterp
      E.fpBlackT = nil
      if cut then E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 0), 0.4) end
      if not r[1] then Coop.log("LauchFromFP error: " .. tostring(r[2])) end
      return r[2]
    end
  end
  Scene.EndOfFpScene = function(usr, ...)
    -- Back in place below: no glide from the scene's end (the fade below covers the cut).
    local origInterp = Scene.SetInterpolCam
    if E.fpRestore and origInterp then Scene.SetInterpolCam = cutInterpolation end
    local r = {pcall(orig, usr, ...)}
    Scene.SetInterpolCam = origInterp
    local keep = E.fpRestore
    E.fpRestore, E.fpLabel = nil, nil
    if keep then
      -- The game put the local body where the scene ends (the top of a climb, past a
      -- door). That is where the scene's character is now: an AI owner (no human holds it)
      -- goes there, the local body goes back.
      local owner = keep.owner and Game.GetEntity(keep.owner)
      if owner and r[1] and Coop.isHost() and not Coop.isRemoteOwned(keep.owner) then
        owner.Pos = usr.Pos
        owner.Ang = usr.Ang
        Coop.log("fp scene over: " .. keep.owner .. " (AI) at the scene's end")
      end
      local body = Game.GetEntity(keep.name)
      if body then
        body.Pos = keep.pos
        body.Ang = keep.ang
        body.IgnoreUsrControl = 0
      end
      -- The view jumps from the scene's end back to the own body: from black, not a cut.
      E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 0), 0.6)
      Coop.log("fp scene over: " .. keep.name .. " back in place")
    end
    if not r[1] then Coop.log("EndOfFpScene error: " .. tostring(r[2])) end
    return r[2]
  end
end

-- During a first-person scene seen through someone else's eyes, say whose: for the first
-- seconds of the scene, then the caption fades. The name is the game's own (language file
-- keys Church, Cole...: "Черч").
E.EYES = {en = "Through %s's eyes", ru = "Вид глазами: %s"}
E.EYES_SHOW = 5
E.EYES_FADE = 1
function E.lang() return Coop.lang() end

-- A scene held at the gate (the level's opening scene while others still load) would leave
-- this player in live play for a few seconds where the game shows the scene at once: the
-- screen stays black and the keys do nothing until it starts; a long wait says why.
E.WAIT = {en = "Waiting for players...", ru = "Ожидание игроков..."}
E.WAIT_TEXT_AFTER = 0.5
-- Fades go through the game's own Scorer.Fade; while the curtain is up, the level's opening
-- fade-in (MapInit.main: black -> clear, run after the mod starts) would show the first frame.
function E.fade(...)
  local f = E.origFade or (Scorer and Scorer.Fade)
  if f then return f(...) end
end

function E.holdCurtain(on)
  if on then
    if E.curtain then return end
    if not E.origFade and Scorer and Scorer.Fade then
      E.origFade = Scorer.Fade
      Scorer.Fade = function(...)
        if E.curtain then return end
        return E.origFade(...)
      end
    end
    -- Same for the HUD the level builds after the mod starts (first level of a session).
    if not E.origShowScorer and Menu and Menu.ShowScorer then
      E.origShowScorer = Menu.ShowScorer
      Menu.ShowScorer = function(...)
        if E.curtain then return end
        return E.origShowScorer(...)
      end
    end
    E.curtain = {t0 = Game.GetTime()}
    Scorer.Clear(0)   -- a HUD built before the mod started would show on the black
    E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 255), 0.1)
    E.curtain.locked = {}
    E.lockCurtainBody()
    Coop.log("curtain: black")
    return
  end
  local c = E.curtain
  if not c then return end
  E.curtain = nil
  for name, was in pairs(c.locked or {}) do
    local body = Game.GetEntity(name)
    if body and body.IgnoreUsrControl == 1 then body.IgnoreUsrControl = was end
  end
  Scorer.Clear(0)
  local show = E.origShowScorer or (Menu and Menu.ShowScorer)
  if show then pcall(show) end
  E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 0), 0.5)
end

-- The body held now (the switch to the lobby seat may come while the screen is black).
function E.lockCurtainBody()
  local c, usr = E.curtain, Game.UsrEntity(0)
  if c and usr and c.locked[usr.Name] == nil then
    c.locked[usr.Name] = usr.IgnoreUsrControl or 0
    usr.IgnoreUsrControl = 1
  end
end

function E.updateCurtain()
  local c = E.curtain
  if not c then return end
  E.lockCurtainBody()
  -- The level-start curtain (no scene held) lifts once everyone has loaded.
  if c.gate and not E.heldScenes and E.gateOpen() then E.holdCurtain(false) return end
  -- Every frame: the level's own fade-in and HUD come up meanwhile (a scene clears the HUD
  -- the same way when it starts, and puts it back when it ends).
  Scorer.Clear(0)
  E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 255), 0.1)
  if Game.GetTime() - c.t0 < E.WAIT_TEXT_AFTER then return end
  local it = Scorer.GetItem(0, "CoopWait")
  if not it then
    it = Scorer.NewItem(0, "CoopWait", "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Effect = "Shadow"
    it.Pos = V2D(320, 240)
    Coop.setCentered(it, Coop.enc(E.WAIT[E.lang()] or E.WAIT.en))
    it.Color = Color(230, 230, 230, 255)
  end
  it.Visible = 1
end

function E.updateSceneLabel()
  E.updateCurtain()
  -- A first-person scene that went black for its start but never started: show play again.
  if E.fpBlackT and Game.GetTime() - E.fpBlackT > 4 then
    E.fpBlackT = nil
    if Menu and Menu.ShowScorer then pcall(Menu.ShowScorer) end
    E.fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 0), 0.4)
    Coop.log("fp scene did not start: screen back")
    -- (and the body, its place and controls, and no caption left for the next scene)
    if not Scene.IsPlaying then pcall(E.finishFpLeftover) end
  end
  local it = Scorer.GetItem(0, "CoopEyes")
  if E.fpLabel and (Scene.IsPlaying or E.fpBlackT) then
    local fresh = not it   -- a HUD clear (scene start, ShowScorer) deletes it
    if fresh then
      it = Scorer.NewItem(0, "CoopEyes", "Text")
      it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
      it.Effect = "Shadow"
      it.Pos = V2D(320, 40)
    end
    if E.fpLabelShown ~= E.fpLabel or fresh then
      if E.fpLabelShown ~= E.fpLabel then E.fpLabelShown, E.fpLabelT0 = E.fpLabel, Game.GetTime() end
      local lang = E.lang()
      local name = Game.GetLangStr(E.fpLabel)
      if not name or name == "" then name = E.fpLabel end
      -- (the name is the game's own text, in its code page already)
      Coop.setCentered(it, string.format(Coop.enc(E.EYES[lang] or E.EYES.en, lang), name))
    end
    local t = Game.GetTime() - E.fpLabelT0
    local a = t < E.EYES_SHOW and 1 or math.max(0, 1 - (t - E.EYES_SHOW) / E.EYES_FADE)
    it.Color = Color(230, 230, 230, math.floor(255 * a))
    it.Visible = a > 0 and 1 or 0
  else
    E.fpLabelShown = nil
    if it then it.Visible = 0 end
  end
end

-- Level changes (story transitions, restarts) are the host's: it announces the level and
-- clients load the same one. SaveGame.LoadLevel is where every story path ends.
function E.installLevelHost()
  local orig = SaveGame.LoadLevel
  SaveGame.LoadLevel = function(name, ...)
    if name and name ~= "menu" then
      Coop.log("level -> " .. tostring(name))
      if CoopSave then CoopSave.sendVars(name) end
      Net.CoopSend(-1, 1, "level|" .. tostring(name))
      Coop.cfg.level = name
      Coop.rearm()
    end
    return orig(name, ...)
  end
end

function E.onLevel(name)
  Coop.log("host changes level to " .. tostring(name))
  Coop.cfg.level = name
  Coop.rearm()
  if CoopSave then CoopSave.applyPending() end
  Coop.levelLoading = Net.CoopTime()
  fromHost(SaveGame.LoadLevel, name)
end

-- A failed QTE replays its scene (Scene.ReloadScene -> ReplayScene). Branches are synced
-- (CoopScenes), so every machine replays by itself: let that Play through on clients and
-- do not forward it from the host.
function E.installReplay()
  local orig = Scene.ReplayScene
  if not orig then return end
  Scene.ReplayScene = function(...)
    Coop.log("scene replay " .. tostring((...)))
    E.inReplay = true
    local ok, err = pcall(orig, ...)
    E.inReplay = false
    if not ok then Coop.log("ReplayScene error: " .. tostring(err)) end
  end
end

-- Level-start scenes (the WWII conversation, the chapel rescue, the ending, ...) would play
-- on the host while clients are still loading. The host holds scene starts until every
-- expected player reported the level loaded (lready), at most GATE_TIMEOUT seconds.
-- Expected players: the lobby seats, or cfg.waitpeers in tests.
E.GATE_TIMEOUT = 90
E.readyPeers = {}

function E.expectedPeers()
  -- Players away in a side instance (the Lost Patrol trio) load their own levels: the hub's
  -- main instance does not wait for them.
  if CoopInst and not Coop.cfg.inst and CoopInst.split() then
    local away = 0
    for _ in pairs(CoopInst.sideMembers()) do away = away + 1 end
    return math.max(0, E.expectedAll() - away)
  end
  return E.expectedAll()
end

function E.expectedAll()
  if Coop.cfg.waitpeers then return Coop.cfg.waitpeers end
  -- A side instance (coop_inst.lua) waits for its own players only.
  if Coop.cfg.inst then
    local n = 0
    for _ in string.gmatch(Coop.cfg.instIds or "", "%d+") do n = n + 1 end
    return math.max(0, n - 1)
  end
  -- Machines, not seats: a split screen player (owner id peer + Coop.P2) loads with its
  -- machine and sends no ready of its own (0.2.1: a session made in the lobby with a host's
  -- player 2 waited the whole GATE_TIMEOUT on every level).
  local n, seen = 0, {}
  for peer in string.gmatch(Coop.cfg.seats or "", "(%d+):[^;]*") do
    peer = Coop.peerOf(tonumber(peer))
    if peer ~= 0 and not seen[peer] then
      seen[peer] = true
      n = n + 1
    end
  end
  return n
end

function E.gateOpen()
  if E.gateOpened then return true end
  local ready = 0
  for _ in pairs(E.readyPeers) do ready = ready + 1 end
  -- A player who left is out of cfg.seats (Coop.onLeave), so expectedAll no longer counts them.
  if ready >= E.expectedPeers() or Net.CoopTime() > (E.gateUntil or 0) then
    E.gateOpened = true
    Coop.log(string.format("scene gate open: %d of %d players loaded", ready, E.expectedPeers()))
  end
  return E.gateOpened
end

function E.flushHeldScenes()
  local held = E.heldScenes
  if not held or not E.gateOpen() then return end
  E.heldScenes = nil
  E.holdCurtain(false)
  for _, h in ipairs(held) do
    Coop.log("scene " .. h.fname .. " " .. tostring(h.class) .. " released")
    Scene[h.fname](h.class, unpack(h.args))
  end
end

function E.installSceneHost()
  E.installReplay()
  E.gateUntil = Net.CoopTime() + E.GATE_TIMEOUT
  -- Everyone starts the level together: black from the first frame the mod sees (before the
  -- level's opening scene or the switch to the lobby character shows) until all have loaded.
  if not E.gateOpen() then
    E.holdCurtain(true)
    E.curtain.gate = true
  end
  local origEnd = Scene.EndOfScene
  Scene.EndOfScene = function(...)
    E.inEndOfScene = true
    if E.fpLabelPlay then E.fpLabel, E.fpLabelPlay = nil, nil end   -- a chained scene sets its own
    local ok, a, b = pcall(origEnd, ...)
    E.inEndOfScene = false
    E.finishFpLeftover()
    if not ok then Coop.log("EndOfScene error: " .. tostring(a)) end
    return a, b
  end
  for mode, fname in pairs(E.SCENE_FUNCS) do
    local orig = Scene[fname]
    Scene[fname] = function(class, ...)
      -- Scenes a story line leaves out (the Lost Patrol's chapel segment skips TheRescue).
      if E.dropScene and E.dropScene(class) then
        Coop.log("scene " .. tostring(class) .. " left out here")
        return false
      end
      if not E.inEndOfScene and not E.inReplay and not E.gateOpen() then
        E.heldScenes = E.heldScenes or {}
        table.insert(E.heldScenes, {fname = fname, class = class, args = {...}})
        E.holdCurtain(true)
        Coop.log("scene " .. fname .. " " .. tostring(class) .. " held until the players have loaded")
        return false
      end
      -- PlayFP -> PlayFPNI -> Play run in sequence (partly asynchronously) for one scene;
      -- the client repeats that chain itself, so forward only its first call.
      local now = Net.CoopTime()
      local repeated = class == E.lastSceneClass and now - (E.lastSceneTime or 0) < 15
      if mode ~= "play" then E.beforeFpScene(class) else E.labelPlayScene(class) end
      E.sceneStartT = Net.CoopTime()
      E.skip = nil   -- skip votes count for one showing of a scene
      if not E.inEndOfScene and not E.inReplay and not repeated then
        Net.CoopSend(-1, 1, "scene|" .. mode .. "|" .. tostring(class))
        E.stats.scenes = (E.stats.scenes or 0) + 1
        E.lastSceneClass, E.lastSceneTime = class, now
      end
      return orig(class, ...)
    end
  end
  -- Skipping (Esc during a scene) is unanimous: every player's skip is a vote, the host
  -- skips for everyone when all players have voted.
  local origAbort = Scene.AbortScene
  E.hostAbort = function(...)
    E.skip = nil
    Net.CoopSend(-1, 1, "scene|abort|")
    return origAbort(...)
  end
  Scene.AbortScene = function(...)
    if Coop.fromHost or not Coop.inSession() or E.playerCount() <= 1 then return E.hostAbort(...) end
    E.voteSkip(0)
  end
end

------------------------------------------------------------------------------
-- Unanimous scene skip
--   skipvote|<scene>        client -> host
--   skipv|<votes>|<players> host -> all (shown as a label)
------------------------------------------------------------------------------

E.SKIP_TEXT = {en = "Skip scene: %d of %d players", ru = "Пропуск сцены: %d из %d игроков"}

function E.playerCount()
  return 1 + (tonumber(string.match(Net.CoopStatus(), "peers=(%d+)")) or 0)
end

function E.showSkip(votes, players)
  local lang = Coop.lang()
  local s = Coop.enc(string.format(E.SKIP_TEXT[lang] or E.SKIP_TEXT.en, votes, players), lang)
  Scorer.SetLabelText(s, Game.GetTime() + 6)
end

-- Host: peer votes to skip the scene that is playing.
function E.voteSkip(peer)
  if not Scene.IsPlaying or not Scene.SceneName then return end
  if not E.skip or E.skip.scene ~= Scene.SceneName then E.skip = {scene = Scene.SceneName, votes = {}} end
  E.skip.votes[peer] = true
  local n = 0
  for _ in pairs(E.skip.votes) do n = n + 1 end
  local players = E.playerCount()
  Coop.log(string.format("scene skip vote from %d: %d of %d", peer, n, players))
  if n >= players then
    E.hostAbort()
  else
    Net.CoopSend(-1, 1, "skipv|" .. n .. "|" .. players)
    E.showSkip(n, players)
  end
end

function E.installSceneClient()
  E.installReplay()
  local origEnd = Scene.EndOfScene
  Scene.EndOfScene = function(...)
    Coop.log("scene ended " .. tostring(Scene.SceneName))
    E.inEndOfScene = true
    if E.fpLabelPlay then E.fpLabel, E.fpLabelPlay = nil, nil end   -- a chained scene sets its own
    local ok, a, b = pcall(origEnd, ...)
    E.inEndOfScene = false
    E.finishFpLeftover()
    if not ok then Coop.log("EndOfScene error: " .. tostring(a)) end
    return a, b
  end
  for mode, fname in pairs(E.SCENE_FUNCS) do
    local orig = Scene[fname]
    E["scene_" .. fname] = orig
    Scene[fname] = function(class, ...)
      if E.dropScene and E.dropScene(class) then return false end
      -- A first-person scene the host started goes on by itself: the game walks the body to
      -- the scene's camera and calls Scene.Play from a scheduled function later.
      local chain = E.fpChain
      local continues = chain and chain.class == class and Net.CoopTime() - chain.t < E.FP_CHAIN_TIME
      if Coop.fromHost or E.inEndOfScene or E.inReplay or continues then
        -- (a chain this machine runs itself, from a scene's end, goes on the same way: the
        -- desert's HelicopterTrip after TheDreamC was dropped at its Scene.Play, 0.2.1; not
        -- one started by the host's skip, which skips it too: the client lost its body)
        local skipped = Net.CoopTime() - (E.lastAbort or -99) < 2
        if mode ~= "play" and not continues and not skipped then E.fpChain = {class = class, t = Net.CoopTime()} end
        if Coop.cfg.chainlog then
          Coop.log(string.format("chainlog: %s %s host %s end %s replay %s continues %s skipped %s", fname, tostring(class),
            tostring(Coop.fromHost), tostring(E.inEndOfScene), tostring(E.inReplay), tostring(continues), tostring(skipped)))
        end
        if mode ~= "play" then E.beforeFpScene(class) else E.labelPlayScene(class) end
        if mode ~= "play" or not continues then E.sceneStartT = Net.CoopTime() end
        return orig(class, ...)
      end
      E.stats.dropped = E.stats.dropped + 1
      return false
    end
  end
  -- Skipping is unanimous: a client's skip is its vote, the host decides.
  E.sceneAbort = Scene.AbortScene
  Scene.AbortScene = function(...)
    if Coop.fromHost then return E.sceneAbort(...) end
    -- (one vote per showing: a failed QTE plays the scene again)
    local key = tostring(Scene.SceneName) .. "@" .. tostring(E.sceneStartT)
    if Scene.SceneName and E.votedScene ~= key then
      E.votedScene = key
      Net.CoopSend(0, 1, "skipvote|" .. Scene.SceneName)
    end
  end
end

E.FP_CHAIN_TIME = 15   -- the walk to the scene's camera takes a second or two

function E.onScene(mode, class)
  E.votedScene = nil   -- a new scene (or a replay) can be voted on again
  E.stats.scenes = (E.stats.scenes or 0) + 1
  Coop.log("scene " .. mode .. " " .. tostring(class))
  if mode == "abort" then
    E.lastAbort = Net.CoopTime()
    -- Not while the scene is still being built here (a skip right as TheRescue started after
    -- the Lost Patrol's merge crashed the game: objref.h "!Refs", branch test 0.2.3): later.
    if Scene.IsPlaying and Net.CoopTime() - (E.sceneStartT or 0) < E.ABORT_SETTLE then
      E.abortAt = (E.sceneStartT or Net.CoopTime()) + E.ABORT_SETTLE
      Coop.log("scene abort held until the scene has settled")
    elseif Scene.IsPlaying then
      fromHost(Scene.AbortScene)
    end
    return
  end
  -- Already started here (this machine's own level script got there first: a player back
  -- from the Lost Patrol's side branch loads the chapel as the host's TheRescue plays): a
  -- second start made the scene twice ("Already exists"), and skipping it then crashed the
  -- game (objref.h "!Refs", branch test 0.2.3).
  local playing = Scene.IsPlaying and tostring(Scene.SceneName or "")
  local recent = class == E.lastSceneClass and Net.CoopTime() - (E.lastSceneTime or 0) < 10
  if playing == tostring(class) or playing == "DM_Scene_" .. tostring(class) or recent then
    Coop.log("scene " .. tostring(class) .. " already started here: the host's start not repeated")
    return
  end
  local fname = E.SCENE_FUNCS[mode]
  if mode ~= "play" then E.fpChain = {class = class, t = Net.CoopTime()} end
  if fname and Scene[fname] then fromHost(Scene[fname], class) end
end

-- A client finished loading the level: bring it to the host's current enemy state
-- (groups already activated, enemies spawned at runtime). Placed enemies exist on both
-- machines with the same names.
function E.sendCatchup(peer)
  local groups, spawns = 0, 0
  if NPC and NPC.Groups then
    for group in pairs(NPC.Groups) do
      if Game.GetSaveVar(init.LevelName .. ".EnemyGroup." .. group .. ".Status") == "1" then
        Net.CoopSend(peer, 1, "egroup|" .. group)
        groups = groups + 1
      end
    end
  end
  local e = Game.GetFirst()
  while e ~= nil do
    if isEnemy(e) and e.Life > 0 and string.sub(e.Name, 1, 6) == "Enemy_" then
      local p = e.Pos
      Net.CoopSend(peer, 1, string.format("espawn|%s|%s|%s|%.0f|%.0f|%.0f", e.Name, tostring(e.ActCtrl),
        tostring(e.EntityList), p.x, p.y, p.z))
      spawns = spawns + 1
    end
    e = Game.GetEntity(e.NextInSlot)
  end
  local parts = E.sendPartCatchup(peer)
  Coop.log(string.format("catch-up for peer %d: %d groups, %d spawned enemies, %d part states", peer, groups, spawns, parts))
  -- Doors and broken objects as the host has them (coop_world.lua).
  if CoopWorld and CoopWorld.sendState then CoopWorld.sendState(peer) end
  E.catchupSent = true
end

-- A client's hit: apply it as a human's hit (no AI team damage roll).
-- Bosses that take damage only on a weak part (Nanna, Utu, the gladiator, the puppet god:
-- their OnDamage reads uData.DamagedParts, filled by explosions, or the last shot's
-- oWeapHit.oBodyPiece) list their parts (uData.bListDamagedParts). A client's hit reached the
-- host as a bare number, with neither, so a client could never hurt them. The client sends
-- the part's bone and the damage it took; the host fills DamagedParts with it.
function E.hitPart(To, From, dmg, fresh)
  -- An exploding cultist's pustule: the piece the client's own shot has just hit (fresh: the
  -- caller has run SetLastBodyPiece for this shot); the host removes that pustule.
  if fresh and To.uData and To.uData.bBombs then
    local piece = To.oWeapHit and To.oWeapHit.oBodyPiece
    if piece and piece.bIsRagdollPart then return piece.oRagDollDamagePart.Name, dmg end
    return
  end
  if not (To.uData and To.uData.bListDamagedParts) then return end
  local best, bestDmg
  for name, d in pairs(To.uData.DamagedParts or {}) do
    if d.Damager == From.Name and (not bestDmg or d.Damage > bestDmg) then best, bestDmg = name, d.Damage end
  end
  To.uData.DamagedParts = nil   -- the boss's OnDamage clears them; it does not run here
  local piece = best and Game.GetEntity(best)
  if not piece then
    piece = To.oWeapHit and To.oWeapHit.oBodyPiece
    bestDmg = dmg
  end
  if piece and piece.bIsRagdollPart then
    return piece.oRagDollDamagePart.Name, bestDmg
  end
end

-- Host: the ragdoll part of a body with that bone (looked up once per body).
E.parts = {}
function E.partByBone(To, bone)
  local map = E.parts[To.Name]
  if not map then
    map = {}
    local e = Game.GetFirst()
    while e ~= nil do
      if e:IsType("PxBodyPhysics") and e.bIsRagdollPart then
        local owner = Game.GetRagdollPartOwner(e.Name)
        if owner and owner.Name == To.Name then map[e.oRagDollDamagePart.Name] = e.Name end
      end
      e = Game.GetEntity(e.NextInSlot)
    end
    E.parts[To.Name] = map
  end
  return map[bone]
end

function E.applyHit(enemyName, damage, attackerName, bone, partDamage)
  local To = Game.GetEntity(enemyName)
  local From = Game.GetEntity(attackerName)
  if not To or not From or To.Life <= 0 then return end
  if bone and bone ~= "" and To.uData and To.uData.bListDamagedParts then
    local part = E.partByBone(To, bone)
    if part then To.uData.DamagedParts = {[part] = {Damage = partDamage or damage, Damager = From.Name}} end
    E.bossHit = {name = To.Name, bone = bone, part = part, life = To.Life}
  end
  -- An exploding cultist loses a pustule only to a hit on that pustule, and only that one: the game
  -- reads the body piece the shot hit (CultistaExplosivo.OnDamage), which a message cannot set
  -- (oWeapHit.oBodyPiece is read-only from Lua), so the game's own RemoveNode does it.
  if bone and bone ~= "" and To.uData and To.uData.bBombs and CultistaExplosivo and not To.uData.Exploded then
    local removed = CultistaExplosivo.RemoveNode(To, bone)
    E.stats.bombHits = (E.stats.bombHits or 0) + 1
    if removed then E.stats.bombHitsRemoved = (E.stats.bombHitsRemoved or 0) + 1 end
    E.stats.hitsApplied = E.stats.hitsApplied + 1
    return
  end
  local factor = To.uData and To.uData.TeamDamageFactor
  if To.uData then To.uData.TeamDamageFactor = nil end
  Coop.applyingRemoteHit = true
  local ok, err = pcall(E.origDamage, From, To, damage, nil)
  Coop.applyingRemoteHit = false
  if To.uData then To.uData.TeamDamageFactor = factor end
  if not ok then Coop.log("applyHit error: " .. tostring(err)) end
  local bh = E.bossHit
  if bh then
    E.bossHit = nil
    Coop.log(string.format("hit %s by %s on %s (%s) life %s -> %s", bh.name, From.Name, bh.bone, tostring(bh.part),
      tostring(bh.life), tostring(To.Life)))
  end
  E.stats.hitsApplied = E.stats.hitsApplied + 1
end

------------------------------------------------------------------------------
-- Client
------------------------------------------------------------------------------

-- Story and spawn logic runs on the host only. Each guard lets calls through while
-- Coop.fromHost is set (the client replaying a host decision).
local function guard(tbl, name)
  local f = tbl and tbl[name]
  if type(f) ~= "function" then return end
  tbl[name] = function(...)
    if Coop.fromHost then return f(...) end
    -- A host callback replayed by coop_world.lua runs the level's own effects here;
    -- enemies, saves and level changes stay dropped (the host sends those itself).
    if Coop.replay and tbl == MapCallbacks then return f(...) end
    -- A replayed callback's own gates count here as on the host (every call is replayed):
    -- "if not SaveGame.FlagCounter(name, n) then return end" let nothing after it run on a
    -- client, so objects, triggers, debris and revives that follow such a gate (73 in the
    -- levels) stayed in the level-start state there (audit 0.2.2 A1).
    if Coop.replay and tbl == SaveGame and name == "FlagCounter" then return f(...) end
    if tbl == MapCallbacks and CoopWorld then CoopWorld.onLocalCallback(name, ...) end
    E.stats.dropped = E.stats.dropped + 1
  end
  return f
end

-- Enemy action events that tell the enemy's AI an appearance ended (the psychic commander, the
-- Firstborn, the Sumerians: oAI:OnAfterAppear / OnAfterDisappear). A client's enemies run no
-- AI (driveEnemies), and the call reached into AI state not kept up there: the client crashed
-- when the psychic commander's disappearance ended (WWII_PillBoxes, split test 0.2.7). On a
-- client only the rest of the event runs (ragdoll, effects).
E.AI_EVENTS = {
  PsichicCommander = {OnAfterDisappear = {"DeActiveRagdoll"}, OnAfterAppear = {"ActiveRagdoll"}},
  EvilFirstBorn = {OnAfterDisappear = {}, OnAfterAppear = {}},
  SummerianNANNA = {OnAfterDisappear = {"FXShieldOff", "FXHeartProtectionOff"},
                    OnAfterAppear = {"FXShieldOn", "FXHeartProtectionOn"}},
  SummerianUTU = {OnAfterDisappear = {"FXShieldOff", "FXHeartProtectionOff"},
                  OnAfterAppear = {"FXShieldOn", "FXHeartProtectionOn"}},
}
function E.guardAIEvents()
  for cls, evs in pairs(E.AI_EVENTS) do
    local t = _G[cls]
    for ev, rest in pairs(evs) do
      local orig = t and t[ev]
      -- (the wrapper is kept to tell it from the game's function a script reload put back)
      if type(orig) == "function" and not (t.coopAIGuard and t.coopAIGuard[ev] == orig) then
        t.coopAIGuard = t.coopAIGuard or {}
        t[ev] = function(name, ...)
          if not (Coop.isClient() and Coop.cfg.myId) then return orig(name, ...) end
          Coop.log("enemy event " .. cls .. "." .. ev .. " of " .. tostring(name) .. " without its AI (host-driven)")
          for _, f in ipairs(rest) do
            local ok, err = pcall(t[f], name)
            if not ok then Coop.log("enemy event " .. cls .. "." .. f .. ": " .. tostring(err)) end
          end
        end
        t.coopAIGuard[ev] = t[ev]
      end
    end
  end
end

function E.installClient()
  E.guardAIEvents()
  E.installFades()
  -- The reaction of a strong hit comes from the host (`phit`); the swing of this machine's own copy of
  -- the enemy (which may have missed on the host) plays none.
  if Soldier and Soldier.DoHitStrong then
    local origHS = Soldier.DoHitStrong
    Soldier.DoHitStrong = function(usr, ...)
      if E.allowHitStrong then return origHS(usr, ...) end
    end
    E.origHitStrong = origHS
  end
  -- Every map callback (area triggers, use actions, scene ends, pulsers).
  local n = 0
  if MapCallbacks then
    for k, v in pairs(MapCallbacks) do
      if type(v) == "function" then guard(MapCallbacks, k) n = n + 1 end
    end
  end
  if AreaTriggers then
    guard(AreaTriggers, "OnEnterPluser")
    guard(AreaTriggers, "OnExitPluser")
  end
  E.origActivate = guard(NPC, "ActivateEnemyGroup")
  E.origCreate = guard(NPC, "CreateWithAI")
  for _, f in ipairs({"ActivateNextEnemy", "ScheduleActivationOfNextEnemy", "Start", "Stop"}) do
    guard(EnemyGen, f)
  end
  for _, f in ipairs({"NewLevel", "NewLevelNow", "AutoSaveWaypoint", "FlagCounter", "LoadLevel",
                      "LoadWaypoint", "Restart"}) do
    guard(SaveGame, f)
  end
  Coop.log("client guards: " .. n .. " map callbacks")

  local origDamage = Weapons.DoDamage
  E.origDamage = origDamage
  Weapons.DoDamage = function(From, To, Damage, BodyMultiplier)
    if Coop.fromHost or not From or not To then
      return origDamage(From, To, Damage, BodyMultiplier)
    end
    if Coop.isLocalPlayer(From.Name) and isEnemy(To) then
      -- Resolve the body-part multiplier locally (it needs this machine's hit), then
      -- report the final damage to the host instead of applying it.
      local dmg = Damage
      if CoopSmod then BodyMultiplier = CoopSmod.headshot(To, From, BodyMultiplier) end
      if BodyMultiplier ~= nil then
        To:SetLastBodyPiece(From)
        local piece = To.oWeapHit and To.oWeapHit.oBodyPiece
        if piece then
          local m = piece.oRagDollDamagePart.Damage
          dmg = m > 1 and Damage * m ^ BodyMultiplier or Damage * m
        end
      end
      local bone, partDmg = E.hitPart(To, From, dmg, BodyMultiplier ~= nil)
      Net.CoopSend(0, 1, string.format("hit|%s|%.2f|%s|%s|%.2f", To.Name, dmg, From.Name, bone or "", partDmg or 0))
      E.stats.hitsSent = E.stats.hitsSent + 1
      if BodyImpact and BodyImpact.OnShot then pcall(BodyImpact.OnShot, To.Name) end
      return false
    end
    if From:IsType("WalkChar") and (From.TgType == "red" or not Coop.isLocalPlayer(From.Name)) then
      -- Enemy damage comes from the host (pdmg); puppets fire for show only.
      E.stats.dropped = E.stats.dropped + 1
      return false
    end
    -- So does a hazard's on this player's body (a barrel, a thrown object: the host's copy
    -- hit it too and sent pdmg; taken here as well it counted twice, audit 0.2.2 A12).
    if not From:IsType("WalkChar") and Coop.isLocalPlayer(To.Name) and Coop.cfg.hazardlocal ~= false then
      E.stats.dropped = E.stats.dropped + 1
      E.stats.hazards = (E.stats.hazards or 0) + 1
      return false
    end
    return origDamage(From, To, Damage, BodyMultiplier)
  end
end

-- Part state from the host (see E.installParts). An enemy that does not exist here yet (a spawn on
-- its way) gets it when it does.
E.pendingParts = {}
function E.applyPart(ent, kind, data)
  local u = ent.uData
  if not u then return end
  if kind == "bombs" then
    if not (u.bBombs and CultistaExplosivo and CultistaExplosivo.Bombs) then return end
    local n = 0
    for i, node in ipairs(CultistaExplosivo.Bombs) do
      local on = string.sub(data, i, i) == "1"
      u.bBombs[node] = on
      ent["bShowNode_" .. node] = on
      if on then n = n + 1 end
      local rp = ent.bActive and Game.GetRagdollPart(ent.Name, node)
      if rp then rp.bWeakPoint = on end
    end
    u.rBombs = n
    -- the cultist's life is its pustules (the game's rule); PrevLife with it, so that nothing reads
    -- the write as damage
    if n > 0 and (ent.Life or 0) > 0 then
      ent.Life = (CultistaExplosivo.BombLife or 50) * n
      ent.PrevLife = ent.Life
    end
  elseif kind == "bomb" then
    if not u.bBombs then return end
    if u.bBombs[data] then
      u.bBombs[data] = false
      u.rBombs = (u.rBombs or 1) - 1
    end
    ent["bShowNode_" .. data] = false
    if ent.bActive then pcall(Impact.DoImpact, "Body/Pustule", "DoFromNode " .. ent.Name .. "#" .. data) end
    local rp = Game.GetRagdollPart(ent.Name, data)
    if rp then rp.bWeakPoint = false end
  elseif kind == "seal" then
    if not u.bSeals then return end
    if u.bSeals[data] then
      pcall(Behemoth.FXBreakSeal, ent.Name, data)
      u.bSeals[data] = false
      ent["bShowNode_" .. data] = false
      local broken = u.bBrokeSeals and u.bBrokeSeals[data]
      if broken then ent["bShowNode_" .. broken] = true end
      if u.lifeSeals then u.lifeSeals[data] = 0 end
      u.numberSeals = (u.numberSeals or 1) - 1
      local rp = Game.GetRagdollPart(ent.Name, data)
      if rp then rp.bWeakPoint = false end
    end
  end
  E.stats.partsApplied = (E.stats.partsApplied or 0) + 1
  if kind ~= "bombs" then E.stats[kind .. "sGone"] = (E.stats[kind .. "sGone"] or 0) + 1 end
end

function E.drainParts()
  local keep = {}
  for _, p in ipairs(E.pendingParts) do
    local ent = Game.GetEntity(p[1])
    if ent then
      local ok, err = pcall(E.applyPart, ent, p[2], p[3])
      if not ok and not E.partError then
        E.partError = true
        Coop.log("part error: " .. tostring(err))
      end
    elseif Net.CoopTime() - p[4] < 20 then
      keep[#keep + 1] = p
    end
  end
  E.pendingParts = keep
end

function E.onSnapshot(body, rt)
  E.snapSeen = true
  local now = Net.CoopTime()
  for item in string.gmatch(body, "[^;]+") do
    local name, x, y, z, yaw, action, flags, pitch, life = string.match(item,
      "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]*),(%d+),(-?[%d%.]*),?(%d*)$")
    if name then
      local fl = tonumber(flags) or 1
      local st = {x = tonumber(x), y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw),
                  action = action, active = fl % 2 == 1, shot = math.floor(fl / 2) % 2 == 1, faded = fl >= 4, pitch = tonumber(pitch) or 0, life = tonumber(life), t = now, rt = rt}
      if Coop.pushState(name, st, Coop.TICK * E.SNAP_EVERY) then E.targets[name] = st end
    end
  end
end

-- Like the players' bodies (coop.lua), host enemies are drawn between two snapshots a little
-- in the past and their actions play without root motion, which moved them a second time
-- (fork MAK-PIVO/jericho-coop). Grabs keep theirs: the grab animation places the enemy on the
-- grabbed player.
local function grabbing(e, action)
  if string.find(action or "", "Grab", 1, true) then return true end
  local g = QTE and QTE.InGame and QTE.InGame.en
  return g ~= nil and g.Name == e.Name
end

-- The host's enemy pulls its trigger: here the puppet's own control field is set the way the
-- squad puppets' is (coop.lua drivePuppets), so the game's shot code plays the sound, the
-- muzzle flash and the tracer. Its damage is dropped (the client's Weapons.DoDamage); the
-- host's own shot hurts. Written only when it changes, so melee enemies are left alone.
E.shotSet = {}
function E.driveShot(e, st, now)
  if Coop.cfg.enemyfx == false then return end   -- (test switch: how it looked before 0.2.8)
  local want = st.shot and now - st.t < 0.3
  if want == (E.shotSet[e.Name] or false) then
    if want then e.ViewAng = V3D(st.pitch or 0, st.yaw, 0) end
    return
  end
  local owc = e.owc
  if not owc then return end
  E.shotSet[e.Name] = want
  if want then
    e.ViewAng = V3D(st.pitch or 0, st.yaw, 0)
    E.stats.shotsOn = (E.stats.shotsOn or 0) + 1
    if (E.stats.shotsOn or 0) <= 20 then
      Coop.log(string.format("enemy fire shown: %s (%s) action=%s pitch=%s", e.Name, tostring(e.ActCtrl), tostring(e.Action),
        tostring(st.pitch)))
    end
  end
  owc.Shot = want and 1 or 0
end

-- Life: the host's percentage (last snapshot field) applied to this copy's own life, so that hit logic
-- and bars here agree with the fight. Never to 0 (the death comes with `edie`; a second kill here would
-- run the death twice), PrevLife with it (the engine reads a bigger gap as damage and calls OnDamage),
-- not for enemies whose life is their parts (Behemoth seals, pustules) and only for changes of 3 points.
function E.driveLife(e, st)
  if not st.life or Coop.cfg.elife == false then return end
  local u = e.uData
  if u and (u.bBombs or u.bSeals) then return end
  local name = e.Name
  local base = E.cLife[name]
  if not base then
    E.cLife[name] = e.Life
    base = e.Life
  end
  local last = E.lifeSet[name] or 100
  if math.abs(st.life - last) < 3 or (e.Life or 0) <= 0 then return end
  local want = math.max(1, math.floor(base * st.life / 100 + 0.5))
  E.lifeSet[name] = st.life
  e.Life = want
  e.PrevLife = want
  E.stats.lifeSet = (E.stats.lifeSet or 0) + 1
end
E.cLife, E.lifeSet = {}, {}

-- Fade state: the host's (flags bit 2) against this copy's own. After 0.4 s of disagreement the fade
-- is played here (the animation event that should have done it was missed).
function E.driveFade(e, st, now)
  if Coop.cfg.fadefix == false then return end   -- (test switch)
  local want = st.faded or false
  if want == (E.fadeSet[e.Name] or false) then
    E.fadeDiff[e.Name] = nil
    return
  end
  local since = E.fadeDiff[e.Name]
  if not since then E.fadeDiff[e.Name] = now return end
  if now - since < 0.4 then return end
  E.fadeDiff[e.Name] = nil
  E.stats.fadesFixed = (E.stats.fadesFixed or 0) + 1
  Coop.log(string.format("fade re-asserted: %s %s (%s)", e.Name, want and "out" or "in", tostring(e.ActCtrl)))
  if want then NPC.DisolveEntity(e.Name, 0.3) else NPC.AppearEntity(e.Name, 0.5) end
end

-- Every frame on a client: host enemies follow the snapshots; no enemy runs local AI.
function E.driveEnemies(dt)
  if #E.pendingParts > 0 then E.drainParts() end
  local follow = 1 - (1 - E.FOLLOW) ^ (math.min(dt, 0.25) / 0.05)
  local now = Net.CoopTime()
  local localKeys = Coop.keepLocalRootMotion()
  for name, st in pairs(E.targets) do
    local e = Game.GetEntity(name)
    if not e then
      E.stats.missing = E.stats.missing + 1
      E.targets[name] = nil
    elseif e.Life <= 0 or now - st.t > 2 then
      E.targets[name] = nil   -- dead, or no longer in the host's snapshots
      if E.shotSet[name] then
        E.shotSet[name] = nil
        if e.owc then e.owc.Shot = 0 end
      end
    else
      if st.active and not e.bActive then e.bActive = true end
      if e.oAI and e.oAI.bEnable then e.oAI.bEnable = false end
      local tg = Coop.puppetTarget(name, now) or st
      local grab = grabbing(e, tostring(e.Action))
      if not grab then Coop.suppressRootMotion(e, localKeys) end
      local pos = e.Pos
      local dx, dy, dz = tg.x - pos.x, tg.y - pos.y, tg.z - pos.z
      local err = math.sqrt(dx * dx + dz * dz)
      if err > E.SNAP_DIST or math.abs(dy) > E.SNAP_DIST then
        e.Pos = V3D(tg.x, tg.y, tg.z)
      elseif not grab then
        e.Pos = V3D(pos.x + dx * follow, pos.y + dy * follow, pos.z + dz * follow)
      end
      e.Ang = V3D(0, tg.yaw, 0)
      if st.action ~= "" and st.action ~= E.applied[name] and e.Action ~= st.action
         and not string.find(st.action, "Death") and st.action ~= Coop.cfg.dropact then
        e.ForceAction = st.action
        E.applied[name] = st.action
      end
      E.driveShot(e, st, now)
      E.driveFade(e, st, now)
      E.driveLife(e, st)
    end
  end
end

-- Enemies the client knows but the host does not drive must not think either.
E.GENERATOR_FUNCS = {"ActivateNextEnemy", "ScheduleActivationOfNextEnemy", "ActivateEnemy", "ActivateSpontaneousEnemy"}

-- Client: an enemy active here but in none of the host's snapshots for ORPHAN_TIME (the host
-- has it off, dead or not at all) is switched off here too; it stood or walked around,
-- harmless and shootable, and the hits on it counted nowhere (audit 0.2.2 A3, owner's Steam
-- test). A later snapshot of it switches it on again (driveEnemies).
E.ORPHAN_TIME = 2.5
E.orphanSince = {}
function E.freezeLocalEnemies()
  local now = Net.CoopTime()
  -- (not before the host's first snapshot here: a client that loads first switched the
  -- level's own enemies off while the host was still loading, review 0.2.2)
  local gate = (E.gateOpen == nil or E.gateOpen()) and E.snapSeen
  local e = Game.GetFirst()
  while e ~= nil do
    if isEnemy(e) and e.Life > 0 and not E.targets[e.Name] then
      if e.oAI and e.oAI.bEnable then e.oAI.bEnable = false end
      if e.bActive and gate then
        local since = E.orphanSince[e.Name]
        if not since then
          E.orphanSince[e.Name] = now
        elseif now - since > E.ORPHAN_TIME then
          e.bActive = false
          E.orphanSince[e.Name] = nil
          E.stats.orphans = (E.stats.orphans or 0) + 1
        end
      else
        E.orphanSince[e.Name] = nil
      end
    elseif E.orphanSince[e.Name] then
      E.orphanSince[e.Name] = nil
    end
    e = Game.GetEntity(e.NextInSlot)
  end
end

------------------------------------------------------------------------------
-- Dispatch
------------------------------------------------------------------------------

function E.onMessage(peer, f)
  local kind = f[1]
  if kind == "e" and Coop.isClient() then
    if f[3] then E.onSnapshot(f[3], tonumber(f[2])) else E.onSnapshot(f[2] or "") end
  elseif kind == "espawn" and Coop.isClient() then
    local name, class, group = f[2], f[3], f[4]
    if not Game.GetEntity(name) and E.origCreate then
      -- Lists the mod adds on the host (story splits' waves) exist here only from their
      -- first enemy on.
      if NPC.Groups and not NPC.Groups[group] and CoopSplits and CoopSplits.newList then
        CoopSplits.newList(group)
      end
      -- The engine names a new enemy from NPC.Counter: the host's number, so the name is the
      -- host's from the start (renaming afterwards could clash with a later one).
      local num = tonumber(string.match(name, "^Enemy_(%d+)$"))
      if num then NPC.Counter = num end
      local e = fromHost(NPC.CreateWithAI, class, tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), group)
      if type(e) ~= "string" and e and e.Name ~= name then e.Name = name end
    end
    E.stats.spawns = E.stats.spawns + 1
  elseif kind == "egroup" and Coop.isClient() then
    -- A generator group fills itself (EnemyGen, random class and spawn point): here it must
    -- not, its enemies come one by one from the host (espawn). Replaying the generator made
    -- enemies only this machine had, under names the host gave others (audit 0.2.2 A2).
    local saved = {}
    if EnemyGen then
      for _, fn in ipairs(E.GENERATOR_FUNCS) do
        if type(EnemyGen[fn]) == "function" then
          saved[fn] = EnemyGen[fn]
          EnemyGen[fn] = function() end
        end
      end
    end
    fromHost(NPC.ActivateEnemyGroup, f[2])
    for fn, orig in pairs(saved) do EnemyGen[fn] = orig end
    E.stats.groups = E.stats.groups + 1
  elseif kind == "edie" and Coop.isClient() then
    local e = Game.GetEntity(f[2])
    if e and e.Life > 0 then
      -- An enemy the host removes quietly, or one never shown here, leaves without the
      -- death effects: dozens of them at once (a generator's pool) overflowed the effect
      -- pool and asserted in EffectRagdoll (G3 test, alk_bunker_01).
      if (f[3] == "1" or not e.bActive) and e.uData then e.uData.RemoveNow = true end
      e.Invulnerable = 0
      e.Life = 0
    elseif e then
      -- already dead here (a kill of this machine's own before the host's word): counted, the death does not run twice
      E.stats.edieLate = (E.stats.edieLate or 0) + 1
    end
    E.targets[f[2]] = nil
    E.stats.deaths = E.stats.deaths + 1
  elseif kind == "epart" and Coop.isClient() then
    E.pendingParts[#E.pendingParts + 1] = {f[2], f[3], f[4] or "", Net.CoopTime()}
    E.drainParts()
  elseif kind == "eact" and Coop.isClient() then
    local e = Game.GetEntity(f[2])
    if e and (e.Life or 0) > 0 and f[3] and f[3] ~= "" and f[3] ~= Coop.cfg.dropact then
      E.stats.actsApplied = (E.stats.actsApplied or 0) + 1
      if e.Action ~= f[3] then e.ForceAction = f[3] end
      E.applied[f[2]] = f[3]
      if E.stats.actsApplied <= 60 then
        Coop.log(string.format("boss action applied %s: %s (was %s)", f[2], f[3], tostring(e.Action)))
      end
    end
  elseif kind == "pfire" then
    local usr = Game.GetEntity(f[2])
    if usr and Coop.isLocalPlayer(f[2]) and not (usr.uData and usr.uData.bProtection) then
      usr.FireRemainTime = tonumber(f[3]) or 0.3
      usr.FireDelayTime = tonumber(f[4]) or 0.015
      usr.FireAtenuationFactor = 0
      usr.Pyromaniac = f[5] or ""
      E.stats.firesApplied = (E.stats.firesApplied or 0) + 1
    end
  elseif kind == "phit" then
    local usr = Game.GetEntity(f[2])
    if usr and Coop.isLocalPlayer(f[2]) then
      E.stats.hitStrongApplied = (E.stats.hitStrongApplied or 0) + 1
      E.allowHitStrong = true
      pcall(E.origHitStrong or Soldier.DoHitStrong, usr)
      E.allowHitStrong = false
    end
  elseif kind == "pdmg" then
    local usr = Game.UsrEntity(0)
    if usr and usr.Name ~= f[2] and Coop.isLocalPlayer(f[2]) then usr = Game.GetEntity(f[2]) end
    if usr and usr.Name == f[2] then
      local from = Game.GetEntity(f[4])
      if not from then E.stats.pdmgNoShooter = (E.stats.pdmgNoShooter or 0) + 1 end
      from = from or usr
      fromHost(E.origDamage, from, usr, tonumber(f[3]), nil)
      E.stats.pdmgApplied = E.stats.pdmgApplied + 1
    end
  elseif kind == "hit" and Coop.isHost() then
    E.applyHit(f[2], tonumber(f[3]), f[4], f[5], tonumber(f[6]))
  elseif kind == "scene" and Coop.isClient() then
    E.onScene(f[2], f[3])
  elseif kind == "skipvote" and Coop.isHost() then
    if f[2] == Scene.SceneName then E.voteSkip(peer) end
  elseif kind == "skipv" and Coop.isClient() then
    E.showSkip(tonumber(f[2]) or 0, tonumber(f[3]) or 0)
  elseif kind == "level" and Coop.isClient() then
    E.onLevel(f[2])
  elseif kind == "lready" and Coop.isHost() then
    if string.lower("levels/" .. (f[2] or "")) == Coop.level then
      E.sendCatchup(peer)
      E.readyPeers[peer] = true
    end
  else
    return false
  end
  return true
end

-- The engine itself hands enemies their targets, among squad bodies whose AI is on (the Lua
-- target functions above are not even called in fights: dev 'targetprobe', 0.2.2). A network
-- player's body has its AI off (the network drives it), so enemies never went for the other
-- players: the host's squad took every attack, the clients none (owner's Steam test, 0.2.1:
-- 0 remote targets all game, 2 damage events a level). Every second, an enemy whose target is
-- clearly farther than a human player's body it can see goes for that body, the game's own
-- way (AIEnemy.DoAttack); then it keeps its target for a few seconds.
E.RETARGET_EVERY = 20       -- ticks
E.RETARGET_HOLD = 4         -- seconds an enemy keeps a target it was given
E.RETARGET_NEARER = 0.8     -- the human must be at most this share of the current target's distance
E.RETARGET_RANGE = 3000
E.retargetAt = {}
function E.retarget()
  if Coop.cfg.retarget == false or not (AIEnemy and AIEnemy.DoAttack) then return end
  local humans = {}
  for name in pairs(Coop.owners or {}) do
    if Coop.isRemoteOwned(name) and not (Coop.storyDriven and Coop.storyDriven[name]) then
      local b = Game.GetEntity(name)
      if b and (b.Life or 0) > 0 and b.bActive ~= false and b.Active ~= 0 then humans[#humans + 1] = b end
    end
  end
  if #humans == 0 then return end
  local now = Game.GetTime()
  local e = Game.GetFirst()
  while e ~= nil do
    if isEnemy(e) and (e.Life or 0) > 0 and e.oAI and e.oAI.bEnable and (E.retargetAt[e.Name] or 0) <= now then
      local cur = e.AI_ObjectiveDin or ""
      if not Coop.isRemoteOwned(cur) then
        local curEnt = cur ~= "" and Game.GetEntity(cur)
        local curD = curEnt and (curEnt.Pos - e.Pos):mod2D()
        if not curD then
          -- An enemy with no target yet (waiting, sometimes for a story trigger): only a player
          -- nearer than every squad member here, who the game would see it react to (it
          -- woke waiting enemies as soon as a joining player was in sight, review 0.2.2).
          curD = math.huge
          for _, n in ipairs(Coop.SQUAD) do
            local s = not Coop.isRemoteOwned(n) and Coop.squadEnt(n)
            if s and (s.Life or 0) > 0 and s.bActive ~= false then
              curD = math.min(curD, (s.Pos - e.Pos):mod2D())
            end
          end
        end
        local best, bestD
        for _, h in ipairs(humans) do
          local d = (h.Pos - e.Pos):mod2D()
          if d < E.RETARGET_RANGE and d < curD * E.RETARGET_NEARER and (not bestD or d < bestD) then
            local ok, vis = pcall(AI.IsVisibleEntityChar, e.Name, h.Name, math.pi)
            if ok and vis then best, bestD = h, d end
          end
        end
        if best then
          local ok, err = pcall(AIEnemy.DoAttack, e, best)
          E.retargetAt[e.Name] = now + E.RETARGET_HOLD
          if ok then
            E.stats.remoteTargets = (E.stats.remoteTargets or 0) + 1
          elseif not E.retargetError then
            E.retargetError = true
            Coop.log("retarget error: " .. tostring(err))
          end
        end
      end
    end
    e = Game.GetEntity(e.NextInSlot)
  end
end

E.ABORT_SETTLE = 1.5   -- s after a scene's start before a skip is carried out

function E.update()
  if E.abortAt and Net.CoopTime() >= E.abortAt then
    E.abortAt = nil
    if Scene.IsPlaying then fromHost(Scene.AbortScene) end
  end
  if Coop.isHost() then
    if Coop.frame % E.SNAP_EVERY == 0 then E.snapshot() end
    if Coop.frame % 90 == 0 then E.installMelee() E.installParts() E.installFlames() E.installMissileRef() E.installBloodHit() E.installHitStrong() end   -- (an enemy class whose script loads later)
    if Coop.frame % E.RETARGET_EVERY == 0 then
      local ok, err = pcall(E.retarget)
      if not ok and not E.retargetError then E.retargetError = true Coop.log("retarget error: " .. tostring(err)) end
    end
    E.flushHeldScenes()
  elseif Coop.isClient() then
    -- Tell the host this level is loaded so it sends the current enemy state.
    if not E.readySent and Coop.cfg.myId then
      E.readySent = true
      Net.CoopSend(0, 1, "lready|" .. string.sub(Game.GetLevelPath(), 8))
    end
    if Coop.frame % 10 == 0 then E.freezeLocalEnemies() end
    -- (an enemy class whose script loads later in the level)
    if Coop.frame % 90 == 0 then E.guardAIEvents() end
  end
end

function E.report()
  local s = E.stats
  if Coop.isClient() then
    local n = 0
    for _ in pairs(E.targets) do n = n + 1 end
    E.lastCount = "driven:" .. n
  end
  local line = string.format("enemies=%s rtargets=%d hits=%d/%d pdmg=%d/%d spawns=%d groups=%d deaths=%d dropped=%d snaps=%d scenes=%d scaled=%d orphans=%d",
    tostring(E.lastCount or "-"), s.remoteTargets or 0, s.hitsSent, s.hitsApplied, s.pdmgSent, s.pdmgApplied, s.spawns,
    s.groups, s.deaths, s.dropped, s.snapshots, s.scenes or 0, s.scaled or 0, s.orphans or 0)
  -- Enemy fire (host: shots / aimed at a remote body / engine hit one / ray passed through one;
  -- pdmg by source), client: fx played. See E.noteShot.
  if s.eShots then
    -- shots: all / aimed at a remote body / engine hit a remote body / given a hit by the ray test;
    -- reference: shots aimed at this machine's own player and how many hit (engine trace)
    line = line .. string.format(" eshots=%d at-remote %d hit-remote %d fixed %d (aimed elsewhere %d) | at-local %d hit-local %d (capsule 20/27/35/45: %d/%d/%d/%d) at-ai %d hit-ai %d",
      s.eShots, s.eShotAtRemote or 0, s.eShotHitRemote or 0, s.eShotFixed or 0, s.eShotFixedOther or 0, s.atLocal or 0, s.hitLocal or 0,
      s.geoLocal20 or 0, s.geoLocal27 or 0, s.geoLocal35 or 0, s.geoLocal45 or 0, s.atAi or 0, s.hitAi or 0)
  end
  if s.mSwingLocal or s.mSwingRemote or s.mSwingAi then
    line = line .. string.format(" melee swings local %d hit %d remote %d hit %d(fixed %d) ai %d hit %d", s.mSwingLocal or 0,
      s.mHitLocal or 0, s.mSwingRemote or 0, (s.mHitRemote or 0) + 0, s.mFix or 0, s.mSwingAi or 0, s.mHitAi or 0)
  end
  if s.killsRemote or s.killsLocal then
    line = line .. string.format(" kills local %d remote %d", s.killsLocal or 0, s.killsRemote or 0)
  end
  if s.partsSent or s.partsApplied or s.bombHits then
    line = line .. string.format(" parts=%d/%d seals=%d bombs=%d bombhits=%d/%d", s.partsSent or 0, s.partsApplied or 0,
      s.sealsGone or 0, s.bombsGone or 0, s.bombHitsRemoved or 0, s.bombHits or 0)
  end
  if s.actsSent or s.actsApplied or s.fadesFixed then
    line = line .. string.format(" bossacts=%d/%d fades-fixed=%d", s.actsSent or 0, s.actsApplied or 0, s.fadesFixed or 0)
  end
  if s.flameHits or s.firesApplied or s.missileHits or s.hitStrong or s.hitStrongApplied then
    line = line .. string.format(" flames=%d/%d missiles=%d hitstrong=%d/%d", s.flameHits or 0, s.firesApplied or 0,
      s.missileHits or 0, s.hitStrong or 0, s.hitStrongApplied or 0)
  end
  if s.flameSegs then
    -- flame segments tested / near a remote body, hit by the capsule test; reference on the host's own body: segments
    -- near it, the engine's lines that hit it, and what the capsule test says at 27/45/60/80 units
    line = line .. string.format(" flame-segs=%d near-remote %d hit %d (capsule 27/45/60/80: %d/%d/%d/%d) | near-local %d engine-hit %d (capsule: %d/%d/%d/%d)",
      s.flameSegs, s.flameNearRemote or 0, s.flameSegHit or 0, s.flameGeoRemote27 or 0, s.flameGeoRemote45 or 0,
      s.flameGeoRemote60 or 0, s.flameGeoRemote80 or 0, s.flameNearLocal or 0, s.flameHitLocal or 0,
      s.flameGeoLocal27 or 0, s.flameGeoLocal45 or 0, s.flameGeoLocal60 or 0, s.flameGeoLocal80 or 0)
  end
  if s.missileNearLocal or s.missileHitLocal or s.pilumThrownRemote or s.pilumThrownLocal then
    line = line .. string.format(" pilum thrown at remote %d local %d ai %d, near-local %d engine-hit-local %d", s.pilumThrownRemote or 0,
      s.pilumThrownLocal or 0, s.pilumThrownAi or 0, s.missileNearLocal or 0, s.missileHitLocal or 0)
  end
  if s.lifeSet then line = line .. " life-set=" .. s.lifeSet end
  if s.edieLate then line = line .. " edie-late=" .. s.edieLate end
  if s.shotsOn then line = line .. " fire-shown=" .. s.shotsOn end
  if E.pdmgBy then
    local t = {}
    for k, v in pairs(E.pdmgBy) do t[#t + 1] = k .. "=" .. v end
    table.sort(t)
    line = line .. " pdmgby=" .. table.concat(t, ",")
  end
  return line
end

-- Scene hooks go in as soon as this file loads: levels schedule their opening scene for
-- the first game tick (wwii_biggates MapInit.main), before the first co-op tick.
function E.installScenes()
  if E.scenesInstalled or not Scene or not Scene.Play or not Scene.EndOfScene then return end
  if not (Coop.isHost() or Coop.isClient()) then return end
  E.scenesInstalled = true
  if Coop.isHost() then E.installSceneHost() else E.installSceneClient() end
  E.installFpRestore()
  Coop.log("scene hooks installed as " .. tostring(Coop.cfg.role))
end

function E.install()
  if E.installed or not NPC or not Weapons then return end
  E.installed = true
  if Coop.isHost() then E.installHost() elseif Coop.isClient() then E.installClient() end
  E.installScenes()
  if SaveGame and Coop.isHost() then E.installLevelHost() end
  Coop.log("enemies installed as " .. tostring(Coop.cfg.role))
end

E.installScenes()

-- Texts of the other languages (Coop.addLangs).
Coop.addLangs(E.EYES, "CoopEnemies.EYES")
Coop.addLangs(E.WAIT, "CoopEnemies.WAIT")
Coop.addLangs(E.SKIP_TEXT, "CoopEnemies.SKIP_TEXT")
