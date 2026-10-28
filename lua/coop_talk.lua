-- Jericho co-op: spoken lines (squad barks, radio chats, incidental chats) on every machine.
-- The game's talk code (scripts/chars/teamtalk.lua) runs on each machine on its own: the squad's
-- barks come from the AI (host only: the client's squad members are puppets), chats come from
-- callbacks and from AI state, and every line picks its voice at random. A client therefore
-- heard and read only what its own copy happened to play (owner, 0.2.7).
--
-- The host decides and says it: every TeamTalk.GenericTalk (the one function every line goes
-- through, voice already chosen) is sent on,
--   talk|<voice id>|<speaker>|<filtered 0/1>|<show 0/1>     host -> all (reliable)
-- and a client plays it with the game's own functions: voice file of its own language, subtitle
-- from its own language file (the speaker's name and the line, as the game builds them),
-- radio filter from its own distance to the speaker, lip animation of the speaker.
--
-- The client's own GenericTalk calls are dropped (they would be a second, differently chosen
-- line). Its local chat chain (TeamTalk.NextChat, the continuation that runs the chat's end
-- callback) keeps going, driven by the host's lines: a played line keeps TeamTalk.EndTalkFunc
-- when it is NextChat, so the end of the voice calls the next local step; a dropped chat line
-- is played from its own text after FALLBACK s if the host's line never came.
CoopTalk = CoopTalk or {}
local K = CoopTalk
local cfg = Coop.cfg

K.WAIT = 2.5        -- s: a host line waits this long for the voice channel, then cuts in
K.FALLBACK = 4      -- s: a dropped local chat line is played after this long without the host's
K.DEDUP = 3         -- s: the same voice twice within this time is one line
K.STALE = 1.5       -- s: a stale EndTalkFunc of a dropped client bark is cleared after this long
K.queue = {}        -- host lines waiting for the voice channel (client)
K.recent = {}       -- voice -> real time it was played here
K.sent, K.played, K.dropped, K.dups, K.fallbacks = 0, 0, 0, 0, 0
K.pend = nil        -- host: a line sent once StartTalkingLips names the speaker
K.localPend = nil   -- client: a dropped local chat line waiting for the host's
K.lastPlay = -100

local function now() return Net.CoopTime() end

local function active()
  return Coop.inSession() and Coop.level ~= "levels/menu"
end

local function clean(s)
  s = tostring(s or "")
  s = string.gsub(s, "[|;\r\n]", "")
  if s == "" then return "-" end
  return s
end

------------------------------------------------------------------------------
-- Host: send every line
------------------------------------------------------------------------------

local function flush(speaker)
  local p = K.pend
  if not p then return end
  K.pend = nil
  K.sent = K.sent + 1
  Net.CoopSend(-1, 1, "talk|" .. clean(p.voice) .. "|" .. clean(speaker) .. "|" .. (p.filtered and 1 or 0) ..
                      "|" .. (p.show and 1 or 0))
  if K.sent <= 60 or cfg.talklog then
    Coop.log("talk sent " .. tostring(p.voice) .. " speaker=" .. tostring(speaker) .. " show=" .. tostring(p.show))
  end
end

------------------------------------------------------------------------------
-- Client: a line from the host
------------------------------------------------------------------------------

-- The subtitle as the game builds it: "<speaker's name>: <line>", the line being the language
-- string of the voice without its "<tone>>" or "<speaker>>" prefix.
local function lineOf(voice)
  local s = Game.GetLangStr(voice)
  if not s or s == "" then return nil, nil end
  local pre, rest = string.match(s, "^([^>]*)>(.*)$")
  if not pre then return nil, s end
  return pre, rest
end

local function busy()
  local ok, remain = pcall(Game.Get, "RemainTalkTime")
  if ok and (tonumber(remain) or 0) > 0.25 then return true end
  return now() - K.lastPlay < 0.6
end

-- Plays a line through the game's own functions. Keeps the continuation of a local chat.
function K.play(voice, speaker, filteredHost, show)
  local T = TeamTalk
  if not T or not K.origGeneric then return false end
  local pre, rest = lineOf(voice)
  if not rest then
    Coop.log("talk " .. tostring(voice) .. ": no text in this language, skipped")
    return false
  end
  if speaker == "-" or speaker == "" then speaker = nil end
  if not speaker and pre and not string.match(pre, "^%d*$") then speaker = pre end
  local text = rest
  if speaker then text = (Game.GetLangStr(speaker) or speaker) .. ": " .. rest end
  local filtered = filteredHost
  if speaker and T.isFiltered then
    local ok, v = pcall(T.isFiltered, speaker)
    if ok then filtered = v end
  end
  if show == nil then show = rest ~= "." end
  local keepF, keepP = T.EndTalkFunc, T.EndTalkParam
  K.passing = true
  local ok, err = pcall(K.origGeneric, text, voice, filtered, show)
  if ok and speaker and K.origLips then ok, err = pcall(K.origLips, speaker) end
  K.passing = false
  if keepF and keepF == T.NextChat then
    T.EndTalkFunc, T.EndTalkParam = keepF, keepP
  end
  K.localPend = nil
  K.lastPlay = now()
  K.recent[voice] = K.lastPlay
  if not ok then
    Coop.log("talk play error " .. tostring(voice) .. ": " .. tostring(err))
    return false
  end
  K.played = K.played + 1
  if K.played <= 60 or cfg.talklog then
    Coop.log("talk played " .. tostring(voice) .. " speaker=" .. tostring(speaker) .. " show=" .. tostring(show) ..
             " filtered=" .. tostring(filtered) .. " text=" .. string.sub(tostring(text), 1, 60))
  end
  return true
end

local function enqueue(voice, speaker, filtered, show)
  local t = K.recent[voice]
  if t and now() - t < K.DEDUP then
    K.dups = K.dups + 1
    Coop.log("talk " .. voice .. " already played here, dropped")
    return
  end
  K.queue[#K.queue + 1] = {voice = voice, speaker = speaker, filtered = filtered, show = show, t = now()}
end

function K.onMessage(peer, f)
  if f[1] ~= "talk" then return false end
  if not Coop.isClient() then return true end
  if not f[2] or f[2] == "" then return true end
  enqueue(f[2], f[3] or "-", f[4] == "1", f[5] ~= "0")
  K.pump()
  return true
end

function K.pump()
  local q = K.queue
  while #q > 0 do
    local head = q[1]
    if busy() and now() - head.t < K.WAIT then return end
    table.remove(q, 1)
    pcall(K.play, head.voice, head.speaker, head.filtered, head.show)
  end
end

------------------------------------------------------------------------------
-- Wrappers
------------------------------------------------------------------------------

function K.wrapGeneric(Text, voice, filtered, show_it)
  if K.passing or not active() then return K.origGeneric(Text, voice, filtered, show_it) end
  if Coop.isHost() then
    flush(nil)
    local a, b, c = K.origGeneric(Text, voice, filtered, show_it)
    K.pend = {voice = voice, filtered = filtered and true or false, show = (show_it == nil) or show_it and true or false,
              t = now()}
    return a, b, c
  end
  -- client: the host's line is the one that plays
  K.dropped = K.dropped + 1
  if K.dropped <= 20 or cfg.talklog then
    Coop.log("talk local line dropped " .. tostring(voice) .. " chat=" .. tostring(TeamTalk.ChatData ~= nil))
  end
  local T = TeamTalk
  if T.ChatData ~= nil then
    local t = K.recent[voice]
    if t and now() - t < 8 then
      -- The host's line came first. While its voice plays, that voice's end calls the chat's
      -- next step (EndTalkFunc is set once this returns); when it is over already, go on now.
      if not busy() then Game.AddScheduledFunc(Game.GetTime() + 0.2, "", "TeamTalk.OnEndTalk") end
    else
      K.localPend = {Text = Text, voice = voice, filtered = filtered, show = show_it, t = now()}
    end
  end
end

function K.wrapLips(charname)
  if K.passing or not active() then return K.origLips(charname) end
  if Coop.isHost() then
    K.origLips(charname)
    flush(charname)
    return
  end
  -- client: local lips belong to the dropped line; the played one starts its own
end

function K.install()
  local T = TeamTalk
  if not T or not T.GenericTalk or not T.StartTalkingLips then return end
  if T.GenericTalk ~= K.wrapGeneric then
    K.origGeneric = T.GenericTalk
    T.GenericTalk = K.wrapGeneric
  end
  if T.StartTalkingLips ~= K.wrapLips then
    K.origLips = T.StartTalkingLips
    T.StartTalkingLips = K.wrapLips
  end
  if not K.logged then
    K.logged = true
    Coop.log("talk wrappers installed (" .. tostring(cfg.role) .. ")")
  end
end

------------------------------------------------------------------------------
-- Every tick
------------------------------------------------------------------------------

function K.update()
  K.install()
  if not active() then return end
  if Coop.isHost() then
    -- a line whose speaker never came (no StartTalkingLips): sent without one
    if K.pend and now() - K.pend.t > 0.2 then flush(nil) end
    return
  end
  K.pump()
  local p = K.localPend
  if p and now() - p.t > K.FALLBACK and not busy() then
    K.localPend = nil
    K.fallbacks = K.fallbacks + 1
    Coop.log("talk: no host line for " .. tostring(p.voice) .. ", played from the local chat")
    local pre = lineOf(p.voice)
    pcall(K.play, p.voice, pre and not string.match(pre, "^%d*$") and pre or "-", false, p.show ~= false)
  end
  -- A dropped client bark leaves an EndTalkFunc that no voice end will call: isTalking() would
  -- stay true. Chat continuations (NextChat) are kept.
  local T = TeamTalk
  if T and T.EndTalkFunc ~= nil and T.EndTalkFunc ~= T.NextChat and not busy() then
    K.staleAt = K.staleAt or now()
    if now() - K.staleAt > K.STALE then
      T.EndTalkFunc, T.EndTalkParam = nil, nil
      K.staleAt = nil
    end
  else
    K.staleAt = nil
  end
end

function K.report()
  return string.format("talk sent=%d played=%d dropped=%d dup=%d fallback=%d queued=%d", K.sent, K.played,
                       K.dropped, K.dups, K.fallbacks, #K.queue)
end
