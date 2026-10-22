-- Act 1 (Al-Khali): Ross's full body for the other players.
-- Ross's own model has no textures of its head (the game never shows it: Ross is always seen
-- through his own eyes, his scenes use TrueRoss, the same model textured): to player 2 in split
-- screen and to the other machines of a session he was a pair of hands with a pistol in the air
-- (owner's report, 0.2.1). A stand-in with TrueRoss's model takes his place: here, where his
-- own player looks through his eyes, it follows his entity (seen by this PC's split screen
-- player 2); on the other machines it is the host's Ross: position, facing, action, weapon and
-- shots from his network state, while his own entity is switched off (Active 0, as scenes hide
-- characters). bObjectVisible alone cannot hide him: while bCheckFPSVisible is set the engine
-- draws a squad member it does not look through whatever that flag says (recorded, 0.2.1: his
-- untextured body, with SMOD his full one, inside the stand-in - "two Rosses"). The AI's Ross
-- (a test that starts the host in another body) keeps running with both flags off. With SMOD,
-- whose own Ross model is complete, the stand-in stays: TrueRoss looks much better (owner).
CoopRoss = CoopRoss or {}
local R = CoopRoss

R.NAME = "CoopRossBody"
R.MODEL = "Models/Chars/TrueRoss/TrueRoss.M3D"
R.MODEL_COOP = "Models/Chars/TrueRoss/TrueRoss_coop.M3D"   -- rifle textured (tools/cm3_retarget.py)
-- Ross's actions (chars/ross.lua: relax, walk, duck, init/end, view, turn, shot, reload, hit).
R.ACTS = {}
for _, n in ipairs({"Relax", "Relax0", "Relax1", "Relax2", "RelaxLeft", "RelaxRight",
                    "RelaxViewLeft0", "RelaxViewLeft1", "RelaxViewRear", "RelaxViewRight0", "RelaxViewRight1",
                    "Walk", "Back", "StrLeft", "StrRight", "Run", "Sprint",
                    "WalkInit", "BackInit", "RunInit", "SprintInit", "WalkEnd", "BackEnd", "RunEnd", "SprintEnd",
                    "WalkDuckInit", "RunDuckInit", "SprintDuckInit", "WalkDuckEnd", "RunDuckEnd", "SprintDuckEnd",
                    "WalkViewLeft0", "WalkViewLeft1", "WalkViewRear", "WalkViewRight0", "WalkViewRight1",
                    "TurnLeft", "TurnRight", "TurnSprint", "Turn180", "Turn90Left", "Turn90Right",
                    "Reload", "Reload0", "ShotInit", "Shot", "Shot0", "ShotEnd", "Punch", "HitStrong",
                    "ShelterDown", "ShelterLeft", "ShelterRight"}) do
  R.ACTS[#R.ACTS + 1] = n
end
for _, n in ipairs({"Relax", "Relax0", "RelaxLeft", "RelaxRight", "RelaxInit", "RelaxEnd",
                    "RelaxViewLeft0", "RelaxViewLeft1", "RelaxViewRight0", "RelaxViewRight1",
                    "Walk", "Back", "StrLeft", "StrRight", "Run", "Sprint",
                    "TurnLeft", "TurnRight", "Turn180", "Turn90Left", "Turn90Right",
                    "Reload", "Reload0", "ShotInit", "Shot", "Shot0", "ShotEnd", "Punch"}) do
  R.ACTS[#R.ACTS + 1] = "Duck" .. n
end

-- The stand-in's class: TrueRoss's model with the animation files of Ross's own actions.
function R.makeClass()
  local ac = Act.GetClass(R.NAME)
  if ac then return ac end
  local rc = Act.GetClass("Ross")
  if not rc then return nil end
  ac = Act.CreateClass(R.NAME)
  pcall(Act.SetCls, "Discardable", 1)
  -- (the installer's copy with the rifle textured, when it built one into Pack1.packed)
  local coopModel = Net.CoopFile and Net.CoopFile("coop/anims/trueross_coop.ok") == 1
  Act.SetCls("ModelFilePath", coopModel and R.MODEL_COOP or R.MODEL)
  Coop.log("ross: stand-in model " .. (coopModel and R.MODEL_COOP or R.MODEL))
  -- His size, and where a weapon sits in his hands (chars/ross.lua).
  local keys = {"ModelSize", "YModelDisp", "WeaponSlots"}
  for i = 0, 15 do
    keys[#keys + 1] = string.format("WeapArm%02d", i)
    keys[#keys + 1] = string.format("WeapAxs%02d", i)
  end
  for _, k in ipairs(keys) do
    local ok, v = pcall(function() return rc[k] end)
    if ok and v ~= nil and v ~= "" then pcall(function() ac[k] = v end) end
  end
  local n = 0
  for _, name in ipairs(R.ACTS) do
    local src = rc:GetAct(name)
    if src and src.AnmFilePath and ac:GetAct(name) == nil then
      local a = ac:NewAct(name)
      a.AnmFilePath = src.AnmFilePath
      a.isLoop = src.isLoop or 0
      a.InterpTime = src.InterpTime or 0.2
      a.UseDisp = 0
      n = n + 1
    end
  end
  ac.DefAction = "Relax"
  Coop.log("ross: stand-in body with " .. n .. " of Ross's actions")
  return ac
end

-- Act 1 in a session (or with this PC's player 2): someone else may look at Ross.
function R.wanted()
  if Coop.cfg.rossbody == false then return false end
  return Coop.actOne() and (Coop.inSession() or (CoopSplit and CoopSplit.on))
end

function R.body()
  if R.failed or not R.wanted() then return nil end
  local e = Game.GetEntity(R.NAME)
  if e then return e end
  if Scene and Scene.IsPlaying then return nil end
  local ok, err = pcall(function()
    if not R.makeClass() then return end
    local r = Game.GetEntity("Ross")
    -- (a "WithLife" entity of a class made after the level loaded had no model: "Check
    -- failed: Model"; a character takes it through ActCtrl, as Maltheus's Rose does)
    e = Game.CreateEntity(R.NAME, "WalkChar", r and r.Pos)
    if e then
      e.ActCtrl = R.NAME
      -- His weapons in its hands: the machine gun and shotgun he carries (Ross.OnCreate gives
      -- him 19 and 20, Jones's two made with his first-person set), as Jones's own 0 and 2:
      -- the same guns, but seen from outside ones with textures (19 was a checkered rifle).
      if Soldier and Soldier.SetWeapon then pcall(Soldier.SetWeapon, e, 0, 2) end
      pcall(function() e.bIgnoreCollision = true end)
      pcall(function() e.EnableCollision = 0 end)
      pcall(function() e.Invulnerable = 1 end)
      e.Active = 0
      Coop.log("ross: stand-in body made")
    end
  end)
  if not ok then
    R.failed = true
    Coop.log("ross: stand-in error " .. tostring(err))
  end
  return e
end

-- Shown where Ross himself is not looking from: on another machine, or in this PC's player 2's
-- view (split screen). Not while a scene plays (it has its own Ross) or once he is down.
function R.showable()
  local r = Game.GetEntity("Ross")
  -- (bActive false: switched off by the story; not when it is off for the stand-in, below)
  if not r or (r.bActive == false and not R.offRoss) or (r.Life or 0) <= 0 then return false end
  if Scene and Scene.IsPlaying then return false end
  return true
end

-- Per frame (coop.lua): follow Ross. view: the user whose view is drawn next (split screen);
-- p2: Ross is this PC's player 2's body.
function R.update(view, p2)
  local e = R.body()
  if not e then
    R.restore()
    return
  end
  local r = Game.GetEntity("Ross")
  local show = R.showable()
  local mine = Coop.isLocalBody("Ross")
  -- Another machine's Ross: what his player's machine sent (his own entity is off here).
  local st = not mine and Coop.remote and Coop.remote["Ross"]
  local tg = st and Coop.puppetTarget and Coop.puppetTarget("Ross", Net.CoopTime())
  -- Nobody's eyes in him, on the machine that runs him: the host's AI Ross (or a game without a
  -- session). He keeps running; only his model is hidden. (A client gets no state for an AI
  -- Ross: its copy is switched off as before, the stand-in follows it.)
  local ai = r ~= nil and not mine and not st and not Coop.isRemoteOwned("Ross") and
             not (Coop.inSession() and not Coop.isHost())
  if show then
    if tg then
      e.Pos = V3D(tg.x, tg.y, tg.z)
      e.Ang = V3D(0, tg.yaw, 0)
      e.ViewAng = V3D(tg.pitch or 0, tg.yaw, 0)
    else
      e.Pos = r.Pos
      e.Ang = V3D(0, r.Ang.y, 0)
      if r.ViewAng then e.ViewAng = r.ViewAng end
    end
    local act = (st and st.action) or r.Action
    if act and act ~= R.lastAct then
      R.lastAct = act
      if Act.GetClass(R.NAME):GetAct(act) then
        e.ForceAction = act
        e.ForceDefLoop = R.loopFor(act)
      end
    end
    -- His shots and weapon, for show: the stand-in's hits are dropped (coop_enemies.lua).
    if st then
      if e.owc then e.owc.Shot = st.shot or 0 end
      Coop.syncSlot(e, st.slot)
    elseif ai then
      if e.owc and r.owc then e.owc.Shot = r.owc.Shot or 0 end
      local wc = r.oWeapCtrl
      if wc and wc.iSlot then Coop.syncSlot(e, tonumber(wc.iSlot)) end
    end
  end
  if mine then
    R.restore()   -- (his player is here now)
  elseif ai then
    -- (switched off through Active he would stop: his AI and the story's orders to him)
    if R.offRoss then R.restore() end
    if show then R.hideModel(r) else R.showModel() end
  elseif r then
    R.showModel()
    -- Switched off while the stand-in shows him; back on when it does not (down, or the
    -- story takes over), unless a scene hides him (the scene gives him back afterwards).
    if show then
      if r.Active ~= 0 then r.Active = 0 end
      R.offRoss = true
    elseif R.offRoss and not (Scene and Scene.IsPlaying) then
      R.restore()
    end
  end
  -- Active takes effect in the frame after next, i.e. in the other view: set in the update
  -- before player 1's view, it shows in player 2's.
  if view ~= nil and mine then
    if p2 then
      show = show and view == 1  -- this PC's player 1 sees player 2's Ross
    else
      show = show and view == 0  -- this PC's player 2 sees this PC's Ross
    end
  elseif mine then
    show = false                 -- only Ross's own view here
  end
  local a = show and 1 or 0
  if e.Active ~= a then e.Active = a end
  if Coop.cfg.rosslog and Coop.frame % 7 == 0 then
    Coop.log(string.format("ross: view %s shown %s ai %s action %s at %.0f,%.0f net %s", tostring(view), tostring(show), tostring(ai),
      tostring(r and r.Action), e.Pos.x, e.Pos.z, tostring(st ~= nil)))
  end
end

-- The loop a one-shot action goes back to (looping one, the action itself). A one-shot set as
-- the loop played over and over: a glance aside or the end of a walk repeated, the rifle jerking
-- back and forth (owner: "his arms animated strangely", 0.2.1).
R.LOOP_AFTER = {WalkInit = "Walk", BackInit = "Back", RunInit = "Run", SprintInit = "Sprint",
  WalkDuckInit = "DuckWalk", RunDuckInit = "DuckRun", SprintDuckInit = "DuckSprint",
  DuckRelaxInit = "DuckRelax", DuckRelaxEnd = "Relax", ShotInit = "Shot", Shot0 = "Shot",
  DuckShotInit = "DuckShot", DuckShot0 = "DuckShot", TurnSprint = "Sprint"}
function R.loopFor(act)
  local a = Act.GetClass(R.NAME):GetAct(act)
  if a and a.isLoop == 1 then
    R.lastLoop = act
    return act
  end
  local loop = R.LOOP_AFTER[act]
  if not loop then
    if string.find(act, "^Walk") then loop = "Walk"
    elseif string.find(act, "^Duck") then loop = "DuckRelax"
    else loop = "Relax" end
  end
  R.lastLoop = loop
  return loop
end

-- The AI's Ross unseen while he runs: with bCheckFPSVisible set the engine draws a squad
-- member whatever bObjectVisible says (the "two Rosses" of 0.2.1); both off, he is hidden.
function R.hideModel(r)
  if not R.hidRoss then
    R.hidRoss = {vis = r.bObjectVisible, check = r.bCheckFPSVisible}
    Coop.log("ross: the AI's Ross shown by the stand-in")
  end
  if r.bCheckFPSVisible ~= false then r.bCheckFPSVisible = false end
  if r.bObjectVisible ~= false then r.bObjectVisible = false end
end

function R.showModel()
  local h = R.hidRoss
  if not h then return end
  R.hidRoss = nil
  local r = Game.GetEntity("Ross")
  if not r then return end
  if h.check ~= nil and r.bCheckFPSVisible ~= h.check then r.bCheckFPSVisible = h.check end
  if h.vis ~= nil and r.bObjectVisible ~= h.vis then r.bObjectVisible = h.vis end
end

-- Ross's own entity on again (it was off for the stand-in): stand-in gone, or not shown.
function R.restore()
  R.showModel()
  if not R.offRoss then return end
  R.offRoss = nil
  local r = Game.GetEntity("Ross")
  if r and r.Active == 0 then r.Active = 1 end
end
