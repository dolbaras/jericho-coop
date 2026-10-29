-- Jericho co-op: what the other players' bodies (and the AI bodies of the host) do, seen on this
-- machine. A puppet is placed and walked from the owner's movement inputs (Coop.drivePuppets);
-- everything else the body does on the owner's machine (falling when downed, getting up, being hit,
-- reloading, hacking...) is an action the engine plays there and nothing here, so these bodies
-- stood still while the original fell or struggled (owner, 0.2.7: "wounded squad members stand
-- instead of falling"). The inventory of all actions and how each is triggered:
-- docs/ally-animations.md.
--
-- First slice (0.2.8), driven by one call per puppet and frame from Coop.drivePuppets:
--   * Downed: the owner's life is 0 (CoopTeam.syncPuppetLife sets the puppet's Life to 0, which
--     does not make the engine play the death: Soldier.OnDeath is called by the engine on a
--     killing hit only). The puppet gets what Soldier.OnDeath gives: AgonyInit / Agony2Init (the
--     variant the owner plays) with its loop, no powers, and the revive function (Team.OnUseDeathPlayer,
--     so a Rawlings here can revive it).
--   * Revived: one Team.RevivePlayer call per revive (it set the End action again every frame and
--     flipped Agony to Agony2End), the engine's Soldier.Revive at the end of the End action gives the
--     life back; after REVIVE_MAX s without it the owner's life is set.
--   * One-shots of the owner's body (A.ONESHOT: hits, reloads, hacks, powers...) are played once on
--     the puppet when the owner's action changes to one of them (Coop.mirrorArms plays the strikes,
--     reloads and powers the first-person arms name; this covers the third-person actions it has
--     no name for, and the AI bodies of the host, which have no first-person arms).
--   * Actions seen on puppets that are neither locomotion nor known are logged once (cfg.animlog:
--     every one) to complete the inventory.
CoopAnim = CoopAnim or {}
local A = CoopAnim
local cfg = Coop.cfg

A.REVIVE_MAX = 4        -- s: the revive's End action should have given the life back by then
A.DOWN_WAIT = 0.6       -- s a puppet's Life must have been 0 before this puts it into agony (the engine's own death first)
A.DOWN_RETRY = 0.5      -- s between two tries to put a downed puppet into agony

