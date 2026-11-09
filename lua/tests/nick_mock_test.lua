-- Offline check of nicknames across code pages (0.3.2): a nickname travels in UTF-8 both ways and
-- every screen shows it in its own font's code page (cp1251 for the Russian game, cp1252 for the
-- others), with the letters that font lacks written in its own alphabet; a seat without a nickname
-- is named in each machine's own language (up to 0.3.1 the sender's word for "Host" went out in
-- its code page: "Хост" from a Russian host showed as "Õîñò" on a German client). Also: the
-- messages' separators never get into a name, a name keeps NICK_MAX characters, the lobby's
-- nickname field (typed in this machine's code page), Steam's names (UTF-8 from native/steam_net.c
-- since 0.3.2), a 0.3.1 peer's bytes, the nameplates and choice cards, split screen player 2.
-- Run: lua tests/nick_mock_test.lua   (from mod/lua)

local failures, nChecks = {}, 0
local function check(ok, what)
  nChecks = nChecks + 1
  if not ok then failures[#failures + 1] = what end
  return ok
end
local function eq(got, want, what)
  return check(got == want, what .. ": got " .. string.format("%q", tostring(got)) .. ", want " .. string.format("%q", tostring(want)))
end

local function anything()
  return setmetatable({}, {__index = function(s, k) local v = anything() rawset(s, k, v) return v end,
                           __call = function() return nil end})
end
V2D = function(x, y) return {x = x, y = y} end
V3D = function(x, y, z) return {x = x, y = y, z = z} end
Color = function(r, g, b, a) return {r, g, b, a} end
function defparam(v, d) if v == nil then return d end return v end
local items = {}
local function fakeItem(name)
  local it = items[name]
  if not it then it = {Text = "", X = 320, Y = 100, Visible = 0}; items[name] = it end
  return it
end
Scorer = anything()
-- (items exist once made: loops look for the end of a list; Menu.VerticalMenu makes a screen's rows Itm1..n)
Scorer.GetItem = function(_, name) return items[name] end
Scorer.NewItem = function(_, name) return fakeItem(name) end
Scorer.SplitString = function(text) return {text} end
local sent = {}
Net = anything()
local clock = 100
Net.CoopTimeRaw = function() return clock end
Net.CoopT0 = 0
Net.CoopTime = function() return clock end   -- (coop.lua makes it from CoopTimeRaw)
Net.CoopLog = function() end
Net.CoopStatus = function() return "role=none" end
Net.CoopFile = function() return nil end
Net.CoopSend = function(to, rel, text) sent[#sent + 1] = {to = to, text = text} end
Game = anything()
Game.GetLevelPath = function() return "Levels/Menu" end
Game.Get = function() return nil end
Game.Set = function() end
Game.GetLangStr = function(k) return k end
Menu = anything()
Menu.GetBackText = function() return "Back" end
Menu.VerticalMenu = function(title, options)
  for name in pairs(items) do if string.find(name, "^Itm%d+$") then items[name] = nil end end
  for i, o in ipairs(options) do fakeItem("Itm" .. i).Text = o[1] end
end
Input = anything()
COOP_CFG = {lang = "en"}
COOP_DIR = ""

local function permissive(f, ...)
  local made = {}
  setmetatable(_G, {__index = function(_, k)
    if type(k) == "string" and string.find(k, "^Coop") then return nil end
    local v = anything() rawset(_G, k, v) made[k] = v return v
  end})
  local res = {pcall(f, ...)}
  setmetatable(_G, nil)
  for k, v in pairs(made) do if rawget(_G, k) == v then rawset(_G, k, nil) end end
  return unpack(res)
end
local ok, err = permissive(dofile, "coop.lua")
assert(ok, "coop.lua loads: " .. tostring(err))
for _, name in ipairs({"coop_hud.lua", "coop_choice.lua"}) do
  if not CoopHud or not CoopChoice then
    local mok, merr = permissive(dofile, name)
    assert(mok, name .. " loads: " .. tostring(merr))
  end
end
assert(CoopMenu and CoopHud and CoopChoice, "the menu, HUD and choice modules")
local cfg = Coop.cfg

-- UTF-8 of a code point list, cp1251 / cp1252 bytes of a few names.
local function U(...) local t = {} for i, c in ipairs({...}) do t[i] = Coop.utf8Char(c) end return table.concat(t) end
local HOST_RU = U(0x425, 0x43E, 0x441, 0x442)                       -- Хост (UTF-8)
local HOST_1251 = "\213\238\241\242"                                -- Хост (cp1251)
local BORIS_RU = U(0x411, 0x43E, 0x440, 0x438, 0x441)                -- Борис (UTF-8)
local BORIS_1251 = "\193\238\240\232\241"                           -- Борис (cp1251)
local MOJIBAKE = "\213\238\241\242"                                 -- the same bytes on a cp1252 font: Õîñò
local JURGEN = "J" .. U(0xFC) .. "rgen"                             -- Jürgen (UTF-8)
local JURGEN_1252 = "J\252rgen"
local YOZH = U(0x401, 0x436)                                         -- Ёж

-- 1. The functions themselves.
eq(Coop.utf8Codes(HOST_RU) and #Coop.utf8Codes(HOST_RU), 4, "UTF-8: four code points")
check(Coop.utf8Codes(HOST_1251) == nil, "cp1251 bytes are not UTF-8")
check(Coop.utf8Codes("\192\128") == nil and Coop.utf8Codes("\237\160\128") == nil and Coop.utf8Codes("\208") == nil,
  "UTF-8: overlong, surrogate and cut sequences refused")
eq(#Coop.NICK_LATIN_PLAIN, 0x17F - 0xBF, "the plain-letter table covers U+00C0-U+017F")
eq(#Coop.NICK_CYR_LATIN + 1, 0x60, "the Cyrillic-in-Latin table covers U+0400-U+045F")
eq(Coop.cleanNick(HOST_RU), HOST_RU, "a UTF-8 Russian name is kept")
eq(Coop.cleanNick(JURGEN), JURGEN, "a UTF-8 German name is kept")
eq(Coop.cleanNick("a|b;c:d[e]f%g\"h\\i{j}k`l"), "abcdefghijkl", "the messages' separators, markup, % and quotes never get in")
eq(Coop.cleanNick("  Big   Boss  "), "Big Boss", "spaces: single, none at the ends")
eq(Coop.cleanNick("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), "ABCDEFGHIJKLMNOP", "NICK_MAX characters")
eq(Coop.cleanNick(string.rep(U(0x416), 20)), string.rep(U(0x416), 16), "NICK_MAX characters, not bytes")
eq(Coop.cleanNick("x" .. U(0x4E2D) .. "y" .. U(0x1F600)), "xy", "characters no font has are left out")
eq(Coop.nickFromLocal(HOST_1251, "ru"), HOST_RU, "the Russian game's field (cp1251) -> UTF-8")
eq(Coop.nickFromLocal(JURGEN_1252, "de"), JURGEN, "a German game's field (cp1252) -> UTF-8")
eq(Coop.nickFromLocal("\168\184", "ru"), U(0x401, 0x451), "cp1251 Ё ё")
eq(Coop.cleanNick(HOST_1251, "ru"), HOST_RU, "bytes that are not UTF-8 (a 0.3.1 peer): this machine's code page")
eq(Coop.nickShow(HOST_RU, "ru"), HOST_1251, "Russian font: Cyrillic as cp1251")
eq(Coop.nickShow(HOST_RU, "de"), "Khost", "cp1252 font: Cyrillic in Latin letters")
check(Coop.nickShow(HOST_RU, "de") ~= MOJIBAKE, "cp1252 font: no Latin-1 mojibake")
eq(Coop.nickShow(JURGEN, "de"), JURGEN_1252, "cp1252 font: Latin-1 as itself")
eq(Coop.nickShow(JURGEN, "ru"), "Jurgen", "Russian font: the plain letter")
eq(Coop.nickShow(YOZH, "ru"), "\168\230", "Russian font: Ё")
eq(Coop.nickShow(YOZH, "fr"), "Yozh", "cp1252 font: Ё in Latin letters")
eq(Coop.nickShow(U(0x141) .. "ukasz " .. U(0xC6, 0x152, 0x153), "es"), "Lukasz \198OEoe", "Latin Extended-A and two-letter ones on cp1252")
eq(Coop.nickShow(U(0xC6, 0xDF), "ru"), "AEss", "two-letter ones on the Russian font")
eq(Coop.nickShow(U(0x404, 0x456, 0x491), "ru"), "\197i\227", "Ukrainian letters on the Russian font")
eq(Coop.nickCut(U(0x416, 0x416, 0x416), 2), U(0x416, 0x416), "a cut keeps whole characters")
for _, lang in ipairs({"en", "ru", "de", "fr", "es", "it"}) do
  for _, name in ipairs({HOST_RU, JURGEN, YOZH, "Plain_Name-1"}) do
    local shown = Coop.nickShow(name, lang)
    check(not string.find(shown, "[\128-\191][\128-\191]") or lang == "ru", "[" .. lang .. "] " .. name .. ": shown without UTF-8 bytes")
    check(Coop.utf8Codes(shown) == nil or not string.find(shown, "[\128-\255]"), "[" .. lang .. "] " .. name .. ": one byte per character")
    check(not string.find(shown, "?", 1, true), "[" .. lang .. "] " .. name .. ": no \"?\" (" .. shown .. ")")
  end
end

-- 2. The lobby across code pages: a Russian host, a German client, then the other way round.
local function lobbyAs(role, lang, nick, steamName)
  cfg.role, cfg.lang, cfg.nick, cfg.myId = role, lang, nick, role == "client" and 1 or nil
  CoopMenu.steamReady = steamName ~= nil
  Net.CoopSteam = function(cmd) if cmd == "name" then return steamName or "" end return "" end
  items = {}
  sent = {}
end
local function lastSent(prefix)
  for i = #sent, 1, -1 do if string.sub(sent[i].text, 1, #prefix) == prefix then return sent[i].text end end
end
local function seatLine(i) return items["CoopLine" .. i] and items["CoopLine" .. i].Text or "" end

-- 2a. Russian host with the nickname "Хост" typed (cp1251 in its field), German client "Jürgen".
lobbyAs("host", "ru", nil)
CoopMenu.seats = {{peer = 0, char = "Delgado", ready = true, nick = CoopMenu.myNick()}}
eq(CoopMenu.myNick(), "", "no nickname, no Steam: none on the network")
eq(CoopMenu.nickField(), Coop.enc("Хост", "ru"), "its field shows the seat's name in its language")
CoopMenu.Lobby()
items.Itm2.Text = BORIS_1251
CoopMenu.checkNick()
clock = clock + 2
CoopMenu.checkNick()
eq(cfg.nick, BORIS_RU, "the typed field (cp1251) becomes the UTF-8 nickname")
CoopMenu.onMessage(1, {"ver", Coop.VERSION})
CoopMenu.seats[#CoopMenu.seats + 1] = {peer = 1, char = "Black", ready = false, nick = ""}
CoopMenu.onMessage(1, {"ver", Coop.VERSION})
CoopMenu.onMessage(1, {"nick", JURGEN})
local seats = CoopMenu.seatsString()
check(string.find(seats, "0:Delgado:1:" .. BORIS_RU, 1, true) ~= nil, "host's seats carry its UTF-8 nickname: " .. seats)
check(string.find(seats, "1:Black:0:" .. JURGEN, 1, true) ~= nil, "host's seats carry the client's UTF-8 nickname: " .. seats)
CoopMenu.refreshLobby()
eq(seatLine(2):match("^[^:]+"), "Jurgen", "the Russian host shows the German client's name in its font")

lobbyAs("client", "de", JURGEN)
CoopMenu.screen = "lobby"
CoopMenu.onMessage(0, {"lobby", CoopMenu.LEVELS[1], seats, "0", ""})
CoopMenu.Lobby()
CoopMenu.refreshLobby()
eq(seatLine(1):match("^[^:]+"), "Boris", "the German client shows the Russian host's name in Latin letters")
check(string.find(seatLine(2), JURGEN_1252, 1, true) == 1, "the German client shows its own name in cp1252: " .. seatLine(2))
eq(items.Itm2.Text, JURGEN_1252, "its field shows its own nickname in cp1252")
-- (the welcome: version, then the nickname in UTF-8)
sent = {}
CoopMenu.onMessage(0, {"welcome", "1", "Menu", "Black", Coop.VERSION})
eq(lastSent("nick|"), "nick|" .. JURGEN, "the client sends its nickname in UTF-8")
-- an untouched field does not resend a changed name (cp1252 shows the same letters here)
sent = {}
CoopMenu.checkNick(); clock = clock + 2; CoopMenu.checkNick()
check(lastSent("nick|") == nil, "an untouched field sends nothing")

-- 2b. A host without a nickname: every client names it in its own language.
lobbyAs("host", "ru", nil)
CoopMenu.seats = {{peer = 0, char = "Delgado", ready = true, nick = CoopMenu.myNick()},
                  {peer = 1, char = "Black", ready = true, nick = ""}}
seats = CoopMenu.seatsString()
check(string.find(seats, "0:Delgado:1:;", 1, true) == 1, "no default word on the network: " .. seats)
for _, lang in ipairs({"en", "ru", "de", "fr", "es", "it"}) do
  lobbyAs("client", lang, nil)
  CoopMenu.screen = "lobby"
  CoopMenu.onMessage(0, {"lobby", CoopMenu.LEVELS[1], seats, "0", ""})
  CoopMenu.Lobby()
  CoopMenu.refreshLobby()
  local host = CoopMenu.T("host_name")
  local p2 = CoopMenu.T("player") .. " 2"
  check(string.find(seatLine(1), host, 1, true) == 1, "[" .. lang .. "] the host's seat in this language: " .. seatLine(1))
  check(string.find(seatLine(2), p2, 1, true) == 1, "[" .. lang .. "] the client's seat in this language: " .. seatLine(2))
  if lang ~= "ru" then check(not string.find(seatLine(1), "\213\238\241\242", 1, true), "[" .. lang .. "] no cp1251 \"Хост\"") end
end

-- 2c. Steam's name (UTF-8 from native/steam_net.c) and the Steam friends list.
lobbyAs("host", "ru", nil, JURGEN .. "|x")
eq(CoopMenu.myNick(), JURGEN .. "x", "the Steam name is the nickname (UTF-8, no separators)")
eq(CoopMenu.nickField(), "Jurgenx", "the Russian field shows it in its font")
CoopMenu.Lobby()
sent = {}
CoopMenu.checkNick(); clock = clock + 2; CoopMenu.checkNick()
eq(cfg.nick, nil, "an untouched field keeps the Steam name (its letters are not changed to the field's)")
Net.CoopSteam = function(cmd) if cmd == "friends" then return HOST_RU .. "|123;" .. JURGEN .. "|456" end return "" end
CoopMenu.steamReady = true
cfg.lang = "de"
CoopMenu.refreshSteam()
eq(items.Itm1.Text, "Steam: Khost", "German Steam list: a Russian friend")
eq(items.Itm2.Text, "Steam: " .. JURGEN_1252, "German Steam list: a German friend")

-- 2d. Split screen player 2's seat: its machine's nickname and " 2", whole characters.
lobbyAs("host", "ru", nil)
local long = string.rep(U(0x416), 16)
CoopMenu.seats = {{peer = 0, char = "Delgado", ready = true, nick = long}}
CoopMenu.setP2(0, "Church")
local p2 = CoopMenu.seatOf(Coop.P2)
eq(p2 and p2.nick, string.rep(U(0x416), 13) .. " 2", "player 2: 13 characters of its machine's name and \" 2\"")
CoopMenu.seats = {{peer = 0, char = "Delgado", ready = true, nick = ""}}
CoopMenu.setP2(0, "Church")
p2 = CoopMenu.seatOf(Coop.P2)
eq(p2 and p2.nick, "", "player 2 of a machine without a nickname: none")
cfg.lang = "de"
eq(CoopMenu.seatName(p2), CoopMenu.T("host_name") .. " 2", "named as its machine's seat and \" 2\" in this language")

-- 2e. A client of 0.3.1 (cp1251 bytes, another version): named in the refusal as well as can be.
lobbyAs("host", "ru", nil)
local msg
local realMessage = CoopMenu.message
CoopMenu.message = function(t) msg = t end
CoopMenu.refuse(1, "0.3.1", HOST_1251)
CoopMenu.message = realMessage
check(msg and string.find(msg, HOST_1251, 1, true) ~= nil, "the refusal names a 0.3.1 Russian peer: " .. tostring(msg))

-- 3. In a level: nameplates and the choice cards from the session's seats.
cfg.seats = "0:Delgado:1:" .. HOST_RU .. ";1:Black:1:" .. JURGEN .. ";2:Church:1:;" .. (1 + Coop.P2) .. ":Cole:1:"
Coop.owners = {Delgado = 0, Black = 1, Church = 2, Cole = 1 + Coop.P2}
for _, lang in ipairs({"ru", "de"}) do
  cfg.lang = lang
  CoopHud.nickCache = CoopHud.nicks()
  eq(CoopHud.label("Delgado"), Coop.nickShow(HOST_RU, lang), "[" .. lang .. "] plate: the host's nickname")
  eq(CoopHud.label("Black"), Coop.nickShow(JURGEN, lang), "[" .. lang .. "] plate: the client's nickname")
  eq(CoopHud.label("Church"), CoopChoice.text("player_n", 3), "[" .. lang .. "] plate: a seat without a nickname, in this language")
  eq(CoopHud.label("Cole"), CoopChoice.text("player_n", 2) .. " 2", "[" .. lang .. "] plate: split screen player 2 without one")
end
cfg.seats = nil
CoopHud.nickCache = CoopHud.nicks()
eq(CoopHud.label("Delgado"), Coop.charName("Delgado"), "no seats (a test session): the character's name")

if #failures > 0 then
  for _, f in ipairs(failures) do print("FAIL " .. f) end
  error(#failures .. " of " .. nChecks .. " nickname checks failed")
end
print(string.format("nick_mock_test: OK (%d checks)", nChecks))
