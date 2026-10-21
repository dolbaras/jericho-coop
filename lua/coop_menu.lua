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
CoopMenu.smodPeers = {}    -- peers that have SMOD (coop_smod.lua), the host's view
CoopMenu.screen = nil      -- "root", "host", "join", "lobby"

------------------------------------------------------------------------------
-- Text: Russian when the game's own strings are Russian (cp1251), else English.
------------------------------------------------------------------------------

CoopMenu.TEXT = {
  en = {
    coop = "Co-op", title_root = "CO-OP", host = "Host game", join = "Join (local network)",
    join_steam = "Join through Steam", net = "Network", net_lan = "local network", net_steam = "Steam",
    title_steam = "JOIN THROUGH STEAM", steam_hint = "Steam friends' games",
    steam_none = "(no friends' games)", steam_off = "Steam unavailable:", invite = "Invite friends (Steam)",
    steam_norun = "Steam is not running", steam_nodll = "steam_api.dll is missing",
    title_host = "HOST CO-OP GAME", chapter = "Chapter", create = "Create session",
    title_join = "JOIN CO-OP GAME", connect = "Connect", join_hint = "Host IP, then Connect",
    title_lobby = "CO-OP LOBBY", character = "Character", ready = "Ready", yes = "YES", no = "no",
    start = "Start", start_wait = "Start (waiting)", close = "Close session",
    leave = "Leave", connecting = "Connecting to", host_name = "Host", player = "Player",
    you = "(you)", is_ready = "READY", port_fail = "Could not open port", host_left = "Host closed the session",
    nick = "Nickname", tags = "Names above players", on = "on", off = "off",
    act = "Special actions", act_players = "players, then AI", act_humans = "players only",
    act_ai = "AI at once", lan = "Games on the local network:", lan_none = "(searching...)",
    continue = "Continue", continue_from = "Continue from",
    scaling = "Enemy toughness", scale_off = "as in the game", scale_light = "+15% per player",
    scale_full = "+30% per player", settings = "Session settings...", title_settings = "SESSION SETTINGS",
    qte = "QTE", qte_normal = "as in the game", qte_auto = "automatic", qte_shared = "all players, one success",
    aisquad = "AI squadmates", ai_normal = "as in the game", ai_tough = "take 60% damage",
    ai_very = "take 30% damage",
    cutscenes = "Cutscenes", pov_off = "original camera", pov_on = "own eyes (experimental)",
    rules = "Rules", rules_smod = "host's SMOD", rules_game = "as in the game",
    p2 = "Player 2 (gamepad)", p2_none = "none",
    rules_notall = "game's (SMOD not for all)", ai_smod = "SMOD (%d%% damage)",
    version_host = "The host has co-op %s, you have %s: both need the same version",
    version_peer = "%s has another co-op version (this is %s)",
  },
  ru = {
    coop = "Совместная игра", title_root = "СОВМЕСТНАЯ ИГРА", host = "Создать игру",
    join = "Присоединиться (локальная сеть)", title_host = "СОЗДАТЬ ИГРУ", chapter = "Глава",
    join_steam = "Присоединиться через Steam", net = "Сеть", net_lan = "локальная сеть", net_steam = "Steam",
    title_steam = "ЧЕРЕЗ STEAM", steam_hint = "Игры друзей в Steam",
    steam_none = "(игр друзей нет)", steam_off = "Steam недоступен:", invite = "Пригласить друзей (Steam)",
    steam_norun = "Steam не запущен", steam_nodll = "нет steam_api.dll",
    create = "Создать сессию", title_join = "ПРИСОЕДИНИТЬСЯ", connect = "Подключиться",
    join_hint = "IP хоста, затем Подключиться", title_lobby = "ЛОББИ",
    character = "Персонаж", ready = "Готов", yes = "ДА", no = "нет", start = "Начать",
    start_wait = "Начать (ждём)", close = "Закрыть сессию", leave = "Выйти",
    connecting = "Подключение к", host_name = "Хост", player = "Игрок", you = "(вы)",
    is_ready = "ГОТОВ", port_fail = "Не удалось открыть порт", host_left = "Хост закрыл сессию",
    nick = "Ник", tags = "Имена над игроками", on = "вкл", off = "выкл",
    act = "Спец. действия", act_players = "игроки, затем ИИ", act_humans = "только игроки",
    act_ai = "сразу ИИ", lan = "Игры в локальной сети:", lan_none = "(поиск...)",
    continue = "Продолжить", continue_from = "Продолжение",
    scaling = "Живучесть врагов", scale_off = "как в игре", scale_light = "+15% за игрока",
    scale_full = "+30% за игрока", settings = "Настройки сессии...", title_settings = "НАСТРОЙКИ СЕССИИ",
    qte = "QTE", qte_normal = "как в игре", qte_auto = "автоматически", qte_shared = "все, хватит одного успеха",
    aisquad = "Союзники ИИ", ai_normal = "как в игре", ai_tough = "60% урона",
    ai_very = "30% урона",
    cutscenes = "Катсцены", pov_off = "камера оригинала", pov_on = "своими глазами (эксп.)",
    rules = "Правила", rules_smod = "SMOD хоста", rules_game = "как в игре",
    p2 = "Игрок 2 (геймпад)", p2_none = "нет",
    rules_notall = "игры (SMOD не у всех)", ai_smod = "SMOD (%d%% урона)",
    version_host = "У хоста кооп %s, у вас %s: версии должны совпадать",
    version_peer = "У игрока %s другая версия коопа (здесь %s)",
  },
}

