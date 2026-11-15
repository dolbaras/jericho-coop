-- Offline check of the off-screen partner markers (coop_hud.lua H.side / H.edge, 0.3.4 gap G-A5): which side of the view a
-- partner is on, the marker's text, place and alignment, hidden with cfg.edges = false.
-- Run: lua tests/hud_mock_test.lua  (from mod/lua)
local function v3(x, y, z)
  local v = {x = x, y = y, z = z}
  return setmetatable(v, {__sub = function(a, b) return v3(a.x - b.x, a.y - b.y, a.z - b.z) end,
                          __add = function(a, b) return v3(a.x + b.x, a.y + b.y, a.z + b.z) end,
                          __index = {rot = function(self) return self end}})
end
V3D = v3
V2D = function(x, y) return {x = x, y = y} end
Color = function() return {} end
local items = {}
Scorer = {GetItem = function(u, n) return items[u .. n] end, NewItem = function(u, n) items[u .. n] = {}; return items[u .. n] end}
Coop = {cfg = {seats = "0:Black:1:Host;1:Church:1:Ann"}, ownerOf = function() return 1 end, nickShow = function(s) return s end,
        charName = function(n) return n end, level = "levels/x"}
-- the camera at the origin looking along +Z (no rotation: rot returns the vector)
local cam = {camPos = v3(0, 0, 0), camAng = v3(0, 0, 0)}
local ents = {Cam = cam}
Game = {GetEntity = function(n) return ents[n] end, Get = function() return nil end}
dofile("coop_hud.lua")
local H = CoopHud
H.nickCache = {[1] = "Ann"}

-- in front: right / left by x; behind with x > 0: right; behind with x < 0: left
assert(H.side("Cam", v3(100, 0, 500)) == 1, "front right")
assert(H.side("Cam", v3(-100, 0, 500)) == -1, "front left")
assert(H.side("Cam", v3(50, 0, -500)) == 1, "behind, a bit right: the right side")
assert(H.side("Cam", v3(-50, 0, -500)) == -1, "behind, a bit left: the left side")
local _, hy = H.side("Cam", v3(0, 300, 300))
assert(hy < 240, "above: higher on the screen: " .. hy)

-- the marker: text, side, alignment, kept in the middle band
local body = {Name = "Church", Pos = v3(-300, 0, -300), Life = 100}
H.headPos = function(e) return e.Pos end
H.edge(0, "Church", body, "Cam", 2500)
local it = items["0CoopEdge_Church"]
assert(it and it.Visible == 1 and it.Text == "< Ann 25 m" and it.Align == "Left" and it.Pos.x == H.EDGE_X.full[1], "left marker: " .. tostring(it and it.Text))
assert(it.Pos.y >= H.EDGE_Y[1] and it.Pos.y <= H.EDGE_Y[2], "middle band")
body.Pos = v3(400, 2000, 100)
H.edge(0, "Church", body, "Cam", 1000)
assert(it.Text == "Ann 10 m >" and it.Align == "Right" and it.Pos.x == H.EDGE_X.full[2] and it.Pos.y == H.EDGE_Y[1], "right marker, clamped: " .. it.Text)
-- split screen: inside the HUD corners' rule
CoopSplit = {on = true}
H.edge(1, "Church", body, "Cam", 1000)
assert(items["1CoopEdge_Church"].Pos.x == H.EDGE_X.split[2], "split: the half's own HUD, inner x")
CoopSplit = nil
-- switched off
Coop.cfg.edges = false
H.edge(0, "Church", body, "Cam", 1000)
assert(it.Visible == 0, "cfg.edges = false")
print("hud mock test: ok")
