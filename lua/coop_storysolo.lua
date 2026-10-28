-- Jericho co-op: the story lines alone (COOP_CFG.storyline = '<id>', "Story Lines" launcher).
-- One player plays one of co-op's own story lines (coop_splits.lua, coop_patrol.lua) in a
-- session of their own: they hold the character the line is for, the AI squad is around
-- them, and the main line the other characters follow meanwhile (in co-op: other players or
-- the AI) is driven here: its story steps are called one after another, at the pace a
-- player would take, so the line gets its waves, its notices and its end.
--
-- A line: the level, the player's character, the spawn point (a vanilla checkpoint near the
-- split; the level is loaded again once with it), and its steps: wait (seconds after the
-- previous step, or until a story function has run), then call a story function.

CoopStorySolo = CoopStorySolo or {}
local SS = CoopStorySolo
local cfg = Coop.cfg

SS.TEXT = {
  en = {
    G1A = "Alpha's recon (Jones): the goodbye at the camp sends Alpha out; hold together.",
    G1C = "Alpha cut off in the dig (Jones): hold the pocket until Omega breaks through.",
    G3 = "Temporal restoration (Cole): stay at the console while the squad defends you.",
    G4 = "Stations of the Path (Rawlings): Delgado's shot tears your soul out; walk it back.",
    G6 = "The gate top (Cole): hold Lichthammer bound (E) and cover the squad.",
    G8 = "Hold the gate (Black): Church climbs alone; hold the jumpers' hall.",
    G10 = "The Torturers' Hall (Black): Delgado walks through the fire; hold the hall.",
    G11 = "Alone on the far side (Black): cover Church from the edge.",
    G15 = "Break the blood link (Black): struggle free (hold E) and fight on.",
    G7 = "The Lost Patrol (Jones): stay with the lost trio at the bridge.",
    main = "The main line goes on by itself: %s",
    done = "End of the line. Esc - main menu.",
    s_climb = "Church climbs alone",
    s_ward = "Church reaches the ward room",
    s_wardfight = "Church fights the ward's guards",
    s_door = "Church opens the door",
    s_fire = "Delgado walks into the fire",
    s_door1 = "Delgado is past the first door",
    s_lever = "Delgado is close to the lever",
    s_drop = "Delgado drops down by the lever",
    s_omega = "Omega fights its way through the city",
    s_omeganear = "Omega is close",
    s_omegain = "Omega breaks through",
    s_blooddoor = "Omega reaches the blood door",
    s_console = "Ross sends Cole to the console",
    s_shot = "Delgado shoots Rawlings",
    s_abyss = "Church crosses the abyss",
    s_bind = "The First Born binds the squad",
    s_bridge = "The squad crosses the bridge",
    s_cure = "Church revives Rawlings",
    s_merge = "The main group reached the chapel: the patrol rejoins it",
    s_square = "The squad fights its way across the square",
    s_bridgeopen = "The squad is on the plates: the bridge comes down",
    s_lastdoor = "The way out of the bunker is open",
    s_fbkill = "Church strikes the First Born",
    s_wave2 = "The second wave hits the squad",
    s_gatedoor = "The squad is through the door to the gate",
    s_flame = "Flamethrowers and grenadiers at the gate",
    s_gatetop = "Church reaches the gate top",
  },
  ru = {
    G1A = "Разведка Альфы (Джонс): после прощания Альфа уходит на разведку; держитесь вместе.",
    G1C = "Альфа отрезана на раскопе (Джонс): держите карман, пока Омега не пробьётся.",
    G3 = "Восстановление архива (Коул): оставайтесь у консоли, отряд вас защищает.",
    G4 = "Станции Пути (Роулингс): выстрел Дельгадо вырывает вашу душу; верните её.",
    G6 = "Верх ворот (Коул): держите Лихтхаммер (E) и прикрывайте отряд.",
    G8 = "Удержать ворота (Блэк): Чёрч поднимается один; держите зал прыгунов.",
    G10 = "Зал палачей (Блэк): Дельгадо идёт через огонь; держите зал.",
    G11 = "Один на той стороне (Блэк): прикройте Чёрча с края.",
    G15 = "Разорвать кровавую связь (Блэк): вырвитесь (удерживайте E) и сражайтесь дальше.",
    G7 = "Потерянный патруль (Джонс): останьтесь с пропавшей тройкой у моста.",
    main = "Основная линия идёт сама: %s",
    done = "Линия пройдена. Esc - главное меню.",
    s_climb = "Чёрч поднимается один",
    s_ward = "Чёрч дошёл до зала печати",
    s_wardfight = "Чёрч бьётся со стражей печати",
    s_door = "Чёрч открывает дверь",
    s_fire = "Дельгадо входит в огонь",
    s_door1 = "Дельгадо прошёл первую дверь",
    s_lever = "Дельгадо почти у рычага",
    s_drop = "Дельгадо спрыгнул у рычага",
    s_omega = "Омега пробивается через город",
    s_omeganear = "Омега уже близко",
    s_omegain = "Омега прорвалась",
    s_blooddoor = "Омега дошла до кровавой двери",
    s_console = "Росс отправляет Коул к консоли",
    s_shot = "Дельгадо стреляет в Роулингса",
    s_abyss = "Чёрч переходит пропасть",
    s_bind = "Перворождённый сковывает отряд",
    s_bridge = "Отряд идёт по мосту",
    s_cure = "Чёрч поднимает Роулингса",
    s_merge = "Основная группа дошла до часовни: патруль возвращается к ней",
    s_square = "Отряд пробивается через площадь",
    s_bridgeopen = "Отряд встал на плиты: мост опускается",
    s_lastdoor = "Выход из бункера открыт",
    s_fbkill = "Чёрч наносит удар Перворождённому",
    s_wave2 = "На отряд идёт вторая волна",
    s_gatedoor = "Отряд прошёл дверь к воротам",
    s_flame = "У ворот огнемётчики и гренадеры",
    s_gatetop = "Чёрч поднялся на ворота",
  },
}

