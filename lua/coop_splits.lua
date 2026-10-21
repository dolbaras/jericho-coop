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
--   G1 (leg A) alk_tomb "Perimeter recon": Alpha's players keep their bodies after the
--      goodbye and hold against cultist waves until Omega reaches the blood door.
--   G1 (leg C) alk_city "Pinned at the north-east dig": Alpha's players keep their bodies in
--      their sealed pocket and hold it until Omega breaks through.
--   G4 wwii_pillboxes "Stations of the Path": a human Rawlings, shot by Delgado, walks his
--      soul back through three stations while the squad defends his body; the revive
--      waits for the soul and is the host's (as in vanilla).
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
    choose = "%s goes on alone (%d)\n1 - play as %s\n2 - stay with your own",
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
    struggle = "The blood link holds you.\nHold E to break free (%d%%)",
    hack = "Cole restores the files: %d%%. Defend her!",
    hack_away = "Restoration paused at %d%%: Cole must be at the console.",
    pinned1 = "Alpha is cut off in the dig. Hold out until Omega gets through.",
    pinned2 = "More cultists from the dig!",
    pinned3 = "They keep coming. Omega is fighting its way to you.",
    omega_near = "Omega is close: you can hear their guns.",
    recon = "Alpha: recon of the tomb's perimeter. No fighting without support.",
    captive = "Keep Lichthammer bound: stand by her and press E (E again lets go).",
    captive_summons = "Nobody holds Lichthammer: she calls her followers!",
    recon_fail = "Cultists! The recon turns into a fight. Hold together.",
    recon_more = "More of them come up from the sand.",
    soul_go = "RAWLINGS' SOUL: go back along the Path of Souls - station %d of %d",
    soul_pray = "Pray: hold E (%d%%)",
    soul_body = "Return to your body",
    soul_defend = "Rawlings is down. Hold them off while his soul finds its way back.",
    soul_station1 = "Rawlings' soul passed the first station. She is losing him.",
    soul_station2 = "Second station. They push harder!",
    soul_station3 = "Last station. Rawlings is almost back.",
    soul_back = "Rawlings' soul is back. Revive him!",
  },
  ru = {
    choose = "%s идёт дальше один (%d)\n1 - играть за: %s\n2 - остаться своим персонажем",
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
    struggle = "Кровавая связь держит вас.\nУдерживайте E, чтобы вырваться (%d%%)",
    hack = "Коул восстанавливает файлы: %d%%. Защищайте её!",
    hack_away = "Восстановление стоит на %d%%: Коул должна быть у консоли.",
    pinned1 = "Альфа отрезана на раскопе. Держитесь, пока Омега не пробьётся.",
    pinned2 = "Из раскопа лезут ещё культисты!",
    pinned3 = "Они не кончаются. Омега уже прорывается к вам.",
    omega_near = "Омега близко: слышна их стрельба.",
    recon = "Альфа: разведка периметра гробницы. Без поддержки в бой не вступать.",
    captive = "Держите Лихтхаммер: встаньте рядом и нажмите E (повторное E - отпустить).",
    captive_summons = "Лихтхаммер никто не держит: она зовёт своих!",
    recon_fail = "Культисты! Разведка превращается в бой. Держитесь вместе.",
    recon_more = "Из песка лезут новые.",
    soul_go = "ДУША РОУЛИНГСА: вернитесь по Пути душ - станция %d из %d",
    soul_pray = "Молитва: удерживайте E (%d%%)",
    soul_body = "Вернитесь к своему телу",
    soul_defend = "Роулингс пал. Держитесь, пока его душа ищет путь назад.",
    soul_station1 = "Душа Роулингса прошла первую станцию. Она теряет его.",
    soul_station2 = "Вторая станция. Они давят сильнее!",
    soul_station3 = "Последняя станция. Роулингс почти вернулся.",
    soul_back = "Душа Роулингса вернулась. Оживите его!",
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
  -- A story line alone (coop_storysolo.lua) is this character's line: nothing to choose.
  if cfg.storyline then return end
  -- The character going on is free: offer it; otherwise there is nothing to choose.
  if Coop.ownerOf(s.goes) ~= nil and Coop.ownerOf(s.goes) ~= Coop.myId() then return end
  Sp.choice = {id = id, target = s.goes, untilT = Net.CoopTime() + Sp.CHOICE_TIME}
  Coop.log("split " .. id .. ": choose " .. s.goes .. " or stay")
end

function Sp.updateChoice()
  local c = Sp.choice
  if not c then
    if not Sp.G15 or not Sp.G15.struggle then Coop.textBlockHide("CoopSplit") end
    return
  end
  local left = math.ceil(c.untilT - Net.CoopTime())
  local pick
  if Net.CoopKey(0x31) == 1 then pick = "take" elseif Net.CoopKey(0x32) == 1 or left <= 0 then pick = "stay" end
  if pick then
    Sp.choice = nil
    Coop.textBlockHide("CoopSplit")
    Coop.log("split " .. c.id .. ": " .. pick)
    if pick == "take" and Team and Team.SwitchSoldier and Coop.ownerOf(c.target) == nil then
      Team.SwitchSoldier(Coop.localChar(), c.target)
    end
    return
  end
  local who = Coop.charName(c.target)
  Coop.textBlock("CoopSplit", string.format(Sp.text("choose"), who, math.max(left, 0), who),
    {y = 90, color = Color(255, 220, 160, 255)})
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

-- The captive: one of the two must hold Lichthammer (stand by her, E: the sacrifice hold
-- pose; E again lets go). Unheld for UNHELD seconds, she calls her followers onto the gate
-- top. Each machine handles its own player; the host counts holders and summons.
--   g6hold|<char>|<1/0>   holder -> host
Sp.G6.HOLD_DIST = 170
Sp.G6.UNHELD = 20
Sp.G6.SUMMON_EVERY = 35
Sp.G6.holders = {}

function Sp.G6holdUpdate()
  local g = Sp.G6
  local me = Coop.localChar()
  if g.free or not g.anchor[me or ""] or (Scene and Scene.IsPlaying) then return end
  local e, b = Game.GetEntity(me), Game.GetEntity("Bitchie")
  if not e or not b then return end
  local down = Net.CoopKey(0x45) == 1
  local pressed = down and not g.keyWas
  g.keyWas = down
  if not pressed then return end
  local d = e.Pos - b.Pos
  if not g.holding and math.sqrt(d.x * d.x + d.z * d.z) > g.HOLD_DIST then return end
  g.holding = not g.holding
  e.IgnoreUsrControl = g.holding and 1 or 0
  e.ForceAction = g.holding and "NaziSacrifice" or "Relax"
  Coop.log("split G6: " .. me .. (g.holding and " holds" or " lets go of") .. " the captive")
  if Coop.isHost() then Sp.G6onHold(me, g.holding) else Net.CoopSend(0, 1, "g6hold|" .. me .. "|" .. (g.holding and 1 or 0)) end
end

function Sp.G6onHold(char, on)
  Sp.G6.holders[char] = on or nil
  Sp.G6.unheldSince = nil
end

-- Host: nobody holds her for a while -> she calls her followers.
function Sp.G6summonCheck()
  local g = Sp.G6
  if g.free or not (human("Cole") or human("Rawlings")) then return end
  if next(g.holders) then
    g.unheldSince = nil
    return
  end
  local now = Net.CoopTime()
  g.unheldSince = g.unheldSince or now
  if now - g.unheldSince < g.UNHELD or now < (g.nextSummon or 0) then return end
  g.nextSummon = now + g.SUMMON_EVERY
  local b = Game.GetEntity("Bitchie")
  if not b then return end
  Sp.newList("CoopGateTop")
  local n = 1 + Sp.humansIn({Cole = true, Rawlings = true})
  for i = 1, n do
    local a = i / n * 2 * math.pi
    local ok, e = pcall(NPC.CreateWithAI, "CultistaExplosivo", b.Pos.x + math.cos(a) * 260, b.Pos.y, b.Pos.z + math.sin(a) * 260, "CoopGateTop", 1)
    if ok and e then e.bActive = true end
  end
  Sp.notice("captive_summons", g.chars)
  Coop.log("split G6: the captive calls " .. n .. " followers")
end

function Sp.G6afterInit()
  if Sp.G6.initDone then return end
  Sp.G6.initDone = true
  Sp.G6keepHumans()
  Sp.G6takeSeat()
  Sp.showNotice("captive", Sp.G6.chars)
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
  -- Vanilla switches both bodies off for the scenes: a player's body is only hidden (a body
  -- switched off is no user any more: the second scene found no user and the screen stayed
  -- black, story line test G6).
  if MapInit.HideRawlingsCole and not Sp.hooked["G6hide"] then
    Sp.hooked["G6hide"] = true
    local origHide = MapInit.HideRawlingsCole
    MapInit.HideRawlingsCole = function(...)
      local keep = {}
      for _, n in ipairs(Sp.G6.chars) do
        local e = Game.GetEntity(n)
        if e and e.UsrControl == 0 then keep[n] = e end
      end
      local r = {pcall(origHide, ...)}
      for n, e in pairs(keep) do
        e.bActive = true
        e.bObjectVisible = false
        Sp.G6.hidden = Sp.G6.hidden or {}
        Sp.G6.hidden[n] = true
        Coop.log("split G6: " .. n .. " hidden for the sacrifice scenes (a player's body stays on)")
      end
      if not r[1] then Coop.log("split G6: HideRawlingsCole error: " .. tostring(r[2])) end
      return unpack(r, 2)
    end
  end
  Sp.after("MapInit.HideRawlingsCole", function() Sp.G6.free = true end)
  Sp.after("MapInit.ReposPeople", function()
    for n in pairs(Sp.G6.hidden or {}) do
      local e = Game.GetEntity(n)
      if e then e.bObjectVisible = true end
    end
    Sp.G6.hidden = nil
  end)
  if Coop.frame % 10 == 0 then Sp.G6leash() end
  Sp.G6holdUpdate()
  if isHost and Coop.frame % 40 == 0 then Sp.G6summonCheck() end
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
        Coop.log("split G15: " .. n .. " is bound by the rune")
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
  if not s then return end
  if Net.CoopKey(0x45) == 1 then s.held = s.held + dt end
  if s.held >= Sp.G15.HOLD then
    Sp.G15.struggle = nil
    Coop.textBlockHide("CoopSplit")
    if Coop.isHost() then
      Net.CoopSend(-1, 1, "spfree|" .. s.char)
    else
      Net.CoopSend(0, 1, "spfree|" .. s.char)
    end
    Sp.G15onFree(s.char)
    return
  end
  Coop.textBlock("CoopSplit", string.format(Sp.text("struggle"), math.floor(100 * s.held / Sp.G15.HOLD)),
    {y = 90, color = Color(255, 120, 120, 255)})
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
    g.restoredAt = Game.GetTime()
    Coop.log("split G3: restoration complete")
    MapInit.DeactivateEnemies()
  end
