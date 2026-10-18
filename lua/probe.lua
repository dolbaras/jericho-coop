-- Probe what the game's Lua environment offers. Loaded with dofile from InitLuaLine.
local function p(...) print("PROBE", ...) end

p("version", _VERSION)
for _, name in ipairs({"io", "os", "string", "table", "math", "debug", "coroutine", "package"}) do
  p("lib", name, type(_G[name]))
end
for _, name in ipairs({"dofile", "loadstring", "loadfile", "require", "pcall", "setfenv", "getfenv"}) do
  p("fn", name, type(_G[name]))
end
if io and io.open then
  local f = io.open("probe_io.txt", "w")
  p("io.open", f ~= nil)
  if f then f:write("ok\n") f:close() end
end
if os and os.clock then p("os.clock", os.clock()) end

-- Engine tables and their functions.
local engine = {}
for k, v in pairs(_G) do
  if type(v) == "table" and k ~= "_G" then
    local n, fns = 0, {}
    for fk, fv in pairs(v) do
      if type(fv) == "function" then n = n + 1 fns[#fns + 1] = fk end
    end
    table.sort(fns)
    engine[#engine + 1] = k .. "(" .. n .. "): " .. table.concat(fns, " ")
  end
end
table.sort(engine)
for _, line in ipairs(engine) do p("table", line) end
p("done")