-- The line's own messages, in a block of their own under the top of the screen (the game's
-- message line is shared with the split's hints: two texts ran over each other in G4).
SS.SAY_Y = 330   -- under the crosshair: the squad wheel takes the middle above it
function SS.say(text, secs)
  Coop.textBlock("StorySolo", text, {y = SS.SAY_Y, color = Color(210, 225, 255, 255)})
  SS.sayUntil = Game.GetTime() + (secs or 8)
end

function SS.sayUpdate()
  if SS.sayUntil and Game.GetTime() >= SS.sayUntil then
    SS.sayUntil = nil
    Coop.textBlockHide("StorySolo")
  end
end

function SS.text(key)
  local lang = Coop.lang()
  local s = (SS.TEXT[lang] or SS.TEXT.en)[key] or SS.TEXT.en[key] or key
  return Coop.enc(s, lang)
end

-- step: {after = seconds} or {on = "<function run by the story>"}, then call = "<path>",
-- args = {...}; say = text shown when it runs (what the main line just did).
SS.LINES = {
  G8 = {level = "Cru_Sewers", char = "Black", spawn = 2, steps = {
    {after = 20, call = "MapCallbacks.TriggerEscalada_0", args = {"Church", "TriggerEscalada"}, say = "s_climb"},
    {after = 80, call = "MapCallbacks.TriggerBloodWar_3", args = {"TriggerBloodWar", 0}, say = "s_ward"},
    {after = 70, call = "MapCallbacks.BloodWarGroup_0", args = {"BloodWarGroup"}, say = "s_wardfight"},
    {after = 70, call = "MapCallbacks.TriggerAperturaPuerta_0", args = {"Church", "TriggerAperturaPuerta"}, say = "s_door", last = true},
  }},
  G10 = {level = "Rom_Caldarium", char = "Black", steps = {
    {after = 25, call = "CoopStorySolo.G10fire", say = "s_fire"},
    {after = 15, call = "MapCallbacks.AreaTriggerOutFire_0", args = {"AreaTriggerOutFire", 0}},
    {after = 70, call = "CoopStorySolo.G10door1", say = "s_door1"},
    {after = 70, call = "MapCallbacks.AreaTrigger308_0", args = {"AreaTrigger308", 0}, say = "s_lever"},
    {after = 70, call = "MapCallbacks.AreaTriggerDelgadoCae_0", args = {"AreaTriggerDelgadoCae", 0}, say = "s_drop", last = true},
  }},
  G1C = {level = "Alk_City", char = "Jones", spawn = 0, steps = {
    -- (the pocket's first wave: co-op starts it when the level hides Alpha, which a line
    -- started as Jones skips)
    {after = 8, call = "CoopSplits.G1Cwave", args = {1}},
    {after = 82, call = "MapCallbacks.AreaTrigger_3", args = {"AreaTrigger_3", 0}, say = "s_omega"},
    {after = 80, call = "MapCallbacks.AreaTrigger49_0", args = {"AreaTrigger49", 0}},
    {after = 70, call = "MapCallbacks.AreaTrigger133_0", args = {"AreaTrigger133", 0}, say = "s_omeganear"},
    {after = 40, call = "CoopStorySolo.G1Cthrough", say = "s_omegain", last = true},
  }},
  -- (from the cave's exit: the level's opening crawl is Ross's own scene, no squad body then)
  G1A = {level = "Alk_Tomb", char = "Jones", spawn = 1, steps = {
    {on = "MapInit.StartSayGoodbye"},
    {after = 240, call = "MapCallbacks.Borrame_cinematica_0", args = {"Borrame_cinematica", 0}, say = "s_blooddoor", last = true},
  }},
  G3 = {level = "Alk_Bunker_01", char = "Cole", steps = {
    {after = 20, call = "MapInit.GoColeToManipulate", say = "s_console"},
    -- the ambush down and the quake's talk over: the way out opens (the level's own flow)
    {on = "MapInit.OpenLastDoor", nokick = true, say = "s_lastdoor", last = true},
  }},
  G4 = {level = "WWII_PillBoxes", char = "Rawlings", steps = {
    {after = 20, call = "MapScenes.OnInit_DelgadokillsRawlings", say = "s_shot"},
    {after = 3, call = "MapInit.AfterRawlingKilled"},
    {when = "CoopStorySolo.G4soulBack", after = 4, call = "CoopStorySolo.G4cure", say = "s_cure", last = true},
  }},
  -- The squad's way to the gate (vanilla area triggers in their order), then Church climbs:
  -- the sacrifice scene (the trigger on the gate top, which needs no player Church).
  G6 = {level = "WWII_Brandenburg", char = "Cole", steps = {
    {after = 30, call = "MapCallbacks.AreaTrigger192_0", args = {"AreaTrigger192", 0}, say = "s_square"},
    {after = 70, call = "MapCallbacks.AreaTrigger_1", args = {"AreaTrigger", 0}},
    {after = 1, call = "MapCallbacks.AreaTrigger161_0", args = {"AreaTrigger161", 0}, say = "s_wave2"},
    {after = 80, call = "MapCallbacks.AreaTrigger215_0", args = {"AreaTrigger215", 0}},
    {after = 1, call = "MapCallbacks.AreaTrigger363_0", args = {"AreaTrigger363", 0}},
    {after = 1, call = "PhysicsObj.OpenDoor", args = {"o53"}, say = "s_gatedoor"},
    {after = 50, call = "MapCallbacks.AreaTrigger158_0", args = {"AreaTrigger158", 0}, say = "s_flame"},
    {after = 70, call = "MapCallbacks.AreaTrigger217_0", args = {"AreaTrigger217", 0}, say = "s_climb"},
    {after = 45, call = "CoopStorySolo.G6sacrifice", say = "s_gatetop", last = true},
  }},
  -- After the wave on Church's side, the main line opens the bridge (vanilla: the others on
  -- the three plates, Church on his).
  -- The legion at the bridge is the squad's fight (this player's too); once the way over the
  -- abyss opens, Church takes it (the use callback of TriggerTheAbyss).
  G11 = {level = "Rom_Palace_01", char = "Black", spawn = 1, steps = {
    {when = "CoopStorySolo.G11abyssReady", testkick = "CoopStorySolo.G11testLegion", after = 15,
     call = "CoopStorySolo.G11cross", say = "s_abyss"},
    {when = "CoopStorySolo.G11cleared", testkick = "CoopStorySolo.G11testWave", rekick = true, after = 8, call = "CoopStorySolo.G11bridge", say = "s_bridgeopen", last = true},
  }},
  -- The kill is Church's (blood rune, first person): once this player broke free, the main
  -- line ends it.
  G15 = {level = "Sum_End", char = "Black", steps = {
    {after = 30, call = "EvilFirstBorn.SchMakeAllUnavailable", say = "s_bind"},
    {when = "CoopStorySolo.G15free", after = 60, call = "EvilFirstBorn.KillFirstBornScene", say = "s_fbkill", last = true},
  }},
  G7 = {level = "Cru_River", char = "Jones", patrol = true, steps = {
    {after = 25, call = "MapScenes.CrossOverBridge", say = "s_bridge"},
  }},
}

