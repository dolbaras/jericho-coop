-- Offline check of coop_enemies.lua helpers: the missile window's end for a body that left the list, the flame
-- wrapper's results, the diag gate and the melee wrappers' arguments.
-- Run: lua tests/enemies_mock_test.lua  (from mod/lua)
local clock = 100
local logs = {}
Net = {CoopTime = function() return clock end, CoopSend = function() end}
V3D = function(x, y, z) return {x = x, y = y, z = z} end
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end, owners = {}, frame = 1, storyDriven = {}, puppetNoCollide = {},
        isHost = function() return Coop.role ~= "client" end, isClient = function() return Coop.role == "client" end,
        isRemoteOwned = function(n) return Coop.owners[n] ~= nil and Coop.owners[n] ~= 0 end,
        inSession = function() return true end, peerOf = function(o) return o end, ownerOf = function(n) return Coop.owners[n] end,
        isLocalPlayer = function() return false end, addLangs = function() end}
local ents = {}
local function body(name, pos) ents[name] = {Name = name, Life = 100, bActive = true, Active = 1, bIgnoreCollision = true, Pos = pos or V3D(0, 0, 0),
  IsType = function() return true end, TgType = "blue"}; return ents[name] end
Game = {GetEntity = function(n) return ents[n] end, UsrEntity = function() return ents.Local end, GetFirst = function() return nil end}
local ok, err = pcall(dofile, "coop_enemies.lua")
assert(ok, "load: " .. tostring(err))
local E = CoopEnemies
assert(E and E.mwApply, "module loaded")

-- 1. missile window: a body that leaves the list while open gets its puppet collision (off) back
Coop.owners = {Black = 1, Cole = 2}
local a, b = body("Black"), body("Cole")
Coop.puppetNoCollide = {Black = false, Cole = false}
E.mwOpen = {}
E.mwOpenBody(a); E.mwOpenBody(b)
assert(a.bIgnoreCollision == false and b.bIgnoreCollision == false and E.mwOpen.Black and E.mwOpen.Cole, "windows open")
-- Black dies / is driven by a story: out of the list; Cole stays and is wanted
E.mwApply({b}, {Cole = true})
assert(a.bIgnoreCollision == true and E.mwOpen.Black == nil, "body out of the list: collision off again, forgotten")
assert(b.bIgnoreCollision == false and E.mwOpen.Cole, "the body still in reach stays open")
-- the list is empty (nobody to hit): every open window is closed
E.mwApply({}, {})
assert(b.bIgnoreCollision == true and next(E.mwOpen) == nil, "empty list: windows closed")
-- a body released by the puppet code (no record any more) is not touched: its own state stays
body("Jones"); ents.Jones.bIgnoreCollision = false
Coop.puppetNoCollide.Jones = nil
E.mwOpen = {Jones = clock}
E.mwApply({}, {})
assert(ents.Jones.bIgnoreCollision == false and next(E.mwOpen) == nil, "released body keeps its state")
-- timeout path as before
a.bIgnoreCollision = true
E.mwOpenBody(a)
clock = clock + E.MW_HOLD + 0.1
E.mwApply({a}, {})
assert(a.bIgnoreCollision == true and E.mwOpen.Black == nil, "hold time over: closed")

-- 2. flames (host wrapper): the engine's own result goes through; with the window (default) a hit on a remote body's name
-- burns it; nothing diagnostic runs without cfg.dev (no capsule tests, no body listing when the line hit nothing)
local enemy = body("Nazi1"); enemy.TgType = "red"
local listed, rays = 0, 0
local origRemote, origRay = E.remoteBodies, E.rayToBody
E.remoteBodies = function() listed = listed + 1; return origRemote() end
E.rayToBody = function(...) rays = rays + 1; return origRay(...) end
local sent = {}
Net.CoopSend = function(to, rel, msg) sent[#sent + 1] = msg end
Coop.frame = 10
local function engine(r1, r2) return function() return r1, r2 end end
local P0, P1 = V3D(0, 0, 0), V3D(100, 0, 0)
Coop.cfg.dev = nil
body("Black"); Coop.owners = {Black = 1}
E.stats = {}
local r1, r2 = E.flameLine(engine(nil, nil), P0, P1, V3D(0, 100, 0), V3D(0, 100, 0), "R", "Nazi1", true)
assert(r1 == nil and r2 == nil and rays == 0, "nothing hit: no capsule tests (" .. rays .. ")")
r1, r2 = E.flameLine(engine(P1, "Wall"), P0, P1, V3D(0, 100, 0), V3D(0, 100, 0), "R", "Nazi1", true)
assert(r2 == "Wall" and rays == 0 and #sent == 0, "a wall: result passes through, no tests")
r1, r2 = E.flameLine(engine(P1, "Black"), P0, P1, V3D(0, 100, 0), V3D(0, 100, 0), "R", "Nazi1", true)
assert(r2 == "Black" and #sent == 1 and sent[1]:find("^pfire|Black"), "the remote body is told it burns: " .. tostring(sent[1]))
assert(not E.stats.flameNearRemote and not E.stats.flameNearLocal, "no reference counters without dev")
Coop.cfg.dev = true
ents.Local = ents.Black
r1, r2 = E.flameLine(engine(P1, "Wall"), P0, P1, V3D(0, 100, 0), V3D(0, 100, 0), "R", "Nazi1", true)
assert(rays > 0 and E.stats.flameNearRemote, "dev: the reference tests run")
Coop.cfg.dev = nil
E.remoteBodies, E.rayToBody = origRemote, origRay

-- 3. flames (client wrapper): a hit on a human's body is shown to the engine's code as a nameless hit (`true`: the
-- flame ends, nobody burns); only on a client
SummerianTest = nil
local engineOut = {P1, "Black"}
WeaponsNaziSoldier = {DoubleLineTest = function() return engineOut[1], engineOut[2] end}
Coop.role = "client"
E.installFlamesClient()
r1, r2 = WeaponsNaziSoldier.DoubleLineTest(P0, P1, nil, nil, "R", "Nazi1", true)
assert(r1 == P1 and r2 == true, "client: named hit on a human hidden: " .. tostring(r2))
engineOut = {P1, "Wall"}
ents.Wall = nil
r1, r2 = WeaponsNaziSoldier.DoubleLineTest(P0, P1, nil, nil, "R", "Nazi1", true)
assert(r2 == "Wall", "other results unchanged")
engineOut = {P1, "Black"}
Coop.role = "host"
r1, r2 = WeaponsNaziSoldier.DoubleLineTest(P0, P1, nil, nil, "R", "Nazi1", true)
assert(r2 == "Black", "a machine that is the host does not hide the hit")
WeaponsNaziSoldier = nil
Coop.role = "host"

-- 4. melee collision-window wrappers pass every argument (nil ones too) to the game's function
local seenArgs
Behemoth = {DrawAttack = function(...) seenArgs = {n = select("#", ...), ...} end}
Coop.cfg.window = true
E.installMelee()
Behemoth.DrawAttack("Nazi1", "Ev", 0.5, nil, "x", nil)
assert(seenArgs.n == 6 and seenArgs[1] == "Nazi1" and seenArgs[3] == 0.5 and seenArgs[5] == "x", "all arguments forwarded: " .. tostring(seenArgs.n))
Behemoth.DrawAttack("Nobody", "Ev", 1, 2)
assert(seenArgs.n == 4, "non-enemy: forwarded too")
Behemoth = nil
print("enemies mock test: ok")
