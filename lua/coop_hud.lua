-- Jericho co-op: nameplates above other players' characters.
-- Each frame, every body another human controls gets a text item at the screen position
-- of its head (Scorer.Get2DPos projects a world point into the 640x480 HUD space).
-- Players can turn plates off in the lobby (COOP_CFG.tags = false).

CoopHud = {}
local H = CoopHud
H.HEAD = 195            -- units above the body origin
H.MAX_DIST = 8000       -- hide plates farther than this
H.items = {}

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
  return name
end

local function cameraForward()
  local cam = Game.GetEntity(Game.GetCam(0))
  if not cam or not cam.camPos or not cam.camAng then return nil end
  return cam.camPos, V3D(0, 0, 10000):rot(cam.camAng)
end

function H.item(name)
  local id = "CoopTag_" .. name
  local it = Scorer.GetItem(0, id)
  if not it then
    it = Scorer.NewItem(0, id, "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(230, 230, 230, 255)
    it.Effect = "Shadow"
    it.Visible = 0
  end
  return it
end

function H.hide(name)
  local it = Scorer.GetItem(0, "CoopTag_" .. name)
  if it then it.Visible = 0 end
end

function H.update()
  -- No nameplates over cutscenes (the bodies are hidden or stand-ins there), nor over the
  -- black before one (CoopEnemies: a scene start or a scene held for loading players).
  local black = CoopEnemies and (CoopEnemies.fpBlackT or CoopEnemies.curtain)
  if Coop.cfg.tags == false or Coop.level == "levels/menu" or (Scene and Scene.IsPlaying) or black then
    for _, name in ipairs(Coop.SQUAD) do H.hide(name) end
    return
  end
  if not H.nickCache or Coop.frame % 20 == 0 then H.nickCache = H.nicks() end
  local camPos, fwd = cameraForward()
  for _, name in ipairs(Coop.SQUAD) do
    local e = Game.GetEntity(name)
    if e and e.Life > 0 and Coop.isRemoteOwned(name) and camPos then
      local head = e.Pos + V3D(0, H.HEAD, 0)
      local d = head - camPos
      local dist = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
      local inFront = d.x * fwd.x + d.y * fwd.y + d.z * fwd.z > 0
      local it = H.item(name)
      if inFront and dist < H.MAX_DIST then
        local x, y = Scorer.Get2DPos(head)
        if x and y then
          it.Text = H.label(name)
          it.CentralText = 1
          it.Pos = V2D(x, y - 12)
          it.Visible = 1
        else
          it.Visible = 0
        end
      else
        it.Visible = 0
      end
    else
      H.hide(name)
    end
  end
end
