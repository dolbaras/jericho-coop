-- Offline checks of the split screen view option (tester report 2026-11-06, J-S1 "split screen
-- should be more stretched"): its row in the game's Video screen (coop.lua Coop.installDisplayMenu,
-- Coop.layoutVideo), its line in coop:display.txt beside the aspect ratio, the view and scales
-- coop_split.lua gives the engine (Sp.view, Sp.scales, Sp.wide, Sp.applyEngine; the test overrides
-- cfg.splitview / splitsx / splitsy first), the texts in six languages and the nameplates' place
-- over a filled half (coop_hud.lua H.splitPlace).
-- Run: lua tests/display_mock_test.lua [<the game's menu.lua>]   (from mod/lua)
-- With the game's decompiled scripts/menu/menu.lua (default ../../work/src/scripts/menu/menu.lua)
-- the layout is checked against its own Menu.VideoMenu as well; without it that part is skipped.
local MENU_LUA = arg and arg[1] or "../../work/src/scripts/menu/menu.lua"

local logs = {}
local files = {}
local gvars = {Platform = "PC", VideoWidth = 1920, VideoHeight = 1080, FullScreen = 1}
local splitCalls = {}

-- Anything the loaded files touch and this test does not care about (a table that answers every
-- field with another such table, called: nil); only while coop.lua loads.
local function anything()
  return setmetatable({}, {__index = function(s, k) local v = anything() rawset(s, k, v) return v end,
                           __call = function() return nil end})
end

V2D = function(x, y) return {x = x, y = y} end
V3D = function(x, y, z) return {x = x, y = y, z = z} end
Color = function(r, g, b, a) return {r, g, b, a} end
function defparam(v, d) if v == nil then return d end return v end

-- Scorer items: setting Pos sets X and Y (the engine's items do); children by item:NewItem.
local items = {}
local function newItem(name)
  local it = {Name = name, uData = {}}
  it.NewItem = function(self, n) local c = newItem(n) c.parent = self return c end
  return setmetatable(it, {__newindex = function(t, k, v)
    if k == "Pos" then rawset(t, "X", v.x) rawset(t, "Y", v.y) else rawset(t, k, v) end
  end})
end
Scorer = {
  Clear = function(id) items[id] = {} end,
  NewItem = function(id, name) items[id] = items[id] or {} local it = newItem(name) items[id][name] = it return it end,
  GetItem = function(id, name) return items[id] and items[id][name] end,
  SetDefault = function() end, SetOnCancel = function() end, SetCursor = function() end, SetMsgText = function() end,
}

Net = anything()
Net.CoopTime = function() return 100 end
Net.CoopLog = function(s) logs[#logs + 1] = s end
Net.CoopStatus = function() return "role=none" end
Net.CoopFile = function(p, m, s)
  if m == "r" then return files[p] end
  if m == "w" then files[p] = s return 1 end
  return files[p] and 1 or 0
end
Net.CoopDisplay = function(cmd)
  if cmd == "get" then return 0, 0 end
  if cmd == "rates" then return "60 144" end
  if cmd == "monitor" then return gvars.VideoWidth, gvars.VideoHeight, 0, 60 end
  return 1
end
Net.CoopSplit = function(mode, pads) splitCalls[#splitCalls + 1] = {mode, pads} return 0 end
Game = anything()
Game.GetLevelPath = function() return "Levels/Menu" end
Game.Get = function(k) return gvars[k] end
Game.Set = function(k, v) gvars[k] = v end
Game.GetLangStr = function(k) return k end
Game.GetVideoModes = function(i) if i == 0 then return 1 end return 1920, 1080, 32 end
Game.GetVideoCurrentMode = function() return 1 end
COOP_CFG = {lang = "en"}
COOP_DIR = ""

-- Game globals made up while a file loads are dropped after it (else "SMOD is there": FOVOVERRIDE);
-- the mod's own (Coop*) are not made up ("CoopSplit = CoopSplit or {}").
local function permissive(f, ...)
  local made = {}
  setmetatable(_G, {__index = function(_, k)
    if type(k) == "string" and string.find(k, "^Coop") then return nil end
    local v = anything() rawset(_G, k, v) made[k] = v return v
  end})
  local res = {pcall(f, ...)}
  setmetatable(_G, nil)   -- from here on an unknown global is nil again
  for k, v in pairs(made) do if rawget(_G, k) == v then rawset(_G, k, nil) end end
  return unpack(res)
end
local ok, err = permissive(dofile, "coop.lua")
assert(ok, "coop.lua loads: " .. tostring(err))
assert(CoopSplit and CoopSplit.view, "coop_split.lua loaded by coop.lua")
local Sp, cfg = CoopSplit, Coop.cfg

local function fresh()   -- a new level load: the file is read again
  Coop.dispFile, Coop.aspectSel, Coop.disp, Coop.dispSaved = nil, nil, nil, nil
end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-6 end
local function scalesAre(sx, sy, what)
  local a, b = Sp.scales()
  assert(near(a, sx) and near(b, sy), what .. ": scales " .. tostring(a) .. " " .. tostring(b))
  assert(Sp.wide() == true, what .. ": a filled half")
end
local function wholeView(what)
  assert(Sp.scales() == nil and Sp.wide() == false, what .. ": the whole picture")
end
local function engineIs(sx, sy, mode, what)
  local last = splitCalls[#splitCalls]
  assert(near(gvars.CameraViewScaleX, sx) and near(gvars.CameraViewScaleY, sy),
    what .. ": engine scales " .. tostring(gvars.CameraViewScaleX) .. " " .. tostring(gvars.CameraViewScaleY))
  assert(last and last[1] == mode, what .. ": split.c mode " .. tostring(last and last[1]))
end
local function hasLog(s)
  for _, l in ipairs(logs) do if string.find(l, s, 1, true) then return true end end
  return false
end

-- 1. No file: Fill on every screen (on 21:9 as before 0.3.1, on 16:9 instead of the whole picture).
fresh()
assert(Coop.splitChoice() == 1 and Sp.view().key == "fill", "default view fill")
for _, wh in ipairs({{2560, 1080}, {3440, 1440}, {1920, 1080}, {1600, 900}, {1680, 1050}, {1024, 768}}) do
  gvars.VideoWidth, gvars.VideoHeight = wh[1], wh[2]
  scalesAre(0.6, 1.2, "default at " .. wh[1] .. "x" .. wh[2])
end
gvars.VideoWidth, gvars.VideoHeight = 1920, 1080
Sp.applyEngine(true)
engineIs(0.6, 1.2, 1, "split on, fill")
assert(splitCalls[#splitCalls][2] == 0, "pads apart")
assert(hasLog("split: view fill, scales 0.60 1.20"), "view logged")
Sp.applyEngine(false, -1)
engineIs(1, 1, 0, "split off")

-- 2. A file of 0.3.0 (the aspect line alone, no newline): read as before, split = Fill.
files[Coop.DISPLAY_FILE] = "aspect\t1.777778"
fresh()
assert(Coop.aspectChoice() == 5, "0.3.0 file: aspect 16:9, got " .. tostring(Coop.aspectChoice()))
assert(Sp.view().key == "fill", "0.3.0 file: fill")

-- 3. The Video screen. The game's, as far as its layout goes (scripts/menu/menu.lua
-- Menu.VerticalMenu: rows one step of 35 apart from Y 217, linked up/down in a ring; then
-- Menu.VideoMenu on a PC: rows 2-3 switch left/right at X 100, rows 4-5 (Advanced, Back) at
-- Y 380 side by side, the resolution row's Down to Back).
local mockMenu
local function installMockMenu()
  Menu = {}
  mockMenu = Menu
  function Menu.LinkLR(l, r) l.Right = r.Name r.Left = l.Name end
  function Menu.LinkUD(u, d) u.Down = d.Name d.Up = u.Name end
  function Menu.VerticalMenu(title, options, back, font, ystart, vstep)
    ystart, vstep = ystart or 160, vstep or 35
    Scorer.Clear(0)
    for i = 1, #options do
      local m = Scorer.NewItem(0, "Itm" .. i, "Text")
      m.Text, m.OnAccept, m.CentralText = options[i][1], options[i][2], 1
      m.Pos = V2D(320, ystart + 22 + i * vstep)
    end
    for i = 1, #options - 1 do Menu.LinkUD(Scorer.GetItem(0, "Itm" .. i), Scorer.GetItem(0, "Itm" .. (i + 1))) end
    Menu.LinkUD(Scorer.GetItem(0, "Itm" .. #options), Scorer.GetItem(0, "Itm1"))
  end
  function Menu.Get_Aspect_Ratio_Status() return "Aspect" end
  function Menu.Get_Screen_Resolution_Status() return "Resolution: 1920x1080" end
  function Menu.Switch_Aspect_Ratio() end
  function Menu.Switch_Aspect_Ratio_Down() end
  function Menu.GetBackText() return "Back" end
  function Menu.VideoMenu(id, control)
    Menu.VerticalMenu("Video", {{"Gamma", "Menu.DoNothing"}, {Menu.Get_Aspect_Ratio_Status(), "Menu.Switch_Aspect_Ratio"},
      {Menu.Get_Screen_Resolution_Status(), "Menu.Switch_Next_Resolution"}, {"Advanced", "Menu.VideoAdvancedMenu"},
      {Menu.GetBackText(), "Menu.ConfigProto"}}, "Menu.ConfigProto")
    local i = Scorer.GetItem(0, "Itm2")
    i.onLeft, i.onRight, i.X = "Menu.Switch_Aspect_Ratio_Down", "Menu.Switch_Aspect_Ratio", 100
    i = Scorer.GetItem(0, "Itm3")
    i.onLeft, i.onRight, i.X = "Menu.Switch_Prev_Resolution", "Menu.Switch_Next_Resolution", 100
    i = Scorer.GetItem(0, "Itm4")
    i.Y, i.X = 380, 60
    i = Scorer.GetItem(0, "Itm5")
    i.Y, i.X = 380, 440
    Menu.LinkLR(Scorer.GetItem(0, "Itm4"), Scorer.GetItem(0, "Itm5"))
    Menu.LinkLR(Scorer.GetItem(0, "Itm5"), Scorer.GetItem(0, "Itm4"))
    Menu.LinkUD(Scorer.GetItem(0, "Itm3"), Scorer.GetItem(0, "Itm5"))
  end
  Menu.saved, Menu.cancelled = 0, 0
  function Menu.SaveConfig2() Menu.saved = Menu.saved + 1 end
  function Menu.CancelConfig() Menu.cancelled = Menu.cancelled + 1 end
  function Menu.MainMenu() end
  function Menu.AcceptMenuMultiline() end
end

local function fn(name)   -- "Coop.splitViewNext" -> the function
  local t = _G
  for part in string.gmatch(name, "[^%.]+") do t = t[part] end
  return t
end
local function row(n) return Scorer.GetItem(0, "Itm" .. n) end

-- The screen as the mod lays it out: eight rows, nothing on top of another, a ring of links.
local function checkLayout(what)
  assert(Coop.videoRows == true, what .. ": rows inserted")
  for i = 1, 8 do assert(row(i), what .. ": Itm" .. i) end
  assert(not row(9), what .. ": no ninth row")
  assert(string.find(row(4).Text, "Display mode", 1, true) and string.find(row(5).Text, "Refresh rate", 1, true) and
         string.find(row(6).Text, "Split screen: ", 1, true), what .. ": the mod's rows 4-6: " .. tostring(row(6).Text))
  assert(row(7).OnAccept == "Menu.VideoAdvancedMenu" and row(8).OnAccept == "Menu.ConfigProto", what .. ": Advanced, Back")
  local step = row(2).Y - row(1).Y
  assert(step >= 30, what .. ": step " .. step)
  for i = 2, 6 do
    assert(row(i).Y - row(i - 1).Y == step, what .. ": row " .. i .. " one step below row " .. (i - 1) ..
      " (" .. row(i - 1).Y .. " -> " .. row(i).Y .. ")")
    assert(row(i).X == 100, what .. ": row " .. i .. " at X 100, got " .. tostring(row(i).X))
  end
  local adv, back = row(7), row(8)
  assert(adv.Y == back.Y and adv.Y - row(6).Y >= 30, what .. ": Advanced/Back below the last row (" .. adv.Y .. ")")
  assert(adv.Y >= 380 and adv.Y <= 445, what .. ": Advanced/Back on the screen (Y " .. adv.Y .. ", the mod's main menu goes to 445)")
  assert(adv.X == 60 and back.X == 440, what .. ": Advanced left, Back right")
  -- nothing else on rows 1-6's lines or on the buttons' line
  for i = 1, 8 do
    for j = i + 1, 8 do
      if not (i == 7 and j == 8) then
        assert(math.abs(row(i).Y - row(j).Y) >= 30, what .. ": Itm" .. i .. " and Itm" .. j .. " overlap")
      end
    end
  end
  -- down: 1..8 and back to 1; up: the other way, both buttons up to the last row
  local seen, at = {}, "Itm1"
  for _ = 1, 8 do seen[#seen + 1] = at at = Scorer.GetItem(0, at).Down end
  assert(table.concat(seen, ",") == "Itm1,Itm2,Itm3,Itm4,Itm5,Itm6,Itm7,Itm8" and at == "Itm1",
    what .. ": down " .. table.concat(seen, ",") .. " -> " .. tostring(at))
  for i = 2, 6 do assert(row(i).Up == "Itm" .. (i - 1), what .. ": Itm" .. i .. ".Up " .. tostring(row(i).Up)) end
  assert(adv.Up == "Itm6" and back.Up == "Itm6", what .. ": buttons up to the split row")
  assert(adv.Right == "Itm8" and back.Left == "Itm7" and back.Right == "Itm7" and adv.Left == "Itm8", what .. ": Advanced <-> Back")
  local onL = {"Coop.displayModePrev", "Coop.displayHzPrev", "Coop.splitViewPrev"}
  local onR = {"Coop.displayModeNext", "Coop.displayHzNext", "Coop.splitViewNext"}
  for k = 1, 3 do
    local r = row(3 + k)
    assert(r.Left == "" and r.Right == "", what .. ": Itm" .. (3 + k) .. " not linked left/right")
    assert(r.onLeft == onL[k] and r.onRight == onR[k], what .. ": Itm" .. (3 + k) .. " switches")
    assert(type(fn(r.onLeft)) == "function" and type(fn(r.onRight)) == "function" and type(fn(r.OnAccept)) == "function",
      what .. ": Itm" .. (3 + k) .. " functions exist")
  end
  assert(row(2).onRight == "Menu.Switch_Aspect_Ratio" and row(3).onRight == "Menu.Switch_Next_Resolution", what .. ": the game's rows")
end

installMockMenu()
Coop.installAspectMenu()
Coop.installDisplayMenu()
assert(Menu.VideoMenu == Coop.videoMenu, "Video screen wrapped")
fresh()
Menu.VideoMenu(0, "Itm3")
checkLayout("mock screen")
assert(row(6).Text == "Split screen: Fill", "row shows the choice: " .. row(6).Text)

-- Stepping: right through the three and around, left back.
fn(row(6).onRight)(0, "Itm6")
assert(row(6).Text == "Split screen: Fill (closer)", "right: " .. row(6).Text)
fn(row(6).onRight)(0, "Itm6")
assert(row(6).Text == "Split screen: Whole picture", "right again: " .. row(6).Text)
fn(row(6).OnAccept)(0, "Itm6")
assert(row(6).Text == "Split screen: Fill", "accept button steps too, around: " .. row(6).Text)
fn(row(6).onLeft)(0, "Itm6")
assert(row(6).Text == "Split screen: Whole picture", "left: " .. row(6).Text)
fn(row(6).onLeft)(0, "Itm6")
assert(row(6).Text == "Split screen: Fill (closer)", "left again: " .. row(6).Text)
-- not kept yet: the file and the view as before
assert(files[Coop.DISPLAY_FILE] == "aspect\t1.777778", "nothing written before Accept")
assert(Sp.view().key == "fill", "the view changes only with Accept")

-- Accept on the Configuration screen: written beside the aspect, the view follows.
Menu.SaveConfig2(0, "Itm1")
assert(mockMenu.saved == 1, "the game's SaveConfig2 still runs")
assert(files[Coop.DISPLAY_FILE] == "aspect\t1.777778\nsplit\tcloser\n", "file: " .. string.format("%q", files[Coop.DISPLAY_FILE]))
assert(hasLog("display: split screen view closer"), "logged")
assert(Sp.view().key == "closer", "view closer")
scalesAre(0.75, 1.5, "closer")
Sp.applyEngine(true)
engineIs(0.75, 1.5, 1, "split on, closer")
-- the aspect row writes the same file: the split line stays
Menu.Switch_Aspect_Ratio(0, "Itm2")
assert(files[Coop.DISPLAY_FILE] == "aspect\t2.370370\nsplit\tcloser\n", "aspect step keeps split: " ..
  string.format("%q", files[Coop.DISPLAY_FILE]))
-- Cancel drops a change made after
Menu.VideoMenu(0, "Itm3")
assert(row(6).Text == "Split screen: Fill (closer)", "reopened: " .. row(6).Text)
fn(row(6).onRight)(0, "Itm6")
Menu.CancelConfig(0, "Itm1")
assert(mockMenu.cancelled == 1, "the game's CancelConfig still runs")
assert(Coop.disp.split == 2 and string.find(files[Coop.DISPLAY_FILE], "split\tcloser", 1, true), "cancelled")
Menu.VideoMenu(0, "Itm3")
assert(row(6).Text == "Split screen: Fill (closer)", "after Cancel: " .. row(6).Text)
-- a new level load reads both back
fresh()
assert(Coop.aspectChoice() == 6 and Sp.view().key == "closer", "read back after a load")
-- the whole picture, accepted: no scales, split.c mode 2
Menu.VideoMenu(0, "Itm3")
fn(row(6).onRight)(0, "Itm6")
assert(row(6).Text == "Split screen: Whole picture", "whole: " .. row(6).Text)
Menu.SaveConfig2(0, "Itm1")
wholeView("whole chosen")
Sp.applyEngine(true)
engineIs(1, 1, 2, "split on, whole")
assert(hasLog("split: view whole, scales 1.00 1.00"), "whole logged")
-- a display mode change still applies as before (and the split line is not written again)
local before = files[Coop.DISPLAY_FILE]
Menu.VideoMenu(0, "Itm3")
fn(row(4).onRight)(0, "Itm4")
Menu.SaveConfig2(0, "Itm1")
assert(files[Coop.DISPLAY_FILE] == before and hasLog("display: mode window"), "display mode applied as before")

-- 4. Test overrides first (cfg.splitview / splitsx / splitsy), the stored "whole" under them.
fresh()
assert(Sp.view().key == "whole", "stored whole")
cfg.splitview = "wide"   scalesAre(0.6, 1.2, "cfg.splitview wide = fill")
cfg.splitview = "fill"   scalesAre(0.6, 1.2, "cfg.splitview fill")
cfg.splitview = "closer" scalesAre(0.75, 1.5, "cfg.splitview closer")
cfg.splitview = "full"   wholeView("cfg.splitview full")
cfg.splitview = "whole"  wholeView("cfg.splitview whole")
cfg.splitview = "bogus"  wholeView("cfg.splitview unknown = whole, as before")
cfg.splitview = "wide"
cfg.splitsx, cfg.splitsy = 1.0, 2.0
scalesAre(1.0, 2.0, "cfg.splitsx/splitsy over a filled view")
Sp.applyEngine(true)
engineIs(1.0, 2.0, 1, "split on, test scales")
cfg.splitview = nil
wholeView("cfg.splitsx/splitsy leave the whole picture whole")
cfg.splitsx, cfg.splitsy = nil, nil

-- 5. Odd files: an unknown value, CRLF, an empty file, lines of a newer version kept.
files[Coop.DISPLAY_FILE] = "aspect\t1.333333\r\nsplit\twhole\r\n"
fresh()
assert(Coop.aspectChoice() == 2 and Sp.view().key == "whole", "CRLF file")
files[Coop.DISPLAY_FILE] = "split\tsideways\n"
fresh()
assert(Sp.view().key == "fill" and Coop.aspectChoice() == 1, "unknown value: fill, Auto")
files[Coop.DISPLAY_FILE] = ""
fresh()
assert(Sp.view().key == "fill", "empty file: fill")
files[Coop.DISPLAY_FILE] = "aspect\t0.000000\nzoom\t3\n"
fresh()
Coop.saveDisplay("split", "closer")
assert(files[Coop.DISPLAY_FILE] == "aspect\t0.000000\nsplit\tcloser\nzoom\t3\n", "newer lines kept: " ..
  string.format("%q", files[Coop.DISPLAY_FILE]))
-- the 0.3.0 reader (string.match(text, "aspect\t([%d%.]+)")) still finds its line
assert(tonumber(string.match(files[Coop.DISPLAY_FILE], "aspect\t([%d%.]+)")) == 0, "0.3.0 reads this file")

-- 6. Texts in the six languages: every key in each language's own table, nothing the game's
-- code page lacks ("?" from Coop.enc), the label's parts different words for each view.
local KEYS = {"split", "splitfill", "splitcloser", "splitwhole"}
for _, lang in ipairs({"en", "ru", "de", "es", "fr", "it"}) do
  cfg.lang = lang
  Coop.fillLang(Coop.TEXT, "Coop.TEXT", lang)
  local t = Coop.TEXT[lang]
  assert(type(t) == "table", lang .. ": Coop.TEXT")
  local seenText = {}
  for _, k in ipairs(KEYS) do
    assert(type(t[k]) == "string" and t[k] ~= "", lang .. ": " .. k)
    if lang ~= "en" then assert(t[k] ~= Coop.TEXT.en[k], lang .. ": " .. k .. " translated") end
    local s = Coop.text(k)
    assert(not string.find(s, "?", 1, true), lang .. ": " .. k .. " fits the code page")
    assert(not seenText[s], lang .. ": " .. k .. " differs from the others")
    seenText[s] = true
  end
  -- The mod's three Video rows fit a 4:3 / 5:4 screen (from X 100; live 2026-11-07 on 1280x1024 the
  -- Russian "Во всю ширину (крупнее)" and refresh rate rows ran off the edge): 33 characters at most,
  -- counted in the game's code page (Coop.text gives one byte per character).
  local rows = {}
  for _, m in ipairs({"full", "window", "borderless"}) do rows[#rows + 1] = Coop.text("mode") .. ": " .. Coop.text(m) end
  for _, v in ipairs({Coop.text("auto"), "144 " .. Coop.text("hzunit")}) do
    rows[#rows + 1] = Coop.text("hz") .. ": " .. v .. " " .. Coop.text("fullonly")
  end
  for _, v in ipairs({"fill", "closer", "whole"}) do rows[#rows + 1] = Coop.text("split") .. ": " .. Coop.text("split" .. v) end
  for _, r in ipairs(rows) do
    assert(#r <= 33, lang .. ": Video row of " .. #r .. " characters: " .. r)
  end
end
cfg.lang = "en"

-- 7. Nameplates over a split screen HUD (coop_hud.lua H.splitPlace): twice as far from the
-- middle over a filled half, none in the HUD's corners (drawn out at the screen's edges).
assert(pcall(dofile, "coop_hud.lua"), "coop_hud.lua loads")
local H = CoopHud
files[Coop.DISPLAY_FILE] = "split\tfill\n"
fresh()
local x, y = H.splitPlace(400, 240)
assert(x == 480 and y == 240, "fill: x doubled from the middle: " .. tostring(x))
assert(H.splitPlace(320, 200) == 320, "fill: the middle stays")
assert(H.splitPlace(450, 240) == 580, "fill: middle band, right")
assert(H.splitPlace(300, 50) == 280, "fill: top band between the corners")
assert(H.splitPlace(250, 50) == 180, "fill: top band, just right of the corner (x 180)")
assert(H.splitPlace(220, 50) == nil, "fill: into the top left corner (x 120): no plate")
assert(H.splitPlace(220, 240) == 120, "fill: middle band, left (x 120): shown")
assert(H.splitPlace(nil, nil) == nil, "behind the camera")
cfg.splitview = "whole"
assert(H.splitPlace(400, 240) == 400, "whole: as on the whole screen")
assert(H.splitPlace(100, 50) == nil and H.splitPlace(100, 240) == 100, "whole: corners as before")
cfg.splitview = nil
cfg.splittagx = false
assert(H.splitPlace(400, 240) == 400 and H.splitPlace(100, 50) == 100, "cfg.splittagx = false: as before")
cfg.splittagx = nil

-- 8. The game's own Video screen (its decompiled menu.lua), when it is there.
local f = io.open(MENU_LUA, "r")
if f then
  f:close()
  Menu = {}   -- (the game makes it before menu.lua)
  local okm, errm = permissive(dofile, MENU_LUA)
  assert(okm, "the game's menu.lua loads: " .. tostring(errm))
  assert(type(Menu.VideoMenu) == "function" and Menu.VideoMenu ~= Coop.videoMenu, "the game's Menu.VideoMenu")
  Coop.installAspectMenu()
  Coop.installDisplayMenu()
  EffectsFrame = {MenuIn = function() end}   -- (Menu.DrawBackMenu's fade-in)
  gvars.RT_HDRLevelsPow = 1                  -- (the gamma slider's value)
  fresh()
  local nlog = #logs
  Menu.VideoMenu(0, "Itm3")
  for i = nlog + 1, #logs do assert(not string.find(logs[i], "error", 1, true), "the game's screen: " .. logs[i]) end
  checkLayout("the game's screen")
  assert(row(1).uData.slider, "the gamma slider is there")
  print("display mock test: the game's Video screen checked (" .. MENU_LUA .. ")")
else
  print("display mock test: the game's menu.lua not found (" .. MENU_LUA .. "), its screen not checked")
end

print("display mock test: OK")
