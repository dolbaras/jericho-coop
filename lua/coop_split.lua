-- Local split screen in one game: a second player on this PC with gamepad 2.
--
-- The engine kept the Scrapland split screen data (docs/splitscreen-research.md): four
-- users, a camera per user, a HUD per user drawn in the top and bottom halves
-- (SplitScreen=1), and its input drives a body with UsrControl 1 from pad 2 (Joy2) by
-- itself: walking, aiming, shooting, reloading, the squad selector. What it lost is the
-- world in two views: it renders one camera per frame (slot R_SplitScreenCamera with
-- R_SplitScreen=1). Here that slot changes every frame and native/split.c puts each
-- frame's world into its half of one picture before the HUDs are drawn on top.
--
-- The second player is a seat of its own in the session: owner id = this machine's peer id
-- + Coop.P2 (coop.lua), so "one body per owner" holds everywhere.
--
-- What is user 0 only in the game's scripts is handled here: switching bodies (the squad
-- selector), the camera and HUD of user 1, effects that carry over from the previous frame
-- (another camera's here), and full screen while a scene or a menu is up.

CoopSplit = CoopSplit or {}
local Sp = CoopSplit
local cfg = Coop.cfg

Sp.CAM = "CoopCam1"
-- Effects that blend the previous frame into this one: with the cameras taking turns they
-- smear one view into the other (pixel motion blur) or flicker (HDR adaptation).
Sp.FX = {RT_PixelMotionBlurPower = 0, RT_PixelMotionBlur = 0, RT_HDRExposureTime = 0.01}
-- How each half shows its view (lobby setting cfg.splitview):
--   "full" (default): the whole normal frame, shape kept, in the middle of the half (black
--     sides): everything the game shows, the first-person weapon included.
--   "wide": the half filled, the view drawn wider than high (view scales below) and squeezed
--     into it; a low first-person weapon (Delgado's minigun) can fall off its bottom.
Sp.WIDE_SCALE_X, Sp.WIDE_SCALE_Y = 0.6, 1.2

function Sp.wide()
  return cfg.splitview == "wide"
end

function Sp.body()
  return Sp.char and Game.GetEntity(Sp.char)
end

-- The engine's own HUD widgets in scorer 1, as Menu.ShowScorer builds scorer 0.
function Sp.buildHud()
  Scorer.Clear(1)
  if cfg.splithud then   -- tests: only these widgets
    for _, w in ipairs(cfg.splithud) do Scorer.NewItem(1, w, w) end
    return
  end
  local m = Scorer.NewItem(1, "Msg", "Msg")
  m.Pos = V2D(320, 40)
  Scorer.NewItem(1, "Damage", "Damage")
  if Menu.bShowAmmo ~= false then Scorer.NewItem(1, "Ammo", "Ammo") end
  Scorer.NewItem(1, "Selector", "Selector")
  if Menu.bShowTeamStatus ~= false then
    local ts = Scorer.NewItem(1, "TeamStatus", "TeamStatus")
    ts.Pos = V2D(48, 36)
  end
  if Menu.bShowAim ~= false then Scorer.NewItem(1, "Aim", "Aim") end
end

-- First-person model of user 1: the game names them <user><class> ("0FP_Black").
function Sp.ensureFP(char)
  if Coop.ensureFP then pcall(Coop.ensureFP, char) end
  local name = "1FP_" .. char
  if not Game.GetEntity(name) and MakeFP and Act.GetClass("FP_" .. char) then
    MakeFP.MakeFPObject("FP_" .. char, 1)
  end
  -- Its user: an FP model's hidden "id" (default 0) says whose it is (docs/scrapland-engine-audit.md).
  local fp = Game.GetEntity(name)
  if fp then fp.id = 1 end
  return name
end

function Sp.attachCamera(char)
  local c = Game.GetEntity(Sp.CAM) or Game.CreateEntity(Sp.CAM, "FCam")
  c.CamRot, c.CamAng, c.CamDist, c.Fov = 5, -20, 0, 90
  c.MainTarget, c.Target = char, char
  Game.SetCam(1, Sp.CAM)
end

-- Give user 1 a body (start, a switch, a revive in another body).
function Sp.takeBody(char, from)
  local t = Game.GetEntity(char)
  if not t then return false end
  Sp.ensureFP(char)
  if from then
    local f = Game.GetEntity(from)
    if f and f.UsrControl == 1 then
      f.UsrControl = -1
      if f.oAI then f.oAI.bEnable = true end
    end
  end
  if t.oAI then t.oAI.bEnable = false end
  local fpName = Sp.ensureFP(char)
  if Game.GetEntity(fpName) and t.FPSEntity ~= fpName then pcall(function() t.FPSEntity = fpName end) end
  t.UsrControl = 1
  t.InCtrl_UseFPS = 1
  t.InCtrl_ResetSlot = 1
  pcall(t.ResetControl, t)
  Sp.char = char
  Sp.attachCamera(char)
  Coop.log("split: " .. char .. " FPSEntity=" .. tostring(t.FPSEntity))
  if Coop.owners then
    for n, p in pairs(Coop.owners) do
      if p == Sp.owner and n ~= char then Coop.owners[n] = nil end
    end
    Coop.owners[char] = Sp.owner
  end
  Coop.log("split: player 2 is " .. char .. (from and (" (was " .. from .. ")") or ""))
  return true
end

-- on: the two views; pads: 0 each player's own, 1 both act as pad 0 (menus, scenes: the game
-- reads only pad 0 there), -1 split screen over.
function Sp.applyEngine(on, pads)
  Game.Set("SplitScreen", on and 1 or 0)
  Game.Set("R_SplitScreen", on and 1 or 0)
  Game.Set("R_SplitScreenCamera", 0)
  local wide = on and Sp.wide()
  Game.Set("CameraViewScaleY", wide and (cfg.splitsy or Sp.WIDE_SCALE_Y) or 1)
  Game.Set("CameraViewScaleX", wide and (cfg.splitsx or Sp.WIDE_SCALE_X) or 1)
  Net.CoopSplit(on and (wide and 1 or 2) or 0, pads or (on and 0 or -1))
end

-- The effects' own values are kept in COOP_CFG (the only state a level change keeps): engine
-- parameters outlive the level, and the player's options must get them back.
function Sp.setFlashFor(slot)
  local saved = cfg.splitSaved and cfg.splitSaved.FPSFlashLightIntens
  if saved == nil then return end
  local want = slot == 1 and 0 or saved
  if Sp.flashSet ~= want then
    Sp.flashSet = want
    Game.Set("FPSFlashLightIntens", want)
  end
end

function Sp.applyFx(on)
  if on then
    cfg.splitSaved = cfg.splitSaved or {}
    for k, v in pairs(Sp.FX) do
      if cfg.splitSaved[k] == nil then cfg.splitSaved[k] = Game.Get(k) end
      Game.Set(k, v)
    end
    if cfg.splitSaved.FPSFlashLightIntens == nil then
      cfg.splitSaved.FPSFlashLightIntens = Game.Get("FPSFlashLightIntens")
    end
  elseif cfg.splitSaved then
    for k, v in pairs(cfg.splitSaved) do Game.Set(k, v) end
    cfg.splitSaved = nil
    Sp.flashSet = nil
  end
end

-- Every level and the menu start without split screen (the engine keeps its parameters
-- across level loads); a level with a player 2 seat turns it on again (Sp.autoStart).
function Sp.resetEngine()
  Game.Set("SplitScreen", 0)
  Game.Set("R_SplitScreen", 0)
  Game.Set("R_SplitScreenCamera", 0)
  Game.Set("CameraViewScaleX", 1)
  Game.Set("CameraViewScaleY", 1)
  if Net.CoopSplit then Net.CoopSplit(0, -1) end
  Sp.applyFx(false)
end

function Sp.start(char, owner)
  if not Net.CoopSplit then
    Coop.log("split: this dinput8.dll has no split screen")
    return false
  end
  Sp.owner = owner
  if not Sp.takeBody(char) then return false end
  Sp.buildHud()
  Sp.applyFx(true)
  Sp.on, Sp.held = true, false
  Sp.applyEngine(true)
  Sp.installHooks()
  local ok, err = pcall(Sp.installPowers)
  if not ok then Coop.log("split: powers hook error: " .. tostring(err)) end
  return true
end

function Sp.stop()
  if not Sp.on then return end
  Sp.on = false
  Sp.applyEngine(false, -1)
  Sp.applyFx(false)
  Scorer.Clear(1)
  local b = Sp.body()
  if b and b.UsrControl == 1 then
    b.UsrControl = -1
    if b.oAI then b.oAI.bEnable = true end
  end
  Coop.log("split: off")
end

-- Full screen (user 0's view and HUD) while a scene plays or a menu is open: scenes and
-- menus are made for one screen.
function Sp.shouldHold()
  if Sp.waiting then return true end
  if Scene and Scene.IsPlaying then return true end
  local set = Input.GetActionSet and Input.GetActionSet()
  return set == "Menu" or set == "Inactive"
end

-- Every frame (coop.lua; it can run more than once per drawn frame).
function Sp.frame()
  if not Sp.on then return end
  local hold = Sp.shouldHold()
  if cfg.dev then
    local set = Input.GetActionSet and Input.GetActionSet()
    if set ~= Sp.lastSet then Sp.lastSet = set; Coop.log("split: action set " .. tostring(set)) end
  end
  if hold ~= Sp.held then
    Sp.held = hold
    Sp.applyEngine(not hold, hold and 1 or 0)
    Coop.log("split: " .. (hold and "full screen (scene or menu)" or "split again"))
  end
  if not hold then
    -- split.c says which half the next drawn frame fills; the engine draws the slot set
    -- now in the frame after (found by test: the other slot).
    local slot = 1 - Net.CoopSplit(Sp.wide() and 1 or 2)
    Game.Set("R_SplitScreenCamera", slot)
    -- Player 1's flashlight is the engine's camera light: it would light player 2's view
    -- from player 2's camera too. Off in player 2's frames.
    Sp.setFlashFor(slot)
  else
    Sp.setFlashFor(0)
  end
  local now = Game.GetTime()
  if now >= (Sp.nextBodyCheck or 0) then
    Sp.nextBodyCheck = now + 1
    Sp.checkBody()
    if Coop.inSession() then Sp.syncOwner() end
  end
  if not Sp.waiting then Sp.checkDown() end
end

-- Player 2 down: as the game does for player 1 (Team.OnDeath -> Team.CheckGameOver), after
-- 2 s into a free living body; with none free the body waits for Rawlings, held by "AI"
-- meanwhile (Team.CanCure revives only those), and player 2 takes it back when it is up.
Sp.DOWN_WAIT = 2
Sp.ORDER = {"Black", "Church", "Rawlings", "Jones", "Cole", "Delgado"}

-- A body player 2 may take: alive, in the level, free of players and of the story, and not
-- player 1's (their seat's body too: player 1 may be a spirit waiting for it).
function Sp.isPlayer1s(name)
  local usr0 = Game.UsrEntity(0)
  return (usr0 and usr0.Name == name) or name == Coop.localChar() or name == cfg.char or name == cfg.seatChar
end

function Sp.freeBody(except)
  -- Player 1 without a body (a spirit, coop_spirit.lua) gets the next free one first.
  if CoopSpirit and CoopSpirit.active then return nil end
  for _, other in ipairs(Sp.ORDER) do
    local e = Game.GetEntity(other)
    if other ~= except and e and e.Life > 0 and e.bActive ~= false and e.Active ~= 0 and
       not Sp.isPlayer1s(other) and Coop.ownerOf(other) == nil and
       not (Team.UnavaliablePlayers and Team.UnavaliablePlayers[other]) then
      return other
    end
  end
end

-- The story takes player 2's body (or the host moved it): into another one, or wait for one
-- with player 1's view full screen.
function Sp.moveOut(target)
  local from = Sp.char
  target = target or Sp.freeBody(from)
  if target then
    Sp.takeBody(target, from)
    Sp.waiting = nil
  else
    local b = Sp.body()
    if b and b.UsrControl == 1 then
      b.UsrControl = -1
      if b.oAI then b.oAI.bEnable = true end
    end
    if Coop.owners then Coop.owners[from] = nil end
    Sp.waiting = true
    Coop.log("split: player 2 has no body, waits")
  end
end

-- The host's owner table must name player 2's body (the host stops its AI and sends its
-- damage here): the host sets it itself, a client asks (claim2|<body>).
function Sp.syncOwner()
  local want = not Sp.waiting and Sp.char or nil
  if Coop.isHost() then
    local changed = false
    for n, p in pairs(Coop.owners) do
      if p == Sp.owner and n ~= want then Coop.owners[n] = nil; changed = true end
    end
    if want and Coop.owners[want] ~= Sp.owner then Coop.owners[want] = Sp.owner; changed = true end
    if changed then Coop.broadcastOwners() end
  elseif cfg.myId then
    if Sp.claimed ~= want or (want and Coop.owners[want] ~= Sp.owner) then
      Net.CoopSend(0, 1, "claim2|" .. (want or ""))
      Sp.claimed = want
    end
  end
end

-- Every second: player 2's body still there and theirs?
function Sp.checkBody()
  local b = Sp.body()
  if Sp.waiting then
    local t = Sp.freeBody()
    if t then Sp.waiting = nil; Sp.takeBody(t) end
    return
  end
  -- Scenes hide and deactivate the squad: no verdict while one plays.
  if Scene and Scene.IsPlaying then return end
  -- Taken by the story (coop_story.lua: the same rule as for the other players); a tutorial
  -- lock on switching (Team.UnavaliablePlayers) does not move a player out of their seat.
  local gone = not b or b.bActive == false or b.Active == 0 or
               (CoopStory and CoopStory.taken and CoopStory.taken(Sp.char))
  if gone and (not b or b.Life > 0) then
    Coop.log(string.format("split: %s is not available (exists %s, bActive %s, Active %s, story %s)", tostring(Sp.char),
      tostring(b ~= nil), tostring(b and b.bActive), tostring(b and b.Active),
      tostring(Team.UnavaliablePlayers and Team.UnavaliablePlayers[Sp.char])))
    Sp.moveOut()
  end
end

function Sp.checkDown()
  local b = Sp.body()
  if not b then return end
  local now = Game.GetTime()
  if b.Life > 0 then
    if Sp.downAt then
      Sp.downAt = nil
      if b.UsrControl ~= 1 then Sp.takeBody(b.Name) end
      Coop.log("split: player 2 (" .. b.Name .. ") is up again")
    end
    return
  end
  if not Sp.downAt then
    Sp.downAt = now
    Coop.log("split: player 2 (" .. b.Name .. ") is down")
    return
  end
  if b.UsrControl ~= 1 or now - Sp.downAt < Sp.DOWN_WAIT then return end
  local usr0 = Game.UsrEntity(0)
  local hold = CoopTeam and CoopTeam.holdDowned and CoopTeam.holdDowned[b.Name]
  if not hold and (not Team.isWithTheTeam or Team.isWithTheTeam()) then
    for _, other in ipairs(Sp.ORDER) do
      local e = Game.GetEntity(other)
      if other ~= b.Name and e and e.Life > 0 and e.bActive ~= false and not Sp.isPlayer1s(other) and
         Coop.ownerOf(other) == nil and not (Team.UnavaliablePlayers and Team.UnavaliablePlayers[other]) then
        Sp.downAt = nil
        Sp.takeBody(other, b.Name)
        return
      end
    end
  end
  b.UsrControl = -1   -- Rawlings can revive it; player 2 keeps its camera on it
  Coop.log("split: player 2 waits for Rawlings in " .. b.Name)
end

-- The squad selector of user 1 calls Team.SwitchCharacter(<user 1's body>) like user 0's,
-- and Team.SwitchSoldier gives the new body to user 0: user 1 gets it here instead, and
-- user 0 never takes user 1's body (or any other player's).
function Sp.installHooks()
  if Sp.hooked or not Team or not Team.SwitchSoldier then return end
  Sp.hooked = true
  local origSwitch = Team.SwitchSoldier
  Team.SwitchSoldier = function(EntityName, Data, ...)
    if not Sp.on then return origSwitch(EntityName, Data, ...) end
    local f = Game.GetEntity(EntityName)
    if f and f.UsrControl == 1 then
      local usr0 = Game.UsrEntity(0)
      if Data == EntityName or not Team.IsPlayerAvaliable(Data) or (usr0 and usr0.Name == Data) or
         Coop.isRemoteOwned(Data) then
        return false
      end
      return Sp.takeBody(Data, EntityName)
    end
    if Data == Sp.char then return false end
    return origSwitch(EntityName, Data, ...)
  end
end

-- The seat of this machine's second player in the session (lobby: peer id + Coop.P2), or a
-- test's cfg.split2 = '<char>'. Started once the level's squad is up.
function Sp.seatChar()
  local me = Coop.myId()
  if me == nil then return nil end
  for item in string.gmatch(cfg.seats or "", "[^;]+") do
    local peer, char = string.match(item, "^(%d+):(%a+)")
    if tonumber(peer) == me + Coop.P2 then return char end
  end
  return cfg.split2
end

function Sp.autoStart()
  if Sp.on or Sp.tried or Coop.level == "levels/menu" or not Coop.inSession() then return end
  local char = Sp.seatChar()
  if not char then Sp.tried = true return end
  local b = Game.GetEntity(char)
  local usr = Game.UsrEntity(0)
  if not b or not usr or (Scene and Scene.IsPlaying) then return end   -- try again next tick
  Sp.tried = true
  if usr.Name == char then
    Coop.log("split: player 2's body " .. char .. " is player 1's")
    return
  end
  Sp.start(char, Coop.myId() + Coop.P2)
end

------------------------------------------------------------------------------
-- Player 2's powers
------------------------------------------------------------------------------

-- The game calls a body's input callbacks (class fields) with the body's name; their scripts
-- assume user 0 here and there (Game.UsrEntity(0), the camera of slot 0, scorer 0). For
-- user 1's body they run with "user 0" meaning user 1, including what they schedule for later.
Sp.CALLBACKS = {"SpecialPress", "SpecialRelease", "SpecialPressPlus", "SpecialReleasePlus", "HoldReload",
  "HoldSwitchChar", "HoldLink", "PressLink", "HoldOSide", "HoldOMain", "dblOSide", "dblOMain", "OSide",
  "OMain", "HitPress", "DigitalUpPress", "DigitalDownPress", "DigitalLeftPress", "DigitalRightPress"}

local function one(i) if i == 0 then return 1 end return i end

function Sp.asUser1(fn, ...)
  if Sp.inUser1 then return fn(...) end
  local G, S, I = Game, Scorer, Input
  local oU, oGC, oSC, oAdd, oSet = G.UsrEntity, G.GetCam, G.SetCam, G.AddScheduledFunc, I.SetActionSet
  local oS = {}
  for k, f in pairs(S) do
    if type(f) == "function" then
      oS[k] = f
      S[k] = function(a, ...) if a == 0 then a = 1 end return f(a, ...) end
    end
  end
  G.UsrEntity = function(i) return oU(one(i)) end
  G.GetCam = function(i) return oGC(one(i)) end
  G.SetCam = function(i, n) return oSC(one(i), n) end
  G.AddScheduledFunc = function(t, id, func, ...) return oAdd(t, id, Sp.later(func), ...) end
  -- One action set for both users: player 2's powers do not take player 1's controls.
  I.SetActionSet = function() end
  Sp.inUser1 = true
  local r = {pcall(fn, ...)}
  Sp.inUser1 = false
  G.UsrEntity, G.GetCam, G.SetCam, G.AddScheduledFunc, I.SetActionSet = oU, oGC, oSC, oAdd, oSet
  for k, f in pairs(oS) do S[k] = f end
  if not r[1] then Coop.log("split: player 2 power error: " .. tostring(r[2])) return end
  return unpack(r, 2)
end

-- A scheduled callback (a global function's dotted name) that runs as user 1 later.
Sp.trampolines = Sp.trampolines or {}
function Sp.later(func)
  if type(func) ~= "string" or func == "" then return func end
  local key = string.gsub(func, "[^%w]", "_")
  if not Sp.trampolines[key] then
    Sp.trampolines[key] = true
    Sp["at_" .. key] = function(...)
      local f = Sp.resolve(func)
      if f then return Sp.asUser1(f, ...) end
    end
  end
  return "CoopSplit.at_" .. key
end

function Sp.resolve(path)
  local t = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return type(t) == "function" and t or nil
end

function Sp.wrapPath(path, wrapper)
  local parent, key = _G, nil
  local parts = {}
  for part in string.gmatch(path, "[^%.]+") do parts[#parts + 1] = part end
  for i = 1, #parts - 1 do
    parent = parent[parts[i]]
    if type(parent) ~= "table" then return false end
  end
  key = parts[#parts]
  local orig = parent[key]
  if type(orig) ~= "function" then return false end
  parent[key] = wrapper(orig)
  return true
end

-- Wrap the callbacks of every squad class once.
function Sp.installPowers()
  Sp.wrapped = Sp.wrapped or {}
  for _, char in ipairs(Coop.SQUAD) do
    local ac = Act.GetClass(char)
    if ac then
      for _, field in ipairs(Sp.CALLBACKS) do
        local fname = ac[field]
        if type(fname) == "string" and fname ~= "" and not Sp.wrapped[fname] then
          Sp.wrapped[fname] = Sp.wrapPath(fname, function(orig)
            return function(name, ...)
              local e = Sp.on and type(name) == "string" and Game.GetEntity(name)
              if e and e.UsrControl == 1 then
                if cfg.dev then Coop.log("split: player 2 " .. field .. " (" .. fname .. ")") end
                return Sp.asUser1(orig, name, ...)
              end
              return orig(name, ...)
            end
          end)
        end
      end
      -- The game's flashlight is user 0's camera light: player 2's shows as a beam from the
      -- body (coop.lua Coop.puppetLights draws it for every split player's body too).
      local fl = ac.FlashlightPress
      if type(fl) == "string" and fl ~= "" and not Sp.wrapped[fl] then
        Sp.wrapped[fl] = Sp.wrapPath(fl, function(orig)
          return function(name, ...)
            local e = Sp.on and type(name) == "string" and Game.GetEntity(name)
            if e and e.UsrControl == 1 then
              Sp.flash = not Sp.flash
              Sound.Play(Sp.flash and "linterna-on" or "linterna-off", 0.2)
              return
            end
            return orig(name, ...)
          end
        end)
      end
    end
  end
end

local okReset, errReset = pcall(Sp.resetEngine)
if not okReset then Coop.log("split reset error: " .. tostring(errReset)) end
