-- Offline check of Cole's grenades across machines (coop_powers.lua, 0.3.4 gap G-A3): the thrower's machine reports the grenade
-- the game makes, where it rests and its explosion; another machine shows a copy that never explodes or damages by itself and
-- plays the blast at the thrower's place.
-- Run: lua tests/grenade_mock_test.lua  (from mod/lua)
local clock = 100
local logs, sent = {}, {}
local role, me = "client", 3
Net = {CoopTime = function() return clock end, CoopSend = function(to, rel, msg) sent[#sent + 1] = {to = to, msg = msg} end}
V3D = function(x, y, z) return {x = x, y = y, z = z} end
local owners = {Cole = 3}
Coop = {cfg = {}, log = function(s) logs[#logs + 1] = s end, level = "levels/wwii_vigil",
        inSession = function() return true end, isHost = function() return role == "host" end, isClient = function() return role == "client" end,
        myId = function() return me end, isLocalPlayer = function(n) return owners[n] == me end,
        ownerOf = function(n) return owners[n] end, isPuppet = function(n) return owners[n] ~= nil and owners[n] ~= me end,
        heldBy = function(n, peer) return owners[n] == peer end}
local ents, made = {}, {}
local function newEnt(name, cls, pos)
  local e = {Name = name, Class = cls, Pos = pos, Vel = V3D(0, 0, 0), Ang = V3D(0, 0, 0), uData = {}}
  e.Del = function(self) ents[self.Name] = nil; self.deleted = true end
  ents[name] = e
  made[#made + 1] = e
  return e
end
Game = {GetEntity = function(n) return ents[n] end, CreateEntity = newEnt, Get = function() return 0 end}
local fx, explosions, damage = {}, {}, 0
FX = {BeginEffect = function(t, n) fx[#fx + 1] = "begin " .. tostring(n) end, SetEffect = function(t, n, c) fx[#fx + 1] = tostring(n) .. " " .. tostring(c) end}
ExplosiveWeapons = {DoExplosion = function(x, y, z, o, typ) explosions[#explosions + 1] = typ .. "@" .. x end, DoExplosionImpact = function() end}
Weapons = {QuakeFX = function() end, ExplotaExplotaQueExplo = function() damage = damage + 1 end}
local noticed = 0
AI = {NotifyImpact = function() noticed = noticed + 1 end}
local cole = newEnt("Cole", "WalkChar", V3D(0, 0, 0))
cole.oWeapCtrl = {Slot = function(self, i) return {UsrString = "Timed"} end}
-- the game's own functions (simplified: the real LaunchGrenade makes one Missile, PetaMina deals the damage)
WeaponsCole = {}
function WeaponsCole.LaunchGrenade(name)
  local o = Game.CreateEntity(name .. "_Grenade", "Missile", V3D(10, 20, 30))
  o.oParent = cole; o.Vel = V3D(1, 2, 3); o.bCheckIfStablePos = true; o.ReboundLimit = 15
end
function WeaponsCole.OnStopGrenade(name) end
function WeaponsCole.PetaMina(me, X, Y, Z, Radius, Damage, DoFX)
  Weapons.ExplotaExplotaQueExplo(X, Y, Z, me.oParent.Name, Radius, Damage, 0)
  ExplosiveWeapons.DoExplosion(X, Y, Z, nil, "Cole")
  me:Del()
end
function WeaponsCole.OnHit() end
SquadCfg = {Cole = {Mine = {Radius = 400}}}

dofile("coop_powers.lua")
local P = CoopPowers
P.installGrenades()

-- 1. the thrower (a client holding Cole): the throw is reported to the host
WeaponsCole.LaunchGrenade("0FP_Cole")
assert(#sent == 1 and sent[1].to == 0, "one message to the host")
local f = {}
for x in string.gmatch(sent[1].msg, "[^|]+") do f[#f + 1] = x end
assert(f[1] == "gr" and f[2] == "Cole" and f[3] == "3_1" and f[4] == "Timed" and f[5] == "10", "gr message: " .. sent[1].msg)
local grenade = made[#made]
-- it rests, then explodes: grs and grx with the same id, the damage dealt once (here)
WeaponsCole.OnStopGrenade(grenade.Name)
assert(sent[2].msg == "grs|Cole|3_1|10|20|30", "rest: " .. sent[2].msg)
WeaponsCole.PetaMina(grenade, 11, 21, 31, 400, 200, 1)
assert(damage == 1 and string.find(sent[3].msg, "^grx|Cole|3_1|11|21|31|1|400"), "explosion: " .. sent[3].msg)
local grMsgs = {sent[1].msg, sent[2].msg, sent[3].msg}

-- 2. the host gets them from peer 3 (who holds Cole): relays to everyone, shows a copy, the blast without damage
role, me = "host", 0
sent, explosions, damage = {}, {}, 0
local function deliver(msg, peer)
  local g = {}
  for x in string.gmatch(msg, "[^|]+") do g[#g + 1] = x end
  return P.onMessage(peer, g, msg)
end
assert(deliver(grMsgs[1], 3), "gr handled")
assert(#sent == 1 and sent[1].to == -1, "relayed to everyone")
local copy = made[#made]
assert(copy.Name == "CoopGr_3_1" and copy.Class == "Missile", "copy made: " .. tostring(copy.Name))
assert(copy.OnExplode == "CoopPowers.grShowExplode" and copy.OnHit == "CoopPowers.grShowHit" and copy.OnZeroSpeed == "CoopPowers.grShowStop",
  "show-only callbacks")
assert(copy.bExplodeOnHit == false and copy.TimeToExplode == P.GR_KEEP and copy.Vel.y == 2, "flies as the thrower's, never explodes by itself")
-- its own explode callback (the long timer ran out) does nothing
P.grShowExplode(copy)
assert(damage == 0 and #explosions == 0, "no blast, no damage from the copy itself")
deliver(grMsgs[2], 3)
assert(copy.Pos.x == 10 and copy.Pos.z == 30, "put where the thrower's rests")
deliver(grMsgs[3], 3)
assert(copy.deleted and #explosions == 1 and explosions[1] == "Cole@11" and damage == 0, "the blast shown at the thrower's place, no damage")
assert(noticed == 1, "the host's AI hears it")
-- 3. a peer that does not hold Cole cannot make grenades appear
sent = {}
assert(deliver("gr|Cole|9_1|Hit|1|2|3|0|0|0|0|0|0|1|15", 9) and #sent == 0, "not relayed from a peer without Cole")
-- 4. the thrower ignores its own relayed messages
role, me = "client", 3
local n = #made
deliver("gr|Cole|3_2|Hit|1|2|3|0|0|0|0|0|0|1|15", 0)
assert(#made == n, "own grenade not copied")
-- 5. a copy whose explosion never comes is removed after GR_KEEP
role, me = "client", 5
owners = {Cole = 3}
deliver("gr|Cole|3_7|Usr|1|2|3|0|0|0|0|0|0|0|0", 0)
local lost = made[#made]
assert(lost.bCheckIfStablePos == false and lost.ReboundLimit == 0, "sticky mine as thrown")
clock = clock + P.GR_KEEP + 10
P.grTidy()
assert(lost.deleted, "an orphan copy is tidied")
print("grenade mock test: ok")
