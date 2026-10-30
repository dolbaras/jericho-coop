-- Jericho co-op: the spectator camera (0.2.8, owner bug 9).
--
-- A player whose body is down waits for Rawlings while the living bodies all belong to other
-- players (coop_team.lua: T.down). Before 0.2.8 the game's own camera was pointed at a
-- partner at first-person distance: a view from inside the head with the partner's nameplate
-- in the middle of the screen. Now the dead player gets a proper third-person follow camera:
--   * its own FCam (CoopSpecCam, as the spirit's), placed behind the watched body's shoulder,
--     smoothed, kept out of walls (Game.TestLine from the body to the wanted place);
--   * the watched body's nickname is a small caption, not something the view is fixed on (its
--     nameplate is off while watched, coop_hud.lua);
--   * A / D, the left stick, the arrow keys or fire switch between the living players when there
--     are several; mouse or right stick orbits; after a moment the view swings back behind the
--     body again;
--   * a watched player who dies hands the camera to the nearest living one;
--   * a revive, another body, a cutscene or a level change gives the normal camera back.
-- In split screen (two views on one machine) the old way stays: MainCam's targets move
-- (coop_team.lua: T.watchPartner).
CoopSpectate = {}
local S = CoopSpectate
S.CAM = "CoopSpecCam"
S.DIST = 230            -- camera distance behind the shoulder
S.BODY_HIDE = 110       -- the watched body is hidden while the camera is nearer than this
S.CLOSEST = 85         -- the nearest the view comes to the body in a tight spot (outside its radius of 50)
S.BACK_GAP = 25         -- kept off a wall by this much
S.CHEST = 150           -- the point looked at: units above the body's origin
S.SHOULDER = 35         -- sideways, so the body is not in the exact middle
S.PITCH = -12           -- degrees, negative looks down
S.TURN = 3              -- degrees per frame (at 30 fps) per unit of turn input, as the spirit
S.SWING_AFTER = 1.5     -- seconds without looking around before the view swings back
S.SWING_RATE = 2.5      -- per second
S.POS_RATE = 10         -- camera position smoothing per second
S.ANCHOR_RATE = 14
S.SNAP_DIST = 700       -- a watched body farther from the view than this was teleported
S.HUD_ITEMS = {"Damage", "Ammo", "Selector", "Aim"}   -- hidden while watching
S.KEY_PREV, S.KEY_NEXT = 0x25, 0x27   -- arrow keys
S.KEY_FIRE = 0x01                      -- left mouse button read straight too (live: the engine's MainShot reads 0 on a dead body)
S.KEY_A, S.KEY_D = 0x41, 0x44          -- A / D read straight from the keyboard (live 2026-10-30: the engine's strafe input reads 0 on a dead body)
S.SWITCH_GAP = 0.3      -- seconds: one switch at most per this long, whichever input asked (a key and the strafe axis may both fire for one press)

S.TEXT = {
  en = {watch = "Watching: %s",
        multi = "A / D or left stick: other player.  Mouse or right stick: look around.",
        one = "Mouse or right stick: look around."},
  ru = {watch = "Вы смотрите за: %s",
        multi = "A / D или левый стик: другой игрок.  Мышь или правый стик: осмотреться.",
        one = "Мышь или правый стик: осмотреться."},
}

function S.text(key)
  local lang = Coop.lang()
  local s = (S.TEXT[lang] or S.TEXT.en)[key] or S.TEXT.en[key]
  return Coop.enc(s, lang)
end

local function sub(a, b) return V3D(a.x - b.x, a.y - b.y, a.z - b.z) end
local function len(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function lerp(a, b, f) return V3D(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f) end
local function wrap(a)   -- degrees to -180..180
  a = a % 360
  if a > 180 then a = a - 360 end
  return a
end

-- View direction from yaw (entity convention) and elevation, degrees (as coop_spirit.lua).
local function forward(yaw, el)
  local y, e = math.rad(yaw), math.rad(el)
  return V3D(-math.sin(y) * math.cos(e), math.sin(e), -math.cos(y) * math.cos(e))
end

local function input(action)
  local ok, v = pcall(Input.GetInputState, "Walk", action, 0)
  return ok and tonumber(v) or 0
end

-- The living bodies another player holds, in a fixed order (owner, then name).
function S.list(usr)
  local t = {}
  for name, owner in pairs(Coop.owners or {}) do
    if not (usr and name == usr.Name) then
      local e = Game.GetEntity(name)
      if e and (e.Life or 0) > 0 and e.Active ~= 0 and e.bActive ~= false then
        t[#t + 1] = {name = name, owner = owner}
      end
    end
  end
  table.sort(t, function(a, b)
    if a.owner ~= b.owner then return a.owner < b.owner end
    return a.name < b.name
  end)
  return t
end

-- Nickname of the body's player and the character's name.
function S.label(name)
  local char = Coop.charName(name)
  local nick = CoopHud and CoopHud.label and CoopHud.label(name) or char
  if nick == char or nick == "" then return char end
  return nick .. " (" .. char .. ")"
end

-- The engine's body-down state is the player's, not ours: only read it.
function S.wanted(usr)
  if CoopSplit and CoopSplit.on then return false end
  local T = CoopTeam
  return T and T.down and usr and (usr.Life or 1) <= 0 and Coop.inSession()
end

function S.select(name, why)
  if S.target == name then return end
  local from = S.target
  if from then S.hideBody(nil) end
  S.target = name
  S.lookT = nil
  local e = Game.GetEntity(name)
  S.yaw = (e and e.Ang) and e.Ang.y or 0
  S.el = S.PITCH
  Coop.log("spectate: watching " .. name .. (from and (" (was " .. from .. ", " .. tostring(why) .. ")") or ""))
end

-- Next (dir 1) or previous (-1) living player in the list.
function S.step(list, dir)
  if #list < 2 then return end
  local at = 1
  for i, v in ipairs(list) do if v.name == S.target then at = i end end
  S.select(list[(at - 1 + dir) % #list + 1].name, "switch")
end

function S.enter(usr, list)
  local cam = Game.GetEntity(S.CAM) or Game.CreateEntity(S.CAM, "FCam")
  local main = Game.GetEntity("MainCam")
  if main and main.Fov then cam.Fov = main.Fov end
  S.prevCam = Game.GetCam(0)
  S.hidden = {}
  for _, n in ipairs(S.HUD_ITEMS) do
    local it = Scorer.GetItem(0, n)
    if it and it.Visible ~= 0 then it.Visible = 0; S.hidden[#S.hidden + 1] = n end
  end
  S.active, S.keys, S.snapNext = true, {}, true
  S.prime()   -- (what is held at death - fire, A / D - switches nothing until released)
  S.switchT = nil
  S.target = nil
  local from = usr.Pos
  local best, bd
  for _, v in ipairs(list) do
    local e = Game.GetEntity(v.name)
    local d = e and len(sub(e.Pos, from))
    if d and (not bd or d < bd) then best, bd = v.name, d end
  end
  S.select(best, "start")
  Game.SetCam(0, S.CAM)
  Coop.log("spectate: camera on (" .. #list .. " living)")
end

function S.leave(why)
  if not S.active then return end
  S.active = false
  if Game.GetCam(0) == S.CAM then Game.SetCam(0, "MainCam") end
  for _, n in ipairs(S.hidden or {}) do
    local it = Scorer.GetItem(0, n)
    if it then it.Visible = 1 end
  end
  S.hidden = nil
  S.hideBody(nil)
  Coop.textBlockHide("CoopSpectate")
  Coop.textBlockHide("CoopSpectateHint")
  S.target = nil
  Coop.log("spectate: camera off (" .. tostring(why) .. ")")
end

-- The watched body is hidden while the camera is inside its reach (nil: show it again).
function S.hideBody(e)
  local old = S.bodyHidden and Game.GetEntity(S.bodyHidden)
  if old and (not e or old.Name ~= e.Name) then old.bObjectVisible = true end
  S.bodyHidden = nil
  if e then
    e.bObjectVisible = false
    S.bodyHidden = e.Name
  end
end

-- Every frame: place the camera.
function S.frame(dt)
  if not S.active then return end
  local cam = Game.GetEntity(S.CAM)
  local e = S.target and Game.GetEntity(S.target)
  if not cam or not e or not e.Pos then return end
  dt = math.min(dt or 0.033, 0.1)
  local now = Net.CoopTime()
  -- Looking around: the mouse or the right stick turns the view round the body.
  local tx = input("TurnRight") - input("TurnLeft")
  local ty = input("TurnUp") - input("TurnDown")
  if Game.Get("InvertCharAxisControl") ~= 0 then ty = -ty end
  local k = dt * 30
  if math.abs(tx) > 0.05 or math.abs(ty) > 0.05 then
    S.yaw = (S.yaw or 0) - tx * S.TURN * k
    S.el = math.max(-70, math.min(40, (S.el or S.PITCH) + ty * S.TURN * 0.5 * k))
    S.lookT = now
  elseif not S.lookT or now - S.lookT > S.SWING_AFTER then
    -- Swings back behind the body's facing, the short way round, and to the usual pitch.
    local want = e.Ang and e.Ang.y or S.yaw
    local f = 1 - math.exp(-S.SWING_RATE * dt)
    S.yaw = S.yaw + wrap(want - S.yaw) * f
    S.el = S.el + (S.PITCH - S.el) * f
  end
  -- The point looked at, followed with a little smoothing.
  local anchor = e.Pos + V3D(0, S.CHEST, 0)
  if S.snapNext or not S.anchor or len(sub(anchor, S.anchor)) > S.SNAP_DIST then
    S.anchor, S.pos, S.snapNext = anchor, nil, nil
  else
    local f = 1 - math.exp(-S.ANCHOR_RATE * dt)
    S.anchor = lerp(S.anchor, anchor, f)
  end
  -- The wanted place: behind the view direction, a little to the right.
  local fwd = forward(S.yaw, S.el)
  local rx, rz = -fwd.z, fwd.x
  local rl = math.sqrt(rx * rx + rz * rz)
  if rl > 0.001 then rx, rz = rx / rl, rz / rl end
  local wantPos = S.anchor + V3D(-fwd.x * S.DIST + rx * S.SHOULDER, -fwd.y * S.DIST, -fwd.z * S.DIST + rz * S.SHOULDER)
  if not S.pos then
    S.pos = wantPos
  else
    local f = 1 - math.exp(-S.POS_RATE * dt)
    S.pos = lerp(S.pos, wantPos, f)
  end
  -- Out of walls: the ray from the body to the camera stops short of what it hits.
  local pos = S.pos
  local ok, hit = pcall(Game.TestLine, S.anchor, pos, "")
  if not (ok and hit) then
    -- (a surface seen only from outside does not stop a ray leaving a wall's volume: the way back does)
    ok, hit = pcall(Game.TestLine, pos, S.anchor, "")
  end
  if ok and hit then
    local d = sub(S.anchor, hit)
    local dl = len(d)
    if dl > 0.01 then
      S.blocked = (S.blocked or 0) + 1
      -- A wall close behind (a corridor, a corner): look down from above instead of squeezing in.
      local raised
      if dl < S.DIST * 0.6 then
        for _, e2 in ipairs({-30, -50, -68}) do
          local f2 = forward(S.yaw, e2)
          local p2 = V3D(S.anchor.x - f2.x * S.DIST, S.anchor.y - f2.y * S.DIST, S.anchor.z - f2.z * S.DIST)
          local okh, h2 = pcall(Game.TestLine, S.anchor, p2, "")
          if okh and not h2 then raised = p2 break end
        end
      end
      if raised then
        pos = raised
      else
        -- (at least CLOSEST from the body, or the view would sit inside its head)
        local back = math.min(S.BACK_GAP, dl)
        local at = math.max(S.CLOSEST, dl - back)
        pos = V3D(S.anchor.x - d.x / dl * at, S.anchor.y - d.y / dl * at, S.anchor.z - d.z / dl * at)
      end
    end
  end
  cam.Pos = pos
  -- Closer than the body's width plus the near plane: the body would fill the view from inside, so it is hidden
  -- (and shown again as the camera backs off).
  local near = len(sub(pos, S.anchor)) < S.BODY_HIDE
  if near ~= (S.bodyHidden == S.target) then S.hideBody(near and e or nil) end
  -- (the camera looks at the body's point: from the clamped place along the same direction)
  local look = sub(S.anchor, pos)
  local ll = len(look)
  local yaw, el = S.yaw, S.el
  if ll > 1 then
    yaw = math.deg(math.atan2(-look.x, -look.z))
    el = math.deg(math.asin(look.y / ll))
  end
  if CoopScenes and CoopScenes.toFCam then cam.Ang = CoopScenes.toFCam(V3D(-el, yaw + 180, 0)) end
  if Game.GetCam(0) ~= S.CAM then Game.SetCam(0, S.CAM) end
end

local function pressed(vk)
  local down = Net.CoopKey ~= nil and Net.CoopKey(vk) == 1
  local was = S.keys[vk]
  S.keys[vk] = down
  return down and not was
end

local function strafeAxis()
  local sx = input("StrafeRight") - input("StrafeLeft")
  if math.abs(sx) < 0.05 and Net.CoopKey then
    -- (the left stick read straight from the pad: a downed body's walk actions can read 0)
    local pad = {pcall(Net.CoopKey, -1, 0)}
    local lx = pad[1] and tonumber(pad[5])
    if lx and math.abs(lx) > 7849 then sx = lx / 32767 end
  end
  return sx
end

-- The inputs count as "held now": the next switch needs a new press (at entry, and while a menu is open).
function S.prime()
  S.keys = S.keys or {}
  if Net.CoopKey then
    for _, vk in ipairs({S.KEY_NEXT, S.KEY_PREV, S.KEY_FIRE, S.KEY_A, S.KEY_D}) do S.keys[vk] = Net.CoopKey(vk) == 1 end
  end
  S.shotHeld = input("MainShot") > 0.5
  S.sHeld = math.abs(strafeAxis()) > 0.6
end

-- Strafe left/right (A, D, the left stick) and fire switch players, once per press.
local function switchDir()
  local sx = strafeAxis()
  local dir = 0
  if sx > 0.6 and not S.sHeld then dir = 1 end
  if sx < -0.6 and not S.sHeld then dir = -1 end
  if math.abs(sx) > 0.6 then S.sHeld = true elseif math.abs(sx) < 0.3 then S.sHeld = false end
  local shot = input("MainShot") > 0.5
  if shot and not S.shotHeld then dir = 1 end
  S.shotHeld = shot
  if pressed(S.KEY_NEXT) then dir = 1 end
  if pressed(S.KEY_PREV) then dir = -1 end
  if pressed(S.KEY_FIRE) then dir = 1 end
  if pressed(S.KEY_D) then dir = 1 end
  if pressed(S.KEY_A) then dir = -1 end
  return dir
end

function S.caption(list)
  if not S.target then return end
  Coop.textBlock("CoopSpectate", string.format(S.text("watch"), S.label(S.target)),
    {y = 392, color = Color(235, 235, 235, 255)})
  Coop.textBlock("CoopSpectateHint", S.text(#list > 1 and "multi" or "one"),
    {y = 420, color = Color(190, 200, 215, 255), width = 600})
end

-- 20 Hz. Returns true when the spectator camera handles the downed player (the caller then
-- leaves MainCam alone), false for the old way.
function S.update()
  if Coop.cfg.spectate == false or not Game.GetCam then return false end
  local usr = Game.UsrEntity(0)
  if CoopSplit and CoopSplit.on then
    if S.active then S.leave("split screen") end
    return false
  end
  local want = S.wanted(usr)
  if not want then
    if S.active then
      S.leave((usr and (usr.Life or 0) > 0) and "up again" or "no longer down")
      if usr and (usr.Life or 0) > 0 and CoopTeam then CoopTeam.down = false end
    end
    return false
  end
  local scene = (Scene and Scene.IsPlaying) or (CoopEnemies and (CoopEnemies.fpBlackT or CoopEnemies.curtain))
  local list = S.list(usr)
  if #list == 0 then
    -- nobody to watch (the host's wipe check ends the game): the normal camera
    if S.active then S.leave("nobody alive") end
    return false
  end
  if scene then
    if S.active then S.leave("scene") end
    return true
  end
  if not S.active then S.enter(usr, list) end
  -- The watched body died or left: the nearest living one takes over.
  local ok = false
  for _, v in ipairs(list) do if v.name == S.target then ok = true end end
  if not ok then
    local last = S.anchor or usr.Pos
    local best, bd
    for _, v in ipairs(list) do
      local e = Game.GetEntity(v.name)
      local d = e and len(sub(e.Pos, last))
      if d and (not bd or d < bd) then best, bd = v.name, d end
    end
    local dead = S.target
    S.select(best, (dead or "?") .. " died or left")
  end
  -- (not while a menu / the ESC screen is open: a click there is no switch; one switch per SWITCH_GAP)
  local okm, set = pcall(function() return Input.GetActionSet and Input.GetActionSet() end)
  if okm and set == "Menu" then
    S.prime()
  else
    local dir = switchDir()
    local t = Net.CoopTime()
    if dir ~= 0 and t - (S.switchT or -100) >= S.SWITCH_GAP then
      S.switchT = t
      S.step(list, dir)
    end
  end
  S.caption(list)
  S.n = (S.n or 0) + 1
  if S.n % 100 == 1 then
    Coop.log(string.format("spectate: %s yaw=%.0f el=%.0f cam blocked %d", tostring(S.target), S.yaw or 0, S.el or 0, S.blocked or 0))
  end
  return true
end

-- The watched body gets no nameplate (its nickname is the caption).
function S.watched(name)
  return S.active and S.target == name
end

Coop.addLangs(S.TEXT, "CoopSpectate.TEXT")
