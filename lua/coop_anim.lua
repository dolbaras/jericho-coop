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
  {"^TKCombo%d", "TKHit", only = "Black"},
  {"^Reequip$", "Reequip"},
  {"^HitStrong$", "HitStrong"},
  -- Rawlings reviving a teammate (Team.CurePlayer plays the first-person Heal): his heal-hands gesture, whose cure event does not run
  -- on a puppet (A.PUPPET_EVENTS); the other members have no third-person twin of the revive
  {"^Heal$", "ShotH", only = "Rawlings"},
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

-- Cole's grenade (D3, 0.2.9). The third-person Shot0 action launches the grenade with its frame-29 event
-- (cole.lua: WeaponsCole.LaunchGrenade). On a puppet the throw comes from the owner's shot flag and slot, so
-- the animation plays here by itself and its event made a SECOND grenade next to the one the owner's machine
-- throws (own physics, own explosion, own damage). The throw is shown, the grenade is not made on a puppet
-- (the real one flies on the machine that holds the body). cfg.puppetgrenade = true: the old behaviour.
function A.installGrenade()
  if A.grenadeInstalled or not WeaponsCole or not WeaponsCole.LaunchGrenade then return end
  A.grenadeInstalled = true
  local orig = WeaponsCole.LaunchGrenade
  WeaponsCole.LaunchGrenade = function(name, ...)
    if cfg.puppetgrenade ~= true and Coop.inSession() and Coop.isPuppet then
      local ok, ent = pcall(Game.GetEntity, name)
      if ok and ent and not ent:IsType("FP") and Coop.isPuppet(ent.Name) then
        A.grenadesDropped = (A.grenadesDropped or 0) + 1
        if A.grenadesDropped <= 5 or cfg.animlog then
          Coop.log("anim: " .. ent.Name .. "'s grenade launch dropped (puppet, the owner's machine throws it)")
        end
        return
      end
    end
    return orig(name, ...)
  end
end

