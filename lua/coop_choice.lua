-- Jericho co-op: the "choose your squad" screen at a story split (docs/split-choice.md, owner
-- bug 8, 0.2.8). ONE shared screen for every human player, the host included, shown before
-- the scene or split starts. Each player goes to the group he wants; several may go to the same
-- group or apart. Cards (group name, members, blurb, who picked it) are text rows; pad or arrow
-- keys move the highlight, A / Enter / the digit keys confirm; ~25 s; default = stay in the body
-- held now. The host resolves the picks and moves the players, then the split's own code runs
-- (what the old offers did for "who holds which body").
--   chs|<split>|<seconds>|<owners>      host -> all: the screen opens (owner ids in screen order)
--   chp|<split>|<group>|<1 confirmed>   player -> host: his highlight / confirmed pick
--   chst|<split>|owner:group:conf;...   host -> all: who points where (every change, 1/s)
--   chr|<split>|owner:char:reason;...   host -> all: the result (reason keep, moved, default, full, host)
--   chd|<split>                         host -> all: the choice is over with no screen (one player...)
--   chq|<split>                         client -> host: "is it decided?" (a held call asks every 2 s; answer chd)
-- A client holds the same calls the host holds (C.gate on both): whichever machine runs a split's
-- trigger, nothing starts until the host's result (chr/chd) has come and been read. `chp` carries the
-- OWNER id (a split screen's player 2 is another owner on the same machine).
-- A split's start is held on the host with CoopChoice.request(id, resume): `resume` runs when the
-- choice is over (at once with one human, or when no two groups can be chosen).
CoopChoice = CoopChoice or {}
local C = CoopChoice
local cfg = Coop.cfg

C.TIME = tonumber(cfg.choicetime) or 25
C.RESULT_HOLD = 3.5   -- seconds the explanation stays on a quiet screen before the split starts
-- Lost Patrol: the host's machine runs the main instance and cannot join the side one (the one
-- guarded condition; set false to let the host pick the trio too, docs/split-choice.md section 6).
C.HOST_PINNED_LP = true

