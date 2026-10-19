-- Jericho co-op: main menu entry, host/join screens and the lobby.
-- Loaded by coop.lua in the menu level. Menus are built with the game's own
-- Menu.VerticalMenu / Scorer items so they look like the rest of the front end.
--
-- Lobby messages (text, "|" separated, reliable):
--   pick|<char>                 client -> host: wants this character
--   nick|<nick>                 client -> host: nickname
--   ready|<0/1>                 client -> host
--   lobby|<level>|<seats>|<c>   host -> all; seats = "peer:char:ready:nick;...", c=1: continuing
--   sv|<save>                   host -> all, before start: the save vars (coop_save.lua)
--   start|<level>|<seats>|<skill>|<scaling>   host -> all; everyone loads <level>

CoopMenu = {}
local cfg = Coop.cfg

CoopMenu.PORT = 28100
CoopMenu.MAX_PLAYERS = 4
-- Characters that live to the end of the campaign come first, so players 2-4 get them by
-- default (docs/campaign-structure.md section 4).
CoopMenu.CHAR_ORDER = {"Black", "Church", "Delgado", "Rawlings", "Jones", "Cole"}
CoopMenu.LEVELS = {
  "Alk_Desert", "Alk_Tomb", "Alk_Bunker_00", "Alk_City", "Alk_Bunker_01", "Alk_Final",
  "WWII_BigGates", "WWII_PillBoxes", "WWII_Mosque", "WWII_Mosque_Inside", "WWII_Vigil",
  "WWII_Vigil_Inside", "WWII_Brandenburg",
  "Cru_River", "Cru_Labyrinth", "Cru_Sewers", "Cru_Keep", "Cru_Catacomb", "Cru_Chapel",
  "Rom_Outskirts", "Rom_Caldarium", "Rom_Tepidarium", "Rom_Palace_01", "Rom_Palace_02",
  "Rom_Coloseum", "Rom_Chamber",
  "Sum_Ziggurat_01", "Sum_Ziggurat_02", "Sum_Ziggurat_03", "Sum_Ziggurat_04",
  "Sum_Ziggurat_Meat", "Sum_End",
}

CoopMenu.levelIndex = CoopMenu.levelIndex or 1
CoopMenu.seats = {}        -- list of {peer=, char=, ready=}
CoopMenu.screen = nil      -- "root", "host", "join", "lobby"

------------------------------------------------------------------------------
-- Text: Russian when the game's own strings are Russian (cp1251), else English.
------------------------------------------------------------------------------

CoopMenu.TEXT = {
  en = {
    coop = "Co-op", title_root = "CO-OP", host = "Host game", join = "Join game",
    title_host = "HOST CO-OP GAME", chapter = "Chapter", create = "Create session",
    title_join = "JOIN CO-OP GAME", connect = "Connect", join_hint = "Host address (IP), then Connect",
    title_lobby = "CO-OP LOBBY", character = "Character", ready = "Ready", yes = "YES", no = "no",
    start = "Start", start_wait = "Start (waiting for players)", close = "Close session",
    leave = "Leave", connecting = "Connecting to", host_name = "Host", player = "Player",
    you = "(you)", is_ready = "READY", port_fail = "Could not open port", host_left = "Host closed the session",
    nick = "Nickname", tags = "Names above players", on = "on", off = "off",
    act = "Character actions", act_players = "players, AI after 30 s", act_humans = "players only",
    act_ai = "AI at once", lan = "Games on the local network:", lan_none = "(searching...)",
    continue = "Continue", continue_from = "Continue from",
    scaling = "Enemy toughness", scale_off = "as in single player", scale_light = "light (+15% per player)",
    scale_full = "full (+30% per player)",
  },
  ru = {
    coop = "Совместная игра", title_root = "СОВМЕСТНАЯ ИГРА", host = "Создать игру",
    join = "Присоединиться", title_host = "СОЗДАТЬ ИГРУ", chapter = "Глава",
    create = "Создать сессию", title_join = "ПРИСОЕДИНИТЬСЯ", connect = "Подключиться",
    join_hint = "Адрес хоста (IP), затем Подключиться", title_lobby = "ЛОББИ",
    character = "Персонаж", ready = "Готов", yes = "ДА", no = "нет", start = "Начать",
    start_wait = "Начать (ждём игроков)", close = "Закрыть сессию", leave = "Выйти",
    connecting = "Подключение к", host_name = "Хост", player = "Игрок", you = "(вы)",
    is_ready = "ГОТОВ", port_fail = "Не удалось открыть порт", host_left = "Хост закрыл сессию",
    nick = "Ник", tags = "Имена над игроками", on = "вкл", off = "выкл",
    act = "Действия персонажей", act_players = "игроки, ИИ через 30 с", act_humans = "только игроки",
    act_ai = "сразу ИИ", lan = "Игры в локальной сети:", lan_none = "(поиск...)",
    continue = "Продолжить", continue_from = "Продолжение",
    scaling = "Живучесть врагов", scale_off = "как в одиночной игре", scale_light = "лёгкая (+15% за игрока)",
    scale_full = "полная (+30% за игрока)",
  },
}

