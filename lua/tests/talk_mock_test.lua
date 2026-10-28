-- Offline check of coop_talk.lua: the game's real teamtalk.lua on two simulated machines (host and
-- client, each with its own globals) with a virtual clock, a scheduler and a message pipe.
-- Run: lua tests/talk_mock_test.lua  (from mod/lua; the path of teamtalk.lua is the first argument,
-- default ../../work/src/scripts/chars/teamtalk.lua)
local TTPATH = arg and arg[1] or "../../work/src/scripts/chars/teamtalk.lua"
local clock = 100
local machines = {}
local LANG = {
  Ross = "Ross", Black = "Black", Cole = "Cole",
  Chat0 = "Ross>Move up.", Chat1 = "Black>Roger.", Chat2 = "Ross>Quiet.",
  Talk_Black_View_Enemy = "1>Enemy ahead!",
  Talk_Black_View_Enemy_RU = "1>x", Talk_Cole_View_Enemy = "1>Hostile.",
}
local RU = {Ross = "Росс", Black = "Блэк", Chat0 = "Ross>Вперёд.", Chat1 = "Black>Понял.", Chat2 = "Ross>Тихо.",
  Talk_Black_View_Enemy = "1>Враг впереди!"}
local DUR = 1.0     -- every voice lasts this long