end

-- After the restoration (host): vanilla goes on when the ambush's generator reports all its
-- enemies dead (emboscada_0 -> EnemiesDeath -> the quake, the last talk, the way out). That
-- report did not come in the story line test with no ambusher left: once none is alive, the
-- level goes on.
function Sp.G3afterRestore()
  local g = Sp.G3
  if not g.restoredAt or g.ended or Coop.frame % 30 ~= 0 then return end
  local left
  local l = Game.GetEntityList and Game.GetEntityList("emboscada")
  if l then pcall(function() left = l:GetEntitiesLeft() end) end
  local alive = 0
  local e = Game.GetFirst()
  while e ~= nil do
    if e:IsType("WalkChar") and e.TgType == "red" and (e.Life or 0) > 0 and e.bActive then alive = alive + 1 end
    e = Game.GetEntity(e.NextInSlot)
  end
  local since = Game.GetTime() - g.restoredAt
  if cfg.dev and Coop.frame % 300 == 0 then
    Coop.log("split G3: after the restoration, " .. alive .. " alive, list left " .. tostring(left))
  end
  if (alive == 0 and since > 5) or (left == 0 and since > 20) then
    g.ended = true
    Coop.log("split G3: ambush down (list left " .. tostring(left) .. "), the level goes on")
    MapInit.EnemiesDeath()
  end
