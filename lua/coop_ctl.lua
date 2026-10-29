-- Jericho co-op: who drives a body a human holds (owner's 0.2.7 bug 7: a player sits in a squad
-- member and the body starts walking by itself, the first-person view is dragged along, the player
-- cannot resist). Diagnostics only, so far (nothing here changes a body):
--   * every body a human holds on this machine (the player's, split screen player 2's) and every
--     body the owner table gives to a human: one log line `ctl: ...` whenever the owner, UsrControl,
--     oAI.bEnable, bActive, the lock (IgnoreUsrControl), the AI's objective or the puppet state of
--     the body changes (the control line of Coop.watchControl printed only the first player's AI flag);
--   * a body this machine's human holds that MOVES while the machine's own pad/keyboard shows no move
--     input: `ctl: X moves by itself ...` with what could drive it (AI, story walk, squad chase,
--     puppet state, the last module that wrote its position, scene), at most once per 3 s per body.
-- Switched off with cfg.ctldiag = false; the movement lines need the window in front for the keyboard
-- (Net.CoopKey) and a pad for the sticks: with neither, "no input" is assumed only in background tests.
CoopCtl = CoopCtl or {}
local C = CoopCtl
local cfg = Coop.cfg

C.LOG_MAX = 400        -- lines per level
C.MOVE_SPEED = 70      -- units/s of horizontal travel that count as moving (a walk is about 150-300)
C.MOVE_TIME = 1.0      -- s of such travel without input before it is logged
C.MOVE_EVERY = 3       -- s between two lines of one body
C.last = {}            -- body -> state key
C.mv = {}              -- body -> {x, z, t, since}
C.logs = 0

local function now() return Net.CoopTime() end

local function g(f)
  local ok, v = pcall(f)
  if ok and v ~= nil then return tostring(v) end
  return "-"
end

-- Does this machine's human push a move input? (keyboard WASD while the window is in front, any
-- pad's left stick; Net.CoopKey(-1, n) = pad n: ok, buttons, lt, rt, lx, ly, rx, ry)
function C.humanInput()
  if not Net.CoopKey then return false end
  for _, vk in ipairs({0x57, 0x41, 0x53, 0x44}) do
    local ok, v = pcall(Net.CoopKey, vk)
    if ok and v == 1 then return true end
  end
  for n = 0, 1 do
    local r = {pcall(Net.CoopKey, -1, n)}
    if r[1] and r[2] ~= nil then
      local lx, ly = tonumber(r[5]) or 0, tonumber(r[6]) or 0
      if math.abs(lx) > 7849 or math.abs(ly) > 7849 then return true end
    end
  end
  return false
end

local function bodyKey(e, name)
  local owner = Coop.owners[name]
  return string.format("owner=%s usr=%s ai=%s active=%s lock=%s obj=%s puppet=%s story=%s",
    tostring(owner), g(function() return e.UsrControl end), g(function() return e.oAI.bEnable end),
    g(function() return e.bActive end), g(function() return e.IgnoreUsrControl end),
    g(function() return e.oAI.ObjectiveDin end), tostring(Coop.isPuppet and Coop.isPuppet(name)),
    tostring(Coop.storyDriven and Coop.storyDriven[name] or false))
end

local function drivers(name)
  local parts = {}
  local w = Coop.posWriters and Coop.posWriters[name]
  if w then parts[#parts + 1] = string.format("lastwriter=%s %.1fs ago", tostring(w.tag), now() - w.t) end
  if CoopSquad and CoopSquad.leaderOf and CoopSquad.leaderOf[name] ~= nil then
    parts[#parts + 1] = "squadleader=" .. tostring(CoopSquad.leaderOf[name])
  end
  if CoopStory and CoopStory.taken and CoopStory.taken(name) then parts[#parts + 1] = "story-taken" end
  if Coop.wasPuppet and Coop.wasPuppet[name] then parts[#parts + 1] = "wasPuppet" end
  if Coop.puppetNoCollide and Coop.puppetNoCollide[name] ~= nil then parts[#parts + 1] = "puppet-collision-state" end
  if Scene and Scene.IsPlaying then parts[#parts + 1] = "scene" end
  return table.concat(parts, " ")
end

local function log(s)
  C.logs = C.logs + 1
  if C.logs <= C.LOG_MAX then Coop.log("ctl: " .. s) end
end

-- Bodies to look at: the local players' and the owner table's.
local function names()
  local t, seen = {}, {}
  local function add(n) if n and not seen[n] then seen[n] = true t[#t + 1] = n end end
  local u = Game.UsrEntity(0)
  add(u and u.Name)
  if CoopSplit and CoopSplit.on and CoopSplit.body then
    local b = CoopSplit.body()
    add(b and b.Name)
  end
  for n in pairs(Coop.owners) do add(n) end
  return t
end

function C.update()
  if cfg.ctldiag == false or not Coop.inSession() or Coop.level == "levels/menu" then return end
  local t = now()
  local human
  local inputKnown = false
  for _, name in ipairs(names()) do
    local e = Game.GetEntity(name)
    if e then
      local key = bodyKey(e, name)
      if key ~= C.last[name] then
        C.last[name] = key
        log(string.format("%s %s act=%s", name, key, g(function() return e.Action end)))
      end
      -- a body this machine's human holds
      local held = (Game.UsrEntity(0) == e) or (CoopSplit and CoopSplit.on and CoopSplit.body and CoopSplit.body() == e)
      if held and (e.Life or 0) > 0 then
        local p = e.Pos
        local m = C.mv[name]
        if not m then m = {x = p.x, z = p.z, t = t, since = nil}; C.mv[name] = m end
        local dt = t - m.t
        if dt >= 0.1 then
          local d = math.sqrt((p.x - m.x) ^ 2 + (p.z - m.z) ^ 2)
          local speed = d / dt
          m.x, m.z, m.t = p.x, p.z, t
          local moving = speed > C.MOVE_SPEED and d < 600   -- (a teleport or a snap is not a walk)
          if moving and not (Scene and Scene.IsPlaying) and g(function() return e.IgnoreUsrControl end) ~= "1" then
            if human == nil then human = C.humanInput() end
            if human then
              m.since = nil
            else
              m.since = m.since or t
              if t - m.since >= C.MOVE_TIME and t - (m.logT or -100) >= C.MOVE_EVERY then
                m.logT = t
                log(string.format("%s moves by itself: %.0f u/s, no move input from this machine's pad/keyboard; act=%s walk=%s/%s/%s %s | %s",
                  name, speed, g(function() return e.Action end), g(function() return e.InCtrl_Walk end),
                  g(function() return e.InCtrl_Str end), g(function() return e.InCtrl_Sprint end), bodyKey(e, name), drivers(name)))
              end
            end
          else
            m.since = nil
          end
        end
      else
        C.mv[name] = nil
      end
    end
  end
end

function C.report()
  return string.format("ctl logs=%d", C.logs)
end
