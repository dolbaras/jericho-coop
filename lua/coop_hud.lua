-- Jericho co-op: nameplates above other players' characters.
-- Each frame, every body another human controls gets a text item at the screen position
-- of its head (Scorer.Get2DPos projects a world point into the 640x480 HUD space).
-- Players can turn plates off in the lobby (COOP_CFG.tags = false).

CoopHud = {}
local H = CoopHud
H.HEAD = 195            -- units above the body origin (no head bone)
H.ABOVE_HEAD = 30       -- units above the head bone
H.MAX_DIST = 8000       -- hide plates farther than this
H.items = {}
H.POWER_CAMS = {AstralCam = true, RawlingsHealtyCam = true}

-- Peer id -> nickname, from the lobby seats ("peer:char:ready:nick;...").
function H.nicks()
  local t = {}
  for peer, nick in string.gmatch(Coop.cfg.seats or "", "(%d+):%a+:%d:([^;]*)") do
    t[tonumber(peer)] = nick
  end
  return t
end

function H.label(name)
  local peer = Coop.ownerOf(name)
  local nick = H.nickCache and peer and H.nickCache[peer]
  if nick and nick ~= "" then return nick end
  return Coop.charName(name)
end

local function cameraForward()
  local cam = Game.GetEntity(Game.GetCam(0))
  if not cam or not cam.camPos or not cam.camAng then return nil end
  return cam.camPos, V3D(0, 0, 10000):rot(cam.camAng)
end

-- A world point on the 640x480 HUD of a camera (by entity name), or nil behind it. Its own
-- maths instead of Scorer.Get2DPos (the camera being drawn) for split screen, where each
-- user's HUD needs its own camera; vertical scale: CameraViewScaleY (split.c draws each half
-- with 2). H.FOV_IS_H: whether the camera's Fov is horizontal (dev 'projtest' checks it).
H.FOV_IS_H = true
H.FWD = 1   -- the camera looks along +Z (1) or -Z (-1) of its rotation
function H.project(camName, p)
  local cam = Game.GetEntity(camName)
  if not cam or not cam.camPos or not cam.camAng then return nil end
  local a = cam.camAng
  local fwd, right, up = V3D(0, 0, H.FWD):rot(a), V3D(H.FWD, 0, 0):rot(a), V3D(0, 1, 0):rot(a)
  local d = p - cam.camPos
  local z = d.x * fwd.x + d.y * fwd.y + d.z * fwd.z
  if z <= 1 then return nil end
  local x = d.x * right.x + d.y * right.y + d.z * right.z
  local y = d.x * up.x + d.y * up.y + d.z * up.z
  local fov = cam.Fov or 1.309   -- radians
  -- The HUD's 640x480 maps the camera with the logical aspect (dev 'projtest': x matches
  -- Scorer.Get2DPos exactly with a horizontal Fov in radians, y with this aspect).
  local aspect = tonumber(Game.Get("CameraDefViewAspect")) or (4 / 3)
  local th = math.tan(fov / 2)
  local tw, tv
  if H.FOV_IS_H then tw, tv = th, th / aspect else tv, tw = th, th * aspect end
  tv = tv / (tonumber(Game.Get("CameraViewScaleY")) or 1)
  tw = tw / (tonumber(Game.Get("CameraViewScaleX")) or 1)
  return 320 + 320 * x / (z * tw), 240 - 240 * y / (z * tv)
end

-- Just above the body's head bone (the plate then follows crouching, agony...), else a
-- fixed height over the body.
function H.headPos(e)
  local bone = e.Name == "Rawlings" and "Bip Rawllings Head" or ("Bip " .. e.Name .. " Head")
  local p = e["NodePosHierarchy_" .. bone]
  if p and p.y then return p + V3D(0, H.ABOVE_HEAD, 0) end
  return e.Pos + V3D(0, H.HEAD, 0)
end

