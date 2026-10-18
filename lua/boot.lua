-- Co-op bootstrap, run by the engine's InitLuaLine after Scripts/init.lua.
-- The engine runs InitLuaLine once and then clears it, and the Lua state is rebuilt on
-- every level load. Coop.rearm() (called from the level tick) writes the line back, built
-- from COOP_CFG, which is the only Lua state that survives a level change.
--
-- InitLuaLine: COOP_DIR='<dir>/' COOP_CFG={role='host',...} dofile(COOP_DIR..'boot.lua')

function COOP_SERIALIZE(v)
  if type(v) == "table" then
    local parts = {}
    for k, x in pairs(v) do
      -- List items (trigargs={'Cole'}) need [n]= keys: "1='Cole'" does not parse.
      local key = type(k) == "number" and "[" .. k .. "]" or k
      parts[#parts + 1] = key .. "=" .. COOP_SERIALIZE(x)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(v) == "string" then
    return "'" .. string.gsub(string.gsub(v, "\\", "\\\\"), "'", "\\'") .. "'"
  end
  return tostring(v)
end

function COOP_BOOT_LINE()
  return "COOP_DIR='" .. COOP_DIR .. "' COOP_CFG=" .. COOP_SERIALIZE(COOP_CFG) ..
         " dofile(COOP_DIR..'boot.lua')"
end

COOP_CFG = COOP_CFG or {}

local ok, err = pcall(dofile, COOP_DIR .. "coop.lua")
if not ok then
  Net.CoopLog("boot error: " .. tostring(err))
  print("COOP boot error: " .. tostring(err))
end
