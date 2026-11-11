-- Offline check of the mod's texts in the six languages (owner's rule: every text the mod adds or
-- changes is in the game's selected language: en, ru, de, fr, es, it; Coop.lang). Every text table
-- the modules register with Coop.addLangs has, in ru (the module itself) and de, fr, es, it
-- (lang_<code>.lua), every key of its English table and nothing else; no text equals the English one
-- unless SAME lists it (names, abbreviations, words these languages write the same way); the same
-- format directives in the same order (string.format takes them by position); nothing the game's code
-- page lacks ("?" from Coop.enc). Every text table a module keeps (en + ru) is registered, every table
-- of a lang file belongs to one, and the keys the code asks for by name exist. Last, the texts that
-- were shown in another language than the player's (2026-11-08 audit) are each machine's own now: the
-- action of a "character needed here" request (the host's text before), the choice cards' names for
-- a player without a nickname ("Host", "P1"), the reason Steam is unavailable (native/steam_net.c's
-- English).
-- Run: lua tests/lang_mock_test.lua   (from mod/lua)

local LANGS = {"ru", "de", "fr", "es", "it"}
-- Texts that are the English ones in these languages, on purpose: "<path>.<key>" -> languages.
local SAME = {
  ["CoopMenu.TEXT.net_steam"] = "ru de fr es it",               -- Steam
  ["CoopMenu.TEXT.qte"] = "ru de fr es it",                     -- QTE (the game's quick-time events)
  ["CoopChoice.TEXT.G1A_omega_name"] = "de es it",           -- the fire team Omega
  ["CoopChoice.TEXT.G1C_omega_name"] = "de es it",
  ["Coop.TEXT.hzunit"] = "de fr es it",                         -- Hz
  ["Coop.TEXT.auto"] = "de fr es it",                           -- "Auto" (a refresh rate, an aspect ratio)
  ["CoopChoice.TEXT.ok"] = "de fr es it",                       -- "(ok)" after a confirmed pick
  ["CoopMenu.TEXT.nick"] = "de",                                -- Nickname
  ["CoopMenu.TEXT.host_name"] = "de it",                        -- Host
  ["CoopChoice.TEXT.host_name"] = "de it",
  ["CoopMenu.TEXT.no"] = "es it",                               -- no
  ["CoopMenu.TEXT.coop"] = "it",                                -- Co-op
  ["CoopMenu.TEXT.title_root"] = "it",
  ["CoopSmod.TR.Cheats"] = "de",                                -- SMOD's menu entries
  ["CoopSmod.TR.Debug"] = "de it",
  ["CoopSmod.TR.Console"] = "fr it",
}
local sameUsed = {}

local failures = {}
local function check(ok, what)
  if not ok then failures[#failures + 1] = what end
  return ok
end

-- Anything the loaded files touch and this test does not care about (a table that answers every
-- field with another such table, called: nil); only while the files load.
local function anything()
  return setmetatable({}, {__index = function(s, k) local v = anything() rawset(s, k, v) return v end,
                           __call = function() return nil end})
end
V2D = function(x, y) return {x = x, y = y} end
V3D = function(x, y, z) return {x = x, y = y, z = z} end
Color = function(r, g, b, a) return {r, g, b, a} end
function defparam(v, d) if v == nil then return d end return v end
Scorer = anything()
Net = anything()
Net.CoopTimeRaw = function() return 100 end   -- (coop.lua makes Net.CoopTime from it)
Net.CoopT0 = 0
Net.CoopTime = function() return 100 end
Net.CoopLog = function() end
Net.CoopStatus = function() return "role=none" end
Net.CoopFile = function() return nil end
Game = anything()
Game.GetLevelPath = function() return "Levels/Menu" end
Game.Get = function() return nil end
Game.Set = function() end
Game.GetLangStr = function(k) return k end
COOP_CFG = {lang = "en"}
COOP_DIR = ""

-- Game globals made up while a file loads are dropped after it; the mod's own (Coop*) are not made up.
local loaded = {}
local function permissive(f, ...)
  local made = {}
  setmetatable(_G, {__index = function(_, k)
    if type(k) == "string" and string.find(k, "^Coop") then return nil end
    local v = anything() rawset(_G, k, v) made[k] = v return v
  end})
  local realDofile = dofile
  dofile = function(p, ...) loaded[p] = true return realDofile(p, ...) end
  local res = {pcall(f, ...)}
  dofile = realDofile
  setmetatable(_G, nil)
  for k, v in pairs(made) do if rawget(_G, k) == v then rawset(_G, k, nil) end end
  return unpack(res)
end

-- 1. Every module: coop.lua in the menu level loads its own; the level's modules (as coop.lua lists them) after it.
local ok, err = permissive(dofile, "coop.lua")
assert(ok, "coop.lua loads: " .. tostring(err))
local cfg = Coop.cfg
local src = io.open("coop.lua", "rb"):read("*a")
local modules = {}
for name in string.gmatch(src, "dofile, COOP_DIR %.%. \"(coop_[%w_]+%.lua)\"") do modules[#modules + 1] = name end
assert(#modules >= 20, "coop.lua's module list: " .. #modules)
for _, name in ipairs(modules) do
  if not loaded[name] then
    local mok, merr = permissive(dofile, name)
    check(mok, name .. " loads: " .. tostring(merr))
  end
end

local byPath = {}
local paths = {}
for tbl, path in pairs(Coop.langTables) do
  check(byPath[path] == nil, path .. " registered once")
  byPath[path] = tbl
  paths[#paths + 1] = path
end
table.sort(paths)
assert(#paths >= 20, "registered text tables: " .. #paths)

local files = {}
for _, lang in ipairs(LANGS) do
  if lang ~= "ru" then
    local fok, t = pcall(dofile, "lang_" .. lang .. ".lua")
    assert(fok and type(t) == "table", "lang_" .. lang .. ".lua: " .. tostring(t))
    files[lang] = t
    for path in pairs(t) do check(byPath[path] ~= nil, "lang_" .. lang .. ".lua: " .. path .. " is a registered table") end
  end
end
for _, path in ipairs(paths) do
  for _, lang in ipairs(LANGS) do Coop.fillLang(byPath[path], path, lang) end
end

local function directives(s)
  local t = {}
  for d in string.gmatch(s, "%%[-%d%.]*[%a%%]") do t[#t + 1] = d end
  return table.concat(t, " ")
end
local function questionMarks(s)
  local _, n = string.gsub(s, "%?", "")
  return n
end
local function inList(list, lang) return string.find(" " .. list .. " ", " " .. lang .. " ", 1, true) ~= nil end

-- One text of one language against its English one.
local function checkText(id, lang, en, s)
  if not check(type(s) == "string" and s ~= "", id .. " [" .. lang .. "]: missing") then return end
  if s == en then
    local allowed = SAME[id] and inList(SAME[id], lang)
    if allowed then sameUsed[id .. " " .. lang] = true end
    check(allowed, id .. " [" .. lang .. "]: the English text \"" .. en .. "\"")
  end
  check(directives(s) == directives(en), id .. " [" .. lang .. "]: directives \"" .. directives(s) ..
    "\", English \"" .. directives(en) .. "\"")
  local shown = Coop.enc(s, lang)
  check(questionMarks(shown) == questionMarks(s), id .. " [" .. lang .. "]: a character the game's code page lacks: " .. shown)
end

-- 2. Every registered table in every language.
local nTexts = 0
for _, path in ipairs(paths) do
  local tbl = byPath[path]
  if path == "CoopSmod.TR" then
    -- SMOD's English texts are the keys (Sm.tr), Russian in the module, the others in the lang files.
    local en = {}
    for k in pairs(tbl.ru or {}) do en[k] = k end
    check(next(en) ~= nil, path .. ": Russian texts")
    for _, lang in ipairs(LANGS) do
      local t = tbl[lang]
      if check(type(t) == "table", path .. " [" .. lang .. "]: a table") then
        for k in pairs(en) do checkText(path .. "." .. k, lang, k, t[k]); nTexts = nTexts + 1 end
        for k in pairs(t) do check(en[k] ~= nil, path .. "." .. k .. " [" .. lang .. "]: no such SMOD text") end
      end
    end
  elseif type(tbl.en) == "string" then
    for _, lang in ipairs(LANGS) do checkText(path, lang, tbl.en, tbl[lang]); nTexts = nTexts + 1 end
  else
    local en = tbl.en
    if check(type(en) == "table", path .. ": an English table") then
      for _, lang in ipairs(LANGS) do
        local t = tbl[lang]
        if check(type(t) == "table", path .. " [" .. lang .. "]: a table") then
          for k, v in pairs(en) do checkText(path .. "." .. k, lang, v, t[k]); nTexts = nTexts + 1 end
          for k in pairs(t) do check(en[k] ~= nil, path .. "." .. k .. " [" .. lang .. "]: not in the English table") end
        end
      end
    end
  end
end
for id, langs in pairs(SAME) do
  for lang in string.gmatch(langs, "%a+") do
    check(sameUsed[id .. " " .. lang], "SAME " .. id .. " [" .. lang .. "]: no longer the English text, take it off the list")
  end
end

-- 3. Every text table a module keeps (English and Russian texts) is registered: the other languages
-- reach only those.
local seen = {}
local function walk(t, name, depth)
  -- (a table with a metatable is a stand-in of this test's for something of the game's)
  if seen[t] or depth > 3 or getmetatable(t) ~= nil then return end
  seen[t] = true
  local en = rawget(t, "en")
  if (type(en) == "table" or type(en) == "string") and rawget(t, "ru") ~= nil then
    check(Coop.langTables[t] ~= nil, name .. ": a text table not registered with Coop.addLangs")
  end
  for k, v in pairs(t) do
    if type(v) == "table" and type(k) == "string" then walk(v, name .. "." .. k, depth + 1) end
  end
end
for name, v in pairs(_G) do
  if type(name) == "string" and string.find(name, "^Coop") and type(v) == "table" then walk(v, name, 0) end
end

-- 4. The keys the code asks for by name are in the English table (else the key itself is shown). A
-- call's first argument as a whole ("key" followed by "," or ")"; "act_" .. mode is checked below).
local K = "\"([%w_]+)\"%s*[,)]"
local USES = {
  {"coop.lua", "Coop.TEXT", {"Coop%.text%(" .. K}},
  {"coop_split.lua", "Coop.TEXT", {"Coop%.text%(" .. K}},
  {"coop_menu.lua", "CoopMenu.TEXT", {"%f[%w_.]T%(" .. K}},
  {"coop_choice.lua", "CoopChoice.TEXT", {"C%.text%(" .. K}},
  {"coop_claim.lua", "CoopClaim.TEXT", {"%f[%w_.]text%(" .. K}},
  {"coop_patrol.lua", "CoopPatrol.TEXT", {"LP%.text%(" .. K, "and \"(t%d)\""}},
  {"coop_session.lua", "CoopSession.TEXT", {"CS%.text%(" .. K}},
  {"coop_souls.lua", "CoopSouls.TEXT", {"S%.tell%(" .. K, "tellSeat%(id, " .. K}},
  {"coop_spectate.lua", "CoopSpectate.TEXT", {"S%.text%(" .. K, "and \"(multi)\" or \"(one)\""}},
  {"coop_spirit.lua", "CoopSpirit.TEXT", {"P%.text%(" .. K}},
  {"coop_splits.lua", "CoopSplits.TEXT", {"Sp%.text%(" .. K, "Sp%.notice%(" .. K, "near and \"([%w_]+)\" or \"([%w_]+)\""}},
  {"coop_squad.lua", "CoopSquad.TEXT", {"Q%.tell%(" .. K}},
  {"coop_story.lua", "CoopStory.TEXT", {"turnText%(" .. K, "St%.say%(" .. K}},
  {"coop_storysolo.lua", "CoopStorySolo.TEXT", {"SS%.text%(" .. K, "say = \"([%w_]+)\""}},
}
local nKeys = 0
for _, u in ipairs(USES) do
  local f = io.open(u[1], "rb")
  local text = f and f:read("*a") or ""
  if f then f:close() end
  local en = byPath[u[2]] and byPath[u[2]].en
  if check(text ~= "" and type(en) == "table", u[1] .. ": source and " .. u[2]) then
    for _, pat in ipairs(u[3]) do
      for a, b in string.gmatch(text, pat) do
        for _, key in ipairs({a, b}) do
          if key and key ~= "" then nKeys = nKeys + 1 check(en[key] ~= nil, u[1] .. ": key \"" .. key .. "\" not in " .. u[2]) end
        end
      end
    end
  end
end
-- (keys made from values)
local function needKey(path, key)
  nKeys = nKeys + 1
  check(byPath[path] and byPath[path].en[key] ~= nil, path .. ": key \"" .. key .. "\" (made from a value) missing")
end
for _, m in ipairs(Coop.MODES) do needKey("Coop.TEXT", m) end
for _, v in ipairs(Coop.SPLIT_VIEWS) do needKey("Coop.TEXT", "split" .. v.key) end
for _, list in ipairs({{"act_", CoopMenu.ACT_MODES}, {"scale_", CoopMenu.SCALINGS}, {"qte_", CoopMenu.QTE_MODES},
                       {"ai_", CoopMenu.AI_SQUAD}}) do
  for _, m in ipairs(list[2]) do needKey("CoopMenu.TEXT", list[1] .. m) end
end
needKey("CoopMenu.TEXT", "host_left")   -- cfg.notice (coop_session.lua)
for id, def in pairs(CoopChoice.DEFS) do
  needKey("CoopChoice.TEXT", id .. "_title")
  for _, g in ipairs(def.groups) do
    for _, part in ipairs({"_name", "_blurb", "_ex"}) do needKey("CoopChoice.TEXT", id .. "_" .. g.key .. part) end
  end
end
for n = 1, #CoopSplits.G4.STATIONS do needKey("CoopSplits.TEXT", "soul_station" .. n) end
for name, line in pairs(CoopStorySolo.LINES) do
  needKey("CoopStorySolo.TEXT", name)
  for _, st in ipairs(line.steps) do if st.say then needKey("CoopStorySolo.TEXT", st.say) end end
end

-- 5. Texts that came from another machine or from native code, in this machine's language.
local blocks = {}
local realBlock = Coop.textBlock
Coop.textBlock = function(name, text) blocks[name] = text end
Coop.textBlockHide = function(name) blocks[name] = nil end
local function enc(path, key, lang)
  local t = byPath[path] and byPath[path][lang]
  if not check(t and t[key], path .. "." .. key .. " [" .. lang .. "]: missing") then return "<" .. key .. " missing>" end
  return Coop.enc(t[key], lang)
end

-- 5a. A client's "character needed here" request: the action in its own language, not the host's.
for _, lang in ipairs({"en", "ru", "de", "fr", "es", "it"}) do
  cfg.lang = lang
  for _, hostLang in ipairs({"en", "ru", "de"}) do
    local hostText = Coop.enc(byPath["CoopClaim.TEXT"][hostLang].obj, hostLang)
    CoopClaim.flash = nil
    CoopClaim.onMessage(0, {"actreq", "gate1", "Delgado", hostText, "20"})
    CoopClaim.updateHud()
    local shown = blocks.CoopClaim or ""
    check(string.find(shown, enc("CoopClaim.TEXT", "obj", lang), 1, true) ~= nil,
      "claim request [" .. lang .. "], host in " .. hostLang .. ": the action in this language: " .. shown)
    if hostLang ~= lang then
      check(string.find(shown, hostText, 1, true) == nil, "claim request [" .. lang .. "]: the host's " .. hostLang .. " text shown")
    end
  end
end
CoopClaim.shown = nil

-- 5b. The squad choice cards: a player without a nickname (no lobby seats, as in a test session).
cfg.seats = nil
for _, lang in ipairs({"en", "ru", "de", "fr", "es", "it"}) do
  cfg.lang = lang
  Coop.frame = 0
  local s = {id = "G8", untilT = Net.CoopTime() + 20, cards = {1, 2}, humans = {0, 1, 9},
             state = {[0] = {g = 1, conf = true}, [1] = {g = 2}, [9] = {g = 2, conf = true}},
             locals = {{owner = 0, pad = 0, keys = {}}}}
  blocks = {}
  CoopChoice.draw(s)
  local cards = (blocks.CoopChoiceCard1 or "") .. "\n" .. (blocks.CoopChoiceCard2 or "")
  local host = enc("CoopChoice.TEXT", "host_name", lang)
  local p2 = string.format(enc("CoopChoice.TEXT", "player_n", lang), 2)
  check(string.find(cards, host .. " " .. enc("CoopChoice.TEXT", "ok", lang), 1, true) ~= nil, "choice card [" .. lang .. "]: the host: " .. cards)
  check(string.find(cards, p2 .. ", ", 1, true) ~= nil, "choice card [" .. lang .. "]: player 2: " .. cards)
  check(string.find(cards, p2 .. " 2 " .. enc("CoopChoice.TEXT", "ok", lang), 1, true) ~= nil, "choice card [" .. lang .. "]: player 2's split screen player: " .. cards)
  if lang ~= "en" then check(string.find(cards, "P1", 1, true) == nil and string.find(cards, "P9", 1, true) == nil, "choice card [" .. lang .. "]: no P1 / P9") end
end
Coop.textBlock = realBlock

-- 5c. Why Steam is unavailable: one of the menu's texts, never native/steam_net.c's English.
local REASONS = {
  ["steam=off error=Steam is not running"] = "steam_norun",
  ["steam=off error=steam_api.dll not found"] = "steam_nodll",
  ["steam=off error=Steam client too old"] = "steam_old",
  ["steam=off error=steam_api.dll too old (no SteamAPI_ManualDispatch_Init)"] = "steam_fail",
  ["steam=off error=Steam interfaces missing"] = "steam_fail",
  ["steam=off error=No appID found"] = "steam_fail",
  ["steam=off error=not started"] = "steam_fail",
  ["steam=ready role=none lobby=0 peers=0 name=x"] = "steam_fail",
}
local realSteam = Net.CoopSteam
for _, lang in ipairs({"en", "ru", "de", "fr", "es", "it"}) do
  cfg.lang = lang
  for status, key in pairs(REASONS) do
    Net.CoopSteam = function() return status end
    local got = CoopMenu.steamError()
    check(got == enc("CoopMenu.TEXT", key, lang), "Steam reason [" .. lang .. "] for \"" .. status .. "\": " .. tostring(got))
  end
end
Net.CoopSteam = realSteam
cfg.lang = "en"

if #failures > 0 then
  for _, f in ipairs(failures) do print("FAIL " .. f) end
  error(#failures .. " text problem(s)")
end
print(string.format("lang_mock_test: OK (%d tables, %d texts checked in %d languages besides English, %d keys asked for by name)",
  #paths, nTexts, #LANGS, nKeys))