-- Animation events whose function changes the game (a heal, a curse, the cost of a spell) run on a puppet's machine too, when the
-- third-person twin of the owner's power is played there for show: Rawlings' heal hands (ShotH: WeaponsRawlings.OnShotHeal cures
-- whoever the puppet's view meets and takes life from the puppet), the ghost heal (Rawlings.GhostHealShot calls the body's AI, which is
-- off on a puppet) and Vlad's course (WeaponsRawlings.OnDoVladsCourse), Church's spell (Church.LoseLifeCutting takes life from the
-- puppet and mutes the damage effects of this machine's player). The effect itself is the owner's machine's and arrives as a power
-- message (pw|...); the twin is played, its event is not. cfg.puppetevents = true: the old behaviour.
-- Black's telekinesis event (Black.UseTelePower) is not in the list: it only pushes this machine's copy of an enemy.
-- {table, function, the body when the function takes no body name}
A.PUPPET_EVENTS = {
  {"WeaponsRawlings", "OnShotHeal"}, {"Rawlings", "GhostHealShot"}, {"WeaponsRawlings", "OnDoVladsCourse", "Rawlings"},
  {"Church", "LoseLifeCutting"},
}
A.wrapped = A.wrapped or {}
function A.guardEvents()
  for _, d in ipairs(A.PUPPET_EVENTS) do
    local tbl, fname, fixed = d[1], d[2], d[3]
    local t = _G[tbl]
    local key = tbl .. "." .. fname
    -- (looked at every frame: a character's script table is built again when a player takes the character, which drops a wrapper)
    if type(t) == "table" and type(t[fname]) == "function" and t[fname] ~= A.wrapped[key] then
      local orig = t[fname]
      local w = function(name, ...)
        if cfg.puppetevents ~= true and Coop.inSession() and Coop.isPuppet then
          local who = fixed or name
          local ok, ent = pcall(Game.GetEntity, who)
          if ok and ent and not ent:IsType("FP") and Coop.isPuppet(ent.Name) then
            A.eventsDropped = (A.eventsDropped or 0) + 1
            if A.eventsDropped <= 8 or cfg.animlog then Coop.log("anim: " .. key .. " dropped (puppet " .. ent.Name .. ", the owner's machine acts)") end
            return
          end
        end
        return orig(name, ...)
      end
      t[fname] = w
      A.wrapped[key] = w
    end
  end
end

-- Every frame for every puppet that has a state (Coop.drivePuppets).
function A.sync(e, name, st)
  local s = stOf(name)
  if not A.grenadeInstalled then A.installGrenade() end
  A.guardEvents()
  if cfg.animtrace and string.find(cfg.animtrace, name, 1, true) then
    -- (dev: every change of the body's own action and of the owner's, with the time, to see what follows an Init/End action)
    local k = tostring(e.Action) .. "|" .. tostring(st.action) .. "|" .. tostring(e.DefLoop)
    if k ~= s.traceKey then
      s.traceKey = k
      Coop.log(string.format("anim trace %s: body %s (defloop %s) owner %s", name, tostring(e.Action), tostring(e.DefLoop), tostring(st.action)))
    end
  end
  local life = tonumber(st.life)
  -- downed
  if life and life <= 0 then
    s.reviveT = nil
    if (tonumber(e.Life) or 1) <= 0 then A.putDown(e, name, st) end
  elseif life and life > 0 and (tonumber(e.Life) or 1) > 0 then
    s.downT, s.reviveT, s.seenDown = nil, nil, nil
  end
  A.dragonArm(e, name, st, s)
  A.syncFP(e, name, st)
  A.noteFpMove(s, st)
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
    if string.find(act, m[1]) and (m.only == nil or m.only == name) then
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

-- Delgado's open arm is closed by the game's own code when the replayed spirit arrives (Ababanili.OnAbabaniliArrived sends
-- Shot1EndAlt). If that never comes (a lost abby message, a spirit that cannot reach its target here) the arm would stay open:
-- when the owner's body has been out of Shot1* for ARM_MAX s and the puppet still holds it, it is closed.
A.ARM_MAX = 6
function A.dragonArm(e, name, st, s)
  local mine = tostring(e.Action)
  local open = string.find(mine, "^Shot1") or string.find(mine, "^DuckShot1")
  local owner = tostring(st.action)
  if not open or string.find(owner, "Shot1") then s.armSince = nil return end
  local t = now()
  s.armSince = s.armSince or t
  if t - s.armSince < A.ARM_MAX then return end
  s.armSince = nil
  local cls = actClass(e, name)
  local end_ = string.find(mine, "^Duck") and "DuckShot1End" or "Shot1EndAlt"
  if hasAct(cls, end_) and (tonumber(e.Life) or 1) > 0 then
    e.ForceAction = end_
    A.armCloses = (A.armCloses or 0) + 1
    if A.armCloses <= 10 or cfg.animlog then Coop.log("anim: " .. name .. "'s open arm closed after " .. A.ARM_MAX .. " s (no spirit arrival)") end
  end
end

function A.noteFpMove(s, st)
  local fpa = st.fpa
  if type(fpa) ~= "string" then return end
  local act = string.match(fpa, "^%d+_(.+)$") or fpa
  for _, p in ipairs(A.FP_MOVES) do
    if string.find(act, p) then
      if not (s.moveUntil and now() < s.moveUntil) then
        A.fpMoves = (A.fpMoves or 0) + 1
        if A.fpMoves <= 20 or cfg.animlog then Coop.log("anim: first-person " .. act .. " shown as a run on the spot") end
      end
      s.moveUntil = now() + A.MOVE_HOLD
      s.moveSprint = string.find(act, "^Hurdle") ~= nil
      return
    end
  end
end

-- A state that lasts (A.FAMILIES): the Init action starts it, the End action ends it. The End starts when the
-- owner's body plays its own End action (live 2026-10-30: waiting for the owner's body to leave the family put it
-- 1.2 s behind: the owner's StupidEnd was over before the puppet began its own), or at the latest when it left the family.
function A.syncState(e, name, st)
  local act = st.action
  if type(act) ~= "string" then return end
  local s = stOf(name)
  local fam
  for _, f in ipairs(A.FAMILIES) do
    if string.find(act, "^" .. f) then fam = f break end
  end
  local function playEnd(f)
    local fe = f .. "End"
    s.endPlayed = true
    local cls = actClass(e, name)
    if hasAct(cls, fe) and (tonumber(e.Life) or 1) > 0 then
      e.ForceAction = fe
      return true
    end
  end
  if fam and not s.fam then
    -- begins: the Init action (a state already running when this machine first sees it is joined at its loop)
    local init = fam .. "Init"
    s.fam, s.endPlayed = fam, false
    if string.find(act, "Init$") then A.play(e, name, init, true) end
    A.famLog(name, "enters " .. fam .. " (owner's action " .. act .. ")")
  elseif fam and fam == s.fam then
    if not s.endPlayed and string.find(act, "^" .. fam .. "End$") then
      playEnd(fam)
      A.famLog(name, "ends " .. fam .. " (owner's action " .. act .. ")")
    elseif s.endPlayed and not string.find(act, "End$") and string.find(act, "Init$") then
      s.endPlayed = false    -- a new Init in the same family: the next End plays again
      A.play(e, name, fam .. "Init", true)
    end
  elseif s.fam and fam ~= s.fam then
    -- the owner's body left it: End action unless it already began with the owner's own (it ends in Relax by its own event)
    local old = s.fam
    s.fam = fam
    if not fam then
      if not s.endPlayed then playEnd(old) end
      s.endPlayed = false
      A.famLog(name, "leaves " .. old .. "End")
    else
      -- straight into another family (cover to dazed): the new one begins
      s.endPlayed = false
      s.fam = fam
      if string.find(act, "Init$") then A.play(e, name, fam .. "Init", true) end
      A.famLog(name, "enters " .. fam .. " from " .. old .. " (owner's action " .. act .. ")")
    end
  end
end

-- Bodies in these states do not walk: Coop.drivePuppets sends no walk input to them (the drawn state is up to 0.2 s behind: its
-- walk input cut the Init of the low-priority Possessed action short, live 2026-10-30). Cover is left out (the body walks in cover).
A.HOLD = {Stupid = true, Trance = true, Astral = true, Possessed = true}
-- The owner's first-person-only moves with no third-person action (Hurdle over a low obstacle, SkipWall climbs): the body itself
-- stays in Relax while the engine moves it, so the puppet slid over the obstacle standing. It runs on the spot instead (the legs of
-- the closest third-person action, with no root motion: the network places it).
A.FP_MOVES = {"^Hurdle", "^SkipWall"}
A.MOVE_HOLD = 0.35   -- s the run lasts after the last state that named the first-person move

-- nil, or the walk / strafe / sprint inputs (a table) the body gets instead of the drawn state's (Coop.drivePuppets).
function A.moveOverride(name)
  local s = A.state[name]
  if not s or cfg.animhold == false then return nil end
  if s.fam and A.HOLD[s.fam] then return {walk = 0, str = 0, sprint = 0} end
  if s.moveUntil and now() < s.moveUntil then return {walk = 1, str = 0, sprint = s.moveSprint and 1 or 0} end
  return nil
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

------------------------------------------------------------------------------
-- Fire controls of a body (0.3.0, owner: "pistol shots show no animation", "Black's shots are synced in one mode only").
-- The state carries the main trigger (owc.Shot, 13th field) and, from 0.3.0, the second weapon's trigger
-- (owc.SecondWeaponTrigger, 22nd field). The weapons that fire on a switch (bFPShotOnSwitch: Black's grenade launcher,
-- all three of Delgado's, Rawlings' pistols and hands) are fired with the second trigger: the body changes to the
-- second weapon (the slot field) and shoots while it is held, and the main trigger stays 0. A puppet only had the
-- main trigger, so it took the weapon in hand and never fired it.
------------------------------------------------------------------------------

-- The 22nd state field of a body (a string): "1" while the second trigger is held.
function A.stateFire(e)
  local ok, v = pcall(function() return e.owc and tonumber(e.owc.SecondWeaponTrigger) end)
  return (ok and v and v > 0.5) and "1" or "0"
end

-- What a puppet's triggers are, every frame (Coop.drivePuppets): the drawn state's main and second trigger.
-- cfg.puppetsecond = false: the main trigger only (0.2.9).
function A.driveFire(e, name, sst)
  local owc = e.owc
  if not owc then return end
  owc.Shot = sst.shot or 0
  if cfg.puppetsecond ~= false then
    local want = sst.sec and 1 or 0
    pcall(function()
      if tonumber(owc.SecondWeaponTrigger) ~= want then owc.SecondWeaponTrigger = want end
    end)
  end
  A.applyModes(e, name, sst.modes)
  if (sst.shot or 0) > 0.5 or sst.sec then A.keepAmmo(e, name) end
end

-- A puppet fires on its own ammo: the engine takes a round from the magazine for every shot it plays, and nothing refilled it (the
-- owner's reloads are shown as an animation, they do not reload the copy). A pistol magazine (Delgado's six rounds, Black's single
-- grenade, Rawlings' 15) ran dry within seconds of firing and the puppet then stood with its weapon up and no shot, which is what a
-- watcher sees as "no animation at all". Its rounds do not matter (its damage is dropped), so the two slots are kept loaded
-- while it fires. cfg.puppetammo = false: the old behaviour.
A.AMMO_EVERY = 0.2   -- s between two looks at a firing puppet's magazines
function A.keepAmmo(e, name)
  if cfg.puppetammo == false then return end
  local s = stOf(name)
  local t = now()
  if s.ammoT and t - s.ammoT < A.AMMO_EVERY then return end
  s.ammoT = t
  local wc = e.oWeapCtrl
  if not wc then return end
  for i = 0, 1 do
    pcall(function()
      local slt = wc:Slot(i)
      local typ = slt.oType
      local load = tonumber(typ.AmmoLoad) or 0
      if load <= 0 then return end   -- (a blade: nothing to load)
      if (tonumber(slt.AmmoLoaded) or load) < math.min(2, load) then
        slt.AmmoLoaded = load
        A.ammoFills = (A.ammoFills or 0) + 1
        if A.ammoFills <= 10 or cfg.animlog then Coop.log("anim: " .. name .. "'s slot " .. i .. " magazine refilled (puppet)") end
      end
      local max = tonumber(typ.MaxAmmoSupply) or 0
      if max > 0 and (tonumber(slt.AmmoSupply) or max) < load then slt.AmmoSupply = max end
    end)
  end
end

-- Weapon modes (0.3.0). What a shot looks like depends on settings of the weapon slot that live on the body and were never
-- sent: the fire mode of the machine guns (Jones, Church, Cole: semi / burst / auto, "Weap_Slot0<i>ShootMode", set from the
-- reload menu) and Rawlings' pistol load (standard / fragmenting / explosive: the slot's ShotReloadPrefix "" / "2" / "3",
-- which picks the third-person action Shot / Shot2 (ShotE) / Shot3 and the rate). A puppet stayed on the defaults, so a held
-- trigger showed one shot in semi mode, or the plain pistol shot for a load the owner had switched.
-- The 23rd state field: four characters, per slot 0 and 1 the fire mode ("0".."2", "-" unreadable) and Rawlings' load ("0" standard,
-- "2", "3"; "-" for every other body).
function A.stateModes(e)
  local out = {}
  for i = 0, 1 do
    local sm, pf = "-", "-"
    pcall(function()
      local v = tonumber(e["Weap_Slot0" .. i .. "ShootMode"])
      if v and v >= 0 and v <= 2 then sm = tostring(math.floor(v)) end
      if e.Name == "Rawlings" then
        local p = e.oWeapCtrl:Slot(i).ShotReloadPrefix
        pf = (p == "2" or p == "3") and p or "0"
      end
    end)
    out[#out + 1] = sm .. pf
  end
  return table.concat(out)
end

A.MODE_EVERY = 0.25   -- s between two looks at a puppet's modes

function A.setPistolLoad(e, i, pf)
  local ok, slt = pcall(function() return e.oWeapCtrl:Slot(i) end)
  if not ok or not slt or not Rawlings then return end
  local want = (pf == "2" or pf == "3") and pf or ""
  local okc, cur = pcall(function() return slt.ShotReloadPrefix end)
  if not okc or cur == want then return end
  local fn = pf == "2" and Rawlings.SetFragment or pf == "3" and Rawlings.SetExplosive or Rawlings.SetStandard
  if type(fn) ~= "function" then return end
  if pcall(fn, slt) then
    A.modeSets = (A.modeSets or 0) + 1
    if A.modeSets <= 30 or cfg.animlog then Coop.log("anim: Rawlings' slot " .. i .. " pistol load " .. tostring(cur) .. " -> " .. want) end
  end
end

-- The owner's modes on a puppet (from driveFire). cfg.puppetmodes = false: the defaults (0.2.9).
function A.applyModes(e, name, modes)
  if cfg.puppetmodes == false or type(modes) ~= "string" or #modes < 4 then return end
  local s = stOf(name)
  local t = now()
  if s.modesT and t - s.modesT < A.MODE_EVERY then return end
  s.modesT = t
  for i = 0, 1 do
    local sm = tonumber(string.sub(modes, 2 * i + 1, 2 * i + 1))
    local pf = string.sub(modes, 2 * i + 2, 2 * i + 2)
    if sm then
      local key = "Weap_Slot0" .. i .. "ShootMode"
      local ok, cur = pcall(function() return tonumber(e[key]) end)
      if ok and cur and cur ~= sm and pcall(function() e[key] = sm end) then
        A.modeSets = (A.modeSets or 0) + 1
        if A.modeSets <= 30 or cfg.animlog then Coop.log("anim: " .. name .. "'s slot " .. i .. " fire mode " .. cur .. " -> " .. sm) end
      end
    end
    if pf ~= "-" and name == "Rawlings" then A.setPistolLoad(e, i, pf) end
  end
end

-- Reload action of a first-person reload (Coop.mirrorArms: the Reload row of Coop.ARM_ACTIONS), see the note there.
A.RELOAD0_SET2 = {Delgado = true, Black = true, Jones = true, Ross = true}
function A.reloadAction(name, cls, load, _, set)
  if load ~= "" and cls:GetAct("ReloadE") then return "ReloadE" end
  if set == "02" and A.RELOAD0_SET2[name] and cls:GetAct("Reload0") then return "Reload0" end
  return "Reload"
end
