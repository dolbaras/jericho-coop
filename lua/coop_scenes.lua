-- Jericho co-op: cutscenes from each player's own character (docs/scenes-catalog.md 2.8).
-- First-person scenes film from one character's arms (FP_<Char>); that camera is directed:
-- it follows the points the scene wants us to look at (the villain stepping out, ...).
-- Every other squad member present has a full-body actor <Scene><Actor>. A player holding
-- one of them watches from that actor's head, but LOOKS AT THE SAME POINT as the scene
-- camera: the focus is where the scene camera's view ray hits the world.

CoopScenes = {}
local S = CoopScenes
S.CAM = "CoopPOVCam"
S.FOCUS_TAU = 0.2         -- smoothing of the shared focus point
S.FOCUS_RANGE = 6000      -- view ray length for the focus
S.FOCUS_DEFAULT = 1500    -- focus distance when the ray hits nothing
S.FOCUS_MIN = 150

function S.headNode(char)
  if char == "Rawlings" then return "Bip Rawllings Head" end   -- sic, as in rawlings.lua
  if char == "Ross" then return "Bip Jones Head" end
  return "Bip " .. char .. " Head"
end

-- The actor entity animating `char` in the current scene: <Scene><Char>, or any scene
-- actor whose skeleton has that character's head bone (TheTrap registers Jones as
-- "Delgado", for example).
function S.findActor(class, char)
  local node = "NodePosHierarchy_" .. S.headNode(char)
  local direct = Game.GetEntity(class .. char)
  if direct and direct[node] then return direct end
  local list = Scene.Actors and Scene.Actors[class]
  if not list then return nil end
  for _, info in pairs(list) do
    local e = Game.GetEntity(info[2])
    if e and not string.find(info[2], "FP_") then
      local ok, v = pcall(function() return e[node] end)
      if ok and v then return e end
    end
  end
  return nil
end

function S.start(class, char, actor)
  local cam = Game.GetEntity(S.CAM) or Game.CreateEntity(S.CAM, "FCam")
  local main = Game.GetEntity("MainCam")
  if main and main.Fov then cam.Fov = main.Fov end
  if cam.clipNear then cam.clipNear = 5 end
  S.prevCam = Game.GetCam(0)
  Game.SetCam(0, S.CAM)
  S.pov = {class = class, char = char, actor = actor.Name, node = S.headNode(char)}
  -- Seen from inside its head: hide the actor's own body, as in first person.
  actor.bObjectVisible = false
  -- A camera linked like the scene camera gives its position and view every frame.
  local eye = Game.GetEntity(S.EYE_CAM) or Game.CreateEntity(S.EYE_CAM, "Cam")
  eye.EntityLink = Scene.GetCamLink(class)
  -- The player watches through their own character: no "through X's eyes" caption.
  if CoopEnemies then CoopEnemies.fpLabel = nil end
  Coop.log("scene POV: " .. class .. " through " .. actor.Name .. " (" .. char .. ")")
end

-- The scene's camera character has only first-person arms. For players watching through
-- another character, show that character's real body (hidden by Scene.HideChars) where the
-- scene camera is, as PlayFP places the player (eye - CenterMoveY, yaw = camAng.y + 180),
-- and hide the floating arms.
S.EYE_CAM = "CoopFPEye"

function S.startStandIn(class, owner)
  local body = Game.GetEntity(owner)
  if not body then return end
  body.Active = 1
  body.TimeSpeed = 1
  if body.oAI then body.oAI.bEnable = false end
  local fp = Game.GetEntity(class .. "FP_" .. owner)
  if fp then fp.bObjectVisible = false end
  S.standIn = {body = owner, fp = fp and fp.Name}
  Coop.log("scene stand-in body: " .. owner)
end

function S.updateStandIn(dt)
  local si = S.standIn
  if not si then return end
  local body, eye = Game.GetEntity(si.body), Game.GetEntity(S.EYE_CAM)
  if not body or not eye or not eye.camPos then return end
  local p, a = eye.camPos, eye.camAng
  local h = body.oActCtrl and body.oActCtrl.oActClass and body.oActCtrl.oActClass.CenterMoveY or 150
  local target = V3D(p.x, p.y - h, p.z)
  local d = target - body.Pos
  local speed = math.sqrt(d.x * d.x + d.z * d.z) / math.max(dt or 0.033, 0.001)
  body.Pos = target
  body.Ang = V3D(0, a.y + 180, 0)
  body.InCtrl_Walk = speed > 60 and math.min(speed / 400, 1) or 0
end

function S.stopStandIn()
  local si = S.standIn
  if not si then return end
  local body = Game.GetEntity(si.body)
  if body then body.InCtrl_Walk = 0 end
  local fp = si.fp and Game.GetEntity(si.fp)
  if fp then fp.bObjectVisible = true end
  S.standIn = nil
end