function SS.line()
  return cfg.storyline and SS.LINES[cfg.storyline]
end

-- The area trigger entity of a map callback ("MapCallbacks.AreaTrigger119_1" ->
-- "AreaTrigger119"), switched off.
function SS.triggerOff(call)
  local name = type(call) == "string" and string.match(call, "^MapCallbacks%.(AreaTrigger.-)_%d+$")
  local t = name and Game.GetEntity(name)
  if t then pcall(function() t.bActive = false end) end
end

function SS.resolve(path)
  local t = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return type(t) == "function" and t or nil
end

-- The line's checkpoint: its spawn point in the level's save vars, then the level once more.
function SS.atSpawn(line)
  if not line.spawn or cfg.storySpawned == cfg.storyline then return true end
  cfg.storySpawned = cfg.storyline
  local var = (init and init.LevelName or ("level." .. string.lower(line.level))) .. ".Spawn.Point"
  pcall(Game.CreateSaveVar, var, tostring(line.spawn))
  Game.SetSaveVar(var, tostring(line.spawn))
  Coop.log("story solo: " .. cfg.storyline .. " from spawn point " .. line.spawn)
  Coop.rearm()
  SaveGame.LoadLevel(line.level)
  return false
end

SS.seen = SS.seen or {}
SS.wrappers = SS.wrappers or {}
-- Marks a story function as run. Checked every frame: the split code may put its own
-- version of the same function in place later (G1A: StartSayGoodbye), then it is wrapped
-- again.
function SS.hookEvents(line)
  for _, st in ipairs(line.steps) do
    if st.on then
      local tname, fname = string.match(st.on, "^([%w_]+)%.([%w_]+)$")
      local tbl = _G[tname]
      local cur = tbl and tbl[fname]
      if type(cur) == "function" and cur ~= SS.wrappers[st.on] then
        local key = st.on
        local w = function(...)
          SS.seen[key] = true
          return cur(...)
        end
        SS.wrappers[key] = w
        tbl[fname] = w
      end
    end
  end
