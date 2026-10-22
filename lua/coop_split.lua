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
-- How each half shows its view (cfg.splitview; players get "full"):
--   "full" (default): the whole normal frame, shape kept, in the middle of the half (black
--     sides): everything the game shows, the first-person weapon included.
--   "wide": the half filled, the view drawn wider than high (view scales below) and squeezed
--     into it; a low first-person weapon (Delgado's minigun) can fall off its bottom.
-- On a screen wider than 16:9 (21:9: each half about 4.7:1) "full" left each player a quarter of
-- the screen between black sides: "wide" is the default there (recorded on 21:9, 0.2.2).
Sp.WIDE_SCALE_X, Sp.WIDE_SCALE_Y = 0.6, 1.2

function Sp.wide()
  if cfg.splitview then return cfg.splitview == "wide" end
  local w, h = tonumber(Game.Get("VideoWidth")), tonumber(Game.Get("VideoHeight"))
  return w ~= nil and h ~= nil and h > 0 and w / h >= (Coop.WIDE_ASPECT or 1.85)
end

-- The camera a player sees (their slot's, but swapped during player 2's astral projection).
function Sp.camOf(user)
  if Sp.on and Sp.camSwap then user = 1 - user end
  return Game.GetCam(user)
end

function Sp.body()
  return Sp.char and Game.GetEntity(Sp.char)
end

-- The engine's own HUD widgets in scorer 1: Menu.ShowScorer run for user 1 (all of user 0's
-- widgets, the Astral one Jones's projection needs included), else the main ones.
function Sp.buildHud()
  Scorer.Clear(1)
  if cfg.splithud then   -- tests: only these widgets
    for _, w in ipairs(cfg.splithud) do Scorer.NewItem(1, w, w) end
    return
  end
  if Menu and Menu.ShowScorer then
    Sp.asUser1(Menu.ShowScorer)
    if Scorer.GetItem(1, "Selector") then return end
    Scorer.Clear(1)
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
  -- What the game does for a body user 0 switches into (power icons, the FP model's state).
  local sw = Team and Team.OnSwitchChar and Team.OnSwitchChar[t.ActCtrl or char]
  if sw then Sp.asUser1(sw, t) end
  -- Scripts of a character loaded since (wrapFn skips what is wrapped already).
  if Sp.on then pcall(Sp.installPowers) end
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
  Sp.padsMerged = nil
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
  Sp.fx, Sp.fxShown, Sp.bodyVis, Sp.bodyFps, Sp.shownFor = nil, nil, {}, {}, nil
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
  cfg.splitWasOn = true   -- the next level load resets the engine's split state
  Sp.fxStart()
  Sp.installScreenFx()
  Sp.applyEngine(true)
  Sp.installHooks()
  local ok, err = pcall(Sp.installPowers)
  if not ok then Coop.log("split: powers hook error: " .. tostring(err)) end
  return true
end

function Sp.stop()
  if not Sp.on then return end
  Sp.on = false
  Sp.fxStop()
  Sp.showAll()
  Sp.screenFxBack()
  local m = Scorer.GetItem(0, "Msg")
  if m then m.Y = 40 end   -- Menu.ShowScorer's
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

-- A first-person scene gives the view back through an interpolating camera, deleted when it
-- arrives (Scene.SetUsrPosAngEndInterpolated): split screen switched on in between, the game
-- deleted its active camera ("Check failed: GetActiveCamera() != this", a network client at the
-- end of the desert's Landing, 0.2.1). Waited for, 3 s at most.
Sp.SCENE_CAM_WAIT = 3
function Sp.sceneCamUp()
  if not Game.GetEntity("InterpolusCamera") then
    Sp.sceneCamSince = nil
    return false
  end
  local now = Net.CoopTime()
  Sp.sceneCamSince = Sp.sceneCamSince or now
  return now - Sp.sceneCamSince < Sp.SCENE_CAM_WAIT
end

-- Full screen (user 0's view and HUD) while a scene plays or a menu is open: scenes and
-- menus are made for one screen.
function Sp.shouldHold()
  if Sp.waiting then return true end
  if Scene and Scene.IsPlaying then return true end
  if Sp.sceneCamUp() then return true end
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
  -- Player 2's astral projection: its camera takes user 0's input only, so both pads act as
  -- pad 0 meanwhile (player 1's body waits in the "Astral" set anyway).
  -- The engine moves only slot 0's camera by input: the astral camera goes into slot 0 and
  -- player 1's into slot 1 meanwhile, and each half still draws its player's camera.
  -- (Sp.p2Astral: from player 2's "Astral" set until their return gives "Walk" back; a menu
  -- or a scene meanwhile changes neither)
  local b = Sp.body()
  if Sp.p2Astral and (Sp.waiting or not b or b.Life <= 0) then
    Sp.p2Astral = nil
    -- Player 2's projection ended without its return (Jones down, out of the body): the
    -- "Walk" it would give back, or player 1 stays frozen in the "Astral" set.
    if Sp.realGetActionSet() == "Astral" then
      Sp.realSetActionSet("Walk")
      Coop.log("split: player 2's projection cut short, controls back to \"Walk\"")
    end
  end
  Sp.applyP2Astral(hold)
  if not hold then
    -- split.c says which half the next drawn frame fills; the engine draws the slot set
    -- now in the frame after (found by test: the other slot).
    local slot = 1 - Net.CoopSplit(Sp.wide() and 1 or 2)
    Game.Set("R_SplitScreenCamera", Sp.camSwap and 1 - slot or slot)
    -- Player 1's flashlight is the engine's camera light: it would light player 2's view
    -- from player 2's camera too. Off in player 2's frames.
    Sp.setFlashFor(slot)
    -- Engine parameters take effect with the camera slot (as the flashlight's), entity
    -- visibility in the frame drawn next (camera 1 - slot).
    Sp.fxShow(slot)
    local vis = 1 - slot
    if cfg.splitvisflip then vis = slot end
    Sp.showFor(vis)
  else
    Sp.setFlashFor(0)
    Sp.fxShow(0)
    Sp.showAll()
  end
  local now = Game.GetTime()
  if now >= (Sp.nextBodyCheck or 0) then
    Sp.nextBodyCheck = now + 1
    Sp.checkBody()
    if Coop.inSession() then Sp.syncOwner() end
  end
  if not Sp.waiting then Sp.checkDown() end
  if not hold then Sp.driveDuringAstral() else Sp.stopDrive() end
  -- pads plugged in or out meanwhile (dll: the players keep theirs, a player without one gets
  -- a free one)
  if not hold and now >= (Sp.nextPadScan or 0) then
    Sp.nextPadScan = now + 3
    local ok, changed = pcall(Net.CoopKey, -2)
    if ok and changed == 1 then
      Scorer.SetMsgText(Coop.text("pads"), Game.GetTime() + 4)
    end
  end
  if not hold and now >= (Sp.nextHudCheck or 0) then
    Sp.nextHudCheck = now + 0.25
    Sp.checkHud()
  end
  Sp.updateHealth()
end

-- Player 2's astral projection: the astral camera in slot 0 (the engine moves only that slot's
-- camera by input), player 1's camera in slot 1, player 2's pad acting as pad 0. Done when
-- player 2's power sets "Astral" too, before the engine changes the set: done a frame later,
-- the button that started the projection showed up on user 0 after the change, as a new
-- press of "Return" (virtual pad test 0.2.1).
function Sp.applyP2Astral(hold)
  local astral = Sp.p2Astral or false
  if astral and not Sp.camSwap and Game.GetCam(1) == "AstralCam" and cfg.astralswap ~= false then
    Sp.p1Cam = Game.GetCam(0)
    Game.SetCam(0, "AstralCam")
    Game.SetCam(1, Sp.p1Cam)
    Sp.camSwap = true
    Coop.log("split: astral camera in slot 0, player 1's " .. tostring(Sp.p1Cam) .. " in slot 1")
  elseif Sp.camSwap and not astral then
    Sp.camSwap = nil
    Game.SetCam(0, Sp.p1Cam or "MainCam")
    if Game.GetCam(1) ~= Sp.CAM then Game.SetCam(1, Sp.CAM) end
    Coop.log("split: cameras back in their slots")
  end
  local merge = astral and cfg.astralmerge ~= false
  if not hold and merge ~= (Sp.padsMerged or false) then
    Sp.padsMerged = merge
    Net.CoopSplit(Sp.wide() and 1 or 2, merge and 2 or 0)
    Coop.log("split: pads " .. (merge and "merged for player 2's astral projection" or "apart again"))
  end
end

-- A power's HUD (Black's ghost bullet, Cole's slowdown...) replaces the user's HUD and the
-- power puts it back with Menu.ShowScorer when it ends, often from an entity callback or a
-- thread, i.e. as user 0: player 2's half would stay without HUD. Back when player 2 is
-- again in their body with their camera.
-- (The message line stays where the game puts it, in its box: split.c draws each HUD batch in
-- its own player's half since 0.2.1; it was moved down while player 1's text came out over
-- the whole screen.)
function Sp.checkHud()
  if Scorer.GetItem(1, "Selector") then return end
  local b = not Sp.waiting and Sp.body()
  local c = Game.GetEntity(Sp.CAM)
  if not b or b.UsrControl ~= 1 or b.IgnoreUsrControl == 1 or b.Life <= 0 or Game.GetCam(1) ~= Sp.CAM or
     not c or c.MainTarget ~= Sp.char then
    return
  end
  Sp.buildHud()
  Coop.log("split: player 2's HUD back")
end

-- A player's astral projection takes the one action set ("Astral") for its camera, and the
-- engine then moves no body from its "Walk" bindings: the other player would stand frozen.
-- Their pad drives their body meanwhile, as the network drives a remote player's: walk,
-- strafe, turn, look, sprint, fire.
Sp.TURN_SPEED, Sp.PITCH_SPEED = 160, 110   -- degrees per second at full stick
Sp.drives = Sp.drives or {}

-- The other player's body while one player's astral projection holds the "Astral" set: its
-- pad straight from XInput (the dll; the game updates no "Walk" input meanwhile: virtual pad
-- test 0.2.1, every state read 0 and the body stood). Without a pad of its own (player 1 on
-- keyboard and mouse, or an older dll) only player 2 falls back to the game's own bindings.
function Sp.driveDuringAstral()
  local set = Input.GetActionSet and Input.GetActionSet()
  local astral = set == "Astral"
  local p2 = not Sp.waiting and Sp.body()
  local p1 = Game.UsrEntity(0)
  -- player 1 projects: player 2 is driven; player 2 projects: player 1 is
  Sp.driveUser(1, astral and not Sp.p2Astral and p2 or nil)
  Sp.driveUser(0, astral and Sp.p2Astral and p1 ~= p2 and p1 or nil)
end

local function axis(v, dead)
  v = tonumber(v) or 0
  local a = math.abs(v)
  if a <= dead then return 0 end
  return (v > 0 and 1 or -1) * math.min(1, (a - dead) / (32767 - dead))
end

function Sp.driveUser(user, b)
  local d = Sp.drives[user]
  -- (not a body the story walks: its lock is the story's, audit 0.2.2 A16)
  if not b or (b.Life or 0) <= 0 or b.UsrControl ~= user or Coop.storyDriven[b.Name] then
    if d then Sp.stopDriveUser(user) end
    return
  end
  local pad = {pcall(Net.CoopKey, -1, user)}
  local raw = pad[1] and pad[2] ~= nil and pad
  if not raw and user == 0 then
    if d then Sp.stopDriveUser(user) end
    return
  end
  local function st(a)
    if raw then
      local buttons, rt = raw[2], raw[4]
      local lx, ly, rx, ry = axis(raw[5], 7849), axis(raw[6], 7849), axis(raw[7], 8689), axis(raw[8], 8689)
      if a == "Forward" then return math.max(0, ly) end
      if a == "Backward" then return math.max(0, -ly) end
      if a == "StrafeRight" then return math.max(0, lx) end
      if a == "StrafeLeft" then return math.max(0, -lx) end
      if a == "TurnRight" then return math.max(0, rx) end
      if a == "TurnLeft" then return math.max(0, -rx) end
      if a == "TurnUp" then return math.max(0, ry) end
      if a == "TurnDown" then return math.max(0, -ry) end
      if a == "MainShot" then return (tonumber(rt) or 0) / 255 end
      if a == "Sprint" then return (math.floor((tonumber(buttons) or 0) / 64) % 2 == 1) and 1 or 0 end
      return 0
    end
    local ok, v = pcall(Input.GetInputState, "Walk", a, user)
    return ok and tonumber(v) or 0
  end
  local now = Game.GetTime()
  if not d then
    local va = b.ViewAng or b.Ang
    d = {name = b.Name, yaw = b.Ang.y, pitch = va and va.x or 0, t = now}
    Sp.drives[user] = d
    if user == 1 then Sp.driving = true end
    Coop.log("split: player " .. (user + 1) .. " driven from their pad during the other's astral projection")
  end
  local dt = math.min(0.1, now - d.t)
  d.t = now
  d.yaw = d.yaw - (st("TurnRight") - st("TurnLeft")) * Sp.TURN_SPEED * dt
  d.pitch = math.max(-80, math.min(80, d.pitch + (st("TurnUp") - st("TurnDown")) * Sp.PITCH_SPEED * dt))
  -- (the engine writes a user's body controls from its input every frame: zeros meanwhile)
  b.IgnoreUsrControl = 1
  b.Ang = V3D(0, d.yaw, 0)
  b.ViewAng = V3D(d.pitch, d.yaw, 0)
  b.InCtrl_Walk = st("Forward") - st("Backward")
  b.InCtrl_Str = st("StrafeRight") - st("StrafeLeft")
  b.InCtrl_Sprint = st("Sprint") > 0.5 and 1 or 0
  if b.owc then b.owc.Shot = st("MainShot") > 0.5 and 1 or 0 end
  Sp.astralHud(b, user)
  if cfg.dev and Coop.frame % 30 == 0 then
    Coop.log(string.format("split: drive %s (user %d) fwd %.2f str %.2f turn %.2f shot %.2f pos %s", b.Name, user,
      st("Forward") - st("Backward"), st("StrafeRight") - st("StrafeLeft"), st("TurnRight") - st("TurnLeft"),
      st("MainShot"), Coop.v3(b.Pos)))
  end
end

-- The engine draws no Aim/Ammo/Selector/TeamStatus item while the action set is "Astral",
-- in either player's scorer (hudprobe 0.2.1: the mod's own text items still show). The
-- player who plays on keeps a crosshair and the loaded ammo meanwhile.
function Sp.astralHud(b, user)
  user = user or 1
  local aim = Scorer.GetItem(user, "AstralAim")
  local ammo = Scorer.GetItem(user, "AstralAmmo")
  if not b then
    if aim then aim.Text = "" end
    if ammo then ammo.Text = "" end
    return
  end
  if not aim then
    aim = Scorer.NewItem(user, "AstralAim", "Text", 1)
    aim.Font = Menu.SmallFont
    aim.Effect = "Shadow"
    aim.Color = V4D(230, 230, 230, 220)
  end
  Coop.setCentered(aim, "+")
  aim.Y = 232
  if not ammo then
    ammo = Scorer.NewItem(user, "AstralAmmo", "Text", 1)
    ammo.Font = Menu.SmallFont
    ammo.Effect = "Shadow"
    ammo.Pos = V2D(586, 440)
  end
  local n
  pcall(function() n = b.oWeapCtrl.oActual.AmmoLoaded end)
  ammo.Text = n and tostring(math.floor(n)) or ""
  ammo.Color = Menu.ItemColor
end

function Sp.stopDriveUser(user)
  local d = Sp.drives[user]
  if not d then return end
  Sp.drives[user] = nil
  if user == 1 then Sp.driving = nil end
  pcall(Sp.astralHud, nil, user)
  local b = Game.GetEntity(d.name)
  if b then
    b.InCtrl_Walk, b.InCtrl_Str, b.InCtrl_Sprint = 0, 0, 0
    if b.owc then b.owc.Shot = 0 end
    if not Coop.storyDriven[b.Name] then b.IgnoreUsrControl = 0 end
  end
  Coop.log("split: player " .. (user + 1) .. " back on the game's own controls")
end

function Sp.stopDrive()
  Sp.stopDriveUser(0)
  Sp.stopDriveUser(1)
end

-- SMOD's health counter (_G.PrintHealth, autoexec.lua) is user 0's, in scorer 0: the same
-- for user 1 in scorer 1, with its look and colours.
function Sp.updateHealth()
  if _G.SHOWHEALTH ~= true or type(_G.PrintHealth) ~= "function" then return end
  local text, bg = Scorer.GetItem(1, "Health"), Scorer.GetItem(1, "HealthBG")
  local b = not Sp.waiting and Sp.body()
  local cls = b and b.oActCtrl and b.oActCtrl.oActClass
  -- Hidden like SMOD's own while the view is a power's (ghost bullet, astral projection).
  if not cls or b.UsrControl ~= 1 or (Scene and Scene.IsPlaying) or (b.IgnoreUsrControl == 1 and not Sp.driving) or
     Game.GetCam(1) ~= Sp.CAM then
    if bg then bg.Color = Color(255, 255, 255, 0) end
    if text then text.Text = "" end
    return
  end
  if not bg then
    bg = Scorer.NewItem(1, "HealthBG", "Sprite", 1)
    bg.HighRes = 1
    bg.File = "2D/smod/healthbg.alpha.tga"
    bg.PivotX, bg.PivotY = 0.5, 0.5
  end
  bg.Color = Color(255, 255, 255, 255)
  if not text then
    text = Scorer.NewItem(1, "Health", "Text", 1)
    text.Font = Menu.SmallFont
    text.Effect = "Shadow"
    text.Pos = V2D(640, 449)
  end
  local life = b.Life
  text.Text = tostring(life)
  text.Color = (life / cls.Life) < 0.4 and V4D(192, 0, 0, 255) or Menu.ItemColor
  if life < 10 then bg.Scale, bg.Pos = V4D(0.05, 0.1, 0, 0), V4D(642, 457)
  elseif life < 99 then bg.Scale, bg.Pos = V4D(0.075, 0.1, 0, 0), V4D(652, 457)
  else bg.Scale, bg.Pos = V4D(0.1, 0.1, 0, 0), V4D(662, 457) end
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
  -- the seat's own body first (back from a wait: a scene's hidden characters shown again)
  local order = {Sp.seatChar and Sp.seatChar() or nil}
  for _, n in ipairs(Sp.ORDER) do order[#order + 1] = n end
  for _, other in ipairs(order) do
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
      if Sp.claimed ~= want then Sp.claimedT = Net.CoopTime() end
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
  -- A body the host gave to another player (two took it at once, claim2 refused): player 2
  -- moves out, as player 1 does (Coop.checkRefusedClaim); it drove on as a second driver.
  local held = Coop.isClient() and b and Coop.owners[Sp.char]
  if held and held ~= Sp.owner and not Coop.storyDriven[Sp.char] and Sp.claimed == Sp.char and
     Net.CoopTime() - (Sp.claimedT or 0) >= Coop.CLAIM_WAIT then
    local name = Sp.char
    Coop.log("split: " .. name .. " is held by owner " .. tostring(held) .. ", player 2 moves out")
    -- (that body is the other player's puppet here: let go of it with its AI left off)
    if b.UsrControl == 1 then b.UsrControl = -1 end
    local t = Sp.freeBody(name)
    if not (t and Sp.takeBody(t)) then
      Sp.waiting = true
      Coop.log("split: player 2 has no body, waits")
    end
    return
  end
  -- Taken by the story (coop_story.lua: the same rule as for the other players); a tutorial
  -- lock on switching (Team.UnavaliablePlayers) does not move a player out of their seat.
  local gone = not b or b.bActive == false or b.Active == 0 or
               (CoopStory and CoopStory.taken and CoopStory.taken(Sp.char))
  if gone and (not b or b.Life > 0) then
    Coop.log(string.format("split: %s is not available (exists %s, bActive %s, Active %s, story %s)", tostring(Sp.char),
      tostring(b ~= nil), tostring(b and b.bActive), tostring(b and b.Active),
      tostring(Team.UnavaliablePlayers and Team.UnavaliablePlayers[Sp.char])))
    Sp.moveOut()
    return
  end
  -- Player 2's FP model: set as the body is taken, the engine sometimes keeps none (no arms
  -- or weapon in player 2's view: Delgado from the lobby, recorded 0.2.1).
  local fpName = "1FP_" .. Sp.char
  if b and b.FPSEntity ~= fpName and Game.GetEntity(fpName) then
    pcall(function() b.FPSEntity = fpName end)
    if not Sp.fpRetried then
      Sp.fpRetried = true
      Coop.log("split: " .. Sp.char .. "'s FP model set again")
    end
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
  if not b or not usr or (Scene and Scene.IsPlaying) or Sp.sceneCamUp() then return end   -- try again next tick
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

-- An FP model hidden from a view has id 3 (Sp.showFor), and the game's scripts take its user
-- from it (Game.UsrEntity(fp.id): Black's telekinesis, melee hits, Church's spell...): user 3
-- is whoever's model has it now.
if Game.UsrEntity ~= Sp.usrWrap then
  local real = Game.UsrEntity
  Sp.usrWrap = function(i, ...)
    if i == 3 and Sp.id3User then return real(Sp.id3User, ...) end
    return real(i, ...)
  end
  Game.UsrEntity = Sp.usrWrap
end

-- Names the game's scripts use for user 0's things, and user 1's (first-person model, camera).
local function fpName(n)
  if type(n) == "string" and string.sub(n, 1, 4) == "0FP_" then return "1FP_" .. string.sub(n, 5) end
  if n == "MainCam" then return Sp.CAM end
  return n
end
local function fxArg(v)
  if type(v) == "string" then return (string.gsub(v, "0FP_", "1FP_")) end
  return v
end

-- The remap of user 0's things to user 1's while player 2's code runs: a list of
-- {table, key, original, replacement}, put in place by Sp.asUser1 and taken back after; Sp.asUser0
-- takes it back for a call made from inside for player 1's body (a damage to player 1 from
-- player 2's explosion runs as player 1).
function Sp.buildRemap()
  local G, S, I = Game, Scorer, Input
  local list = {}
  local function add(t, k, make)
    local f = t and t[k]
    if type(f) == "function" then list[#list + 1] = {t, k, f, make(f)} end
  end
  for k, f in pairs(S) do
    if type(f) == "function" then
      list[#list + 1] = {S, k, f, function(a, ...) if a == 0 then a = 1 end return f(a, ...) end}
    end
  end
  for _, k in ipairs({"SetEffect", "BeginEffect"}) do
    add(FX, k, function(f)
      return function(...)
        local args, n = {...}, select("#", ...)
        for i = 1, n do args[i] = fxArg(args[i]) end
        return f(unpack(args, 1, n))
      end
    end)
  end
  add(G, "UsrEntity", function(f) return function(i) return f(one(i)) end end)
  -- User 1's camera answers to "MainCam" (jones.lua: no astral projection unless the camera
  -- is "MainCam"; the returns set "MainCam" back).
  add(G, "GetCam", function(f)
    return function(i)
      local c = f(one(i))
      if one(i) == 1 and c == Sp.CAM then return "MainCam" end
      return c
    end
  end)
  add(G, "SetCam", function(f) return function(i, n) return f(one(i), fpName(n)) end end)
  add(G, "GetEntity", function(f) return function(n, ...) return f(fpName(n), ...) end end)
  add(G, "AddScheduledFunc", function(f) return function(t, id, func, ...) return f(t, id, Sp.later(func), ...) end end)
  -- One action set for both users: player 2's powers do not take player 1's controls. Except
  -- Jones's astral projection: its camera takes the "Astral" set (one for both users, so
  -- player 1's body waits meanwhile, as player 2's does for player 1's projection), and its
  -- end gives "Walk" back whenever the set is still "Astral".
  add(I, "SetActionSet", function(f)
    return function(set)
      Sp.p2Set = set
      if set == "Astral" then
        Sp.p2Astral = true
        pcall(Sp.asUser0, Sp.applyP2Astral, Sp.held)
        return f(set)
      elseif set == "Walk" and (Sp.p2Astral or Sp.realGetActionSet() == "Astral") then
        Sp.p2Astral = nil
        return f(set)
      end
    end
  end)
  -- The scripts recognise a first-person model by its "0FP_" prefix (FireWeapons.DoFire takes
  -- the character's name from it): user 1's "1FP_" reads the same.
  add(string, "sub", function(f)
    return function(str, i, j)
      local r = f(str, i, j)
      if i == 1 and j == 4 and r == "1FP_" then return "0FP_" end
      return r
    end
  end)
  add(I, "Rumble", function(f) return function(i, ...) return f(one(i), ...) end end)
  -- The action set is one for both users: player 1's squad selector ("Inactive") is not
  -- player 2's (Cole's loop stopped when it saw it). Menus and scenes stay what they are.
  add(I, "GetActionSet", function(f)
    return function(...)
      local set = f(...)
      if set == "Menu" or (Scene and Scene.IsPlaying) then return set end
      if Sp.p2Astral then return "Astral" end
      return "Walk"
    end
  end)
  return list
end

-- The engine's own action set functions (inside player 2's calls Input's are remapped).
Sp.REAL_GET_SET = Sp.REAL_GET_SET or Input.GetActionSet
Sp.REAL_SET_SET = Sp.REAL_SET_SET or Input.SetActionSet
function Sp.realGetActionSet() return Sp.REAL_GET_SET and Sp.REAL_GET_SET() end
function Sp.realSetActionSet(set) if Sp.REAL_SET_SET then Sp.REAL_SET_SET(set) end end

local function remapOn(list) for _, e in ipairs(list) do e[1][e[2]] = e[4] end end
local function remapOff(list) for _, e in ipairs(list) do e[1][e[2]] = e[3] end end

Sp.errorsBy = Sp.errorsBy or {}
function Sp.logError(where, err)
  local key = tostring(where)
  local n = (Sp.errorsBy[key] or 0) + 1
  Sp.errorsBy[key] = n
  if n <= 3 then Coop.log("split: player 2 error in " .. key .. ": " .. tostring(err)) end
end

function Sp.asUser1(fn, ...)
  if Sp.inUser1 then return fn(...) end
  local list = Sp.buildRemap()
  remapOn(list)
  Sp.inUser1, Sp.remap = true, list
  local r = {pcall(fn, ...)}
  Sp.inUser1, Sp.remap = false, nil
  remapOff(list)
  if not r[1] then Sp.logError(Sp.callLabel or "power", r[2]) return end
  return unpack(r, 2)
end

-- From inside player 2's code, for player 1's body: the game as it is.
function Sp.asUser0(fn, ...)
  local list = Sp.inUser1 and Sp.remap
  if not list then return fn(...) end
  remapOff(list)
  Sp.inUser1, Sp.remap = false, nil
  local r = {pcall(fn, ...)}
  remapOn(list)
  Sp.inUser1, Sp.remap = true, list
  if not r[1] then Sp.logError("player 1's part of " .. tostring(Sp.callLabel or "power"), r[2]) return end
  return unpack(r, 2)
end

-- A scheduled callback (a global function's dotted name) that runs as user 1 later.
Sp.trampolines = Sp.trampolines or {}
function Sp.later(func)
  if type(func) ~= "string" or func == "" then return func end
  local key = Sp.trampolines[func]
  if not key then
    Sp.trampolineCount = (Sp.trampolineCount or 0) + 1
    key = "at_" .. Sp.trampolineCount
    Sp.trampolines[func] = key
    Sp[key] = function(...)
      local f = Sp.resolve(func)
      if not f then return end
      if not Sp.on then return f(...) end   -- split screen over meanwhile
      -- for player 1's body (player 2 left it or swapped meanwhile): as the game does
      if select("#", ...) > 0 and Sp.isP1Subject((...)) then return f(...) end
      Sp.callLabel = func
      return Sp.asUser1(f, ...)
    end
  end
  return "CoopSplit." .. key
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

-- Is this (a name or an entity) player 2's: their body, their first-person model (the
-- engine calls FP animation events with its name), or a ghost bullet they fired? A
-- character's death handler gets the body after player 2 lost control of it (death).
function Sp.isP2Subject(x, death)
  if not Sp.on or not Sp.char then return false end
  local name = x
  if type(x) ~= "string" then
    if type(x) ~= "table" and type(x) ~= "userdata" then return false end
    local ok, n = pcall(function() return x.Name end)
    name = ok and n
  end
  if type(name) ~= "string" or name == "" then return false end
  if string.sub(name, 1, 4) == "1FP_" then return true end
  if death and name == Sp.char then return true end
  local ok, yes = pcall(function()
    local e = Game.GetEntity(name)
    if not e then return false end
    if e.UsrControl == 1 then return true end
    local u = e.uData
    return u ~= nil and u.UsrControl == 1 and u.usr ~= nil
  end)
  return ok and yes
end

-- Player 1's body (or first-person model), seen from inside player 2's code (the engine's
-- functions as they are, not the remapped ones).
function Sp.isP1Subject(x)
  local get = Game.GetEntity
  for _, e in ipairs(Sp.remap or {}) do
    if e[1] == Game and e[2] == "GetEntity" then get = e[3] end
  end
  local name = x
  if type(x) ~= "string" then
    if type(x) ~= "table" and type(x) ~= "userdata" then return false end
    local ok, n = pcall(function() return x.Name end)
    name = ok and n
  end
  if type(name) ~= "string" or name == "" then return false end
  if string.find(name, "^0FP_") then return true end
  local ok, yes = pcall(function()
    local e = get(name)
    return e ~= nil and e.UsrControl == 0
  end)
  return ok and yes
end

Sp.wrappers = Sp.wrappers or setmetatable({}, {__mode = "k"})
function Sp.wrapFn(parent, key, make)
  local f = type(parent) == "table" and parent[key]
  if type(f) ~= "function" or Sp.wrappers[f] then return false end
  local w = make(f)
  Sp.wrappers[w] = true
  parent[key] = w
  return true
end

-- label: the function's name (error log keys); quiet: not logged per call in dev mode.
local function asP2(orig, label, death, quiet)
  return function(a, ...)
    if Sp.on and not Sp.inUser1 and Sp.isP2Subject(a, death) then
      if cfg.dev and label and not quiet then Coop.log("split: player 2 " .. label) end
      Sp.callLabel = label or "power"
      return Sp.asUser1(orig, a, ...)
    end
    if Sp.inUser1 and Sp.isP1Subject(a) then return Sp.asUser0(orig, a, ...) end
    return orig(a, ...)
  end
end

-- The scripts of the squad's characters, powers, threads and weapons: what they do for player
-- 2's body runs as user 1 (Sp.asUser1), wherever the engine calls it from (input callbacks,
-- FP animation events, selector picks, weapon callbacks, the callbacks of a power's cameras
-- and bullets, death). Docs: work audit "powers-split-audit".
Sp.P2_TABLES = {"Black", "Church", "Cole", "Delgado", "Jones", "Rawlings", "Ababanili",
  "ThreadsBlack", "ThreadsChurch", "ThreadsCole", "ThreadsDelgado", "ThreadsJones", "ThreadsRawlings", "Threads",
  "WeaponsBlack", "WeaponsChurch", "WeaponsCole", "WeaponsDelgado", "WeaponsJones", "WeaponsRawlings",
  "AstralCamera", "FP_Black", "FP_Church", "FP_Cole", "FP_Delgado", "FP_Jones", "FP_Rawlings"}
-- Called for someone else than the one using the power (Rawlings cursing an ally).
Sp.P2_SKIP = {main = true, OnCreate = true, CreateFP = true, CreateEffects = true,
  DoVladCurseAlliedFX = true, EndVladCurseAlliedFX = true}

function Sp.installPowers()
  local n = 0
  -- The astral camera takes the input of the user it is given to.
  if AstralCamera then
    Sp.wrapFn(AstralCamera, "Start", function(orig)
      return asP2(function(...)
        local r = orig(...)
        local cam = Game.GetEntity("AstralCam")
        -- Player 2's projection: the astral camera is user 0's (it sits in slot 0, its input is
        -- player 2's pad as pad 0). Left at its default (-1) it ended after 0.75 s although
        -- "Return" was held (virtual pad test 0.2.1). (astraluser = <n> forces a user, tests)
        local want = cfg.astraluser
        if want == nil and Sp.inUser1 then want = 0 end
        if cam and want ~= nil and want ~= false then
          local u = type(want) == "number" and want or (Sp.inUser1 and 1 or 0)
          local ok, err = pcall(function() cam.UsrControl = u end)
          if cfg.dev then Coop.log("split: astral camera for user " .. u .. (ok and "" or (" (" .. tostring(err) .. ")"))) end
        end
        return r
      end, cfg.dev and "AstralCamera.Start")
    end)
  end
  for _, t in ipairs(Sp.P2_TABLES) do
    local tbl = rawget(_G, t)
    if type(tbl) == "table" then
      for k, f in pairs(tbl) do
        if type(f) == "function" and type(k) == "string" and not Sp.P2_SKIP[k] and
           not string.find(k, "^Make") and not string.find(k, "^Init") then
          -- (the Astral HUD widget asks its funcOn* every frame: not logged)
          local label, quiet = t .. "." .. k, string.find(k, "^funcOn") ~= nil
          if Sp.wrapFn(tbl, k, function(orig) return asP2(orig, label, k == "OnDeath", quiet) end) then
            n = n + 1
          end
        end
      end
    end
  end
  -- Input callbacks of the squad classes that live elsewhere (Team orders, Weapons menus).
  for _, char in ipairs(Coop.SQUAD) do
    local ac = Act.GetClass(char)
    if ac then
      for _, field in ipairs(Sp.CALLBACKS) do
        local fname = ac[field]
        if type(fname) == "string" and fname ~= "" then
          local parent, key = Sp.parentOf(fname)
          if Sp.wrapFn(parent, key, function(orig) return asP2(orig, field .. " " .. fname) end) then
            n = n + 1
          end
        end
      end
      -- The game's flashlight is user 0's camera light: player 2's shows as a beam from the
      -- body (coop.lua Coop.puppetLights draws it for every split player's body too).
      local fl = ac.FlashlightPress
      if type(fl) == "string" and fl ~= "" then
        local parent, key = Sp.parentOf(fl)
        Sp.wrapFn(parent, key, function(orig)
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
  if Weapons and Sp.wrapFn(Weapons, "FP_MeleeHitEvent", function(orig) return asP2(orig, "Weapons.FP_MeleeHitEvent") end) then n = n + 1 end
  -- An explosion shakes user 0's camera (by its distance): player 2's too.
  if Weapons then
    Sp.wrapFn(Weapons, "QuakeFX", function(orig)
      return function(...)
        local r = orig(...)
        if Sp.on and not Sp.inUser1 then Sp.asUser1(orig, ...)
        elseif Sp.inUser1 then Sp.asUser0(orig, ...) end
        return r
      end
    end)
  end
  -- The squad's weapon types' own callbacks (not class fields).
  for i = 0, 40 do
    local w = Game.GetWeapon and Game.GetWeapon(i)
    if w then
      for _, field in ipairs({"OnShot", "ShotPress", "ShotRelease", "ReloadPress", "ReloadRelease", "HoldReload"}) do
        local ok, fname = pcall(function() return w[field] end)
        if ok and type(fname) == "string" and fname ~= "" then
          local parent, key = Sp.parentOf(fname)
          if Sp.wrapFn(parent, key, function(orig) return asP2(orig, fname) end) then n = n + 1 end
        end
      end
    end
  end
  if n > 0 then Coop.log("split: " .. n .. " functions run as player 2 for their body") end
end

function Sp.parentOf(path)
  local parts = {}
  for part in string.gmatch(path, "[^%.]+") do parts[#parts + 1] = part end
  local parent = _G
  for i = 1, #parts - 1 do
    parent = type(parent) == "table" and parent[parts[i]] or nil
  end
  if type(parent) ~= "table" then return nil end
  return parent, parts[#parts]
end

-- Only after a split screen (single player keeps whatever the game or a tweak set).
if cfg.splitWasOn or cfg.splitSaved then
  cfg.splitWasOn = nil
  local okReset, errReset = pcall(Sp.resetEngine)
  if not okReset then Coop.log("split reset error: " .. tostring(errReset)) end
end

------------------------------------------------------------------------------
-- What each view shows of the other player, and screen effects per view
------------------------------------------------------------------------------

-- The engine draws first-person arms (FP entities) and the screen effects of its parameters
-- (blur, colour, noise... fx/effectsframe.lua) in every frame, whichever camera it is: player
-- 1's arms floated in player 2's view where player 1's body should be, and a power's screen
-- effect showed in both halves. Here the frame about to be drawn gets its user's arms and
-- effects, the other user's body.
Sp.FX_KEYS = {
  "RadialBlurFactorBegin", "RadialBlurFactorEnd", "RadialBlurTime", "RadialBlurEndTime",
  "MotionBlurFactorBegin", "MotionBlurFactorEnd", "MotionBlurTime", "MotionBlurEndTime", "MotionBlurOffVar",
  "TravelFactorBegin", "TravelFactorEnd", "TravelTime", "TravelEndTime",
  "EagleViewFactorBegin", "EagleViewFactorEnd", "EagleViewTime", "EagleViewEndTime", "RT_EagleViewColor",
  "CloseBlurFactorBegin", "CloseBlurFactorEnd", "CloseBlurTime", "CloseBlurEndTime", "RT_CloseBlurValue",
  "DirectionalDamageFactorBegin", "DirectionalDamageFactorEnd", "DirectionalDamageTime",
  "DirectionalDamageEndTime", "RT_DirectionalDamageFX", "RT_DirectionalDamageFY",
  "HeadacheFactorBegin", "HeadacheFactorEnd", "HeadacheTime", "HeadacheEndTime", "RT_HeadacheColor",
  "RT_AberrationValue", "RT_MonitorViewValue", "NoiseFactor", "NoiseEndTime", "RT_SilhouetteColor",
  "RT_DOFAutoFocusMin", "RT_DOFAutoFocusFar", "RT_DOFAutoFocusNear", "RT_DOFAutoFocusField",
  "RT_DOFAutoFocus", "RT_DOFValue", "RT_DOFNearDist", "RT_DOFNearDistTo", "RT_DOFNearDistStep",
  "RT_DOFNearRange", "RT_DOFNearRangeTo", "RT_DOFNearRangeStep",
  "NoFXDamage",   -- (Church's and Rawlings's powers mute their user's damage effects, not the other's)
}
-- Resting values (EffectsFrame.RT_Reset / DOF_Normal) for parameters the engine reads back as nothing.
Sp.FX_DEFAULT = {RT_DOFAutoFocusMin = 600, RT_DOFAutoFocusFar = 1, RT_DOFAutoFocusNear = 0,
  RT_DOFAutoFocusField = 0.8, RT_DOFAutoFocus = 50000, RT_DOFValue = 0.8, RT_DOFNearDist = 0,
  RT_DOFNearDistTo = -1, RT_DOFNearDistStep = 0, RT_DOFNearRangeTo = -1, RT_DOFNearRangeStep = 0, NoFXDamage = 0}
for _, k in ipairs({"RadialBlur", "MotionBlur", "Travel", "EagleView", "CloseBlur", "DirectionalDamage", "Headache"}) do
  Sp.FX_DEFAULT[k .. "FactorBegin"], Sp.FX_DEFAULT[k .. "FactorEnd"] = 0, 0
  Sp.FX_DEFAULT[k .. "Time"], Sp.FX_DEFAULT[k .. "EndTime"] = 0, 0
end
Sp.FX_DEFAULT.MotionBlurOffVar, Sp.FX_DEFAULT.RT_CloseBlurValue = 0, 0
Sp.FX_DEFAULT.RT_AberrationValue, Sp.FX_DEFAULT.RT_MonitorViewValue = 0, 0
Sp.FX_DEFAULT.NoiseFactor, Sp.FX_DEFAULT.NoiseEndTime = 0, 0
-- The engine runs these clocks of an effect forward in the frames it shows it.
Sp.FX_CLOCKS = {RadialBlurTime = true, MotionBlurTime = true, TravelTime = true, EagleViewTime = true,
  CloseBlurTime = true, DirectionalDamageTime = true, HeadacheTime = true}
Sp.FX_KEY = {}
for _, k in ipairs(Sp.FX_KEYS) do Sp.FX_KEY[k] = true end

-- Game.Set / Game.Get of an effect parameter go to the user it is for: player 2's while their
-- power runs (Sp.asUser1), else player 1's; the engine has the values of the view on screen.
function Sp.installFxHooks()
  if Sp.fxHooked == Game then return end
  Sp.fxHooked = Game
  local set, get = Game.Set, Game.Get
  Sp.rawSet, Sp.rawGet = set, get
  Game.Set = function(k, v, ...)
    local st = Sp.fx
    if st and Sp.FX_KEY[k] then
      local u = Sp.inUser1 and 1 or 0
      if cfg.fxprobe and k == "EagleViewFactorEnd" then
        Coop.log("fxprobe: set " .. k .. "=" .. tostring(v) .. " by user " .. u .. " shown " .. tostring(Sp.fxShown) ..
          " " .. (string.gsub(debug.traceback("", 2), "%c", " | ")))
      end
      st[u][k] = v
      if Sp.fxShown ~= u then return end
    end
    return set(k, v, ...)
  end
  Game.Get = function(k, ...)
    local st = Sp.fx
    if st and Sp.FX_KEY[k] then
      local u = Sp.inUser1 and 1 or 0
      if Sp.fxShown ~= u and st[u][k] ~= nil then return st[u][k] end
    end
    return get(k, ...)
  end
end

function Sp.fxStart()
  Sp.installFxHooks()
  local a, b = {}, {}
  for _, k in ipairs(Sp.FX_KEYS) do
    local ok, v = pcall(Sp.rawGet, k)
    if not ok or v == nil then v = Sp.FX_DEFAULT[k] end
    -- Player 1 keeps what the engine has; player 2 starts at rest (the engine's values can
    -- be the tail of player 1's effect: a green astral tint stayed in player 2's half).
    local rest = Sp.FX_DEFAULT[k]
    if rest == nil then rest = v end
    if v ~= nil then a[k] = v end
    if rest ~= nil then b[k] = rest end
  end
  if cfg.dev then
    local missing = {}
    for _, k in ipairs(Sp.FX_KEYS) do if a[k] == nil then missing[#missing + 1] = k end end
    if #missing > 0 then Coop.log("split: effect parameters without a value: " .. table.concat(missing, ", ")) end
  end
  Sp.fx, Sp.fxShown, Sp.fxAt = {[0] = a, [1] = b}, 0, {[0] = Game.GetTime(), [1] = Game.GetTime()}
end

-- Player 1's effects back on the engine (split over, or a scene/menu full screen).
function Sp.fxStop()
  if not Sp.fx then return end
  Sp.fxShow(0)
  Sp.fx, Sp.fxShown = nil, nil
end

function Sp.fxShow(u)
  local st = Sp.fx
  if not st or Sp.fxShown == u then return end
  local now = Game.GetTime()
  local old = Sp.fxShown
  if old ~= nil then
    -- What the engine moved meanwhile (clocks, DOF steps towards their targets) stays.
    local o = st[old]
    for _, k in ipairs(Sp.FX_KEYS) do
      local ok, v = pcall(Sp.rawGet, k)
      if ok and v ~= nil then o[k] = v end
    end
    Sp.fxAt[old] = now
  end
  if cfg.fxprobe and Coop.frame % 30 == 0 then
    Coop.log(string.format("fxprobe: show %d eagle0 %s eagle1 %s engine %s time0 %s time1 %s", u,
      tostring(st[0].EagleViewFactorEnd), tostring(st[1].EagleViewFactorEnd), tostring(Sp.rawGet("EagleViewFactorEnd")),
      tostring(st[0].EagleViewTime), tostring(st[1].EagleViewTime)))
  end
  local away = now - (Sp.fxAt[u] or now)
  for k, v in pairs(st[u]) do
    if Sp.FX_CLOCKS[k] and type(v) == "number" then v = v + away end
    Sp.rawSet(k, v)
  end
  Sp.fxShown = u
end

-- FP arms and bodies for the view drawn next (user u). A player's body is hidden in its own
-- player's view (the camera is inside it) and shown in the other's; the game's values come back after.
-- While a body's bCheckFPSVisible is set the engine hides it in both views and shows its
-- player's FP model instead (only the weapon and arms of the other player were left in each
-- half): off on player 1's body (the FP model stays), and on player 2's in player 1's view only
-- (without it the engine switches player 2's FP model off).
Sp.bodyVis = Sp.bodyVis or {}
Sp.bodyFps = Sp.bodyFps or {}
local function bodyFor(b, shown, check)
  if not b then return end
  local saved = Sp.bodyVis[b.Name]
  if saved == nil then
    saved = b.bObjectVisible
    Sp.bodyVis[b.Name] = saved
    Sp.bodyFps[b.Name] = b.bCheckFPSVisible
  end
  local want = shown == true
  if b.bObjectVisible ~= want then b.bObjectVisible = want end
  if b.bCheckFPSVisible ~= check then b.bCheckFPSVisible = check end
end

local function restoreBody(name, e)
  local v, fps = Sp.bodyVis[name], Sp.bodyFps[name]
  if e and v ~= nil and e.bObjectVisible ~= v then e.bObjectVisible = v end
  if e and fps ~= nil and e.bCheckFPSVisible ~= fps then e.bCheckFPSVisible = fps end
  Sp.bodyVis[name], Sp.bodyFps[name] = nil, nil
end

function Sp.showFor(u)
  local b0, b1 = Game.UsrEntity(0), not Sp.waiting and Sp.body()
  if b1 == b0 then b1 = nil end
  -- A body no longer a player's (a switch, a move): back to what the game gave it.
  for name in pairs(Sp.bodyVis) do
    if not ((b0 and b0.Name == name) or (b1 and b1.Name == name)) then
      restoreBody(name, Game.GetEntity(name))
    end
  end
  local f0 = b0 and Game.GetEntity("0FP_" .. b0.Name)
  local f1 = Sp.char and Game.GetEntity("1FP_" .. Sp.char)
  -- The engine draws each user's FP model in every view, at that user's camera (the other
  -- player's arms and weapon floating at their body, recorded 0.2.1), and sets its visibility
  -- and Active itself each frame. Its hidden "id" (whose camera it follows) it keeps: a user
  -- that does not exist (3) in the view it does not belong to draws it nowhere. Like a body's
  -- visibility it takes effect in the frame after next: set for the other view.
  local uf = 1 - u
  if cfg.splitfpflip == false then uf = u end
  local id0, id1 = (uf == 0) and 0 or 3, (uf == 1) and 1 or 3
  Sp.id3User = (f0 and id0 == 3 and 0) or (f1 and id1 == 3 and 1) or nil
  if f0 and f0.id ~= id0 then f0.id = id0 end
  if f1 and f1.id ~= id1 then f1.id = id1 end
  if cfg.splitbodies ~= false then
    -- A body's visibility too (recorded 0.2.1: set for the view drawn next, each player saw
    -- their own body from inside and the other's weapon alone).
    local ub, uc = u, u
    if cfg.splitbodyflip ~= false then ub = 1 - u end
    if cfg.splitcheckflip ~= false then uc = 1 - u end
    -- Act 1: Ross is shown by his stand-in (coop_ross.lua), his own model unseen: player 1's
    -- in player 2's view, the AI's in both.
    local ross = CoopRoss and CoopRoss.body()
    if ross then
      local ok, err = pcall(CoopRoss.update, u)
      if not ok then Coop.log("split: ross error " .. tostring(err)) end
    end
    if not (ross and b0 and b0.Name == "Ross") then
      bodyFor(b0, ub == 1, false)
    end
    bodyFor(b1, ub == 0, uc == 1)
  end
  Sp.shownFor = u
end

-- Everything as the game has it for one screen (split held or over).
function Sp.showAll()
  if Sp.shownFor == nil then return end
  for i, n in ipairs({"0FP_", "1FP_"}) do
    for _, c in ipairs(Coop.SQUAD) do
      local f = Game.GetEntity(n .. c)
      if f and f.bObjectVisible == false then f.bObjectVisible = true end
      if f and f.id ~= i - 1 then f.id = i - 1 end
    end
  end
  Sp.id3User = nil
  for name in pairs(Sp.bodyVis) do
    restoreBody(name, Game.GetEntity(name))
  end
  Sp.bodyVis, Sp.bodyFps = {}, {}
  Sp.shownFor = nil
end

-- Particle effects drawn over the whole screen (Delgado's fire barrier is linked to the
-- camera) show in both halves, and the engine cannot show an instance in one view only
-- (ActiveInstance 0 stops it for good, BirthEnabled toggled per frame asserts): in split
-- screen they are off, the power itself works (its icon shows it); back on when split ends.
Sp.SCREEN_FX = {["EFFECT_PARTICLES" .. string.char(183) .. "DELGADO_BARRIER"] = true}
Sp.screenFx = Sp.screenFx or {}

function Sp.installScreenFx()
  if not FX or Sp.fxWrapped == FX.BeginEffect then return end
  local begin, stop = FX.BeginEffect, FX.EndEffect
  -- (arguments passed on as given: the engine counts them, a nil is not a missing one)
  FX.BeginEffect = function(...)
    local t, inst = ...
    local r = begin(...)
    -- (not when it did not start, nor while a scene or menu shows one full screen)
    if r and Sp.on and not Sp.held and Sp.SCREEN_FX[t] then
      Sp.screenFx[t .. "|" .. tostring(inst)] = {t = t, inst = inst or ""}
      pcall(FX.SetEffect, t, inst or "", "ActiveInstance 0")
      if cfg.dev then Coop.log("split: screen effect " .. tostring(inst) .. " off in split screen") end
    end
    return r
  end
  FX.EndEffect = function(...)
    local t, inst = ...
    Sp.screenFx[tostring(t) .. "|" .. tostring(inst)] = nil
    return stop(...)
  end
  Sp.fxWrapped = FX.BeginEffect
end

function Sp.screenFxBack()
  for k, e in pairs(Sp.screenFx) do
    pcall(FX.SetEffect, e.t, e.inst, "ActiveInstance 1")
    Sp.screenFx[k] = nil
  end
end
