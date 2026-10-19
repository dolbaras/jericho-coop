-- Jericho co-op: the spirit role (docs/coop-story-extensions.md, owner's choice). A player
-- with no body in the level (their character is not loaded, captured, switched off by the
-- story, or there are more players than bodies) flies as an echo of Ross's spirit:
--   * free flight, steered like Black's ghost bullet (scripts/thread/threadsblack.lua: the
--     body ignores the player's input while Input.GetInputState("Walk", ...) still reads it),
--     kept inside the level (no flying through walls) and within RADIUS of the squad;
--   * F marks the enemy the spirit looks at, for everyone (Jones' selection aura);
--   * E takes the nearest free squad body, with the squad's own "Ross enters" line.
-- (No square brackets in on-screen text: the engine treats "[...]" as markup.)
--   mark|<entity>    any -> host -> everyone
-- A story may run the spirit as a soul on a path instead (P.startSoul: Rawlings' soul in
-- wwii_pillboxes, coop_splits.lua G4): it starts at a given place, is leashed to the path's
-- points instead of the squad, shows the story's hint, and E belongs to the story.
-- Jones' AstralCam was tried first: the engine places it from its linked entity, and a
-- stale position left it outside the level's sectors (nothing but sky drawn).
CoopSpirit = {}
local P = CoopSpirit
P.CAM = "CoopSpiritCam"
P.RADIUS = 1000          -- how far from the nearest squad member the spirit may fly
P.LOW, P.HIGH = -100, 450   -- height band relative to that member
P.LOST_TIME = 1.5        -- seconds without a line of sight to the squad before going back
P.WALL_GAP = 40
P.HUD_ITEMS = {"Damage", "Ammo", "Selector", "TeamStatus", "Aim"}   -- Menu.ShowScorer
P.ENTER_DELAY = 3        -- seconds without a body before the spirit starts
P.SPEED = 500            -- units per second
P.TURN = 3               -- degrees per frame per unit of turn input (as the ghost bullet)
P.MARK_TIME = 8
P.MARK_COS = 0.97        -- the enemy must be within ~14 degrees of the view to be marked
P.KEY_MARK = 0x46        -- F
P.KEY_TAKE = 0x45        -- E
P.AURA = "EFFECT_RAGDOLL\183AURASELECT"
P.marks = {}             -- entity name -> time the mark ends

P.TEXT = {
  en = {hint = "SPIRIT:  F - mark enemy,  E - take a free body", none = "no free body"},
  ru = {hint = "ДУХ:  F - отметить врага,  E - занять свободное тело", none = "свободных тел нет"},
}

-- Why a player is a spirit here: one line when the spirit starts in a level where the story
-- leaves characters out (docs/coop-story-extensions.md G2, G5, G7, G12-G14).
P.STORY = {
  ["levels/alk_bunker_00"] = {
    en = "Only Ross and Rawlings go down to Muriel. The others guard the way in above.",
    ru = "К Мюриэль спускаются только Росс и Роулингс. Остальные охраняют вход наверху."},
  ["levels/wwii_vigil_inside"] = {
    en = "Only Cole, Church and Rawlings got into the Vigil. You follow them as an echo of Ross.",
    ru = "В Бдение вошли только Коул, Чёрч и Роулингс. Вы следуете за ними эхом Росса."},
  ["levels/cru_labyrinth"] = {
    en = "The bridge took Jones, Cole and Rawlings. The children have them now.",
    ru = "Мост забрал Джонса, Коула и Роулингса. Теперь они у детей."},
  ["levels/cru_sewers"] = {
    en = "Jones, Cole and Rawlings are lost. Their souls are somewhere below.",
    ru = "Джонс, Коул и Роулингс потеряны. Их души где-то внизу."},
  ["levels/cru_keep"] = {
    en = "Jones, Cole and Rawlings are still the children's captives.",
    ru = "Джонс, Коул и Роулингс всё ещё в плену у детей."},
  ["levels/cru_catacomb"] = {
    en = "Somewhere in these catacombs the children hold Jones, Cole and Rawlings.",
    ru = "Где-то в этих катакомбах дети держат Джонса, Коула и Роулингса."},
  ["levels/sum_ziggurat_01"] = {
    en = "Jones is possessed. Fight for his body: stay with the squad.",
    ru = "Джонс одержим. Боритесь за его тело: держитесь рядом с отрядом."},
  ["levels/sum_ziggurat_02"] = {
    en = "The vortex scattered the squad. Search with Black.",
    ru = "Вихрь раскидал отряд. Ищите вместе с Блэком."},
  ["levels/sum_ziggurat_03"] = {
    en = "Delgado and Rawlings are still lost in the vortex.",
    ru = "Дельгадо и Роулингс всё ещё потеряны в вихре."},
  ["levels/sum_ziggurat_04"] = {
    en = "Cole and Church are hidden by the vortex until the end of the ziggurat.",
    ru = "Коул и Чёрч скрыты вихрем до конца зиккурата."},
}

function P.storyLine()
  local t = P.STORY[Coop.level]
  if not t then return nil end
  local lang = Coop.lang()
  local s = t[lang] or t.en
  return lang == "ru" and Coop.cp1251(s) or s
end

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

-- View direction from the spirit's yaw (entity convention) and elevation, in degrees.
local function forward()
  local y, e = math.rad(P.yaw), math.rad(P.el)
  return V3D(-math.sin(y) * math.cos(e), math.sin(e), -math.cos(y) * math.cos(e))
end

-- Anchors the spirit stays near: the squad, or the closest point of a soul's path (the
-- polyline through its points, so the stretches between stations can be flown too).
function P.anchors()
  if not P.soul then return P.squad() end
  local pts, best, bd = P.soul.points, nil, nil
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local ab = b - a
    local l2 = ab.x * ab.x + ab.z * ab.z
    local t = 0
    if l2 > 0 then
      t = ((P.pos.x - a.x) * ab.x + (P.pos.z - a.z) * ab.z) / l2
      t = math.max(0, math.min(1, t))
    end
    local q = V3D(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t)
    local d = (P.pos.x - q.x) ^ 2 + (P.pos.z - q.z) ^ 2
    if not bd or d < bd then best, bd = q, d end
  end
  return {{Pos = best or pts[1]}}
end

function P.startSoul(def)
  P.soul = def
  if P.active then P.leave() end
  P.enter()
end

function P.endSoul()
  P.soul = nil
  if P.active then P.leave() end
end

function P.enter()
  local usr = Game.UsrEntity(0)
  if P.soul then
    local a, b = P.soul.points[1], P.soul.points[2] or P.soul.points[1]
    local d = b - a
    P.yaw, P.el = math.deg(math.atan2(-d.x, -d.z)), -5
    P.pos = a + V3D(0, 150, 0)
  else
    local squad = P.squad()
    local anchor = usr and usr.Pos and nearest(squad, usr.Pos) or squad[1]
    if not anchor then return end
    P.yaw, P.el = anchor.Ang.y, -10
    local f = forward()
    P.pos = anchor.Pos + V3D(-f.x * 150, 200, -f.z * 150)
  end
  local cam = Game.GetEntity(P.CAM) or Game.CreateEntity(P.CAM, "FCam")
  local main = Game.GetEntity("MainCam")
  if main and main.Fov then cam.Fov = main.Fov end
  P.prevCam = Game.GetCam(0)
  Game.SetCam(0, P.CAM)
  if usr then
    usr.IgnoreUsrControl = 1
    usr.InCtrl_Walk, usr.InCtrl_Str = 0, 0
  end
  -- FX.InitEffect loads the aura's particle model; loading it again while the first copy is
  -- still referenced asserts in the engine (objref.h "!Refs": client in cru_chapel, spirit
  -- on, TheRescue, spirit on again). Once per level is enough.
  if not P.fxReady and AstralCamera and AstralCamera.CreateEffects then
    P.fxReady = true
    pcall(AstralCamera.CreateEffects)
  end
  if not Coop.cfg.spiritnofx and EffectsFrame and EffectsFrame.Jones_Ini then pcall(EffectsFrame.Jones_Ini) end
  for _, n in ipairs(P.HUD_ITEMS) do
    local it = Scorer.GetItem(0, n)
    if it then it.Visible = 0 end
  end
  P.active = true
  P.keys = {}
  P.lastSeen, P.lostSince = P.pos, nil
  P.place(cam)
  local story = not P.soul and P.storyLine()
  if story and not P.storyShown then
    P.storyShown = true
    P.flash = {text = story, untilT = Net.CoopTime() + 10}
  end
  Coop.log("spirit: on" .. (P.soul and " (soul on a path)" or ""))
end

function P.leave()
  if not P.active then return end
  P.active = false
  if Game.GetCam(0) == P.CAM then Game.SetCam(0, "MainCam") end
  local usr = Game.UsrEntity(0)
  if usr then usr.IgnoreUsrControl = 0 end
  if EffectsFrame then
    if EffectsFrame.Jones_End then pcall(EffectsFrame.Jones_End) end
    if EffectsFrame.RT_Reset then pcall(EffectsFrame.RT_Reset) end
  end
  local it = Scorer.GetItem(0, "CoopSpirit")
  if it then it.Visible = 0 end
  for _, n in ipairs(P.HUD_ITEMS) do
    local h = Scorer.GetItem(0, n)
    if h then h.Visible = 1 end
  end
  Coop.log("spirit: off")
end

function P.place(cam)
  cam.Pos = P.pos
  if CoopScenes and CoopScenes.toFCam then
    cam.Ang = CoopScenes.toFCam(V3D(-P.el, P.yaw + 180, 0))
  end
end

local function input(action)
  local ok, v = pcall(Input.GetInputState, "Walk", action, 0)
  return ok and tonumber(v) or 0
end

-- Every frame: steer and move, never through a wall, never far from the squad.
function P.frame(dt)
  if not P.active then return end
  local cam = Game.GetEntity(P.CAM)
  if not cam then return end
  dt = math.min(dt or 0.033, 0.1)
  local k = dt * 30
  local turnX = input("TurnRight") - input("TurnLeft")
  local turnY = input("TurnUp") - input("TurnDown")
  if Coop.cfg.spiritauto then turnX, turnY = 0.3, 0 end   -- test autopilot
  if Game.Get("InvertCharAxisControl") ~= 0 then turnY = -turnY end
  P.yaw = P.yaw - turnX * P.TURN * k
  P.el = math.max(-80, math.min(80, P.el + turnY * P.TURN * 0.5 * k))
  local fwd = input("Forward") - input("Back")
  local str = input("StrafeRight") - input("StrafeLeft")
  if Coop.cfg.spiritauto then fwd = 0.5 end
  local f = forward()
  local right = V3D(-f.z, 0, f.x)
  local rl = math.sqrt(right.x * right.x + right.z * right.z)
  if rl > 0.001 then right = V3D(right.x / rl, 0, right.z / rl) end
  local step = V3D(f.x * fwd + right.x * str, f.y * fwd, f.z * fwd + right.z * str)
  local target = P.pos + V3D(step.x * P.SPEED * dt, step.y * P.SPEED * dt, step.z * P.SPEED * dt)
  local move = target - P.pos
  local len = math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
  if len > 0.5 then
    -- Keep a gap to walls: test a little beyond the step.
    local probe = P.pos + V3D(move.x / len * (len + P.WALL_GAP), move.y / len * (len + P.WALL_GAP), move.z / len * (len + P.WALL_GAP))
    if not Game.TestLine(P.pos, probe, "") then P.pos = target end
  end
  local e = nearest(P.anchors(), P.pos)
  local radius = P.soul and P.soul.radius or P.RADIUS
  if e then
    local v = P.pos - e.Pos
    local h = math.sqrt(v.x * v.x + v.z * v.z)
    if h > radius then
      local s = radius / h
      P.pos = V3D(e.Pos.x + v.x * s, P.pos.y, e.Pos.z + v.z * s)
    end
    P.pos = V3D(P.pos.x, math.max(e.Pos.y + P.LOW, math.min(e.Pos.y + P.HIGH, P.pos.y)), P.pos.z)
    -- Stay where the squad can be seen: open courtyards and single-sided walls would
    -- otherwise let the spirit leave the playable space.
    local head = e.Pos + V3D(0, 150, 0)
    if not P.soul and Game.TestLine(P.pos, head, "") then
      P.lostSince = P.lostSince or Net.CoopTime()
      if Net.CoopTime() - P.lostSince > P.LOST_TIME and P.lastSeen then
        P.pos = P.lastSeen
        P.lostSince = nil
      end
    else
      P.lostSince = nil
      P.lastSeen = P.pos
    end
  end
  P.place(cam)
  if Game.GetCam(0) ~= P.CAM then Game.SetCam(0, P.CAM) end
end

function P.isEnemy(e)
  return e and e:IsType("WalkChar") and not Coop.SQUAD_SET[e.Name] and e.Name ~= "Ross"
    and e.TgType and e.TgType ~= "" and e.Life and e.Life > 0
end

-- The enemy closest to the centre of the spirit's view.
function P.lookedAtEnemy()
  local f = forward()
  local best, bestCos
  local e = Game.GetFirst()
  while e ~= nil do
    if P.isEnemy(e) then
      local v = (e.Pos + V3D(0, 120, 0)) - P.pos
      local d = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
      local c = d > 0 and (v.x * f.x + v.y * f.y + v.z * f.z) / d or 0
      if d < 6000 and c > P.MARK_COS and (not bestCos or c > bestCos) then best, bestCos = e, c end
    end
    if e.NextInSlot == "" then break end
    e = Game.GetEntity(e.NextInSlot)
  end
  return best
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
    local e = Game.GetEntity(name)
    if now > t or not e or (e.Life or 0) <= 0 then
      pcall(FX.EndEffect, P.AURA, "CoopMark_" .. name)
      P.marks[name] = nil
    end
  end
end

-- Ask the host for the free squad body nearest to the spirit.
function P.takeBody()
  local free = {}
  for _, e in ipairs(P.squad()) do
    if Coop.ownerOf(e.Name) == nil then free[#free + 1] = e end
  end
  local e = nearest(free, P.pos)
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
  if Team and Team.SwitchSoldier then
    local usr = Game.UsrEntity(0)
    if usr and usr.Name ~= e.Name then pcall(Team.SwitchSoldier, usr.Name, e.Name) end
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
    it.Pos = V2D(320, 60)
  end
  local text = P.soul and P.soul.hint and P.soul.hint() or P.text("hint")
  if P.flash and Net.CoopTime() < P.flash.untilT then text = P.flash.text end
  it.Text = text
  it.CentralText = 1
  it.Visible = 1
end

local function pressed(vk)
  local down = Net.CoopKey ~= nil and Net.CoopKey(vk) == 1
  local was = P.keys[vk]
  P.keys[vk] = down
  return down and not was
end

-- 20 Hz: enter or leave, keys, HUD.
function P.update()
  P.updateMarks()
  if not Coop.inSession() or Coop.level == "levels/menu" or (Scene and Scene.IsPlaying) then
    if P.active then P.leave() end
    return
  end
  if P.soul then
    if not P.active then P.enter() end
  elseif P.bodiless() then
    P.since = P.since or Net.CoopTime()
    if not P.active and Net.CoopTime() - P.since > P.ENTER_DELAY then P.enter() end
  else
    P.since = nil
    if P.active then P.leave() end
  end
  if not P.active then return end
  if pressed(P.KEY_MARK) then
    local e = P.lookedAtEnemy()
    if e then P.mark(e.Name, true) end
  end
  if not P.soul and pressed(P.KEY_TAKE) then P.takeBody() end
  P.updateHud()
  P.n = (P.n or 0) + 1
  if P.n % 60 == 1 then
    Coop.log(string.format("spirit: at %s yaw=%.0f el=%.0f", Coop.v3(P.pos), P.yaw, P.el))
  end
end

function P.onMessage(peer, f)
  if f[1] ~= "mark" then return false end
  if Coop.isHost() then Net.CoopSend(-1, 1, "mark|" .. tostring(f[2])) end
  P.mark(f[2], false)
  return true
end