end

function SS.update()
  local line = SS.line()
  if not line or Coop.level == "levels/menu" then return end
  SS.sayUpdate()
  if line.patrol and cfg.storyPatrol then return SS.updatePatrol() end
  if Coop.level ~= "levels/" .. string.lower(line.level) then return end
  if not SS.started then
    if Coop.frame < 40 then return end
    if not SS.atSpawn(line) then SS.started = "reloading" return end
    -- after the level's opening scenes (Sum_End: TheEndA and B), in a body
    if (Scene and Scene.IsPlaying) or not Game.UsrEntity(0) then return end
    SS.started = true
    SS.step, SS.stepT = 1, Game.GetTime()
    SS.hookEvents(line)
    -- The level's area triggers that are the main line's steps run from here only: the AI
    -- squad walking about must not run them early (G1C: Omega's AI walked into two of them
    -- in the first 20 s and both waves came at once).
    for _, s2 in ipairs(line.steps) do SS.triggerOff(s2.call) end
    SS.say(SS.text(cfg.storyline), 12)
    Coop.log("story solo: " .. cfg.storyline .. " in " .. line.level .. " as " .. tostring(Coop.localChar()))
    if line.patrol then SS.installPatrol() end
  end
  if SS.started ~= true then return end
  if SS.finishAt and Game.GetTime() >= SS.finishAt then
    SS.finishAt = nil
    SS.say(SS.text("done"), 15)
    Coop.log("story solo: " .. cfg.storyline .. " done")
  end
  local st = line.steps[SS.step]
  if not st then return end
  if st.on then SS.hookEvents(line) end
  if Scene and Scene.IsPlaying then SS.stepT = Game.GetTime() return end   -- the clock waits for scenes
  if st.on and not SS.seen[st.on] then
    SS.stepT = Game.GetTime()
    -- Tests (dev, storykick = seconds): nobody walks to the trigger, the story runs it.
    SS.onSince = SS.onSince or Game.GetTime()
    if cfg.dev and cfg.storykick and not st.nokick and Game.GetTime() - SS.onSince > cfg.storykick then
      local fn = SS.resolve(st.on)
      SS.onSince = Game.GetTime() + 9999
      Coop.log("story solo: test kick " .. st.on .. (fn and "" or " (not found)"))
      if fn then pcall(fn) end
      SS.seen[st.on] = true
    end
    return
  end
  if st.when then
    local f = SS.resolve(st.when)
    if not (f and f()) then
      SS.stepT = Game.GetTime()
      -- Tests (dev, storykick): what the player would do to get there, done by the story.
      SS.whenSince = SS.whenSince or Game.GetTime()
      if cfg.dev and cfg.storykick and st.testkick and Game.GetTime() - SS.whenSince > cfg.storykick then
        SS.whenSince = st.rekick and Game.GetTime() or Game.GetTime() + 9999
        local k = SS.resolve(st.testkick)
        Coop.log("story solo: test kick " .. st.testkick .. (k and "" or " (not found)"))
        if k then pcall(k) end
      end
      return
    end
    SS.whenSince = nil
  end
  if st.after and Game.GetTime() - SS.stepT < st.after then return end
  SS.step, SS.stepT = SS.step + 1, Game.GetTime()
  if st.call then
    local fn = SS.resolve(st.call)
    Coop.log("story solo: step " .. (SS.step - 1) .. " " .. st.call .. (fn and "" or " (not found)"))
    if fn then
      local ok, err = pcall(fn, unpack(st.args or {}))
      if not ok then Coop.log("story solo: step error " .. tostring(err)) end
      SS.triggerOff(st.call)
    end
  end
  if st.say then SS.say(string.format(SS.text("main"), SS.text(st.say)), 8) end
  if st.last then SS.finishAt = Game.GetTime() + 60 end