C.DEFS = {
  G8 = {groups = {{key = "go", chars = {"Church"}}, {key = "stay", chars = {"Black", "Delgado"}}}},
  G10 = {groups = {{key = "go", chars = {"Delgado"}}, {key = "stay", chars = {"Black", "Church", "Cole", "Jones", "Rawlings"}}}},
  LP = {groups = {{key = "main", chars = {"Delgado", "Church", "Black"}}, {key = "trio", chars = {"Jones", "Cole", "Rawlings"}}},
        hostGroup = function() return C.HOST_PINNED_LP and 1 or nil end},
  -- 0.2.9 (docs/split-choice.md section 4). `inactive`: bodies the level keeps switched off until a
  -- player holds them (a card counts them, the move switches them on); `pinned`: bodies whose holder
  -- cannot leave (the story script needs them); `settle`: seconds of rest before the screen opens;
  -- `after`: run on every machine when the result is known (a split's hook is CoopSplits.afterChoice[id]).
  G6 = {groups = {{key = "sacrifice", chars = {"Church"}}, {key = "top", chars = {"Cole", "Rawlings"}},
                  {key = "base", chars = {"Jones", "Delgado", "Black"}}},
        inactive = {Cole = true, Rawlings = true}, settle = 3},
  G11 = {groups = {{key = "cross", chars = {"Church"}}, {key = "cover", chars = {"Black", "Cole", "Delgado", "Jones", "Rawlings"}}}},
  G15 = {groups = {{key = "kill", chars = {"Church"}}, {key = "bound", chars = {"Black", "Delgado", "Rawlings"}}}},
  G4 = {groups = {{key = "soul", chars = {"Rawlings"}}, {key = "defend", chars = {"Church", "Black", "Cole", "Delgado", "Jones"}}}},
  G1A = {groups = {{key = "omega", chars = {"Ross", "Church", "Black", "Rawlings"}}, {key = "alpha", chars = {"Jones", "Cole", "Delgado"}}},
         pinned = function() return {Ross = true} end, settle = 2},
  G1C = {groups = {{key = "omega", chars = {"Ross", "Church", "Black", "Rawlings"}}, {key = "alpha", chars = {"Jones", "Cole", "Delgado"}}},
         inactive = {Jones = true, Cole = true, Delgado = true}, pinned = function() return {Ross = true} end, settle = 2},
  G3 = {groups = {{key = "console", chars = {"Cole"}}, {key = "defend", chars = {"Ross", "Church", "Black", "Rawlings", "Jones", "Delgado"}}},
        pinned = function() return {Ross = true} end},
}

C.TEXT = {
  en = {
    hint = "Left / Right: choose   A or Enter: confirm   1 2 3: quick pick",
    wait = "Waiting for the others...",
    nobody = "nobody yet",
    ok = "(ok)",
    full = "That group was full: you stay as %s.",
    host = "The host's game runs the main group: you stay with it.",
    default = "No choice made: you stay as %s.",
    G8_title = "Church climbs on alone",
    G8_go_name = "THE CLIMB", G8_go_blurb = "Climb the shaft with Church. The descent is yours.",
    G8_stay_name = "HOLD THE GATE", G8_stay_blurb = "Hold the hall below against the Templars until the door opens.",
    G8_go_ex = "You climb with Church: the descent is yours.",
    G8_stay_ex = "You hold the gate below with Black and Delgado.",
    G10_title = "Delgado goes through the fire alone",
    G10_go_name = "THE FIRE", G10_go_blurb = "Cross the burning hall as Delgado and pull the lever.",
    G10_stay_name = "THE TORTURERS' HALL", G10_stay_blurb = "Hold the pinned hall against the cultists while Delgado crosses.",
    G10_go_ex = "You cross the fire as Delgado.",
    G10_stay_ex = "You hold the hall while Delgado crosses the fire.",
    LP_title = "The bridge is falling",
    LP_main_name = "THE MAIN GROUP", LP_main_blurb = "Fight on through the labyrinth and the sewers.",
    LP_trio_name = "THE LOST PATROL", LP_trio_blurb = "Wake in the blood river and fight your way to the chapel.",
    LP_main_ex = "You go on with the main group.",
    LP_trio_ex = "You stay with the lost patrol: Jones, Cole and Rawlings.",
    pinned = "You are %s: the story needs him, you go on with him.",
    pinnedhint = "Your character is fixed by the story. The others are choosing...",
    hint2 = "Player 2: pad 2 left / right and A",
    G6_title = "The Brandenburg Gate: where do you fight?",
    G6_sacrifice_name = "THE SACRIFICE",
    G6_sacrifice_blurb = "Church faces the sacrifice at the gate. The last scenes are his.",
    G6_sacrifice_ex = "You are Church: the sacrifice is yours.",
    G6_top_name = "THE GATE TOP",
    G6_top_blurb = "Cole and Rawlings guard the captive Lichthammer high above the fight.",
    G6_top_ex = "You stay on the gate top with the captive.",
    G6_base_name = "THE BASE",
    G6_base_blurb = "Fight through to the gate with the squad below.",
    G6_base_ex = "You fight on with the squad below.",
    G11_title = "Church crosses the abyss alone",
    G11_cross_name = "THE ABYSS",
    G11_cross_blurb = "Cross the abyss as Church and hold the far side against the legion.",
    G11_cross_ex = "You cross the abyss as Church.",
    G11_cover_name = "THE EDGE",
    G11_cover_blurb = "Cover Church from the edge. Jones can shut the legion door with the crank.",
    G11_cover_ex = "You cover Church from the edge.",
    G15_title = "The blood rune binds the squad",
    G15_kill_name = "THE KILL",
    G15_kill_blurb = "Church has to strike the First Born down.",
    G15_kill_ex = "You are Church: the kill is yours.",
    G15_bound_name = "BOUND BY THE RUNE",
    G15_bound_blurb = "Black, Delgado and Rawlings are bound. Hold E to break the link.",
    G15_bound_ex = "You are bound by the rune: hold E to break free.",
    G4_title = "Rawlings is shot: his soul is torn out",
    G4_soul_name = "THE PATH OF SOULS",
    G4_soul_blurb = "Walk Rawlings' soul back through three stations (hold E to pray).",
    G4_soul_ex = "You walk Rawlings' soul back to his body.",
    G4_defend_name = "DEFEND HIS BODY",
    G4_defend_blurb = "Hold the pillbox field against the Nazis until his soul is back.",
    G4_defend_ex = "You defend Rawlings' body.",
    G1A_title = "Alpha goes on a recon",
    G1A_omega_name = "OMEGA",
    G1A_omega_blurb = "Ross, Church, Black and Rawlings stay with the main team at the tomb.",
    G1A_omega_ex = "You stay with Omega.",
    G1A_alpha_name = "ALPHA: THE RECON",
    G1A_alpha_blurb = "Jones, Cole and Delgado scout the perimeter and hold against the cultists.",
    G1A_alpha_ex = "You go with Alpha on the recon.",
    G1C_title = "Alpha is pinned at the dig",
    G1C_omega_name = "OMEGA",
    G1C_omega_blurb = "Fight your way through the city toward Alpha.",
    G1C_omega_ex = "You fight through the city with Omega.",
    G1C_alpha_name = "ALPHA: PINNED DOWN",
    G1C_alpha_blurb = "Hold the sealed pocket against the cultists crawling out of the dig.",
    G1C_alpha_ex = "You hold the pocket with Alpha.",
    G3_title = "Temporal restoration",
    G3_console_name = "THE CONSOLE",
    G3_console_blurb = "Cole hacks the console. Stay beside it while the restoration runs.",
    G3_console_ex = "You hack the console as Cole.",
    G3_defend_name = "THE DEFENCE",
    G3_defend_blurb = "Defend Cole against the ambush while the restoration runs.",
    G3_defend_ex = "You defend the console.",
  },
  ru = {
    hint = "Влево / Вправо: выбор   A или Enter: подтвердить   1 2 3: быстрый выбор",
    wait = "Ждём остальных...",
    nobody = "пока никого",
    ok = "(ок)",
    full = "Эта группа заполнена: вы остаётесь: %s.",
    host = "Игра хоста ведёт основную группу: вы остаётесь с ней.",
    default = "Выбор не сделан: вы остаётесь: %s.",
    G8_title = "Чёрч идёт дальше один",
    G8_go_name = "ПОДЪЁМ", G8_go_blurb = "Поднимитесь по шахте с Чёрчем. Спуск за вами.",
    G8_stay_name = "УДЕРЖАТЬ ВОРОТА", G8_stay_blurb = "Держите зал внизу против тамплиеров, пока не откроется дверь.",
    G8_go_ex = "Вы поднимаетесь с Чёрчем: спуск за вами.",
    G8_stay_ex = "Вы держите ворота внизу вместе с Блэком и Дельгадо.",
    G10_title = "Дельгадо идёт через огонь один",
    G10_go_name = "ОГОНЬ", G10_go_blurb = "Пройдите через горящий зал за Дельгадо и потяните рычаг.",
    G10_stay_name = "ЗАЛ ПАЛАЧЕЙ", G10_stay_blurb = "Держите зал против культистов, пока Дельгадо идёт.",
    G10_go_ex = "Вы проходите через огонь за Дельгадо.",
    G10_stay_ex = "Вы держите зал, пока Дельгадо идёт через огонь.",
    LP_title = "Мост рушится",
    LP_main_name = "ОСНОВНАЯ ГРУППА", LP_main_blurb = "Пробивайтесь дальше через лабиринт и канализацию.",
    LP_trio_name = "ПОТЕРЯННЫЙ ПАТРУЛЬ", LP_trio_blurb = "Очнитесь в кровавой реке и пробейтесь к часовне.",
    LP_main_ex = "Вы идёте дальше с основной группой.",
    LP_trio_ex = "Вы остаётесь с потерянным патрулём: Джонс, Коул и Роулингс.",
    pinned = "Вы %s: он нужен сюжету, вы идёте с ним.",
    pinnedhint = "Ваш персонаж закреплён сюжетом. Остальные выбирают...",
    hint2 = "Игрок 2: геймпад 2, влево / вправо и A",
    G6_title = "Бранденбургские ворота: где вы сражаетесь?",
    G6_sacrifice_name = "ЖЕРТВОПРИНОШЕНИЕ",
    G6_sacrifice_blurb = "Чёрч идёт на жертву у ворот. Последние сцены его.",
    G6_sacrifice_ex = "Вы Чёрч: жертва за вами.",
    G6_top_name = "ВЕРХ ВОРОТ",
    G6_top_blurb = "Коул и Роулингс стерегут пленную Лихтхаммер высоко над боем.",
    G6_top_ex = "Вы остаётесь на верху ворот с пленницей.",
    G6_base_name = "ПОДНОЖИЕ",
    G6_base_blurb = "Прорывайтесь к воротам вместе с отрядом внизу.",
    G6_base_ex = "Вы идёте дальше с отрядом внизу.",
    G11_title = "Чёрч пересекает пропасть один",
    G11_cross_name = "ПРОПАСТЬ",
    G11_cross_blurb = "Пересеките пропасть за Чёрча и удержите дальний край против легиона.",
    G11_cross_ex = "Вы пересекаете пропасть за Чёрча.",
    G11_cover_name = "КРАЙ",
    G11_cover_blurb = "Прикрывайте Чёрча с края. Джонс может закрыть дверь легиона рукоятью.",
    G11_cover_ex = "Вы прикрываете Чёрча с края.",
    G15_title = "Кровавая руна связывает отряд",
    G15_kill_name = "УДАР",
    G15_kill_blurb = "Чёрч должен сразить Перворождённого.",
    G15_kill_ex = "Вы Чёрч: удар за вами.",
    G15_bound_name = "СВЯЗАННЫЕ РУНОЙ",
    G15_bound_blurb = "Блэк, Дельгадо и Роулингс связаны. Удерживайте E, чтобы разорвать связь.",
    G15_bound_ex = "Вы связаны руной: удерживайте E, чтобы освободиться.",
    G4_title = "Роулингса застрелили: его душу вырвали",
    G4_soul_name = "ПУТЬ ДУШ",
    G4_soul_blurb = "Проведите душу Роулингса назад через три станции (удерживайте E для молитвы).",
    G4_soul_ex = "Вы ведёте душу Роулингса назад к его телу.",
    G4_defend_name = "ЗАЩИТА ТЕЛА",
    G4_defend_blurb = "Держите поле с дотами против нацистов, пока его душа не вернётся.",
    G4_defend_ex = "Вы защищаете тело Роулингса.",
    G1A_title = "Альфа уходит в разведку",
    G1A_omega_name = "ОМЕГА",
    G1A_omega_blurb = "Росс, Чёрч, Блэк и Роулингс остаются с основной группой у гробницы.",
    G1A_omega_ex = "Вы остаётесь с Омегой.",
    G1A_alpha_name = "АЛЬФА: РАЗВЕДКА",
    G1A_alpha_blurb = "Джонс, Коул и Дельгадо разведывают периметр и держатся против культистов.",
    G1A_alpha_ex = "Вы идёте с Альфой в разведку.",
    G1C_title = "Альфа прижата у раскопа",
    G1C_omega_name = "ОМЕГА",
    G1C_omega_blurb = "Пробивайтесь через город к Альфе.",
    G1C_omega_ex = "Вы пробиваетесь через город с Омегой.",
    G1C_alpha_name = "АЛЬФА: В ЛОВУШКЕ",
    G1C_alpha_blurb = "Держите запертый карман против культистов, ползущих из раскопа.",
    G1C_alpha_ex = "Вы держите карман с Альфой.",
    G3_title = "Временное восстановление",
    G3_console_name = "КОНСОЛЬ",
    G3_console_blurb = "Коул взламывает консоль. Оставайтесь рядом, пока идёт восстановление.",
    G3_console_ex = "Вы взламываете консоль за Коул.",
    G3_defend_name = "ОБОРОНА",
    G3_defend_blurb = "Защищайте Коул от засады, пока идёт восстановление.",
    G3_defend_ex = "Вы защищаете консоль.",
  },
}

function C.text(key, ...)
  local lang = Coop.lang()
  local s = (C.TEXT[lang] or C.TEXT.en)[key] or C.TEXT.en[key] or key
  s = Coop.enc(s, lang)
  if select("#", ...) > 0 then s = string.format(s, ...) end
  return s
end

local function now() return Net.CoopTime() end

-- Owner id order: host first, clients as they joined, split screen players after them.
local function rank(id)
  if id == 0 then return 0 end
  if id < Coop.P2 then return id end
  return 100 + id
end

-- The session's human players: owner id -> the body held.
function C.humans()
  local list, body = {}, {}
  for name, owner in pairs(Coop.owners or {}) do
    if owner ~= nil then
      if not body[owner] then list[#list + 1] = owner end
      body[owner] = name
    end
  end
  table.sort(list, function(a, b) return rank(a) < rank(b) end)
  return list, body
end

local function groupIndexOf(def, char)
  for i, g in ipairs(def.groups) do
    for _, c in ipairs(g.chars) do if c == char then return i end end
  end
end

-- A body a player could move into: alive, on, not driven or taken by the story, not rune-bound.
local function usable(name, def)
  local e = Game.GetEntity(name)
  if not e or (e.Life or 0) <= 0 then return false end
  -- (a body the level keeps switched off, a prop until a player holds it: def.inactive names those)
  if e.Active == 0 or e.bActive == false then
    if not (def and def.inactive and def.inactive[name]) then return false end
  end
  if Coop.storyDriven and Coop.storyDriven[name] then return false end
  if CoopStory and CoopStory.taken and CoopStory.taken(name) then return false end
  if CoopSplits and CoopSplits.runeBound and CoopSplits.runeBound(name) then return false end
  return true
end

-- Groups a card can be shown for: some body of it is usable or held by a player.
function C.cards(def)
  local cards = {}
  for i, g in ipairs(def.groups) do
    local n = 0
    for _, c in ipairs(g.chars) do
      if usable(c, def) or Coop.owners[c] ~= nil then n = n + 1 end
    end
    if n > 0 then cards[#cards + 1] = i end
  end
  return cards
end

------------------------------------------------------------------------------
-- Host: hold a split's start, open the screen, resolve
------------------------------------------------------------------------------

-- Everything of one level/session: a level load builds a new Coop table (coop.lua), a session end
-- or a new one starts clean, so a replayed split never finds an old "done".
function C.reset(why)
  if C.scr then pcall(C.closeLocal) end
  C.done, C.pending, C.cur, C.result = {}, {}, nil, nil
  C.later = {}     -- queue of resumes {t, id, fn}: a second finish never overwrites the first
  C.held = {}      -- a client's held calls by split id
  C.coopRef = Coop
  if why then Coop.log("choice: reset (" .. why .. ")") end
end

-- Host: `resume` runs once the choice for split `id` is over (it may run at once).
function C.request(id, resume)
  if C.done[id] then if resume then resume() end return end
  if C.pending[id] then return end   -- the trigger fired again while the screen is up
  C.pending[id] = {resume = resume, since = now()}
  Coop.log("choice " .. id .. ": requested")
end

-- A wrapper for a split's entry (a MapCallbacks entry, Scene.PlayFP, a MapInit function...): the
-- first call is held until the choice is over, then runs with its own arguments; calls meanwhile
-- are dropped. Host and client both hold: the client's call (a replay of the host's callback) waits
-- for the host's chr/chd, so the two machines start the split together (`replayOnly`: map callbacks,
-- where a call by this machine's own player is no replay and goes through to its guard).
function C.gate(id, fn, when, replayOnly)
  return function(...)
    if not Coop.inSession() or C.done[id] then return fn(...) end
    -- (`when`: only a call that would really start the split opens the screen)
    if when and not when(...) then return fn(...) end
    local args = {n = select("#", ...), ...}
    -- (a held call runs later, outside the replay or host-replay it was made in: those flags go with it,
    -- also the world replay's "who triggered it")
    local replay, fromHost = Coop.replay, Coop.fromHost
    local W = CoopWorld
    local wr, wt, wu = W and W.replaying, W and W.replayTriggered, W and W.forUser
    local call = function()
      local r0, f0 = Coop.replay, Coop.fromHost
      local w0, t0, u0 = W and W.replaying, W and W.replayTriggered, W and W.forUser
      local origTrig = Game.GetTriggeredEntity
      Coop.replay, Coop.fromHost = replay, fromHost
      if W and wr then
        W.replaying, W.replayTriggered, W.forUser = wr, wt, wu
        Game.GetTriggeredEntity = function(eid) return W.replayTriggered or origTrig(eid) end
      end
      local res = {pcall(fn, unpack(args, 1, args.n))}
      Game.GetTriggeredEntity = origTrig
      Coop.replay, Coop.fromHost = r0, f0
      if W and wr then W.replaying, W.replayTriggered, W.forUser = w0, t0, u0 end
      if not res[1] then error(res[2], 0) end
      return unpack(res, 2)
    end
    if Coop.isHost() then
      if C.pending[id] then return end
      C.request(id, call)
    elseif Coop.isClient() and Coop.cfg.myId then
      -- (a map callback the client's own player triggers must reach the guard that tells the host: only
      -- the host's replayed calls are held)
      if replayOnly and not (Coop.replay or Coop.fromHost) then return fn(...) end
      if C.held[id] then return end
      C.held[id] = {fn = call, t = now()}
      Coop.log("choice " .. id .. ": call held until the host's result")
    else
      return fn(...)
    end
  end
end

-- Client: the host says split `id` is decided (`hold`: seconds the explanation stays up first).
function C.clientDone(id, hold)
  C.done[id] = true
  local h = C.held[id]
  C.held[id] = nil
  if h then C.later[#C.later + 1] = {t = now() + hold, id = id, fn = h.fn} end
end

local function finish(id, result)
  local p = C.pending[id]
  C.pending[id] = nil
  C.done[id] = true
  C.cur = nil
  C.result = result
  -- (a client holds the same call: told that nothing is to be read, it goes on at once)
  if not result and Coop.inSession() then Net.CoopSend(-1, 1, "chd|" .. id) end
  if p and p.resume then
    -- (after the explanation was read; at once when no screen was shown)
    C.later[#C.later + 1] = {t = result and now() + C.RESULT_HOLD or 0, id = id, fn = p.resume}
    C.runLater()
  end
end

function C.runLater()
  local q = C.later
  while q[1] and now() >= q[1].t do
    local l = table.remove(q, 1)
    local ok, err = pcall(l.fn)
    if not ok then Coop.log("choice " .. l.id .. ": resume error: " .. tostring(err)) end
  end
end

-- Host, 20 Hz: open a requested screen when the squad is at rest (no cutscene, no black curtain).
function C.hostUpdate()
  local cur = C.cur
  if not cur then
    for id, p in pairs(C.pending) do
      local def = C.DEFS[id]
      local rest = not (Scene and Scene.IsPlaying) and not (CoopEnemies and (CoopEnemies.curtain or CoopEnemies.fpBlackT))
      -- (everybody is in the level: a screen sent to a machine that is still loading is lost)
      if rest and CoopEnemies and CoopEnemies.gateOpen and not CoopEnemies.gateOpen() then rest = false end
      -- (some seconds at rest first: at a level's start the other machines claim their bodies)
      if not rest then p.restT = nil elseif not p.restT then p.restT = now() end
      local settled = p.restT and now() - p.restT >= ((def and def.settle) or 0)
      if not def or cfg.storyline or cfg.choice == "skip" then
        finish(id, nil)
      elseif settled or now() - p.since > 60 then
        C.start(id)
      end
      break
    end
    return
  end
  -- players who left
  local humans = C.humans()
  local have = {}
  for _, h in ipairs(humans) do have[h] = true end
  for i = #cur.humans, 1, -1 do
    local h = cur.humans[i]
    if not have[h] then
      table.remove(cur.humans, i)
      cur.picks[h] = nil
      cur.dirty = true
      Coop.log("choice " .. cur.id .. ": player " .. h .. " left")
    end
  end
  local all = #cur.humans > 0
  for _, h in ipairs(cur.humans) do
    if not (cur.picks[h] and cur.picks[h].conf) then all = false end
  end
  if cur.dirty or now() - (cur.sentT or 0) >= 1 then C.sendState() end
  if all or now() >= cur.untilT or #cur.humans == 0 then C.resolve() end
end

function C.start(id)
  local def = C.DEFS[id]
  local humans, body = C.humans()
  local cards = C.cards(def)
  if #humans < 2 or #cards < 2 then
    Coop.log("choice " .. id .. ": nothing to choose (" .. #humans .. " players, " .. #cards .. " groups)")
    finish(id, nil)
    return
  end
  local cur = {id = id, untilT = now() + C.TIME, humans = humans, picks = {}, cards = cards, seq = 0, pinned = {}}
  local pins = def.pinned and def.pinned() or {}
  local pinList = {}
  for _, h in ipairs(humans) do
    cur.picks[h] = {g = groupIndexOf(def, body[h]) or cards[1], conf = false, t = 0}
    -- (the holder of a body the story script needs: his card is fixed, he only watches the others pick)
    if pins[body[h]] then
      cur.pinned[h] = true
      cur.picks[h].conf = true
      pinList[#pinList + 1] = h
    end
  end
  C.cur = cur
  Net.CoopSend(-1, 1, "chs|" .. id .. "|" .. C.TIME .. "|" .. table.concat(humans, ",") .. "|" .. table.concat(pinList, ",") .. "|" .. table.concat(cards, ","))
  C.openLocal(id, C.TIME, humans, cards)
  if C.scr then C.scr.pinned = cur.pinned end
  C.sendState()
  Coop.log("choice " .. id .. ": screen open, " .. #humans .. " players")
end

function C.sendState()
  local cur = C.cur
  if not cur then return end
  local t = {}
  for _, h in ipairs(cur.humans) do
    local p = cur.picks[h]
    t[#t + 1] = h .. ":" .. p.g .. ":" .. (p.conf and 1 or 0)
  end
  cur.sentT, cur.dirty = now(), false
  Net.CoopSend(-1, 1, "chst|" .. cur.id .. "|" .. table.concat(t, ";"))
  C.applyState(cur.id, table.concat(t, ";"))
end

-- Host: a player's highlight or confirmed pick.
function C.setPick(owner, g, conf)
  local cur = C.cur
  if not cur or not cur.picks[owner] or cur.pinned[owner] then return end
  local p = cur.picks[owner]
  local ok = false
  for _, c in ipairs(cur.cards) do if c == g then ok = true end end
  if not ok then return end
  if p.conf and p.g == g and conf then return end
  p.g = g
  Coop.log("choice " .. cur.id .. ": owner " .. owner .. " " .. (conf and "confirms" or "points at") .. " card " .. g)
  if conf and not p.conf then C.seq = (C.seq or 0) + 1; p.t = C.seq end
  p.conf = conf and true or false
  cur.dirty = true
end

-- Host: every pick resolved into moves, applied, announced.
function C.resolve()
  local cur = C.cur
  if not cur then return end
  local def, id = C.DEFS[cur.id], cur.id
  local humans, body = C.humans()
  -- the order: confirmed picks first (by time), then by seat
  local order = {}
  for _, h in ipairs(cur.humans) do order[#order + 1] = h end
  table.sort(order, function(a, b)
    local pa, pb = cur.picks[a], cur.picks[b]
    if pa.conf ~= pb.conf then return pa.conf end
    if pa.conf and pa.t ~= pb.t then return pa.t < pb.t end
    return rank(a) < rank(b)
  end)
  local want, reason, move = {}, {}, {}
  local hostGroup = def.hostGroup and def.hostGroup()
  for _, h in ipairs(order) do
    local g = cur.picks[h].g
    reason[h] = cur.pinned[h] and "pinned" or (cur.picks[h].conf and "keep" or "default")
    if hostGroup and h == 0 and g ~= hostGroup then g = hostGroup; reason[h] = "host" end
    want[h] = g
  end
  -- keepers: a body already in the wanted group
  local keeps, leavers = {}, {}
  for _, h in ipairs(order) do
    if groupIndexOf(def, body[h]) == want[h] then keeps[body[h]] = h else leavers[#leavers + 1] = h end
  end
  -- movers take a free body of the group (not held by a keeper, not already given)
  local given, leaving = {}, {}
  for _, h in ipairs(leavers) do leaving[body[h]] = h end
  local function pick(h, preferFree)
    for _, c in ipairs(def.groups[want[h]].chars) do
      local holder = Coop.owners[c]
      local free = holder == nil or (leaving[c] and not preferFree)
      if free and not keeps[c] and not given[c] and usable(c, def) then return c end
    end
  end
  for _, h in ipairs(leavers) do
    local target = pick(h, true) or pick(h, false)
    if target then
      given[target] = h
      move[h] = target
      reason[h] = reason[h] == "host" and "host" or "moved"
    else
      reason[h] = reason[h] == "host" and "host" or "full"
    end
  end
  -- a moved body's old holder must really leave it: a mover whose target is held by a leaver that
  -- got no body keeps the target's holder in place: both stay (cycle without a spare body)
  local changed = true
  while changed do
    changed = false
    for h, target in pairs(move) do
      local holder = Coop.owners[target]
      if holder ~= nil and holder ~= h and not move[holder] then
        move[h] = nil
        reason[h] = "full"
        changed = true
      end
    end
  end
  -- apply: owners rewritten at once, the holders told (evict) before the table goes out
  local lines = {}
  local from = {}
  for h, target in pairs(move) do from[h] = body[h]; Coop.owners[body[h]] = nil end
  for h, target in pairs(move) do Coop.owners[target] = h end
  local localMoves = {}
  for h, target in pairs(move) do
    Coop.log("choice " .. id .. ": player " .. h .. " " .. from[h] .. " -> " .. target)
    if Coop.isMine(h) then
      localMoves[#localMoves + 1] = {h, from[h], target}
    else
      -- (a body the level keeps switched off is switched on for its new player: the 4th field)
      Net.CoopSend(Coop.peerOf(h), 1, "evict|" .. from[h] .. "|" .. target .. ((def.inactive and def.inactive[target]) and "|a" or ""))
    end
  end
  Coop.broadcastOwners()
  for _, m in ipairs(localMoves) do C.moveLocal(m[1], m[2], m[3], def) end
  local final = {}
  for _, h in ipairs(order) do
    local char = move[h] or body[h] or "-"
    final[h] = char
    lines[#lines + 1] = h .. ":" .. char .. ":" .. (reason[h] or "keep")
  end
  Net.CoopSend(-1, 1, "chr|" .. id .. "|" .. table.concat(lines, ";"))
  C.onResult(id, table.concat(lines, ";"))
  Coop.log("choice " .. id .. ": result " .. table.concat(lines, " "))
  finish(id, {move = move, want = want, final = final})
end

-- This machine's own player moves into `to` (the host's player, or its split screen player).
function C.moveLocal(owner, old, to, def)
  if owner == 0 then
    if Team and Team.SwitchSoldier then
      Coop.cfg.char = to
      C.enter(old, to, def and def.inactive and def.inactive[to])
    end
  elseif CoopSplit and CoopSplit.on and CoopSplit.char == old and CoopSplit.moveOut then
    CoopSplit.moveOut(to)
  end
end

-- Switch into `to` although the game keeps it unavailable (a tutorial lock, or a body it switched off).
function C.enter(old, to, activate)
  local locks = Team.UnavaliablePlayers
  local was = locks and locks[to]
  if locks then locks[to] = nil end
  local e = Game.GetEntity(to)
  if activate and e and e.bActive == false then e.bActive = true end
  local ok, res = pcall(Team.SwitchSoldier, old, to)
  if locks then locks[to] = was end
  if not ok then Coop.log("choice: switch " .. tostring(old) .. " -> " .. tostring(to) .. " failed: " .. tostring(res)) end
  return ok and res
end

------------------------------------------------------------------------------
-- Every machine: the screen
------------------------------------------------------------------------------

function C.openLocal(id, secs, humans, cards)
  local def = C.DEFS[id]
  if not def then return end
  -- (the host's list of cards when it sent one: every machine shows the cards the host resolves with)
  cards = cards or C.cards(def)
  if #cards < 1 then return end
  -- this machine's players: its own (keyboard and pad 1) and its split screen player (pad 2 only)
  local locals = {}
  for _, h in ipairs(humans) do
    if Coop.isMine(h) then locals[#locals + 1] = {owner = h, pad = h >= Coop.P2 and 1 or 0, conf = false, keys = {}} end
  end
  C.scr = {id = id, untilT = now() + (tonumber(secs) or C.TIME), humans = humans, cards = cards, state = {},
           locals = locals, mine = locals[1] and locals[1].owner or Coop.myId(), locked = {}}
  C.lockBodies(true)
  if Scorer and Scorer.Fade then pcall(Scorer.Fade, 0, Color(0, 0, 0, 0), Color(0, 0, 0, 120), 0.3) end
  Coop.log("choice " .. id .. ": screen, " .. #locals .. " local player(s)")
end

function C.closeLocal()
  local s = C.scr
  if not s then return end
  C.scr = nil
  C.lockBodies(false, s)
  if Scorer and Scorer.Fade then pcall(Scorer.Fade, 0, Color(0, 0, 0, 120), Color(0, 0, 0, 0), 0.4) end
  Coop.textBlockHide("CoopChoice")
  Coop.textBlockHide("CoopChoiceHint")
  for k = 1, 3 do Coop.textBlockHide("CoopChoiceCard" .. k) end
end

-- The stick, Enter and the arrows are in use: this player's bodies stand still and cannot be hurt.
function C.lockBodies(on, s)
  if on then
    local names = {}
    local usr = Game.UsrEntity(0)
    if usr then names[#names + 1] = usr.Name end
    if CoopSplit and CoopSplit.on and CoopSplit.char then names[#names + 1] = CoopSplit.char end
    C.scr.locked = {}
    for _, n in ipairs(names) do
      local e = Game.GetEntity(n)
      if e then
        C.scr.locked[n] = {ign = e.IgnoreUsrControl, inv = e.Invulnerable}
        e.IgnoreUsrControl = 1
        e.InCtrl_Walk, e.InCtrl_Str = 0, 0
        e.Invulnerable = 1
      end
    end
  elseif s then
    for n, was in pairs(s.locked or {}) do
      local e = Game.GetEntity(n)
      if e then e.IgnoreUsrControl = was.ign or 0; e.Invulnerable = was.inv or 0 end
    end
    -- (a body moved into since: its lock goes too)
    local usr = Game.UsrEntity(0)
    if usr and not (s.locked or {})[usr.Name] then usr.IgnoreUsrControl = 0 end
  end
end

function C.applyState(id, text)
  local s = C.scr
  if not s or s.id ~= id then return end
  local st = {}
  for owner, g, conf in string.gmatch(text or "", "(%d+):(%d+):(%d)") do
    st[tonumber(owner)] = {g = tonumber(g), conf = conf == "1"}
  end
  s.state = st
  for _, L in ipairs(s.locals) do
    local mine = st[L.owner]
    if mine and not L.cursor then L.cursor = mine.g end
  end
end

function C.onResult(id, text)
  local s = C.scr
  local def = C.DEFS[id]
  local lines = {}
  for owner, char, reason in string.gmatch(text or "", "(%d+):([%w_%-]+):(%a+)") do
    if def and Coop.isMine(tonumber(owner)) then
      local gi = groupIndexOf(def, char) or 1
      local line
      if reason == "full" then line = C.text("full", Coop.charName(char))
      elseif reason == "host" then line = C.text("host")
      elseif reason == "pinned" then line = C.text("pinned", Coop.charName(char))
      elseif reason == "default" then line = C.text("default", Coop.charName(char)) .. " " .. C.text(id .. "_" .. def.groups[gi].key .. "_ex")
      else line = C.text(id .. "_" .. def.groups[gi].key .. "_ex") end
      lines[#lines + 1] = line
    end
  end
  if id then C.clientAfter(id) end
  local line = table.concat(lines, "\n")
  if #lines > 0 then
    Coop.log("choice " .. id .. ": " .. string.gsub(line, "\n", " | "))
    if s then
      -- the cards go, the explanation stays a moment (the bodies stay locked until then)
      s.result = {text = line, untilT = now() + C.RESULT_HOLD}
      return
    end
    pcall(Scorer.SetMsgText, line, Game.GetTime() + 6)
  end
  C.closeLocal()
end

-- Every machine, when the result is known and the owner table is current: the split's own code
-- (def.after) re-reads who holds which body (G6's gate top, ...).
function C.clientAfter(id)
  local def = C.DEFS[id]
  -- (coop_splits.lua loads before this file: its hooks are looked up by name, not stored in DEFS)
  local after = (def and def.after) or (CoopSplits and CoopSplits.afterChoice and CoopSplits.afterChoice[id])
  if after then
    local ok, err = pcall(after, id)
    if not ok then Coop.log("choice " .. id .. ": after error: " .. tostring(err)) end
  end
end

local function padButtons(n)
  local pad = {pcall(Net.CoopKey, -1, n)}
  if not pad[1] or pad[2] == nil then return nil end
  return tonumber(pad[2]) or 0, tonumber(pad[5]) or 0
end

local function bit(v, n) return math.floor(v / n) % 2 == 1 end

-- Which input edges happened this tick for local player `L`: left, right, confirm, digit. The keyboard
-- (arrows, Enter, digits) and pad 1 belong to the first player; the split screen player 2 has pad 2 only.
function C.readInput(L)
  local down = {}
  if L.pad == 0 and Net.CoopKey then
    down.left = Net.CoopKey(0x25) == 1
    down.right = Net.CoopKey(0x27) == 1
    down.confirm = Net.CoopKey(0x0D) == 1
    for d = 1, 3 do down["d" .. d] = Net.CoopKey(0x30 + d) == 1 end
  end
  local b, lx = padButtons(L.pad)
  if b then
    down.left = down.left or bit(b, 4) or lx < -16000
    down.right = down.right or bit(b, 8) or lx > 16000
    down.confirm = down.confirm or bit(b, 4096)
  end
  local edges = {}
  for k, v in pairs(down) do
    if v and not L.keys[k] then edges[#edges + 1] = k end
    L.keys[k] = v
  end
  if #edges > 0 and Coop.cfg.dev then Coop.log("choice: player " .. L.owner .. " pad " .. L.pad .. " input " .. table.concat(edges, ",") .. " buttons=" .. tostring(b)) end
  for _, k in ipairs(L.injected or {}) do edges[#edges + 1] = k end
  L.injected = nil
  return edges
end

-- Tests and bots: press a key by name (left, right, confirm, d1..d3) for local player n (1 or 2).
function C.press(key, n)
  local L = C.scr and C.scr.locals[n or 1]
  if not L then return 0 end
  L.injected = L.injected or {}
  L.injected[#L.injected + 1] = key
  return #L.injected
end

function C.send(s, L, g, conf)
  if Coop.isHost() then C.setPick(L.owner, g, conf)
  else Net.CoopSend(0, 1, "chp|" .. s.id .. "|" .. g .. "|" .. (conf and 1 or 0) .. "|" .. L.owner) end
  -- (shown at once; the host's state message corrects it)
  s.state[L.owner] = {g = g, conf = conf}
end

function C.step(s, L, dir)
  local at = 1
  for i, g in ipairs(s.cards) do if g == L.cursor then at = i end end
  L.cursor = s.cards[(at - 1 + dir) % #s.cards + 1]
  L.conf = false
  C.send(s, L, L.cursor, false)
end

-- Text width: in split screen the HUD is drawn into one viewport, a narrower strip of the screen.
function C.width()
  return (CoopSplit and CoopSplit.on) and 400 or 560
end

function C.localUpdate()
  local s = C.scr
  if not s then return end
  if s.result then
    for k = 1, 3 do Coop.textBlockHide("CoopChoiceCard" .. k) end
    Coop.textBlockHide("CoopChoiceHint")
    Coop.textBlock("CoopChoice", s.result.text, {y = 190, color = Color(255, 230, 130, 255), width = C.width()})
    if now() >= s.result.untilT then C.closeLocal() end
    return
  end
  local menu = Input.GetActionSet and Input.GetActionSet() == "Menu"
  for n, L in ipairs(s.locals) do
    if not menu and not (s.pinned and s.pinned[L.owner]) then
      for _, e in ipairs(C.readInput(L)) do
        if e == "left" then C.step(s, L, -1)
        elseif e == "right" then C.step(s, L, 1)
        elseif e == "confirm" and L.cursor then L.conf = true; C.send(s, L, L.cursor, true)
        elseif string.match(e, "^d%d$") then
          local g = s.cards[tonumber(string.sub(e, 2))]
          if g then L.cursor = g; L.conf = true; C.send(s, L, g, true) end
        end
      end
    end
    -- tests: confirm this card after 2 s (cfg.choice for the first player, cfg.choice2 for the second;
    -- cfg.lpchoice for the Lost Patrol)
    local auto = (n == 1 and (cfg.choice or (s.id == "LP" and cfg.lpchoice))) or (n == 2 and cfg.choice2)
    if auto and not L.autoDone and now() > s.untilT - C.TIME + 2 and not (s.pinned and s.pinned[L.owner]) then
      L.autoDone = true
      local g = s.cards[tonumber(auto)]
      if g then L.cursor = g; L.conf = true; C.send(s, L, g, true) end
    end
  end
  C.draw(s)
end

local nickCache
local function nick(owner)
  if not nickCache or Coop.frame % 20 == 0 then nickCache = CoopHud and CoopHud.nicks and CoopHud.nicks() or {} end
  local n = nickCache[owner]
  if n and n ~= "" then return n end
  return owner == 0 and "Host" or ("P" .. owner)
end

-- Number of rows a text takes in a block of this width (Coop.textBlock breaks the same way).
function C.rows(text, width)
  local n = 0
  for part in string.gmatch(text .. "\n", "([^\n]*)\n") do
    local k = 1
    if Scorer.SplitString and part ~= "" then
      local ok, r = pcall(Scorer.SplitString, part, (Menu and Menu.SmallFont) or "ScrapMedium", width)
      if ok and type(r) == "table" and #r > 0 then k = #r end
    end
    n = n + k
  end
  return n
end

function C.draw(s)
  local def = C.DEFS[s.id]
  local left = math.max(0, math.ceil(s.untilT - now()))
  local width = C.width()
  Coop.textBlock("CoopChoice", C.text(s.id .. "_title") .. "  (" .. left .. ")", {y = 24, color = Color(255, 220, 160, 255), width = width})
  -- the cards stack by their real height (a narrow screen wraps more rows)
  local y = 24 + 22 * C.rows(C.text(s.id .. "_title") .. "  (00)", width) + 8
  for k, gi in ipairs(s.cards) do
    local g = def.groups[gi]
    local names = {}
    for _, c in ipairs(g.chars) do names[#names + 1] = Coop.charName(c) end
    local who = {}
    for _, h in ipairs(s.humans) do
      local p = s.state[h]
      if p and p.g == gi then who[#who + 1] = nick(h) .. (p.conf and (" " .. C.text("ok")) or "") end
    end
    local here = false
    for _, L in ipairs(s.locals) do
      local mine = s.state[L.owner]
      if (mine and mine.g == gi) or L.cursor == gi then here = true end
    end
    local text = (here and "> " or "  ") .. k .. "  " .. C.text(s.id .. "_" .. g.key .. "_name") .. ":  " .. table.concat(names, ", ") .. "\n"
      .. C.text(s.id .. "_" .. g.key .. "_blurb") .. "\n"
      .. (#who > 0 and table.concat(who, ", ") or C.text("nobody"))
    local color = here and Color(255, 230, 130, 255) or Color(190, 190, 190, 255)
    Coop.textBlock("CoopChoiceCard" .. k, text, {y = y, color = color, width = width, step = 22})
    y = y + 22 * C.rows(text, width) + 10
  end
  local mine = s.locals[1] and s.state[s.locals[1].owner]
  local hint = (mine and mine.conf) and C.text("wait") or C.text("hint")
  if s.locals[1] and s.pinned and s.pinned[s.locals[1].owner] then hint = C.text("pinnedhint") end
  if s.locals[2] then hint = hint .. "\n" .. C.text("hint2") end
  Coop.textBlock("CoopChoiceHint", hint, {y = y, color = Color(210, 215, 225, 255), width = width, step = 22})
end

------------------------------------------------------------------------------
-- Messages and the tick
------------------------------------------------------------------------------

function C.onMessage(peer, f)
  local kind = f[1]
  if kind == "chs" and Coop.isClient() then
    local humans = {}
    for h in string.gmatch(f[4] or "", "%d+") do humans[#humans + 1] = tonumber(h) end
    local cards = {}
    for g in string.gmatch(f[6] or "", "%d+") do cards[#cards + 1] = tonumber(g) end
    if not C.scr and not C.done[f[2]] then
      C.openLocal(f[2], f[3], humans, #cards > 0 and cards or nil)
      for h in string.gmatch(f[5] or "", "%d+") do
        C.scr.pinned = C.scr.pinned or {}
        C.scr.pinned[tonumber(h)] = true
      end
    end
    return true
  elseif kind == "chst" and Coop.isClient() then
    C.applyState(f[2], f[3])
    return true
  elseif kind == "chr" and Coop.isClient() then
    C.onResult(f[2], f[3])
    C.clientDone(f[2], C.RESULT_HOLD)
    return true
  elseif kind == "chd" and Coop.isClient() then
    C.clientDone(f[2], 0)
    return true
  elseif kind == "chq" and Coop.isHost() then
    -- (decided, and the explanation no longer on screen)
    local queued = false
    for _, l in ipairs(C.later) do if l.id == f[2] then queued = true end end
    if C.done[f[2]] and not queued and not (C.cur and C.cur.id == f[2]) then Net.CoopSend(peer, 1, "chd|" .. f[2]) end
    return true
  elseif kind == "chp" and Coop.isHost() then
    -- (the sender's own players only: the machine's player or its split screen player)
    local owner = tonumber(f[5])
    if not owner or Coop.peerOf(owner) ~= peer then owner = peer end
    C.setPick(owner, tonumber(f[3]) or 0, f[4] == "1")
    return true
  end
  return false
end

function C.update()
  local inSession = Coop.inSession() and Coop.level ~= "levels/menu"
  -- (a level load builds a new Coop table, a session end or a new session starts clean)
  if C.coopRef ~= Coop or (C.wasIn and not inSession) then C.reset("level or session change") end
  C.wasIn = inSession
  if not inSession then
    if C.scr then C.closeLocal() end
    return
  end
  if Coop.isHost() then C.hostUpdate() end
  C.runLater()
  C.heldCheck()
  C.localUpdate()
  -- a screen the host never closed (its game went away): back to play after a while
  if C.scr and now() > C.scr.untilT + 8 then C.closeLocal() end
end

-- Client: a call held for a result that never came (the host's game went away) runs after a while.
function C.heldCheck()
  for id, h in pairs(C.held or {}) do
    -- (the screen's own length when one is up here: the host may have set another time)
    local limit = (C.scr and C.scr.id == id) and (C.scr.untilT - h.t) or C.TIME
    if now() - h.t > math.max(C.TIME, limit) + 12 then
      Coop.log("choice " .. id .. ": no result from the host, the held call runs")
      C.clientDone(id, 0)
    elseif now() - (h.q or 0) >= 2 then
      -- (a client that loaded after the host had decided never saw its chr/chd: asks)
      h.q = now()
      Net.CoopSend(0, 1, "chq|" .. id)
    end
  end
end

C.reset()
Coop.addLangs(C.TEXT, "CoopChoice.TEXT")
