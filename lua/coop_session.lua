-- Jericho co-op: the in-game pause menu and leaving a session.
--
-- * The pause menu does not stop the world in a session (vanilla sets the time speed to 0,
--   which on the host would freeze everyone): see CoopTeam's time hook, which drops the
--   menu's own SetTimeSpeed calls. The player's body just stands while the menu is open.
-- * Clients do not get "restart level" / "load checkpoint": restarts are the host's (it
--   sends the level and its save vars to everyone, coop_save.lua).
-- * "Back to title" leaves the session; a client whose host is gone is told so and goes
--   back to the main menu, where the lobby shows the reason.

CoopSession = CoopSession or {}
local CS = CoopSession
local cfg = Coop.cfg

CS.TEXT = {
  en = {host_left = "The host has left the session. Back to the main menu..."},
  ru = {host_left = "Хост покинул сессию. Возврат в главное меню..."},
}
CS.HOST_LEFT_DELAY = 4   -- seconds the message stays before the menu loads

function CS.text(key)
  local lang = Coop.lang()
  local s = (CS.TEXT[lang] or CS.TEXT.en)[key] or CS.TEXT.en[key] or key
  return lang == "ru" and Coop.cp1251(s) or s
end

CS.CLIENT_HIDDEN = {["Menu.RestartWaypointGameMenu"] = true, ["Menu.RestartGameMenu"] = true}

function CS.installMenu()
  if not Menu or CS.menuHooked == Menu then return end
  CS.menuHooked = Menu
  local origMain, origVertical = Menu.MainMenu, Menu.VerticalMenu
  Menu.MainMenu = function(...)
    CS.inPauseMenu = Coop.isClient() and not Menu.isStartUpMenu
    local ok, err = pcall(origMain, ...)
    CS.inPauseMenu = false
    if not ok then Coop.log("pause menu error: " .. tostring(err)) end
  end
  Menu.VerticalMenu = function(title, options, ...)
    if CS.inPauseMenu and type(options) == "table" then
      CS.inPauseMenu = false
      for i = #options, 1, -1 do
        if CS.CLIENT_HIDDEN[options[i][2]] then table.remove(options, i) end
      end
    end
    return origVertical(title, options, ...)
  end
  -- The world goes on while the menu is open, so no "Paused" label (Menu.StartNewMenu draws
  -- it when InitMenuSys sets UsePauseMessage).
  local origInitSys = Menu.InitMenuSys
  Menu.InitMenuSys = function(...)
    local r = {origInitSys(...)}
    if Coop.inSession() then Menu.UsePauseMessage = false end
    return unpack(r)
  end
  -- Back to title: no profile save in a session (coop_save.lua), and on a client the level
  -- change must get past the client guards (level changes are otherwise the host's).
  local origBack = Menu.BackTitle
  Menu.BackTitle = function(...)
    if not Coop.inSession() then return origBack(...) end
    CS.toMenu("leave")
  end
end

-- Leave the level for the main menu; coop.lua closes the connection there.
function CS.toMenu(why)
  Coop.log("session: back to the main menu (" .. tostring(why) .. ")")
  cfg.notice = why == "host_left" and "host_left" or nil
  Coop.rearm()
  if CoopEnemies and CoopEnemies.fromHost then
    CoopEnemies.fromHost(SaveGame.LoadLevel, "menu")
  else
    SaveGame.LoadLevel("menu")
  end
end

function CS.onLeave(peer)
  if Coop.isClient() and peer == 0 and not CS.leaving then
    CS.leaving = Net.CoopTime() + CS.HOST_LEFT_DELAY
    Scorer.SetMsgText(CS.text("host_left"), Game.GetTime() + CS.HOST_LEFT_DELAY + 1)
  end
end

function CS.update()
  CS.installMenu()
  if CS.leaving and Net.CoopTime() >= CS.leaving then
    CS.leaving = false   -- once
    CS.toMenu("host_left")
  end
end