function CoopMenu.detectLanguage()
  if cfg.lang then return cfg.lang end   -- tests: the other language on this install
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
-- CentralText centres the text on the item's current X: put X back on the centre line
-- first, or every change of the text moves it further left.
local function setText(it, text)
  if it and it.Text ~= text then
    it.Text = text
    it.X = 320
    it.CentralText = 1
  end
end

CoopMenu.charName = Coop.charName

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
    pcall(CoopMenu.fitMainMenu)
  end
  Menu.VerticalMenu = function(title, options, ...)
    if CoopMenu.injecting then
      CoopMenu.injecting = false
      table.insert(options, 2, {T("coop"), "CoopMenu.Root"})
    end
    return origVertical(title, options, ...)
  end
end

-- The main menu moves its 7th entry down to 400 to set "Exit" apart. With more entries
-- (SMOD's Cheats/Debug plus ours) that lands on another one and the last runs off the
-- screen: then spread them all evenly between the first entry and MAIN_BOTTOM.
CoopMenu.MAIN_BOTTOM = 445
function CoopMenu.fitMainMenu()
  local n = 0
  while item("Itm" .. (n + 1)) do n = n + 1 end
  if n < 8 then return end
  local top = item("Itm1").Y
  local step = (CoopMenu.MAIN_BOTTOM - top) / (n - 1)
  for i = 1, n do item("Itm" .. i).Y = top + (i - 1) * step end
end

function CoopMenu.Root()
  CoopMenu.screen = "root"
  Menu.VerticalMenu(T("title_root"), {
    {T("host"), "CoopMenu.HostSetup"},
    {T("join"), "CoopMenu.JoinSetup"},
    -- Steam (native/steam_net.c, from the fork MAK-PIVO/jericho-coop): friends join a
    -- Steam lobby through Valve's relay, no IP or open port. Its own lobby, its own screen.
    {T("join_steam"), "CoopMenu.SteamJoinSetup"},
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
    {"", "CoopMenu.ToggleNet"},
    {T("create"), "CoopMenu.CreateSession"},
  }
  CoopMenu.saved = CoopMenu.savedGame()
  if CoopMenu.saved then
    options[#options + 1] = {T("continue") .. ": " .. CoopMenu.levelName(CoopMenu.saved.level), "CoopMenu.ContinueSession"}
  end
  options[#options + 1] = {Menu.GetBackText(), "CoopMenu.Root"}
  Menu.VerticalMenu(T("title_host"), options, "CoopMenu.Root")
  local a, b = item("Itm1"), item("Itm2")
  CoopMenu.rowsTop = a and a.Y
  CoopMenu.rowsStep = a and b and b.Y - a.Y
  local it = item("Itm1")
  it.onLeft = "CoopMenu.PrevLevel"
  it.onRight = "CoopMenu.NextLevel"
  local net = item("Itm2")
  net.onLeft = "CoopMenu.ToggleNet"
  net.onRight = "CoopMenu.ToggleNet"
  CoopMenu.refreshHost()
end

function CoopMenu.refreshHost()
  setText(item("Itm1"), "< " .. T("chapter") .. ": " .. CoopMenu.levelName(CoopMenu.LEVELS[CoopMenu.levelIndex]) .. " >")
  setText(item("Itm2"), "< " .. T("net") .. ": " .. T(cfg.net == "steam" and "net_steam" or "net_lan") .. " >")
end

-- The session's network: the local network (ENet, LAN list and IP) or Steam (a friends-only
-- lobby). Steam itself starts only when a session or the Steam screen uses it.
function CoopMenu.ToggleNet()
  cfg.net = cfg.net ~= "steam" and "steam" or nil
  CoopMenu.refreshHost()
end

-- Why Steam is not there, for the player.
function CoopMenu.steamError()
  local st = Net.CoopSteam and Net.CoopSteam("status") or ""
  local err = string.match(st, "error=(.*)$") or st
  if string.find(err, "not running", 1, true) then return T("steam_norun") end
  if string.find(err, "not found", 1, true) or not Net.CoopSteam then return T("steam_nodll") end
  return err
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
  if cfg.net == "steam" then
    local s = Net.CoopSteam and Net.CoopSteam("host", tostring(CoopMenu.MAX_PLAYERS - 1))
    Coop.log("lobby: steam host " .. tostring(s))
    if s ~= 1 then
      Net.CoopClose()
      CoopMenu.message(T("steam_off") .. " " .. CoopMenu.steamError())
      return
    end
    CoopMenu.steamReady = true
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
  local a, b = item("Itm1"), item("Itm2")
  CoopMenu.rowsTop = a and a.Y
  CoopMenu.rowsStep = a and b and b.Y - a.Y
  CoopMenu.lanNext = 0
  local it = item("Itm1")
  it.MaxInput = 21
  Coop.textBlock("CoopHint", T("join_hint"), {y = 130, font = Menu.SmallFont, color = Menu.ItemColor, width = 600})
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
        setText(it, string.format("LAN: %s - %s (%s/%s)", nick, CoopMenu.levelName(g.level or ""),
          g.players or "?", g.max or "?"))
      else
        setText(it, i == 1 and ("LAN: " .. T("lan_none")) or "")
      end
    end
  end
end

-- Join through Steam: friends' Steam lobbies (Net.CoopSteam "friends"), refreshed every
-- second while the screen is open.
CoopMenu.steamGames = {}

function CoopMenu.SteamJoinSetup()
  CoopMenu.screen = "steam"
  local options = {}
  for i = 1, CoopMenu.LAN_SLOTS do options[#options + 1] = {"", "CoopMenu.JoinSteam" .. i} end
  options[#options + 1] = {Menu.GetBackText(), "CoopMenu.Root"}
  Menu.VerticalMenu(T("title_steam"), options, "CoopMenu.Root")
  local a, b = item("Itm1"), item("Itm2")
  CoopMenu.rowsTop = a and a.Y
  CoopMenu.rowsStep = a and b and b.Y - a.Y
  local st = Net.CoopSteam and Net.CoopSteam("init") or ""
  CoopMenu.steamReady = string.find(st, "ready", 1, true) ~= nil
  Coop.log("lobby: steam screen, " .. tostring(st))
  local hint = CoopMenu.steamReady and T("steam_hint") or (T("steam_off") .. " " .. CoopMenu.steamError())
  Coop.textBlock("CoopHint", hint, {y = 130, font = Menu.SmallFont, color = Menu.ItemColor, width = 600})
  CoopMenu.steamNext = 0
  CoopMenu.refreshSteam()
end

function CoopMenu.refreshSteam()
  CoopMenu.steamGames = {}
  if CoopMenu.steamReady then
    for entry in string.gmatch(Net.CoopSteam("friends") or "", "[^;]+") do
      local name, lobby = string.match(entry, "^(.*)|(%d+)$")
      if lobby then CoopMenu.steamGames[#CoopMenu.steamGames + 1] = {lobby = lobby, nick = name} end
    end
  end
  for i = 1, CoopMenu.LAN_SLOTS do
    local it = item("Itm" .. i)
    local g = CoopMenu.steamGames[i]
    if it then
      if g then
        setText(it, "Steam: " .. Coop.cleanNick(g.nick or ""))
      else
        setText(it, i == 1 and CoopMenu.steamReady and T("steam_none") or "")
      end
    end
  end
  CoopMenu.keepRows(CoopMenu.rowsTop, CoopMenu.rowsStep)
end

function CoopMenu.joinSteam(i)
  local g = CoopMenu.steamGames[i]
  if g then CoopMenu.ConnectSteam(g.lobby, g.nick) end
end
for i = 1, 4 do CoopMenu["JoinSteam" .. i] = function() CoopMenu.joinSteam(i) end end

-- Join a friend's Steam lobby (from the Steam screen or an invite accepted in Steam).
function CoopMenu.ConnectSteam(lobby, name)
  Net.CoopClose()
  local ok = Net.CoopSteam("join", lobby)
  Coop.log("lobby: steam join " .. tostring(lobby) .. " -> " .. tostring(ok))
  cfg.joinLabel = "Steam: " .. Coop.cleanNick(name or "")
  cfg.net = "steam"
  cfg.role = "client"
  cfg.myId = nil
  CoopMenu.seats = {}
  CoopMenu.smodPeers = {}
  CoopMenu.Lobby()
end

-- Host of a Steam session: Steam's own invite dialog (overlay).
function CoopMenu.SteamInvite()
  local ok = Net.CoopSteam and Net.CoopSteam("invite")
  Coop.log("lobby: steam invite dialog " .. tostring(ok))
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
    -- (a Steam session is listed to Steam friends only, not on the LAN)
    if cfg.net == "steam" and Net.CoopSteam then
      Net.CoopSteam("text", text)
      Net.CoopAnnounce("")
    else
      Net.CoopAnnounce(text)
    end
  end
end

function CoopMenu.Connect()
  local addr = item("Itm1") and item("Itm1").Text or "127.0.0.1"
  addr = string.gsub(addr, "%s", "")
  cfg.addr = addr
  cfg.joinLabel = nil
  Net.CoopClose()
  local ok = Net.CoopJoin(addr, cfg.port or CoopMenu.PORT)
  Coop.log("lobby: join " .. addr .. " -> " .. ok)
  cfg.role = "client"
  cfg.myId = nil
  CoopMenu.seats = {}
  CoopMenu.smodPeers = {}
  CoopMenu.Lobby()
end

------------------------------------------------------------------------------
-- Lobby
------------------------------------------------------------------------------

function CoopMenu.Lobby()
  CoopMenu.screen = "lobby"
  CoopMenu.sub = nil
  local options = {
    {"", "CoopMenu.NextChar"},
    {CoopMenu.myNick(), "!EditText"},
    {"", "CoopMenu.ToggleTags"},
    -- A second player on this PC with gamepad 2 (split screen, coop_split.lua).
    {"", "CoopMenu.NextP2"},
    {"", "CoopMenu.ToggleReady"},
  }
  if Coop.isHost() then
    -- The session's rules live on their own screen: the lobby has to fit 4:3 screens and
    -- bigger menu fonts (SMOD).
    options[#options + 1] = {T("settings"), "CoopMenu.Settings"}
    options[#options + 1] = {T("start"), "CoopMenu.Start"}
    if cfg.net == "steam" then options[#options + 1] = {T("invite"), "CoopMenu.SteamInvite"} end
    options[#options + 1] = {T("close"), "CoopMenu.Leave"}
  else
    options[#options + 1] = {T("leave"), "CoopMenu.Leave"}
  end
  -- (a Steam host's lobby has one row more, "Invite friends": rows a little closer, from a
  -- little higher, or the last one left the screen)
  CoopMenu.lobbyTop = #options > 8 and CoopMenu.LOBBY_TOP - 8 or CoopMenu.LOBBY_TOP
  CoopMenu.lobbyStep = #options > 8 and CoopMenu.LOBBY_STEP - 3 or CoopMenu.LOBBY_STEP
  Menu.VerticalMenu(T("title_lobby"), options, "CoopMenu.Leave", nil, CoopMenu.lobbyTop - 52, CoopMenu.lobbyStep)
  local it = item("Itm1")
  it.onLeft = "CoopMenu.PrevChar"
  it.onRight = "CoopMenu.NextChar"
  item("Itm2").MaxInput = 16
  local p2 = item("Itm4")
  p2.onLeft = "CoopMenu.PrevP2"
  p2.onRight = "CoopMenu.NextP2"
  CoopMenu.nickSent = CoopMenu.myNick()
  -- Read-only lines: chapter and the player list.
  for i = 0, CoopMenu.MAX_PLAYERS do
    local t = Scorer.NewItem(0, "CoopLine" .. i, "Text")
    t.Text = ""
    t.Pos = V2D(320, CoopMenu.lineY(i))
    t.CentralText = 1
    t.Font = Menu.SmallFont
    t.Color = Menu.ItemColor
  end
  CoopMenu.refreshLobby()
end

-- Lobby rows: one step apart from LOBBY_TOP, set again on every refresh (one entry was seen
-- 14 units off its row, over its neighbour, without anything of ours moving it).
CoopMenu.LOBBY_TOP, CoopMenu.LOBBY_STEP = 246, 28
function CoopMenu.layoutRows()
  local i = 1
  while item("Itm" .. i) do
    item("Itm" .. i).Y = (CoopMenu.lobbyTop or CoopMenu.LOBBY_TOP) + (i - 1) * (CoopMenu.lobbyStep or CoopMenu.LOBBY_STEP)
    i = i + 1
  end
end

-- The settings and join rows drift the same way (0.2.1: the cutscene row, "Back", a LAN game
-- over their neighbour): one step apart from where the menu put the first row.
function CoopMenu.keepRows(top, step)
  if not top or not step or step <= 0 then return end
  local i = 1
  while item("Itm" .. i) do
    item("Itm" .. i).Y = top + (i - 1) * step
    i = i + 1
  end
end

-- Host: the session's rules (lobby sub-screen; the lobby keeps running underneath).
function CoopMenu.Settings()
  CoopMenu.sub = "settings"
  local options = {
    -- Who does character-only actions nobody holds (coop_claim.lua).
    {"", "CoopMenu.CycleActMode"},
    -- Vanilla difficulty, and how much tougher enemies get per extra player (coop_enemies.lua).
    {"", "CoopMenu.CycleSkill"},
    {"", "CoopMenu.CycleScaling"},
    -- QTEs pass by themselves for everyone (the game's own QTEMode 2), and how much damage
    -- the AI squadmates take (coop_enemies.lua): the host's choice, the same for all.
    {"", "CoopMenu.CycleQTE"},
    {"", "CoopMenu.CycleAISquad"},
    -- First-person scenes from each player's own character instead of the original camera
    -- (coop_scenes.lua S.povAllowed): an experiment, off by default.
    {"", "CoopMenu.TogglePov"},
  }
  -- With SMOD on the host: its rules for everyone when every player has SMOD (coop_smod.lua).
  if CoopMenu.hostSmod() then options[#options + 1] = {"", "CoopMenu.ToggleSmodRules"} end
  options[#options + 1] = {Menu.GetBackText(), "CoopMenu.Lobby"}
  Menu.VerticalMenu(T("title_settings"), options, "CoopMenu.Lobby", nil, 160, 35)
  local a, b = item("Itm1"), item("Itm2")
  CoopMenu.settingsTop = a and a.Y
  CoopMenu.settingsStep = a and b and b.Y - a.Y
  CoopMenu.refreshLobby()
end

function CoopMenu.refreshLobby()
  if CoopMenu.screen ~= "lobby" or not item("Itm1") then return end
  if CoopMenu.sub == "settings" then
    setText(item("Itm1"), T("act") .. ": " .. T("act_" .. (cfg.actmode or "players")))
    setText(item("Itm2"), CoopMenu.skillText())
    setText(item("Itm3"), T("scaling") .. ": " .. T("scale_" .. (cfg.scaling or "light")))
    setText(item("Itm4"), T("qte") .. ": " .. T("qte_" .. (cfg.qte or "normal")))
    local ai = T("ai_" .. (cfg.aisquad or "normal"))
    if (cfg.aisquad or "normal") == "normal" and CoopMenu.smodRules() then
      ai = string.format(T("ai_smod"), CoopSmod.ownValues().ai * 100 + 0.5)
    end
    setText(item("Itm5"), T("aisquad") .. ": " .. ai)
    setText(item("Itm6"), T("cutscenes") .. ": " .. T(cfg.povall and "pov_on" or "pov_off"))
    if CoopMenu.hostSmod() then
      local v = cfg.smodrules == false and "rules_game" or (CoopMenu.smodRules() and "rules_smod" or "rules_notall")
      setText(item("Itm7"), T("rules") .. ": " .. T(v))
    end
    CoopMenu.keepRows(CoopMenu.settingsTop, CoopMenu.settingsStep)
    return
  end
  CoopMenu.layoutRows()
  local level = CoopMenu.LEVELS[CoopMenu.levelIndex]
  local line0 = item("CoopLine0")
  if line0 then
    local status = Net.CoopStatus()
    if Coop.isClient() and not cfg.myId then
      CoopMenu.setLine(0, T("connecting") .. " " .. tostring(cfg.joinLabel or cfg.addr) .. "...")
    else
      local label = (CoopMenu.continueRec or cfg.continuing) and T("continue_from") or T("chapter")
      CoopMenu.setLine(0, label .. ": " .. CoopMenu.levelName(level))
    end
  end
  for i = 1, CoopMenu.MAX_PLAYERS do
    local t = item("CoopLine" .. i)
    local s = CoopMenu.seats[i]
    if t then
      if s then
        local who = (s.nick and s.nick ~= "") and s.nick or (s.peer == 0 and T("host_name") or (T("player") .. " " .. (s.peer + 1)))
        local you = s.peer == CoopMenu.myPeer() and " " .. T("you") or ""
        -- Act 1: the host is Ross until Ross dies (Coop.startChar), then takes the seat.
        local char = CoopMenu.charName(s.char)
        local ross = s.peer == 0 and string.find(string.lower(level or ""), "^alk_") and CoopMenu.charName("Ross") .. " -> " or ""
        local pp = Coop.peerOf(s.peer)
        local smod = (pp == 0 and Coop.isHost() and CoopMenu.hostSmod() or CoopMenu.smodPeers[pp]) and " [SMOD]" or ""
        local tail = smod .. (s.ready and "  - " .. T("is_ready") or "")
        -- A long nickname: drop "(you)", then Ross, then shorten the name, until it fits.
        CoopMenu.setLine(i, CoopMenu.fit({
          who .. you .. ": " .. ross .. char .. tail,
          who .. ": " .. ross .. char .. tail,
          who .. ": " .. char .. tail,
          string.sub(who, 1, 8) .. ".: " .. char .. tail,
        }, Menu.SmallFont))
      else
        CoopMenu.setLine(i, "")
      end
    end
  end
  local me = CoopMenu.seatOf(CoopMenu.myPeer())
  setText(item("Itm1"), "< " .. T("character") .. ": " .. (me and CoopMenu.charName(me.char) or "-") .. " >")
  setText(item("Itm3"), T("tags") .. ": " .. (cfg.tags == false and T("off") or T("on")))
  local p2 = CoopMenu.seatOf((CoopMenu.myPeer() or 0) + Coop.P2)
  setText(item("Itm4"), "< " .. T("p2") .. ": " .. (p2 and CoopMenu.charName(p2.char) or T("p2_none")) .. " >")
  setText(item("Itm5"), T("ready") .. ": " .. ((me and me.ready) and T("yes") or T("no")))
  if Coop.isHost() and item("Itm7") then
    setText(item("Itm7"), CoopMenu.allReady() and T("start") or T("start_wait"))
  end
  CoopMenu.checkNick()
end

-- The chapter line (0) and the player lines, below the title. CentralText centres the text
-- on its position vertically too, by the height the engine measures for it (a long line
-- counts as two), so every line is put back on its row after a text change.
function CoopMenu.lineY(i)
  return 94 + i * 28
end

function CoopMenu.setLine(i, text)
  local t = item("CoopLine" .. i)
  if t and t.Text ~= text then
    setText(t, text)
    t.Y = CoopMenu.lineY(i)
  end
end

-- The first text that fits on one line of the screen (4:3 included) in that font.
CoopMenu.LINE_WIDTH = 600

function CoopMenu.fit(texts, font)
  for _, text in ipairs(texts) do
    local ok, r = pcall(Scorer.SplitString, text, font, CoopMenu.LINE_WIDTH)
    if not ok or type(r) ~= "table" then
      if not CoopMenu.fitWarned then CoopMenu.fitWarned = true; Coop.log("lobby: line width unknown: " .. tostring(r)) end
      return text
    end
    if #r <= 1 then return text end
  end
  return texts[#texts]
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

-- The second player of a machine (split screen): a seat of its own, owner id peer + P2,
-- always ready with its machine. "-" removes it.
function CoopMenu.setP2(peer, char)
  local id = peer + Coop.P2
  for i, s in ipairs(CoopMenu.seats) do
    if s.peer == id then table.remove(CoopMenu.seats, i) break end
  end
  local main = CoopMenu.seatOf(peer)
  if char and char ~= "-" and main and not CoopMenu.taken(char, id) and #CoopMenu.seats < CoopMenu.MAX_PLAYERS then
    CoopMenu.seats[#CoopMenu.seats + 1] = {peer = id, char = char, ready = true,
                                           nick = Coop.cleanNick(string.sub(main.nick or "", 1, 13) .. " 2")}
  end
  CoopMenu.broadcastLobby()
end

function CoopMenu.cycleP2(step)
  local me = CoopMenu.myPeer()
  if me == nil then return end
  local cur = CoopMenu.seatOf(me + Coop.P2)
  -- none, then the free characters in the lobby's order
  local list = {"-"}
  for _, c in ipairs(CoopMenu.CHAR_ORDER) do
    if (cur and cur.char == c) or not CoopMenu.taken(c, me + Coop.P2) then list[#list + 1] = c end
  end
  local idx = 1
  for i, c in ipairs(list) do
    if c == (cur and cur.char or "-") then idx = i end
  end
  if #list == 1 or (not cur and #CoopMenu.seats >= CoopMenu.MAX_PLAYERS) then return end
  local nxt = list[(idx - 1 + step) % #list + 1]
  if Coop.isHost() then
    CoopMenu.setP2(me, nxt)
  else
    Net.CoopSend(0, 1, "p2|" .. nxt)
  end
  CoopMenu.refreshLobby()
end

function CoopMenu.NextP2() CoopMenu.cycleP2(1) end
function CoopMenu.PrevP2() CoopMenu.cycleP2(-1) end

function CoopMenu.myNick()
  local n = Coop.cleanNick(cfg.nick)
  if n == "" and CoopMenu.steamReady and Net.CoopSteam then n = Coop.cleanNick(Net.CoopSteam("name") or "") end
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

-- shared: every player gets the scene's QTE, one success is enough (coop_scenes.lua)
CoopMenu.QTE_MODES = {"normal", "auto", "shared"}
CoopMenu.AI_SQUAD = {"normal", "tough", "very"}
local function cycle(list, cur)
  for i, m in ipairs(list) do
    if m == cur then return list[i % #list + 1] end
  end
  return list[1]
end

function CoopMenu.CycleQTE()
  cfg.qte = cycle(CoopMenu.QTE_MODES, cfg.qte or "normal")
  CoopMenu.refreshLobby()
end

function CoopMenu.CycleAISquad()
  cfg.aisquad = cycle(CoopMenu.AI_SQUAD, cfg.aisquad or "normal")
  CoopMenu.refreshLobby()
end

function CoopMenu.hostSmod()
  return CoopSmod ~= nil and CoopSmod.present()
end

-- Every seated player has SMOD (the host's own SMOD for seat 0).
function CoopMenu.allSmod()
  for _, s in ipairs(CoopMenu.seats) do
    local peer = Coop.peerOf(s.peer)   -- a second player on a PC (split screen) has its SMOD
    if not (peer == 0 and CoopMenu.hostSmod() or CoopMenu.smodPeers[peer]) then return false end
  end
  return #CoopMenu.seats > 0
end

-- The session will play by the host's SMOD rules (CoopMenu.Start).
function CoopMenu.smodRules()
  return CoopMenu.hostSmod() and cfg.smodrules ~= false and CoopMenu.allSmod()
end

function CoopMenu.ToggleSmodRules()
  cfg.smodrules = cfg.smodrules == false and nil or false
  CoopMenu.refreshLobby()
end

function CoopMenu.TogglePov()
  cfg.povall = not cfg.povall or nil
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
  CoopMenu.smodPeers = {}
  CoopMenu.Root()
end

function CoopMenu.broadcastLobby()
  if not Coop.isHost() or CoopMenu.screen ~= "lobby" and CoopMenu.screen ~= "host" then return end
  local smod = {}
  for _, s in ipairs(CoopMenu.seats) do
    if s.peer == 0 and CoopMenu.hostSmod() or CoopMenu.smodPeers[s.peer] then smod[#smod + 1] = s.peer end
  end
  Net.CoopSend(-1, 1, "lobby|" .. CoopMenu.LEVELS[CoopMenu.levelIndex] .. "|" .. CoopMenu.seatsString() ..
               "|" .. (CoopMenu.continueRec and 1 or 0) .. "|" .. table.concat(smod, ","))
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
  cfg.qte, cfg.aisquad = cfg.qte or "normal", cfg.aisquad or "normal"
  -- SMOD's rules: the host's values, when every player has SMOD and the host keeps them on.
  cfg.smod = CoopMenu.smodRules() and CoopSmod.encode(CoopSmod.ownValues()) or nil
  Net.CoopSend(-1, 1, "start|" .. level .. "|" .. seats .. "|" .. cfg.skill .. "|" .. cfg.scaling .. "|" ..
               cfg.qte .. "|" .. cfg.aisquad .. "|" .. (cfg.povall and "own" or "orig") .. "|" .. (cfg.smod or "-"))
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
    Net.CoopSend(peer, 1, "welcome|" .. peer .. "|Menu|" .. CoopMenu.seats[#CoopMenu.seats].char .. "|" .. Coop.VERSION)
    CoopMenu.broadcastLobby()
  end
end

-- A player with another co-op version: off the session (the network messages differ).
function CoopMenu.refuse(peer, ver, nick)
  Coop.log("lobby: peer " .. peer .. " has version " .. tostring(ver) .. ", refused")
  Net.CoopClose(peer)
  CoopMenu.onLeave(peer)
  CoopMenu.message(string.format(T("version_peer"), Coop.cleanNick(nick or "") ~= "" and Coop.cleanNick(nick) or
    (T("player") .. " " .. (peer + 1)), Coop.VERSION))
end

function CoopMenu.onLeave(peer)
  if Coop.isHost() then
    for i, s in ipairs(CoopMenu.seats) do
      if s.peer == peer then table.remove(CoopMenu.seats, i) break end
    end
    for i, s in ipairs(CoopMenu.seats) do
      if s.peer == peer + Coop.P2 then table.remove(CoopMenu.seats, i) break end
    end
    CoopMenu.smodPeers[peer] = nil
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
  elseif kind == "ver" and Coop.isHost() then
    local s = CoopMenu.seatOf(peer)
    if s then s.ver = f[2] end
    if f[2] ~= Coop.VERSION then CoopMenu.refuse(peer, f[2]) end
    return true
  elseif kind == "nick" and Coop.isHost() then
    local s = CoopMenu.seatOf(peer)
    -- A client before 0.2 says nothing of its version: another version.
    if s and not s.ver then CoopMenu.refuse(peer, "<0.2", f[2]) return true end
    if s then
      s.nick = Coop.cleanNick(f[2])
      CoopMenu.broadcastLobby()
    end
    return true
  elseif kind == "p2" and Coop.isHost() then
    CoopMenu.setP2(peer, f[2])
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
    CoopMenu.smodPeers = {}
    for id in string.gmatch(f[5] or "", "%d+") do CoopMenu.smodPeers[tonumber(id)] = true end
    return true
  elseif kind == "start" and Coop.isClient() then
    Coop.log("lobby: host started " .. f[2] .. " (" .. table.concat(f, " ", 4) .. ")")
    cfg.skill = tonumber(f[4]) or cfg.skill
    cfg.scaling = f[5] or cfg.scaling
    cfg.qte, cfg.aisquad = f[6] or cfg.qte, f[7] or cfg.aisquad
    cfg.povall = f[8] == "own" or nil
    cfg.smod = f[9] ~= nil and f[9] ~= "-" and f[9] or nil
    CoopMenu.launch(f[2], f[3])
    return true
  elseif kind == "welcome" and Coop.isClient() and f[3] == "Menu" then
    if f[5] ~= Coop.VERSION then
      Coop.log("lobby: host version " .. tostring(f[5]) .. ", mine " .. Coop.VERSION)
      Net.CoopClose()
      CoopMenu.Root()
      CoopMenu.message(string.format(T("version_host"), f[5] or "0.1", Coop.VERSION))
      return true
    end
    cfg.myId = tonumber(f[2])
    Net.CoopSend(0, 1, "ver|" .. Coop.VERSION)
    Net.CoopSend(0, 1, "nick|" .. CoopMenu.myNick())
    if CoopMenu.hostSmod() then Net.CoopSend(0, 1, "smod|1") end
    return true
  elseif kind == "smod" and Coop.isHost() then
    CoopMenu.smodPeers[peer] = f[2] == "1" or nil
    Coop.log("lobby: peer " .. peer .. " has SMOD")
    CoopMenu.broadcastLobby()
    CoopMenu.refreshLobby()
    return true
  end
  return false
end

-- The game's start screen (language list, shown on every start): its entries carry a language.
function CoopMenu.onLanguageScreen()
  local it = item("Itm1")
  return it ~= nil and it.uData ~= nil and it.uData.Language ~= nil
end

function CoopMenu.update()
  -- Back from a session that ended by itself (host gone): say why, on the co-op screen.
  if cfg.notice and Coop.frame > 40 and CoopMenu.screen == nil and not CoopMenu.onLanguageScreen() then
    local why = cfg.notice
    cfg.notice = nil
    CoopMenu.Root()
    CoopMenu.message(T(why))
  end
  if CoopMenu.screen == "lobby" then CoopMenu.refreshLobby() end
  -- (a LAN game over "Connect", the chapter over "Create session", as the settings rows did)
  if CoopMenu.screen == "host" or CoopMenu.screen == "join" then
    CoopMenu.keepRows(CoopMenu.rowsTop, CoopMenu.rowsStep)
  end
  if CoopMenu.screen == "join" and Coop.frame >= (CoopMenu.lanNext or 0) then
    CoopMenu.lanNext = Coop.frame + 10
    CoopMenu.refreshLan()
  end
  if CoopMenu.screen == "steam" and Coop.frame >= (CoopMenu.steamNext or 0) then
    CoopMenu.steamNext = Coop.frame + 20
    CoopMenu.refreshSteam()
  end
  -- An invite accepted in Steam (or "Join game" in the friends list) while the co-op menus
  -- are open and Steam runs for the mod: that lobby is joined.
  if CoopMenu.steamReady and Net.CoopSteam and CoopMenu.screen and CoopMenu.screen ~= "lobby" and Coop.frame % 20 == 0 then
    local pending = Net.CoopSteam("pending")
    if pending and pending ~= "" and pending ~= 0 then CoopMenu.ConnectSteam(pending) end
  end
  CoopMenu.announce()
end

CoopMenu.hookMainMenu()
