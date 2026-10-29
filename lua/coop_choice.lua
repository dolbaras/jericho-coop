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
local function usable(name)
  local e = Game.GetEntity(name)
  if not e or (e.Life or 0) <= 0 or e.Active == 0 or e.bActive == false then return false end
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
      if usable(c) or Coop.owners[c] ~= nil then n = n + 1 end
    end
    if n > 0 then cards[#cards + 1] = i end
  end
  return cards
end

------------------------------------------------------------------------------
-- Host: hold a split's start, open the screen, resolve
------------------------------------------------------------------------------

C.done, C.pending = {}, {}

-- Host: `resume` runs once the choice for split `id` is over (it may run at once).
function C.request(id, resume)
  if C.done[id] then if resume then resume() end return end
  if C.pending[id] then return end   -- the trigger fired again while the screen is up
  C.pending[id] = {resume = resume, since = now()}
  Coop.log("choice " .. id .. ": requested")
end

-- A wrapper for a split's entry (a MapCallbacks entry, Scene.PlayFP...): the first call is held
-- until the choice is over, then runs with its own arguments; calls meanwhile are dropped.
function C.gate(id, fn, when)
  return function(...)
    if not Coop.isHost() or not Coop.inSession() or C.done[id] then return fn(...) end
    -- (`when`: only a call that would really start the split opens the screen)
    if when and not when(...) then return fn(...) end
    local args = {n = select("#", ...), ...}
    if C.pending[id] then return end
    C.request(id, function() return fn(unpack(args, 1, args.n)) end)
  end
end

local function finish(id, result)
  local p = C.pending[id]
  C.pending[id] = nil
  C.done[id] = true
  C.cur = nil
  C.result = result
  if p and p.resume then
    -- (after the explanation was read; at once when no screen was shown)
    C.later = {t = result and now() + C.RESULT_HOLD or 0, id = id, fn = p.resume}
    C.runLater()
  end
end

function C.runLater()
  local l = C.later
  if not l or now() < l.t then return end
  C.later = nil
  local ok, err = pcall(l.fn)
  if not ok then Coop.log("choice " .. l.id .. ": resume error: " .. tostring(err)) end
end

-- Host, 20 Hz: open a requested screen when the squad is at rest (no cutscene, no black curtain).
function C.hostUpdate()
  local cur = C.cur
  if not cur then
    for id, p in pairs(C.pending) do
      local def = C.DEFS[id]
      local rest = not (Scene and Scene.IsPlaying) and not (CoopEnemies and (CoopEnemies.curtain or CoopEnemies.fpBlackT))
      if not def or cfg.storyline or cfg.choice == "skip" then
        finish(id, nil)
      elseif rest or now() - p.since > 60 then
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
  local cur = {id = id, untilT = now() + C.TIME, humans = humans, picks = {}, cards = cards, seq = 0}
  for _, h in ipairs(humans) do
    cur.picks[h] = {g = groupIndexOf(def, body[h]) or cards[1], conf = false, t = 0}
  end
  C.cur = cur
  Net.CoopSend(-1, 1, "chs|" .. id .. "|" .. C.TIME .. "|" .. table.concat(humans, ","))
  C.openLocal(id, C.TIME, humans)
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
  if not cur or not cur.picks[owner] then return end
  local p = cur.picks[owner]
  local ok = false
  for _, c in ipairs(cur.cards) do if c == g then ok = true end end
  if not ok then return end
  if p.conf and p.g == g and conf then return end
  p.g = g
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
    reason[h] = cur.picks[h].conf and "keep" or "default"
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
      if free and not keeps[c] and not given[c] and usable(c) then return c end
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
      Net.CoopSend(Coop.peerOf(h), 1, "evict|" .. from[h] .. "|" .. target)
    end
  end
  Coop.broadcastOwners()
  for _, m in ipairs(localMoves) do C.moveLocal(m[1], m[2], m[3]) end
  for _, h in ipairs(order) do
    local char = move[h] or body[h] or "-"
    lines[#lines + 1] = h .. ":" .. char .. ":" .. (reason[h] or "keep")
  end
  Net.CoopSend(-1, 1, "chr|" .. id .. "|" .. table.concat(lines, ";"))
  C.onResult(id, table.concat(lines, ";"))
  Coop.log("choice " .. id .. ": result " .. table.concat(lines, " "))
  finish(id, {move = move, want = want})
end

-- This machine's own player moves into `to` (the host's player, or its split screen player).
function C.moveLocal(owner, old, to)
  if owner == 0 then
    if Team and Team.SwitchSoldier then
      Coop.cfg.char = to
      pcall(Team.SwitchSoldier, old, to)
    end
  elseif CoopSplit and CoopSplit.on and CoopSplit.char == old and CoopSplit.moveOut then
    CoopSplit.moveOut(to)
  end
end

------------------------------------------------------------------------------
-- Every machine: the screen
------------------------------------------------------------------------------

function C.openLocal(id, secs, humans)
  local def = C.DEFS[id]
  if not def then return end
  local cards = C.cards(def)
  if #cards < 1 then return end
  C.scr = {id = id, untilT = now() + (tonumber(secs) or C.TIME), humans = humans, cards = cards, state = {}, keys = {},
           mine = Coop.myId(), cursor = nil, conf = false, locked = {}}
  C.lockBodies(true)
  if Scorer and Scorer.Fade then pcall(Scorer.Fade, 0, Color(0, 0, 0, 0), Color(0, 0, 0, 120), 0.3) end
  Coop.log("choice " .. id .. ": screen")
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
  local mine = st[s.mine]
  if mine and not s.cursor then s.cursor = mine.g end
end

function C.onResult(id, text)
  local s = C.scr
  local me = Coop.myId()
  local line
  for owner, char, reason in string.gmatch(text or "", "(%d+):([%w_%-]+):(%a+)") do
    if tonumber(owner) == me then
      local def = C.DEFS[id]
      local gi = groupIndexOf(def, char) or 1
      if reason == "full" then line = C.text("full", Coop.charName(char))
      elseif reason == "host" then line = C.text("host")
      elseif reason == "default" then line = C.text("default", Coop.charName(char)) .. " " .. C.text(id .. "_" .. def.groups[gi].key .. "_ex")
      else line = C.text(id .. "_" .. def.groups[gi].key .. "_ex") end
    end
  end
  if line then
    Coop.log("choice " .. id .. ": " .. line)
    if s then
      -- the cards go, the explanation stays a moment (the bodies stay locked until then)
      s.result = {text = line, untilT = now() + C.RESULT_HOLD}
      return
    end
    pcall(Scorer.SetMsgText, line, Game.GetTime() + 6)
  end
  C.closeLocal()
end

local function padButtons()
  local pad = {pcall(Net.CoopKey, -1, 0)}
  if not pad[1] or pad[2] == nil then return nil end
  return tonumber(pad[2]) or 0, tonumber(pad[5]) or 0
end

local function bit(v, n) return math.floor(v / n) % 2 == 1 end

-- Which input edges happened this tick: left, right, confirm, digit.
function C.readInput(s)
  local down = {}
  if Net.CoopKey then
    down.left = Net.CoopKey(0x25) == 1
    down.right = Net.CoopKey(0x27) == 1
    down.confirm = Net.CoopKey(0x0D) == 1
    for d = 1, 3 do down["d" .. d] = Net.CoopKey(0x30 + d) == 1 end
  end
  local b, lx = padButtons()
  if b then
    down.left = down.left or bit(b, 4) or lx < -16000
    down.right = down.right or bit(b, 8) or lx > 16000
    down.confirm = down.confirm or bit(b, 4096)
  end
  local edges = {}
  for k, v in pairs(down) do
    if v and not s.keys[k] then edges[#edges + 1] = k end
    s.keys[k] = v
  end
  for _, k in ipairs(C.injected or {}) do edges[#edges + 1] = k end
  C.injected = nil
  return edges
end

-- Tests and bots: press a key by name (left, right, confirm, d1..d3).
function C.press(key)
  C.injected = C.injected or {}
  C.injected[#C.injected + 1] = key
  return #C.injected
end

function C.send(s, g, conf)
  if Coop.isHost() then C.setPick(0, g, conf) else Net.CoopSend(0, 1, "chp|" .. s.id .. "|" .. g .. "|" .. (conf and 1 or 0)) end
  -- (shown at once; the host's state message corrects it)
  s.state[s.mine] = {g = g, conf = conf}
end

function C.step(s, dir)
  local at = 1
  for i, g in ipairs(s.cards) do if g == s.cursor then at = i end end
  s.cursor = s.cards[(at - 1 + dir) % #s.cards + 1]
  s.conf = false
  C.send(s, s.cursor, false)
end

function C.localUpdate()
  local s = C.scr
  if not s then return end
  if s.result then
    for k = 1, 3 do Coop.textBlockHide("CoopChoiceCard" .. k) end
    Coop.textBlockHide("CoopChoiceHint")
    Coop.textBlock("CoopChoice", s.result.text, {y = 190, color = Color(255, 230, 130, 255), width = 560})
    if now() >= s.result.untilT then C.closeLocal() end
    return
  end
  local menu = Input.GetActionSet and Input.GetActionSet() == "Menu"
  if not menu then
    for _, e in ipairs(C.readInput(s)) do
      if e == "left" then C.step(s, -1)
      elseif e == "right" then C.step(s, 1)
      elseif e == "confirm" and s.cursor then s.conf = true; C.send(s, s.cursor, true)
      elseif string.match(e, "^d%d$") then
        local g = s.cards[tonumber(string.sub(e, 2))]
        if g then s.cursor = g; s.conf = true; C.send(s, g, true) end
      end
    end
  end
  local auto = cfg.choice or (s.id == "LP" and cfg.lpchoice)   -- tests: confirm this card after 2 s
  if auto and not s.autoDone and now() > s.untilT - C.TIME + 2 then
    s.autoDone = true
    local g = s.cards[tonumber(auto)]
    if g then s.cursor = g; s.conf = true; C.send(s, g, true) end
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

function C.draw(s)
  local def = C.DEFS[s.id]
  local left = math.max(0, math.ceil(s.untilT - now()))
  Coop.textBlock("CoopChoice", C.text(s.id .. "_title") .. "  (" .. left .. ")", {y = 36, color = Color(255, 220, 160, 255)})
  local step = #s.cards == 3 and 112 or 128
  for k, gi in ipairs(s.cards) do
    local g = def.groups[gi]
    local names = {}
    for _, c in ipairs(g.chars) do names[#names + 1] = Coop.charName(c) end
    local who = {}
    for _, h in ipairs(s.humans) do
      local p = s.state[h]
      if p and p.g == gi then who[#who + 1] = nick(h) .. (p.conf and (" " .. C.text("ok")) or "") end
    end
    local mine = s.state[s.mine]
    local here = (mine and mine.g == gi) or (s.cursor == gi)
    local text = (here and "> " or "  ") .. k .. "  " .. C.text(s.id .. "_" .. g.key .. "_name") .. ":  " .. table.concat(names, ", ") .. "\n"
      .. C.text(s.id .. "_" .. g.key .. "_blurb") .. "\n"
      .. (#who > 0 and table.concat(who, ", ") or C.text("nobody"))
    local color = here and Color(255, 230, 130, 255) or Color(190, 190, 190, 255)
    Coop.textBlock("CoopChoiceCard" .. k, text, {y = 70 + (k - 1) * step, color = color, width = 560, step = 22})
  end
  local mine = s.state[s.mine]
  Coop.textBlock("CoopChoiceHint", (mine and mine.conf) and C.text("wait") or C.text("hint"),
    {y = 70 + #s.cards * step + 4, color = Color(210, 215, 225, 255), width = 600})
end

------------------------------------------------------------------------------
-- Messages and the tick
------------------------------------------------------------------------------

function C.onMessage(peer, f)
  local kind = f[1]
  if kind == "chs" and Coop.isClient() then
    local humans = {}
    for h in string.gmatch(f[4] or "", "%d+") do humans[#humans + 1] = tonumber(h) end
    if not C.scr then C.openLocal(f[2], f[3], humans) end
    return true
  elseif kind == "chst" and Coop.isClient() then
    C.applyState(f[2], f[3])
    return true
  elseif kind == "chr" and Coop.isClient() then
    C.onResult(f[2], f[3])
    return true
  elseif kind == "chp" and Coop.isHost() then
    -- (the sender's own player only)
    C.setPick(peer, tonumber(f[3]) or 0, f[4] == "1")
    return true
  end
  return false
end

function C.update()
  if Coop.level == "levels/menu" or not Coop.inSession() then
    if C.scr then C.closeLocal() end
    return
  end
  if Coop.isHost() then C.hostUpdate(); C.runLater() end
  C.localUpdate()
  -- a screen the host never closed (its game went away): back to play after a while
  if C.scr and now() > C.scr.untilT + 8 then C.closeLocal() end
end

Coop.addLangs(C.TEXT, "CoopChoice.TEXT")