end

function Sp.G3quakeFallback()
  if Sp.G3.quaked then return end
  Coop.log("split G3: the ambush talk never ended, the quake comes anyway")
  MapInit.QuakeOff()
end

function Sp.G3doorFallback()
  if Sp.G3.doorOpen then return end
  Coop.log("split G3: the final talk never ended, the way out opens anyway")
  pcall(TeamTalk.EndOfIncidentalChat, true)
  MapInit.OpenLastDoor()
end

function Sp.G3show(pct, near)
  local key = near and "hack" or "hack_away"
  Scorer.SetMsgText(string.format(Sp.text(key), pct), Game.GetTime() + 3)
end

function Sp.installG3(isHost)
  if not MapInit.StartManipulation or Sp.hooked["G3"] then
    if isHost and Sp.G3.hacking then Sp.G3update(Coop.TICK) end
    if isHost then Sp.G3afterRestore() end
    return
  end
  -- The vanilla talks end in the next step (their callback); they were written for the
  -- stand-in Cole: should one never end, the next step comes anyway.
  Sp.after("MapInit.EnemiesDeath", function()
    Sp.G3.ended = true
    Coop.log("split G3: the ambush is down")
    if isHost then Game.AddScheduledFunc(Game.GetTime() + 40, "CoopSplitG3", "CoopSplits.G3quakeFallback") end
  end)
  Sp.after("MapInit.OpenLastDoor", function() Sp.G3.doorOpen = true Coop.log("split G3: the way out is open") end)
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
    if Sp.G3.quaked then return end
    Sp.G3.quaked = true
    Coop.log("split G3: the quake")
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
    Coop.log("split G3: the final talk")
    Game.GetEntity("Cole").bActive = true
    TeamTalk.InitIncidentalChat(Speech, MapInit.OpenLastDoor, true)
    if isHost then Game.AddScheduledFunc(Game.GetTime() + 40, "CoopSplitG3", "CoopSplits.G3doorFallback") end
  end
