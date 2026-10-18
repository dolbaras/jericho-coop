-- Jericho co-op: cutscenes from each player's own character (docs/scenes-catalog.md 2.8).
-- First-person scenes film from one character's arms (FP_<Char>); that camera is directed:
-- it follows the points the scene wants us to look at (the villain stepping out, ...).
-- Every other squad member present has a full-body actor <Scene><Actor>. A player holding
-- one of them watches from that actor's head, but LOOKS AT THE SAME POINT as the scene
-- camera: the focus is where the scene camera's view ray hits the world.

CoopScenes = {}
local S = CoopScenes

-- Exponential smoothing of a vector towards target with time constant tau (seconds).
local function lowpass(cur, target, tau, dt)
  if not cur then return target end
  local k = 1 - math.exp(-math.min(dt or 0.033, 0.25) / tau)
  return cur + V3D((target.x - cur.x) * k, (target.y - cur.y) * k, (target.z - cur.z) * k)
end

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

-- The first-person camera bobs and turns with every gesture; a body copying it each frame
-- ran on the spot and spun (scene audit, wwii_biggates Conversation). The stand-in follows a
-- smoothed anchor, walks only while the anchor really travels, faces where it walks, and
-- otherwise stands in its idle pose turned (slowly) towards where the camera looks.
S.STANDIN_POS_TAU = 0.35
S.STANDIN_SPEED_TAU = 0.4
S.STANDIN_YAW_TAU = 0.6
S.STANDIN_WALK_SPEED = 90   -- units/s of anchor travel before the body walks

local function yawLowpass(cur, target, tau, dt)
  if not cur then return target end
  local d = (target - cur + 540) % 360 - 180
  return cur + d * (1 - math.exp(-math.min(dt or 0.033, 0.25) / tau))
end

function S.updateStandIn(dt)
  local si = S.standIn
  if not si then return end
  local body, eye = Game.GetEntity(si.body), Game.GetEntity(S.EYE_CAM)
  if not body or not eye or not eye.camPos then return end
  local p, a = eye.camPos, eye.camAng
  local h = body.oActCtrl and body.oActCtrl.oActClass and body.oActCtrl.oActClass.CenterMoveY or 150
  -- Stand on the floor under the camera (a body hung below the camera sank into the floor
  -- whenever the character sat or knelt) and crouch when the camera is low.
  local ground = Game.TestLine(p, V3D(p.x, p.y - 3 * h, p.z), "")
  local footY = ground and ground.y or (p.y - h)
  local camH = p.y - footY
  si.crouch = camH < h * (si.crouch and 0.85 or 0.75)   -- with hysteresis
  local prev = si.pos
  si.pos = lowpass(si.pos, V3D(p.x, footY, p.z), S.STANDIN_POS_TAU, dt)
  local step = prev and (si.pos - prev) or V3D(0, 0, 0)
  local inst = math.sqrt(step.x * step.x + step.z * step.z) / math.max(dt or 0.033, 0.001)
  si.speed = (si.speed or 0) + (inst - (si.speed or 0)) * (1 - math.exp(-math.min(dt or 0.033, 0.25) / S.STANDIN_SPEED_TAU))
  body.Pos = si.pos
  local wantYaw = a.y + 180
  if si.speed > S.STANDIN_WALK_SPEED and inst > 1 then
    wantYaw = math.deg(math.atan2(-step.x, -step.z))
    body.InCtrl_Walk = math.max(0.3, math.min(si.speed / 450, 1))
  else
    body.InCtrl_Walk = 0
  end
  si.yaw = yawLowpass(si.yaw, wantYaw, S.STANDIN_YAW_TAU, dt)
  body.Ang = V3D(0, si.yaw, 0)
  -- Head and aim follow the camera's pitch (PlayFP itself sets ViewAng.x = -camAng.x).
  si.pitch = (si.pitch or 0) + ((-a.x) - (si.pitch or 0)) * (1 - math.exp(-math.min(dt or 0.033, 0.25) / S.STANDIN_YAW_TAU))
  body.ViewAng = V3D(si.pitch, si.yaw, 0)
  if body.owc then body.owc.Crouch = si.crouch and 1 or 0 end
  body.InCtrl_Str = 0
  body.InCtrl_Sprint = 0
