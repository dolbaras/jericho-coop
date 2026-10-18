-- Transport smoke test: the client pings the host once a second, the host answers.
-- Usage from InitLuaLine: COOP_ROLE='host' (or 'client') then dofile this file.
CoopTest = {}

function CoopTest.start(role, addr, port)
  CoopTest.role = role
  CoopTest.n = 0
  if role == "host" then
    Net.CoopLog("start host " .. Net.CoopHost(port, 4))
  else
    Net.CoopLog("start client " .. Net.CoopJoin(addr, port))
  end
  Game.AddScheduledFunc(Game.GetTime() + 0.1, "CoopTick", "CoopTest.tick", 0)
end

function CoopTest.tick()
  while true do
    local peer, kind, data = Net.CoopRecv()
    if not peer then break end
    Net.CoopLog("recv peer=" .. peer .. " kind=" .. kind .. " data=" .. data)
    if kind == "msg" and CoopTest.role == "host" then
      Net.CoopSend(peer, 1, "pong " .. data)
    end
  end
  CoopTest.n = CoopTest.n + 1
  if CoopTest.role == "client" and CoopTest.n % 20 == 0 then
    Net.CoopSend(0, 1, "ping " .. CoopTest.n .. " t=" .. string.format("%.3f", Net.CoopTime()))
  end
  if CoopTest.n % 40 == 0 then
    Net.CoopLog(Net.CoopStatus())
  end
  Game.AddScheduledFunc(Game.GetTime() + 0.05, "CoopTick", "CoopTest.tick", 0)
end

CoopTest.start(COOP_ROLE, COOP_ADDR or "127.0.0.1", COOP_PORT or 28100)
