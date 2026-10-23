-- Offline check of coop_souls.lua (seat roles, refused switches, downed rule) with stub engine tables.
-- Run: lua tests/souls_mock_test.lua (from mod/lua)
local msgs = {}
local ents = {}
for _, n in ipairs({"Black", "Church", "Rawlings", "Jones", "Cole", "Delgado"}) do
  ents[n] = {Name = n, Life = 100, bActive = true}
end
Game = {
  GetEntity = function(n) return ents[n] end, GetTime = function() return 0 end,
  GetLangStr = function(n) return n end,
}
Net = {CoopTime = function() return 100 end}
Scorer = {SetMsgText = function(s) msgs[#msgs + 1] = s end}
Coop = {cfg = {seats = "0:Black:1:a;1:Church:1:b;2:Cole:1:c;3:Delgado:1:d"}, P2 = 8, level = "levels/wwii_mosque",
  owners = {Black = 0, Church = 1, Cole = 2, Delgado = 3},
  inSession = function() return true end, actOne = function() return false end,
  myId = function() return 0 end, localChar = function() return "Black" end,
  lang = function() return "en" end, enc = function(s) return s end, addLangs = function() end,
  log = function() end}
Coop.ownerOf = function(n) return Coop.owners[n] end
local switched
Team = {Icons = {Jones = 8, Cole = 10, Delgado = 9, Church = 6, Rawlings = 5, Black = 7}, UnavaliablePlayers = {},
  IsPlayerAvaliable = function(n)
    local c = ents[n]
    return not Team.UnavaliablePlayers[n] and c ~= nil and c.Life > 0 and c.bActive
  end,
  SetIdChar = function(e, idvar, Text, Name) e[idvar .. "OnSelect"] = "Team.SwitchSoldier" end,
  SwitchCharacter = function(n) switched = n end}
dofile("coop_souls.lua")
local S = CoopSouls
S.install()

assert(S.role(0) == "ross" and S.role(1) == "jones" and S.role(2) == "fixed" and S.role(3) == "fixed", "roles")
-- a split screen player of the host comes after the clients
local allOwners = Coop.owners
Coop.owners = {Black = 0, Jones = 8, Church = 1}
Coop.cfg.seats = "0:Black:1:a;8:Jones:1:p2;1:Church:1:b"
assert(S.role(1) == "jones" and S.role(8) == "fixed", "split screen seat after the clients")
Coop.owners = {Black = 0, Jones = 8}
Coop.cfg.seats = "0:Black:1:a;8:Jones:1:p2"
assert(S.role(8) == "jones", "split screen player as the second seat")
Coop.owners = allOwners
Coop.cfg.seats = "0:Black:1:a;1:Church:1:b;2:Cole:1:c;3:Delgado:1:d"

-- squad menu: seat 3 sees the others greyed out, seat 1 does not. The engine's menu fields are
-- write-only from Lua (a read is an engine error), so the stub refuses reads.
local function menu(name)
  local written = {}
  local e = setmetatable({}, {
    __index = function(_, k)
      if k == "Name" then return name end
      error("engine field read: " .. k)
    end,
    __newindex = function(_, k, v) written[k] = v end})
  return e, written
end
local e, ew = menu("Cole")
Team.SetIdChar(e, "Sele_Up_", "Jones", "Jones")
assert(ew.Sele_Up_OnSelect == "", "seat 3 menu greyed")
assert(string.find(msgs[#msgs], "you are Cole"), "reason told")
local h, hw = menu("Black")
Team.SetIdChar(h, "Sele_Up_", "Jones", "Jones")
assert(hw.Sele_Up_OnSelect == "Team.SwitchSoldier", "host menu free")

-- aiming switch: refused for seat 3, usable objects still used
ents.Cole.SelectedEntity, ents.Cole.AutoSelectedEntity = "Jones", ""
switched = nil; Team.SwitchCharacter("Cole"); assert(switched == nil, "seat 3 aim switch refused")
ents.Cole.AutoSelectedEntity = "Lever"
Team.SwitchCharacter("Cole"); assert(switched == "Cole", "usable object still works")
ents.Church.SelectedEntity, ents.Church.AutoSelectedEntity = "Jones", ""
switched = nil; Team.SwitchCharacter("Church"); assert(switched == "Church", "seat 2 switches")

-- Jones held: seat 2 refused, seat 1 free
ents.Jones.bActive = false
assert(not S.mayChoose(1) and S.mayChoose(0), "projection cut")
ents.Jones.bActive = true
-- Act 1: nobody
Coop.actOne = function() return true end
assert(not S.mayChoose(0) and not S.mayChoose(1), "act 1")
Coop.actOne = function() return false end

-- downed: seat 3 waits while Rawlings lives, else moves; seats 1-2 move
assert(S.waitsDowned("Cole") and not S.waitsDowned("Black") and not S.waitsDowned("Church"), "downed waits")
ents.Rawlings.Life = 0
assert(not S.waitsDowned("Cole"), "no Rawlings: moves")
-- off switch
Coop.cfg.souls = false
assert(S.mayChoose(3), "cfg.souls=false")
print("souls mock test ok")
