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
  -- Delgado's release of the Ababanili (the arm opens; its frame-40 event is dropped on puppets,
  -- coop_powers.lua: the abby message sends the spirit)
  "Shot1Init", "DuckShot1Init",
}) do A.ONESHOT[n] = true end

-- States that last: begin with the Init action, end with the End action when the owner's body leaves
-- the family (the loop in between follows the Init through its own event). docs/ally-animations.md.
A.FAMILIES = {"Stupid", "Trance", "Astral", "Possessed", "ShelterDown", "ShelterLeft", "ShelterRight"}

-- The owner's first-person arms name things the third-person body has an action for, which
-- Coop.mirrorArms (Combo/Punch/Reload/Spell/Hack/Special_0*) does not map: Black's telekinesis
-- combos, Cole's reequip, the hit reactions of a human body (the AI bodies' own Hit comes with the action).
A.FPMAP = {
  {"^TKCombo%d", "TKHit", Black = true},
  {"^Reequip$", "Reequip"},
  {"^HitStrong$", "HitStrong"},
  {"^Hit(%a+)$", "Hit"},
}
-- first-person actions that are movement, posture or menus: no third-person counterpart needed
local FP_QUIET = {"^Relax", "^Walk", "^Str", "^Back", "^Hide", "^Show", "^Duck", "^Turn", "^Shot", "^Aim", "^Order", "^Switch",
                  "^ChooseMode", "^SkipWall", "^Hurdle", "^Fall", "^Combo", "^Reload", "^Spell", "^Hack", "^Special_0",
                  "^Special_From", "^Special_To", "^Special_Relax", "^Heal"}

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
  A.syncFP(e, name, st)
  A.syncState(e, name, st)
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

-- A first-person action of the owner's arms that has a third-person action (A.FPMAP).
function A.syncFP(e, name, st)
  local fpa = st.fpa
  local s = stOf(name)
  if type(fpa) ~= "string" or fpa == "-" or fpa == s.lastFpa then return end
  s.lastFpa = fpa
  local act = string.match(fpa, "^%d+_(.+)$") or fpa
  -- (what Coop.mirrorArms maps itself is its to play)
  for _, m in ipairs(Coop.ARM_ACTIONS or {}) do
    if string.find(act, m[1]) then return end
  end
  local own = Coop.ARM_BY_CHAR and Coop.ARM_BY_CHAR[name]
  if own then for pat in pairs(own) do if string.find(act, pat) then return end end end
  for _, m in ipairs(A.FPMAP) do
    if string.find(act, m[1]) and (m.Black == nil or name == "Black") then
      local want = m[2]
      if string.find(tostring(st.action), "^Duck") then
        local cls = actClass(e, name)
        if hasAct(cls, "Duck" .. want) then want = "Duck" .. want end
        if want == "DuckHit" then want = "HitDuck" end
      end
      A.play(e, name, want)
      return
    end
  end
  for _, p in ipairs(FP_QUIET) do if string.find(act, p) then return end end
  A.unmappedFp = A.unmappedFp or {}
  local key = name .. ":" .. act
  if not A.unmappedFp[key] and (A.nUnmappedFp or 0) < 60 then
    A.unmappedFp[key] = true
    A.nUnmappedFp = (A.nUnmappedFp or 0) + 1
    Coop.log("anim: first-person " .. key .. " on the owner's arms, no third-person action mapped")
  end
end

-- A state that lasts (A.FAMILIES): the Init action starts it, the End action ends it.
function A.syncState(e, name, st)
  local act = st.action
  if type(act) ~= "string" then return end
  local s = stOf(name)
  local fam
  for _, f in ipairs(A.FAMILIES) do
    if string.find(act, "^" .. f) then fam = f break end
  end
  if fam and not s.fam then
    -- begins: the Init action (a state already running when this machine first sees it is joined at its loop)
    local init = fam .. "Init"
    s.fam = fam
    if string.find(act, "Init$") then A.play(e, name, init, true) end
    A.famLog(name, "enters " .. fam .. " (owner's action " .. act .. ")")
  elseif s.fam and fam ~= s.fam then
    -- the owner's body left it: End action (it ends in Relax by its own event)
    local fe = s.fam .. "End"
    s.fam = fam
    if not fam then
      local cls = actClass(e, name)
      if hasAct(cls, fe) and (tonumber(e.Life) or 1) > 0 then
        e.ForceAction = fe
      end
      A.famLog(name, "leaves " .. tostring(fe))
    end
  end
end

function A.famLog(name, what)
  A.famN = (A.famN or 0) + 1
  if A.famN <= 40 or Coop.cfg.animlog then Coop.log("anim: " .. name .. " " .. what) end
end

function A.play(e, name, act, force)
  if cfg.animmirror == false then return end
  if (tonumber(e.Life) or 1) <= 0 then return end
  local t = now()
  -- (Coop.mirrorArms just played the strike / reload / power the first-person arms named)
  if not force and Coop.mirrorT and t - (Coop.mirrorT[name] or -10) < 0.6 then return end
  local cls = actClass(e, name)
  if not hasAct(cls, act) then return end
  if string.find(tostring(e.Action), "^" .. act) then return end
  e.ForceAction = act
  Coop.mirrorT = Coop.mirrorT or {}
  Coop.mirrorT[name] = t
  A.plays = (A.plays or 0) + 1
  if A.plays <= 60 or cfg.animlog then Coop.log("anim: " .. name .. " plays " .. act) end
end
