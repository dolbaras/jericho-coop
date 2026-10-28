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
K.FALLBACK = 1.5    -- s: a dropped local chat line is played after this long without the host's
K.SKIP = 20         -- s: a local chat line of a voice played this recently here is not played again
K.DEDUP = 3         -- s: the same voice twice within this time is one line
K.STALE = 1.5       -- s: a stale EndTalkFunc of a dropped client bark is cleared after this long
K.queue = {}        -- host lines waiting for the voice channel (client)
K.recent = {}       -- voice -> real time it was played here
K.sent, K.played, K.dropped, K.dups, K.fallbacks, K.relayed, K.said = 0, 0, 0, 0, 0, 0, 0
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
function K.play(voice, speaker, filteredHost, show, nochain)
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
  if not nochain and keepF and keepF == T.NextChat then
    T.EndTalkFunc, T.EndTalkParam = keepF, keepP
  end
  K.localPend = nil
  -- A local chat chain follows the host's lines: its next step is this very line, which it then
  -- finds played already and goes on from (a line the client never got, sent while it was still
  -- loading, no longer leaves it behind; the previous voice's end, a few ms after the host's next
  -- line came in, no longer ends the chain early).
  if not nochain and T.ChatData and T.iChatData then
    for i, c in ipairs(T.ChatData) do
      if c[1] == voice then
        T.iChatData = i
        break
      end
    end
  end
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

-- A line a client's own body said (it played it itself): the host passes it on to everybody else
-- and plays it when its own voice channel is free (a barking squad is no chat: never cuts one off).
function K.fromClient(peer, f)
  local voice = f[2]
  Net.CoopSend(-1, 1, "talk|" .. clean(voice) .. "|" .. clean(f[3]) .. "|" .. (f[4] == "1" and 1 or 0) .. "|" ..
                      (f[5] ~= "0" and 1 or 0) .. "|" .. tostring(peer))
  K.relayed = K.relayed + 1
  local T = TeamTalk
  local t = K.recent[voice]
  local playing = not T or T.isTalking() or T.ChatData ~= nil or (t and now() - t < K.DEDUP)
  if K.relayed <= 60 or cfg.talklog then
    Coop.log("talk relayed " .. tostring(voice) .. " from " .. tostring(peer) .. " speaker=" .. tostring(f[3]) ..
             (playing and " (not played here)" or ""))
  end
  if not playing then pcall(K.play, voice, f[3] or "-", f[4] == "1", f[5] ~= "0", true) end
end

function K.onMessage(peer, f)
  if f[1] ~= "talk" then return false end
  if not f[2] or f[2] == "" then return true end
  if Coop.isHost() then
    if peer and peer ~= 0 then K.fromClient(peer, f) end
    return true
  end
  if not Coop.isClient() then return true end
  -- another client's line is relayed with its peer id; this client's own line comes back unplayed
  if f[6] and tonumber(f[6]) == Coop.myId() then return true end
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
  -- client: the host's line is the one that plays ...
  local T = TeamTalk
  if T.ChatData == nil then
    -- ... except what its own body says: StartTalkingLips follows at once and names the speaker
    K.cpend = {Text = Text, voice = voice, filtered = filtered, show = show_it, t = now()}
    return
  end
  K.dropped = K.dropped + 1
  if K.dropped <= 20 or cfg.talklog then
    Coop.log("talk local line dropped " .. tostring(voice) .. " chat=" .. tostring(T.ChatData ~= nil))
  end
  if T.ChatData ~= nil then
    -- NextChat moved its pointer past this line: the pointer follows the host's lines only
    -- (K.play), so a local step that runs twice or too early cannot run ahead of the host.
    local idx
    for i, c in ipairs(T.ChatData) do
      if c[1] == voice then idx = i break end
    end
    local t = K.recent[voice]
    if idx and not (t and now() - t < K.SKIP) then T.iChatData = idx end
    if t and now() - t < K.SKIP then
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
  -- client: the line waiting for its speaker is said here if it is this machine's own body
  -- (or the answer to such a line, the next step of an order); else the host's line plays
  local c = K.cpend
  K.cpend = nil
  if not c then return end
  local mine = Coop.isLocalBody and Coop.isLocalBody(charname)
  if (mine or K.cont) and not Coop.replay and not Coop.fromHost then
    K.localSay(c, charname)
  else
    K.dropped = K.dropped + 1
    if K.dropped <= 20 or cfg.talklog then
      Coop.log("talk local line dropped " .. tostring(c.voice) .. " speaker=" .. tostring(charname))
    end
  end