end

function S.stopStandIn()
  local si = S.standIn
  if not si then return end
  local body = Game.GetEntity(si.body)
  if body then
    body.InCtrl_Walk = 0
    if body.owc then body.owc.Crouch = 0 end
  end
  local fp = si.fp and Game.GetEntity(si.fp)
  if fp then fp.bObjectVisible = true end
  S.standIn = nil
end

function S.stop()
  S.stopStandIn()
  S.smooth, S.focus, S.eye, S.look, S.headCache = nil, nil, nil, nil, nil
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
    S.stopExtras()
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
        -- The full-body copy (below) replaces the old stand-in where it exists.
        if not (S.body and S.body.class == class) then S.startStandIn(class, owner) end
      else
        Coop.log("scene POV: no actor for " .. me .. " in " .. class)
      end
    end
    S.showBody(class)
    S.startExtras(class)
    -- The AI did this character's action (nobody took it over): its QTE passes by itself.
    if Coop.isHost() and owner and Coop.ownerOf(owner) == nil and CoopClaim and CoopClaim.aiDid[owner] then
      S.savedQTEMode = Game.Get("QTEMode")
      Game.Set("QTEMode", 2)
      Coop.log("scene QTE: " .. owner .. " is AI, QTE passes by itself")
    end
  end
  S.updateStandIn(dt)
  S.updateBody()
  S.updateExtras(dt)
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

-- Heads of the scene's actors (Scene.Actors[class] = {"Actor_<Name>", entity, actor class}),
-- for finding who the scene camera looks at. World rays pass through characters, so a
-- speaker looked at would otherwise give a point on the floor or wall behind them.
S.HEAD_NODES = {"Bip01 Head", "Bip %s Head", "Bip Head"}
S.LOOK_CONE_COS = 0.85   -- within about 32 degrees of the view ray (the subject is rarely centred)

