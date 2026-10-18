-- Jericho co-op: character actions (owner's rule, 2026-10-19). Some actions need one
-- particular character: a Church-only climb or blood seal, a Jones-only astral lever, a
-- Delgado-only door, a QTE. When no human holds that character and a player is close to
-- the spot, everyone is asked to take it over; the first to accept switches into it and
-- does the action. If nobody accepts in time, the AI does it (walks there and uses it; a
-- QTE then passes by itself). Lobby option cfg.actmode:
--   "players" (default) players first, AI after ACT_TIMEOUT s
--   "humans"            players only, no AI
--   "ai"                the AI at once
-- Messages: actreq|<gate>|<char>|<what>|<seconds>  host -> all (seconds 0 = closed)
--           (taking it over is the existing claim|<char> message)
CoopClaim = {}
local C = CoopClaim
C.ACT_TIMEOUT = 30
C.AI_WALK_TIMEOUT = 25        -- seconds for the AI to walk there before it is moved there
C.NEAR = 900                 -- a human this close to the spot opens the request
C.KEY = 0x59                 -- Y: take control (Net.CoopKey, only while the game is in front)
C.gates = {}                 -- name -> {name, char, func, radius}
C.open = {}                  -- host: gate -> {char, deadline}
C.aiActing = {}              -- char -> true while the AI does the action (IsPlayer accepts it)
C.aiDid = {}                 -- char -> true after the AI took over an action this level

C.TEXT = {
  en = {req = "%s is needed here (%s).  Y - take control  (%d)", ai = "%s: the AI does it", obj = "use"},
  ru = {req = "Нужен %s (%s).  Y - взять управление  (%d)", ai = "%s: делает ИИ", obj = "действие"},
}

local function text(key)
  local lang = Coop.lang()
  local s = (C.TEXT[lang] or C.TEXT.en)[key]
  return lang == "ru" and Coop.cp1251(s) or s
end

local function prop(list, key)
  for _, kv in ipairs(list) do
    if kv[1] == key then return kv[2] end
  end
end

-- Character-only use objects are plain Lua data: MapPhysicObjects.PhysicObjects keeps
-- every object's property list (mapphysiclogic.lua: UseJustEntity, UseFunc, VRadius).
function C.scanGates()
  C.gates = {}
  local list = MapPhysicObjects and MapPhysicObjects.PhysicObjects
  if not list then return 0 end
  local n = 0
  for _, obj in ipairs(list) do
    local char, name, func = prop(obj, "UseJustEntity"), prop(obj, "Name"), prop(obj, "UseFunc")
    if char and name and func and func ~= "" then
      C.gates[name] = {name = name, char = char, func = func, radius = prop(obj, "VRadius") or 300}
      n = n + 1
    end
  end
  return n
end

function C.mode()
  return Coop.cfg.actmode or "players"
end

local function humanNear(pos)
  for name, peer in pairs(Coop.owners) do
    local e = Game.GetEntity(name)
    if e and e.Pos then
      local d = e.Pos - pos
      if math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z) < C.NEAR then return true end
    end
  end
  return false
end

-- Host, about once a second: open requests for usable gates whose character no human holds.
function C.updateHost()
  local now = Net.CoopTime()
  for name, g in pairs(C.gates) do
    local o = Game.GetEntity(name)
    local usable = o and o.bActive ~= false and o.bArrowCanUse ~= false
    local held = Coop.ownerOf(g.char) ~= nil
    local req = C.open[name]
    if req and (held or not usable) then
      C.close(name, held and "taken" or "gone")
    elseif not req and usable and not held and not C.aiActing[g.char] and humanNear(o.Pos) then
      C.request(name, g.char, text("obj"))
    end
  end
  for name, req in pairs(C.open) do
    if req.deadline and now > req.deadline then C.aiDoes(name) end
  end
  -- The AI did not get there (no path, stuck, killed on the way): put the character at the
  -- object and do it, so the story never stalls.
  local p = C.pendingUse
  if p and now > p.deadline then
    local body, o = Game.GetEntity(p.char), Game.GetEntity(p.gate)
    Coop.log("claim: the AI did not reach " .. p.gate .. " in time, " .. p.char .. " is moved there")
    if body and o then
      if (body.Life or 0) <= 0 and Team and Team.RevivePlayer then pcall(Team.RevivePlayer, body) end
      body.Pos = o.Pos + V3D(60, 0, 0)
    end
    C.aiArrived()
  end
end

function C.request(gate, char, what)
  local mode = C.mode()
  if mode == "ai" then
    C.open[gate] = {char = char}
    C.aiDoes(gate)
    return
  end
  local secs = mode == "humans" and 0 or C.ACT_TIMEOUT
  C.open[gate] = {char = char, what = what, deadline = secs > 0 and Net.CoopTime() + secs or nil}
  Net.CoopSend(-1, 1, string.format("actreq|%s|%s|%s|%d", gate, char, what, secs > 0 and secs or -1))
  C.showLocal(gate, char, what, secs > 0 and secs or -1)
  Coop.log("claim: " .. char .. " needed at " .. gate)
