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

-- 5. (0.3.4) the level-start strip names the machines still loading: one name per machine (player 2's
-- seat id = peer + 8), the host and machines that said lready left out, the plain text without seats
Coop.role = "host"
Coop.P2 = 8
Coop.peerOf = function(o) return o >= 8 and o - 8 or o end
Coop.enc = function(s) return s end
Coop.nickShow = function(s) return s end
Coop.lang = function() return "en" end
Coop.cfg.seats = "0:Church:1:Hostie;3:Black:1:Ann;11:Jones:1:Ann P2;5:Cole:0:"
E.readyPeers = {}
local names = E.waitingNames()
assert(#names == 2 and names[1] == "Ann" and names[2] == "#5", "two machines loading: " .. table.concat(names, ","))
assert(E.waitText("en") == "Waiting for Ann, #5...", "strip: " .. E.waitText("en"))
E.readyPeers[3] = true
assert(E.waitText("en") == "Waiting for #5...", "Ann loaded: " .. E.waitText("en"))
E.readyPeers[5] = true
assert(E.waitText("en") == "Waiting for players...", "all loaded: the plain strip")
Coop.cfg.seats = nil
E.readyPeers = {}
assert(E.waitText("en") == "Waiting for players...", "no seats (test without the lobby): the plain strip")
Coop.cfg.seats = "0:Church:1:Hostie;3:Black:1:Ann"
Coop.role = "client"
assert(E.waitText("en") == "Waiting for players...", "a client has no ready list: the plain strip")
Coop.role = "host"
Coop.cfg.seats = nil

-- 6. (0.3.4) skip votes per player: a split screen player 2 is a voter of its own (owner id peer + 8), told apart by its
-- own pad's START / BACK; the strip names the local player still to press
do
  local status, pads, label, aborted, sent = "peers=0", {}, nil, 0, {}
  Net.CoopStatus = function() return status end
  Net.CoopKey = function(k, user) if k == -1 then return pads[user] or 0, 0, 0, 0, 0, 0, 0 end end
  Net.CoopSend = function(to, rel, msg) sent[#sent + 1] = msg end
  Scene = {IsPlaying = true, SceneName = "DM_Scene_Conversation"}
  Scorer = {SetLabelText = function(s) label = s end}
  Game.GetTime = function() return clock end
  Coop.myId = function() return Coop.role == "host" and 0 or 3 end
  Coop.owners = {}
  E.hostAbort = function() aborted = aborted + 1; E.skip = nil end
  E.skip = nil
  CoopSplit = nil
  assert(E.playerCount() == 1, "alone: one player")
  -- the host's split screen: two voters on one machine
  CoopSplit = {on = true}
  assert(E.playerCount() == 2, "host + its player 2: " .. E.playerCount())
  -- player 1 presses (keyboard or pad 1): one vote, the strip asks player 2
  local v = E.localVoters()
  assert(#v == 1 and v[1] == 0, "player 1's vote")
  E.voteSkip(v[1])
  local st = E.skipStrip
  assert(aborted == 0 and st and st[1] == "Skip scene: 1 of 2 players" and st[2] == "Player 2: press START to skip", "strip: " .. tostring(st and st[1]))
  -- drawn as two text items over the scene (the game's label line is not drawn during scenes, live 2026-11-15)
  local items = {}
  Scorer.GetItem = function(u, n) return items[n] end
  Scorer.NewItem = function(u, n) items[n] = {Y = 0}; return items[n] end
  V2D = function(x, y) return {x = x, y = y} end
  Color = function() return {} end
  Coop.setCentered = function(it, t) it.Text = t end
  E.updateSkipStrip()
  assert(items.CoopSkip.Text == "Skip scene: 1 of 2 players" and items.CoopSkip.Visible == 1 and items.CoopSkip2.Text == "Player 2: press START to skip",
    "strip items")
  -- player 1 again: still one vote
  E.voteSkip(0)
  assert(aborted == 0, "the same player twice is one vote")
  -- player 2 presses START on their own pad: the second vote ends the scene
  pads[1] = 0x10
  v = E.localVoters()
  assert(#v == 1 and v[1] == 8, "player 2's vote: " .. tostring(v[1]))
  E.voteSkip(v[1])
  assert(aborted == 1, "both voted: skipped")
  -- player 2 first (BACK), then player 1: the strip asks player 1
  pads[1] = 0x20
  E.voteSkip(E.localVoters()[1])
  assert(E.skipStrip[2] == "Player 1: press START / Esc to skip", "strip for player 1: " .. tostring(E.skipStrip[2]))
  -- the scene is over: the items go
  Scene.IsPlaying = false
  E.updateSkipStrip()
  assert(items.CoopSkip.Visible == 0 and E.skipStrip == nil, "strip hidden after the scene")
  Scene.IsPlaying = true
  pads[1] = 0
  -- a client with its own player 2: four voters (host, its player 2, the client, the client's player 2 = 3 + 8)
  status = "peers=1"
  Coop.owners = {Black = 0, Church = 8, Cole = 3, Jones = 11}
  assert(E.playerCount() == 4, "four players: " .. E.playerCount())
  -- the client's messages: "skipvote|scene|1" from the client's player 1, "|2" from its player 2
  E.skip = nil; aborted = 0
  E.voteSkip(0); E.voteSkip(8)
  E.onMessage = E.onMessage
  E.voteSkip(3)
  assert(aborted == 0, "three of four")
  E.voteSkip(3 + 8)
  assert(aborted == 1, "four of four: skipped")
  -- a client's own presses: one message per local player and showing
  Coop.role = "client"
  E.votedScene = nil; sent = {}
  E.sceneStartT = 5
  pads[1] = 0x10; pads[0] = 0x10
  v = E.localVoters()
  assert(#v == 2 and v[1] == 3 and v[2] == 11, "both pads held: both vote")
  pads = {}
  Coop.role = "host"
  CoopSplit, Scene, Scorer = nil, nil, nil
  Coop.owners = {}
end

-- 7. (0.3.4) rewards of joining players: a client's hit carries what the game would count, the host credits the kill to
-- that machine, which counts it; level pictures the host unlocks at a level's end go to everyone
do
  local sent = {}
  Net.CoopSend = function(to, rel, msg) sent[#sent + 1] = {to = to, msg = msg} end
  local counted, pics = {}, {}
  local vars = {MeleeKills = 49}
  Game.Get = function(k) return vars[k] or 0 end
  SaveGame = {IncreaseTracker = function(t) vars[t] = (vars[t] or 0) + 1; counted[#counted + 1] = t end,
              AddPic = function(n) pics[#pics + 1] = n; return true end,
              CheckVisitedLevels = function(name, add) if add then SaveGame.AddPic(7) end end,
              CheckLevelTrackVarValue = function() SaveGame.AddPic(9) end}
  -- client: the melee event's hit is tagged "m"
  Weapons = Weapons or {}
  Weapons.FP_MeleeHitEvent = function() return E.trkCtx end
  WeaponsChurch, ThreadsBlack = {FatHitEventUpGo = function() return E.trkCtx end}, {AbbObjSlot = function() return E.trkCtx end}
  Weapons.ExplosionDamage = function() return E.trkCtx end
  E.installRewardsClient()
  assert(Weapons.FP_MeleeHitEvent() == "m" and ThreadsBlack.AbbObjSlot() == "g" and WeaponsChurch.FatHitEventUpGo() == "m", "contexts")
  Weapons.NameTargetToExplode = "Nazi1"
  assert(Weapons.ExplosionDamage("Nazi1") == "x" and Weapons.ExplosionDamage("Nazi2") == "", "only an explosion's direct target")
  assert(E.trkCtx == nil, "context cleared after the call")
  E.installRewardsClient()
  assert(Weapons.FP_MeleeHitEvent() == "m", "not wrapped twice")
  -- host: the hit of peer 3 killed: trk to peer 3 only; a hit that does not kill: nothing
  Coop.role = "host"
  local nazi = {Name = "Nazi9", Life = 30, uData = {}}
  local cole = {Name = "Cole", Life = 100}
  ents.Nazi9, ents.Cole = nazi, cole
  E.origDamage = function(From, To, dmg) To.Life = To.Life - dmg return true end
  E.stats = E.stats or {}; E.stats.hitsApplied = E.stats.hitsApplied or 0
  E.applyHit("Nazi9", 10, "Cole", "", 0, "m", 3)
  assert(#sent == 0, "not killed: no credit")
  E.applyHit("Nazi9", 25, "Cole", "", 0, "m", 3)
  assert(#sent == 1 and sent[1].to == 3 and sent[1].msg == "trk|m|Nazi9", "credit: " .. tostring(sent[1] and sent[1].msg))
  E.applyHit("Nazi9", 25, "Cole", "", 0, "m", 3)
  assert(#sent == 1, "a dead enemy is not credited twice")
  -- client: counts it as the game does (the 50th melee kill unlocks the picture through the game's own tracker table)
  Coop.role = "client"
  E.onCredit("m", "Nazi9")
  assert(counted[1] == "MeleeKills" and vars.MeleeKills == 50, "counted")
  E.onCredit("?", "Nazi9")
  assert(#counted == 1, "unknown kinds ignored")
  -- host: level pictures (visited, Hard / no deaths) go to everyone, the host's own kill trackers do not
  Coop.role = "host"
  sent = {}
  E.installRewardsHost()
  SaveGame.CheckVisitedLevels("wwii_vigil", true)
  SaveGame.CheckLevelTrackVarValue("wwii_vigil", "Hard")
  SaveGame.AddPic(3)
  assert(#sent == 2 and sent[1].msg == "pic|7" and sent[2].msg == "pic|9", "level pictures sent: " .. #sent)
  assert(#pics == 3, "the host unlocks all three itself")
  -- client: a level picture
  Coop.role = "client"
  E.onPic("7")
  assert(pics[#pics] == 7, "client unlocks the level picture")
  Coop.role = "host"
  SaveGame, WeaponsChurch, ThreadsBlack = nil, nil, nil
end
print("enemies mock test: ok")