function S.actorHead(info)
  local e = Game.GetEntity(info[2])
  if not e or string.find(info[3] or "", "^FP_") then return nil end
  S.headCache = S.headCache or {}
  local node = S.headCache[info[2]]
  if node == nil then
    local tries = {"NodePosHierarchy_" .. S.headNode(info[3] or "")}
    for _, n in ipairs(S.HEAD_NODES) do tries[#tries + 1] = "NodePosHierarchy_" .. string.format(n, info[3] or "") end
    for _, k in ipairs(tries) do
      local ok, v = pcall(function() return e[k] end)
      if ok and v then node = k break end
    end
    S.headCache[info[2]] = node or false
  end
  return node and e[node] or nil
end

-- The actor head closest to the view ray (p, dir) and nearer than maxDist; mine = it is the
-- local player's own actor.
function S.lookedAtActor(p, dir, maxDist)
  local list = Scene.Actors and S.pov and Scene.Actors[S.pov.class]
  if not list then return nil end
  local best, bestCos, mine
  for _, info in pairs(list) do
    local hp = S.actorHead(info)
    if hp then
      local v = hp - p
      local dist = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
      local c = dist > 0 and (v.x * dir.x + v.y * dir.y + v.z * dir.z) / dist or 0
      if S.debugLook then S.debugLook[#S.debugLook + 1] = string.format("%s:%.0f/%.2f", tostring(info[3]), dist, c) end
      if dist > 50 and dist < maxDist then
        if c > S.LOOK_CONE_COS and (not bestCos or c > bestCos) then
          best, bestCos, mine = hp, c, info[2] == S.pov.actor
        end
      end
    end
  end
  return best, mine
end

-- Where a player looked at by the scene's character looks back: that character's visible
-- full body (its head), else the scene camera. First-person scene cameras sit up to a few
-- metres off the body's head (HelicopterTrip: about 2.2 m), so looking at the camera
-- itself stared at a seat.
function S.speakerPos(p)
  local b = S.body
  if b and not b.hidden and S.pov and b.class == S.pov.class then
    local hp = S.actorHead({"", b.entity, b.char})
    if hp then return hp end
  end
  return p
end

-- Where the scene camera looks, smoothed: the actor it looks at (or, when that is the local
-- player's own actor, the speaker: the scene camera itself), else the hit point of its view
-- ray, else a point ahead.
function S.updateFocus(dt, p, dir)
  local far = p + V3D(dir.x * S.FOCUS_RANGE, dir.y * S.FOCUS_RANGE, dir.z * S.FOCUS_RANGE)
  local hit = Game.TestLine(p, far, "")
  local hitDist = S.FOCUS_RANGE
  if hit then
    local d = hit - p
    hitDist = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
    if hitDist < S.FOCUS_MIN then hit = nil end
  end
  S.debugLook = ((S.frames or 0) % 60 == 0) and {} or nil
  local head, mine = S.lookedAtActor(p, dir, hitDist + 100)
  if S.debugLook then Coop.log(string.format("look: hit %.0f, %s", hitDist, table.concat(S.debugLook, " "))) end
  local target
  if head then
    target = mine and S.speakerPos(p) or head
  else
    target = hit or (p + V3D(dir.x * S.FOCUS_DEFAULT, dir.y * S.FOCUS_DEFAULT, dir.z * S.FOCUS_DEFAULT))
  end
  S.focusActor = head and (mine and "self" or "actor") or "world"
  S.focus = lowpass(S.focus, target, S.FOCUS_TAU, dt)
  return S.focus
end

-- The vanilla scene camera is directed (it pans to what matters). Other players see that
-- direction from their own character's eyes: the eye is the head of their character's scene
-- actor (smoothed against the animation's bob), looking at the scene camera's focus. The
-- actor's own body is hidden for them, as in first person. If the head is implausibly far
-- from the scene camera (no animation data), the eye stays near the scene camera.
S.EYE_TAU = 0.25
S.SELF_FOCUS = 180        -- the scene camera looks at this player's own head
S.LOOK_TAU = 0.35
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
  -- When the scene camera looks at this character (the speaker turns to them), they look
  -- back at the speaker instead of into their own face.
  local focus = S.updateFocus(dt, p, dir)
  local toSelf = focus - pos
  local target = math.sqrt(toSelf.x * toSelf.x + toSelf.y * toSelf.y + toSelf.z * toSelf.z) < S.SELF_FOCUS and S.speakerPos(p) or focus
  S.look = lowpass(S.look, target, S.LOOK_TAU, dt)
  local look = S.look - pos
  if math.sqrt(look.x * look.x + look.y * look.y + look.z * look.z) < S.FOCUS_MIN then look = dir end
  local ang = S.dirToAng(look)
  if ang then cam.Ang = S.toFCam(ang) end
  if Game.GetCam(0) ~= S.CAM then Game.SetCam(0, S.CAM) end
  S.frames = (S.frames or 0) + 1
  if S.frames % 60 == 1 then
    Coop.log(string.format("POV eye=%s owner=%s off=%s focus=%s (%s)", Coop.v3(pos), Coop.v3(p), Coop.v3(pos - p), Coop.v3(focus), tostring(S.focusActor)))
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

------------------------------------------------------------------------------
-- Full-body copy of the first-person character. A first-person scene animates its owner
-- only as FP_<Char> (arms and camera on screen), but those animation files drive the whole
-- biped ("Bip <Char> ..." nodes, legs included: dev 'bones'). Played on the character's
-- full model they show what the character really does in the scene: sits in the
-- helicopter, kneels, types, gestures. Every first-person scene loaded in a session gets
-- this extra actor "CoopBody"; it mirrors the FP actor's current action (branches and
-- retries included) and is hidden for the player who watches through those eyes.
------------------------------------------------------------------------------

S.BODY_MODEL = {RossNude = "Ross"}   -- FP models without a full-body twin of the same name

-- Levels load most scenes when they start, before the mod, so the body is added when a
-- scene is played: Scene.Play calls Scene.Load every time (it returns early if loaded).
function S.installBodyActor()
  if S.bodyInstalled or not Scene or not Scene.Load then return end
  S.bodyInstalled = true
  local origLoad = Scene.Load
  Scene.Load = function(SceneClass, ...)
    local r = {origLoad(SceneClass, ...)}
    if Coop.inSession() then
      local ok, err = pcall(S.ensureBody, SceneClass)
      if not ok then Coop.log("scene body error: " .. tostring(err)) end
    end
    return unpack(r)
  end
end

-- Action names the scene scripts give FP actors (mapscenes.lua: Play, PlayA..I, Play_A..,
-- <Scene>, <Scene>A.., Behemoth_A.., SceneApertura).
function S.fpActionNames(class)
  local names, bases = {}, {"Play", class, "Behemoth", "Scene" .. class}
  local suffixes = {"", "A", "B", "C", "D", "E", "F", "G", "H", "I", "_A", "_B", "_C", "_D"}
  for _, b in ipairs(bases) do
    for _, x in ipairs(suffixes) do names[#names + 1] = b .. x end
  end
  return names
end

function S.ensureBody(class)
  local list = Scene.Actors and Scene.Actors[class]
  if not list then return end
  local fpInfo
  for _, info in ipairs(list) do
    if info[2] == class .. "CoopBody" then return end
    if not fpInfo and string.find(info[3] or "", "^FP_") then fpInfo = info end
  end
  if not fpInfo then return end
  local fpc = Act.GetClass(fpInfo[2])
  if not fpc then return end
  local rec = {}
  for _, name in ipairs(S.fpActionNames(class)) do
    local a = fpc:GetAct(name)
    if a then rec[#rec + 1] = {name = name, file = a.AnmFilePath, loop = a.isLoop, turn = a.RotSpeed} end
  end
  if #rec == 0 then
    Coop.log("scene body: no FP actions found for " .. fpInfo[2])
    return
  end
  local char = string.sub(fpInfo[3], 4)
  local model = S.BODY_MODEL[char] or char
  local sceneName, last = Scene.SceneName, Scene.lastActorName
  Scene.SceneName = class
  local ac = Scene.BaseAddActor("CoopBody", model, "Models/Chars/" .. model .. "/" .. model .. ".M3D")
  -- Scenes not in absolute coordinates link every actor to its node in the scene model
  -- (LinkModel "<scene>,Actor_<name>", Scene.Play); the body takes the FP actor's node.
  list[#list][1] = fpInfo[1]
  pcall(Act.SetCls, "Discardable", 1)
  for _, a in ipairs(rec) do
    if ac:GetAct(a.name) == nil then
      local act = ac:NewAct(a.name)
      act.AnmFilePath = a.file
      act.isLoop = a.loop or 0
      act.RotSpeed = a.turn or 0
      act.AngRotLimit = 90
      act.UseDisp = 0
      act.NodeModifier = -1
      act.AngleModifierSpeed = 5
      act.AnimAbsMove = 1
    end
  end
  ac.DefAction = fpc.DefAction or rec[1].name
  Scene.SceneName, Scene.lastActorName = sceneName, last
  S.body = {class = class, char = char == "RossNude" and "Ross" or char, fp = fpInfo[2], entity = class .. "CoopBody"}
  Coop.log(string.format("scene body: %s gets %s with %d actions of %s (%s)", class, model, #rec, fpInfo[2], rec[1].file))
end

-- At scene start: the body is shown only to players watching from their own actor; whoever
-- watches through the character's eyes (its owner, or a player with no actor in the scene)
-- would have it in front of the camera.
function S.showBody(class)
  local b = S.body
  if not b or b.class ~= class then return end
  local e = Game.GetEntity(b.entity)
  if not e then return end
  b.hidden = S.pov == nil
  e.bObjectVisible = not b.hidden
  Coop.log("scene body: " .. b.entity .. (b.hidden and " hidden (seen through its eyes)" or " shown"))
end

function S.updateBody()
  local b = S.body
  if not b or not Scene.SceneName or string.sub(Scene.SceneName, 10) ~= b.class then return end
  local fp, body = Game.GetEntity(b.fp), Game.GetEntity(b.entity)
  if not fp or not body then return end
  local act = fp.Action
  if act and act ~= "" and body.Action ~= act then
    body.ForceAction = act
    body.ForceDefLoop = act
  end
end

S.installBodyActor()

------------------------------------------------------------------------------
-- Everyone else stays alive on screen, from any player's viewpoint:
-- * Squad members who are in the level but not in the scene: vanilla hides them
--   (Scene.HideChars) because the owner's camera never sees them, but another player's
--   camera may look where they stand. They stay visible, idling with their own relax
--   animations, slowly turning towards the scene.
-- * Scene actors whose animation ended while the scene goes on (RawlingsTorture's loop
--   branches animate only Rawlings; Church and Cole froze): the actor is swapped for the
--   character's real body idling at the same spot, until the scene gives it a new action.
------------------------------------------------------------------------------

S.IDLE_GRACE = 0.3            -- seconds past the end of an animation before idling
-- Scenes where squad members are in the level but not in the scene, checked against the
-- story (they must really be there, not gone or on another task):
--   RossDeath: all six gather at the Firstborn first (alk_final MapInit.EveryBodyLookAtFistro);
--     Church and Cole are actors again in RossDeathB.
--   NaziSacrificeB: Jones, Delgado and Black wait at the foot of the gate while Church climbs.
--   TheEndA: Church, Delgado and Rawlings start sum_end with Black; actors again in TheEndB.
S.WATCH_SCENES = {RossDeath = true, NaziSacrificeB = true, TheEndA = true}
S.WATCH_RADIUS = 2500          -- farther from the scene's people: leave them hidden
S.WATCH_YAW_TAU = 1.2
S.PEOPLE = {Ross = true}
for name in pairs(Coop.SQUAD_SET) do S.PEOPLE[name] = true end

function S.dist(a, b)
  local d = a - b
  return math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
end

local function bone(char, part)
  return "Bip " .. (char == "Rawlings" and "Rawllings" or char) .. " " .. part
end

function S.startExtras(class)
  S.stopExtras()
  local x = {class = class, watchers = {}, actors = {}}
  local inScene = {}
  for _, info in ipairs((Scene.Actors and Scene.Actors[class]) or {}) do
    local c = info[3] or ""
    if string.find(c, "^FP_") then
      inScene[string.sub(c, 4)] = true
    elseif S.PEOPLE[c] then
      inScene[c] = true
      local hiddenBody = S.body and S.body.entity == info[2] and S.body.hidden
      if not hiddenBody then x.actors[info[2]] = {char = c, entity = info[2]} end
    end
  end
  -- Watchers only for players who see the scene from their own actor: the vanilla
  -- first-person framing (its owner, or players without an actor) stays as it was.
  local hidden = S.pov and S.WATCH_SCENES[class] and Scene.HidenChars or {}
  S.extras = x
  local center = S.sceneCenter()
  for _, name in ipairs(hidden) do
    local e = Game.GetEntity(name)
    local near = center and e and S.dist(e.Pos, center) < S.WATCH_RADIUS
    if S.PEOPLE[name] and not inScene[name] and e and near and (e.Life or 0) > 0 and e.bActive ~= false then
      e.Active = 1
      e.TimeSpeed = 1
      if e.oAI then e.oAI.bEnable = false end
      e.InCtrl_Walk, e.InCtrl_Str = 0, 0
      x.watchers[name] = {yaw = e.Ang.y}
      Coop.log("scene extras: " .. name .. " stays in view, idle")
    end
  end
  S.extras = x
end

-- Middle of the scene's people (actor heads), what the watchers turn to.
function S.sceneCenter()
  local sx, sy, sz, n = 0, 0, 0, 0
  for _, info in ipairs((Scene.Actors and S.extras and Scene.Actors[S.extras.class]) or {}) do
    local hp = S.actorHead(info)
    if hp then sx, sy, sz, n = sx + hp.x, sy + hp.y, sz + hp.z, n + 1 end
  end
  if n == 0 then return nil end
  return V3D(sx / n, sy / n, sz / n)
end

function S.beginIdle(a, e)
  local body = Game.GetEntity(a.char)
  if not body or (S.pov and a.entity == S.pov.actor) then return end
  local pelvis = e["NodePosHierarchy_" .. bone(a.char, "Pelvis")]
  local head = e["NodeAngHierarchy_" .. S.headNode(a.char)]
  if not pelvis then return end
  local ground = Game.TestLine(pelvis, V3D(pelvis.x, pelvis.y - 300, pelvis.z), "")
  local yaw = body.Ang.y
  if head then
    local f = V3D(0, 0, 1):rot(head)
    yaw = math.deg(math.atan2(-f.x, -f.z))
  end
  body.Active = 1
  body.TimeSpeed = 1
  if body.oAI then body.oAI.bEnable = false end
  body.InCtrl_Walk, body.InCtrl_Str = 0, 0
  body.Pos = ground or V3D(pelvis.x, pelvis.y - 90, pelvis.z)
  body.Ang = V3D(0, yaw, 0)
  body.bObjectVisible = true
  e.bObjectVisible = false
  a.idle = true
  Coop.log("scene extras: " .. a.entity .. " animation ended, " .. a.char .. " idles in its place")
end

function S.endIdle(a)
  local e, body = Game.GetEntity(a.entity), Game.GetEntity(a.char)
  if e and not (S.pov and a.entity == S.pov.actor) then e.bObjectVisible = true end
  if body and not (S.extras and S.extras.watchers[a.char]) then body.Active = 0 end
  a.idle = false
end

function S.updateExtras(dt)
  local x = S.extras
  if not x then return end
  local now = Game.GetTime()
  for _, a in pairs(x.actors) do
    local e = Game.GetEntity(a.entity)
    if e then
      local act = e.Action
      if act ~= a.action then
        a.action, a.t0 = act, now
        if a.idle then S.endIdle(a) end
      end
      local cls = Act.GetClass(a.entity)
      local ad = cls and act and act ~= "" and cls:GetAct(act)
      if not a.idle and ad and ad.isLoop ~= 1 and ad.AnmTotalTime and now - a.t0 > ad.AnmTotalTime + S.IDLE_GRACE then
        S.beginIdle(a, e)
      end
    end
  end
  local center = next(x.watchers) and S.sceneCenter()
  if center then
    for name, w in pairs(x.watchers) do
      local e = Game.GetEntity(name)
      if e then
        local d = center - e.Pos
        local want = math.deg(math.atan2(-d.x, -d.z))
        local k = 1 - math.exp(-math.min(dt or 0.033, 0.25) / S.WATCH_YAW_TAU)
        w.yaw = w.yaw + ((want - w.yaw + 540) % 360 - 180) * k
        e.Ang = V3D(0, w.yaw, 0)
      end
    end
  end
end

-- After the scene vanilla shows its hidden characters again; give the AI back to the
-- bodies no human holds.
function S.stopExtras()
  if S.savedQTEMode then
    Game.Set("QTEMode", S.savedQTEMode)
    S.savedQTEMode = nil
  end
  local x = S.extras
  if not x then return end
  S.extras = nil
  local touched = {}
  for name in pairs(x.watchers) do touched[name] = true end
  for _, a in pairs(x.actors) do if a.idle then touched[a.char] = true end end
  for name in pairs(touched) do
    local e = Game.GetEntity(name)
    if e and e.oAI and Coop.ownerOf(name) == nil then e.oAI.bEnable = true end
  end
end