end

-- The client's own body speaks: played at once with the game's functions, told to the host.
function K.localSay(c, speaker)
  K.passing = true
  local ok, err = pcall(K.origGeneric, c.Text, c.voice, c.filtered, c.show)
  if ok then ok, err = pcall(K.origLips, speaker) end
  K.passing = false
  K.lastPlay = now()
  K.recent[c.voice] = K.lastPlay
  K.localVoice = true
  K.said = K.said + 1
  Net.CoopSend(0, 1, "talk|" .. clean(c.voice) .. "|" .. clean(speaker) .. "|" .. (c.filtered and 1 or 0) .. "|" ..
                     ((c.show == nil or c.show) and 1 or 0))
  if K.said <= 60 or cfg.talklog then
    Coop.log("talk said " .. tostring(c.voice) .. " speaker=" .. tostring(speaker) .. (ok and "" or " error " .. tostring(err)))
  end
end

-- The end of a voice this client said runs the order's next step (a member's answer): that
-- answer is said here too.
function K.wrapEnd(...)
  if Coop.isClient() and K.localVoice then
    K.localVoice = false
    K.cont = true
    local r = {pcall(K.origEnd, ...)}
    K.cont = false
    if not r[1] then error(r[2], 0) end
    return unpack(r, 2)
  end
  return K.origEnd(...)
end

-- The chat's step that finds no line left ends the chat. On a client such a call can come while
-- the host's last line is still playing (a retry the game scheduled, or the previous voice's end a
-- few ms after the host's next line came in): wait for that voice.
function K.wrapNext(...)
  local T = TeamTalk
  if K.passing or not Coop.inSession() or not Coop.isClient() then return K.origNext(...) end
  if T.ChatData and T.iChatData and T.ChatData[T.iChatData] == nil and busy() then
    Game.AddScheduledFunc(Game.GetTime() + 1, "TeamTalk_NextChat", "TeamTalk.NextChat")
    return true
  end
  return K.origNext(...)
end

function K.install()
  local T = TeamTalk
  if not T or not T.GenericTalk or not T.StartTalkingLips then return end
  if T.OnEndTalk and T.OnEndTalk ~= K.wrapEnd and T.OnEndTalk ~= K.traceEnd then
    K.origEnd = T.OnEndTalk
    T.OnEndTalk = K.wrapEnd
  end
  if T.NextChat and T.NextChat ~= K.wrapNext and T.NextChat ~= K.traceNext then
    K.origNext = T.NextChat
    T.NextChat = K.wrapNext
  end
  if T.GenericTalk ~= K.wrapGeneric then
    K.origGeneric = T.GenericTalk
    T.GenericTalk = K.wrapGeneric
  end
  if T.StartTalkingLips ~= K.wrapLips then
    K.origLips = T.StartTalkingLips
    T.StartTalkingLips = K.wrapLips
  end
  if cfg.talklog and T.NextChat and T.OnEndTalk and T.NextChat ~= K.traceNext then
    -- tracing (cfg.talklog): when the chat's steps run and what the talk state is
    local oN, oE = T.NextChat, T.OnEndTalk
    K.traceNext = function(...)
      Coop.log(string.format("talk trace NextChat: EndTalkFunc=%s remain=%s idx=%s", tostring(T.EndTalkFunc ~= nil),
        tostring(Game.Get("RemainTalkTime")), tostring(T.iChatData)))
      return oN(...)
    end
    K.traceEnd = function(...)
      Coop.log(string.format("talk trace OnEndTalk: EndTalkFunc=%s", tostring(T.EndTalkFunc == K.traceNext and "NextChat" or T.EndTalkFunc ~= nil)))
      return oE(...)
    end
    T.NextChat, T.OnEndTalk = K.traceNext, K.traceEnd
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
  if K.cpend and now() - K.cpend.t > 0.3 then K.cpend = nil end
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

-- The level's first chat can start before the first tick: wrap at once when the game's table is there.
pcall(K.install)

function K.report()
  return string.format("talk sent=%d played=%d dropped=%d dup=%d fallback=%d queued=%d", K.sent, K.played,
                       K.dropped, K.dups, K.fallbacks, #K.queue)
end
