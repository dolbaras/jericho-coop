-- Jericho co-op: the spirit role (docs/coop-story-extensions.md, owner's choice). A player
-- with no body in the level (their character is not loaded, captured, switched off by the
-- story, or there are more players than bodies) flies as an echo of Ross's spirit:
--   * free astral flight (Jones' AstralCam in free mode, the "Astral" action set), kept
--     within SPIRIT_RADIUS of the squad;
--   * GoTo (the power key) marks the enemy under the crosshair for everyone (Jones' aura);
--   * Return (the special key) takes the nearest free squad body, with the squad's own
--     "Ross enters" line, as the switch does in single player.
--   mark|<entity>    any -> host -> everyone
CoopSpirit = {}
local P = CoopSpirit
P.CAM = "CoopSpiritCam"
P.RADIUS = 1500          -- how far from the nearest squad member the spirit may fly
P.ENTER_DELAY = 3        -- seconds without a body before the spirit starts
P.MARK_TIME = 8
P.AURA = "EFFECT_RAGDOLL\183AURASELECT"
P.marks = {}             -- entity name -> time the mark ends

P.TEXT = {
  en = {hint = "SPIRIT  -  [%s] mark enemy   [%s] take a free body", none = "no free body"},
  ru = {hint = "ДУХ  -  [%s] отметить врага   [%s] занять свободное тело", none = "свободных тел нет"},
}

function P.text(key)
  local lang = Coop.lang()
  local s = (P.TEXT[lang] or P.TEXT.en)[key]
  return lang == "ru" and Coop.cp1251(s) or s
end

-- True when the local player owns no usable body.
function P.bodiless()
  local me = Coop.myId()
  for name, peer in pairs(Coop.owners) do
    if peer == me then
      local e = Game.GetEntity(name)
      if e and e.Active ~= 0 and e.bActive ~= false then return false end
    end
  end
  return true
end

function P.squad()
  local list = {}
  for _, name in ipairs(Coop.SQUAD) do
    local e = Game.GetEntity(name)
    if e and e.Active ~= 0 and e.bActive ~= false and e.Life and e.Life > 0 then list[#list + 1] = e end
  end
  return list
end

local function dist(a, b)
  local d = a - b
  return math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
end

local function nearest(list, pos)
  local best, bd
  for _, e in ipairs(list) do
    local d = dist(e.Pos, pos)
    if not bd or d < bd then best, bd = e, d end
  end
  return best, bd
end

function P.enter()
  local squad = P.squad()
  local cam0 = Game.GetEntity(Game.GetCam(0))
  local from = cam0 and cam0.camPos or (squad[1] and squad[1].Pos)
  local anchor = from and nearest(squad, from)
  if not anchor then return end
  if AstralCamera and AstralCamera.CreateEffects then pcall(AstralCamera.CreateEffects) end
  local cam = Game.GetEntity(P.CAM) or Game.CreateEntity(P.CAM, "AstralCam")
  cam:Reset()
  cam.Pos = from + V3D(0, 40, 0)
  cam.bUseTurbo = true
  cam:SetOwner(anchor.Name)
  cam:LinkToEntity(anchor.Name)
  cam:SetFree()
  cam.OnChangeSelectedEntity = "CoopSpirit.onSelect"
  P.prevCam = Game.GetCam(0)
  Game.SetCam(0, P.CAM)
  P.prevSet = Input.GetActionSet()
  Input.SetActionSet("Astral")
  if EffectsFrame and EffectsFrame.Jones_Ini then pcall(EffectsFrame.Jones_Ini) end
  P.active = true
  P.keys = {}
  Coop.log("spirit: on (anchor " .. anchor.Name .. ")")
end

function P.leave()
  if not P.active then return end
  P.active = false
  if Game.GetCam(0) == P.CAM then Game.SetCam(0, "MainCam") end
  Input.SetActionSet("Walk")
  if EffectsFrame then
    if EffectsFrame.Jones_End then pcall(EffectsFrame.Jones_End) end
    if EffectsFrame.RT_Reset then pcall(EffectsFrame.RT_Reset) end
  end
  local it = Scorer.GetItem(0, "CoopSpirit")
  if it then it.Visible = 0 end
  Coop.log("spirit: off")
end

function P.onSelect(last, new)
  P.selected = new
end

-- Edge-triggered key press in the Astral action set.
function P.pressed(action)
  local down = (Input.GetInputState("Astral", action, 0) or 0) > 0.5
  local was = P.keys[action]
  P.keys[action] = down
  return down and not was
end

function P.isEnemy(e)
  return e and e:IsType("WalkChar") and e.TgType and e.TgType ~= "" and not Coop.SQUAD_SET[e.Name] and e.Life and e.Life > 0
end

function P.mark(name, send)
  local e = Game.GetEntity(name or "")
  if not e then return end
  if not P.marks[name] then pcall(FX.BeginEffect, P.AURA, "CoopMark_" .. name, name) end
  P.marks[name] = Net.CoopTime() + P.MARK_TIME
  if send then Net.CoopSend(-1, 1, "mark|" .. name) end
end

function P.updateMarks()
  local now = Net.CoopTime()
  for name, t in pairs(P.marks) do
    if now > t or not Game.GetEntity(name) or (Game.GetEntity(name).Life or 0) <= 0 then
      pcall(FX.EndEffect, P.AURA, "CoopMark_" .. name)
      P.marks[name] = nil
    end
  end
end

-- Ask the host for the free squad body nearest to the spirit.
function P.takeBody()
  local cam = Game.GetEntity(P.CAM)
  local free = {}
  for _, e in ipairs(P.squad()) do
    if Coop.ownerOf(e.Name) == nil then free[#free + 1] = e end
  end
  local e = cam and nearest(free, cam.Pos)
  if not e then
    P.flash = {text = P.text("none"), untilT = Net.CoopTime() + 2}
    return
  end
  Coop.log("spirit: claims " .. e.Name)
  if Coop.isHost() then
    Coop.owners[e.Name] = Coop.myId()
    Coop.broadcastOwners()
  else
    Net.CoopSend(0, 1, "claim|" .. e.Name)
  end
  if TeamTalk and TeamTalk.RadioTalk then pcall(TeamTalk.RadioTalk, e.Name, "Ross_Enters", "Talk") end
end

function P.updateHud()
  local it = Scorer.GetItem(0, "CoopSpirit")
  if not it then
    it = Scorer.NewItem(0, "CoopSpirit", "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(170, 200, 255, 255)
    it.Effect = "Shadow"
    it.Pos = V2D(320, 440)
  end
  local text = string.format(P.text("hint"), "F", "Q")
  if P.flash and Net.CoopTime() < P.flash.untilT then text = P.flash.text end
  it.Text = text
  it.CentralText = 1
  it.Visible = 1
end

-- Keep the spirit near the squad: past RADIUS from the nearest member it is pulled back.
function P.leash()
  local cam = Game.GetEntity(P.CAM)
  if not cam then return end
  local e, d = nearest(P.squad(), cam.Pos)
  if e and d > P.RADIUS then
    local k = P.RADIUS / d
    local v = cam.Pos - e.Pos
    cam.Pos = e.Pos + V3D(v.x * k, v.y * k, v.z * k)
  end
end

function P.update()
  P.updateMarks()
  if not Coop.inSession() or Coop.level == "levels/menu" or (Scene and Scene.IsPlaying) then
    if P.active then P.leave() end
    return
  end
  if P.bodiless() then
    P.since = P.since or Net.CoopTime()
    if not P.active and Net.CoopTime() - P.since > P.ENTER_DELAY then P.enter() end
  else
    P.since = nil
    if P.active then P.leave() end
  end
  if not P.active then return end
  if Game.GetCam(0) ~= P.CAM then Game.SetCam(0, P.CAM) end
  if Input.GetActionSet() ~= "Astral" then Input.SetActionSet("Astral") end
  P.leash()
  if P.pressed("GoTo") and P.selected then
    local e = Game.GetEntity(P.selected)
    if P.isEnemy(e) then P.mark(P.selected, true) end
  end
  if P.pressed("Return") then P.takeBody() end
  P.updateHud()
end

function P.onMessage(peer, f)
  if f[1] ~= "mark" then return false end
  if Coop.isHost() then Net.CoopSend(-1, 1, "mark|" .. tostring(f[2])) end
  P.mark(f[2], false)
  return true
end