end

-- G6: Church on the gate top: the sacrifice (the use object's callback; the object itself off,
-- or co-op's claims had the AI use it once more and the scenes played twice).
function SS.G6sacrifice()
  local t = Game.GetEntity("triggerUseChurch")
  if t then pcall(function() t.bArrowCanUse = false; t.bActive = false end) end
  SS.aiDoes("Church")
  MapCallbacks.triggerUseNaziSacrifice_0("Church", "triggerUseChurch", "Use", "")
end

-- G1C: Omega breaks through to the pocket (MapCallbacks.AreaTrigger119_1, each part on its
-- own: the explosive it wakes may be gone already, and the rest must still run).
function SS.G1Cthrough()
  Game.AddScheduledFunc(Game.GetTime() + 1, "", "PhysicsObj.OpenDoor", "primera_puerta_black")
  local x = Game.GetEntity("ExplosivoDePega")
  if x then x.bActive = true end
  pcall(NPC.ActivateEnemyGroup, "primer_explosivo")
  pcall(NPC.ActivateEnemyGroup, "primeros_cultistas_explosivos")
  pcall(MapInit.EnableAlpha)
  pcall(ObjFX.ActivateFX, "Debris_primera_puerta_black", 15)
  Game.AddScheduledFunc(Game.GetTime() + 1, "", "MapSoundFuncs.ScarySound")
  -- the split's own end of the pocket (it follows the trigger's callback)
  if CoopSplits and CoopSplits.G1C then
    CoopSplits.G1C.done = true
    if CoopSplits.setSides then CoopSplits.setSides(nil) end
    pcall(CoopSplits.radio, "Jones", "Rejoin_Team")
  end
  SS.triggerOff("MapCallbacks.AreaTrigger119_1")
end

-- G10: Delgado walks into the fire. The vanilla trigger takes whoever entered it: called by
-- the story it took the player, burned them (Life 0) and froze the controls ("Inactive").
-- Delgado walks it unharmed here (in co-op his player keeps the barrier up).
function SS.G10fire()
  AreaTriggers.FireAreaDamage = 15
  pcall(Team.ReviveAll)
  pcall(AreaTriggers.SetTeamsThere, V3D(-30732, -170, -4934))
  Game.DeleteScheduledFuncs("SchFireArea")
  pcall(Team.HoldPosMain)
  pcall(Team.HoldPosSide)
  local t = Game.GetEntity("AreaTrigger_Fire")
  if t then pcall(function() t.bActive = false end) end