local function split(s)
  local t = {}
  for part in string.gmatch(s .. "|", "([^|]*)|") do t[#t + 1] = part end
  if t[#t] == "" then t[#t] = nil end
  return t
end

local function newMachine(role, lang, id, mine)
  local m = {role = role, id = id or (role == 'host' and 0 or 1), mine = mine or {}, sched = {}, inbox = {}, log = {}, spoken = {}, subs = {}, lips = {}, voices = {}}
  local env = setmetatable({}, {__index = _G})
  env._G = env
  m.env = env
  env.defparam = function(v, d) if v == nil then return d end return v end
  env.init = {LevelName = "Levels/WWII_Vigil"}
  local remain = 0
  env.Game = {
    GetTime = function() return clock end,
    Get = function(k) if k == "RemainTalkTime" then return math.max(0, remain - 0) end return 0 end,
    Set = function(k, v) if k == "RemainTalkTime" then remain = v end end,
    GetNumberOfLangStr = function(n)
      local c = -1
      while (lang == "ru" and RU or LANG)[n .. (c + 1)] do c = c + 1 end
      return c
    end,
    GetLangStr = function(n) return (lang == "ru" and RU[n]) or LANG[n] or "" end,
    GetEntity = function(n) return nil end,
    UsrEntity = function() return nil end,
    GetLanguage = function() return lang end,
    Get2 = nil,
    FileExist = function() return false end,
    Rand = function(a, b) return a end,
    AddScheduledFunc = function(t, name, fn, ...)
      m.sched[#m.sched + 1] = {t = t, name = name, fn = fn, args = {...}}
    end,
    DeleteScheduledFuncs = function(n)
      for i = #m.sched, 1, -1 do
        if m.sched[i].name == n or m.sched[i].fn == n then table.remove(m.sched, i) end
      end
    end,
  }
  env.Game.Get = function(k)
    if k == "RemainTalkTime" then return m.remain or 0 end
    if k == "VoicePath" then return "Sounds/Voices/" end
    return 0
  end
  env.Game.Set = function(k, v) if k == "RemainTalkTime" then m.remain = v end end
  env.Sound = {
    OpenVoice = function(file, chan) m.opened = file end,
    VoiceIsReady = function() return true end,
    PlayVoice = function(chan) m.voices[#m.voices + 1] = m.opened; m.playedAt = clock end,
    SetVoiceVolume = function() end,
    VoiceRemain = function() return DUR end,
    StopVoice = function() end,
  }
  env.Scorer = {GetItem = function() return nil end, SetSpeechText = function(t, s) m.subs[#m.subs + 1] = t end}
  env.Team = {Data = {}, ReviveAll = function() if env.Team.ReviveAllCallback then env.Team.ReviveAllCallback() end end}
  env.AISquad = {}
  env.Net = {
    CoopTime = function() return clock end,
    CoopSend = function(peer, rel, data)
      local function put(o) o.inbox[#o.inbox + 1] = {t = clock + 0.03, data = data, from = m.id} end
      if role ~= "host" then put(machines.host)
      elseif peer == -1 then
        for _, r in ipairs({"client", "client2"}) do if machines[r] then put(machines[r]) end end
      else
        for _, r in ipairs({"client", "client2"}) do if machines[r] and machines[r].id == peer then put(machines[r]) end end
      end
    end,
  }
  env.Coop = {cfg = {role = role == 'host' and 'host' or 'client', talklog = true}, level = "levels/wwii_vigil",
    inSession = function() return true end, isHost = function() return role == "host" end,
    isClient = function() return role ~= "host" end, myId = function() return m.id end,
    isLocalBody = function(n) return m.mine[n] == true end, log = function(s) m.log[#m.log + 1] = s end}
  -- the game's code
  local f = assert(loadfile(TTPATH))
  setfenv(f, env)
  env.TeamTalk = {}
  f()
  env.TeamTalk.main()
  env.TeamTalk.VoiceConditions = {}
  local orig = env.TeamTalk.GenericTalk
  -- count what the game's GenericTalk plays (voice file + subtitle)
  local ogen = env.TeamTalk.GenericTalk
  env.TeamTalk.GenericTalk = function(Text, voice, filtered, show)
    m.spoken[#m.spoken + 1] = {voice = voice, text = Text, t = clock, filtered = filtered, show = show}
    return ogen(Text, voice, filtered, show)
  end
  local olips = env.TeamTalk.StartTalkingLips
  env.TeamTalk.StartTalkingLips = function(c) m.lips[#m.lips + 1] = c; return olips(c) end
  -- the mod
  local mf = assert(loadfile("coop_talk.lua"))
  setfenv(mf, env)
  mf()
  m.K = env.CoopTalk
  m.K.install()
  m.call = function(dotted, ...)
    local fn = env
    for part in string.gmatch(dotted, "[^.]+") do fn = fn[part] end
    return fn(...)
  end
  machines[role] = m
  return m
end

local function step(dt)
  clock = clock + dt
  for _, role in ipairs({"host", "client", "client2"}) do
    local m = machines[role]
    if m then
    -- the voice time runs down
    if m.remain and m.remain > 0 then m.remain = math.max(0, m.remain - dt) end
    -- messages
    for i = #m.inbox, 1, -1 do
      local msg = m.inbox[i]
      if msg.t <= clock then
        table.remove(m.inbox, i)
        m.K.onMessage(msg.from, split(msg.data))
      end
    end
    -- scheduled functions (run in order of time)
    table.sort(m.sched, function(a, b) return a.t < b.t end)
    while m.sched[1] and m.sched[1].t <= clock do
      local s = table.remove(m.sched, 1)
      local ok, err = pcall(m.call, s.fn, unpack(s.args))
      if not ok then error("scheduled " .. s.fn .. ": " .. tostring(err)) end
    end
    m.K.update()
    end
  end
end

local function run(secs, dt)
  dt = dt or 0.05
  local t = 0
  while t < secs do step(dt); t = t + dt end
end

local function voices(m)
  local t = {}
  for _, s in ipairs(m.spoken) do t[#t + 1] = s.voice end
  return table.concat(t, ",")
end

local function reset_unused()
  for _, m in pairs(machines) do
    m.spoken, m.subs, m.lips, m.sched, m.inbox, m.log = {}, {}, {}, {}, {}, {}
    m.remain = 0
  end
end

local function setup(clang, mine, two)
  machines = {}
  newMachine("host", "en")
  newMachine("client", clang or "en", 1, mine)
  if two then newMachine("client2", "ru", 2, {}) end
end

------------------------------------------------------------------------------
-- 1. a chat started on both (the callback replayed on the client a little later)
------------------------------------------------------------------------------
setup()
local H, C = machines.host, machines.client
local ended = {host = 0, client = 0}
local e1 = {}
H.env.TeamTalk.InitIncidentalChat("Chat", function() ended.host = ended.host + 1; e1.h = clock end, false)
run(0.1)
C.env.TeamTalk.InitIncidentalChat("Chat", function() ended.client = ended.client + 1; e1.c = clock end, false)
run(8)
print(string.format("1 chat end host %.2f client %.2f", e1.h, e1.c))
print("1 host:   " .. voices(H))
print("1 client: " .. voices(C))
assert(voices(H) == "Chat0,Chat1,Chat2", "host plays the chat once")
assert(voices(C) == "Chat0,Chat1,Chat2", "client plays the host's chat once, in order: " .. voices(C))
assert(ended.host == 1 and ended.client == 1, "chat end callbacks: " .. ended.host .. "/" .. ended.client)
assert(C.spoken[1].text == "Ross: Move up.", "subtitle of the client: " .. C.spoken[1].text)
assert(#C.lips == 3 and C.lips[2] == "Black", "lips")
assert(not C.env.TeamTalk.IncidentalSpeach and not H.env.TeamTalk.IncidentalSpeach, "chats over")
assert(C.env.TeamTalk.EndTalkFunc == nil, "no stale continuation")

------------------------------------------------------------------------------
-- 2. the client's copy of the chat starts BEFORE the host's line reaches it
------------------------------------------------------------------------------
setup()
H, C = machines.host, machines.client
ended = {host = 0, client = 0}
C.env.TeamTalk.InitIncidentalChat("Chat", function() ended.client = ended.client + 1 end, false)
run(0.01)
H.env.TeamTalk.InitIncidentalChat("Chat", function() ended.host = ended.host + 1 end, false)
run(8)
print("2 client: " .. voices(C))
assert(voices(C) == "Chat0,Chat1,Chat2", "client first: " .. voices(C))
assert(ended.host == 1 and ended.client == 1, "chat end callbacks: " .. ended.host .. "/" .. ended.client)

------------------------------------------------------------------------------
-- 3. the client's copy starts late (the host's first lines came before it)
------------------------------------------------------------------------------
setup()
H, C = machines.host, machines.client
ended = {host = 0, client = 0}
H.env.TeamTalk.InitIncidentalChat("Chat", function() ended.host = ended.host + 1 end, false)
run(1.3)
C.env.TeamTalk.InitIncidentalChat("Chat", function() ended.client = ended.client + 1 end, false)
run(12)
print("3 client: " .. voices(C))
assert(voices(C) == "Chat0,Chat1,Chat2", "client late: " .. voices(C))
assert(ended.client == 1, "late client chat end: " .. ended.client)
assert(not C.env.TeamTalk.IncidentalSpeach, "late client chat over")

------------------------------------------------------------------------------
-- 4. a squad bark: only the host's line, in the client's own language
------------------------------------------------------------------------------
setup("ru")
H, C = machines.host, machines.client
assert(H.env.TeamTalk.ForceRadioTalk("Black", "View_Enemy"))
C.env.TeamTalk.ForceRadioTalk("Black", "View_Enemy")   -- the client's own copy
run(4)
print("4 host: " .. voices(H) .. " | " .. H.spoken[1].text)
print("4 client: " .. voices(C) .. " | " .. tostring(C.spoken[1] and C.spoken[1].text))
assert(#H.spoken == 1 and #C.spoken == 1, "one bark each")
assert(C.spoken[1].text == "Блэк: Враг впереди!", "russian subtitle: " .. tostring(C.spoken[1].text))
assert(C.spoken[1].voice == "Talk_Black_View_Enemy", "voice id")
assert(C.env.TeamTalk.EndTalkFunc == nil, "no stale continuation after a client bark")

------------------------------------------------------------------------------
-- 5. a client-only bark is dropped, and does not wedge the talk state
------------------------------------------------------------------------------
setup()
H, C = machines.host, machines.client
C.env.TeamTalk.EndTalkFunc = function() end   -- what OneToAll leaves behind after a dropped line
run(3)
assert(C.env.TeamTalk.EndTalkFunc == nil, "stale continuation cleared")
assert(not C.env.TeamTalk.isTalking(), "client may talk again")

------------------------------------------------------------------------------
-- 6. the host's chat lines never arrive: the client's own chat plays after the delay
------------------------------------------------------------------------------
setup()
H, C = machines.host, machines.client
ended = {host = 0, client = 0}
C.env.TeamTalk.InitIncidentalChat("Chat", function() ended.client = ended.client + 1 end, false)
run(20)
print("6 client: " .. voices(C))
assert(voices(C) == "Chat0,Chat1,Chat2", "fallback plays the chat: " .. voices(C))
assert(ended.client == 1, "fallback chat end: " .. ended.client)

-- 7. the host's own game is unchanged: one GenericTalk, one message
setup()
H, C = machines.host, machines.client
H.env.TeamTalk.InitIncidentalChat("Chat", nil, false)
run(8)
assert(H.K.sent == 3, "three lines sent: " .. H.K.sent)
assert(C.K.played == 3, "three lines played: " .. C.K.played)

-- 8. the client was still loading when the host's first line was sent: that line is lost, the
-- chain must not stay one line behind (no repeats of old lines, one end callback, in time)
setup()
H, C = machines.host, machines.client
ended = {host = 0, client = 0}
H.env.TeamTalk.InitIncidentalChat("Chat", function() ended.host = ended.host + 1 end, false)
C.inbox = {}                                   -- the first line's message never reached it
run(0.2)
C.env.TeamTalk.InitIncidentalChat("Chat", function() ended.client = ended.client + 1 end, false)
run(15)
print("8 client: " .. voices(C))
assert(voices(C) == "Chat1,Chat2", "lost first line: " .. voices(C))
assert(ended.client == 1, "lost first line, chat end: " .. ended.client)

-- 9. the same chat again 12 s later (a second chat of the same name): played again, once
local before = #C.spoken
H.env.TeamTalk.InitIncidentalChat("Chat", nil, false)
run(0.1)
C.env.TeamTalk.InitIncidentalChat("Chat", nil, false)
run(8)
assert(#C.spoken - before == 3, "repeat plays three lines: " .. (#C.spoken - before))

-- 10. extra NextChat calls on the client (the game's own retries) must not run its chain ahead:
-- the chat's end callback comes with the host's last line
setup()
H, C = machines.host, machines.client
local endT = {}
H.env.TeamTalk.InitIncidentalChat("Chat", function() endT.host = clock end, false)
run(0.05)
C.env.TeamTalk.InitIncidentalChat("Chat", function() endT.client = clock end, false)
run(0.9)
C.env.TeamTalk.NextChat(); C.env.TeamTalk.NextChat()
run(0.3)
C.env.TeamTalk.NextChat()
run(10)
print("10 client: " .. voices(C) .. string.format("  end host %.1f client %.1f", endT.host, endT.client))
assert(voices(C) == "Chat0,Chat1,Chat2", "extra NextChat calls: " .. voices(C))
assert(math.abs(endT.client - endT.host) < 0.6, "chat end together")

-- 11. a client's own body barks: played at once there, relayed by the host to the other client
-- (its own language), played on the host too; nobody hears it twice; another body's line from
-- a client is dropped there
setup("en", {Black = true}, true)
H, C = machines.host, machines.client
local C2 = machines.client2
C.env.TeamTalk.ForceRadioTalk("Black", "View_Enemy")
C.env.TeamTalk.ForceRadioTalk("Cole", "View_Enemy")      -- not this client's body
run(0.5)
print("11 client: " .. voices(C) .. " | host: " .. voices(H) .. " | client2: " .. voices(C2) .. " | " .. tostring(C2.spoken[1] and C2.spoken[1].text))
assert(#C.spoken == 1 and C.spoken[1].voice == "Talk_Black_View_Enemy", "client says its own body's line once")
assert(#H.spoken == 1 and H.spoken[1].voice == "Talk_Black_View_Enemy", "host plays the relayed line")
assert(#C2.spoken == 1 and C2.spoken[1].text == "Блэк: Враг впереди!", "other client hears it in its language")
assert(C.K.dropped == 1 and #C.spoken == 1, "the other body's line is dropped")
-- the host's own line from the same voice reaching the speaker's client: no second play there
H.env.TeamTalk.TalkStamp = -1000
H.env.TeamTalk.ForceRadioTalk("Black", "View_Enemy")
run(4)
assert(#C.spoken == 1, "the speaker does not hear it again: " .. #C.spoken)

-- 12. the end of a voice the client said runs the order's confirmation, said by a squad member: heard by all
setup("en", {Ross = true}, true)
H, C, C2 = machines.host, machines.client, machines.client2
LANG.Talk_Ross_Order = "1>Move out."; LANG.Talk_Cole_Done = "1>On it."
C.env.TeamTalk.RadioTalk("Ross", "Order")
C.env.TeamTalk.EndTalkFunc = function() C.env.TeamTalk.RadioTalk("Cole", "Done") end
run(6)
print("12 client: " .. voices(C) .. " | host: " .. voices(H) .. " | client2: " .. voices(C2))
assert(voices(C) == "Talk_Ross_Order,Talk_Cole_Done" and voices(H) == voices(C) and voices(C2) == voices(C), "order and answer reach everybody")

print("talk mock test: OK")
