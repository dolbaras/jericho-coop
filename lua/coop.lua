-- Jericho co-op: per-level entry point (loaded by boot.lua on every level).
--
-- Model: the host runs the real game (AI, enemies, story scripts). Every human controls
-- one squad member. Each side sends the state of the body it controls 20 times a second;
-- the host also sends the state of every squad member, so on a client all bodies except
-- its own follow the host. Bodies driven from the network are "puppets": AI off, moved
-- through the engine's own character control (InCtrl_Walk / InCtrl_Str), with a position
-- snap when they drift too far.
--
-- Messages (text, fields separated by "|"):
--   hello|<wantedChar>|<nick>|<version>     client -> host, reliable
--   welcome|<peerId>|<level>|<char>         host -> client, reliable
--   own|<char>=<peer>,...                   host -> all, reliable (ownership table)
--   claim|<char>                            client -> host, reliable (player switched)
--   s|<char>|x|y|z|yaw|pitch|walk|str|sprint|life|action|shot   state, unreliable

-- Time in small numbers. Direct3D 9 leaves the x87 unit at single precision, so every Lua sum is
-- rounded to 24 bits of its own size: Net.CoopTime() is the machine's uptime (2.5e5 s on the main
-- PC, 9e5 s on the N100) and "now - offset - delay" came out in steps of 1/16 s (lab 2026-10-29:
-- the interpolation target stood still every other frame, 47 % of the frames of a running puppet).
-- Seconds since this game process first loaded the mod keep the sums in the millisecond range.
if not Net.CoopTimeRaw then
  Net.CoopTimeRaw = Net.CoopTime
  Net.CoopT0 = Net.CoopTime()
end
Net.CoopTime = function() return Net.CoopTimeRaw() - Net.CoopT0 end