end

function C.close(gate, why)
  C.open[gate] = nil
  Net.CoopSend(-1, 1, "actreq|" .. gate .. "|-|-|0")
  C.showLocal(gate, nil)
  Coop.log("claim: " .. gate .. " closed (" .. tostring(why) .. ")")
end

-- Nobody took the character: the AI walks it to the object and uses it.
function C.aiDoes(gate)
  local req = C.open[gate]
  local g = C.gates[gate]
  C.close(gate, "ai")
  if not req then return end
  local body, o = Game.GetEntity(req.char), Game.GetEntity(gate)
  if not body or not o then return end
  C.aiActing[req.char] = true
  C.aiDid[req.char] = true
  Net.CoopSend(-1, 1, "actreq|" .. gate .. "|" .. req.char .. "|ai|0")
  C.flash = {text = string.format(text("ai"), req.char), untilT = Net.CoopTime() + 4}
  Coop.log("claim: the AI does " .. gate .. " with " .. req.char)
  C.pendingUse = {char = req.char, gate = gate, func = g and g.func, deadline = Net.CoopTime() + C.AI_WALK_TIMEOUT}
  if AIGen and AIGen.GoAndAction then
    pcall(AIGen.GoAndAction, req.char, body.Pos, o.Pos, CoopClaim.aiArrived, (g and g.radius or 300) * 0.5)
  else
    C.aiArrived()
  end
end

function C.aiArrived()
  local p = C.pendingUse
  C.pendingUse = nil
  if not p then return end
  if p.func then
    local f = loadstring("return " .. p.func)
    local ok, fn = pcall(f)
    if ok and type(fn) == "function" then pcall(fn, p.char, p.gate, "Use") end
  end
  C.aiActing[p.char] = nil
end

-- Client and host: the request on screen.
function C.showLocal(gate, char, what, secs)
  if not char then
    if C.shown and C.shown.gate == gate then C.shown = nil end
    return
  end
  C.shown = {gate = gate, char = char, what = what, untilT = secs > 0 and Net.CoopTime() + secs or nil}
end

function C.updateHud()
  local it = Scorer.GetItem(0, "CoopClaim")
  local s, msg = C.shown, nil
  if s then
    local left = s.untilT and math.max(0, math.floor(s.untilT - Net.CoopTime())) or 0
    msg = string.format(text("req"), s.char, s.what or "", left)
  elseif C.flash and Net.CoopTime() < C.flash.untilT then
    msg = C.flash.text
  end
  if not msg then
    if it then it.Visible = 0 end
    return
  end
  if not it then
    it = Scorer.NewItem(0, "CoopClaim", "Text")
    it.Font = (Menu and Menu.SmallFont) or "ScrapMedium"
    it.Color = Color(255, 220, 140, 255)
    it.Effect = "Shadow"
    it.Pos = V2D(320, 400)
  end
  it.Text = msg
  it.CentralText = 1
  it.Visible = 1
end

function C.update()
  if not Coop.inSession() or Coop.level == "levels/menu" then return end
  if not C.scanned then
    C.scanned = true
    Coop.log("claim: " .. C.scanGates() .. " character-only objects in this level")
  end
  if Coop.isHost() and Coop.frame % 20 == 0 then C.updateHost() end
  -- Take control: the existing claim path switches this player into the character.
  local s = C.shown
  if s and Net.CoopKey and Net.CoopKey(C.KEY) == 1 and not C.keyWas then
    Coop.log("claim: taking " .. s.char)
    if Coop.isHost() then
      for n, p in pairs(Coop.owners) do if p == Coop.myId() then Coop.owners[n] = nil end end
      Coop.owners[s.char] = Coop.myId()
      Coop.broadcastOwners()
    else
      Net.CoopSend(0, 1, "claim|" .. s.char)
    end
  end
  C.keyWas = s and Net.CoopKey and Net.CoopKey(C.KEY) == 1
  C.updateHud()
end

function C.onMessage(peer, f)
  if f[1] ~= "actreq" then return false end
  local gate, char, what, secs = f[2], f[3], f[4], tonumber(f[5]) or 0
  if what == "ai" then
    C.flash = {text = string.format(text("ai"), char), untilT = Net.CoopTime() + 4}
    C.showLocal(gate, nil)
  elseif secs == 0 or char == "-" then
    C.showLocal(gate, nil)
  else
    C.showLocal(gate, char, what, secs)
  end
  return true
end

-- AreaTriggers.IsPlayer: while the AI does a character's action, that body counts as the
-- player for the character-only trigger it walks into.
function C.acceptsAI(name)
  return name and C.aiActing[name] == true
end