function CoopMenu.detectLanguage()
  local probe = Game.GetLangStr("Menu_ExitGame") or ""
  for i = 1, #probe do
    if string.byte(probe, i) >= 192 then return "ru" end
  end
  return "en"
end
CoopMenu.lang = CoopMenu.detectLanguage()

-- The sources are UTF-8; the game's fonts use cp1251. Convert Cyrillic once at load.
local function utf8_to_cp1251(s)
  return (string.gsub(s, "([\208\209])([\128-\191])", function(a, b)
    local code = (string.byte(a) - 192) * 64 + (string.byte(b) - 128)   -- Unicode code point
    if code == 0x401 then return "\168" end      -- Ё
    if code == 0x451 then return "\184" end      -- ё
    if code >= 0x410 and code <= 0x44F then return string.char(code - 0x410 + 192) end
    return "?"
  end))
end
for k, v in pairs(CoopMenu.TEXT.ru) do CoopMenu.TEXT.ru[k] = utf8_to_cp1251(v) end

local function T(key)
  return CoopMenu.TEXT[CoopMenu.lang][key] or CoopMenu.TEXT.en[key] or key
end
CoopMenu.T = T

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- Set an item's text and re-centre it (the engine centres when CentralText is set).
local function setText(it, text)
  if it and it.Text ~= text then
    it.Text = text
    it.CentralText = 1
  end
end

function CoopMenu.levelName(id)
  local s = Game.GetLangStr(string.lower(id))
  if not s or s == "" or string.find(s, "^%?") then s = id end
  return s
end

local function item(name) return Scorer.GetItem(0, name) end

function CoopMenu.seatOf(peer)
  for _, s in ipairs(CoopMenu.seats) do
    if s.peer == peer then return s end
  end
end

function CoopMenu.taken(char, exceptPeer)
  for _, s in ipairs(CoopMenu.seats) do
    if s.char == char and s.peer ~= exceptPeer then return true end
  end
  return false
end

function CoopMenu.firstFree(exceptPeer)
  for _, c in ipairs(CoopMenu.CHAR_ORDER) do
    if not CoopMenu.taken(c, exceptPeer) then return c end
  end
end