function S.stop()
  S.stopStandIn()
  S.smooth, S.focus, S.eye = nil, nil, nil
  local eye = Game.GetEntity(S.EYE_CAM)
  if eye then eye:Del() end
  if not S.pov then return end
  if Game.GetCam(0) == S.CAM then Game.SetCam(0, S.prevCam or "MainCam") end
  local actor = Game.GetEntity(S.pov.actor)
  if actor then actor.bObjectVisible = true end
  S.pov = nil
end

function S.update(dt)
  if not Scene or not Scene.IsPlaying or not Scene.SceneName then
    if S.pov then S.stop() end
    S.checked = nil
    return
  end
  local class = string.sub(Scene.SceneName, 10)
  if not S.pov and S.checked ~= class then
    S.checked = class
    local me = Coop.localChar() or Coop.cfg.char   -- UsrEntity(0) is empty during FP scenes
    local owner = CoopEnemies and CoopEnemies.FP_OWNER[string.lower(class)]
    if me and owner and me ~= owner then
      local actor = S.findActor(class, me)
      if actor then
        S.start(class, me, actor)
        S.startStandIn(class, owner)
      else
        Coop.log("scene POV: no actor for " .. me .. " in " .. class)
      end
    end
  end
  S.updateStandIn(dt)
  if S.pov then S.updatePOV(dt) end
end

-- Camera angles that make the camera look along direction d. The engine's own forward of
-- a camera is V3D(0,0,1):rot(camAng) (QuickConsole.drawLine); the first conversion that
-- reproduces d is kept (checked once).
S.ANG_FORMS = {
  function(yaw, el) return V3D(-el, yaw + 180, 0) end,
  function(yaw, el) return V3D(el, yaw + 180, 0) end,
  function(yaw, el) return V3D(-el, yaw, 0) end,
  function(yaw, el) return V3D(el, yaw, 0) end,
}

function S.dirToAng(d)
  local horiz = math.sqrt(d.x * d.x + d.z * d.z)
  local len = math.sqrt(horiz * horiz + d.y * d.y)
  if len < 1e-3 then return nil end
  local yaw = math.deg(math.atan2(-d.x, -d.z))
  local el = math.deg(math.atan2(d.y, horiz))
  if not S.angForm then
    local best, bestDot = 1, -2
    for i, form in ipairs(S.ANG_FORMS) do
      local f = V3D(0, 0, 1):rot(form(yaw, el))
      local dot = (f.x * d.x + f.y * d.y + f.z * d.z) / len
      if dot > bestDot then best, bestDot = i, dot end
    end
    S.angForm = best
    Coop.log(string.format("scene POV: angle form %d (dot %.3f)", best, bestDot))
  end
  return S.ANG_FORMS[S.angForm](yaw, el)
end

-- camAng reads in degrees, but an FCam's Ang is set in radians (dev 'fcam' test: radians
-- reproduce MainCam's view exactly; sum_end's credits camera is set the same way).
function S.toFCam(a)
  return V3D(math.rad(a.x), math.rad(a.y), math.rad(a.z))
end

-- The scene camera's eye and view direction this frame. A camera linked like the scene
-- camera only computes camPos/camAng when its link is set, so it is re-linked every frame.
function S.ownerView()
  local eye = Game.GetEntity(S.EYE_CAM)
  if not eye then return nil end
  eye.EntityLink = ""
  eye.EntityLink = Scene.GetCamLink(S.pov.class)
  if not eye.camPos or not eye.camAng then return nil end
  return eye.camPos, V3D(0, 0, 1):rot(eye.camAng)
end

local function lowpass(cur, target, tau, dt)
  if not cur then return target end
  local k = 1 - math.exp(-math.min(dt or 0.033, 0.25) / tau)
  return cur + V3D((target.x - cur.x) * k, (target.y - cur.y) * k, (target.z - cur.z) * k)
end

-- Where the scene camera looks: the hit point of its view ray (or a point ahead), smoothed.
function S.updateFocus(dt, p, dir)
  local far = p + V3D(dir.x * S.FOCUS_RANGE, dir.y * S.FOCUS_RANGE, dir.z * S.FOCUS_RANGE)
  local target = Game.TestLine(p, far, "")
  if target then
    local d = target - p
    if math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z) < S.FOCUS_MIN then target = nil end
  end
  target = target or (p + V3D(dir.x * S.FOCUS_DEFAULT, dir.y * S.FOCUS_DEFAULT, dir.z * S.FOCUS_DEFAULT))
  S.focus = lowpass(S.focus, target, S.FOCUS_TAU, dt)
  return S.focus
end