-- One-shot actions of the playable squad (docs/ally-animations.md: "one-shot (mirror)").
A.ONESHOT = {}
for _, n in ipairs({
  "Hit", "HitDuck", "HitStrong", "FriendlyFire", "DuckFriendlyFire",
  "Punch", "DuckPunch", "Reload", "Reload0", "DuckReload", "DuckReload0", "ReloadE", "DuckReloadE",
  "Reequip", "DuckReequip", "Hack", "Spell", "TKHit", "TKHitDuck",
  "Special1", "DuckSpecial1", "ShotH", "DuckShotH", "ShotH_GH", "DuckShotH_GH",
  "ShelterDownReload", "ShelterDownReload0", "ShelterDownReloadE", "ShelterLeftReload", "ShelterLeftReload0",
  "ShelterLeftReloadE", "ShelterRightReload", "ShelterRightReload0", "ShelterRightReloadE",
  -- story one-shots the levels add to a class (levels/*/scripts/mapinit.lua, MakeChar.AddMove)
  "NaziSacrifice", "BrokenWall", "KO", "KOEnd",
}) do A.ONESHOT[n] = true end

-- Locomotion and posture actions: not mirrored here (the inputs and Coop.syncCrouch do them).
local LOCO = {"^Relax", "^Walk", "^Run", "^Sprint", "^Back", "^Str", "^Turn", "^Duck", "^Facial_", "^Shot", "^Shelter",
              "^Agony", "^Astral", "^Trance", "^Possessed", "^Stupid", "^Jump", "^Fall", "^Climb"}

function A.isLoco(act)
  for _, p in ipairs(LOCO) do
    if string.find(act, p) then return true end
  end
  return false
end

A.state = {}       -- per body: down (time it was seen down), revive (time the revive started), last action
local function stOf(name)
  local s = A.state[name]
  if not s then s = {last = nil}; A.state[name] = s end
  return s
end

local function now() return Net.CoopTime() end

local function isAgony(act)
  return type(act) == "string" and string.find(act, "^Agony") ~= nil
end

local function actClass(e, name)
  local ok, c = pcall(function() return Act.GetClass(e.ActCtrl ~= "" and e.ActCtrl or name) end)
  return ok and c or nil
end

local function hasAct(cls, n)
  local ok, v = pcall(function() return cls and cls:GetAct(n) end)
  return ok and v ~= nil and v ~= false
end

-- Soldier.OnDeath, for a body the engine did not kill here.
function A.putDown(e, name, st)
  if cfg.animdown == false then return end   -- (lab: the behaviour without this slice)
  local s = stOf(name)
  local t = now()
  -- (the engine's own OnDeath follows a puppet's Life = 0 within a frame or two, with its own
  -- random variant: lab 2026-10-28, anim-a2 against a5. This is for a body it leaves standing.)
  if not s.seenDown then s.seenDown = t end
  if t - s.seenDown < A.DOWN_WAIT then return end
  if s.downT and t - s.downT < A.DOWN_RETRY then return end
  s.downT = t
  local act = tostring(e.Action)
  if isAgony(act) then return end
  local variant = string.find(tostring(st.action), "^Agony2") and "Agony2" or "Agony"
  local cls = actClass(e, name)
  if not hasAct(cls, variant .. "Init") then variant = "Agony" end
  e.Action = variant .. "Init"
  e.DefLoop = variant
  pcall(function() e.MainPowerStatus = 0 end)
  pcall(function() e.SecondaryPowerStatus = 0 end)
  if Team and Team.AssignReviveFunction then pcall(Team.AssignReviveFunction, e) end
  A.downs = (A.downs or 0) + 1
  if A.downs <= 40 or cfg.animlog then
    Coop.log(string.format("anim: %s put into %s (was %s, owner's action %s)", name, variant, act, tostring(st.action)))
  end
end

-- Called by CoopTeam.syncPuppetLife when the owner's life is back and the puppet's is not:
-- once per revive.
function A.revive(e, name, st, origRevive)
  local s = stOf(name)
  local t = now()
  if not s.reviveT then
    s.reviveT = t
    local before = tostring(e.Action)
    origRevive(e)
    A.revives = (A.revives or 0) + 1
    if A.revives <= 40 or cfg.animlog then
      Coop.log(string.format("anim: %s revive started (action %s -> %s)", name, before, tostring(e.ForceAction)))
    end
    return
  end
  if t - s.reviveT > A.REVIVE_MAX then
    -- the End action did not give the life back (it was cut short, or the engine's event did not run)
    s.reviveT = nil
    e.Invulnerable = 0
    e.Life = st.life
    pcall(function() if Team and Team.RemoveReviveFunction then Team.RemoveReviveFunction(e) end end)
    Coop.log("anim: " .. name .. " revive did not finish in " .. A.REVIVE_MAX .. " s, life set")
  end
end

-- Every frame for every puppet that has a state (Coop.drivePuppets).
function A.sync(e, name, st)
  local s = stOf(name)
  local life = tonumber(st.life)
  -- downed
  if life and life <= 0 then
    s.reviveT = nil
    if (tonumber(e.Life) or 1) <= 0 then A.putDown(e, name, st) end
  elseif life and life > 0 and (tonumber(e.Life) or 1) > 0 then
    s.downT, s.reviveT, s.seenDown = nil, nil, nil
  end
  -- one-shots of the owner's body
  local act = st.action
  if type(act) == "string" and act ~= s.last then
    s.last = act
    if A.ONESHOT[act] then
      A.play(e, name, act)
    elseif cfg.animlog or not A.isLoco(act) then
      A.unmapped = A.unmapped or {}
      local key = name .. ":" .. act
      if not A.unmapped[key] then
        A.unmapped[key] = true
        if cfg.animlog or A.nUnmapped == nil or A.nUnmapped < 60 then
          A.nUnmapped = (A.nUnmapped or 0) + 1
          Coop.log("anim: " .. key .. " seen on the owner's body, not mirrored")
        end
      end
    end
  end
end

function A.play(e, name, act)
  if cfg.animmirror == false then return end
  if (tonumber(e.Life) or 1) <= 0 then return end
  local t = now()
  -- (Coop.mirrorArms just played the strike / reload / power the first-person arms named)
  if Coop.mirrorT and t - (Coop.mirrorT[name] or -10) < 0.6 then return end
  local cls = actClass(e, name)
  if not hasAct(cls, act) then return end
  if string.find(tostring(e.Action), "^" .. act) then return end
  e.ForceAction = act
  Coop.mirrorT = Coop.mirrorT or {}
  Coop.mirrorT[name] = t
  A.plays = (A.plays or 0) + 1
  if A.plays <= 60 or cfg.animlog then Coop.log("anim: " .. name .. " plays " .. act) end
end
