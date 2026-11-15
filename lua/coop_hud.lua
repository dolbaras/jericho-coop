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

-- Owner id -> nickname as this screen shows it (Coop.nickShow: the seats carry UTF-8), from the
-- lobby seats ("peer:char:ready:nick;..."); "" for a seat without one.
function H.nicks()
  local t = {}
  for peer, nick in string.gmatch(Coop.cfg.seats or "", "(%d+):%a+:%d:([^;]*)") do
    t[tonumber(peer)] = Coop.nickShow(nick)
  end
  return t
end

-- A body's plate: its player's nickname; a seat without one is named as the lobby and the choice
-- cards name it (Host, Player 2, in this machine's language); no seat (a test session): the
-- character.
function H.label(name)
  local peer = Coop.ownerOf(name)
  local nick = H.nickCache and peer and H.nickCache[peer]
  if nick and nick ~= "" then return nick end
  if nick == "" and CoopChoice and CoopChoice.playerName then return CoopChoice.playerName(peer) end
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

-- A plate's place on a split screen player's HUD (x, y from H.project). split.c draws each
-- player's HUD in the middle of the half with the whole screen's shape (fit_vp, both views):
-- over the whole picture in the "whole" view, but over the middle half of a filled half's
-- picture, which is twice as wide (the screen's width at half its height): there x is twice as
-- far from the middle. The HUD's corners are drawn out at the screen's edges (hud_edges, both
-- views): no plate there. (Up to 0.3.0 a filled view had neither: plates sat halfway to the
-- middle, INFERRED from the code, not seen; the filled view was then the 21:9 one only.)
-- cfg.splittagx = false: as before.
function H.splitPlace(x, y)
  if not x or not y then return nil, y end
  local filled = CoopSplit.wide()
  if filled then
    if Coop.cfg.splittagx == false then return x, y end
    x = 320 + (x - 320) * 2
  end
  if (x < 140 or x > 500) and (y < 110 or y > 330) then return nil, y end
  return x, y
end

-- Just above the body's head bone (the plate then follows crouching, agony...), else a
-- fixed height over the body. A missing bone is an engine error on every read, so a body
-- without one is remembered.
H.BONE = {Rawlings = "Bip Rawllings Head", CoopRossBody = "Bip Ross Head"}
H.noHead = {}
function H.headPos(e)
  local key = tostring(Coop.level) .. ":" .. e.Name
  if not H.noHead[key] then
    local p = e["NodePosHierarchy_" .. (H.BONE[e.Name] or ("Bip " .. e.Name .. " Head"))]
    if p and p.y then return p + V3D(0, H.ABOVE_HEAD, 0) end
    H.noHead[key] = true
  end
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
    it = Scorer.GetItem(id, "CoopEdge_" .. name)
    if it then it.Visible = 0 end
  end
end

------------------------------------------------------------------------------
-- Off-screen partners (0.3.4, sync checklist row 5, gap G-A5; owner's idea 2026-11-08, docs/coop-ux-research.md 5.9).
-- Jericho has no map: a partner whose plate is off the view (behind, beside, above) gets a marker at the side of the view
-- he is on, per HUD (each split screen half its own): "< Nick 25 m" on the left, "Nick 25 m >" on the right, at the height
-- the head would be (kept in the middle band, clear of the game's HUD corners). Hidden with the plates (scenes, black,
-- menus, power views, cfg.tags = false); cfg.edges = false: none.
------------------------------------------------------------------------------
H.EDGE_X = {full = {28, 612}, split = {150, 490}}   -- HUD x of the markers (split: inside the corner rule of H.splitPlace)
H.EDGE_Y = {150, 330}

-- Which side of the camera `camName` the point p is on: -1 left, 1 right; and the HUD y it would have (nil: no camera).
function H.side(camName, p)
  local cam = Game.GetEntity(camName)
  if not cam or not cam.camPos or not cam.camAng then return nil end
  local a = cam.camAng
  local fwd, right, up = V3D(0, 0, H.FWD):rot(a), V3D(H.FWD, 0, 0):rot(a), V3D(0, 1, 0):rot(a)
  local d = p - cam.camPos
  local z = d.x * fwd.x + d.y * fwd.y + d.z * fwd.z
  local x = d.x * right.x + d.y * right.y + d.z * right.z
  local y = d.x * up.x + d.y * up.y + d.z * up.z
  local side = x < 0 and -1 or 1
  -- (behind the camera with no sideways part: the nearer turn, to the right)
  local flat = math.sqrt(x * x + z * z)
  local hy = 240 - 240 * y / math.max(flat, 1)
  return side, hy
end

function H.edge(user, name, e, cam, dist)
  local it = Scorer.GetItem(user, "CoopEdge_" .. name)
  if Coop.cfg.edges == false or not cam then
    if it then it.Visible = 0 end
    return
  end
  local side, hy = H.side(cam, H.headPos(e))
  if not side then
    if it then it.Visible = 0 end
    return
  end
  if not it then
    it = Scorer.NewItem(user, "CoopEdge_" .. name, "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(230, 230, 230, 230)
    it.Effect = "Shadow"
  end
  local m = string.format("%d m", math.floor(dist / 100 + 0.5))
  local label = H.label(name)
  local xs = (CoopSplit and CoopSplit.on and not CoopSplit.held) and H.EDGE_X.split or H.EDGE_X.full
  it.Text = side < 0 and ("< " .. label .. " " .. m) or (label .. " " .. m .. " >")
  it.Align = side < 0 and "Left" or "Right"
  it.CentralText = 0
  it.Pos = V2D(side < 0 and xs[1] or xs[2], math.max(H.EDGE_Y[1], math.min(H.EDGE_Y[2], hy or 240)))
  it.Visible = 1
end

-- The squad, and in act 1 Ross (a player may hold him; audit 0.2.2 A11).
function H.names()
  if not (Coop.actOne and Coop.actOne()) then return Coop.SQUAD end
  if not H.withRoss then
    H.withRoss = {}
    for i, n in ipairs(Coop.SQUAD) do H.withRoss[i] = n end
    H.withRoss[#H.withRoss + 1] = "Ross"
  end
  return H.withRoss
end

-- The body a plate goes over: Ross's stand-in where it shows him (coop_ross.lua; his own
-- entity is off or unseen there), else the body itself.
function H.bodyOf(name)
  local e = Coop.squadEnt(name)
  if name ~= "Ross" or not e or (e.Life or 0) <= 0 then return e end
  local s = CoopRoss and CoopRoss.body and CoopRoss.body()
  if s and CoopRoss.showable() then return s end
  return e
end

-- Bodies that get a plate on the HUD of user (0 or 1): other players' bodies, and in split
-- screen the other local player's.
function H.wants(name, user)
  local split = CoopSplit and CoopSplit.on
  if user == 0 and name == Coop.localChar() then return false end
  -- (the player being watched by a downed one: the nickname is the spectator's caption)
  if user == 0 and CoopSpectate and CoopSpectate.watched(name) then return false end
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
  if CoopChoice and CoopChoice.scr then black = true end   -- (the squad choice screen is up)
  if Coop.cfg.tags == false or Coop.level == "levels/menu" or (Scene and Scene.IsPlaying) or black or menu then
    for _, name in ipairs(H.names()) do H.hide(name) end
    return
  end
  if not H.nickCache or Coop.frame % 20 == 0 then H.nickCache = H.nicks() end
  -- Split screen draws each user's HUD over its own camera: the projection is done per
  -- camera here (Scorer.Get2DPos follows the camera being drawn, which alternates).
  local split = CoopSplit and CoopSplit.on and not CoopSplit.held
  for _, name in ipairs(H.names()) do
    local e = H.bodyOf(name)
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
            x, y = H.splitPlace(H.project(cam, head))
          else
            local camPos, fwd = cameraForward()
            local dd = head - camPos
            if dd.x * fwd.x + dd.y * fwd.y + dd.z * fwd.z > 0 then x, y = Scorer.Get2DPos(head) end
          end
          local it = H.item(name, user)
          H.place(it, name, x, y)
          shown = true
          -- (0.3.4) the plate is off the view: the marker at its side instead
          if it.Visible == 1 then
            local edge = Scorer.GetItem(user, "CoopEdge_" .. name)
            if edge then edge.Visible = 0 end
          else
            H.edge(user, name, e, cam, dist)
          end
        end
      end
      if not shown then
        local it = Scorer.GetItem(user, "CoopTag_" .. name)
        if it then it.Visible = 0 end
        it = Scorer.GetItem(user, "CoopEdge_" .. name)
        if it then it.Visible = 0 end
      end
    end
  end
end