-- The vanilla scene camera is directed (it pans to what matters). Other players see that
-- direction from their own character's eyes: the eye is the head of their character's scene
-- actor (smoothed against the animation's bob), looking at the scene camera's focus. The
-- actor's own body is hidden for them, as in first person. If the head is implausibly far
-- from the scene camera (no animation data), the eye stays near the scene camera.
S.EYE_TAU = 0.25
S.EYE_MAX = 2000

function S.updatePOV(dt)
  local a = Game.GetEntity(S.pov.actor)
  local cam = Game.GetEntity(S.CAM)
  if not a or not cam then S.stop() return end
  local hp = a["NodePosHierarchy_" .. S.pov.node]
  local p, dir = S.ownerView()
  if not hp or not p then return end
  local off = hp - p
  if math.sqrt(off.x * off.x + off.y * off.y + off.z * off.z) > S.EYE_MAX then hp = p end
  S.eye = lowpass(S.eye, hp, S.EYE_TAU, dt)
  local pos = S.eye
  cam.Pos = pos
  local focus = S.updateFocus(dt, p, dir)
  local look = focus - pos
  if math.sqrt(look.x * look.x + look.y * look.y + look.z * look.z) < S.FOCUS_MIN then look = dir end
  local ang = S.dirToAng(look)
  if ang then cam.Ang = S.toFCam(ang) end
  if Game.GetCam(0) ~= S.CAM then Game.SetCam(0, S.CAM) end
  S.frames = (S.frames or 0) + 1
  if S.frames % 60 == 1 then
    Coop.log(string.format("POV eye=%s owner=%s off=%s focus=%s", Coop.v3(pos), Coop.v3(p), Coop.v3(pos - p), Coop.v3(focus)))
  end
end

-- EndOfScene clears the link of whatever camera is current: hand MainCam back first.
function S.install()
  if S.installed or not Scene or not Scene.EndOfScene then return end
  S.installed = true
  local orig = Scene.EndOfScene
  Scene.EndOfScene = function(...)
    S.stop()
    return orig(...)
  end
end

------------------------------------------------------------------------------
-- Scene branches and QTEs (scripts/missions/qte.lua). One player decides each scene:
-- the human holding its first-person character, else the host. Only the decider sees
-- QTE prompts and presses keys. Every branch switch of the scene (Scene.PlayAlternate:
-- a failed QTE, a random torture loop, a replay after death) is taken by the decider
-- and sent to everyone; the others ignore their own choices.
--   qalt|<scene entity>|<suffix>   decider -> host -> everyone
------------------------------------------------------------------------------

function S.sceneClass(name)
  return name and string.sub(name, 10)
end

-- Peer id that decides the scene `name` (Scene.SceneName).
function S.decider(name)
  local owner = CoopEnemies and CoopEnemies.FP_OWNER[string.lower(tostring(S.sceneClass(name)))]
  local peer = owner and Coop.ownerOf(owner)
  return peer or 0
end

function S.decides(name)
  return not Coop.inSession() or S.decider(name) == Coop.myId()
end

-- QTE functions run for in-game grabs too; those always belong to the local player.
local function inSceneNotMine()
  return Coop.inSession() and Scene.IsPlaying and Scene.SceneName and not S.decides(Scene.SceneName)
end

function S.installQTE()
  if S.qteInstalled or not QTE or not QTE.LaunchSequence or not Scene or not Scene.PlayAlternate then return end
  S.qteInstalled = true
  for _, fn in ipairs({"LaunchSequence", "LaunchRndSequence", "WrongAction", "RightAction"}) do
    local orig = QTE[fn]
    QTE[fn] = function(...)
      if inSceneNotMine() then return end
      return orig(...)
    end
  end
  local origValidate = QTE.ValidateSequence
  QTE.ValidateSequence = function(...)
    if inSceneNotMine() then return end
    return origValidate(...)
  end
  S.origAlternate = Scene.PlayAlternate
  Scene.PlayAlternate = function(sufix, sceneName)
    local name = sceneName or Scene.SceneName
    if not S.decides(name) then
      Coop.log("scene branch " .. tostring(sufix) .. " of " .. tostring(name) .. " left to peer " .. S.decider(name))
      return
    end
    if Coop.inSession() then Net.CoopSend(-1, 1, "qalt|" .. tostring(name) .. "|" .. tostring(sufix)) end
    return S.origAlternate(sufix, sceneName)
  end
end

function S.onMessage(peer, f)
  if f[1] ~= "qalt" then return false end
  local name, sufix = f[2], f[3]
  if Coop.isHost() then Net.CoopSend(-1, 1, "qalt|" .. name .. "|" .. sufix) end
  if S.decides(name) then return true end   -- our own decision coming back
  if Scene.SceneName == name and Game.GetEntity(name) and S.origAlternate then
    Coop.log("scene branch " .. sufix .. " of " .. name .. " from peer " .. peer)
    S.origAlternate(sufix, name)
  else
    Coop.log("scene branch " .. sufix .. " for " .. name .. " ignored: playing " .. tostring(Scene.SceneName))
  end
  return true
end
