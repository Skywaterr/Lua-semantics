-- M7 feature test: errors, positions and messages, pcall/xpcall/error/assert.
-- Every error is caught, so the program itself runs to the end.

-- runtime errors name the variable involved (global, local, upvalue, field,
-- method) and carry the position of the failing statement
local t = nil
print(pcall(function() return t.x end))
print(pcall(function() local a = {} return a.b.c end))
print(pcall(function() undefinedfn() end))
print(pcall(function() local o = {} o:nomethod() end))
print(pcall(function() local q = {} return q[1].x end))
print(pcall(function() local q = {} q["key"]() end))
print(pcall(function() x.y.z = 1 end))
print(pcall(function() local a; a.b = 1 end))
print(pcall(function() return 1 + {} end))
print(pcall(function() local n; return n * 2 end))
print(pcall(function() local s = "a" .. nil end))
print(pcall(function() return {} .. "" end))
print(pcall(function() return #nil end))
print(pcall(function() return -{} end))
print(pcall(function() return {} < {} end))
print(pcall(function() return 1 < "x" end))
print(pcall(function() return {} <= 1 end))
print(pcall(function() local up = nil; return (function() return up.field end)() end))
print(pcall(function() for i = "a", 2 do end end))
print(pcall(function() for i = 1, {} do end end))
print(pcall(function() local k = {} k[nil] = 1 end))
print(pcall(function() local k = {} k[0/0] = 1 end))
print(pcall(nil))
print(pcall({}))

-- error(): levels, non-string values, no position
local function thrower(level) error("thrown", level) end
local function caller(level) thrower(level) end
print(pcall(caller, 1))
print(pcall(caller, 2))
print(pcall(caller, 0))
print(pcall(error, "direct"))
print(pcall(error))
print(select("#", pcall(error)))
local ok, e = pcall(error, {code = 42})
print(ok, type(e), e.code)
print(pcall(error, 42))
print(pcall(function() error("msg", 3) end))

-- assert
print(pcall(assert, false, "my msg"))
print(pcall(assert, nil))
print(pcall(assert, false))
print(assert(1, 2, 3))
print(pcall(assert))
print(select("#", assert(true, nil, nil)))

-- bad arguments name the function as it was called
local r = string.rep
print(pcall(function() r() end))
print(pcall(function() ("x"):rep() end))
print(pcall(function() string.rep() end))
print(pcall(string.rep))
print(pcall(function() math.floor("a") end))
print(pcall(function() setmetatable(1, {}) end))
print(pcall(function() for k in next, nil do end end))
print(pcall(string.format, "%d", "x"))
print(pcall(function() return ("x"):bad() end))
print(pcall(function() table.insert(nil, 1) end))
print(pcall(function() ("abc"):sub({}) end))

-- pcall results, nesting, rethrowing, xpcall
print(pcall(function(...) return ... end, 1, 2, 3))
print(pcall(function() return end))
print(pcall(pcall, error, "inner"))
print(pcall(function()
  local ok, err = pcall(error, "first")
  error("rethrown: " .. err, 0)
end))
print(xpcall(function() error("x") end, function(m) return "handled: " .. m end))
print(xpcall(function() return "fine", 2 end, print))
print(xpcall(function() local z = nil; return z.w end, function(m) return string.upper(m) end))

-- errors inside metamethods and library callbacks
local mt = {__index = function(t, k) error("no field " .. k) end}
print(pcall(function() return setmetatable({}, mt).foo end))
print(pcall(table.sort, {3, 1, 2}, function(a, b) error("in comparator") end))
print(pcall(string.gsub, "abc", "%w", function(c) error("in gsub " .. c) end))

-- the state after a caught error is intact: locals, loops, break, return
local count = 0
for i = 1, 5 do
  local ok = pcall(function() if i % 2 == 0 then error("even") end end)
  if ok then count = count + 1 end
  if i == 4 then break end
end
print("count", count)
local function guarded(v)
  local ok, res = pcall(function() if v then return "value " .. v end error("missing") end)
  return ok, res
end
print(guarded(7))
print(guarded(nil))
local acc = {}
for i = 1, 3 do
  local ok, msg = pcall(function() local b = {} return b.missing.x end)
  acc[#acc + 1] = ok and "ok" or "err"
end
print(table.concat(acc, ","))
print("done")