end

-- G10: Delgado's first door, the vanilla use callback without its first-person use animation
-- (MakeFP.CoolUse plays it on the user's view model: for an AI Delgado the game crashed).
function SS.G10door1()
  local door = Game.GetEntity("puerta_delgado_1")
  if door then
    door.Action = "Open"
    door.bArrowCanUse = false
  end
  pcall(SaveGame.AutoSaveWaypoint, 1)
  pcall(NPC.ActivateEnemyGroup, "tercer_cultista_sorpresa")
  pcall(NPC.ActivateEnemyGroup, "happy_torturer")
  local e = Game.GetEntity("Enemy163")
  if e then e.FireRemainTime = 100 end
  Game.AddScheduledFunc(Game.GetTime() + Game.Rand(35, 45), "SchFireArea2", "MapInit.SchFireArea2")
  -- the hall's second wave (coop_splits.lua runs it after the door's own callback)
  if CoopSplits and CoopSplits.G10wave then pcall(CoopSplits.G10wave, 2) end
end

-- G11: the wave on Church's side is down; the plates and Church's own open the bridge.
function SS.G11cleared()
  return CoopSplits and CoopSplits.G11 and CoopSplits.G11.cleared and true or false
end

-- (the legion's last group down: vanilla makes the ledge usable)
function SS.G11abyssReady()
  local t = Game.GetEntity("TriggerTheAbyss")
  return t ~= nil and t.bActive == true and t.bArrowCanUse == true
end

-- An AI character's action played as a scene: its QTE passes by itself (coop_scenes.lua does
-- so for what co-op's claims had the AI do).
function SS.aiDoes(char)
  if CoopClaim and CoopClaim.aiDid then CoopClaim.aiDid[char] = true end
end

-- Church crosses the abyss (the ledge's use callback; the ledge itself off).
function SS.G11cross()
  SS.aiDoes("Church")
  local t = Game.GetEntity("TriggerTheAbyss")
  if t then pcall(function() t.bArrowCanUse = false end) end
  MapCallbacks.o249_0("Church", "TriggerTheAbyss", "Use", "")
end

-- (tests: the legion at the bridge down)
function SS.G11testLegion()
  for _, l in ipairs({"LegionariosPuente1", "LegionariosPuente2", "LegionariosPuente3", "LegionariosPuente4"}) do
    pcall(EnemyGen.Stop, l, true)
  end
  local t = Game.GetEntity("TriggerTheAbyss")
  if t then t.bActive, t.bArrowCanUse = true, true end
end

-- (tests: the wave on Church's side down)
function SS.G11testWave()
  if Legionary and Legionary.OnDamage and not SS.legionWrapped then
    SS.legionWrapped = true
    local orig = Legionary.OnDamage
    Legionary.OnDamage = function(name, ...)
      local e = Game.GetEntity(name)
      if e and e.uData and e.uData.CoopTestKill then return end
      return orig(name, ...)
    end
  end
  for _, n in ipairs(CoopSplits and CoopSplits.G11 and CoopSplits.G11.spawned or {}) do
    local e = Game.GetEntity(n)
    if e and (e.Life or 0) > 0 then
      Coop.log(string.format("story solo: G11 %s life=%s active=%s act=%s at %d,%d,%d", n, tostring(e.Life),
        tostring(e.bActive), tostring(e.Action), e.Pos.x, e.Pos.y, e.Pos.z))
      -- (vanilla Legionary.OnDamage gives the life back when the last hit was on the shield:
      -- the squad's AI shot at them, and Life = 0 did not stay)
      e.uData.CoopTestKill = true
      e.Invulnerable = 0; e.Life = 0
    end
  end
end

function SS.G11bridge()
  for _, n in ipairs({"LosetaPuenteA", "LosetaPuenteB", "LosetaPuenteC"}) do
    local e = Game.GetEntity(n)
    if e and e.uData then e.uData.Pulsed = true end
  end
  MapCallbacks.PressChurch_0(Game.GetEntity("LosetaPuenteA"))
end

-- G15: this player broke free of the rune once.
function SS.G15free()
  local me = Coop.localChar()
  if CoopSplits and CoopSplits.G15 and me and CoopSplits.G15.freed[me] then SS.g15free = true end
  return SS.g15free or false
end

-- G4: the soul is back; Church comes over and revives Rawlings (in co-op, a player does).
function SS.G4soulBack()
  return CoopSplits and CoopSplits.G4 and CoopSplits.G4.arrived and true or false
end

function SS.G4cure()
  local raw = Game.GetEntity("Rawlings")
  if not raw or raw.Life > 0 then return end
  for _, n in ipairs({"Church", "Black", "Jones", "Cole", "Delgado"}) do
    local e = Game.GetEntity(n)
    if e and e.Life > 0 and e.bActive ~= false then
      -- (Team.CurePlayer is a player's cure, of AI bodies only: the player's own body is
      -- revived as co-op revives a body its machine holds)
      Coop.notePos(n, "storysolo.raw")
      e.Pos = raw.Pos + V3D(80, 0, 0)
      pcall(Health.DoCure, n, "Rawlings")
      if CoopTeam then CoopTeam.holdDowned.Rawlings = nil end
      if CoopTeam and CoopTeam.reviveLocal then CoopTeam.reviveLocal(raw) end
      Coop.log("story solo: " .. n .. " revives Rawlings")
      return
    end
  end
end

------------------------------------------------------------------------------
-- The Lost Patrol alone: the main group's levels are simulated, the trio's segments run as
-- in co-op with this machine as their authority.
------------------------------------------------------------------------------
-- Where the main group is after each of the trio's segments, and how long a segment lasts.
SS.PATROL_MAIN = {"Cru_Sewers", "Cru_Catacomb", "Cru_Chapel"}
SS.PATROL_SECS = 300

-- The bridge scene's end sends the main group on to cru_labyrinth: here the trio stays.
function SS.installPatrol()
  if not MapScenes or SS.patrolHooked then return end
  SS.patrolHooked = true
  MapScenes.OnEnd_BridgeCollapses = function() SS.patrolSplit() end
end

-- The bridge fell: this machine becomes the trio's side instance and its authority.
function SS.patrolSplit()
  cfg.netRole, cfg.realId = cfg.netRole or cfg.role, cfg.realId or cfg.myId or 0
  cfg.inst, cfg.instAuth, cfg.instIds = "trio", cfg.realId, tostring(cfg.realId)
  cfg.role = "host"
  cfg.storyPatrol, cfg.storyPatrolT = 1, nil
  Coop.log("story solo: the Lost Patrol starts")
  if CoopPatrol and CoopPatrol.onSplit then pcall(CoopPatrol.onSplit) end
  CoopInst.loadLevel("Cru_River")
end

-- In the trio's levels: the simulated main group moves on every PATROL_SECS.
function SS.updatePatrol()
  local stage = cfg.storyPatrol
  if not stage or Coop.frame < 60 then return end
  if Scene and Scene.IsPlaying then return end
  SS.patrolT = SS.patrolT or Game.GetTime()
  if Game.GetTime() - SS.patrolT < (cfg.dev and cfg.patrolsecs or SS.PATROL_SECS) then return end
  SS.patrolT = Game.GetTime() + 9999   -- once per level
  local main = SS.PATROL_MAIN[stage]
  if not main then return end
  cfg.storyPatrol = stage + 1
  Coop.log("story solo: the main group reaches " .. main)
  if main == "Cru_Chapel" then
    -- The merge: back to one group in the chapel (the rescue scene).
    cfg.inst, cfg.instAuth, cfg.instIds, cfg.storyPatrol = nil, nil, nil, nil
    cfg.role = cfg.netRole or "host"
    SS.say(SS.text("s_merge"), 6)
    Coop.rearm()
    SaveGame.LoadLevel("Cru_Chapel")
  elseif CoopPatrol and CoopPatrol.sideMainLevel then
    CoopPatrol.sideMainLevel(main)
  end
end

-- Texts of the other languages (Coop.addLangs).
Coop.addLangs(SS.TEXT, "CoopStorySolo.TEXT")

return SS
