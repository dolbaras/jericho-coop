-- Jericho co-op: main menu entry, host/join screens and the lobby.
-- Loaded by coop.lua in the menu level. Menus are built with the game's own
-- Menu.VerticalMenu / Scorer items so they look like the rest of the front end.
--
-- Lobby messages (text, "|" separated, reliable):
--   pick|<char>                 client -> host: wants this character
--   nick|<nick>                 client -> host: nickname
--   ready|<0/1>                 client -> host
--   lobby|<level>|<seats>       host -> all; seats = "peer:char:ready:nick;..."
--   start|<level>|<seats>       host -> all; everyone loads <level>

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

function CoopMenu.HostSetup()
  CoopMenu.screen = "host"
  Menu.VerticalMenu(T("title_host"), {
    {"", "CoopMenu.NextLevel"},
    {T("create"), "CoopMenu.CreateSession"},
    {Menu.GetBackText(), "CoopMenu.Root"},
  }, "CoopMenu.Root")
  local it = item("Itm1")
  it.onLeft = "CoopMenu.PrevLevel"
  it.onRight = "CoopMenu.NextLevel"
  CoopMenu.refreshHost()
end

function CoopMenu.refreshHost()
  setText(item("Itm1"), "< " .. T("chapter") .. ": " .. CoopMenu.levelName(CoopMenu.LEVELS[CoopMenu.levelIndex]) .. " >")
end

function CoopMenu.PrevLevel()
  CoopMenu.levelIndex = (CoopMenu.levelIndex - 2) % #CoopMenu.LEVELS + 1
  CoopMenu.refreshHost()
  CoopMenu.broadcastLobby()
end

function CoopMenu.NextLevel()
  CoopMenu.levelIndex = CoopMenu.levelIndex % #CoopMenu.LEVELS + 1
  CoopMenu.refreshHost()
  CoopMenu.broadcastLobby()
end

function CoopMenu.CreateSession()
  Net.CoopClose()
  local ok = Net.CoopHost(cfg.port or CoopMenu.PORT, CoopMenu.MAX_PLAYERS - 1)
  Coop.log("lobby: host " .. ok)
  if ok ~= 1 then
    CoopMenu.message(T("port_fail") .. " " .. (cfg.port or CoopMenu.PORT))
    return
  end
  cfg.role = "host"
  cfg.myId = 0
  CoopMenu.seats = {{peer = 0, char = cfg.want or CoopMenu.CHAR_ORDER[1], ready = false, nick = CoopMenu.myNick()}}
  CoopMenu.Lobby()
end

------------------------------------------------------------------------------
-- Join
------------------------------------------------------------------------------

function CoopMenu.JoinSetup()
  CoopMenu.screen = "join"
  Menu.VerticalMenu(T("title_join"), {
    {cfg.addr or "127.0.0.1", "!EditText"},
    {T("connect"), "CoopMenu.Connect"},
    {Menu.GetBackText(), "CoopMenu.Root"},
  }, "CoopMenu.Root")
  local it = item("Itm1")
  it.MaxInput = 21
  local hint = Scorer.NewItem(0, "CoopHint", "Text")
  hint.Text = T("join_hint")
  hint.Pos = V2D(320, 150)
  hint.CentralText = 1
  hint.Font = Menu.SmallFont
  hint.Color = Menu.ItemColor
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
  local options = {
    {"", "CoopMenu.NextChar"},
    {CoopMenu.myNick(), "!EditText"},
    {"", "CoopMenu.ToggleTags"},
    {"", "CoopMenu.ToggleReady"},
  }
  if Coop.isHost() then
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
      setText(line0, T("chapter") .. ": " .. CoopMenu.levelName(level))
    end
  end
  for i = 1, CoopMenu.MAX_PLAYERS do
    local t = item("CoopLine" .. i)
    local s = CoopMenu.seats[i]
    if t then
      if s then
        local who = (s.nick and s.nick ~= "") and s.nick or (s.peer == 0 and T("host_name") or (T("player") .. " " .. (s.peer + 1)))
        if s.peer == CoopMenu.myPeer() then who = who .. " " .. T("you") end
        setText(t, who .. ": " .. s.char .. (s.ready and "  - " .. T("is_ready") or ""))
      else
        setText(t, "")
      end
    end
  end
  local me = CoopMenu.seatOf(CoopMenu.myPeer())
  setText(item("Itm1"), "< " .. T("character") .. ": " .. (me and me.char or "-") .. " >")
  setText(item("Itm3"), T("tags") .. ": " .. (cfg.tags == false and T("off") or T("on")))
  setText(item("Itm4"), T("ready") .. ": " .. ((me and me.ready) and T("yes") or T("no")))
  if Coop.isHost() and item("Itm5") then
    setText(item("Itm5"), CoopMenu.allReady() and T("start") or T("start_wait"))
  end
  CoopMenu.checkNick()
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
  Net.CoopClose()
  cfg.role = nil
  cfg.myId = nil
  CoopMenu.seats = {}
  CoopMenu.Root()
end

function CoopMenu.broadcastLobby()
  if not Coop.isHost() or CoopMenu.screen ~= "lobby" and CoopMenu.screen ~= "host" then return end
  Net.CoopSend(-1, 1, "lobby|" .. CoopMenu.LEVELS[CoopMenu.levelIndex] .. "|" .. CoopMenu.seatsString())
end

function CoopMenu.Start()
  if not Coop.isHost() or not CoopMenu.allReady() then return end
  local level = CoopMenu.LEVELS[CoopMenu.levelIndex]
  local seats = CoopMenu.seatsString()
  Coop.log("lobby: start " .. level .. " seats=" .. seats)
  Net.CoopSend(-1, 1, "start|" .. level .. "|" .. seats)
  CoopMenu.launch(level, seats)
end

-- Everyone: remember the session in COOP_CFG (survives level loads) and load the level.
function CoopMenu.launch(level, seats)
  cfg.level = level
  cfg.seats = seats
  cfg.loaded = true
  local own = {}
  for _, s in ipairs(CoopMenu.parseSeats(seats)) do
    own[#own + 1] = s.char .. "=" .. s.peer
    if s.peer == CoopMenu.myPeer() then cfg.char = s.char end
  end
  cfg.owners = table.concat(own, ",")
  cfg.save = "coop"   -- marks the session for the co-op save slot
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
    return true
  elseif kind == "start" and Coop.isClient() then
    Coop.log("lobby: host started " .. f[2])
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
  if CoopMenu.screen == "lobby" then CoopMenu.refreshLobby() end
end

CoopMenu.hookMainMenu()
