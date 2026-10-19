-- Jericho co-op: story splits (docs/coop-story-extensions.md, docs/story/*-splits.md).
-- Where the story sends one character on alone, the players whose characters stay behind
-- choose: take the character who goes on (if no human holds it), or stay and play their own
-- line. Lines built so far:
--   G8 cru_sewers "Hold the gate": Church climbs alone; Black and Delgado stay active below
--      and hold the jumpers' hall against waves (the level's own generators, re-armed) in
--      three phases that follow Church's progress, until Church opens the door.
--   G10 rom_caldarium "The Torturers' Hall": Delgado walks through the fire alone; the others
--      stay active and hold the pinned hall against cultists emerging from the blood pits.
--   G6 wwii_brandenburg "The gate top": Cole and Rawlings players stay active on the gate top
--      (vanilla props) and cover the squad; a leash keeps them up there until the sacrifice.
--   G3 alk_bunker_01 "Temporal restoration": a human Cole is the hacker; the restoration
--      advances while she stays at the console, the others defend her.
--   G15 sum_end "Break the blood link": players bound by the First Born's rune struggle free
--      (hold E) and fight on; the kill stays Church's.
--   G11 rom_palace_01 "Alone on the far side": after Church's crossing legionaries emerge on
--      his side; the others cover him from the edge; the plates work once the wave is down.
--
-- Messages:
--   spc|<split>|<target>     host -> all: choose (shown to the players the split leaves behind)
--   spn|<text key>|<chars>   host -> all: objective text for the players holding <chars>

CoopSplits = CoopSplits or {}
local Sp = CoopSplits
local cfg = Coop.cfg

Sp.TEXT = {
  en = {
    choose = "%s goes on alone.  1 - take %s,  2 - stay with your own (%d)",
    hold1 = "Hold the hall: the noise of the fight brings the Templars back.",
    hold2 = "Second wave! Hold until Church opens the door.",
    hold3 = "They come from below! Keep Church's way back open.",
    held = "The door is open. Church is back.",
    hall1 = "Cultists crawl out of the blood pits! Hold the hall until Delgado gets through.",
    hall2 = "More of them! Delgado is past the first door.",
    hall3 = "They keep coming. Delgado is close to the lever.",
    delgado_back = "Delgado is behind the door. Get ready.",
    abyss1 = "The legion door opens again! Cover Church from the edge.",
    abyss2 = "Church's side is clear. Stand on the plates.",
    struggle = "The blood link holds you. Hold E to break free (%d%%)",
    hack = "Cole restores the files: %d%%. Defend her!",
    hack_away = "Restoration paused at %d%%: Cole must be at the console.",
  },
  ru = {
    choose = "%s идёт дальше один.  1 - перейти в %s,  2 - остаться своим персонажем (%d)",
    hold1 = "Удерживайте зал: шум боя вернул тамплиеров.",
    hold2 = "Вторая волна! Держитесь, пока Чёрч не откроет дверь.",
    hold3 = "Они лезут снизу! Не дайте отрезать Чёрчу путь назад.",
    held = "Дверь открыта. Чёрч вернулся.",
    hall1 = "Культисты лезут из кровавых ям! Держите зал, пока Дельгадо идёт через огонь.",
    hall2 = "Их ещё больше! Дельгадо прошёл первую дверь.",
    hall3 = "Они не кончаются. Дельгадо уже у рычага.",
    delgado_back = "Дельгадо за дверью. Приготовьтесь.",
    abyss1 = "Дверь легиона снова открывается! Прикройте Чёрча с края.",
    abyss2 = "На стороне Чёрча чисто. Встаньте на плиты.",
    struggle = "Кровавая связь держит вас. Удерживайте E, чтобы вырваться (%d%%)",
    hack = "Коул восстанавливает файлы: %d%%. Защищайте её!",
    hack_away = "Восстановление стоит на %d%%: Коул должна быть у консоли.",
  },
}
Sp.CHOICE_TIME = 20

function Sp.text(key)
  local lang = Coop.lang()
  local s = (Sp.TEXT[lang] or Sp.TEXT.en)[key] or Sp.TEXT.en[key] or key
  return lang == "ru" and Coop.cp1251(s) or s
end

local function human(name)
  return CoopWorld and CoopWorld.isHuman(name)
end

------------------------------------------------------------------------------
-- Choice at a split (each machine for its own player)
------------------------------------------------------------------------------

Sp.SPLITS = {
  -- split id = {goes on, stays behind}
  G8 = {goes = "Church", stays = {Black = true, Delgado = true}},
  G10 = {goes = "Delgado", stays = {Black = true, Church = true, Cole = true, Jones = true, Rawlings = true}},
}

function Sp.offer(id)
  local s = Sp.SPLITS[id]
  local me = Coop.localChar()
  if not s or not me or not s.stays[me] then return end
  -- The character going on is free: offer it; otherwise there is nothing to choose.
  if Coop.ownerOf(s.goes) ~= nil and Coop.ownerOf(s.goes) ~= Coop.myId() then return end
  Sp.choice = {id = id, target = s.goes, untilT = Net.CoopTime() + Sp.CHOICE_TIME}
  Coop.log("split " .. id .. ": choose " .. s.goes .. " or stay")
end

function Sp.updateChoice()
  local c = Sp.choice
  local it = Scorer.GetItem(0, "CoopSplit")
  if not c then
    if it then it.Visible = 0 end
    return
  end
  local left = math.ceil(c.untilT - Net.CoopTime())
  local pick
  if Net.CoopKey(0x31) == 1 then pick = "take" elseif Net.CoopKey(0x32) == 1 or left <= 0 then pick = "stay" end
  if pick then
    Sp.choice = nil
    if it then it.Visible = 0 end
    Coop.log("split " .. c.id .. ": " .. pick)
    if pick == "take" and Team and Team.SwitchSoldier and Coop.ownerOf(c.target) == nil then
      Team.SwitchSoldier(Coop.localChar(), c.target)
    end
    return
  end
  if not it then
    it = Scorer.NewItem(0, "CoopSplit", "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(255, 220, 160, 255)
    it.Effect = "Shadow"
    it.Pos = V2D(320, 90)
  end
  it.Text = string.format(Sp.text("choose"), c.target, c.target, math.max(left, 0))
  it.CentralText = 1
  it.Visible = 1
end

------------------------------------------------------------------------------
-- Holds: the level's own enemy generators, re-armed (host)
------------------------------------------------------------------------------

Sp.rearmed = {}

-- Make generator group `name` spawn without end, `max` at a time, at its own spawn points.
function Sp.rearm(name, max)
  local g = NPC and NPC.Groups and NPC.Groups[name]
  if not g or not g.uData or not g.uData.spawnPoints then
    Coop.log("split: group " .. name .. " cannot be re-armed")
    return false
  end
  local el = Game.GetEntityList(name)
  if el then el.OnAllDeath = "" end   -- its story callback already ran
  g.uData.isInfinite = true
  g.uData.Stopped = false
  g.uData.wasActivated = true
  g.uData.maxSimultaneousEnemies = max
  Game.DeleteScheduledFuncs(name .. "ActivateNextEnemy")
  for _ = 1, max do EnemyGen.ScheduleActivationOfNextEnemy(name) end
  Sp.rearmed[name] = true
  Coop.log("split: " .. name .. " re-armed, " .. max .. " at a time")
  return true
end

function Sp.stopHolds()
  for name in pairs(Sp.rearmed) do
    pcall(EnemyGen.Stop, name, true)
  end
  Sp.rearmed = {}
end

-- Players below: how many humans hold the staying characters.
function Sp.humansIn(set)
  local n = 0
  for name in pairs(set) do if human(name) then n = n + 1 end end
  return n
end

function Sp.notice(key, chars)
  Net.CoopSend(-1, 1, "spn|" .. key .. "|" .. table.concat(chars, ","))
  Sp.showNotice(key, chars)
end

function Sp.showNotice(key, chars)
  local me = Coop.localChar()
  for _, c in ipairs(chars) do
    if c == me then
      Scorer.SetMsgText(Sp.text(key), Game.GetTime() + 8)
      return
    end
  end
end

function Sp.radio(char, category, n)
  if TeamTalk and TeamTalk.RadioTalk and Game.GetEntity(char) then
    pcall(TeamTalk.RadioTalk, char, category, "Talk", n)
  end
end

------------------------------------------------------------------------------
-- Hooks by name, after the original (host)
------------------------------------------------------------------------------

function Sp.after(path, fn)
  local tname, fname = string.match(path, "^([%w_]+)%.([%w_]+)$")
  local tbl = _G[tname]
  local f = tbl and tbl[fname]
  -- Once per name: the Lua state is rebuilt on every level load, and other modules wrap
  -- the same functions later (CoopWorld), so the function itself is not a reliable mark.
  if type(f) ~= "function" or Sp.hooked[path] then return end
  local orig = f
  local w = function(...)
    local r = {orig(...)}
    local ok, err = pcall(fn, ...)
    if not ok then Coop.log("split hook " .. path .. " error: " .. tostring(err)) end
    return unpack(r)
  end
  tbl[fname] = w
  Sp.hooked[path] = true
end
Sp.hooked = {}

------------------------------------------------------------------------------
-- G8 cru_sewers: "Hold the gate"
------------------------------------------------------------------------------

Sp.G8 = {stays = {Black = true, Delgado = true}, list = {"Black", "Delgado"}}

function Sp.G8phase(n)
  local g = Sp.G8
  local below = Sp.humansIn(g.stays)
  if below == 0 or g.phase == "done" then return end
  g.phase = n
  if Team and Team.ReviveAll then pcall(Team.ReviveAll) end
  Coop.log("split G8: phase " .. n .. ", " .. below .. " player(s) below")
  if n == 1 then
    Sp.rearm("Enemy_Generator_Jumpers", 1 + below)
    Sp.notice("hold1", g.list)
    Sp.radio("Black", "Enemy_Ambush")
  elseif n == 2 then
    Sp.rearm("Enemy_First", 1 + below)
    Sp.notice("hold2", g.list)
    Sp.radio("Delgado", "Under_Heavy_Fire")
  elseif n == 3 then
    Sp.rearm("Enemy_Generator_Jumpers", 2 + below)
    Sp.notice("hold3", g.list)
    Sp.radio("Black", "Help_Omega")
  end
end

function Sp.installG8(isHost)
  if not isHost then return end
  -- Church starts the climb (use object or area trigger): the choice, then phase 1 when
  -- the scene hands control back.
  local function climb()
    Net.CoopSend(-1, 1, "spc|G8")
    Sp.offer("G8")
    Game.AddScheduledFunc(Game.GetTime() + 12, "CoopSplitG8", "CoopSplits.G8phase", 1)
  end
  Sp.after("MapCallbacks.TriggerEscalada_0", climb)
  Sp.after("MapCallbacks.PlayEscalada", function(_, Playerid)
    if Scene and Scene.IsPlaying then climb() end
  end)
  -- Church enters the ward room: vanilla switches Black and Delgado off; human ones stay.
  Sp.after("MapCallbacks.TriggerBloodWar_3", function()
    for _, n in ipairs(Sp.G8.list) do
      local e = Game.GetEntity(n)
      if e and human(n) then e.bActive = true end
    end
    Sp.G8phase(2)
  end)
  Sp.after("MapCallbacks.BloodWarGroup_0", function() Sp.G8phase(3) end)
  Sp.after("MapCallbacks.TriggerAperturaPuerta_0", function()
    if Sp.G8.phase and Sp.G8.phase ~= "done" then
      Sp.G8.phase = "done"
      Sp.stopHolds()
      Sp.notice("held", Sp.G8.list)
      Coop.log("split G8: held")
    end
  end)
end

------------------------------------------------------------------------------
-- G10 rom_caldarium: "The Torturers' Hall" (docs/story/act45-splits.md section 3)
-- Delgado walks through the fire alone (vanilla, fire-proof). The others stay active in the
-- pinned hall (vanilla freezes them with Active = 0) and hold it against cultists emerging
-- from the blood pits, in waves tied to Delgado's route, until he drops down by the lever.
------------------------------------------------------------------------------

Sp.G10 = {stays = {Black = true, Church = true, Cole = true, Jones = true, Rawlings = true},
          list = {"Black", "Church", "Cole", "Jones", "Rawlings"}}
-- Hall spawn points of melee_emb_final (vanilla uses them only after the lever) and ke_putada.
Sp.G10.PITS = {V3D(-30527, -176, -5569), V3D(-30755, -159, -5557), V3D(-30502, -166, -5250)}
Sp.G10.FAR = V3D(-32276, 165, -5533)
Sp.G10.LIST = "Primer_cultista_torturador"   -- activated at the same step, no story callback

-- Vanilla freezes the five (fire exit, checkpoint loads); a body a human holds stays active.
-- Runs on every machine: clients replay the callback on their own copies.
function Sp.G10keepHumans()
  for _, n in ipairs(Sp.G10.list) do
    local e = Game.GetEntity(n)
    if e and human(n) then e.Active = 1 end
  end
end

function Sp.G10spawn(class, pos, n)
  for k = 1, n do
    local p = pos or Sp.G10.PITS[(k - 1) % #Sp.G10.PITS + 1]
    local ok, e = pcall(NPC.CreateWithAI, class, p.x + (k - 1) * 40, p.y, p.z, Sp.G10.LIST, 1)
    if ok and e then
      e.bActive = true
      e.ForceAction = "Emerge"
    else
      Coop.log("split G10: spawn " .. class .. " failed: " .. tostring(e))
    end
  end
end

function Sp.G10wave(n)
  local g = Sp.G10
  local hall = Sp.humansIn(g.stays)
  if hall == 0 or g.phase == "done" or (g.phase or 0) >= n then return end
  g.phase = n
  Coop.log("split G10: wave " .. n .. ", " .. hall .. " player(s) in the hall")
  if n == 1 then
    Sp.G10spawn("CultistaMelee", nil, 2 + hall)
    Sp.notice("hall1", g.list)
    Sp.radio("Black", "150_L4_Hot_Coals")
  elseif n == 2 then
    Sp.G10spawn("CultistaMelee", nil, 1 + hall)
    Sp.G10spawn("CultistaExplosivo", g.FAR, 1)
    Sp.notice("hall2", g.list)
    Sp.radio("Jones", "Enemy_Ambush")
  elseif n == 3 then
    Sp.G10spawn("CultistaMelee", nil, 2 + hall)
    Game.AddScheduledFunc(Game.GetTime() + 6, "CoopSplitG10", "CoopSplits.G10late")
    Sp.notice("hall3", g.list)
    Sp.radio("Rawlings", "Under_Heavy_Fire")
  end
end

function Sp.G10late()
  if Sp.G10.phase ~= "done" then
    Sp.G10spawn("CultistaMelee", nil, 1)
    Sp.G10spawn("CultistaExplosivo", Sp.G10.FAR, 1)
  end
end

function Sp.installG10(isHost)
  Sp.after("MapCallbacks.AreaTriggerOutFire_0", function()
    Sp.G10keepHumans()
    if isHost then Sp.G10wave(1) end
  end)
  Sp.after("MapInit.SetSoloMission", Sp.G10keepHumans)
  -- A checkpoint load runs SetSoloMission from the scheduler on the first frames, possibly
  -- before the hook above: undo it once shortly after the start.
  if not Sp.G10.loadChecked and Coop.frame > 40 then
    Sp.G10.loadChecked = true
    if Team and Team.GetSavedSpawnPlayerPoint and Team.GetSavedSpawnPlayerPoint() >= 1 then Sp.G10keepHumans() end
  end
  if not isHost then return end
  Sp.after("MapCallbacks.AreaTrigger_Fire_0", function()
    if not Sp.G10.offered then
      Sp.G10.offered = true
      Net.CoopSend(-1, 1, "spc|G10")
      Sp.offer("G10")
    end
  end)
  Sp.after("MapCallbacks.puerta_delgado_1_0", function() Sp.G10wave(2) end)
  Sp.after("MapCallbacks.AreaTrigger308_0", function() Sp.G10wave(3) end)
  Sp.after("MapCallbacks.AreaTriggerDelgadoCae_0", function()
    if Sp.G10.phase and Sp.G10.phase ~= "done" then
      Sp.G10.phase = "done"
      Sp.notice("delgado_back", Sp.G10.list)
      Sp.radio("Black", "161_L4_Lift_Door")
      Coop.log("split G10: Delgado is back")
    end
  end)
end

------------------------------------------------------------------------------
-- G11 rom_palace_01: "Alone on the Far Side" (docs/story/act45-splits.md section 4)
-- Church crosses the abyss alone (QTE). Then the legion door grinds open again and
-- legionaries emerge on Church's side; Church fights them by plate A, the others cover him
-- from the edge and Jones may shut the door again with the crank (re-armed). The plates
-- only work once the wave is down.
------------------------------------------------------------------------------

Sp.G11 = {all = {"Black", "Church", "Cole", "Delgado", "Jones", "Rawlings"}, spawned = {}}
Sp.G11.DOOR_SPAWNS = {V3D(-65454, -1272, 5891), V3D(-65454, -1272, 6058), V3D(-65454, -1272, 6224),
                      V3D(-65454, -1272, 6391)}
Sp.G11.LIST = "LegionariosPuente4"   -- its AI team exists; vanilla stops it before the crossing

function Sp.G11alive()
  for _, name in ipairs(Sp.G11.spawned) do
    local e = Game.GetEntity(name)
    if e and (e.Life or 0) > 0 then return true end
  end
  return false
end

function Sp.G11wave()
  local g = Sp.G11
  if g.started then return end
  g.started = true
  local n = math.min(6, 3 + (CoopEnemies and CoopEnemies.playerCount and CoopEnemies.playerCount() or 1))
  pcall(PhysicsObj.OpenDoor, "puertaPuzzlePuente")
  local crank = Game.GetEntity("ManivelaPuertaPuente")
  if crank then crank.bArrowCanUse = true end
  for k = 1, n do
    local p = g.DOOR_SPAWNS[(k - 1) % #g.DOOR_SPAWNS + 1]
    local ok, e = pcall(NPC.CreateWithAI, "Legionary", p.x - math.floor((k - 1) / 4) * 120, p.y, p.z, g.LIST, 1)
    if ok and e then
      e.bActive = true
      e.ForceAction = "Emerge"
      g.spawned[#g.spawned + 1] = e.Name
    else
      Coop.log("split G11: spawn failed: " .. tostring(e))
    end
  end
  Coop.log("split G11: " .. #g.spawned .. " legionaries on Church's side")
  Sp.notice("abyss1", g.all)
  Sp.radio("Black", "173_L4_Block_Legion")
  Sp.radio("Church", "Enemy_Ambush")
end

function Sp.G11check()
  local g = Sp.G11
  if g.started and not g.cleared and not Sp.G11alive() then
    g.cleared = true
    Sp.notice("abyss2", g.all)
    Sp.radio("Church", "Rejoin_Team")
    Coop.log("split G11: wave cleared, plates armed")
  end
end

function Sp.installG11(isHost)
  if not isHost then return end
  -- TheAbyss ended for good (a failed QTE replays it: wait until no scene plays).
  Sp.after("Scene.EndOfScene", function()
    if Scene.LastSceneName == "DM_Scene_TheAbyss" and not Sp.G11.started then
      Game.AddScheduledFunc(Game.GetTime() + 2, "CoopSplitG11", "CoopSplits.G11afterScene")
    end
  end)
  -- The plates open the bridge only when the wave is down.
  local press = MapCallbacks.PressChurch_0
  if press and not Sp.hooked["MapCallbacks.PressChurch_0/gate"] then
    Sp.hooked["MapCallbacks.PressChurch_0/gate"] = true
    MapCallbacks.PressChurch_0 = function(...)
      if Sp.G11.started and Sp.G11alive() then return end
      return press(...)
    end
  end
  if Coop.frame % 20 == 0 then Sp.G11check() end
end

function Sp.G11afterScene()
  if Scene and Scene.IsPlaying then
    Game.AddScheduledFunc(Game.GetTime() + 2, "CoopSplitG11", "CoopSplits.G11afterScene")
    return
  end
  Sp.G11wave()
end

------------------------------------------------------------------------------
-- G6 wwii_brandenburg: "The Gate Top" (docs/story/act2-splits.md section 4)
-- Cole and Rawlings hold the captive Lichthammer on top of the Brandenburg gate for the
-- whole level; vanilla keeps them there as inactive props until Church's sacrifice scene.
-- Players holding them stay active up there and cover the squad fighting to the gate; a
-- leash brings a body that falls off back to its place. AI-held ones stay vanilla props.
------------------------------------------------------------------------------

Sp.G6 = {chars = {"Cole", "Rawlings"},
         anchor = {Cole = V3D(-23505, 533, 66981), Rawlings = V3D(-23646, 533, 66995)},
         LEASH = 700}

function Sp.G6keepHumans()
  for _, n in ipairs(Sp.G6.chars) do
    local e = Game.GetEntity(n)
    if e and human(n) then
      e.bActive = true
      e.bIgnoreCollision = false
      if e.uData then e.uData.CannotSpeak = false end
    end
  end
end

-- The holder of Cole or Rawlings may take its body at level start (vanilla makes both
-- unavailable for switching; on this machine only the holder's own lock goes).
function Sp.G6takeSeat()
  local want = cfg.seatChar or cfg.char
  local me = Coop.localChar()
  if (want == "Cole" or want == "Rawlings") and me and me ~= want and Coop.ownerOf(want) == nil then
    if Team.UnavaliablePlayers then Team.UnavaliablePlayers[want] = nil end
    Coop.log("split G6: taking " .. want .. " on the gate top")
    Team.SwitchSoldier(me, want)
  end
end

-- Vanilla stages both as props in the sacrifice pose (ShowRawlingsCole / EnsureRawlingsCole):
-- only AI-held ones; the captive is always staged.
function Sp.G6stage(origShow, origEnsure)
  local anyHuman = human("Cole") or human("Rawlings")
  if not anyHuman then return false end
  local bitchie = Game.GetEntity("Bitchie")
  local offs = {Cole = V3D(57.78, 0, 28.49), Rawlings = V3D(-78.325, 0, 50.859)}
  for _, n in ipairs(Sp.G6.chars) do
    local e = Game.GetEntity(n)
    if e and not human(n) and bitchie then
      pcall(AITeamList.DeleteMember, e.oAI.Team, n)
      e.bIgnoreCollision = true
      e.Pos = bitchie.Pos + offs[n]
      e.bActive = true
      e.oAI.bEnable = false
      e.ForceAction = "NaziSacrifice"
      e.Ang = V3D(0, 0, 0)
      e.Invulnerable = 1
    end
  end
  if bitchie then
    bitchie.Pos = V3D(-23562.86, 532.48, 66947.56)
    bitchie.Ang = V3D(0, -3.87, 0)
    bitchie.ForceAction = "NaziSacrifice"
    bitchie.bIgnoreCollision = true
    bitchie.bActive = true
    bitchie.Invulnerable = 1
  end
  return true
end

-- Leash for this machine's own body while the gate-top line runs.
function Sp.G6leash()
  local me = Coop.localChar()
  local a = me and Sp.G6.anchor[me]
  if not a or Sp.G6.free or (Scene and Scene.IsPlaying) then return end
  local e = Game.GetEntity(me)
  if not e or (e.Life or 0) <= 0 then return end
  local d = e.Pos - a
  if math.sqrt(d.x * d.x + d.z * d.z) > Sp.G6.LEASH or d.y < -250 then
    e.Pos = a
    Game.SetOnFloor(me)
    Coop.log("split G6: " .. me .. " back on the gate top")
  end
end

function Sp.G6afterInit()
  if Sp.G6.initDone then return end
  Sp.G6.initDone = true
  Sp.G6keepHumans()
  Sp.G6takeSeat()
end

function Sp.installG6(isHost)
  -- MapInit.Init runs from the scheduler on the first frames, possibly before this hook;
  -- it sets MapInit.EBuck, so that tells whether it already ran.
  Sp.after("MapInit.Init", function() Sp.G6.initDone = false Sp.G6afterInit() end)
  if MapInit.EBuck ~= nil then Sp.G6afterInit() end
  if MapInit.ShowRawlingsCole and not Sp.hooked["G6stage"] then
    Sp.hooked["G6stage"] = true
    local origShow, origEnsure = MapInit.ShowRawlingsCole, MapInit.EnsureRawlingsCole
    MapInit.ShowRawlingsCole = function(...)
      if not Sp.G6stage() then return origShow(...) end
    end
    MapInit.EnsureRawlingsCole = function(...)
      if not Sp.G6stage() then return origEnsure(...) end
    end
  end
  -- The sacrifice scenes take over; afterwards ReposPeople gathers everyone (vanilla).
  Sp.after("MapInit.HideRawlingsCole", function() Sp.G6.free = true end)
  if Coop.frame % 10 == 0 then Sp.G6leash() end
end

------------------------------------------------------------------------------
-- G15 sum_end: "Break the blood link" (docs/story/act45-splits.md section 8)
-- In the final phase the First Born's blood rune binds Black, Delgado and Rawlings
-- (stunned, forever) and the kill is Church's. In co-op each bound player struggles: hold
-- the use key (E) for a few seconds to break the link and fight on; a new rune binds again.
-- The kill stays Church's (coop_story.lua resolves "the player is Church").
--   spstun|<char>   host -> all: <char> is bound (its holder struggles)
--   spfree|<char>   holder -> host -> all: <char> broke free
------------------------------------------------------------------------------

Sp.G15 = {bound = {"Black", "Delgado", "Rawlings"}, freed = {}, HOLD = 6, struggle = nil, told = {}}

function Sp.G15stun(e)
  e.oAI.bEnable = false
  if e.Action ~= "Stupid" and e.Action ~= "StupidInit" then e.ForceAction = "StupidInit" end
end

-- Host: vanilla re-applies the stun every 0.1 s; members who broke free are skipped until
-- the next rune, and each bound holder is told once per rune.
function Sp.G15schedule()
  local g = Sp.G15
  Team.UnavaliablePlayers = Team.UnavaliablePlayers or {}
  for _, n in ipairs(g.bound) do
    local e = Game.GetEntity(n)
    if e and not g.freed[n] then
      if not Coop.isRemoteOwned(n) then Sp.G15stun(e) end
      Team.UnavaliablePlayers[n] = true
      if human(n) and not g.told[n] then
        g.told[n] = true
        Net.CoopSend(-1, 1, "spstun|" .. n)
        Sp.G15onStun(n)
      end
    end
  end
  Game.AddScheduledFunc(Game.GetTime() + 0.1, "", "EvilFirstBorn.SchMakeAllUnavailable")
end

-- Any machine: its own bound body starts the struggle.
function Sp.G15onStun(n)
  if n ~= Coop.localChar() then return end
  local e = Game.GetEntity(n)
  if e then
    e.IgnoreUsrControl = 1
    Sp.G15stun(e)
  end
  Sp.G15.struggle = {char = n, held = 0}
  Coop.log("split G15: " .. n .. " is bound, struggle")
end

function Sp.G15onFree(n)
  Sp.G15.freed[n] = true
  if Team.UnavaliablePlayers then Team.UnavaliablePlayers[n] = nil end
  local e = Game.GetEntity(n)
  if e then e.ForceAction = "StupidEnd" end
  if n == Coop.localChar() and e then e.IgnoreUsrControl = 0 end
  Coop.log("split G15: " .. n .. " broke free")
  if Coop.isHost() then
    -- Fight the stolen powers: wake the First Born's helpers if the engine left them idle.
    for _, h in ipairs({"EvilAbabanili", "EGHBlack", "EGHChurch", "EGHDelgado"}) do
      local x = Game.GetEntity(h)
      if x and x.bActive == false and (x.Life or 0) > 0 then x.bActive = true end
    end
    Sp.radio(n, "Help_Church")
  end
end

function Sp.G15updateStruggle(dt)
  local s = Sp.G15.struggle
  local it = Scorer.GetItem(0, "CoopSplit")
  if not s then return end
  if Net.CoopKey(0x45) == 1 then s.held = s.held + dt end
  if s.held >= Sp.G15.HOLD then
    Sp.G15.struggle = nil
    if it then it.Visible = 0 end
    if Coop.isHost() then
      Net.CoopSend(-1, 1, "spfree|" .. s.char)
    else
      Net.CoopSend(0, 1, "spfree|" .. s.char)
    end
    Sp.G15onFree(s.char)
    return
  end
  if not it then
    it = Scorer.NewItem(0, "CoopSplit", "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(255, 120, 120, 255)
    it.Effect = "Shadow"
    it.Pos = V2D(320, 90)
  end
  it.Text = string.format(Sp.text("struggle"), math.floor(100 * s.held / Sp.G15.HOLD))
  it.CentralText = 1
  it.Visible = 1
end

function Sp.installG15(isHost)
  if not isHost or not EvilFirstBorn or Sp.hooked["G15"] then return end
  Sp.hooked["G15"] = true
  EvilFirstBorn.SchMakeAllUnavailable = function()
    if not Coop.inSession() then return Sp.G15schedule() end
    Sp.G15schedule()
  end
  -- A new rune binds everyone again.
  Sp.after("EvilFirstBorn.DoBloodRune", function()
    Sp.G15.freed, Sp.G15.told = {}, {}
  end)
end

------------------------------------------------------------------------------
-- G3 alk_bunker_01: "Temporal restoration" (docs/story/act1-splits.md G3)
-- Vanilla walks Cole to the console, swaps her for an invulnerable FakeCole playing the hack
-- and switches the real Cole off for a ~120 s ambush on timers. With a human Cole that
-- would make the player's body vanish (and QuakeOff/FinalTalk read the fake's alias). Now
-- the human Cole is the hacker: the restoration advances only while she stands at the
-- console, the progress (and Cole's vanilla lines) follow it, the others defend her.
--   spp|<percent>|<1 at console / 0>   host -> all
--   spchat|<chat>                      host -> all: play an incidental chat
------------------------------------------------------------------------------

Sp.G3 = {TIME = 120, RADIUS = 160,
         CHATS = {{20, "Mission_Alk_Bunker_01_ACombat"}, {40, "Mission_Alk_Bunker_01_BCombat"},
                  {60, "Mission_Alk_Bunker_01_CCombat"}, {80, "Mission_Alk_Bunker_01_DCombat"},
                  {100, "Mission_Alk_Bunker_01_ECombat"}}}

function Sp.chat(name)
  Net.CoopSend(-1, 1, "spchat|" .. name)
  pcall(TeamTalk.InitIncidentalChat, name, nil, false)
end

function Sp.G3start()
  local g = Sp.G3
  g.human, g.t, g.next, g.lastSent = true, 0, 1, -1
  g.hacking = true
  Coop.log("split G3: human Cole hacks the console")
end

function Sp.G3update(dt)
  local g = Sp.G3
  if not g.hacking then return end
  local cole = Game.GetEntity("Cole")
  if not cole then return end
  local d = cole.Pos - MapInit.ColePos
  local near = math.sqrt(d.x * d.x + d.z * d.z) < g.RADIUS and (cole.Life or 0) > 0
  if near then g.t = g.t + dt end
  local pct = math.min(100, math.floor(100 * g.t / g.TIME))
  local c = g.CHATS[g.next]
  if c and g.t >= g.TIME * c[1] / 120 then
    g.next = g.next + 1
    Sp.chat(c[2])
  end
  if pct ~= g.lastSent or near ~= g.lastNear then
    g.lastSent, g.lastNear = pct, near
    Net.CoopSend(-1, 0, "spp|" .. pct .. "|" .. (near and 1 or 0))
    Sp.G3show(pct, near)
  end
  if g.t >= g.TIME then
    g.hacking = false
    Coop.log("split G3: restoration complete")
    MapInit.DeactivateEnemies()
  end
end

function Sp.G3show(pct, near)
  local key = near and "hack" or "hack_away"
  Scorer.SetMsgText(string.format(Sp.text(key), pct), Game.GetTime() + 3)
end

function Sp.installG3(isHost)
  if not MapInit.StartManipulation or Sp.hooked["G3"] then
    if isHost and Sp.G3.hacking then Sp.G3update(Coop.TICK) end
    return
  end
  Sp.hooked["G3"] = true
  local origStart, origAmbush = MapInit.StartManipulation, MapInit.Ambush
  local origQuake, origFinal = MapInit.QuakeOff, MapInit.FinalTalk
  MapInit.StartManipulation = function(char, ...)
    if not (Coop.inSession() and human("Cole")) then return origStart(char, ...) end
    Sp.G3.human = true
    -- No FakeCole, no switching the real Cole off: the player is the hacker.
    if isHost then
      MapInit.MoveSquadAndStartCombat()
      Sp.G3start()
    end
  end
  MapInit.Ambush = function(...)
    if not Sp.G3.human then return origAmbush(...) end
    if isHost then
      -- Vanilla minus the fixed timers (the restoration progress plays Cole's lines).
      NPC.ActivateEnemyGroup("emboscada")
      Sp.chat("Mission_Alk_Bunker_01_Ambush")
    end
  end
  MapInit.QuakeOff = function(...)
    if TeamTalk.FacialAlias.Cole then return origQuake(...) end
    Game.Set("DoingStopChat", 1)
    pcall(MapSoundFuncs.Temblor)
    pcall(MapSoundFuncs.Temblor2)
    local cam = Game.GetEntity(Game.GetCam(0))
    if cam and cam:IsType("FCam") then
      cam.QuakeFactor = 1
      cam.QuakeTime = 2
    end
    PhysicsObj.CloseDoor("ScreenView")
    Game.AddScheduledFunc(Game.GetTime() + 2, "", "MapInit.FinalTalk", "Mission_Alk_Bunker_01_End")
  end
  MapInit.FinalTalk = function(Speech, ...)
    if TeamTalk.FacialAlias.Cole then return origFinal(Speech, ...) end
    Game.GetEntity("Cole").bActive = true
    TeamTalk.InitIncidentalChat(Speech, MapInit.OpenLastDoor, true)
  end
end

------------------------------------------------------------------------------

Sp.LEVELS = {["levels/cru_sewers"] = Sp.installG8, ["levels/rom_caldarium"] = Sp.installG10,
             ["levels/rom_palace_01"] = Sp.installG11, ["levels/wwii_brandenburg"] = Sp.installG6,
             ["levels/sum_end"] = Sp.installG15, ["levels/alk_bunker_01"] = Sp.installG3}

function Sp.onMessage(peer, f)
  if f[1] == "spp" and Coop.isClient() then
    Sp.G3show(tonumber(f[2]) or 0, f[3] == "1")
    return true
  elseif f[1] == "spchat" and Coop.isClient() then
    pcall(TeamTalk.InitIncidentalChat, f[2], nil, false)
    return true
  elseif f[1] == "spstun" and Coop.isClient() then
    Sp.G15onStun(f[2])
    return true
  elseif f[1] == "spfree" then
    -- From the holder (to the host, which tells everyone) or from the host.
    if Coop.isHost() then
      if Coop.ownerOf(f[2] or "") ~= peer then return true end
      Net.CoopSend(-1, 1, "spfree|" .. f[2])
    end
    if f[2] ~= Coop.localChar() then Sp.G15onFree(f[2]) end
    return true
  elseif f[1] == "spc" and Coop.isClient() then
    Sp.offer(f[2])
    return true
  elseif f[1] == "spn" and Coop.isClient() then
    local chars = {}
    for c in string.gmatch(f[3] or "", "[^,]+") do chars[#chars + 1] = c end
    Sp.showNotice(f[2], chars)
    return true
  end
  return false
end

function Sp.update()
  if Sp.LEVELS[Coop.level] and MapCallbacks and MapInit then Sp.LEVELS[Coop.level](Coop.isHost()) end
  Sp.updateChoice()
  if Sp.G15.struggle then Sp.G15updateStruggle(Coop.TICK) end
end
