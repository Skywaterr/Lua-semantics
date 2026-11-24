-- M8 feature test: coroutines.

-- values in both directions, status changes, running()
local co
co = coroutine.create(function(a, b)
  print("start", a, b, coroutine.status(co), coroutine.running() == co)
  local c = coroutine.yield(a + b)
  print("got", c)
  local d, e = coroutine.yield(c * 2, "two values")
  print("got", d, e)
  return "done", 99
end)
print(type(co), coroutine.status(co), coroutine.running())
print(coroutine.resume(co, 1, 2))
print(coroutine.status(co))
print(coroutine.resume(co, 10))
print(coroutine.resume(co, "x", "y"))
print(coroutine.status(co), coroutine.resume(co))

-- generators with wrap
local function range(n)
  return coroutine.wrap(function() for i = 1, n do coroutine.yield(i) end end)
end
local sum = 0
for i in range(100) do sum = sum + i end
print("sum", sum)
local function permgen(a, n)
  n = n or #a
  if n <= 1 then coroutine.yield(a) else
    for i = 1, n do
      a[n], a[i] = a[i], a[n]
      permgen(a, n - 1)
      a[n], a[i] = a[i], a[n]
    end
  end
end
for p in coroutine.wrap(function() permgen({"a", "b", "c"}) end) do io.write(table.concat(p), " ") end
print()

-- producer / consumer with a filter in between
local function producer()
  return coroutine.create(function()
    for _, w in ipairs({"alpha", "beta", "gamma"}) do coroutine.yield(w) end
  end)
end
local function filter(src)
  return coroutine.create(function()
    while true do
      local ok, w = coroutine.resume(src)
      if not w then return end
      coroutine.yield(w:upper())
    end
  end)
end
local f = filter(producer())
while true do
  local ok, w = coroutine.resume(f)
  if not w then break end
  io.write(w, " ")
end
print(coroutine.status(f))

-- locals of a suspended coroutine survive whatever runs meanwhile
local keeper = coroutine.wrap(function()
  local a, b, c = "kept a", "kept b", {n = 1}
  for round = 1, 3 do
    coroutine.yield(a .. "/" .. b .. "/" .. c.n .. "/" .. round)
    c.n = c.n + 1
  end
end)
for i = 1, 3 do
  do local x, y, z = 1, 2, 3 for j = 1, 10 do local w = j * x end end
  print(keeper())
end

-- errors: inside the coroutine, dead coroutines, wrap re-raising
local bad = coroutine.create(function() local z = nil; return z.field end)
print(coroutine.resume(bad))
print(coroutine.status(bad), coroutine.resume(bad))
local w = coroutine.wrap(function() coroutine.yield(1) end)
print(w(), w())
print(pcall(w))
print(pcall(coroutine.wrap(function() error("in wrap") end)))
local okw, ew = pcall(coroutine.wrap(function() error({code = 7}) end))
print(okw, type(ew), ew.code)
local e = select(2, coroutine.resume(coroutine.create(function() error({code = 8}) end)))
print(type(e), e.code)

-- statuses of nested coroutines
local outer
outer = coroutine.create(function()
  local inner = coroutine.create(function()
    print("inner sees outer", coroutine.status(outer))
    print(coroutine.resume(outer))
    coroutine.yield("from inner")
  end)
  print(coroutine.resume(inner))
  print("inner status", coroutine.status(inner))
  coroutine.yield("from outer")
end)
print(coroutine.resume(outer))
print(coroutine.status(outer))

-- yielding is not allowed across C boundaries in 5.1
print(pcall(coroutine.yield, 1))
print(coroutine.resume(coroutine.create(function() print(pcall(coroutine.yield, 1)) end)))
print(coroutine.resume(coroutine.create(function()
  local t = setmetatable({}, {__index = function() coroutine.yield() end})
  return t.x
end)))
print(coroutine.resume(coroutine.create(function()
  table.sort({3, 2, 1}, function(a, b) coroutine.yield() return a < b end)
end)))
print(pcall(coroutine.create, print))
print(pcall(coroutine.resume, 1))
print(coroutine.resume(coroutine.create(function(...) return select("#", ...), ... end), nil, 2, nil))
print(coroutine.resume(coroutine.create(function() return coroutine.yield() end)))