Coop = {}
Coop.VERSION = "0.2.9"      -- players must have the same (lobby check); tools/package.ps1 checks it
Coop.cfg = COOP_CFG
Coop.level = string.lower(Game.GetLevelPath())
Coop.SQUAD = {"Jones", "Cole", "Delgado", "Church", "Rawlings", "Black"}
Coop.SQUAD_SET = {}
for _, name in ipairs(Coop.SQUAD) do Coop.SQUAD_SET[name] = true end
Coop.TICK = 0.05
Coop.SEND_EVERY = 1        -- ticks between state messages (20 Hz)
Coop.SNAP_DIST = 250       -- units; puppet is teleported beyond this error
Coop.FOLLOW = 1            -- fraction of the error to the interpolated place removed per 0.05 s (1: placed on it;
                           -- 0.9 added a lag of 0.02 s and fought the engine's own walking, cfg.pfollow = 0.9)
-- Height follows the owner's too: a puppet ignores collision, so the engine does not keep it
-- on the floor, and leaving height to it under 40 units left bodies up to that deep in the
-- floor or above it on slopes and stairs (owner's report, 0.2.2; measured 20-42 units).
Coop.FOLLOW_Y = 1          -- units of height error left alone
-- Other bodies are drawn a little in the past, between two received states (snapshot
-- interpolation): the delay covers the send interval plus the network's jitter (fork
-- MAK-PIVO/jericho-coop: 107-201 visible jumps a minute of a running puppet before, 1.5-4.5 after).
Coop.INTERP_MIN = 0.1      -- seconds (two states of the sender at 20 Hz)
Coop.INTERP_MAX = 0.25
Coop.EXTRAP_MAX = 0.2      -- seconds a body keeps moving on its last velocity when states stop
Coop.owners = {}           -- char name -> peer id (0 = host)
Coop.remote = {}           -- char name -> latest received state
Coop.storyDriven = {}      -- char name -> true while a story walk drives it (coop_story.lua)
Coop.frame = 0
Coop.oldStates = 0         -- states from the last level dropped at this one's start (Coop.onMessage)

local cfg = Coop.cfg

function Coop.log(s)
  Net.CoopLog(s)
end

local function v3(v)
  if not v then return "nil" end
  return string.format("%.0f,%.0f,%.0f", v.x, v.y, v.z)
end
Coop.v3 = v3

-- A squad body by name for the per-frame loops: a body the level does not have is not looked
-- up again for a second (the engine writes a log line for every lookup of a missing entity).
Coop.absent = {}
function Coop.squadEnt(name)
  local now = Net.CoopTime()
  if (Coop.absent[name] or 0) > now then return nil end
  local e = Game.GetEntity(name)
  if not e then Coop.absent[name] = now + 1 end
  return e
end

local function split(s)
  local t = {}
  for part in string.gmatch(s, "([^|]*)|?") do
    t[#t + 1] = part
  end
  if t[#t] == "" then t[#t] = nil end
  return t
end

-- Nicknames travel inside "|"/";"/":"-separated messages and the boot line (single
-- quotes), so keep letters, digits, space, "_" and "-" (cp1251 letters included).
-- A squad member's name in the game's language (language file keys Church, Cole...: "Черч").
function Coop.charName(id)
  local s = id and Game.GetLangStr(id)
  if not s or s == "" or string.find(s, "^%?") then s = id end
  return s
end

-- Centred text that may need several lines (Scorer text items do not break lines: one long
-- line runs off 4:3 screens and SMOD-sized fonts). The game's own Scorer.SplitString breaks it
-- by the font's real width, one item per line (name, name.."#2", ...), as Menu.TextMultiline
-- does. CentralText centres on the item's current X, so X is put back first each time or
-- every change of the text moves it further left.
Coop.TEXT_WIDTH = 520
function Coop.setCentered(it, text, x)
  if it.Text ~= text then
    -- CentralText also moves the item half a line up each time: keep its Y.
    local y = it.Y
    it.Text = text
    it.X = x or 320
    it.CentralText = 1
    it.Y = y
  end
end

-- opts: x, y (first line), font, color, effect, step (between lines), width.
function Coop.textBlock(name, text, opts)
  opts = opts or {}
  local font = opts.font or (Menu and Menu.SmallFont) or "ScrapMedium"
  -- Explicit breaks ("\n") first, then the font's width for each part.
  local lines = {}
  for part in string.gmatch(text .. "\n", "([^\n]*)\n") do
    local split
    if Scorer.SplitString and part ~= "" then
      local ok, r = pcall(Scorer.SplitString, part, font, opts.width or Coop.TEXT_WIDTH)
      if ok and type(r) == "table" and #r > 0 then split = r end
    end
    for _, l in ipairs(split or {part}) do lines[#lines + 1] = l end
  end
  local step = opts.step or 24
  local y0 = Coop.blockY(name, opts.y or 240, #lines, step)
  local n = 0
  for k, line in ipairs(lines) do
    n = k
    local key = k == 1 and name or (name .. "#" .. k)
    local it = Scorer.GetItem(0, key)
    if not it then
      it = Scorer.NewItem(0, key, "Text")
      it.Font = font
      it.Effect = opts.effect or "Shadow"
    end
    it.Y = y0 + (k - 1) * step
    Coop.setCentered(it, line, opts.x)
    if opts.color then it.Color = opts.color end
    it.Visible = 1
  end
  Coop.textBlockHide(name, n + 1)
end

-- Hints shown at once never draw over each other (owner's screenshot, 0.2.2: "cut off from
-- the squad?" over "Delgado is needed here"): a block that would overlap another moves away
-- from it, in the bottom half up (the lowest keeps its place), in the top half down.
Coop.blocks = {}
Coop.BLOCK_GAP = 6
Coop.LINE_H = 22
function Coop.blockY(name, y, n, step)
  Coop.blocks[name] = {y = y, h = (n - 1) * step + Coop.LINE_H}
  local up = y >= 240
  local list = {}
  for k, b in pairs(Coop.blocks) do
    if (b.y >= 240) == up then list[#list + 1] = {name = k, y = b.y, h = b.h} end
  end
  table.sort(list, function(a, b)
    if a.y ~= b.y then if up then return a.y > b.y else return a.y < b.y end end
    return a.name < b.name
  end)
  local edge
  for _, b in ipairs(list) do
    local top = b.y
    if edge then
      if up then top = math.min(top, edge - Coop.BLOCK_GAP - b.h) else top = math.max(top, edge + Coop.BLOCK_GAP) end
    end
    edge = up and top or (top + b.h)
    if b.name == name then return top end
  end
  return y
end

-- Hides the block's lines from line `from` on (1 = all of it).
function Coop.textBlockHide(name, from)
  if (from or 1) <= 1 then Coop.blocks[name] = nil end
  local k = from or 1
  while true do
    local it = Scorer.GetItem(0, k == 1 and name or (name .. "#" .. k))
    if not it then
      if k > 8 then break end
    else
      it.Visible = 0
    end
    k = k + 1
  end
end

function Coop.cleanNick(s)
  s = string.gsub(tostring(s or ""), "[^%w _%-92-­]", "")
  return string.sub(s, 1, 16)
end

-- The mod's language: the game's (Options -> Language): "de", "fr", "es", "it", "ru" when its
-- strings are Russian (the Russian release has them as its "English"), else "en".
Coop.LANG_NAMES = {erman = "de", rench = "fr", panish = "es", talian = "it"}
function Coop.detectLang()
  local sel = string.lower(tostring(Game.Get("SelectedLanguage") or ""))
  for part, code in pairs(Coop.LANG_NAMES) do
    if string.find(sel, part, 1, true) then return code end
  end
  return (string.byte(Game.GetLangStr("Menu_ExitGame") or "", 1) or 0) >= 192 and "ru" or "en"
end

-- A change in the options while a level runs reaches every table added (Coop.addLangs) at once,
-- not only the menu's (0.2.2: hints stayed in the old language until the next level).
Coop.langTables = {}
function Coop.lang()
  if cfg.lang then return cfg.lang end   -- tests: another language on this install
  local lang = Coop.detectLang()
  if lang ~= Coop.langSeen then
    local changed = Coop.langSeen ~= nil
    Coop.langSeen = lang
    if changed then
      for tbl, path in pairs(Coop.langTables) do Coop.fillLang(tbl, path, lang) end
      Coop.log("language now " .. lang)
    end
  end
  return lang
end

-- Texts of the other languages (lang_<code>.lua: {["CoopMenu.TEXT"] = {...}, ...}) put into a
-- module's own table under that code, so its lookups find them like en and ru.
function Coop.addLangs(tbl, path)
  if type(tbl) ~= "table" then return end
  Coop.langTables[tbl] = path
  Coop.fillLang(tbl, path, Coop.lang())
end

function Coop.fillLang(tbl, path, lang)
  if lang == "en" or lang == "ru" then return end
  Coop.langTexts = Coop.langTexts or {}
  if Coop.langTexts[lang] == nil then
    local ok, t = pcall(dofile, COOP_DIR .. "lang_" .. lang .. ".lua")
    Coop.langTexts[lang] = ok and type(t) == "table" and t or false
    if not ok then Coop.log("language " .. lang .. ": " .. tostring(t)) end
  end
  local t = Coop.langTexts[lang] and Coop.langTexts[lang][path]
  if t ~= nil and tbl[lang] == nil then tbl[lang] = t end
end

-- Mod sources are UTF-8; the game's fonts use the language's code page: cp1251 for Russian,
-- cp1252 for the others.
function Coop.enc(s, lang)
  if type(s) ~= "string" then return s end
  lang = lang or Coop.lang()
  if lang == "ru" then return Coop.cp1251(s) end
  return Coop.cp1252(s)
end

Coop.CP1252 = {[0x20AC] = 128, [0x201A] = 130, [0x201E] = 132, [0x2026] = 133, [0x0152] = 140, [0x2018] = 145,
               [0x2019] = 146, [0x201C] = 147, [0x201D] = 148, [0x2013] = 150, [0x2014] = 151, [0x0153] = 156,
               [0x0178] = 159}
function Coop.cp1252(s)
  return (string.gsub(s, "[\194-\239][\128-\191]+", function(c)
    local b1, b2, b3 = string.byte(c, 1, 3)
    local code
    if b1 < 224 then code = (b1 - 192) * 64 + (b2 - 128)
    elseif b3 then code = ((b1 - 224) * 64 + (b2 - 128)) * 64 + (b3 - 128) end
    if code and code >= 160 and code <= 255 then return string.char(code) end
    local x = code and Coop.CP1252[code]
    return x and string.char(x) or "?"
  end))
end

-- Short texts of this file and of coop_split.lua.
Coop.TEXT = {
  en = {clip = "Last 30 s saved as a video: ", pads = "Gamepads assigned again", auto = "Auto",
        mode = "Display mode", full = "Full screen", window = "Window", borderless = "Borderless window",
        hz = "Refresh rate", hzunit = "Hz", fullonly = "(full screen)",
        restart = "The display mode changes at the next start of the game"},
  ru = {clip = "Видео последних 30 с сохранено: ", pads = "Геймпады назначены заново", auto = "Авто",
        mode = "Режим экрана", full = "Полный экран", window = "Окно", borderless = "Окно без рамки",
        hz = "Частота обновления", hzunit = "Гц", fullonly = "(в полном экране)",
        restart = "Режим экрана сменится при следующем запуске игры"},
}
Coop.addLangs(Coop.TEXT, "Coop.TEXT")
function Coop.text(key)
  local lang = Coop.lang()
  return Coop.enc((Coop.TEXT[lang] or Coop.TEXT.en)[key] or Coop.TEXT.en[key] or key, lang)
end

-- Mod sources are UTF-8; the game's fonts use cp1251.
function Coop.cp1251(s)
  -- (first the punctuation cp1251 has, still UTF-8: dashes, quotes, the ellipsis)
  s = string.gsub(s, "[\194\226][\128-\191]+", Coop.CP1251_PUNCT)
  return (string.gsub(s, "([\208\209])([\128-\191])", function(a, b)
    local code = (string.byte(a) - 192) * 64 + (string.byte(b) - 128)
    if code == 0x401 then return "\168" end      -- Ё
    if code == 0x451 then return "\184" end      -- ё
    if code >= 0x410 and code <= 0x44F then return string.char(code - 0x410 + 192) end
    return "?"
  end))
end
Coop.CP1251_PUNCT = {["\226\128\148"] = "\151", ["\226\128\147"] = "\150", ["\194\171"] = "\171",
  ["\194\187"] = "\187", ["\226\128\166"] = "\133", ["\226\128\156"] = "\147", ["\226\128\157"] = "\148",
  ["\194\160"] = " "}

function Coop.isHost() return cfg.role == "host" end
function Coop.isClient() return cfg.role == "client" end
function Coop.myId() return Coop.isHost() and 0 or cfg.myId end

-- Keep InitLuaLine equal to the boot line for the current COOP_CFG, so the next level
-- starts with this session's state (peer id, body, owners).
function Coop.rearm()
  local line = COOP_BOOT_LINE()
  if Game.Get("InitLuaLine") ~= line then
    Game.Set("InitLuaLine", line)
  end
end

------------------------------------------------------------------------------
-- Ownership
------------------------------------------------------------------------------

function Coop.ownerOf(name)
  return Coop.owners[name]
end

-- A second player on the same PC (split screen, coop_split.lua) is an owner of its own:
-- the machine's peer id + P2, so every owner still holds one body.
Coop.P2 = 8

-- The machine (peer) an owner id plays on.
function Coop.peerOf(owner)
  if owner and owner >= Coop.P2 then return owner - Coop.P2 end
  return owner
end

-- Owners that play on this machine: its player, and its split screen player.
function Coop.isMine(owner)
  return owner ~= nil and Coop.myId() ~= nil and Coop.peerOf(owner) == Coop.myId()
end

-- A body this machine plays: its player's, or its split screen player's (coop_split.lua).
function Coop.isLocalBody(name)
  return name ~= nil and (name == Coop.localChar() or Coop.isMine(Coop.owners[name]))
end

-- True when a message from this peer may act for this body: its own, or its machine's split
-- screen player's (that one's owner id is peer + P2, its messages come from the peer).
function Coop.heldBy(name, peer)
  local o = Coop.owners[name or ""]
  return o ~= nil and Coop.peerOf(o) == peer
end

-- True when another human controls this body.
function Coop.isRemoteOwned(name)
  local o = Coop.owners[name]
  return o ~= nil and not Coop.isMine(o)
end

-- Bodies the players of this machine control (user 0, and user 1 in split screen).
function Coop.isLocalPlayer(name)
  if name == nil then return false end
  if name == Coop.localChar() then return true end
  return CoopSplit ~= nil and CoopSplit.on and CoopSplit.char == name
end

function Coop.ownString()
  local parts = {}
  for name, peer in pairs(Coop.owners) do
    parts[#parts + 1] = name .. "=" .. peer
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

function Coop.parseOwn(s)
  local t = {}
  for name, peer in string.gmatch(s or "", "(%a+)=(%d+)") do
    t[name] = tonumber(peer)
  end
  return t
end

function Coop.broadcastOwners()
  cfg.owners = Coop.ownString()
  Net.CoopSend(-1, 1, "own|" .. cfg.owners)
end

-- A refused claim: the owners to the claimer only, at most every 2 s per peer (a split screen
-- player 2 asks again every second while its body is not its own).
function Coop.ownersTo(peer, why)
  Coop.ownersToT = Coop.ownersToT or {}
  local now = Net.CoopTime()
  if now - (Coop.ownersToT[peer] or -10) < 2 then return end
  Coop.ownersToT[peer] = now
  if why then Coop.log(why) end
  Net.CoopSend(peer, 1, "own|" .. Coop.ownString())
end

-- Host: give a joining peer the wanted body if it is free, else the first free one.
function Coop.assign(peer, wanted)
  for name, p in pairs(Coop.owners) do
    if p == peer then Coop.owners[name] = nil end
  end
  -- Tutorial locks (Team.UnavaliablePlayers) limit single-player switching only; a body the
  -- story has taken away (CoopStory.taken) or switched off is not free.
  local function free(name)
    local e = Game.GetEntity(name)
    return e and e.Life > 0 and Coop.owners[name] == nil and e.bActive ~= false and
           not (CoopStory and CoopStory.taken and CoopStory.taken(name))
  end
  local pick = nil
  if wanted and free(wanted) then pick = wanted end
  if not pick then
    for _, name in ipairs(Coop.SQUAD) do
      if free(name) then pick = name break end
    end
  end
  if pick then Coop.owners[pick] = peer end
  return pick
end

-- Players may only switch to bodies no other human controls.
function Coop.wrapTeam()
  if not Team or Coop.teamWrapped then return end
  Coop.teamWrapped = true
  local orig = Team.IsPlayerAvaliable
  Team.IsPlayerAvaliable = function(name, ...)
    if Coop.isRemoteOwned(name) then return false end
    return orig(name, ...)
  end
end

------------------------------------------------------------------------------
-- Local player state
------------------------------------------------------------------------------

function Coop.localChar()
  local usr = Game.UsrEntity(0)
  return usr and usr.Name
end

function Coop.stateOf(e)
  local p, a = e.Pos, e.Ang
  local va = e.ViewAng or a
  local shot = e.owc and e.owc.Shot or 0
  -- The flashlight is the player's own (one camera light per game): on while its timer runs.
  local usr = Game.UsrEntity(0)
  local flash = usr and usr.Name == e.Name and (tonumber(Game.Get("FPSFlashLightTimeOn")) or 0) > 0
  if CoopSplit and CoopSplit.on and CoopSplit.char == e.Name then flash = CoopSplit.flash end
  Coop.stateSeq = (Coop.stateSeq or 0) + 1
  -- The weapon slot in hand: 0/1 the weapons, 2/3 a power used as a weapon (Delgado's fire
  -- arm, Church's blade...). The puppet takes the same slot, so it shows and fires that.
  local wc = e.oWeapCtrl
  local slot = wc and tonumber(wc.iSlot) or -1
  -- What the player's first-person arms play (a human body's own action stays "Relax" when it
  -- strikes, reloads or casts: only the arms show it): the other machines mirror it on the body.
  local fp = e.FPSEntity and e.FPSEntity ~= "" and Game.GetEntity(e.FPSEntity)
  local fpa = fp and fp.Action
  if type(fpa) ~= "string" or fpa == "" then fpa = "-" end
  -- (a Delgado whose arms hold the barrier or release the dragon reports the Ababanili's slot, CoopAnim.reportSlot)
  if CoopAnim and CoopAnim.reportSlot then slot = CoopAnim.reportSlot(e, fpa, slot) end
  -- Switched on or off by the story ("-": not said): the host's word for the bodies it runs.
  local on = "-"
  -- (not while a scene plays here: scenes hide the squad for themselves)
  if Coop.isHost() and not Coop.isRemoteOwned(e.Name) and not (Scene and Scene.IsPlaying) then
    on = e.bActive == false and "0" or "1"
  end
  -- (the 20th field: the body's floor distance, standing or crouched: the feet are Pos.y - FloorDist,
  -- so a puppet needs the owner's value to stand on the same floor)
  -- (the 21st: the model's height offset, which the engine's crouch raises by DispCrouch: a puppet
  -- left at the standing offset had the model 60 units too low, sunk waist-deep)
  local okfd, fd = pcall(function() return tonumber(e.FloorDist) end)
  local okym, ymd = pcall(function() return tonumber(e.YModelDisp) end)
  return string.format("s|%s|%.0f|%.0f|%.0f|%.1f|%.1f|%.2f|%.2f|%d|%.0f|%s|%d|%d|%d|%.3f|%d|%s|%s|%.1f|%.1f",
    e.Name, p.x, p.y, p.z, a.y, va.x, e.InCtrl_Walk or 0, e.InCtrl_Str or 0,
    e.InCtrl_Sprint or 0, e.Life or 0, tostring(e.Action), shot > 0.5 and 1 or 0, flash and 1 or 0,
    Coop.stateSeq, Net.CoopTime(), slot, (string.gsub(fpa, "|", "")), on, okfd and fd or 0, okym and ymd or 0)
    -- (the 22nd: the second weapon's trigger, 0.3.0. The weapons that fire on a switch (Black's grenade launcher, Delgado's
    -- Raging Bull, Rawlings' pistols) are fired with it, not with the main trigger the 13th field carries)
    .. "|" .. ((CoopAnim and CoopAnim.stateFire) and CoopAnim.stateFire(e) or "0")
    -- (the 23rd: the fire modes of the two weapon slots and Rawlings' pistol load, four characters: CoopAnim.stateModes)
    .. "|" .. ((CoopAnim and CoopAnim.stateModes) and CoopAnim.stateModes(e) or "----")
end

-- A puppet of a body the host runs is switched on or off as there: host-only story code
-- (split hooks, story walks) switched bodies on the host alone, and a client's replay could
-- leave one off that the host had on (audit 0.2.2 A9).
function Coop.syncPuppetActive(e, st)
  if cfg.syncactive == false or st.on == nil then return end
  if e.bActive ~= st.on then
    e.bActive = st.on
    Coop.log("puppet " .. e.Name .. (st.on and " switched on" or " switched off") .. " as on the host")
  end
end

function Coop.sendStates()
  if Coop.isHost() then
    for _, name in ipairs(Coop.SQUAD) do
      local e = Coop.squadEnt(name)
      if e and (not Coop.isRemoteOwned(name) or Coop.storyDriven[name]) then
        Net.CoopSend(-1, 0, Coop.stateOf(e))
      end
    end
    -- Act 1's Ross is not one of the six: his state was never sent, so the other machines'
    -- stand-in stood where he appeared and his flashlight never showed (owner's Steam test, 0.2.1).
    if Coop.actOne() and not Coop.isRemoteOwned("Ross") then
      local r = Game.GetEntity("Ross")
      if r and r.bActive ~= false then Net.CoopSend(-1, 0, Coop.stateOf(r)) end
    end
    -- Relay remote players' latest states to the other clients.
    for name, st in pairs(Coop.remote) do
      if Coop.isRemoteOwned(name) and not Coop.storyDriven[name] and st.raw then
        Net.CoopSend(-1, 0, st.raw)
      end
    end
  else
    local usr = Game.UsrEntity(0)
    if usr and not Coop.storyDriven[usr.Name] then Net.CoopSend(0, 0, Coop.stateOf(usr)) end
    local p2 = CoopSplit and CoopSplit.on and CoopSplit.body()
    if p2 and not Coop.storyDriven[p2.Name] then Net.CoopSend(0, 0, Coop.stateOf(p2)) end
  end
end

------------------------------------------------------------------------------
-- Puppets
------------------------------------------------------------------------------

-- Which bodies this machine drives from the network.
function Coop.isPuppet(name)
  -- A story walk (coop_story.lua): the host's AI walks the body, everyone else follows it.
  if Coop.storyDriven and Coop.storyDriven[name] then return not Coop.isHost() end
  if Coop.isLocalPlayer(name) then return false end
  if Coop.isHost() then return Coop.isRemoteOwned(name) end
  return Coop.isClient() and cfg.myId ~= nil
end

-- Root motion: locomotion actions (UseDisp = 1) move a body by their animation. On a puppet
-- that moved it a second time on top of the network position, unevenly from frame to frame
-- (fork MAK-PIVO/jericho-coop, from the earlier JerichoCoop mod). A puppet's current action
-- plays without displacement. Action objects are shared by the bodies of a class: the actions
-- this machine's players are playing (player 1, and player 2 in split screen) keep theirs.
Coop.rootMotion = {}   -- "class:action" -> {class, action, value} original UseDisp

local function actionKey(e)
  local ok, cls, act, obj = pcall(function()
    local a = e.oActCtrl.oAction
    return e.oActCtrl.oActClass.Name, a.Name, a
  end)
  if not ok or type(cls) ~= "string" or type(act) ~= "string" then return nil end
  return cls .. ":" .. act, cls, act, obj
end

local function restoreRootMotion(rec)
  pcall(function()
    local c = Act and Act.GetClass and Act.GetClass(rec.class)
    local a = c and c:GetAct(rec.action)
    if a and tonumber(a.UseDisp) ~= rec.value then a.UseDisp = rec.value end
  end)
end

function Coop.suppressRootMotion(e, localKeys)
  local key, cls, act, obj = actionKey(e)
  if not key then return end
  local rec = Coop.rootMotion[key]
  if not rec then
    local v = tonumber(obj.UseDisp)
    if v == nil then return end
    rec = {class = cls, action = act, value = v}
    Coop.rootMotion[key] = rec
  end
  -- Turns rotate the body through their displacement: left alone.
  if (localKeys and localKeys[key]) or string.find(act, "Turn", 1, true) then
    restoreRootMotion(rec)
  elseif tonumber(obj.UseDisp) ~= 0 then
    pcall(function() obj.UseDisp = 0 end)
  end
end

-- The actions this machine's players are playing: their root motion put back every frame.
function Coop.keepLocalRootMotion()
  local keys = {}
  local bodies = {Game.UsrEntity(0)}
  if CoopSplit and CoopSplit.on and CoopSplit.body then bodies[2] = CoopSplit.body() end
  for _, b in pairs(bodies) do
    local key = b and actionKey(b)
    if key then
      keys[key] = true
      local rec = Coop.rootMotion[key]
      if rec then restoreRootMotion(rec) end
    end
  end
  return keys
end

function Coop.restoreAllRootMotion()
  for _, rec in pairs(Coop.rootMotion) do restoreRootMotion(rec) end
end

function Coop.releasePuppet(e)
  e.InCtrl_Walk = 0
  e.InCtrl_Str = 0
  e.InCtrl_Sprint = 0
  e.InCtrl_Crouch = 0
  if e.owc then
    e.owc.Shot = 0
    pcall(function() e.owc.SecondWeaponTrigger = 0 end)
  end
  if e.oAI then e.oAI.bEnable = true end
  -- Back to the engine: collision on, and actions move bodies again.
  if Coop.puppetNoCollide and Coop.puppetNoCollide[e.Name] ~= nil then
    local ok0, cur = pcall(function() return e.bIgnoreCollision end)
    pcall(function() e.bIgnoreCollision = Coop.puppetNoCollide[e.Name] end)
    Coop.log(string.format("puppet %s released: collision ignore %s -> %s (life %s, action %s)", e.Name,
      tostring(ok0 and cur), tostring(Coop.puppetNoCollide[e.Name]), tostring(e.Life), tostring(e.Action)))
    Coop.puppetNoCollide[e.Name] = nil
  end
  if Coop.ymdSet and Coop.ymdSet[e.Name] and Coop.ymdBase[e.Name] then
    pcall(function() e.YModelDisp = Coop.ymdBase[e.Name] end)
    Coop.ymdSet[e.Name] = nil
  end
  if Coop.floorSet and Coop.floorSet[e.Name] and Coop.floorBase[e.Name] then
    pcall(function() e.FloorDist = Coop.floorBase[e.Name] end)
    Coop.floorSet[e.Name] = nil
  end
  Coop.restoreAllRootMotion()
end

-- Smoothness metrics (chunk I, 2026-10-29), per kind of remote thing ("squad", "enemy", "prop"):
-- the receive interval of its state packets (mean, deviation, max, how many were later than 0.1 s),
-- the offset jitter the interpolation delay is built on, and, for frames where the thing is moving
-- (>150 units/s on the sender's side), how the drawn horizontal step behaves: frames with no step,
-- frames with a step above twice what the sender moves (+150 u/s), and the variation of the
-- speed from frame to frame (cv = deviation / mean, 0 = perfectly even). Printed with the 100-tick
-- report as "pm:<kind> ..." and reset there.
Coop.mx = Coop.mx or {}
function Coop.mxOf(kind)
  local m = Coop.mx[kind]
  if not m then
    m = {pk = 0, ivS = 0, ivSS = 0, ivMax = 0, late = 0, jS = 0, jMax = 0, fr = 0, mv = 0, stall = 0,
         spike = 0, vS = 0, vSS = 0, snaps = 0, last = {}}
    Coop.mx[kind] = m
  end
  return m
end

function Coop.mxPacket(kind, iv, jit)
  local m = Coop.mxOf(kind)
  m.pk = m.pk + 1
  if iv then
    m.ivS, m.ivSS, m.ivMax = m.ivS + iv, m.ivSS + iv * iv, math.max(m.ivMax, iv)
    if iv > 0.1 then m.late = m.late + 1 end
  end
  if jit then m.jS, m.jMax = m.jS + math.abs(jit), math.max(m.jMax, math.abs(jit)) end
end

-- x, z: where the thing was drawn this frame; speed: how fast the sender moves it (units/s).
function Coop.mxFrame(kind, key, x, z, now, speed, wx, wz, tx, tz, under)
  local m = Coop.mxOf(kind)
  local l = m.last[key]
  local nl = {x = x, z = z, t = now, tx = tx, tz = tz}
  m.last[key] = nl
  if not l then return end
  -- frames drawn on a guess (the newest state is older than the drawn time: extrapolation)
  if under and speed and speed > 150 then m.und = (m.und or 0) + 1 end
  -- the interpolated target itself: frames in which it did not move although the sender does
  if tx and l.tx and speed and speed > 150 then
    m.tfr = (m.tfr or 0) + 1
    if math.sqrt((tx - l.tx) ^ 2 + (tz - l.tz) ^ 2) < 0.5 then m.tstall = (m.tstall or 0) + 1 end
  end
  local dt = now - l.t
  if dt <= 0 or dt > 0.5 then return end
  m.fr = m.fr + 1
  if speed and speed > 150 and wx then
    -- what the engine moved the body by since it was placed (its own walking on top of the placement)
    local es = math.sqrt((x - wx) ^ 2 + (z - wz) ^ 2)
    m.eS, m.eMax, m.eN = (m.eS or 0) + es, math.max(m.eMax or 0, es), (m.eN or 0) + 1
  end
  if speed and speed > 150 then
    local disp = math.sqrt((x - l.x) ^ 2 + (z - l.z) ^ 2)
    -- a jump of a body (teleport, snap) is not a step: counted apart, out of the speed statistics
    if disp > 200 then
      m.jumps = (m.jumps or 0) + 1
      return
    end
    local v = disp / dt
    -- irregularity: how far a frame's speed is from the mean of its neighbours' (0 = even; a
    -- stop-and-go or a double step shows, a real change of pace barely does); three drawn frames in a row on the move
    nl.v1, nl.v2 = v, l.v1
    if l.v1 and l.v2 and v > 100 and l.v1 > 100 and l.v2 > 100 then
      m.irS, m.irV, m.irN = (m.irS or 0) + math.abs(l.v1 - (l.v2 + v) / 2), (m.irV or 0) + l.v1, (m.irN or 0) + 1
    end
    m.mv = m.mv + 1
    m.vS, m.vSS = m.vS + v, m.vSS + v * v
    if disp < 0.5 then m.stall = m.stall + 1 end
    if v > 2 * speed + 150 then m.spike = m.spike + 1 end
  end
end

-- One frame of a remote thing (squad body, enemy): its speed on the sender's side is read from the
-- history; returns that speed.
function Coop.mxPuppet(kind, name, pos, now, tg, wx, wz)
  local h = Coop.hist[name]
  local sp = 0
  if h and h.n > 1 and h[h.n].rt > h[h.n - 1].rt then
    local a, b = h[h.n - 1], h[h.n]
    sp = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) / (b.rt - a.rt)
  end
  Coop.mxFrame(kind, name, pos.x, pos.z, now, sp, wx, wz, tg and tg.x, tg and tg.z, h and h.under)
  return sp
end

-- Dev trace (cfg.mxtrace = "Jones" or "enemy"): every frame of one remote body, as one log line per 30 frames:
-- time, place before this frame's write (what the engine left), written place, interpolated target, under.
function Coop.mxTrace(name, now, pos, wx, wz, tg)
  local want = cfg.mxtrace
  if not want then return end
  local key
  if Coop.SQUAD_SET[name] then
    key = string.find("," .. want .. ",", "," .. name .. ",", 1, true) and name
  else
    key = string.find("," .. want .. ",", ",enemy,", 1, true) and "enemy"
  end
  if not key then return end
  Coop.mxTr = Coop.mxTr or {}
  local tr = Coop.mxTr[key]
  if not tr then
    tr = {n = 0}
    Coop.mxTr[key] = tr
  end
  if tr.name == nil then tr.name = name elseif tr.name ~= name then return end
  local h = Coop.hist[name]
  tr.n = tr.n + 1
  tr[tr.n] = string.format("%.3f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%d,%.3f", now, pos.x, pos.z, wx or pos.x, wz or pos.z,
    tg and tg.x or 0, tg and tg.z or 0, h and h.under and 1 or 0, h and h.dbgRR or 0)
  if tr.n >= 30 then
    Coop.log("mxt " .. name .. " " .. table.concat(tr, " "))
    Coop.mxTr[key] = nil
  end
end

-- Dev trace on the sending machine (cfg.mxsrc = "Delgado,Enemy259"): where the named bodies really are, every frame, as
-- "mxs <name> t,x,z,y,action ..." (30 frames per line): the truth the client's trace is compared with (lab/mxt.py).
function Coop.mxSource(now)
  local names = cfg.mxsrc
  if not names then return end
  Coop.mxSrcBuf = Coop.mxSrcBuf or {}
  for name in string.gmatch(names, "[^,]+") do
    local e = Game.GetEntity(name)
    if e then
      local ok, p = pcall(function() return e.Pos end)
      if ok and p then
        local b = Coop.mxSrcBuf[name]
        if not b then
          b = {n = 0}
          Coop.mxSrcBuf[name] = b
        end
        b.n = b.n + 1
        b[b.n] = string.format("%.3f,%.1f,%.1f,%.1f,%s", now, p.x, p.z, p.y, tostring(e.Action))
        if b.n >= 30 then
          Coop.log("mxs " .. name .. " " .. table.concat(b, " "))
          Coop.mxSrcBuf[name] = nil
        end
      end
    end
  end
end

-- The enemies' drawn places after the client placed them this frame (coop_enemies.lua driveEnemies).
-- (mxEnemyPre runs before driveEnemies: where the engine left each enemy since it was placed last frame)
Coop.mxPre, Coop.mxPost = {}, {}
function Coop.mxEnemyPre()
  if cfg.mxenemy == false then return end
  for name in pairs(CoopEnemies.targets) do
    local e = Game.GetEntity(name)
    if e then
      local p = e.Pos
      Coop.mxPre[name] = {p.x, p.z}
    end
  end
end

function Coop.mxEnemies(now)
  if cfg.mxenemy == false then return end
  for name, st in pairs(CoopEnemies.targets) do
    local h = Coop.hist[name]
    local e = h and Game.GetEntity(name)
    if e and e.Life > 0 then
      local pos = e.Pos
      local sp = Coop.mxPuppet("enemy", name, pos, now, nil, nil, nil)
      local pre, post = Coop.mxPre[name], Coop.mxPost[name]
      if pre and post and sp > 150 then
        local es = math.sqrt((pre[1] - post[1]) ^ 2 + (pre[2] - post[2]) ^ 2)
        local m = Coop.mxOf("enemy")
        m.eS, m.eMax, m.eN = (m.eS or 0) + es, math.max(m.eMax or 0, es), (m.eN or 0) + 1
      end
      Coop.mxPost[name] = {pos.x, pos.z}
      Coop.mxTrace(name, now, pos, pos.x, pos.z, nil)
    end
  end
end

function Coop.mxReport()
  local out = {}
  for kind, m in pairs(Coop.mx) do
    if m.pk > 0 or m.fr > 0 then
      local n = math.max(m.pk - 1, 1)
      local mean = m.ivS / n
      local sd = math.sqrt(math.max(m.ivSS / n - mean * mean, 0))
      local vm = m.mv > 0 and m.vS / m.mv or 0
      local vsd = m.mv > 0 and math.sqrt(math.max(m.vSS / m.mv - vm * vm, 0)) or 0
      out[#out + 1] = string.format("pm:%s pk=%d iv=%.0f/%.0f/%.0fms late=%d jit=%.0f/%.0fms fr=%d mv=%d stall=%d spike=%d cv=%.2f snaps=%d eng=%.1f/%.0f/%d tstall=%d/%d und=%d irr=%.3f/%d jumps=%d",
        kind, m.pk, mean * 1000, sd * 1000, m.ivMax * 1000, m.late, m.jS / math.max(m.pk, 1) * 1000, m.jMax * 1000,
        m.fr, m.mv, m.stall, m.spike, vm > 0 and vsd / vm or 0, m.snaps, (m.eN or 0) > 0 and m.eS / m.eN or 0, m.eMax or 0, m.eN or 0, m.tstall or 0, m.tfr or 0,
        m.und or 0, (m.irN or 0) > 0 and m.irS / math.max(m.irV, 1e-3) or 0, m.irN or 0, m.jumps or 0)
      Coop.mx[kind] = nil
      Coop.mxOf(kind).last = m.last
    end
  end
  table.sort(out)
  return table.concat(out, " ")
end

-- History of a body's states for interpolation (Coop.hist[name]): ordered by the sender's
-- clock (st.rt); out-of-order and repeated states are dropped (a relay may reorder
-- unreliable messages). Returns false for a dropped state.
Coop.hist = Coop.hist or {}
function Coop.pushState(name, st, interval)
  -- Dev: a lossy link (cfg.simloss = share of states lost, cfg.simburst = states lost in a row once one is): the paths
  -- are drawn from fewer states, as over the internet (chunk W).
  if cfg.simloss then
    Coop.simDrop = Coop.simDrop or {}
    local left = Coop.simDrop[name] or 0
    if left > 0 then
      Coop.simDrop[name] = left - 1
      Coop.simLost = (Coop.simLost or 0) + 1
      return false
    elseif math.random() < cfg.simloss / (cfg.simburst or 1) then
      Coop.simDrop[name] = (cfg.simburst or 1) - 1
      Coop.simLost = (Coop.simLost or 0) + 1
      return false
    end
  end
  local h = Coop.hist[name]
  local now = st.t
  if not st.rt then st.rt = now end   -- a sender without times: its receive time
  if h and h.n > 0 then
    local last = h[h.n]
    -- A new sender (owner change, restarted level): start over.
    if st.rt < last.rt - 2 or st.rt > last.rt + 5 then h = nil end
  end
  if not h then
    h = {n = 0, jit = 0, interval = interval or Coop.TICK}
    Coop.hist[name] = h
  end
  if h.n > 0 and st.rt <= h[h.n].rt then
    Coop.stale = (Coop.stale or 0) + 1
    return false
  end
  -- Clock offset: the smallest (local - sender) time seen lately is the least delayed state;
  -- it may creep up 1 ms per state so a drifting clock is followed.
  local off = now - st.rt
  if not h.off or off < h.off then h.off = off else h.off = h.off + 0.001 end
  h.jit = h.jit * 0.9 + (off - h.off) * 0.1
  if h.n > 0 and not st.noMetric then Coop.mxPacket(st.mxKind or (Coop.SQUAD_SET[name] and "squad" or "enemy"), now - h[h.n].t, off - h.off) end
  -- Receive interval and its deviation (slow averages): the interpolation delay of "adaptive" mode.
  if h.n > 0 then
    local iv = now - h[h.n].t
    h.ivMean = h.ivMean and (h.ivMean * 0.97 + iv * 0.03) or iv
    h.ivDev = h.ivDev and (h.ivDev * 0.97 + math.abs(iv - h.ivMean) * 0.03) or 0
  end
  h.n = h.n + 1
  h[h.n] = st
  -- About two seconds.
  if h.n > 48 then
    table.remove(h, 1)
    h.n = h.n - 1
  end
  return true
end

local function lerpAngle(a, b, u)
  return a + ((b - a + 180) % 360 - 180) * u
end

Coop.TELEPORT = 500   -- units between two states of a body that are a jump (teleport, level script), not a walk
local function jumped(a, b)
  local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
  return dx * dx + dy * dy + dz * dz > Coop.TELEPORT * Coop.TELEPORT
end

-- Cubic Hermite between two states (values p0, p1, slopes m0, m1 in units per second, dt seconds apart).
local function hermite(p0, p1, m0, m1, dt, u)
  local u2 = u * u
  local u3 = u2 * u
  return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * dt * m0 + (3 * u2 - 2 * u3) * p1 + (u3 - u2) * dt * m1
end

-- The slope of a state's path in one axis from its neighbours (either may be missing): the weighted
-- mean of the slopes to both, zero where the path turns round (no overshoot at a stop or a reversal).
local function tangent(prev, cur, nxt, key)
  if prev and jumped(prev, cur) then prev = nil end   -- (a jump is not part of the path)
  if nxt and jumped(cur, nxt) then nxt = nil end
  local cl = prev and cur.rt > prev.rt and (cur[key] - prev[key]) / (cur.rt - prev.rt)
  local cr = nxt and nxt.rt > cur.rt and (nxt[key] - cur[key]) / (nxt.rt - cur.rt)
  if cl and cr then
    if cl * cr <= 0 then return 0 end
    local hl, hr = cur.rt - prev.rt, nxt.rt - cur.rt
    return (hr * cl + hl * cr) / (hl + hr)
  end
  return cl or cr or 0
end

-- The place on a body's path at sender time rr: between the two states around it (a cubic through the states, or
-- straight), carried on the last velocity for a short while when the states stop. Returns the place, whether it is
-- carried on (under) and the state whose inputs and action apply.
local function pathAt(h, rr)
  local a, b = h[1], h[h.n]
  if rr <= a.rt then
    return {x = a.x, y = a.y, z = a.z, yaw = a.yaw, pitch = a.pitch or 0, st = a}, false
  end
  if rr >= b.rt then
    local p = h.n > 1 and h[h.n - 1]
    local ext = math.min(rr - b.rt, Coop.EXTRAP_MAX)
    if not p or b.rt - p.rt <= 0 or ext <= 0 or jumped(p, b) then
      return {x = b.x, y = b.y, z = b.z, yaw = b.yaw, pitch = b.pitch or 0, st = b}, true
    end
    -- (the body slows to a stop over the extrapolation instead of running on at full speed: at a wall, a corner or a turn
    -- the sender's body does not run on, and the lost states are the ones that tell; cfg.extrapdamp=false: full speed, as before 0.2.9)
    if cfg.extrapdamp ~= false then ext = ext - ext * ext / (2 * Coop.EXTRAP_MAX) end
    local k = ext / (b.rt - p.rt)
    return {x = b.x + (b.x - p.x) * k, y = b.y, z = b.z + (b.z - p.z) * k,
            yaw = b.yaw, pitch = b.pitch or 0, st = b}, true
  end
  local i = h.n - 1
  while i > 1 and h[i].rt > rr do i = i - 1 end
  a, b = h[i], h[i + 1]
  local u = (rr - a.rt) / math.max(b.rt - a.rt, 1e-3)
  local x, y, z
  if jumped(a, b) then
    -- a jump between two states: no path through it, the body is at one end or the other
    local c = u < 0.5 and a or b
    return {x = c.x, y = c.y, z = c.z, yaw = c.yaw, pitch = c.pitch or 0, st = c}, false
  elseif Coop.cfg.hermite == false then
    x, y, z = a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u
  else
    -- a smooth path through the states (a cubic with the neighbours' slopes): the straight pieces had
    -- a different speed in each, a step of speed every 0.05 s on a turn or a change of pace
    local p, n = h[i - 1], h[i + 2]
    local dt = math.max(b.rt - a.rt, 1e-3)
    x = hermite(a.x, b.x, tangent(p, a, b, "x"), tangent(a, b, n, "x"), dt, u)
    y = hermite(a.y, b.y, tangent(p, a, b, "y"), tangent(a, b, n, "y"), dt, u)
    z = hermite(a.z, b.z, tangent(p, a, b, "z"), tangent(a, b, n, "z"), dt, u)
  end
  return {
    x = x, y = y, z = z,
    yaw = lerpAngle(a.yaw, b.yaw, u), pitch = (a.pitch or 0) + ((b.pitch or 0) - (a.pitch or 0)) * u,
    st = u < 0.5 and a or b,
  }, false
end

-- How far behind the sender a body is drawn: two states of the sender's rate plus what the network and the frame
-- rate add (the measured lateness of states over the earliest one seen). cfg.olddelay: 0.07 s + twice the lateness.
Coop.DELAY_PACKETS = 2
function Coop.puppetDelay(h)
  local delay
  if Coop.cfg.olddelay then
    delay = math.max(0.07, math.min(Coop.INTERP_MAX, h.interval * 1.4 + 2 * h.jit))
  else
    delay = math.max(Coop.INTERP_MIN, math.min(Coop.INTERP_MAX, Coop.DELAY_PACKETS * h.interval + 3 * h.jit))
  end
  local w = Coop.cfg.psmooth or Coop.SMOOTH_W
  if w > 0 then delay = delay + w / 2 end   -- the averaging window reaches that far ahead
  if Coop.cfg.adaptdelay and h.ivMean then
    -- two packets at least, more as the packets come late or unevenly; it moves slowly (a change of
    -- the delay moves the drawn place, so it may not move faster than 0.05 s per second)
    local want = math.max(0.1, math.min(0.3, h.ivMean + 2.5 * h.ivDev))
    local t = Net.CoopTime()
    local cur = h.delay or want
    cur = cur + math.max(-0.05, math.min(0.05, want - cur)) * math.min(1, (t - (h.delayT or t)))
    h.delay, h.delayT = cur, t
    delay = cur
  end
  return delay
end

-- Where a body should be drawn now: its path (pathAt) at the sender's clock now minus the delay, averaged over
-- Coop.SMOOTH_W seconds around that time. The bodies' own places come from the sender's game at its own pace
-- (the engine moves bodies in steps of its own, a run's stride makes the speed pulse); sampled at 20 Hz these alias
-- into a stop-and-go; the average over a window as long as two states takes the ripple out.
Coop.SMOOTH_W = 0.1
function Coop.puppetTarget(name, now)
  local h = Coop.hist[name]
  if not h or h.n == 0 then return nil end
  local delay = Coop.puppetDelay(h)
  local rr = now - h.off - delay
  h.dbgRR, h.dbgDelay = rr, delay
  local tg, under = pathAt(h, rr)
  h.under = under
  local w = Coop.cfg.psmooth or Coop.SMOOTH_W
  if w > 0 and h.n > 1 then
    -- five places over the window (a trapezoid: the ends count half), summed as differences from the middle one
    local dx, dy, dz = 0, 0, 0
    for k = 0, 4 do
      if k ~= 2 then
        local q = pathAt(h, rr + w * (k / 4 - 0.5))
        if jumped(q, tg) then return tg end   -- a teleport inside the window: no average over it
        local wt = (k == 0 or k == 4) and 0.5 or 1
        dx, dy, dz = dx + (q.x - tg.x) * wt, dy + (q.y - tg.y) * wt, dz + (q.z - tg.z) * wt
      end
    end
    tg.x, tg.y, tg.z = tg.x + dx / 4, tg.y + dy / 4, tg.z + dz / 4
  end
  return tg
end

-- A puppet takes the weapon slot its owner holds (oWeapCtrl.iDesiredSlot, the way the
-- characters' scripts switch). Slots 2/3 are powers used as weapons: the scripts point the
-- main and second weapon at them too (delgado.lua PressSpecial), and back to 0/1 after.
function Coop.syncSlot(e, slot)
  local wc = e.oWeapCtrl
  -- The owner's engine accepted this slot for the same body, so the puppet has it too; a
  -- slot out of range would stop the engine (WeaponCtrl.cpp:180 "i>=0 && i<nSlots").
  if not wc or not slot or slot < 0 or slot > 3 or slot ~= math.floor(slot) then return end
  local ok = pcall(function()
    if tonumber(wc.iSlot) == slot or tonumber(wc.iDesiredSlot) == slot then return end
    wc.iDesiredSlot = slot
    if slot >= 2 then
      wc.idMainWeapon, wc.idSecondWeapon = slot, slot
    elseif tonumber(wc.idMainWeapon) and tonumber(wc.idMainWeapon) >= 2 then
      wc.idMainWeapon, wc.idSecondWeapon = 0, 1
    end
    Coop.log("puppet " .. e.Name .. " takes weapon slot " .. slot)
  end)
  if not ok then Coop.slotErrors = (Coop.slotErrors or 0) + 1 end
end

-- A network player's strikes, reloads and powers on their body here. The owner sends what
-- their first-person arms play ("<weapon set>_<action>", e.g. "01_Combo1Hit1", "02_Reload");
-- the body plays the matching third-person action once, when the class has it (owner's Steam
-- test, 0.2.1: the host saw nothing of a client's melee or powers; shots already showed).
-- The third-person reload of a body is Reload for the first weapon and Reload0 for the second one whose weapon type has the suffix "0"
-- (ReloadShotSufix: Delgado's Raging Bull, Black's grenade launcher, the shotguns of Jones and Ross; Delgado has no plain Reload
-- at all, so his pistol reload showed nothing), ReloadE for Rawlings' fragmenting and explosive loads (FP Reload2 / Reload3).
-- (CoopAnim.reloadAction: coop_anim.lua)
Coop.ARM_ACTIONS = {
  {"^Combo(%d)Hit(%d)$", function(c, cls, a, b) return cls:GetAct("Combo" .. a .. "Hit" .. b) and ("Combo" .. a .. "Hit" .. b) or "Punch" end},
  {"^Punch", "Punch"}, {"^Reload(%d?)", function(...) return CoopAnim.reloadAction(...) end}, {"^Spell", "Spell"}, {"^Hack", "Hack"},
  {"^Special_0Init$", "Shot1Init"}, {"^Special_0$", "Shot1"}, {"^Special_0End$", "Shot1End"},
  {"^Special", "Special1"},
}
-- (a character's own names are matched before the general ones; "" = shown by nothing: the name is a step of a power whose
-- twin is played once, at its start)
-- Rawlings (0.3.0): Special_0* is the ghost heal, Special_1* Vlad's course (rawlings.lua SpecialInit). The general rows took Special_0
-- for the pistol's Shot1 (a shot of the fragmenting load, with its shot events) and replayed Special1 for each of the three steps.
Coop.ARM_BY_CHAR = {
  Black = {["^Special"] = "TKHit"},
  Rawlings = {
    ["^Special_0Init$"] = "ShotH_GH", ["^Special_0$"] = "", ["^Special_0End$"] = "", ["^Special_0Fail$"] = "",
    ["^Special_1Init$"] = "Special1", ["^Special_1$"] = "", ["^Special_1End$"] = "",
    ["^Special_To$"] = "", ["^Special_From$"] = "",
  },
}
Coop.mirrored = {}
function Coop.mirrorArms(e, name, st)
  if Coop.cfg.mirrorarms == false then return end
  local fpa = st.fpa
  if not fpa or fpa == Coop.mirrored[name] then return end
  Coop.mirrored[name] = fpa
  local act = string.match(fpa, "^%d+_(.+)$") or fpa
  local cls = Act.GetClass(e.ActCtrl ~= "" and e.ActCtrl or name)
  if not cls then return end
  local want
  local own = Coop.ARM_BY_CHAR[name]
  if own then
    for pat, a in pairs(own) do if string.find(act, pat) then want = a end end
    if want == "" then return end
  end
  if not want then
    for _, m in ipairs(Coop.ARM_ACTIONS) do
      local caps = {string.match(act, m[1])}
      if caps[1] then
        want = type(m[2]) == "function" and m[2](name, cls, caps[1], caps[2], string.match(fpa, "^(%d+)_")) or m[2]
        break
      end
    end
  end
  if not want then return end
  local crouched = string.find(tostring(st.action), "^Duck") ~= nil
  if crouched and cls:GetAct("Duck" .. want) then want = "Duck" .. want end
  if cls:GetAct(want) then
    e.ForceAction = want
    Coop.mirrorT = Coop.mirrorT or {}
    Coop.mirrorT[name] = Net.CoopTime()
    if Coop.cfg.mirrorlog then Coop.log("mirror: " .. name .. " " .. fpa .. " -> " .. want) end
  end
end

-- Crouching (the game has it standing still only: a step stands up): the puppet stood upright
-- (0.2.2 check). Its crouch input alone does not take (the body here is placed, not walked):
-- the owner's Duck action is played as it comes, and standing up when it ends.
function Coop.syncCrouch(e, name, st)
  local act = tostring(st.action)
  local duck = string.find(act, "^Duck") ~= nil
  local now = string.find(tostring(e.Action), "^Duck") ~= nil
  local v = duck and 1 or 0
  if e.InCtrl_Crouch ~= v then e.InCtrl_Crouch = v end
  if duck == now then return end
  -- (not over a strike or power just mirrored on it, nor again and again if it does not take)
  local t = Net.CoopTime()
  if Coop.mirrorT and t - (Coop.mirrorT[name] or -10) < 1 then return end
  Coop.crouchT = Coop.crouchT or {}
  if t - (Coop.crouchT[name] or -10) < 0.5 then return end
  local cls = Act.GetClass(e.ActCtrl ~= "" and e.ActCtrl or name)
  local want = duck and act or "Relax"
  if cls and cls:GetAct(want) then
    Coop.crouchT[name] = t
    e.ForceAction = want
    if Coop.cfg.mirrorlog then Coop.log("crouch: " .. name .. " -> " .. want) end
  end
end

-- Diagnostics for puppets that keep being snapped (owner's 0.2.7 log: 90-290 snaps per 5 s for
-- minutes with a horizontal error of 0-20, so a body whose height kept leaving the host's).
-- Per puppet (Coop.pd[name], one table per level): the place this driver last wrote, how many
-- snaps and of which kind, how far the engine (or another module) moved the body between two
-- writes. Log lines are rate limited: the first PD_FIRST snaps of a puppet, then one per
-- PD_EVERY seconds; a storm (PD_STORM snaps within PD_WINDOW seconds) adds the map's doors,
-- blockers and lifts, once per PD_QUIET seconds.
Coop.pd = Coop.pd or {}
Coop.posWriters = Coop.posWriters or {}
Coop.PD_FIRST, Coop.PD_EVERY, Coop.PD_STORM, Coop.PD_WINDOW, Coop.PD_QUIET = 3, 2, 20, 5, 30
Coop.PD_MOVED = 40       -- units the body moved between two writes that were not this driver's

-- Other modules that put a body somewhere say so, so a log line can name who wrote last.
function Coop.notePos(name, tag)
  if name then Coop.posWriters[name] = {tag = tag, t = Net.CoopTime()} end
end

local function pdOf(name)
  local d = Coop.pd[name]
  if not d then
    d = {snaps = 0, vsnaps = 0, win = 0, winT = 0, logT = -100, stormT = -100, movedT = -100,
         movedN = 0, eSum = 0, eN = 0}
    Coop.pd[name] = d
  end
  return d
end

-- The body's own view (Action, velocity, collision, AI, life, active), read only when logging.
local function pdBody(e)
  local function g(f) local ok, v = pcall(f) return ok and v ~= nil and tostring(v) or "-" end
  local vel = g(function() local v = e.Vel return string.format("%.0f,%.0f,%.0f", v.x, v.y, v.z) end)
  return string.format("act=%s vel=%s life=%s ign=%s ai=%s active=%s", g(function() return e.Action end), vel,
    g(function() return e.Life end), g(function() return e.bIgnoreCollision end),
    g(function() return e.oAI.bEnable end), g(function() return e.bActive end))
end

local function pdWriter(name, now)
  local w = Coop.posWriters[name]
  return w and string.format("%s %.1fs ago", w.tag, now - w.t) or "none"
end

local function pdSnap(name, e, d, tg, err, dy, pos, now)
  d.snaps = d.snaps + 1
  if math.abs(dy) > Coop.SNAP_DIST and err <= Coop.SNAP_DIST then d.vsnaps = d.vsnaps + 1 end
  if now - d.winT > Coop.PD_WINDOW then d.win, d.winT = 0, now end
  d.win = d.win + 1
  if d.snaps <= Coop.PD_FIRST or now - d.logT >= Coop.PD_EVERY then
    d.logT = now
    Coop.log(string.format("snap %s #%d %s err=%.0f dy=%.0f local.y=%.0f target.y=%.0f wrote.y=%s lastWriter=%s | %s",
      name, d.snaps, math.abs(dy) > Coop.SNAP_DIST and err <= Coop.SNAP_DIST and "VERTICAL" or "horizontal",
      err, dy, pos.y, tg.y, d.wy and string.format("%.0f", d.wy) or "-", pdWriter(name, now), pdBody(e)))
  end
  if d.win >= Coop.PD_STORM and now - d.stormT >= Coop.PD_QUIET then
    d.stormT = now
    Coop.log(string.format("snap storm %s: %d snaps in %.1fs (vertical %d of %d), action here %s, owner's %s; %s",
      name, d.win, now - d.winT, d.vsnaps, d.snaps, tostring(e.Action),
      tostring(Coop.remote[name] and Coop.remote[name].action),
      CoopWorld and CoopWorld.context and CoopWorld.context() or "no world module"))
    if CoopWorld and CoopWorld.near then
      Coop.log("snap storm " .. name .. " near the body: " .. CoopWorld.near(pos, 1000))
    end
  end
  if d.win > Coop.STORM_SNAPS and cfg.stormrelease ~= false then Coop.stormRelease(name, e, d, now) end
end

-- Safety net: a body the engine puts back after every placement (a replayed use that pins it, a
-- link, a script that moves it) gets more than STORM_SNAPS snaps within the window: the driver
-- lets go of it for a while (collision and AI back, the engine's pins undone, nothing placed), then
-- places it again; a storm that comes back at once is let go for twice as long (up to 8 s).
Coop.STORM_SNAPS, Coop.STORM_HOLD = 20, 1
function Coop.stormRelease(name, e, d, now)
  local hold = Coop.STORM_HOLD
  if d.holdEnd and now - d.holdEnd < 5 then hold = math.min(8, (d.holdLen or hold) * 2) end
  d.holdLen, d.holdEnd = hold, now + hold
  d.win, d.winT = 0, now
  d.stormReleases = (d.stormReleases or 0) + 1
  Coop.log(string.format("snap storm: released %s for %.0f s (%d snaps in %.1f s; act=%s lock=%s inv=%s offmul=%s)", name, hold,
    Coop.STORM_SNAPS + 1, Coop.PD_WINDOW, tostring(e.Action), tostring(e.IgnoreUsrControl), tostring(e.Invulnerable),
    tostring(e.OffMul)))
  pcall(Coop.releasePuppet, e)
  Coop.clearPins(e)
end

-- What keeps the engine moving a body after a script left it half way (lab 2026-10-30, the replayed
-- MakeFP.CoolUse): the entity's MoveMePosAng(2, ...) holds it at the place it had when the call ran
-- for good (the body is put back after every placement; clearing the lock, invulnerability, model
-- offset and link did not end it), and it leaves OffMul 1 with TgModelPos at the object's node (the skeleton's node positions stayed with the body in the lab: no displaced model seen).
-- A new short move to where the body is replaces the old one; OnEndMove is cleared first (it would
-- run the script's next step with state that is gone).
function Coop.clearPins(e)
  pcall(function() e.Vel = V3D(0, 0, 0) end)
  pcall(function() e.OnEndMove = "" end)
  pcall(function() e.OffMul = 0 e.DeltaOffMul = 0 end)
  pcall(function() e:MoveMePosAng(1, 0.05, e.Pos, e.Ang) end)
  -- What CoolUse set on the user: nobody plays a puppet here, so the control lock goes (not during a scene or a
  -- story walk, which lock bodies themselves) and invulnerability goes back to what it was before the call.
  pcall(function()
    if e.Invulnerable == 1 then
      local was = e.uData and e.uData.LastInvulnerableState
      e.Invulnerable = (was == 1) and 1 or 0
      if e.uData then e.uData.LastInvulnerableState = nil end
    end
    if e.IgnoreUsrControl == 1 and not (Scene and Scene.IsPlaying) and not (Coop.storyDriven and Coop.storyDriven[e.Name]) then
      e.IgnoreUsrControl = 0
    end
  end)
end

function Coop.stormHeld(name, now)
  local d = Coop.pd[name]
  return d and d.holdEnd and now < d.holdEnd
end

-- The body is not where this driver put it: the engine (gravity, floor, an action) or another
-- module moved it.
local function pdMoved(name, e, d, pos, now)
  local mx, my, mz = pos.x - d.wx, pos.y - d.wy, pos.z - d.wz
  d.eSum, d.eN = d.eSum + my, d.eN + 1
  if math.abs(mx) + math.abs(my) + math.abs(mz) > Coop.PD_MOVED and d.movedN < 30 and now - d.movedT >= Coop.PD_EVERY then
    d.movedT, d.movedN = now, d.movedN + 1
    Coop.log(string.format("puppet %s moved outside the driver by %.0f,%.0f,%.0f (%.2fs after the write); lastWriter=%s | %s",
      name, mx, my, mz, now - d.wt, pdWriter(name, now), pdBody(e)))
  end
end

-- Where the host's copy of a client's own body stands (hp, once a second per remote body, host to
-- its owner): a client that is stuck at an invisible wall, or runs through a texture, is somewhere
-- other than the host's copy of it. The owner logs a difference above PD_OWN units.
Coop.PD_OWN, Coop.PD_OWN_Y = 300, 150
Coop.pdOwn = Coop.pdOwn or {}
function Coop.sendHostPos()
  if cfg.pdiag == false then return end
  for name, owner in pairs(Coop.owners) do
    local peer = Coop.peerOf(owner)
    if owner ~= nil and not Coop.isMine(owner) and peer and peer ~= 0 then
      local e = Coop.squadEnt(name)
      local ok, line = pcall(function()
        local p = e.Pos
        return string.format("hp|%s|%.0f|%.0f|%.0f|%s", name, p.x, p.y, p.z, tostring(e.Action))
      end)
      if e and ok then Net.CoopSend(peer, 0, line) end
    end
  end
end

function Coop.onHostPos(f)
  local name = f[2]
  local e = name and Coop.isLocalBody(name) and Game.GetEntity(name)
  local hx, hy, hz = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
  if not e or not hx or not hy or not hz then return end
  local p = e.Pos
  local h = math.sqrt((p.x - hx) ^ 2 + (p.z - hz) ^ 2)
  local dy = p.y - hy
  local d = Coop.pdOwn[name]
  if not d then d = {n = 0, logT = -100} Coop.pdOwn[name] = d end
  d.host = {x = hx, y = hy, z = hz, t = Net.CoopTime()}
  local now = Net.CoopTime()
  if (h > Coop.PD_OWN or math.abs(dy) > Coop.PD_OWN_Y) and now - d.logT >= 5 and d.n < 40 then
    d.n, d.logT = d.n + 1, now
    Coop.log(string.format("own body %s differs from the host's copy of it by %.0f flat, dy=%.0f (here %.0f,%.0f,%.0f; host's copy %.0f,%.0f,%.0f action %s; mine %s) | %s",
      name, h, dy, p.x, p.y, p.z, hx, hy, hz, tostring(f[6]), tostring(e.Action), pdBody(e)))
  end
end

-- A local player's body that is pushed into something and does not move (an invisible wall, a
-- door that is shut here only, a floor that is not there): input on, almost no movement for
-- PD_STUCK seconds. Logs the body's place, what is near it and where the host's copy of it is.
Coop.PD_STUCK = 2
function Coop.pdStuck(now)
  if cfg.pdiag == false then return end
  local bodies = {Game.UsrEntity(0)}
  if CoopSplit and CoopSplit.on and CoopSplit.body then bodies[2] = CoopSplit.body() end
  for i = 1, 2 do
    local e = bodies[i]
    if e and (e.Life or 0) > 0 then
      local name = e.Name
      local d = Coop.pdOwn[name]
      if not d then d = {n = 0, logT = -100} Coop.pdOwn[name] = d end
      local p = e.Pos
      -- A body this machine's player holds must collide: one still marked as a puppet's (collision
      -- off) walks through walls and falls through the floor.
      local okc, ign = pcall(function() return e.bIgnoreCollision end)
      if okc and ign == true and not Coop.isPuppet(name) then
        d.ignFirst = d.ignFirst or now
        -- (the engine sets it for a moment itself, in scripted moves: only a lasting one is undone)
        if now - d.ignFirst > 3 and cfg.localcollide ~= false then
          pcall(function() e.bIgnoreCollision = false end)
          d.ignFirst = nil
          Coop.log(string.format("local body %s had collision ignore ON for 3 s (puppet record %s, life %s, action %s, at %.0f,%.0f,%.0f): set off",
            name, tostring(Coop.puppetNoCollide and Coop.puppetNoCollide[name]), tostring(e.Life), tostring(e.Action), p.x, p.y, p.z))
        end
      else
        d.ignFirst = nil
      end
      if not d.t then
        d.t, d.x, d.z, d.stuck, d.sn, d.sT = now, p.x, p.z, 0, 0, -100
      elseif now - d.t >= 1 then
        local moved = math.sqrt((p.x - d.x) ^ 2 + (p.z - d.z) ^ 2)
        local pushing = math.abs(tonumber(e.InCtrl_Walk) or 0) > 0.5 or math.abs(tonumber(e.InCtrl_Str) or 0) > 0.5
        d.t, d.x, d.z = now, p.x, p.z
        if pushing and moved < 30 and tonumber(e.IgnoreUsrControl) ~= 1 then d.stuck = d.stuck + 1 else d.stuck = 0 end
        if d.stuck >= Coop.PD_STUCK and now - d.sT >= 5 and d.sn < 40 then
          d.sT, d.sn = now, d.sn + 1
          local hc = d.host and now - d.host.t < 3 and
            string.format("host's copy %.0f,%.0f,%.0f (%.0f flat away)", d.host.x, d.host.y, d.host.z,
              math.sqrt((p.x - d.host.x) ^ 2 + (p.z - d.host.z) ^ 2)) or "no host copy"
          Coop.log(string.format("stuck: %s at %.0f,%.0f,%.0f for %ds, walk=%.2f str=%.2f; %s; floorDist=%s | %s | near: %s",
            name, p.x, p.y, p.z, d.stuck, tonumber(e.InCtrl_Walk) or 0, tonumber(e.InCtrl_Str) or 0, hc,
            tostring(e.FloorDist), pdBody(e), CoopWorld and CoopWorld.near and CoopWorld.near(p, 800) or "-"))
        end
      end
    end
  end
end

-- The floor distance of a crouched body (e.FloorDist: the feet are Pos.y - FloorDist below the
-- body) is lowered by the class's DispCrouch (60) by the engine's own crouch handling, which a
-- puppet does not run (its crouch is an action played on it). The owner's height is that of a
-- crouched body, so the puppet's feet stood 60 units below the floor: bodies crouched in cover
-- were sunk waist-deep, most visibly on slopes (owner's 0.2.7 Vigil screenshot; lab 2026-10-28:
-- feet -58 against +3 for the same body on the host). The puppet gets the owner's value.
Coop.floorBase = Coop.floorBase or {}   -- name -> standing FloorDist, recorded while the body stands
Coop.floorSet = Coop.floorSet or {}     -- name -> true while this driver has changed it
Coop.CROUCH_DISP = 60
Coop.ymdBase = Coop.ymdBase or {}     -- name -> standing YModelDisp
function Coop.syncModelDisp(e, name, act, ownerYmd)
  if cfg.puppetfloor == false then return end
  local ok, cur = pcall(function() return tonumber(e.YModelDisp) end)
  if not ok or not cur then return end
  local want
  local duck = string.find(tostring(act), "^Duck") ~= nil
  if ownerYmd then
    want = ownerYmd
    -- (standing is the lower value)
    if not Coop.ymdBase[name] or ownerYmd < Coop.ymdBase[name] then Coop.ymdBase[name] = ownerYmd end
  else
    if not duck and not Coop.ymdSet then Coop.ymdSet = {} end
    Coop.ymdSet = Coop.ymdSet or {}
    if not duck and not Coop.ymdSet[name] then Coop.ymdBase[name] = cur end
    local base = Coop.ymdBase[name] or cur
    want = duck and base + Coop.CROUCH_DISP or base
  end
  if math.abs(cur - want) > 0.5 then
    pcall(function() e.YModelDisp = want end)
    Coop.ymdSet = Coop.ymdSet or {}
    Coop.ymdSet[name] = true
  end
end

function Coop.syncFloorDist(e, name, act, ownerFd)
  if cfg.puppetfloor == false then return end
  local ok, fd = pcall(function() return tonumber(e.FloorDist) end)
  if not ok or not fd then return end
  local want
  if ownerFd then
    -- the owner's own value (any stance); the standing one is the larger
    want = ownerFd
    if not Coop.floorBase[name] or ownerFd > Coop.floorBase[name] then Coop.floorBase[name] = ownerFd end
  else
    -- an owner that does not send it (an older version): crouched by the action's name
    local duck = string.find(tostring(act), "^Duck") ~= nil
    if not duck and not Coop.floorSet[name] then Coop.floorBase[name] = fd end
    local base = Coop.floorBase[name] or 129.09
    want = duck and base - Coop.CROUCH_DISP or base
  end
  if math.abs(fd - want) > 0.5 then
    pcall(function() e.FloorDist = want end)
    Coop.floorSet[name] = true
  end
end

function Coop.drivePuppets(dt)
  -- Scenes freeze and hide the squad (Scene.HideChars); puppets resume afterwards.
  if Scene and Scene.IsPlaying then return end
  pcall(Coop.pdStuck, Net.CoopTime())
  -- FOLLOW is the share of the error removed per 0.05 s; scale it to this frame's length.
  local fshare = Coop.cfg.pfollow or Coop.FOLLOW
  local follow = fshare >= 1 and 1 or 1 - (1 - fshare) ^ (math.min(dt, 0.25) / 0.05)
  local now = Net.CoopTime()
  local localKeys = Coop.keepLocalRootMotion()
  Coop.puppetNoCollide = Coop.puppetNoCollide or {}
  for _, name in ipairs(Coop.SQUAD) do
    local e = Coop.squadEnt(name)
    local st = Coop.remote[name]
    -- A body that stopped being a puppet gets its collision and AI back whatever its life: one
    -- that died as a puppet and then went to a local player or the AI kept "collision ignore"
    -- on (it was released only for a living body): the player walked through walls and fell
    -- through the floor (lab 2026-10-28, owner's 0.2.7 report).
    if e and Coop.puppetNoCollide[name] ~= nil and not (st and Coop.isPuppet(name)) then Coop.releasePuppet(e) end
    if e and st and CoopTeam and Coop.isPuppet(name) then CoopTeam.syncPuppetLife(e, st) end
    if e and st and Coop.isPuppet(name) then Coop.syncPuppetActive(e, st) end
    if e and st and CoopAnim and Coop.isPuppet(name) then CoopAnim.sync(e, name, st) end
    if e and e.Life and e.Life > 0 then
      local tg = Coop.isPuppet(name) and st and not Coop.stormHeld(name, now) and Coop.puppetTarget(name, now)
      if tg then
        if e.oAI and e.oAI.bEnable and not cfg.puppetai then e.oAI.bEnable = false end
        -- The network places this body: colliding with the local player or other soldiers
        -- made them shove each other and the body shook (fork MAK-PIVO/jericho-coop).
        if Coop.puppetNoCollide[name] == nil and cfg.puppetcollide ~= true then
          local ok, was = pcall(function() return e.bIgnoreCollision end)
          -- (squad bodies collide: a "true" read here is the engine's own, momentary (the AI's shelter
          -- sprint sets it): restoring that one left a player's body without collision, lab 2026-10-28)
          Coop.puppetNoCollide[name] = false
          Coop.log(string.format("puppet %s: collision ignore was %s, now on (life %s, action %s)", name,
            tostring(was), tostring(e.Life), tostring(e.Action)))
          pcall(function() e.bIgnoreCollision = true end)
        end
        Coop.suppressRootMotion(e, localKeys)
        local pos = e.Pos
        local d = pdOf(name)
        if d.wy and (pos.x ~= d.wx or pos.y ~= d.wy or pos.z ~= d.wz) then pdMoved(name, e, d, pos, now) end
        local dx, dy, dz = tg.x - pos.x, tg.y - pos.y, tg.z - pos.z
        local err = math.sqrt(dx * dx + dz * dz)
        do
          local h = Coop.hist[name]
          local sp = Coop.mxPuppet("squad", name, pos, now, tg, d.wx, d.wz)
          if cfg.mxdump and sp > 150 then
            Coop.mxRing = Coop.mxRing or {}
            Coop.mxRing[#Coop.mxRing + 1] = string.format("%.3f rr%.3f d%.3f n%d new%.3f t%.0f p%.0f", now, (h.dbgRR or 0) % 1000, h.dbgDelay or 0, h.n, h[h.n].rt % 1000, tg.x, pos.x)
            if #Coop.mxRing > 14 then table.remove(Coop.mxRing, 1) end
          end
          if cfg.mxdump and sp > 150 and (Coop.mxDumpT or 0) < now - 5 then
            Coop.log("mxframes " .. table.concat(Coop.mxRing or {}, " | "))
            -- (the newest states and what the target did: to see where a stop-and-go comes from)
            Coop.mxDumpT = now
            local t = {}
            for i = math.max(1, h.n - 9), h.n do t[#t + 1] = string.format("%.3f:%.0f,%.0f", h[i].rt, h[i].x, h[i].z) end
            Coop.log(string.format("mxdump %s now=%.3f off=%.3f delay~%.3f target=%.0f,%.0f states %s", name, now, h.off or 0,
              h.delay or (Coop.cfg.adaptdelay and 0 or math.max(Coop.INTERP_MIN, math.min(Coop.INTERP_MAX, h.interval * 1.4 + 2 * h.jit))),
              tg.x, tg.z, table.concat(t, " ")))
          end
        end
        local wx, wy, wz
        if err > Coop.SNAP_DIST or math.abs(dy) > Coop.SNAP_DIST then
          wx, wy, wz = tg.x, tg.y, tg.z
          Coop.snaps = (Coop.snaps or 0) + 1
          Coop.mxOf("squad").snaps = Coop.mxOf("squad").snaps + 1
          if err > 5000 then Coop.log(string.format("puppet %s moved %.0f", name, err)) end
          pdSnap(name, e, d, tg, err, dy, pos, now)
        else
          -- The body walks on its own inputs (animation, collision); this keeps it on the
          -- interpolated path every frame, without a dead zone that would make it jump.
          wx, wy, wz = pos.x + dx * follow, math.abs(dy) > Coop.FOLLOW_Y and pos.y + dy * follow or pos.y, pos.z + dz * follow
        end
        e.Pos = V3D(wx, wy, wz)
        d.wx, d.wy, d.wz, d.wt = wx, wy, wz, now
        if cfg.mxtrace then Coop.mxTrace(name, now, pos, wx, wz, tg) end
        Coop.notePos(name, "drivePuppets")
        -- The engine's walker takes a body whose height is not on its own floor (the owner jumps,
        -- stands on a stair or a prop, or the floor differs here) for falling and lets it fall at
        -- a growing speed, with no limit: lab 2026-10-28, a running puppet reached -4800 units/s
        -- within 1.7 s and dropped hundreds of units between two frames (snap storms, bodies seen
        -- sunk into the map). The height is the owner's, so the fall is cancelled every frame.
        if cfg.puppetfall ~= false then
          local ok, v = pcall(function() return e.Vel end)
          -- The horizontal part too: the engine walks the body from its inputs on top of the placement
          -- (lab 2026-10-29: 34 units per frame after each placement, 3 times what the owner moves,
          -- so the drawn body went forward and was put back every frame: 31 % of the frames with a
          -- step above twice the owner's speed, speed variation cv 0.98; with the velocity zeroed
          -- the engine's step is 1.3 units, no such frames, cv 0.27). cfg.zerovel=false: vertical only.
          local zeroH = cfg.zerovel ~= false
          if ok and v and (zeroH or v.y < -20 or v.y > 20) then
            pcall(function() e.Vel = zeroH and V3D(0, 0, 0) or V3D(v.x, 0, v.z) end)
            d.velFixed = (d.velFixed or 0) + 1
          end
        end
        e.Ang = V3D(0, tg.yaw, 0)
        e.ViewAng = V3D(tg.pitch, tg.yaw, 0)
        -- Firing through the body's own control makes the engine play the shot (sound,
        -- flash, animation); damage from puppet shots is dropped in coop_enemies.lua.
        -- Shots, the weapon in hand and the arms' actions come from the state drawn now, as the movement does:
        -- from the newest one they ran ahead of the body by the interpolation delay (0.1-0.2 s: the flash and
        -- the tracer left a body that had not turned yet). cfg.shotnewest: the old way.
        local sst = cfg.shotnewest and st or tg.st
        if CoopAnim and CoopAnim.driveFire then CoopAnim.driveFire(e, name, sst)
        elseif e.owc then e.owc.Shot = sst.shot or 0 end
        Coop.syncSlot(e, sst.slot)
        Coop.mirrorArms(e, name, sst)
        -- (coop_anim.lua may override the inputs: a body held in a state (dazed, trance, astral, possessed) does not walk, the
        -- drawn state's walk input is up to 0.2 s behind and broke the low-priority Init; a first-person hurdle/climb runs)
        local mo = CoopAnim and CoopAnim.moveOverride and CoopAnim.moveOverride(name)
        e.InCtrl_Walk = mo and mo.walk or tg.st.walk
        e.InCtrl_Str = mo and mo.str or tg.st.str
        e.InCtrl_Sprint = mo and mo.sprint or tg.st.sprint
        Coop.syncCrouch(e, name, tg.st)
        Coop.syncFloorDist(e, name, tg.st.action, tg.st.fd)
        Coop.syncModelDisp(e, name, tg.st.action, tg.st.ymd)
        Coop.perr = Coop.perr or {}
        Coop.perr[name] = err
        Coop.errN = (Coop.errN or 0) + 1
        Coop.errSum = (Coop.errSum or 0) + err
        Coop.errMax = math.max(Coop.errMax or 0, err)
      elseif Coop.wasPuppet and Coop.wasPuppet[name] then
        Coop.releasePuppet(e)
      end
    elseif e and st and Coop.isPuppet(name) and cfg.puppetdead ~= false then
      -- A downed puppet stays where its owner's body lies: it was left alone before, and a body with
      -- collision ignored and nobody placing it rose at +1500 units/s up to the level's ceiling
      -- (lab 2026-10-28: Cole at 1318 against 729, snapped back at the revive).
      local tg = Coop.puppetTarget(name, now)
      if tg then
        local pos = e.Pos
        local d = pdOf(name)
        if d.wy and (pos.x ~= d.wx or pos.y ~= d.wy or pos.z ~= d.wz) then pdMoved(name, e, d, pos, now) end
        e.Pos = V3D(tg.x, tg.y, tg.z)
        d.wx, d.wy, d.wz, d.wt = tg.x, tg.y, tg.z, now
        Coop.notePos(name, "drivePuppets(down)")
        local ok, v = pcall(function() return e.Vel end)
        if ok and v and (v.y < -20 or v.y > 20) then pcall(function() e.Vel = V3D(v.x, 0, v.z) end) end
      end
    end
  end
  Coop.wasPuppet = {}
  for _, name in ipairs(Coop.SQUAD) do
    if Coop.isPuppet(name) and Coop.remote[name] then Coop.wasPuppet[name] = true end
  end
end

-- Squad bodies are solid in the original game (lab 2026-10-30, single player: a body that walks into another stops at a centre distance
-- of 90-100 units and pushes it aside or stands still; with the other body's collision off it walked through at once). The bodies other
-- machines drive here are puppets with collision off (placed by the network, they must not shove or shake), so this machine's own bodies
-- walked through them: the players' bodies (the user, split screen's player 2) and, on the host, the AI squad bodies. A soft push-apart:
-- a solid body closer than PUSH_SEP to a puppet is moved away from it by the overlap (at most PUSH_SPEED units a second), never into a wall
-- (a line to where it would go), not while a script holds it (IgnoreUsrControl, story walks, scenes; cfg.pushscripted=true for the test bots that
-- hold their body that way), not a downed or dead body. cfg.bodypush=false: off. The puppets themselves are never moved (their place is their owner's).
Coop.PUSH_SEP, Coop.PUSH_SPEED, Coop.PUSH_PART, Coop.PUSH_DY = 90, 900, 1, 130
Coop.push = Coop.push or {n = 0, blocked = 0, maxOv = 0, logT = 0}
function Coop.bodyPush(dt)
  if Scene and Scene.IsPlaying then return end
  if CoopSpirit and CoopSpirit.active then return end   -- (the player is a spirit: no body of theirs to move)
  local pups = {}
  for _, name in ipairs(Coop.SQUAD) do
    if Coop.isPuppet(name) and Coop.remote[name] and not Coop.storyDriven[name] then
      local e = Coop.squadEnt(name)
      if e and (e.Life or 0) > 0 then pups[#pups + 1] = e end
    end
  end
  if #pups == 0 then return end
  local solids = {}
  local function add(e)
    if e and (e.Life or 0) > 0 and (e.IgnoreUsrControl ~= 1 or cfg.pushscripted) and not Coop.storyDriven[e.Name] and not Coop.isPuppet(e.Name) then
      solids[#solids + 1] = e
    end
  end
  add(Game.UsrEntity(0))
  if CoopSplit and CoopSplit.on and CoopSplit.body then add(CoopSplit.body()) end
  if Coop.isHost() then
    for _, name in ipairs(Coop.SQUAD) do
      local e = Coop.squadEnt(name)
      if e and e.bActive and not Coop.isLocalBody(name) then add(e) end
    end
  end
  local P = Coop.push
  for _, s in ipairs(solids) do
    for _, p in ipairs(pups) do
      if p ~= s then
        local sp, pp = s.Pos, p.Pos
        local dx, dz = sp.x - pp.x, sp.z - pp.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d < Coop.PUSH_SEP and math.abs(sp.y - pp.y) < Coop.PUSH_DY then
          local ux, uz
          if d > 1 then
            ux, uz = dx / d, dz / d
          else
            local yaw = math.rad(s.Ang.y)   -- exactly on it: back off the way the body looks away from
            ux, uz = math.sin(yaw), math.cos(yaw)
          end
          local step = math.min((Coop.PUSH_SEP - d) * Coop.PUSH_PART, Coop.PUSH_SPEED * math.min(math.max(dt or 0.033, 0.008), 0.1))
          -- the way away, or a way to either side, that is not a wall
          local moved = false
          for _, a in ipairs({0, 0.6, -0.6, 1.2, -1.2}) do
            local c, sn = math.cos(a), math.sin(a)
            local vx, vz = ux * c - uz * sn, ux * sn + uz * c
            local ok, hit = pcall(Game.TestLine, sp, V3D(sp.x + vx * (step + 40), sp.y, sp.z + vz * (step + 40)), "")
            if ok and not hit then
              s.Pos = V3D(sp.x + vx * step, sp.y, sp.z + vz * step)
              moved = true
              break
            end
          end
          P.n = P.n + 1
          P.maxOv = math.max(P.maxOv, Coop.PUSH_SEP - d)
          if not moved then P.blocked = P.blocked + 1 end
        end
      end
    end
  end
  local now = Net.CoopTime()
  if P.n > (P.logN or 0) and now - P.logT > 30 then
    P.logT, P.logN = now, P.n
    Coop.log(string.format("bodypush: %d pushes (%d with no free way), deepest overlap %.0f units", P.n, P.blocked, P.maxOv))
  end
end

-- Other players' flashlights: the game has one camera-bound flashlight (the local player's),
-- so another player's beam is a spot light at their body's weapon, aimed with their view.
-- How a SpotLight takes its settings (dev.lua 'lighttest', 2026-10-20): Ang (0,0,0) points
-- down, (90 + view pitch, yaw, 0) along the view (pitch up is positive); the cone works only
-- with a projector texture (else it lights all around); bLightOverShoot adds a second spot
-- the opposite way; Del takes effect on the next frame.
Coop.FLASH_NODE = "NodePosHierarchy_DF_Burst_A"
Coop.LIGHT_BODIES = {"Jones", "Cole", "Delgado", "Church", "Rawlings", "Black", "Ross"}

function Coop.puppetLights()
  if cfg.puppetlights == false then return end
  local scene = Scene and Scene.IsPlaying
  for _, name in ipairs(Coop.LIGHT_BODIES) do
    local id = "CoopFlash" .. name
    -- Looked up only once made (the engine logs every lookup of a missing entity).
    Coop.flashLights = Coop.flashLights or {}
    local light = Coop.flashLights[name] and Game.GetEntity(id)
    local e
    if name == "Ross" then
      -- Act 1: another machine's Ross is shown by his stand-in (coop_ross.lua).
      e = CoopRoss and Coop.actOne() and CoopRoss.body()
      if e and e.Active == 0 then e = nil end
    else
      e = Coop.squadEnt(name)
    end
    local st = Coop.remote[name]
    -- A split screen player's body (coop_split.lua) is driven here, its flashlight too.
    local p2 = CoopSplit and CoopSplit.on and CoopSplit.char == name
    local on = not scene and e and e.Life > 0 and
               (p2 and CoopSplit.flash or (st and st.flash and Coop.isPuppet(name)))
    if on then
      local pos = e[Coop.FLASH_NODE] or (e.Pos + V3D(0, 150, 0))
      local va = p2 and e.ViewAng
      local ang = va and V3D(va.x + 90, va.y, 0) or V3D((st.pitch or 0) + 90, st.yaw or 0, 0)
      if not light then
        light = PhysicsObj.CreateObj(id, "SpotLight", pos, ang, false)
        Coop.flashLights[name] = true
        light.LightConeInner00 = 15
        light.LightConeOuter00 = 32
        light.LightRange00 = 1400
        light.LightIntens00 = 1
        light.LightColor00 = V4D(255, 245, 225, 255)
        -- The flashlight's own texture (lights.ini Light20; SMOD sets FPSFlashLightTexture).
        light.bLightProjEnable00 = true
        local tex = tonumber(Game.Get("FPSFlashLightTexture"))
        light.ProjID00 = (tex and tex > 0) and tex or 20
        light.bLightOverShoot00 = false
        light.LightAttStart00 = 0
        light.LightDotAtt00 = 0.5
        light.LightDirVector00 = V4D(0, 0, 0, 0)
        light.bLightShadow00 = (tonumber(Game.Get("FPSFlashLightShadows")) or 0) ~= 0
        light.LightShadowMapBias00 = 1
        light.LightQualityDist00 = 2000
        light.bLightSectorEnable00 = true
        Coop.log("flashlight of " .. name .. " on")
      else
        light.Pos = pos
        light.Ang = ang
      end
    elseif light then
      light:Del()
      Coop.flashLights[name] = nil
      Coop.log("flashlight of " .. name .. " off")
    end
  end
end

------------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------------

function Coop.onMessage(peer, data)
  local f = split(data)
  local kind = f[1]
  if CoopEnemies and CoopEnemies.onMessage(peer, f) then return end
  if CoopTeam and CoopTeam.onMessage(peer, f) then return end
  if CoopScenes and CoopScenes.onMessage(peer, f) then return end
  if CoopSpirit and CoopSpirit.onMessage(peer, f) then return end
  if CoopWorld and CoopWorld.onMessage(peer, f, data) then return end
  if CoopClaim and CoopClaim.onMessage(peer, f) then return end
  if CoopSquad and CoopSquad.onMessage(peer, f) then return end
  if CoopSave and CoopSave.onMessage(peer, f) then return end
  if CoopStory and CoopStory.onMessage(peer, f) then return end
  if CoopSplits and CoopSplits.onMessage(peer, f) then return end
  if CoopPatrol and CoopPatrol.onMessage(peer, f) then return end
  if CoopTalk and CoopTalk.onMessage(peer, f) then return end
  if CoopPowers and CoopPowers.onMessage(peer, f, data) then return end
  if kind == "s" then
    local name = f[2]
    -- Only the owner (or the host for unowned bodies) may drive a body.
    local owner = Coop.owners[name]
    if Coop.isHost() and Coop.peerOf(owner) ~= peer then return end
    -- States sent in the last level and delivered after the load hold that level's places: a
    -- body put there fell through the map (0.2.7 campaign test: player 2 at Rom_Coloseum, the
    -- host relayed the client's own old state back before split screen took the body). The
    -- host takes a peer's states once it said it loaded this level (lready), a client after
    -- its first second; and nobody's relayed copy of this machine's own bodies.
    local ready = CoopEnemies and CoopEnemies.readyPeers
    if (Coop.isHost() and ready and not ready[peer] and Coop.frame < 300) or (not Coop.isHost() and Coop.frame < 30) then
      Coop.oldStates = (Coop.oldStates or 0) + 1
      if Coop.oldStates == 1 then Coop.log("state of " .. tostring(name) .. " from before this level dropped") end
      return
    end
    if not Coop.isHost() and Coop.isLocalBody(name) and not Coop.storyDriven[name] then return end
    local st = {
      x = tonumber(f[3]), y = tonumber(f[4]), z = tonumber(f[5]),
      yaw = tonumber(f[6]), pitch = tonumber(f[7]),
      walk = tonumber(f[8]), str = tonumber(f[9]), sprint = tonumber(f[10]),
      life = tonumber(f[11]), action = f[12], shot = tonumber(f[13]) or 0, flash = f[14] == "1",
      raw = data, t = Net.CoopTime(), seq = tonumber(f[15]), rt = tonumber(f[16]), slot = tonumber(f[17]),
      fpa = f[18],
      sec = f[22] == "1", modes = f[23],
    }
    if f[19] == "1" then st.on = true elseif f[19] == "0" then st.on = false end
    local fd = tonumber(f[20])
    if fd and fd > 1 then st.fd = fd end
    if f[21] and tonumber(f[21]) and st.fd then st.ymd = tonumber(f[21]) end
    if not st.x or not st.z then return end
    if Coop.pushState(name, st) then Coop.remote[name] = st end
  elseif kind == "hp" and Coop.isClient() then
    pcall(Coop.onHostPos, f)
  elseif kind == "jump" then
    -- Another player jumped (SMOD's jump, coop_smod.lua): the same push for their body here.
    local name = f[2]
    if Coop.isHost() then
      if Coop.peerOf(Coop.owners[name]) ~= peer then return end
      Net.CoopSend(-1, 1, data)
    end
    -- The body's height follows its owner's (drivePuppets), so the jump's arc comes with the
    -- states: a push here as well lifted it twice. Counted for the dev checks.
    local e = Game.GetEntity(name)
    if e and Coop.isPuppet(name) and e.Life > 0 then
      Coop.lastJump = {name = name, y = e.Pos.y, peak = e.Pos.y, frame = Coop.frame}
      Coop.jumpsSeen = (Coop.jumpsSeen or 0) + 1
    end
  elseif kind == "hello" and Coop.isHost() then
    if f[4] ~= Coop.VERSION then   -- another co-op version (before 0.2: no field)
      Coop.log("hello from " .. peer .. " with version " .. tostring(f[4]) .. ": refused")
      Net.CoopClose(peer)
      return
    end
    local pick = Coop.assign(peer, f[2])
    -- Without the lobby (late join, tests) the host builds the seat list here.
    local seats = {}
    for item in string.gmatch(cfg.seats or ("0:" .. tostring(Coop.localChar()) .. ":1:" .. Coop.cleanNick(cfg.nick)), "[^;]+") do
      if not string.find(item, "^" .. peer .. ":") then seats[#seats + 1] = item end
    end
    seats[#seats + 1] = peer .. ":" .. tostring(pick) .. ":1:" .. Coop.cleanNick(f[3])
    cfg.seats = table.concat(seats, ";")
    Net.CoopSend(-1, 1, "seats|" .. cfg.seats)
    Coop.log("hello from " .. peer .. " wants " .. tostring(f[2]) .. " -> " .. tostring(pick))
    -- welcome|peer|level|char|x|y|z|yaw : the body's current place lets bots start there.
    local where = ""
    local e = pick and Game.GetEntity(pick)
    if e then
      where = string.format("|%.0f|%.0f|%.0f|%.1f", e.Pos.x, e.Pos.y, e.Pos.z, e.Ang.y)
    end
    Net.CoopSend(peer, 1, "welcome|" .. peer .. "|" .. string.sub(Game.GetLevelPath(), 8) .. "|" .. tostring(pick) .. where)
    Coop.broadcastOwners()
  elseif kind == "claim" and Coop.isHost() then
    local name = f[2]
    -- Bodies the story has taken away (coop_story.lua) cannot be claimed.
    local unav = CoopStory and CoopStory.taken and CoopStory.taken(name)
    -- Only a free body (or its own): "not remote-owned" let a stale claim take the host's
    -- body or its player 2's, and the two ping-ponged (audit 0.2.2 A6). A refused claim gets
    -- the owners back, so the claimer sees it and moves out (Coop.checkRefusedClaim).
    if not unav and (Coop.owners[name] == nil or Coop.owners[name] == peer) then
      for n, p in pairs(Coop.owners) do
        if p == peer then Coop.owners[n] = nil end
      end
      Coop.owners[name] = peer
      Coop.broadcastOwners()
    else
      Coop.log("claim of " .. tostring(name) .. " by peer " .. peer .. " refused")
      Coop.ownersTo(peer)
    end
  elseif kind == "claim2" and Coop.isHost() then
    -- A client's split screen player (coop_split.lua) holds this body now ("" none).
    local name, id = f[2] or "", peer + Coop.P2
    local unav = name ~= "" and CoopStory and CoopStory.taken and CoopStory.taken(name)
    if not unav and (name == "" or Coop.owners[name] == nil or Coop.owners[name] == id) then
      for n, p in pairs(Coop.owners) do
        if p == id then Coop.owners[n] = nil end
      end
      if name ~= "" then Coop.owners[name] = id end
      Coop.broadcastOwners()
    else
      Coop.ownersTo(peer, "claim2 of " .. tostring(name) .. " by peer " .. peer .. " refused")
    end
  elseif kind == "welcome" and Coop.isClient() then
    cfg.myId = tonumber(f[2])
    cfg.char = f[4]
    Coop.log("welcome id=" .. f[2] .. " level=" .. f[3] .. " char=" .. f[4])
    -- (a welcome again during a slow load does not start the same load twice)
    if string.lower("levels/" .. f[3]) ~= Coop.level and Coop.loadingLevel ~= string.lower(f[3]) then
      Coop.log("following host to " .. f[3])
      Coop.rearm()   -- carry myId/char into the next level
      Coop.levelLoading = Net.CoopTime()
      Coop.loadingLevel = string.lower(f[3])
      Game.LoadLevel("Levels/" .. f[3])
    end
  elseif kind == "seats" and Coop.isClient() then
    cfg.seats = f[2]
  elseif kind == "own" then
    if Coop.isClient() then
      Coop.owners = Coop.parseOwn(f[2])
      cfg.owners = f[2]
    end
  end
end

function Coop.onJoin(peer)
  Coop.log("peer " .. peer .. " connected")
  if Coop.isClient() then
    if CoopMenu then CoopMenu.wasFull = nil end   -- (a new connection: its own refusal, if any)
    Net.CoopSend(0, 1, "hello|" .. tostring(cfg.char or cfg.want or "") .. "|" .. Coop.cleanNick(cfg.nick) .. "|" ..
      Coop.VERSION)
  end
end

function Coop.onLeave(peer)
  Coop.log("peer " .. peer .. " left")
  for name, p in pairs(Coop.owners) do
    if Coop.peerOf(p) == peer then   -- (its split screen player 2 too: owner peer + Coop.P2)
      Coop.owners[name] = nil
      local e = Game.GetEntity(name)
      if e then Coop.releasePuppet(e) end
    end
  end
  if Coop.isHost() then
    Coop.broadcastOwners()
    -- A player who left is no longer expected at the next level start (CoopEnemies gate).
    if cfg.seats then
      local seats = {}
      for item in string.gmatch(cfg.seats, "[^;]+") do
        -- (with the player's split screen player 2, peer + Coop.P2)
        if Coop.peerOf(tonumber(string.match(item, "^(%d+):"))) ~= peer then seats[#seats + 1] = item end
      end
      cfg.seats = table.concat(seats, ";")
      Net.CoopSend(-1, 1, "seats|" .. cfg.seats)
      Coop.rearm()
    end
  end
  if CoopSession then CoopSession.onLeave(peer) end
end

-- In the menu level the lobby (coop_menu.lua) owns the session; tests set cfg.auto to
-- host/join and load a level without the menu.
function Coop.menuMode()
  return CoopMenu ~= nil and Coop.level == "levels/menu" and not cfg.auto
end

-- One message: an error in its handler is logged (a few per kind) and the tick goes on;
-- before, one failing handler stopped the whole network tick, state sending included
-- (audit 0.2.2 A13).
Coop.msgErrors = {}
local function handle(peer, kind, data)
  if Coop.menuMode() then
    if kind == "msg" then
      if not CoopMenu.onMessage(peer, split(data)) then Coop.onMessage(peer, data) end
    elseif kind == "join" then CoopMenu.onJoin(peer)
    elseif kind == "leave" then CoopMenu.onLeave(peer) end
  elseif kind == "msg" then Coop.onMessage(peer, data)
  elseif kind == "join" then Coop.onJoin(peer)
  elseif kind == "leave" then Coop.onLeave(peer) end
end

-- A load that never came (a level the game does not find, an error in its loader): the
-- messages are handled again after a while, not dropped for the rest of the level.
Coop.LOAD_WAIT = 20
function Coop.loading()
  if not Coop.levelLoading then return false end
  if Net.CoopTime() - Coop.levelLoading < Coop.LOAD_WAIT then return true end
  Coop.log("level load did not happen: messages handled again")
  Coop.levelLoading = nil
  return false
end

function Coop.pump()
  if Coop.loading() then return end
  for _ = 1, 200 do
    local peer, kind, data = Net.CoopRecv()
    if not peer then return end
    local ok, err = pcall(handle, peer, kind, data)
    if not ok then
      local k = kind == "msg" and (string.match(data or "", "^([^|]*)") or "?") or tostring(kind)
      Coop.msgErrors[k] = (Coop.msgErrors[k] or 0) + 1
      if Coop.msgErrors[k] <= 3 then Coop.log("message " .. k .. " error: " .. tostring(err)) end
    end
    -- A message that started loading a level ends this pump: the rest belongs to the new level
    -- (handled there, by its own scripts and guards).
    if Coop.loading() then return end
  end
end

------------------------------------------------------------------------------
-- Local ownership: keep this machine's body in sync with the session
------------------------------------------------------------------------------

-- Act 1 (Al-Khali): the host is Ross, as in the story (Ross cannot possess anyone until he
-- dies at the end of alk_final); the other players hold squad members. Test sessions that
-- name a character (cfg.auto with cfg.char) keep it.
function Coop.actOne()
  return string.find(Coop.level, "^levels/alk_") ~= nil and Game.GetEntity("Ross") ~= nil
end

-- First-person arms and weapons of a squad member. While Ross leads (Act 1) the game builds
-- only his set (Team.CreateTeam: BuildFP.FP_Chars = {"Ross"}): a player in another body had
-- no view model at all. All six are built at level start, as BuildFP.LoadSet does, in the
-- order the game builds them elsewhere: sounds are cached by file name and later sets load
-- some of theirs only from earlier sets' folders (Rawlings' coger3bb3.wav is in Delgado's
-- and Cole's; loading it from his own folder kills the game), so a character not in the
-- level is built too.
Coop.FP_ORDER = {"Jones", "Delgado", "Cole", "Rawlings", "Church", "Black"}

-- Where a sound a set names may really be: the game loads each file name once per level,
-- from the folder of whichever set or character names it first, and in Act 1 some of
-- those are absent (Delgado's Abanil_Launch.wav is his third-person character's).
Coop.SOUND_DIRS = {"Sounds/FX/"}
for _, n in ipairs({"Ross", "Jones", "Delgado", "Cole", "Rawlings", "Church", "Black"}) do
  table.insert(Coop.SOUND_DIRS, "Sounds/FP/FP_" .. n .. "/")
  table.insert(Coop.SOUND_DIRS, "Sounds/Chars/" .. n .. "/")
end

-- LoadSounds with every ac.AddSoundRes checked first: a file missing from the folder it is
-- asked from kills the game (CheckFailed), so it is taken from a folder that has it, or left out.
function Coop.loadFPSounds(name)
  local real = Act.GetClass("FP_" .. name)
  local getClass, set = Act.GetClass, Game.Set
  local path, missing = "", {}
  -- Game.FileExist looks in the current PathInPackFile folder.
  local proxy = setmetatable({}, {
    __index = function(_, k)
      local v = real[k]
      if type(v) == "function" then return function(_, ...) return v(real, ...) end end
      return v
    end,
    __newindex = function(_, k, v)
      if k ~= "AddSoundRes" or Game.FileExist(v) then real[k] = v return end
      for _, d in ipairs(Coop.SOUND_DIRS) do
        set("PathInPackFile", d)
        if Game.FileExist(v) then
          real.AddSoundRes = v
          set("PathInPackFile", path)
          return
        end
      end
      set("PathInPackFile", path)
      table.insert(missing, v)
    end,
  })
  Act.GetClass = function(n, ...) if n == "FP_" .. name then return proxy end return getClass(n, ...) end
  Game.Set = function(k, v, ...)
    if k == "PathInPackFile" then path = v or "" end
    return set(k, v, ...)
  end
  local ok, err = pcall(_G["FP_" .. name .. "Sound"].LoadSounds, "FP_" .. name)
  Act.GetClass, Game.Set = getClass, set
  if #missing > 0 then Coop.log("first-person set " .. name .. ": no " .. table.concat(missing, ", ")) end
  if not ok then error(err) end
end

function Coop.buildFP(name)
  if Act.GetClass("FP_" .. name) ~= nil then return end
  Game.PreloadLibrary("Scripts/FP/FP_" .. name .. ".lua", "FP_" .. name)
  _G["FP_" .. name].CreateFP()
  Game.PreloadLibrary("Scripts/Sound/FP_" .. name .. "Sound.lua", "FP_" .. name .. "Sound")
  Coop.loadFPSounds(name)
end

function Coop.ensureFP(name)
  if not (name and Coop.SQUAD_SET[name] and Act and Act.GetClass and Game.PreloadLibrary) then return end
  if Act.GetClass("FP_" .. name) ~= nil then return end
  for _, n in ipairs(Coop.FP_ORDER) do
    -- (a character the level does not have: its own script is not loaded, and its set needs
    -- it: alk_bunker_00 left a half-built FP_Church, "attempt to index global 'Church'")
    if _G[n] == nil and n ~= name then
      Coop.log("first-person set " .. n .. ": not in this level")
    else
      local ok, err = pcall(Coop.buildFP, n)
      Coop.log("first-person set " .. n .. ": " .. (ok and "built" or tostring(err)))
    end
    if n == name then return end
  end
end

function Coop.installFP()
  if Coop.fpInstalled or not (Team and Team.SwitchSoldier) then return end
  Coop.fpInstalled = true
  if Coop.actOne() then Coop.ensureFP(Coop.FP_ORDER[#Coop.FP_ORDER]) end
  local orig = Team.SwitchSoldier
  Team.SwitchSoldier = function(from, to, ...)
    Coop.ensureFP(to)
    return orig(from, to, ...)
  end
end

-- A body this player may take at level start: in the level and not held by someone else.
function Coop.freeFor(name)
  local owner = name and Coop.owners[name]
  local e = name and Game.GetEntity(name)
  return e ~= nil and e.bActive ~= false and (owner == nil or owner == Coop.myId()) and
         not (CoopStory and CoopStory.taken and CoopStory.taken(name))
end

-- A level may keep the squad switched off at its start (sum_ziggurat_meat: the arrival by
-- teleport, ~12 s). The start switch waits up to START_WAIT ticks for the body this player
-- held instead of giving it up at once (the client then flew as a spirit for good).
Coop.START_WAIT = 600
function Coop.startBodyLater()
  local name = cfg.char
  local e = name and name ~= "Ross" and Game.GetEntity(name)
  local owner = name and Coop.owners[name]
  return e and e.bActive == false and (owner == nil or owner == Coop.myId()) and Coop.frame < Coop.START_WAIT or false
end

-- The body to move into when a level starts: the last one held, else the lobby seat, else
-- the first free squad member (a story split may have taken the body away).
function Coop.startChar()
  if Coop.isHost() and Coop.actOne() and not (cfg.auto and cfg.char) then return "Ross" end
  -- A story line alone (coop_storysolo.lua): its character, even where the level starts with
  -- that body put away (Alk_City: Alpha is hidden until Omega reaches it).
  if cfg.storyline and cfg.char then
    local e = Game.GetEntity(cfg.char)
    if e then
      if e.bActive == false then e.bActive = true end
      return cfg.char
    end
  end
  for _, name in ipairs({cfg.char, cfg.seatChar}) do
    if name ~= "Ross" and Coop.freeFor(name) then return name end
  end
  for _, name in ipairs(CoopMenu and CoopMenu.CHAR_ORDER or Coop.SQUAD) do
    if Coop.freeFor(name) then return name end
  end
end

-- A player left without a body: a first-person scene skipped in its first moments (the host
-- skips the opening of the desert at once in tests; a fast unanimous skip can too) ended on a
-- client now and then (1 run in 15 before 0.2.1, a few more since the client keeps its own
-- scene chains) with the characters the scene hid (Scene.HideChars: Active 0, TimeSpeed 0)
-- never shown again, the player's body among them. Once no scene or scene camera is up for
-- 2 s: the game's own Scene.UnhideChars, and the body taken back as the game's switch does.
Coop.NOBODY_WAIT = 2
function Coop.reclaimBody()
  if Coop.level == "levels/menu" or Game.UsrEntity(0) ~= nil then Coop.noBodySince = nil return end
  if (Scene and Scene.IsPlaying) or Game.GetEntity("InterpolusCamera") or Game.GetEntity("Cameraman") then
    Coop.noBodySince = nil
    return
  end
  local now = Net.CoopTime()
  Coop.noBodySince = Coop.noBodySince or now
  if now - Coop.noBodySince < Coop.NOBODY_WAIT then return end
  Coop.noBodySince = nil
  if Scene and Scene.UnhideChars and Scene.HidenChars and next(Scene.HidenChars) then
    pcall(Scene.UnhideChars)
    Scene.HidenChars = {}
    Coop.log("no body after a scene: the scene's hidden characters shown again")
  end
  local name = cfg.char
  if not name or (Coop.owners[name] ~= nil and not Coop.isMine(Coop.owners[name])) then
    for n, p in pairs(Coop.owners) do
      if p == Coop.myId() then name = n break end
    end
  end
  local t = name and Game.GetEntity(name)
  if not t or (t.Life or 0) <= 0 or t.UsrControl == 1 then return end
  if t.Active == 0 then t.Active = 1 end
  if t.TimeSpeed == 0 then t.TimeSpeed = 1 end
  t.UsrControl = 0
  t.InCtrl_UseFPS = 1
  t.InCtrl_ResetSlot = 1
  if t.oAI then t.oAI.bEnable = false end
  pcall(t.ResetControl, t)
  local cam = Game.GetEntity("MainCam")
  if cam then
    Game.SetCam(0, "MainCam")
    cam.MainTarget, cam.Target = name, name
  end
  if Input.GetActionSet() ~= "Walk" then Input.SetActionSet("Walk") end
  if Team and Team.ResetUsrAnim then pcall(Team.ResetUsrAnim, t) end
  Coop.log("no body after a scene: " .. name .. " taken back")
end

function Coop.updateLocalOwnership()
  local mine = Coop.localChar()
  if not mine then return end
  -- Test option: this player holds no body (a 4th player in a 3-body level), so it becomes
  -- a spirit (coop_spirit.lua).
  if cfg.nobody then
    for n, p in pairs(Coop.owners) do
      if p == Coop.myId() then Coop.owners[n] = nil end
    end
    return
  end
  -- At level start (and after a welcome) move once to the character picked in the lobby;
  -- after that the player switches freely (cfg.char follows the body they hold).
  if not Coop.switchedTo and (Coop.isHost() or cfg.myId) then
    local want = Coop.startChar()
    if want ~= cfg.char and Coop.startBodyLater() then return end
    Coop.switchedTo = want or mine
    if want and mine ~= want then
      -- A tutorial lock on the seat's character must not keep its player out of it.
      local locks = Team and Team.UnavaliablePlayers
      local was = locks and locks[want]
      if locks then locks[want] = nil end
      local ok = Team and Team.SwitchSoldier and Team.SwitchSoldier(mine, want)
      if locks then locks[want] = was end
      Coop.log("switch " .. mine .. " -> " .. want .. " " .. tostring(ok))
      if ok then return end
    end
  end
  if Coop.isHost() then
    if Coop.owners[mine] ~= 0 then
      for n, p in pairs(Coop.owners) do
        if p == 0 then Coop.owners[n] = nil end
      end
      Coop.owners[mine] = 0
      cfg.char = mine
      Coop.broadcastOwners()
    end
  elseif Coop.isClient() and cfg.myId then
    if Coop.owners[mine] ~= cfg.myId and Coop.lastClaim ~= mine then
      Coop.lastClaim = mine
      Coop.lastClaimT = Net.CoopTime()
      cfg.char = mine
      Net.CoopSend(0, 1, "claim|" .. mine)
    end
    Coop.checkRefusedClaim(mine)
  end
end

-- Client: the body this player drives belongs to another player (two switched into the same
-- free body at once; the host gave it to the other): move to the body the owners give this
-- player, else to a free one. It drove on as a second driver before (audit 0.2.2 A6).
Coop.CLAIM_WAIT = 1.5   -- (was 3: the host answers a refused claim at once; the player sat in a body that was not theirs that long)
function Coop.checkRefusedClaim(mine)
  local owner = Coop.owners[mine]
  if owner == nil or owner == cfg.myId or Coop.storyDriven[mine] then return end
  -- (only a claim of its own that the host refused: a spirit or a player who never claimed
  -- this body is left to coop_spirit.lua)
  if Coop.lastClaim ~= mine or Net.CoopTime() - (Coop.lastClaimT or 0) < Coop.CLAIM_WAIT then return end
  if Scene and Scene.IsPlaying then return end
  if CoopSpirit and CoopSpirit.active then return end
  -- (once a second: with no free body this would look up the squad every tick)
  local now = Net.CoopTime()
  if now < (Coop.refusedNextT or 0) then return end
  Coop.refusedNextT = now + 1
  local target
  for n, p in pairs(Coop.owners) do
    if p == cfg.myId then target = n end
  end
  if not target then
    for _, n in ipairs(Coop.SQUAD) do
      local e = Coop.squadEnt(n)
      if Coop.owners[n] == nil and e and (e.Life or 0) > 0 and e.bActive ~= false and
         not (CoopStory and CoopStory.taken and CoopStory.taken(n)) then
        target = n
        break
      end
    end
  end
  if (Coop.refusedLogT or 0) + 5 < Net.CoopTime() then
    Coop.refusedLogT = Net.CoopTime()
    Coop.log("claim: " .. mine .. " is held by owner " .. tostring(owner) .. ", moving to " .. tostring(target))
  end
  if target and Team and Team.SwitchSoldier then
    local locks = Team.UnavaliablePlayers
    local was = locks and locks[target]
    if locks then locks[target] = nil end
    pcall(Team.SwitchSoldier, mine, target)
    if locks then locks[target] = was end
  end
end

------------------------------------------------------------------------------
-- Tick
------------------------------------------------------------------------------

-- The engine calls the OnRenderDebug function every rendered frame, whatever the game
-- time speed (the scheduler follows game time and nearly stops when a scene slows time
-- down). Puppets are driven every frame; network work runs at TICK in real time.
Coop.FRAME_HOOK = "Coop.onFrame"

function Coop.onFrame()
  local now = Net.CoopTime()
  if not Coop.lastFrame then Coop.log("first frame hook") end
  local dt = now - (Coop.lastFrame or now)
  Coop.lastFrame = now
  local ok, err = pcall(Coop.frameUpdate, now, dt)
  if not ok then
    Coop.errors = (Coop.errors or 0) + 1
    if Coop.errors <= 10 then Coop.log("frame error: " .. tostring(err)) end
  end
end

function Coop.inSession()
  return cfg.role == "host" or cfg.role == "client"
end

function Coop.frameUpdate(now, dt)
  if Coop.devFrame then pcall(Coop.devFrame, dt) end
  if CoopStorySolo then
    local ok, err = pcall(CoopStorySolo.update)
    if not ok and (Coop.storyErrors or 0) < 5 then
      Coop.storyErrors = (Coop.storyErrors or 0) + 1
      Coop.log("story solo error: " .. tostring(err))
    end
  end
  if CoopSplit and CoopSplit.on then
    local ok, err = pcall(CoopSplit.frame)
    if not ok and (Coop.splitErrors or 0) < 5 then
      Coop.splitErrors = (Coop.splitErrors or 0) + 1
      Coop.log("split error: " .. tostring(err))
    end
  end
  -- Ross's stand-in (act 1) per frame, as the puppets: at 20 Hz it moved in steps (audit
  -- 0.2.2 A10). (In split screen coop_split.lua runs it per view, unless the screen is whole
  -- for a scene.)
  if CoopRoss and not (CoopSplit and CoopSplit.on and CoopSplit.shownFor ~= nil) and Coop.level ~= "levels/menu" then
    local ok, err = pcall(CoopRoss.update)
    if not ok and (Coop.rossErrors or 0) < 5 then
      Coop.rossErrors = (Coop.rossErrors or 0) + 1
      Coop.log("ross error: " .. tostring(err))
    end
  end
  if Coop.inSession() then
    -- Messages are taken every frame once the level's first ticks have run: the states of other bodies were
    -- handled only at the 20 Hz tick, so they reached the interpolation up to a tick late and in bursts.
    if cfg.fastpump ~= false and Coop.frame >= 40 and Coop.level ~= "levels/menu" then Coop.pump() end
    Coop.drivePuppets(dt)
    if cfg.bodypush ~= false then
      local okb, errb = pcall(Coop.bodyPush, dt)
      if not okb and (Coop.pushErrors or 0) < 5 then
        Coop.pushErrors = (Coop.pushErrors or 0) + 1
        Coop.log("bodypush error: " .. tostring(errb))
      end
    end
    if cfg.mxsrc and Coop.isHost() then pcall(Coop.mxSource, now) end
    if CoopWorld and CoopWorld.frame then pcall(CoopWorld.frame, now) end
    if CoopPowers then
      local okp, errp = pcall(CoopPowers.frame, now)
      if not okp and (Coop.powerErrors or 0) < 5 then
        Coop.powerErrors = (Coop.powerErrors or 0) + 1
        Coop.log("powers error: " .. tostring(errp))
      end
    end
    local ok, err = pcall(Coop.puppetLights)
    if not ok and (Coop.lightErrors or 0) < 5 then
      Coop.lightErrors = (Coop.lightErrors or 0) + 1
      Coop.log("puppet light error: " .. tostring(err))
    end
  end
  if CoopHud and Coop.inSession() then
    local ok, err = pcall(CoopHud.update)
    if not ok and (Coop.hudErrors or 0) < 5 then
      Coop.hudErrors = (Coop.hudErrors or 0) + 1
      Coop.log("hud error: " .. tostring(err))
    end
  end
  if CoopEnemies and CoopEnemies.installed and Coop.isClient() then
    pcall(Coop.mxEnemyPre)
    CoopEnemies.driveEnemies(dt)
    pcall(Coop.mxEnemies, now)
  end
  if CoopSpirit and CoopSpirit.active then pcall(CoopSpirit.frame, dt) end
  if CoopSpectate and CoopSpectate.active then pcall(CoopSpectate.frame, dt) end
  if CoopEnemies and CoopEnemies.installed and Scene then CoopEnemies.updateSceneLabel() end
  if CoopScenes and Coop.inSession() then
    CoopScenes.install()
    CoopScenes.installQTE()
    local ok, err = pcall(CoopScenes.update, dt)
    if not ok and (Coop.sceneErrors or 0) < 5 then
      Coop.sceneErrors = (Coop.sceneErrors or 0) + 1
      Coop.log("scene POV error: " .. tostring(err))
    end
  end
  if now >= (Coop.nextTick or 0) then
    -- Step from the previous tick, not from now: at 30 fps "now + TICK" ticked every other
    -- frame (15 Hz, logs 0.2.1). After a long frame (loading) the schedule restarts from now.
    -- (fork MAK-PIVO/jericho-coop)
    Coop.nextTick = math.max((Coop.nextTick or now) + Coop.TICK, now - Coop.TICK)
    Coop.rearm()
    Coop.update()
  end
end

-- Control lock watchdog (fork MAK-PIVO/jericho-coop, from the earlier JerichoCoop mod). Stock
-- story scripts lock the player (IgnoreUsrControl = 1) and unlock later, often from a scheduled
-- map callback; on a client those callbacks are the host's, and a script line that errors there
-- (it reads something only the host has) never reaches its unlock: the player was left without
-- control. A lock nobody in this mod holds is released after 12 s, on clients only (the host's
-- story releases its own locks: a 12 s release cut a Brandenburg cinematic short).
Coop.LOCK_LIMIT = 12

function Coop.modHoldsControl()
  if not Coop.isClient() then return true end
  local me = Coop.localChar() or ""
  if Coop.storyDriven and Coop.storyDriven[me] then return true end
  if Scene and Scene.IsPlaying then return true end
  if CoopEnemies and CoopEnemies.curtain then return true end
  if CoopSpirit and CoopSpirit.active then return true end
  -- Menus, astral projections, a squad switch's travel: not the "Walk" set.
  if Input and Input.GetActionSet and Input.GetActionSet() ~= "Walk" then return true end
  -- Split screen: player 1 driven from their pad during player 2's astral projection.
  if CoopSplit and CoopSplit.drives and next(CoopSplit.drives) then return true end
  if cfg.storyline then return true end
  local sp = CoopSplits
  if sp and sp.G6 and sp.G6.holding then return true end
  if sp and sp.G15 and sp.G15.struggle and not (sp.G15.freed or {})[me] then return true end
  local ok, grab = pcall(function() return QTE and QTE.InGame and QTE.InGame.Blocked end)
  if ok and grab then return true end
  return cfg.bot ~= nil
end

function Coop.controlWatchdog()
  local usr = Game.UsrEntity(0)
  if not usr or usr.IgnoreUsrControl ~= 1 or Coop.modHoldsControl() then
    Coop.lockSince = nil
    return
  end
  local now = Net.CoopTime()
  Coop.lockSince = Coop.lockSince or now
  if now - Coop.lockSince > Coop.LOCK_LIMIT then
    usr.IgnoreUsrControl = 0
    Coop.lockSince = nil
    Coop.log("control lock on " .. tostring(usr.Name) .. " released after " .. Coop.LOCK_LIMIT .. " s")
  end
end

-- F11: the last 30 seconds saved as a video for a bug report (native/clip.c).
Coop.CLIP_KEY = 0x7A
function Coop.clipKey()
  if not Net.CoopClip then return end
  local down = Net.CoopKey(Coop.CLIP_KEY) == 1
  if down and not Coop.clipHeld then
    local path = Net.CoopClip("save")
    Coop.log("clip: F11 -> " .. tostring(path))
    if path and path ~= "" then
      local name = string.match(path, "[^\\]+$") or path
      pcall(Scorer.SetMsgText, Coop.text("clip") .. "Coop\\" .. name, Game.GetTime() + 5)
    end
  end
  Coop.clipHeld = down
end

-- Aspect ratio. The game's option has only 4:3, 16:9 and 16:10, and the player profile
-- (Profile.CBJericho) puts its stored value back at the main menu over game.cfg, so an
-- ultrawide screen was always stretched (owner, 0.2.1). The option now offers Auto (the
-- screen's own ratio, the default) and the common ratios; the choice is kept in the mod's
-- own file (Coop\display.txt) and put back every second over whatever the profile loaded.
Coop.WIDE_ASPECT = 1.85
Coop.ASPECTS = {
  {0, "Auto"}, {4 / 3, "4:3"}, {5 / 4, "5:4"}, {16 / 10, "16:10"}, {16 / 9, "16:9"},
  {64 / 27, "21:9 (2560x1080)"}, {43 / 18, "21:9 (3440x1440)"}, {32 / 9, "32:9"},
}
Coop.DISPLAY_FILE = "coop:display.txt"

function Coop.aspectChoice()
  if Coop.aspectSel == nil then
    Coop.aspectSel = 1
    local text = Net.CoopFile and Net.CoopFile(Coop.DISPLAY_FILE, "r")
    local v = text and string.match(text, "aspect\t([%d%.]+)")
    v = tonumber(v)
    if v then
      for i, a in ipairs(Coop.ASPECTS) do
        if math.abs(a[1] - v) < 0.001 then Coop.aspectSel = i end
      end
    end
  end
  return Coop.aspectSel
end

function Coop.screenRatio()
  -- A borderless window shows the picture stretched over its whole monitor: the monitor's
  -- ratio, whatever the resolution (coop_display, Net.CoopDisplay).
  if Net.CoopDisplay then
    local ok, mw, mh, on = pcall(Net.CoopDisplay, "monitor")
    if ok and on == 1 and mw and mh and mh > 0 then return mw / mh, mw, mh end
  end
  local w, h = tonumber(Game.Get("VideoWidth")), tonumber(Game.Get("VideoHeight"))
  if w and h and h > 0 then return w / h, w, h end
end

-- The ratio the game should use now.
function Coop.wantedAspect()
  local a = Coop.ASPECTS[Coop.aspectChoice()]
  if a[1] > 0 then return a[1] end
  return (Coop.screenRatio())
end

-- Frame cap (owner, 0.2.6): the game draws as fast as it can when its own cap (R_LimitFPS, 0 by
-- default) and vertical sync are off; the mod caps it at the screen's refresh rate, twice that in
-- split screen (each view is drawn every other frame), so every view keeps up with the screen.
-- A cap of the player's own or vertical sync: none of the mod's. Once a second.
function Coop.frameCap()
  if Coop.frame % 30 ~= 2 or not Net.CoopDisplay then return end
  local own = tonumber(Game.Get("R_LimitFPS")) or 0
  local vsync = tonumber(Game.Get("VSync")) or 0
  local cap = 0
  if own <= 0 and vsync == 0 and cfg.framecap ~= false then
    local _, _, _, hz = Net.CoopDisplay("monitor")
    hz = tonumber(hz) or 0
    if hz < 30 then hz = 60 end
    cap = hz * ((CoopSplit and CoopSplit.on and not CoopSplit.held) and 2 or 1)
  end
  if cap ~= Coop.capSet then
    Coop.capSet = cap
    Net.CoopDisplay("cap", cap)
  end
end

function Coop.autoAspect()
  if cfg.aspect == false or Coop.frame % 30 ~= 1 then return end
  Coop.installAspectMenu()
  Coop.installDisplayMenu()
  local r = Coop.wantedAspect()
  if not r then return end
  local cur = tonumber(Game.Get("PhysicalAspectRatio")) or 0
  if math.abs(cur - r) > 0.005 then
    Game.Set("PhysicalAspectRatio", r)
    if not Coop.aspectLogged then
      Coop.aspectLogged = true
      local _, w, h = Coop.screenRatio()
      Coop.log(string.format("aspect: %sx%s, %s, PhysicalAspectRatio %.4f -> %.4f", tostring(w), tostring(h),
        Coop.ASPECTS[Coop.aspectChoice()][2], cur, r))
    end
  end
end

function Coop.aspectLabel()
  local a = Coop.ASPECTS[Coop.aspectChoice()]
  if a[1] > 0 then return a[2] end
  local r = Coop.screenRatio()
  local name = Coop.text("auto")
  return r and string.format("%s (%.2f:1)", name, r) or name
end

-- The game's options screen (scripts/menu/menu.lua): its aspect ratio entry steps through
-- Coop.ASPECTS instead of its three ratios.
function Coop.installAspectMenu()
  if not Menu or not Menu.Switch_Aspect_Ratio or Menu.Switch_Aspect_Ratio == Coop.aspectSwitch then return end
  local function step(id, control, d)
    local n = #Coop.ASPECTS
    Coop.aspectSel = (Coop.aspectChoice() - 1 + d) % n + 1
    if Net.CoopFile then Net.CoopFile(Coop.DISPLAY_FILE, "w", "aspect\t" .. string.format("%.6f", Coop.ASPECTS[Coop.aspectSel][1])) end
    local r = Coop.wantedAspect()
    if r then Game.Set("PhysicalAspectRatio", r) end
    local itm = id and control and Scorer.GetItem(id, control)
    if itm then itm.Text = Menu.Get_Aspect_Ratio_Status() end
  end
  Coop.aspectSwitch = function(id, control) step(id, control, 1) end
  Menu.Switch_Aspect_Ratio = Coop.aspectSwitch
  Menu.Switch_Aspect_Ratio_Down = function(id, control) step(id, control, -1) end
  Menu.Get_Aspect_Ratio_Status = function()
    return Game.GetLangStr("Menu_Aspect_Ratio") .. ": " .. Coop.aspectLabel()
  end
end

-- Display mode and refresh rate (0.2.4, owner): the game has neither in its options (full
-- screen only through game.cfg's FullScreen). Two rows in its Video screen after the
-- resolution: the display mode (full screen, a window, or a borderless window over the whole
-- monitor: FullScreen 0 plus the DLL's borderless window) and the refresh rate (Auto or one
-- the monitor has; full screen only). The DLL keeps them (Net.CoopDisplay, coop:video.txt)
-- and puts the refresh rate into the device; they apply when the Video screen is left, the
-- display mode at the next start.
Coop.MODES = {"full", "window", "borderless"}
-- SMOD sets FullScreen in its autoexec.lua on every start: there the player's SMOD setting
-- decides full screen; the window can still go borderless.
function Coop.displayModes()
  if CoopSmod and CoopSmod.present and CoopSmod.present() then
    if (tonumber(Game.Get("FullScreen")) or 1) ~= 0 then return {1} end
    return {2, 3}
  end
  return {1, 2, 3}
end

function Coop.displayState()
  if not Coop.disp then
    local ok, hz, bl = pcall(Net.CoopDisplay, "get")
    if not ok then hz, bl = 0, 0 end
    local fs = tonumber(Game.Get("FullScreen")) or 1
    Coop.disp = {hz = tonumber(hz) or 0, mode = fs ~= 0 and 1 or ((tonumber(bl) or 0) ~= 0 and 3 or 2)}
    Coop.dispSaved = {hz = Coop.disp.hz, mode = Coop.disp.mode}
  end
  return Coop.disp
end

function Coop.displayRates()
  local t = {0}
  local ok, s = pcall(Net.CoopDisplay, "rates")
  -- (TV modes of 24-30 Hz left out)
  for r in string.gmatch(ok and s or "", "%d+") do
    if tonumber(r) >= 48 then t[#t + 1] = tonumber(r) end
  end
  return t
end

function Coop.displayModeLabel()
  return Coop.text("mode") .. ": " .. Coop.text(Coop.MODES[Coop.displayState().mode])
end

function Coop.displayHzLabel()
  local d = Coop.displayState()
  local v = d.hz > 0 and (d.hz .. " " .. Coop.text("hzunit")) or Coop.text("auto")
  if d.mode ~= 1 then v = v .. " " .. Coop.text("fullonly") end
  return Coop.text("hz") .. ": " .. v
end

local function setRow(id, name, text)
  local it = Scorer.GetItem(id or 0, name)
  if it then it.Text = text end
end

function Coop.displayMode(id, control, dir)
  local d = Coop.displayState()
  local list, at = Coop.displayModes(), 1
  for i, m in ipairs(list) do if m == d.mode then at = i end end
  d.mode = list[(at - 1 + (dir or 1)) % #list + 1]
  setRow(id, "Itm4", Coop.displayModeLabel())
  setRow(id, "Itm5", Coop.displayHzLabel())
end
function Coop.displayModeNext(id, control) Coop.displayMode(id, control, 1) end
function Coop.displayModePrev(id, control) Coop.displayMode(id, control, -1) end

function Coop.displayHz(id, control, dir)
  local d = Coop.displayState()
  local rates, at = Coop.displayRates(), 1
  for i, r in ipairs(rates) do if r == d.hz then at = i end end
  d.hz = rates[(at - 1 + (dir or 1)) % #rates + 1]
  setRow(id, "Itm5", Coop.displayHzLabel())
end
function Coop.displayHzNext(id, control) Coop.displayHz(id, control, 1) end
function Coop.displayHzPrev(id, control) Coop.displayHz(id, control, -1) end

-- Leaving the Video screen: keep what changed. A new refresh rate in full screen applies at
-- once (the game's own mode change resets the device); the display mode at the next start.
function Coop.applyDisplay()
  local d, s = Coop.disp, Coop.dispSaved
  if not d or (d.hz == s.hz and d.mode == s.mode) then return end
  pcall(Net.CoopDisplay, "set", d.hz, d.mode == 3 and 1 or 0)
  if d.mode ~= s.mode then
    Game.Set("FullScreen", d.mode == 1 and 1 or 0)
    Coop.restartNotice = true
  elseif d.mode == 1 then
    pcall(Game.SetVideoCurrentMode, Game.GetVideoCurrentMode())
  end
  Coop.log(string.format("display: mode %s, %d Hz", Coop.MODES[d.mode], d.hz))
  Coop.dispSaved = {hz = d.hz, mode = d.mode}
end

-- The rows go in through the screen's VerticalMenu call; its layout code (written for five
-- rows: Advanced and Back side by side at the bottom) is then redone for seven.
function Coop.layoutVideo()
  local function it(n) return Scorer.GetItem(0, "Itm" .. n) end
  local i2, i3, i4, i5, i6, i7 = it(2), it(3), it(4), it(5), it(6), it(7)
  if not (i2 and i3 and i4 and i5 and i6 and i7) then return end
  local step = i3.Y - i2.Y
  for k, row in ipairs({i4, i5}) do
    row.Y = i3.Y + k * step
    row.X = 100
    row.Left, row.Right = "", ""
  end
  i4.onLeft, i4.onRight = "Coop.displayModePrev", "Coop.displayModeNext"
  i5.onLeft, i5.onRight = "Coop.displayHzPrev", "Coop.displayHzNext"
  i3.Down, i4.Up, i4.Down, i5.Up = "Itm4", "Itm3", "Itm5", "Itm4"
  local y = math.max(380, i5.Y + step)
  i6.Y, i6.X, i7.Y, i7.X = y, 60, y, 440
  Menu.LinkLR(i6, i7)
  Menu.LinkLR(i7, i6)
  i5.Down, i6.Up, i7.Up = "Itm6", "Itm5", "Itm5"
end

function Coop.installDisplayMenu()
  if not Menu or not Menu.VideoMenu or Menu.VideoMenu == Coop.videoMenu or not Net.CoopDisplay then return end
  if Game.Get("Platform") ~= "PC" then return end
  local orig = Menu.VideoMenu
  Coop.videoMenu = function(id, control, ...)
    Coop.displayState()
    local vm = Menu.VerticalMenu
    Menu.VerticalMenu = function(title, options, ...)
      Menu.VerticalMenu = vm
      if type(options) == "table" and #options == 5 then
        table.insert(options, 4, {Coop.displayModeLabel(), "Coop.displayModeNext"})
        table.insert(options, 5, {Coop.displayHzLabel(), "Coop.displayHzNext"})
        Coop.videoRows = true
      end
      return vm(title, options, ...)
    end
    Coop.videoRows = false
    local ok, err = pcall(orig, id, control, ...)
    Menu.VerticalMenu = vm
    if not ok then Coop.log("video menu error: " .. tostring(err)) return end
    if Coop.videoRows then
      local okl, errl = pcall(Coop.layoutVideo)
      if not okl then Coop.log("video menu layout error: " .. tostring(errl)) end
    end
  end
  Menu.VideoMenu = Coop.videoMenu
  -- As the game's own resolution: applied by Accept on the Configuration screen (SaveConfig2,
  -- also after its resolution question), dropped by Cancel. A new display mode is told in the
  -- game's message box once back in the menu (hints are not drawn in menus; the menu is built
  -- twice after Accept, the second time by the config save's callback).
  local save, cancel, main = Menu.SaveConfig2, Menu.CancelConfig, Menu.MainMenu
  if save then
    Menu.SaveConfig2 = function(...)
      local ok, err = pcall(Coop.applyDisplay)
      if not ok then Coop.log("display apply error: " .. tostring(err)) end
      return save(...)
    end
  end
  if cancel then
    Menu.CancelConfig = function(...)
      local s = Coop.dispSaved
      if s then Coop.disp = {hz = s.hz, mode = s.mode} end
      return cancel(...)
    end
  end
  if main and Menu.AcceptMenuMultiline then
    Menu.MainMenu = function(...)
      if Coop.restartNotice then Coop.restartNoticeAt = Net.CoopTime() + 0.5 end
      return main(...)
    end
  end
end

-- Who holds this player's body, logged on every change (owner's Steam test, 0.2.1: the client's
-- character "became uncontrollable" now and then, by scripts or AI, with nothing in the log):
-- input locked, its AI on, the action set, the camera, a scene, a story walk.
Coop.CONTROL_LOG_MAX = 300
function Coop.watchControl()
  if Coop.level == "levels/menu" or Coop.frame % 5 ~= 0 then return end
  local u = Game.UsrEntity(0)
  local key
  if not u then
    key = "no body"
  else
    local okSet, set = pcall(Input.GetActionSet)
    local scene = Scene and Scene.IsPlaying and tostring(Scene.SceneName or "?") or "-"
    key = string.format("%s lock=%s ai=%s set=%s cam=%s scene=%s story=%s", u.Name, tostring(u.IgnoreUsrControl),
      tostring(u.oAI and u.oAI.bEnable), tostring(okSet and set), tostring(Game.GetCam(0)), scene,
      tostring(Coop.storyDriven and Coop.storyDriven[u.Name] or false))
  end
  if key ~= Coop.controlKey then
    Coop.controlKey = key
    Coop.controlLogs = (Coop.controlLogs or 0) + 1
    if Coop.controlLogs <= Coop.CONTROL_LOG_MAX then Coop.log("control: " .. key) end
  end
  if u then Coop.checkOwnModel(u) end
end

-- The player's own model is not drawn in first person (the engine hides it, the arms are
-- the FP set). After a downed player was moved into another body on a client the model
-- stayed drawn: the view sat behind its own head, no arms (0.2.2 test, alk_bunker_01). Not
-- in split screen (coop_split.lua shows each body in the other player's view) nor in a
-- scene or a power's own camera.
function Coop.checkOwnModel(u)
  local hid = Coop.ownModelHidden
  if hid and hid ~= u.Name then
    local e = Game.GetEntity(hid)
    if e and e.bObjectVisible == false then e.bObjectVisible = true end
    Coop.ownModelHidden = nil
  end
  local fpView = Game.GetCam(0) == "MainCam" and u.InCtrl_UseFPS == 1 and (u.Life or 0) > 0
  -- Out of the first-person view (astral projection, SMOD's third person, death): the body it
  -- hid is shown again (it stayed invisible there, review 0.2.2). Scenes show and hide it
  -- themselves.
  if Coop.ownModelHidden == u.Name and not fpView and not (Scene and Scene.IsPlaying) then
    if u.bObjectVisible == false then u.bObjectVisible = true end
    Coop.ownModelHidden = nil
    Coop.log("own model of " .. u.Name .. " shown again (out of first person)")
  end
  if cfg.fpbodyfix == false or (CoopSplit and CoopSplit.on) or (Scene and Scene.IsPlaying) then return end
  if not fpView then return end
  local fp = u.FPSEntity and u.FPSEntity ~= "" and Game.GetEntity(u.FPSEntity)
  if not fp or u.bObjectVisible ~= true then
    Coop.ownModelSeen = nil
    return
  end
  -- (twice in a row: a switch shows the body for a moment on its own)
  if Coop.ownModelSeen ~= u.Name then
    Coop.ownModelSeen = u.Name
    return
  end
  u.bObjectVisible = false
  Coop.ownModelHidden = u.Name
  if fp.bObjectVisible == false then fp.bObjectVisible = true end
  Coop.ownModelSeen = nil
  Coop.ownModelFixes = (Coop.ownModelFixes or 0) + 1
  if Coop.ownModelFixes <= 10 then Coop.log("own model of " .. u.Name .. " drawn in first person: hidden") end
end

function Coop.displayNotice()
  if not Coop.restartNoticeAt or Net.CoopTime() < Coop.restartNoticeAt then return end
  -- (only over a menu: else at the next one)
  if not (Menu and (Menu.isStartUpMenu or Game.Get("InGameMenu") == 1)) then return end
  Coop.restartNotice, Coop.restartNoticeAt = nil, nil
  local ok, err = pcall(Menu.AcceptMenuMultiline, Coop.text("restart"), "Menu.MainMenu")
  if not ok then Coop.log("display notice error: " .. tostring(err)) end
end

function Coop.update()
  Coop.frame = Coop.frame + 1
  pcall(Coop.clipKey)
  pcall(Coop.autoAspect)
  pcall(Coop.frameCap)
  pcall(Coop.displayNotice)
  pcall(Coop.watchControl)
  if CoopSmod and CoopSmod.update then CoopSmod.update() end
  if CoopAddon and CoopAddon.update then CoopAddon.update() end
  if Coop.inSession() then
    local ok, err = pcall(Coop.reclaimBody)
    if not ok and (Coop.reclaimErrors or 0) < 3 then
      Coop.reclaimErrors = (Coop.reclaimErrors or 0) + 1
      Coop.log("reclaim error: " .. tostring(err))
    end
  end
  if CoopSplit and not CoopSplit.on and Coop.frame >= 10 then
    local ok, err = pcall(CoopSplit.autoStart)
    if not ok then Coop.log("split start error: " .. tostring(err)) end
  end
  -- SMOD (autoexec.lua, re-run every level) slows the whole world while the squad menu is
  -- open: in a session that would slow one machine only.
  -- Lobby option: QTEs pass by themselves on every machine (the game's own QTEMode 2; its
  -- bonus codes set QTEMode again on every level load).
  if cfg.qte == "auto" and Coop.inSession() and Coop.level ~= "levels/menu" and Game.Get("QTEMode") ~= 2 then
    Game.Set("QTEMode", 2)
  end
  if _G.TEAMMENUSLOWMO and Coop.inSession() then
    _G.TEAMMENUSLOWMO = false
    Coop.log("SMOD: squad menu slow motion off for the session")
  end
  -- Keep running while unfocused for the length of a session (a paused host would
  -- freeze everyone); outside a session the game behaves as in single player.
  -- Test runs (dev) keep running unfocused in the menu too.
  local bg = (Coop.inSession() or cfg.dev) and 1 or 0
  if bg ~= Coop.bgState and Net.CoopBackground then
    Net.CoopBackground(bg)
    Coop.bgState = bg
  end
  Coop.wrapTeam()
  -- The guards first: a client's first tick in a level handles what arrived while it loaded
  -- (replayed callbacks, spawned enemies), which must meet them (audit 0.2.2 A4).
  if CoopEnemies and (Coop.isHost() or Coop.isClient()) then
    CoopEnemies.install()
    if CoopEnemies.installed and CoopWorld then CoopWorld.install() end
  end
  Coop.pump()
  if CoopEnemies and (Coop.isHost() or Coop.isClient()) then
    if CoopEnemies.installed then
      CoopEnemies.update()
      if CoopWorld then
        CoopWorld.install()
        local ok, err = pcall(CoopWorld.update)
        if not ok and (Coop.worldErrors or 0) < 5 then
          Coop.worldErrors = (Coop.worldErrors or 0) + 1
          Coop.log("world error: " .. tostring(err))
        end
      end
    end
  end
  if CoopTeam and Coop.inSession() and Coop.level ~= "levels/menu" then CoopTeam.update() end
  if CoopSquad then
    local okq, errq = pcall(CoopSquad.update)
    if not okq and (Coop.squadErrors or 0) < 3 then
      Coop.squadErrors = (Coop.squadErrors or 0) + 1
      Coop.log("squad error: " .. tostring(errq))
    end
  end
  if CoopSouls then
    local oks, errs = pcall(CoopSouls.update)
    if not oks and (Coop.soulsErrors or 0) < 3 then
      Coop.soulsErrors = (Coop.soulsErrors or 0) + 1
      Coop.log("souls error: " .. tostring(errs))
    end
  end
  if CoopClaim then
    local ok, err = pcall(CoopClaim.update)
    if not ok and (Coop.claimErrors or 0) < 5 then
      Coop.claimErrors = (Coop.claimErrors or 0) + 1
      Coop.log("claim error: " .. tostring(err))
    end
  end
  if CoopStory and Coop.inSession() then
    local ok, err = pcall(CoopStory.update)
    if not ok and (Coop.storyTickErrors or 0) < 5 then
      Coop.storyTickErrors = (Coop.storyTickErrors or 0) + 1
      Coop.log("story error: " .. tostring(err))
    end
  end
  if CoopPatrol and Coop.inSession() then
    local ok, err = pcall(CoopPatrol.update)
    if not ok and (Coop.patrolErrors or 0) < 5 then
      Coop.patrolErrors = (Coop.patrolErrors or 0) + 1
      Coop.log("patrol error: " .. tostring(err))
    end
  end
  if CoopSplits and Coop.inSession() then
    local ok, err = pcall(CoopSplits.update)
    if not ok and (Coop.splitsErrors or 0) < 5 then
      Coop.splitsErrors = (Coop.splitsErrors or 0) + 1
      Coop.log("splits error: " .. tostring(err))
    end
  end
  if CoopTalk then pcall(CoopTalk.update) end
  if CoopCtl then pcall(CoopCtl.update) end
  if CoopSession and Coop.inSession() then
    local ok, err = pcall(CoopSession.update)
    if not ok and (Coop.sessionErrors or 0) < 5 then
      Coop.sessionErrors = (Coop.sessionErrors or 0) + 1
      Coop.log("session error: " .. tostring(err))
    end
  end
  if CoopSpirit then
    local ok, err = pcall(CoopSpirit.update)
    if not ok and (Coop.spiritErrors or 0) < 5 then
      Coop.spiritErrors = (Coop.spiritErrors or 0) + 1
      Coop.log("spirit error: " .. tostring(err))
    end
  end
  if Coop.inSession() then
    Coop.updateLocalOwnership()
    if Coop.level ~= "levels/menu" then pcall(Coop.controlWatchdog) end
    if Coop.level ~= "levels/menu" and CoopPowers then
      local okp, errp = pcall(CoopPowers.update)
      if not okp and (Coop.powerErrors or 0) < 5 then
        Coop.powerErrors = (Coop.powerErrors or 0) + 1
        Coop.log("powers error: " .. tostring(errp))
      end
    end
    if Coop.frame % Coop.SEND_EVERY == 0 then Coop.sendStates() end
    if Coop.isHost() and Coop.frame % 40 == 0 then Coop.broadcastOwners() end
    if Coop.isHost() and Coop.frame % 20 == 7 then pcall(Coop.sendHostPos) end
  end
  if Coop.menuMode() then CoopMenu.update() end
  if Coop.bot then Coop.bot() end
  if Coop.dev then Coop.dev() end
  if Coop.frame % 100 == 0 then Coop.report() end
end

function Coop.start()
  Game.Set("OnRenderDebug", Coop.FRAME_HOOK)
end

function Coop.report()
  local errAvg = Coop.errN and Coop.errN > 0 and Coop.errSum / Coop.errN or -1
  local parts = {"f=" .. Coop.frame, "me=" .. tostring(Coop.localChar()), "own=" .. Coop.ownString(),
                 Net.CoopStatus(), "snaps=" .. (Coop.snaps or 0),
                 string.format("err_avg=%.0f err_max=%.0f", errAvg, Coop.errMax or -1),
                 CoopEnemies and CoopEnemies.report() or "", CoopWorld and CoopWorld.report() or "",
                 Coop.mxReport()}
  Coop.errN, Coop.errSum, Coop.errMax = 0, 0, 0
  for _, name in ipairs(Coop.SQUAD) do
    local st = Coop.remote[name]
    local e = Coop.squadEnt(name)
    if st and e and Coop.isPuppet(name) then
      parts[#parts + 1] = name .. ":err=" .. string.format("%.0f", Coop.perr and Coop.perr[name] or -1) ..
                          ",act=" .. tostring(e.Action)
      local d = Coop.pd[name]
      if d and d.snaps > 0 then
        parts[#parts] = parts[#parts] .. string.format(",snaps=%d,vsnaps=%d,engDy=%.1f", d.snaps, d.vsnaps,
                                                       d.eN > 0 and d.eSum / d.eN or 0)
        d.eSum, d.eN = 0, 0
      end
    end
  end
  Coop.log(table.concat(parts, " "))
end

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------

-- Restore the ownership table carried over from the previous level.
if cfg.owners then Coop.owners = Coop.parseOwn(cfg.owners) end

-- Game.UsrEntity(n) reads the engine's table of local users with no check: only user 0 is
-- there in a game without split screen (user 1 with it; coop_split.lua maps the 3 it gives
-- hidden first-person models). The game's own scripts pass an FP model's id
-- (Game.UsrEntity(fp.id)), and the FP models of other players' characters have other ids:
-- the engine then read a bad pointer and the game crashed (0x427489, 0.2.2 tests: a client
-- in Rom_Outskirts). No such user: nil, which those scripts take as a script error.
if Game.UsrEntity ~= Coop.usrGuard then
  local real = Game.UsrEntity
  Coop.usrGuard = function(i, ...)
    if i == 0 or (i == 1 and CoopSplit and (CoopSplit.on or CoopSplit.char)) then return real(i, ...) end
    Coop.usrRefused = (Coop.usrRefused or 0) + 1
    if Coop.usrRefused <= 3 then Coop.log("Game.UsrEntity(" .. tostring(i) .. "): no such user here, nil") end
    return nil
  end
  Game.UsrEntity = Coop.usrGuard
end

do
  -- Side instances (the Lost Patrol) wrap the network calls: load before anything sends.
  local ok, err = pcall(dofile, COOP_DIR .. "coop_inst.lua")
  if not ok then Coop.log("inst load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_save.lua")
  if not ok then Coop.log("save load error: " .. tostring(err)) end
end

local status = Net.CoopStatus()
if cfg.auto and Coop.isHost() and string.find(status, "role=none") then
  Coop.log("host start: " .. Net.CoopHost(cfg.port or 28100, 4))
  -- (test sessions over Steam: the lobby too)
  if cfg.net == "steam" and Net.CoopSteam then Coop.log("steam host: " .. tostring(Net.CoopSteam("host", "4"))) end
elseif cfg.auto and Coop.isClient() and string.find(status, "role=none") then
  if cfg.steamjoin and Net.CoopSteam then
    -- (test sessions over Steam: the host's lobby id)
    Coop.log("client start (steam): " .. tostring(Net.CoopSteam("join", tostring(cfg.steamjoin))))
  else
    Coop.log("client start: " .. Net.CoopJoin(cfg.addr or "127.0.0.1", cfg.port or 28100))
  end
elseif not cfg.auto and Coop.level == "levels/menu" and not string.find(status, "role=none") then
  -- Back in the main menu after a session: the session is over.
  Net.CoopClose()
  if CoopSave then pcall(CoopSave.endSession) end
  cfg.role, cfg.myId, cfg.char, cfg.owners, cfg.seats, cfg.loaded = nil, nil, nil, nil, nil, nil
  cfg.inst, cfg.instAuth, cfg.instIds, cfg.instOf, cfg.instAuthOnHub, cfg.netRole, cfg.realId = nil, nil, nil, nil, nil, nil, nil
  status = Net.CoopStatus()
end

if Coop.level == "levels/menu" and not cfg.auto then
  local ok, err = pcall(dofile, COOP_DIR .. "coop_menu.lua")
  if not ok then Coop.log("menu error: " .. tostring(err)) end
end
if Coop.level ~= "levels/menu" then
  if Coop.inSession() then
    local okfp, errfp = pcall(Coop.installFP)
    if not okfp then Coop.log("first-person sets error: " .. tostring(errfp)) end
  end
  local ok, err = pcall(dofile, COOP_DIR .. "coop_enemies.lua")
  if not ok then Coop.log("enemies error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_hud.lua")
  if not ok then Coop.log("hud load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_team.lua")
  if not ok then Coop.log("team load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_scenes.lua")
  if not ok then Coop.log("scenes load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_spirit.lua")
  if not ok then Coop.log("spirit load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_powers.lua")
  if not ok then Coop.log("powers load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_world.lua")
  if not ok then Coop.log("world load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_claim.lua")
  if not ok then Coop.log("claim load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_squad.lua")
  if not ok then Coop.log("squad load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_souls.lua")
  if not ok then Coop.log("souls load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_session.lua")
  if not ok then Coop.log("session load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_story.lua")
  if not ok then Coop.log("story load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_splits.lua")
  if not ok then Coop.log("splits load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_patrol.lua")
  if not ok then Coop.log("patrol load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_talk.lua")
  if not ok then Coop.log("talk load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_anim.lua")
  if not ok then Coop.log("anim load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_ctl.lua")
  if not ok then Coop.log("ctl load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_choice.lua")
  if not ok then Coop.log("choice load error: " .. tostring(err)) end
  ok, err = pcall(dofile, COOP_DIR .. "coop_spectate.lua")
  if not ok then Coop.log("spectate load error: " .. tostring(err)) end
  if cfg.storyline then
    ok, err = pcall(dofile, COOP_DIR .. "coop_storysolo.lua")
    if not ok then Coop.log("story solo load error: " .. tostring(err)) end
  end
end
-- SMOD next to co-op (texts, the same rules for everyone): menu and levels alike.
do
  local ok, err = pcall(dofile, COOP_DIR .. "coop_smod.lua")
  if not ok then Coop.log("smod load error: " .. tostring(err)) end
  -- SMOD Add-ons (PHM2D) on top of SMOD: the third-person view and the rest, found by their own globals.
  ok, err = pcall(dofile, COOP_DIR .. "coop_addon.lua")
  if not ok then Coop.log("addon load error: " .. tostring(err)) end
  -- Split screen in one game: off at every load, on again in a level with a player 2.
  ok, err = pcall(dofile, COOP_DIR .. "coop_split.lua")
  if not ok then Coop.log("split load error: " .. tostring(err)) end
  -- Act 1: Ross's body for the other players (split screen and session alike).
  ok, err = pcall(dofile, COOP_DIR .. "coop_ross.lua")
  if not ok then Coop.log("ross load error: " .. tostring(err)) end
end
if cfg.dev then pcall(dofile, COOP_DIR .. "dev.lua") end
-- Test sessions start without the lobby: protect the profile from the first level on.
if CoopSave and Coop.inSession() and Coop.level ~= "levels/menu" then CoopSave.beginSession() end

Coop.log("coop.lua loaded level=" .. Coop.level .. " role=" .. tostring(cfg.role) .. " " .. status)

function Coop.menuLoad()
  cfg.loaded = true
  -- Tests: start the level at a given spawn point (checkpoint).
  if cfg.dev and cfg.prespawn then
    local var = "level." .. string.lower(cfg.level) .. ".Spawn.Point"
    Game.CreateSaveVar(var, tostring(cfg.prespawn))
    Game.SetSaveVar(var, tostring(cfg.prespawn))
  end
  Game.Set("InitLuaLine", COOP_BOOT_LINE())
  Coop.log("loading " .. cfg.level)
  Game.LoadLevel("Levels/" .. cfg.level)
end

if Coop.level == "levels/menu" and cfg.auto then
  if Coop.isHost() or cfg.role == "solo" then
    if cfg.level and not cfg.loaded then
      Game.AddScheduledFunc(Game.GetTime() + 0.5, "CoopMenu", "Coop.menuLoad", 0)
    end
  end
  -- Clients wait in the menu for the host's welcome, which names the level to load.
end
Coop.start()