end

------------------------------------------------------------------------------
-- A new enemy list for the mod's waves (every vanilla list of some levels counts its
-- deaths for story flags). Created on every machine: clients mirror spawns into it.
------------------------------------------------------------------------------

function Sp.newList(name)
  if not NPC or not NPC.Groups or NPC.Groups[name] then return NPC and NPC.Groups and NPC.Groups[name] ~= nil end
  local ok, err = pcall(function()
    local els = Game.CreateEntityList(name)
    els.uData.isGenerator = false
    NPC.Groups[name] = {}
    NPC.Groups[name].uData = els.uData
    AIEnemiesTeam.Create({[name] = {}}, name)
  end)
  Coop.log("split: enemy list " .. name .. (ok and " created" or (" failed: " .. tostring(err))))
  return ok
end

function Sp.spawnWave(list, class, points, n, anim)
  local spawned = {}
  for k = 1, n do
    local p = points[(k - 1) % #points + 1]
    local off = math.floor((k - 1) / #points) * 60
    local ok, e = pcall(NPC.CreateWithAI, class, p.x + off, p.y, p.z + off, list, 1)
    if ok and e then
      e.bActive = true
      e.ForceAction = anim or "Emerge"
      spawned[#spawned + 1] = e.Name
    else
      Coop.log("split: spawn " .. class .. " into " .. list .. " failed: " .. tostring(e))
    end
  end
  return spawned
end

------------------------------------------------------------------------------
-- G1 leg C alk_city: "Pinned at the north-east dig" (docs/story/act1-splits.md G1)
-- Vanilla hides Alpha (Jones, Cole, Delgado) at the start and shows them at the reunion.
-- Alpha's players keep their bodies in their sealed pocket and hold it against cultists
-- crawling out of the dig, harder as Omega gets closer, until Omega breaks through.
------------------------------------------------------------------------------

Sp.G1C = {alpha = {Delgado = true, Jones = true, Cole = true}, list = {"Delgado", "Jones", "Cole"},
          LIST = "CoopAlphaCity",
          PITS = {V3D(582, 1, -11113), V3D(481, 88, -8080), V3D(-160, 5, -10704), V3D(-718, 104, -10786)}}

function Sp.G1Cwave(n)
  local g = Sp.G1C
  local alpha = Sp.humansIn(g.alpha)
  if alpha == 0 or g.done or (g.phase or 0) >= n then return end
  g.phase = n
  Coop.log("split G1C: wave " .. n .. ", " .. alpha .. " Alpha player(s)")
  if n == 1 then
    Sp.spawnWave(g.LIST, "CultistaMelee", g.PITS, 1 + alpha)
    Sp.notice("pinned1", g.list)
    Sp.radio("Jones", "Help_Alpha")
  elseif n == 2 then
    Sp.spawnWave(g.LIST, "CultistaMelee", g.PITS, 2 + alpha)
    Sp.notice("pinned2", g.list)
    Sp.radio("Cole", "Enemy_Ambush")
  elseif n == 3 then
    Sp.spawnWave(g.LIST, "CultistaMelee", g.PITS, 2 + alpha)
    Sp.spawnWave(g.LIST, "CultistaExplosivo", g.PITS, 1)
    Sp.notice("pinned3", g.list)
    Sp.radio("Delgado", "Forboding_Sound")
  end
end

function Sp.installG1C(isHost)
  Sp.newList(Sp.G1C.LIST)
  if MapInit.DisableAlpha and not Sp.hooked["G1Cdisable"] then
    Sp.hooked["G1Cdisable"] = true
    local orig = MapInit.DisableAlpha
    MapInit.DisableAlpha = function(...)
      if not Coop.inSession() or Sp.humansIn(Sp.G1C.alpha) == 0 then return orig(...) end
      -- Only AI-held Alpha members are hidden; the players hold the pocket.
      for _, n in ipairs(Sp.G1C.list) do
        local e = Game.GetEntity(n)
        if e and not human(n) then
          e.oAI.bEnable = false
          e.bActive = false
        end
      end
      if isHost then Game.AddScheduledFunc(Game.GetTime() + 8, "CoopSplitG1C", "CoopSplits.G1Cwave", 1) end
    end
  end
  -- AreaTriggerInit sits on Ross's start and may hide Alpha before the hook above: bring
  -- the players' bodies back once, shortly after the start.
  if not Sp.G1C.startChecked and Coop.frame > 40 then
    Sp.G1C.startChecked = true
    local fixed = false
    for _, n in ipairs(Sp.G1C.list) do
      local e = Game.GetEntity(n)
      if e and human(n) and e.bActive == false then
        e.bActive = true
        fixed = true
      end
    end
    if fixed and isHost and not Sp.G1C.phase then
      Game.AddScheduledFunc(Game.GetTime() + 8, "CoopSplitG1C", "CoopSplits.G1Cwave", 1)
    end
  end
  if not isHost then return end
  Sp.after("MapCallbacks.AreaTrigger_3", function() Sp.G1Cwave(2) end)
  Sp.after("MapCallbacks.AreaTrigger49_0", function() Sp.G1Cwave(3) end)
  Sp.after("MapCallbacks.AreaTrigger133_0", function()
    if Sp.G1C.phase and not Sp.G1C.done then
      Sp.notice("omega_near", Sp.G1C.list)
      Sp.radio("Cole", "Spot_Team")
    end
  end)
  Sp.after("MapCallbacks.AreaTrigger119_1", function()
    Sp.G1C.done = true
    Sp.radio("Jones", "Rejoin_Team")
  end)
end

------------------------------------------------------------------------------
-- G4 wwii_pillboxes: "Stations of the Path" (docs/story/act2-splits.md section 2, owner's
-- decision 2026-10-19). Delgado's shot tears Rawlings' soul out onto Lichthammer's Path of
-- Souls. With a human Rawlings: his player walks the soul back (spirit flight) from the trap
-- door through three stations (hold E to pray) to his body; the squad defends the body
-- against the final Nazi wave, harder at every station; the revive works only once the soul
-- is back, and it is the host's (Ross's spirit, as in vanilla) - or any other human's when
-- the host is Rawlings. With an AI Rawlings everything stays vanilla.
--   spsoul|<1..3>|arrived   soul's machine -> host -> all
------------------------------------------------------------------------------

Sp.G4 = {START = V3D(-14574, 328, 3218),
         STATIONS = {V3D(-16728, 391, 5260), V3D(-16035, 439, 6940), V3D(-17887, 434, 8239)},
         BODY = V3D(-17100, 415, 9112), RADIUS = 300, PRAY = 3,
         squad = {"Black", "Church", "Cole", "Delgado", "Jones"}}

function Sp.G4on() return Sp.G4.active == true end

-- Revive gate (every machine): Rawlings' body cannot be revived before his soul is back, and
-- only by the host (or by the others when the host holds Rawlings).
function Sp.G4canCure(obj)
  if not Sp.G4on() or not obj or obj.Name ~= "Rawlings" then return true end
  if not Sp.G4.arrived then return false end
  if Coop.ownerOf("Rawlings") == 0 then return not Coop.isHost() end
  return Coop.isHost()
end

function Sp.G4hint()
  local g = Sp.G4
  if g.prayer then
    return string.format(Sp.text("soul_pray"), math.floor(100 * g.prayer / g.PRAY))
  end
  if g.station > #g.STATIONS then return Sp.text("soul_body") end
  return string.format(Sp.text("soul_go"), g.station, #g.STATIONS)
end

-- The soul's own machine (Rawlings' holder).
function Sp.G4startSoul()
  local g = Sp.G4
  if g.soulOn or not CoopSpirit then return end
  g.soulOn, g.station, g.prayer = true, 1, nil
  local pts = {g.START}
  for _, p in ipairs(g.STATIONS) do pts[#pts + 1] = p end
  pts[#pts + 1] = g.BODY
  CoopSpirit.startSoul({points = pts, radius = 700, hint = Sp.G4hint})
  Coop.log("split G4: Rawlings' soul on the Path of Souls")
end

function Sp.G4soulFrame(dt)
  local g = Sp.G4
  if not g.soulOn or not CoopSpirit or not CoopSpirit.pos then return end
  local target = g.STATIONS[g.station] or g.BODY
  if cfg.soulauto then
    -- Test autopilot (dev): fly to the next station and pray there.
    local v = target - CoopSpirit.pos
    local l = math.sqrt(v.x * v.x + v.z * v.z)
    local step = math.min(l, 600 * dt)
    if l > 1 then CoopSpirit.pos = CoopSpirit.pos + V3D(v.x / l * step, 0, v.z / l * step) end
  end
  local pos = CoopSpirit.pos
  local d = pos - target
  local near = math.sqrt(d.x * d.x + d.z * d.z) < g.RADIUS
  if g.station > #g.STATIONS then
    if near and not g.arrivedSent then
      g.arrivedSent = true
      Sp.G4send("arrived")
    end
    return
  end
  if near and (Net.CoopKey(0x45) == 1 or cfg.soulauto) then
    g.prayer = (g.prayer or 0) + dt
    if g.prayer >= g.PRAY then
      g.prayer = nil
      Sp.G4send(tostring(g.station))
      g.station = g.station + 1
    end
  elseif not near then
    g.prayer = nil
  end
end

function Sp.G4send(what)
  if Coop.isHost() then Sp.G4onSoul(what, 0) else Net.CoopSend(0, 1, "spsoul|" .. what) end
end

-- Every machine learns of the soul's progress; the host also turns it into pressure.
function Sp.G4onSoul(what, peer)
  local g = Sp.G4
  if what == "begin" or what == "end" then
    if not Coop.isHost() then
      if what == "begin" then Sp.G4begin() else Sp.G4end() end
    end
    return
  end
  if Coop.isHost() then
    if peer ~= 0 and Coop.ownerOf("Rawlings") ~= peer then return end
    Net.CoopSend(-1, 1, "spsoul|" .. what)
  end
  if what == "arrived" then
    g.arrived = true
    Sp.showNotice("soul_back", g.squad)
    Coop.log("split G4: the soul is back at the body")
    if Coop.isHost() then Sp.radio("Rawlings", "Using_PowerTwo", 2) end
  else
    local n = tonumber(what) or 0
    Coop.log("split G4: station " .. n)
    if Coop.isHost() then
      pcall(EnemyGen.IncreaseMaxEnemies, "nazis_final")
      Sp.radio("Rawlings", "Tactical_Flavor", (n - 1) % 2)
      Sp.notice("soul_station" .. n, g.squad)
    end
  end
end

function Sp.G4begin()
  local g = Sp.G4
  if g.active then return end
  g.active = true
  Coop.log("split G4: Stations of the Path (Rawlings is a player)")
  if Coop.isHost() then
    -- Clients start too, also when Delgado's shot did not play on their machine.
    Net.CoopSend(-1, 1, "spsoul|begin")
    Sp.rearm("nazis_final", 1 + Sp.humansIn({Black = true, Church = true, Cole = true, Delgado = true, Jones = true}))
    Sp.notice("soul_defend", g.squad)
    Sp.radio("Jones", "Help_Rawlings")
  end
  if Coop.localChar() == "Rawlings" then
    -- The body is the holder's: it lies down here, or the host's copy would follow it up.
    local raw = Game.GetEntity("Rawlings")
    if CoopTeam then CoopTeam.holdDowned.Rawlings = true end
    if raw and raw.Life > 0 then
      raw.Invulnerable = 0
      raw.Life = 0
    end
    Sp.G4startSoul()
  end
end

function Sp.G4end()
  local g = Sp.G4
  if g.ended then return end
  g.ended = true
  if g.soulOn and CoopSpirit then CoopSpirit.endSoul() end
  g.soulOn = false
  if CoopTeam then CoopTeam.holdDowned.Rawlings = nil end
  if Coop.isHost() then
    Net.CoopSend(-1, 1, "spsoul|end")
    pcall(EnemyGen.Stop, "nazis_final", true)
  end
  Coop.log("split G4: Rawlings revived")
end

function Sp.installG4(isHost)
  if not Sp.hooked["G4"] and Team and Team.CanCure and MapInit.PillBoxOnUse and MapScenes then
    Sp.hooked["G4"] = true
    local origCan = Team.CanCure
    Team.CanCure = function(obj, ...)
      if not Sp.G4canCure(obj) then return false end
      return origCan(obj, ...)
    end
    -- The wave goes on while Cole is in the pillbox's vision (vanilla kills it there).
    local origUse = MapInit.PillBoxOnUse
    MapInit.PillBoxOnUse = function(...)
      if not (Coop.inSession() and human("Rawlings")) then return origUse(...) end
      local origStop = EnemyGen.Stop
      EnemyGen.Stop = function(name, ...) if name ~= "nazis_final" then return origStop(name, ...) end end
      local ok, err = pcall(origUse, ...)
      EnemyGen.Stop = origStop
      if not ok then Coop.log("split G4: PillBoxOnUse error: " .. tostring(err)) end
    end
    -- After the shot: no AI-off loop for the squad (it defends the body).
    local origLoop = MapScenes.DisableAILoop
    MapScenes.DisableAILoop = function(...)
      if not Sp.G4on() then return origLoop(...) end
      pcall(Team.HoldPosMain)
      pcall(Team.HoldPosSide)
    end
  end
  -- The shot: a human Rawlings stays in his body (the soul walk starts from it).
  Sp.after("MapScenes.OnInit_DelgadokillsRawlings", function()
    if Coop.inSession() and human("Rawlings") and CoopTeam then CoopTeam.holdDowned.Rawlings = true end
  end)
  Sp.after("MapInit.AfterRawlingKilled", function()
    if Coop.inSession() and human("Rawlings") then Sp.G4begin() end
  end)
  Sp.after("MapInit.AfterRawlingHealed", function() if Sp.G4on() then Sp.G4end() end end)
  if Sp.G4.soulOn then Sp.G4soulFrame(Coop.TICK) end
end

------------------------------------------------------------------------------
-- G1 leg A alk_tomb: "Perimeter recon" (docs/story/act1-splits.md G1)
-- Ross sends Alpha (Jones, Cole, Delgado) on a recon; vanilla switches them off and lets
-- three invulnerable walkers leave in their place. Alpha's players keep their bodies: they
-- start where the walkers do, "do not engage without support" fails, and they hold against
-- waves of cultists until Omega reaches the blood door (they meet again in alk_city).
------------------------------------------------------------------------------

Sp.G1A = {alpha = {Jones = true, Cole = true, Delgado = true}, list = {"Jones", "Cole", "Delgado"},
          LIST = "CoopAlphaTomb",
          WALKER = {Jones = {V3D(176, -2043, 16070), 123}, Delgado = {V3D(307, -2061, 15984), 123},
                    Cole = {V3D(-132, -2068, 16046), 131}},
          WAVES = {30, 100, 170}}

-- Vanilla MapInit.StartSayGoodbye with Alpha's players kept, run on every machine.
function Sp.G1Agoodbye()
  local g = Sp.G1A
  MapInit.GoodByeChars = {}
  Scorer.Fade(0, Color(0, 0, 0, 255), Color(0, 0, 0, 0), 1)
  for _, n in ipairs(g.list) do
    local w = g.WALKER[n]
    if human(n) then
      -- The player's body starts where its walker would.
      if n == Coop.localChar() or (Coop.isHost() and not Coop.isRemoteOwned(n)) then
        local e = Game.GetEntity(n)
        if e then
          e.Pos = w[1]
          e.Ang = V3D(0, w[2], 0)
          Game.SetOnFloor(n)
        end
      end
    else
      Game.GetEntity(n).bActive = false
      local o = Game.CreateEntity("Fake" .. n, "WalkChar")
      o.ActCtrl = n
      o.Pos = w[1]
      o.Ang = V3D(0, w[2], 0)
      o.Invulnerable = 1
      o.Action = "WalkInit"
      o.DefLoop = "Walk"
      MapInit.GoodByeChars[#MapInit.GoodByeChars + 1] = o
    end
  end
  local places = {Ross = V3D(291, -2219, 15052), Church = V3D(92, -2220, 14439),
                  Black = V3D(109, -2220, 14075), Rawlings = V3D(753, -2220, 14001)}
  for n, p in pairs(places) do
    local e = Game.GetEntity(n)
    if e and (n == Coop.localChar() or not human(n)) then
      e.Pos = p
      Game.SetOnFloor(n)
    end
  end
  local ross = Game.GetEntity("Ross")
  if ross then ross.Ang = V3D(0, 164, 0) end
  Game.AddScheduledFunc(Game.GetTime() + 20, "StartSayGoodbye", "MapInit.DeleteGoodByeChars")
  -- Ross's walk and lock belong to Ross's player only (vanilla: "the player").
  if Coop.localChar() == "Ross" then
    Game.UsrEntity(0).IgnoreUsrControl = 1
    Game.AddScheduledFunc(Game.GetTime() + 1, "StartSayGoodbye", "MapInit.MiraDetrasDeTi")
  end
  if Coop.isHost() and Sp.humansIn(g.alpha) > 0 then
    Sp.notice("recon", g.list)
    for i, t in ipairs(g.WAVES) do
      Game.AddScheduledFunc(Game.GetTime() + t, "CoopSplitG1A", "CoopSplits.G1Awave", i)
    end
  end
end

function Sp.G1Awave(n)
  local g = Sp.G1A
  local alpha = Sp.humansIn(g.alpha)
  if alpha == 0 or g.done then return end
  -- Around Alpha's players, a short way out, on the floor.
  local center, k = V3D(0, 0, 0), 0
  for _, name in ipairs(g.list) do
    local e = Game.GetEntity(name)
    if e and human(name) and (e.Life or 0) > 0 then
      center = center + e.Pos
      k = k + 1
    end
  end
  if k == 0 then return end
  center = V3D(center.x / k, center.y / k, center.z / k)
  local count = (n == 3 and 3 or 2) + alpha
  local spawned = 0
  for i = 1, count do
    local a = (i / count + n * 0.17) * 2 * math.pi
    local p = V3D(center.x + math.cos(a) * 750, center.y + 60, center.z + math.sin(a) * 750)
    local ok, e = pcall(NPC.CreateWithAI, "CultistaMelee", p.x, p.y, p.z, g.LIST, 1)
    if ok and e then
      e.bActive = true
      pcall(Game.SetOnFloor, e.Name)
      spawned = spawned + 1
    end
  end
  Coop.log("split G1A: wave " .. n .. ", " .. spawned .. " cultists around Alpha")
  Sp.notice(n == 1 and "recon_fail" or "recon_more", g.list)
  Sp.radio(n == 1 and "Jones" or "Delgado", n == 1 and "Enemy_Ambush" or "Forboding_Sound")
end

function Sp.installG1A(isHost)
  Sp.newList(Sp.G1A.LIST)
  if MapInit.StartSayGoodbye and not Sp.hooked["G1A"] then
    Sp.hooked["G1A"] = true
    local orig = MapInit.StartSayGoodbye
    MapInit.StartSayGoodbye = function(...)
      if not (Coop.inSession() and Sp.humansIn(Sp.G1A.alpha) > 0) then return orig(...) end
      -- once (a second call would bring every wave twice)
      if Sp.G1A.saidGoodbye then return end
      Sp.G1A.saidGoodbye = true
      Sp.G1Agoodbye()
    end
  end
  -- Omega reaches the blood door: the recon is over.
  Sp.after("MapCallbacks.Borrame_cinematica_0", function() Sp.G1A.done = true end)
end

------------------------------------------------------------------------------

Sp.LEVELS = {["levels/cru_sewers"] = Sp.installG8, ["levels/rom_caldarium"] = Sp.installG10,
             ["levels/rom_palace_01"] = Sp.installG11, ["levels/wwii_brandenburg"] = Sp.installG6,
             ["levels/sum_end"] = Sp.installG15, ["levels/alk_bunker_01"] = Sp.installG3,
             ["levels/alk_city"] = Sp.installG1C, ["levels/alk_tomb"] = Sp.installG1A, ["levels/wwii_pillboxes"] = Sp.installG4}

function Sp.onMessage(peer, f)
  if f[1] == "g6hold" and Coop.isHost() then
    if Coop.ownerOf(f[2] or "") == peer then Sp.G6onHold(f[2], f[3] == "1") end
    return true
  elseif f[1] == "spsoul" then
    Sp.G4onSoul(f[2], peer)
    return true
  elseif f[1] == "spp" and Coop.isClient() then
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