-- One plate per body and HUD (scorer 0; in split screen also scorer 1, player 2's half).
function H.item(name, id)
  id = id or 0
  local key = "CoopTag_" .. name
  local it = Scorer.GetItem(id, key)
  if not it then
    it = Scorer.NewItem(id, key, "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(230, 230, 230, 255)
    it.Effect = "Shadow"
    it.Visible = 0
  end
  return it
end

function H.hide(name)
  for id = 0, 1 do
    local it = Scorer.GetItem(id, "CoopTag_" .. name)
    if it then it.Visible = 0 end
  end
end

-- Bodies that get a plate on the HUD of user (0 or 1): other players' bodies, and in split
-- screen the other local player's.
function H.wants(name, user)
  local split = CoopSplit and CoopSplit.on
  if user == 0 and name == Coop.localChar() then return false end
  if user == 1 and split and name == CoopSplit.char then return false end
  if Coop.isRemoteOwned(name) then return true end
  if not split then return false end
  return (user == 0 and name == CoopSplit.char) or (user == 1 and name == Coop.localChar())
end

function H.place(it, name, x, y)
  -- Off the screen (a head above the view): no plate pinned to the edge.
  if x and y and x > 0 and x < 640 and y > 24 and y < 470 then
    it.Text = H.label(name)
    -- CentralText centres on the position it has when set (both ways, by the text's size).
    it.Pos = V2D(x, y - 4)
    it.CentralText = 1
    it.Visible = 1
  else
    it.Visible = 0
  end
end

function H.update()
  -- No nameplates over cutscenes (the bodies are hidden or stand-ins there), nor over the
  -- black before one (CoopEnemies: a scene start or a scene held for loading players).
  local black = CoopEnemies and (CoopEnemies.fpBlackT or CoopEnemies.curtain)
  -- Nor over a menu (pause, help): the world goes on behind it in a session.
  local menu = Input.GetActionSet and Input.GetActionSet() == "Menu"
  if Coop.cfg.tags == false or Coop.level == "levels/menu" or (Scene and Scene.IsPlaying) or black or menu then
    for _, name in ipairs(Coop.SQUAD) do H.hide(name) end
    return
  end
  if not H.nickCache or Coop.frame % 20 == 0 then H.nickCache = H.nicks() end
  -- Split screen draws each user's HUD over its own camera: the projection is done per
  -- camera here (Scorer.Get2DPos follows the camera being drawn, which alternates).
  local split = CoopSplit and CoopSplit.on and not CoopSplit.held
  for _, name in ipairs(Coop.SQUAD) do
    local e = Coop.squadEnt(name)
    for _, user in ipairs({0, 1}) do
      local shown = false
      -- (no plates over a power's own view: astral projection, Rawlings's healing flight)
      local ucam = CoopSplit and CoopSplit.camOf and CoopSplit.camOf(user) or Game.GetCam(user)
      local powerView = H.POWER_CAMS[ucam or ""]
      if e and e.Life > 0 and (user == 0 or split) and not powerView and H.wants(name, user) then
        local head = H.headPos(e)
        local cam = CoopSplit and CoopSplit.camOf and CoopSplit.camOf(user) or Game.GetCam(user)
        local camE = cam and Game.GetEntity(cam)
        local d = camE and camE.camPos and (head - camE.camPos)
        local dist = d and math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
        if dist and dist < H.MAX_DIST then
          local x, y
          if split then
            -- Full view (coop_split.lua): split.c draws each HUD over its picture only, so
            -- the HUD space is the picture's, as on the whole screen.
            x, y = H.project(cam, head)
            -- The HUD's corners are drawn out on the black sides (split.c): no plate there.
            if x and y and not CoopSplit.wide() and (x < 140 or x > 500) and (y < 110 or y > 330) then x = nil end
          else
            local camPos, fwd = cameraForward()
            local dd = head - camPos
            if dd.x * fwd.x + dd.y * fwd.y + dd.z * fwd.z > 0 then x, y = Scorer.Get2DPos(head) end
          end
          H.place(H.item(name, user), name, x, y)
          shown = true
        end
      end
      if not shown then
        local it = Scorer.GetItem(user, "CoopTag_" .. name)
        if it then it.Visible = 0 end
      end
    end
  end
end
