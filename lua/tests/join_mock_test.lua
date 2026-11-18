-- Offline check of joining a running level (0.3.5, sync checklist G-E26): the host in a level tells a joining peer
-- ("inlevel"), a client in the menu answers with the in-level hello (once, only for the same co-op version), the host
-- seats it, refuses a full session, sends the session's settings and its save vars of the level before the welcome, and
-- the client's welcome applies them before the level load; a late joiner is told which enemies already died.
-- Run: lua tests/join_mock_test.lua   (from mod/lua)

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
Scorer.GetItem = function(_, name) return items[name] end
Scorer.NewItem = function(_, name) return fakeItem(name) end
Scorer.SplitString = function(text) return {text} end
local sent = {}
local closed = {}
Net = anything()
local clock = 100
Net.CoopTimeRaw = function() return clock end
Net.CoopT0 = 0
Net.CoopTime = function() return clock end
Net.CoopLog = function() end
Net.CoopStatus = function() return "role=none" end
Net.CoopFile = function() return nil end
Net.CoopSend = function(to, rel, text) sent[#sent + 1] = {to = to, text = text} end
Net.CoopClose = function(peer) closed[#closed + 1] = peer or "all" end
local level = "Levels/Menu"
local entities = {}
local function body(name, life) return {Name = name, Life = life or 100, bActive = true, Pos = V3D(10, 20, 30), Ang = V3D(0, 90, 0)} end
for _, n in ipairs({"Delgado", "Black", "Church", "Cole", "Jones", "Rawlings", "Ross"}) do entities[n] = body(n) end
Game = anything()
Game.GetLevelPath = function() return level end
Game.GetEntity = function(n) return entities[n] end
Game.GetFirstVarObj = function() return nil end
Game.GetSaveVar = function() return nil end
Game.Get = function(k) if k == "GameSkill" then return 1 end return nil end
Game.sets = {}
Game.Set = function(k, v) Game.sets[k] = v end
Game.GetLangStr = function(k) return k end
Game.LoadLevel = function(l) Game.loaded = l end
Menu = anything()
Menu.GetBackText = function() return "Back" end
Menu.VerticalMenu = function(title, options)
  for name in pairs(items) do if string.find(name, "^Itm%d+$") then items[name] = nil end end
  for i, o in ipairs(options) do fakeItem("Itm" .. i).Text = o[1] end
end
Input = anything()
COOP_CFG = {lang = "en", role = "client"}
COOP_DIR = ""
COOP_BOOT_LINE = function() return "boot" end

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
local mok, merr = permissive(dofile, "coop_menu.lua")
assert(mok, "coop_menu.lua loads: " .. tostring(merr))
assert(CoopMenu and CoopSave, "the menu and the save module")
local cfg = Coop.cfg
local function take(pred)
  local out = {}
  for _, m in ipairs(sent) do if pred(m) then out[#out + 1] = m end end
  return out
end
local function starts(prefix) return function(m) return string.sub(m.text, 1, #prefix) == prefix end end
local function kinds() local t = {} for _, m in ipairs(sent) do t[#t + 1] = string.match(m.text, "^[^|]*") end return table.concat(t, ",") end

-- 1. A client in the menu (no lobby seat yet): the host's "inlevel" makes it send the hello, once.
cfg.role, cfg.nick = "client", "Late"
Coop.level = "levels/menu"
sent = {}
check(CoopMenu.onMessage(0, {"inlevel", Coop.VERSION, "Rom_Outskirts"}) == true, "the menu takes 'inlevel'")
local hello = take(starts("hello|"))
eq(#hello, 1, "one hello")
eq(hello[1] and hello[1].to, 0, "the hello goes to the host")
check(hello[1] and string.find(hello[1].text, "|Late|" .. Coop.VERSION, 1, true) ~= nil, "the hello carries the nickname and the version")
CoopMenu.onMessage(0, {"inlevel", Coop.VERSION, "Rom_Outskirts"})
eq(#take(starts("hello|")), 1, "a second 'inlevel' does not send another hello")
-- another co-op version: no hello, the connection is closed, the lobby's own words are shown
CoopMenu.lateHello = nil
sent, closed = {}, {}
CoopMenu.onMessage(0, {"inlevel", "0.0.1", "Rom_Outskirts"})
eq(#take(starts("hello|")), 0, "another version: no hello")
eq(#closed, 1, "another version: the connection is closed")

-- 2. The host in a level: a joining peer is told; the lobby's host does not say it.
cfg.role = "host"
cfg.nick = "Host"
Coop.level = "levels/rom_outskirts"
level = "Levels/Rom_Outskirts"
sent = {}
Coop.onJoin(1)
eq(kinds(), "inlevel", "the host in a level answers a join with 'inlevel'")
eq(sent[1] and sent[1].text, "inlevel|" .. Coop.VERSION .. "|Rom_Outskirts", "its text: version and level")
sent = {}
Coop.level = "levels/menu"
Coop.onJoin(1)
eq(#sent, 0, "in the menu level 'inlevel' is not sent (the lobby's own welcome)")
Coop.level = "levels/rom_outskirts"

-- 3. The hello: settings, the host's vars and the seat before the welcome.
cfg.seats = "0:Delgado:1:Host"
cfg.skill, cfg.scaling, cfg.qte, cfg.aisquad, cfg.povall = 2, "full", "shared", "tough", true
Coop.owners = {Delgado = 0}
sent = {}
Coop.onMessage(1, "hello|Black|Late|" .. Coop.VERSION)
local order = kinds()
check(string.find(order, "^lset,sv,seats,welcome") ~= nil, "settings and vars come before the seat list and the welcome (got " .. order .. ")")
local lset = take(starts("lset|"))[1]
eq(lset and lset.text, "lset|2|full|shared|tough|own|-", "the settings travel as the lobby's start has them")
eq(lset and lset.to, 1, "the settings go to the joiner only")
eq(take(starts("sv|"))[1] and take(starts("sv|"))[1].to, 1, "the save vars go to the joiner only")
local w = take(starts("welcome|"))[1]
check(w and string.find(w.text, "^welcome|1|Rom_Outskirts|Black") ~= nil, "the welcome names the level and the body")
eq(Coop.owners.Black, 1, "the joiner holds Black")
-- (the host's save vars off: the switch for the live comparison)
cfg.latesv = false
sent = {}
Coop.onMessage(2, "hello|Church|Third|" .. Coop.VERSION)
eq(#take(starts("sv|")), 0, "latesv=false: no vars sent")
cfg.latesv = nil

-- 4. A full session: three machines are in already.
cfg.seats = "0:Delgado:1:Host;1:Black:1:A;2:Church:1:B;3:Cole:1:C"
Coop.owners = {Delgado = 0, Black = 1, Church = 2, Cole = 3}
sent, closed = {}, {}
Coop.onMessage(4, "hello|Jones|Fifth|" .. Coop.VERSION)
eq(#take(starts("full|")), 1, "a fourth client gets 'full'")
eq(#take(starts("welcome|")), 0, "no welcome for it")
eq(closed[1], 4, "its connection is closed")
-- seats count as in the lobby (split screen player 2 too); the joiner's own seats do not
cfg.seats = "0:Delgado:1:Host;1:Black:1:A;" .. (1 + Coop.P2) .. ":Cole:1:A2"
Coop.owners = {Delgado = 0, Black = 1, Cole = 1 + Coop.P2}
sent, closed = {}, {}
Coop.onMessage(3, "hello|Jones|Third|" .. Coop.VERSION)
eq(#take(starts("welcome|")), 1, "three seats (one a split screen player 2): a fourth player is welcome")

-- 5. The client's welcome in the menu: settings first, then the save vars, then the load.
cfg.role, cfg.myId, cfg.seats, cfg.owners = "client", nil, nil, nil
cfg.skill, cfg.scaling, cfg.qte, cfg.aisquad, cfg.povall = nil, nil, nil, nil, nil
Coop.level = "levels/menu"
CoopSave.pending = {level = "Rom_Outskirts", vars = {}}
local applied
local origApply = CoopSave.apply
CoopSave.apply = function(rec) applied = rec end
Game.loaded, Game.sets = nil, {}
Coop.onMessage(0, "lset|2|full|shared|tough|own|-")
eq(cfg.skill, 2, "client: game skill")
eq(cfg.scaling, "full", "client: toughness")
eq(cfg.qte, "shared", "client: QTE")
eq(cfg.aisquad, "tough", "client: AI squadmates")
eq(cfg.povall, true, "client: own eyes")
Coop.onMessage(0, "welcome|1|Rom_Outskirts|Black")
eq(Game.loaded, "Levels/Rom_Outskirts", "the welcome loads the host's level")
check(applied ~= nil and applied.level == "Rom_Outskirts", "the host's save vars are applied before the load")
eq(Game.sets.GameSkill, 2, "the host's game skill is set")
CoopSave.apply = origApply

-- 6. Enemies the host killed are listed for the catch-up.
local eok, eerr = permissive(dofile, "coop_enemies.lua")
check(eok and CoopEnemies ~= nil, "coop_enemies.lua loads: " .. tostring(eerr))
if CoopEnemies then
  CoopEnemies.deadNames = {Enemy_3 = true, Enemy_9 = true}
  cfg.role = "host"
  sent = {}
  Game.GetFirst = function() return nil end
  CoopEnemies.sendCatchup(1)
  local dead = take(starts("edie|"))
  eq(#dead, 2, "catch-up: both dead enemies named")
  check(dead[1] and string.sub(dead[1].text, -2) == "|1", "catch-up: removed quietly")
end

-- 7. Nanna's / Utu's heart state (0.3.5, G-D19): the host's engine AI calls <Class>.OnHeartStateChanged; the change goes to the clients,
-- is applied there with the game's own function, and a late joiner is told the current state.
if CoopEnemies then
  local calls = {}
  SummerianNANNA = {OnHeartStateChanged = function(state, name) calls[#calls + 1] = "N:" .. tostring(state) .. ":" .. tostring(name) end}
  SummerianUTU = {OnHeartStateChanged = function(state, name) calls[#calls + 1] = "U:" .. tostring(state) .. ":" .. tostring(name) end}
  cfg.role = "host"
  CoopEnemies.installHeart()
  sent = {}
  SummerianNANNA.OnHeartStateChanged(2, "Nanna")
  SummerianUTU.OnHeartStateChanged(1, "Utu")
  eq(#take(starts("eheart|")), 2, "heart: both changes are sent")
  eq(take(starts("eheart|"))[1].text, "eheart|SummerianNANNA|2|Nanna", "heart: the message")
  eq(calls[1] .. calls[2], "N:2:NannaU:1:Utu", "heart: the game's own function still runs on the host")
  CoopEnemies.installHeart()
  sent = {}
  SummerianNANNA.OnHeartStateChanged(0, "Nanna")
  eq(#take(starts("eheart|")), 1, "heart: installed once (a second install does not send twice)")
  cfg.heartsync = false
  sent = {}
  SummerianNANNA.OnHeartStateChanged(1, "Nanna")
  eq(#take(starts("eheart|")), 0, "heartsync=false: nothing sent")
  cfg.heartsync = nil
  sent = {}
  CoopEnemies.sendCatchup(2)
  local hs = take(starts("eheart|"))
  eq(#hs, 2, "catch-up: the heart states the host reached (Nanna and Utu)")
  -- the client applies it
  cfg.role = "client"
  calls = {}
  local E = CoopEnemies
  entities.Nanna, entities.Utu = body("Nanna"), body("Utu")
  E.onMessage(0, {"eheart", "SummerianNANNA", "2", "Nanna"})
  eq(calls[1], "N:2:Nanna", "client: the host's state is applied with the game's function")
end

if #failures > 0 then
  for _, f in ipairs(failures) do print("FAIL " .. f) end
  error(#failures .. " of " .. nChecks .. " join checks failed")
end
print(string.format("join_mock_test: OK (%d checks)", nChecks))