function CoopMenu.seatsString()
  local parts = {}
  for _, s in ipairs(CoopMenu.seats) do
    parts[#parts + 1] = s.peer .. ":" .. s.char .. ":" .. (s.ready and 1 or 0) .. ":" .. Coop.cleanNick(s.nick)
  end
  return table.concat(parts, ";")
end

function CoopMenu.parseSeats(str)
  local seats = {}
  for item in string.gmatch(str or "", "[^;]+") do
    local peer, char, ready, nick = string.match(item, "^(%d+):(%a+):(%d):?(.*)$")
    if peer then
      seats[#seats + 1] = {peer = tonumber(peer), char = char, ready = ready == "1", nick = nick}
    end
  end
  return seats
end

function CoopMenu.myPeer()
  return Coop.isHost() and 0 or cfg.myId
end

------------------------------------------------------------------------------
-- Main menu entry
------------------------------------------------------------------------------

-- Insert "Co-op" after the campaign entry of the main menu.
function CoopMenu.hookMainMenu()
  if not MainMenu or CoopMenu.mainHooked then return end
  CoopMenu.mainHooked = true
  local origMain = MainMenu.MainMenu
  local origVertical = Menu.VerticalMenu
  MainMenu.MainMenu = function(...)
    CoopMenu.injecting = Game.Get("isDemo") == 0
    local ok, err = pcall(origMain, ...)
    CoopMenu.injecting = false
    if not ok then Coop.log("main menu error: " .. tostring(err)) end
  end
  Menu.VerticalMenu = function(title, options, ...)
    if CoopMenu.injecting then
      CoopMenu.injecting = false
      table.insert(options, 2, {T("coop"), "CoopMenu.Root"})
    end
    return origVertical(title, options, ...)
  end
end

function CoopMenu.Root()
  CoopMenu.screen = "root"
  Menu.VerticalMenu(T("title_root"), {
    {T("host"), "CoopMenu.HostSetup"},
    {T("join"), "CoopMenu.JoinSetup"},
    {Menu.GetBackText(), "MainMenu.MainMenu"},
  }, "MainMenu.MainMenu")
end

------------------------------------------------------------------------------
-- Host setup
------------------------------------------------------------------------------

-- The co-op save (coop_save.lua): the last checkpoint, else the start of the last level.
function CoopMenu.savedGame()
  if not CoopSave then return nil end
  local rec = CoopSave.read(CoopSave.CHECKPOINT) or CoopSave.read(CoopSave.SAVE)
  if rec and rec.level and CoopMenu.indexOf(rec.level) then return rec end
end

function CoopMenu.indexOf(level)
  for i, id in ipairs(CoopMenu.LEVELS) do
    if string.lower(id) == string.lower(level or "") then return i end
  end
end

-- Chapters a new session can start from: the first one, every level reached in co-op or
-- in single player (VisitedLevels); all of them in test runs.
function CoopMenu.unlocked(i)
  if i == 1 or cfg.dev then return true end
  local id = string.lower(CoopMenu.LEVELS[i])
  if not CoopMenu.unlockedSet then
    local set = {}
    if CoopSave then
      local _, coopSet = CoopSave.visited()
      for k in pairs(coopSet) do set[k] = true end
    end
    for name in string.gmatch(Game.Get("VisitedLevels") or "", "[^,]+") do set[string.lower(name)] = true end
    CoopMenu.unlockedSet = set
  end
  return CoopMenu.unlockedSet[id] == true
end

function CoopMenu.HostSetup()
  CoopMenu.screen = "host"
  CoopMenu.unlockedSet = nil
  if not CoopMenu.unlocked(CoopMenu.levelIndex) then CoopMenu.levelIndex = 1 end
  local options = {
    {"", "CoopMenu.NextLevel"},
    {T("create"), "CoopMenu.CreateSession"},
  }
  CoopMenu.saved = CoopMenu.savedGame()
  if CoopMenu.saved then
    options[#options + 1] = {T("continue") .. ": " .. CoopMenu.levelName(CoopMenu.saved.level), "CoopMenu.ContinueSession"}
  end
  options[#options + 1] = {Menu.GetBackText(), "CoopMenu.Root"}
  Menu.VerticalMenu(T("title_host"), options, "CoopMenu.Root")
  local it = item("Itm1")
  it.onLeft = "CoopMenu.PrevLevel"
  it.onRight = "CoopMenu.NextLevel"
  CoopMenu.refreshHost()
end

function CoopMenu.refreshHost()
  setText(item("Itm1"), "< " .. T("chapter") .. ": " .. CoopMenu.levelName(CoopMenu.LEVELS[CoopMenu.levelIndex]) .. " >")
end

function CoopMenu.stepLevel(step)
  local n = #CoopMenu.LEVELS
  for _ = 1, n do
    CoopMenu.levelIndex = (CoopMenu.levelIndex - 1 + step) % n + 1
    if CoopMenu.unlocked(CoopMenu.levelIndex) then break end
  end
  CoopMenu.refreshHost()
  CoopMenu.broadcastLobby()
end

function CoopMenu.PrevLevel() CoopMenu.stepLevel(-1) end
function CoopMenu.NextLevel() CoopMenu.stepLevel(1) end

function CoopMenu.ContinueSession()
  local rec = CoopMenu.saved or CoopMenu.savedGame()
  if not rec then return end
  CoopMenu.levelIndex = CoopMenu.indexOf(rec.level) or CoopMenu.levelIndex
  CoopMenu.openSession()
  CoopMenu.continueRec = rec
end

function CoopMenu.CreateSession()
  CoopMenu.openSession()
  CoopMenu.continueRec = nil
end

function CoopMenu.openSession()
  Net.CoopClose()
  local ok = Net.CoopHost(cfg.port or CoopMenu.PORT, CoopMenu.MAX_PLAYERS - 1)
  Coop.log("lobby: host " .. ok)
  if ok ~= 1 then
    CoopMenu.message(T("port_fail") .. " " .. (cfg.port or CoopMenu.PORT))
    return
  end
  cfg.role = "host"
  cfg.myId = 0
  -- The host's default seat is Delgado: in the story Ross's spirit enters Delgado when Ross
  -- dies (alk_final), and the host is Ross in Act 1 (Coop.startChar).
  CoopMenu.seats = {{peer = 0, char = cfg.want or "Delgado", ready = false, nick = CoopMenu.myNick()}}
  CoopMenu.Lobby()
end

------------------------------------------------------------------------------
-- Join
------------------------------------------------------------------------------

-- LAN games heard through Net.CoopDiscover (native/coop_net.c): items 3..6 of the join
-- screen, refreshed by CoopMenu.update. Hosts announce "nick|level|players|max|port".
CoopMenu.LAN_SLOTS = 4
CoopMenu.lan = {}

function CoopMenu.JoinSetup()
  CoopMenu.screen = "join"
  local options = {
    {cfg.addr or "127.0.0.1", "!EditText"},
    {T("connect"), "CoopMenu.Connect"},
  }
  for i = 1, CoopMenu.LAN_SLOTS do options[#options + 1] = {"", "CoopMenu.JoinLan" .. i} end
  options[#options + 1] = {Menu.GetBackText(), "CoopMenu.Root"}
  Menu.VerticalMenu(T("title_join"), options, "CoopMenu.Root")
  CoopMenu.lanNext = 0
  local it = item("Itm1")
  it.MaxInput = 21
  local hint = Scorer.NewItem(0, "CoopHint", "Text")
  hint.Text = T("join_hint")
  hint.Pos = V2D(320, 150)
  hint.CentralText = 1
  hint.Font = Menu.SmallFont
  hint.Color = Menu.ItemColor
end

function CoopMenu.refreshLan()
  if not Net.CoopDiscover then return end
  CoopMenu.lan = {}
  local byText = {}
  for entry in string.gmatch(Net.CoopDiscover() or "", "[^;]+") do
    local f = {}
    for x in string.gmatch(entry .. "|", "([^|]*)|") do f[#f + 1] = x end
    local g = {ip = f[1], nick = f[2], level = f[3], players = f[4], max = f[5], port = tonumber(f[6])}
    -- A host on this PC answers on the loopback and on its LAN address: list it once,
    -- under the LAN address.
    local key = table.concat(f, "|", 2)
    local seen = byText[key]
    if not seen then
      byText[key] = g
      CoopMenu.lan[#CoopMenu.lan + 1] = g
    elseif seen.ip == "127.0.0.1" then
      seen.ip = g.ip
    end
  end
  for i = 1, CoopMenu.LAN_SLOTS do
    local it = item("Itm" .. (2 + i))
    local g = CoopMenu.lan[i]
    if it then
      if g then
        local nick = (g.nick and g.nick ~= "") and g.nick or T("host_name")
        setText(it, string.format("LAN: %s - %s (%s/%s)  %s", nick, CoopMenu.levelName(g.level or ""),
          g.players or "?", g.max or "?", g.ip or ""))
      else
        setText(it, i == 1 and ("LAN: " .. T("lan_none")) or "")
      end
    end
  end
end

function CoopMenu.joinLan(i)
  local g = CoopMenu.lan[i]
  if not g then return end
  if g.port then cfg.port = g.port end
  if item("Itm1") then item("Itm1").Text = g.ip end
  CoopMenu.Connect()
end
for i = 1, 4 do CoopMenu["JoinLan" .. i] = function() CoopMenu.joinLan(i) end end

-- Host: announce the session on the LAN while the lobby is open.
function CoopMenu.announce()
  if not Net.CoopAnnounce then return end
  local text = ""
  if Coop.isHost() and CoopMenu.screen == "lobby" then
    text = table.concat({Coop.cleanNick(CoopMenu.myNick()), CoopMenu.LEVELS[CoopMenu.levelIndex] or "",
      #CoopMenu.seats, CoopMenu.MAX_PLAYERS, cfg.port or CoopMenu.PORT}, "|")
  end
  if text ~= CoopMenu.announced then
    CoopMenu.announced = text
    Net.CoopAnnounce(text)
  end
end

function CoopMenu.Connect()
  local addr = item("Itm1") and item("Itm1").Text or "127.0.0.1"
  addr = string.gsub(addr, "%s", "")
  cfg.addr = addr
  Net.CoopClose()
  local ok = Net.CoopJoin(addr, cfg.port or CoopMenu.PORT)
  Coop.log("lobby: join " .. addr .. " -> " .. ok)
  cfg.role = "client"
  cfg.myId = nil
  CoopMenu.seats = {}
  CoopMenu.Lobby()
end

------------------------------------------------------------------------------
-- Lobby
------------------------------------------------------------------------------

function CoopMenu.Lobby()
  CoopMenu.screen = "lobby"
  CoopMenu.portraitOf = nil
  local options = {
    {"", "CoopMenu.NextChar"},
    {CoopMenu.myNick(), "!EditText"},
    {"", "CoopMenu.ToggleTags"},
    {"", "CoopMenu.ToggleReady"},
  }
  if Coop.isHost() then
    -- Who does character-only actions nobody holds (coop_claim.lua); the host decides.
    options[#options + 1] = {"", "CoopMenu.CycleActMode"}
    -- Vanilla difficulty, and how much tougher enemies get per extra player (coop_enemies.lua).
    options[#options + 1] = {"", "CoopMenu.CycleSkill"}
    options[#options + 1] = {"", "CoopMenu.CycleScaling"}
    options[#options + 1] = {T("start"), "CoopMenu.Start"}
    options[#options + 1] = {T("close"), "CoopMenu.Leave"}
  else
    options[#options + 1] = {T("leave"), "CoopMenu.Leave"}
  end
  Menu.VerticalMenu(T("title_lobby"), options, "CoopMenu.Leave", nil, 205, 30)
  local it = item("Itm1")
  it.onLeft = "CoopMenu.PrevChar"
  it.onRight = "CoopMenu.NextChar"
  item("Itm2").MaxInput = 16
  CoopMenu.nickSent = CoopMenu.myNick()
  -- Read-only lines: chapter and the player list.
  for i = 0, CoopMenu.MAX_PLAYERS do
    local t = Scorer.NewItem(0, "CoopLine" .. i, "Text")
    t.Text = ""
    t.Pos = V2D(320, 95 + i * 24)
    t.CentralText = 1
    t.Font = Menu.SmallFont
    t.Color = Menu.ItemColor
  end
  CoopMenu.refreshLobby()
end

function CoopMenu.refreshLobby()
  if CoopMenu.screen ~= "lobby" or not item("Itm1") then return end
  local level = CoopMenu.LEVELS[CoopMenu.levelIndex]
  local line0 = item("CoopLine0")
  if line0 then
    local status = Net.CoopStatus()
    if Coop.isClient() and not cfg.myId then
      setText(line0, T("connecting") .. " " .. tostring(cfg.addr) .. "...")
    else
      local label = (CoopMenu.continueRec or cfg.continuing) and T("continue_from") or T("chapter")
      setText(line0, label .. ": " .. CoopMenu.levelName(level))
    end
  end
  for i = 1, CoopMenu.MAX_PLAYERS do
    local t = item("CoopLine" .. i)
    local s = CoopMenu.seats[i]
    if t then
      if s then
        local who = (s.nick and s.nick ~= "") and s.nick or (s.peer == 0 and T("host_name") or (T("player") .. " " .. (s.peer + 1)))
        if s.peer == CoopMenu.myPeer() then who = who .. " " .. T("you") end
        -- Act 1: the host is Ross until Ross dies (Coop.startChar), then takes the seat.
        local char = s.char
        if s.peer == 0 and string.find(string.lower(level or ""), "^alk_") then char = "Ross -> " .. char end
        setText(t, who .. ": " .. char .. (s.ready and "  - " .. T("is_ready") or ""))
      else
        setText(t, "")
      end
    end
  end
  local me = CoopMenu.seatOf(CoopMenu.myPeer())
  setText(item("Itm1"), "< " .. T("character") .. ": " .. (me and me.char or "-") .. " >")
  CoopMenu.showPortrait(me and me.char)
  setText(item("Itm3"), T("tags") .. ": " .. (cfg.tags == false and T("off") or T("on")))
  setText(item("Itm4"), T("ready") .. ": " .. ((me and me.ready) and T("yes") or T("no")))
  if Coop.isHost() and item("Itm8") then
    setText(item("Itm5"), T("act") .. ": " .. T("act_" .. (cfg.actmode or "players")))
    setText(item("Itm6"), CoopMenu.skillText())
    setText(item("Itm7"), T("scaling") .. ": " .. T("scale_" .. (cfg.scaling or "light")))
    setText(item("Itm8"), CoopMenu.allReady() and T("start") or T("start_wait"))
  end
  CoopMenu.checkNick()
end

-- Portraits: the game's own character art from the Extras gallery (2D/Menu/Extra_N_Picture_0,
-- titles Extra_N_Main_Title, e.g. "Sergeant Frank Delgado").
CoopMenu.PORTRAIT = {Ross = 0, Black = 1, Delgado = 2, Church = 3, Jones = 4, Cole = 5, Rawlings = 6}

function CoopMenu.showPortrait(char)
  local n = CoopMenu.PORTRAIT[char or ""]
  local pic, name = item("CoopPortrait"), item("CoopPortraitName")
  if not n then
    if pic then pic.Visible = 0 end
    if name then name.Visible = 0 end
    return
  end
  if not pic then pic = Scorer.NewItem(0, "CoopPortrait", "Sprite") end
  if CoopMenu.portraitOf ~= char then
    CoopMenu.portraitOf = char
    -- In the order the game's Extras gallery uses (loading the file resets the rest):
    -- top right of the screen, 136 units of the 640x480 layout.
    pic.File = "2D/Menu/Extra_" .. n .. "_Picture_0.bmp"
    pic.Unit = 1
    pic.Pos = V2D(564, 96)
    pic.Scale = V2D(136, 136)
    pic.Color = Color(255, 255, 255, 255)
    pic.Pivot = V2D(0.5, 0.5)
  end
  pic.Visible = 1
  if not name then
    name = Scorer.NewItem(0, "CoopPortraitName", "Text")
    name.Font = Menu.SmallFont
    name.Pos = V2D(564, 168)
    name.CentralText = 1
    name.Color = Menu.ItemColor
  end
  -- The title carries the rank ("Sergeant Frank Delgado"); under the picture only the name fits.
  local words = {}
  for w in string.gmatch(Game.GetLangStr("Extra_" .. n .. "_Main_Title") or "", "%S+") do words[#words + 1] = w end
  setText(name, table.concat(words, " ", math.max(1, #words - 1)))
  name.Visible = 1
end

function CoopMenu.allReady()
  if #CoopMenu.seats == 0 then return false end
  for _, s in ipairs(CoopMenu.seats) do
    if not s.ready then return false end
  end
  return true
end

function CoopMenu.cycleChar(step)
  local me = CoopMenu.seatOf(CoopMenu.myPeer())
  if not me then return end
  local n = #CoopMenu.CHAR_ORDER
  local idx = 1
  for i, c in ipairs(CoopMenu.CHAR_ORDER) do
    if c == me.char then idx = i end
  end
  for _ = 1, n do
    idx = (idx - 1 + step) % n + 1
    local c = CoopMenu.CHAR_ORDER[idx]
    if not CoopMenu.taken(c, me.peer) then
      if Coop.isHost() then
        me.char = c
        me.ready = false
        CoopMenu.broadcastLobby()
      else
        Net.CoopSend(0, 1, "pick|" .. c)
      end
      break
    end
  end
  CoopMenu.refreshLobby()
end

function CoopMenu.NextChar() CoopMenu.cycleChar(1) end
function CoopMenu.PrevChar() CoopMenu.cycleChar(-1) end

function CoopMenu.myNick()
  local n = Coop.cleanNick(cfg.nick)
  if n == "" then n = Coop.isHost() and T("host_name") or T("player") end
  return n
end

-- The nickname field is edited in place by the engine; send it once it stops changing.
function CoopMenu.checkNick()
  local it = item("Itm2")
  if not it then return end
  local text = Coop.cleanNick(it.Text)
  if text ~= CoopMenu.nickPending then
    CoopMenu.nickPending, CoopMenu.nickSince = text, Net.CoopTime()
    return
  end
  if text ~= "" and text ~= CoopMenu.nickSent and Net.CoopTime() - CoopMenu.nickSince > 1 then
    CoopMenu.nickSent = text
    cfg.nick = text
    if Coop.isHost() then
      local me = CoopMenu.seatOf(0)
      if me then me.nick = text end
      CoopMenu.broadcastLobby()
    else
      Net.CoopSend(0, 1, "nick|" .. text)
    end
  end
end

CoopMenu.ACT_MODES = {"players", "humans", "ai"}

CoopMenu.SKILL_KEYS = {[0] = "Menu_Skill_Easy", [1] = "Menu_Skill_Normal", [2] = "Menu_Skill_Hard"}
CoopMenu.SCALINGS = {"off", "light", "full"}

-- The game's own strings (already in the game's encoding).
function CoopMenu.skillText()
  local skill = cfg.skill or Game.Get("GameSkill") or 1
  return Game.GetLangStr("Menu_Skill_Level") .. ": " .. Game.GetLangStr(CoopMenu.SKILL_KEYS[skill] or "Menu_Skill_Normal")
end

function CoopMenu.CycleSkill()
  cfg.skill = ((cfg.skill or Game.Get("GameSkill") or 1) + 1) % 3
  CoopMenu.refreshLobby()
end

function CoopMenu.CycleScaling()
  local cur = cfg.scaling or "light"
  for i, m in ipairs(CoopMenu.SCALINGS) do
    if m == cur then cfg.scaling = CoopMenu.SCALINGS[i % #CoopMenu.SCALINGS + 1] break end
  end
  CoopMenu.refreshLobby()
end

function CoopMenu.CycleActMode()
  local cur = cfg.actmode or "players"
  for i, m in ipairs(CoopMenu.ACT_MODES) do
    if m == cur then cfg.actmode = CoopMenu.ACT_MODES[i % #CoopMenu.ACT_MODES + 1] break end
  end
  CoopMenu.refreshLobby()
end

function CoopMenu.ToggleTags()
  cfg.tags = cfg.tags == false
  CoopMenu.refreshLobby()
end

function CoopMenu.ToggleReady()
  local me = CoopMenu.seatOf(CoopMenu.myPeer())
  if not me then return end
  if Coop.isHost() then
    me.ready = not me.ready
    CoopMenu.broadcastLobby()
  else
    Net.CoopSend(0, 1, "ready|" .. (me.ready and 0 or 1))
  end
  CoopMenu.refreshLobby()
end

function CoopMenu.Leave()
  if Net.CoopAnnounce then Net.CoopAnnounce("") end
  CoopMenu.continueRec = nil
  cfg.continuing = nil
  CoopMenu.announced = ""
  Net.CoopClose()
  cfg.role = nil
  cfg.myId = nil
  CoopMenu.seats = {}
  CoopMenu.Root()
end

function CoopMenu.broadcastLobby()
  if not Coop.isHost() or CoopMenu.screen ~= "lobby" and CoopMenu.screen ~= "host" then return end
  Net.CoopSend(-1, 1, "lobby|" .. CoopMenu.LEVELS[CoopMenu.levelIndex] .. "|" .. CoopMenu.seatsString() ..
               "|" .. (CoopMenu.continueRec and 1 or 0))
end

function CoopMenu.Start()
  if not Coop.isHost() or not CoopMenu.allReady() then return end
  local level = CoopMenu.LEVELS[CoopMenu.levelIndex]
  local seats = CoopMenu.seatsString()
  Coop.log("lobby: start " .. level .. " seats=" .. seats .. (CoopMenu.continueRec and " (continue)" or ""))
  -- Save state: the co-op save when continuing, else a clean start (which becomes the
  -- new co-op save). The clients get the same vars before "start".
  if CoopSave then
    CoopSave.beginSession()
    if CoopMenu.continueRec then
      CoopSave.apply(CoopMenu.continueRec)
      level = CoopMenu.continueRec.level
    else
      Game.DelSaveVars("")
      CoopSave.levelStart(level)
    end
    CoopSave.sendVars(level)
  end
  CoopMenu.continueRec = nil
  cfg.skill = cfg.skill or Game.Get("GameSkill")
  cfg.scaling = cfg.scaling or "light"
  Net.CoopSend(-1, 1, "start|" .. level .. "|" .. seats .. "|" .. cfg.skill .. "|" .. cfg.scaling)
  CoopMenu.launch(level, seats)
end

-- Everyone: remember the session in COOP_CFG (survives level loads) and load the level.
function CoopMenu.launch(level, seats)
  if Net.CoopAnnounce then Net.CoopAnnounce("") end
  cfg.level = level
  cfg.seats = seats
  cfg.loaded = true
  local own = {}
  for _, s in ipairs(CoopMenu.parseSeats(seats)) do
    own[#own + 1] = s.char .. "=" .. s.peer
    if s.peer == CoopMenu.myPeer() then cfg.char, cfg.seatChar = s.char, s.char end
  end
  cfg.owners = table.concat(own, ",")
  cfg.save = "coop"   -- marks the session for the co-op save slot
  cfg.continuing = nil
  if CoopSave then
    CoopSave.beginSession()
    CoopSave.applyPending()
  end
  if cfg.skill then Game.Set("GameSkill", cfg.skill) end   -- restored when the session ends
  Coop.rearm()
  Game.LoadLevel("Levels/" .. level)
end

function CoopMenu.message(text)
  local t = item("CoopLine0") or Scorer.NewItem(0, "CoopLine0", "Text")
  t.Pos = V2D(320, 110)
  t.Font = Menu.SmallFont
  setText(t, text)
  t.Font = Menu.SmallFont
  t.Color = Menu.ItemColor
end

------------------------------------------------------------------------------
-- Messages and events (called from coop.lua while in the menu level)
------------------------------------------------------------------------------

function CoopMenu.onJoin(peer)
  if Coop.isHost() then
    if #CoopMenu.seats >= CoopMenu.MAX_PLAYERS then return end
    CoopMenu.seats[#CoopMenu.seats + 1] = {peer = peer, char = CoopMenu.firstFree(peer), ready = false,
                                           nick = T("player") .. " " .. (peer + 1)}
    Net.CoopSend(peer, 1, "welcome|" .. peer .. "|Menu|" .. CoopMenu.seats[#CoopMenu.seats].char)
    CoopMenu.broadcastLobby()
  end
end

function CoopMenu.onLeave(peer)
  if Coop.isHost() then
    for i, s in ipairs(CoopMenu.seats) do
      if s.peer == peer then table.remove(CoopMenu.seats, i) break end
    end
    CoopMenu.broadcastLobby()
  elseif peer == 0 then
    CoopMenu.Root()
    CoopMenu.message(T("host_left"))
  end
end

-- Returns true when the message was a lobby message.
function CoopMenu.onMessage(peer, f)
  local kind = f[1]
  if kind == "pick" and Coop.isHost() then
    local s = CoopMenu.seatOf(peer)
    if s and f[2] and not CoopMenu.taken(f[2], peer) then
      s.char = f[2]
      s.ready = false
      CoopMenu.broadcastLobby()
    end
    return true
  elseif kind == "nick" and Coop.isHost() then
    local s = CoopMenu.seatOf(peer)
    if s then
      s.nick = Coop.cleanNick(f[2])
      CoopMenu.broadcastLobby()
    end
    return true
  elseif kind == "ready" and Coop.isHost() then
    local s = CoopMenu.seatOf(peer)
    if s then
      s.ready = f[2] == "1"
      CoopMenu.broadcastLobby()
    end
    return true
  elseif kind == "lobby" and Coop.isClient() then
    for i, id in ipairs(CoopMenu.LEVELS) do
      if id == f[2] then CoopMenu.levelIndex = i end
    end
    CoopMenu.seats = CoopMenu.parseSeats(f[3])
    cfg.continuing = f[4] == "1" or nil
    return true
  elseif kind == "start" and Coop.isClient() then
    Coop.log("lobby: host started " .. f[2])
    cfg.skill = tonumber(f[4]) or cfg.skill
    cfg.scaling = f[5] or cfg.scaling
    CoopMenu.launch(f[2], f[3])
    return true
  elseif kind == "welcome" and Coop.isClient() and f[3] == "Menu" then
    cfg.myId = tonumber(f[2])
    Net.CoopSend(0, 1, "nick|" .. CoopMenu.myNick())
    return true
  end
  return false
end

function CoopMenu.update()
  -- Back from a session that ended by itself (host gone): say why, on the co-op screen.
  if cfg.notice and Coop.frame > 40 and CoopMenu.screen == nil and not Menu.isStartUpMenu then
    local why = cfg.notice
    cfg.notice = nil
    CoopMenu.Root()
    CoopMenu.message(T(why))
  end
  if CoopMenu.screen == "lobby" then CoopMenu.refreshLobby() end
  if CoopMenu.screen == "join" and Coop.frame >= (CoopMenu.lanNext or 0) then
    CoopMenu.lanNext = Coop.frame + 10
    CoopMenu.refreshLan()
  end
  CoopMenu.announce()
end

CoopMenu.hookMainMenu()
