-- Act 1 (Al-Khali): Ross's full body for the other players.
-- Ross's own model has no textures of its head (the game never shows it: Ross is always seen
-- through his own eyes, his scenes use TrueRoss, the same model textured): to player 2 in split
-- screen and to the other machines of a session he was a pair of hands with a pistol in the air
-- (owner's report, 0.2.1). His entity stays unseen; a stand-in with TrueRoss's model takes his
-- place, position and facing every frame, and plays the action his entity plays (the engine
-- picks those as for any character, drawn or not).
CoopRoss = CoopRoss or {}
local R = CoopRoss

R.NAME = "CoopRossBody"
R.MODEL = "Models/Chars/TrueRoss/TrueRoss.M3D"
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
  Act.SetCls("ModelFilePath", R.MODEL)
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
      -- His weapons in its hands (Ross.OnCreate).
      if Soldier and Soldier.SetWeapon then pcall(Soldier.SetWeapon, e, 19, 20) end
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
  if not r or r.bActive == false or (r.Life or 0) <= 0 then return false end
  if Scene and Scene.IsPlaying then return false end
  return true
end

-- Per frame (coop.lua): follow Ross. view: the user whose view is drawn next (split screen).
function R.update(view)
  local e = R.body()
  if not e then return end
  local r = Game.GetEntity("Ross")
  local show = R.showable()
  if show then
    e.Pos = r.Pos
    e.Ang = V3D(0, r.Ang.y, 0)
    local act = r.Action
    if act and act ~= R.lastAct then
      R.lastAct = act
      if Act.GetClass(R.NAME):GetAct(act) then
        e.ForceAction = act
        e.ForceDefLoop = act
      end
    end
  end
  -- Hidden through Active: the visibility flag the other bodies use does nothing on it
  -- (tested 0.2.1), and Active takes effect a frame later than that flag does, i.e. in the
  -- other view: shown in player 2's view when set in the update before player 1's.
  local mine = Coop.isLocalBody("Ross")
  if view ~= nil and mine then
    show = show and view == 0   -- this PC's player 2 sees this PC's Ross
  elseif mine then
    show = false                -- only Ross's own view here
  end
  local a = show and 1 or 0
  if e.Active ~= a then e.Active = a end
  if Coop.cfg.rosslog and Coop.frame % 7 == 0 then
    Coop.log(string.format("ross: view %s shown %s action %s", tostring(view), tostring(show), tostring(r and r.Action)))
  end
  -- His own entity: never drawn but in his own view (where the game keeps it hidden itself).
  if not mine and r and r.bObjectVisible ~= false then r.bObjectVisible = false end
end
