-- M6 feature test: metatables, metamethods and function environments.

-- __index: a table, a function, and chains of them
local defaults = {color = "red", size = 1}
local obj = setmetatable({size = 5}, {__index = defaults})
print(obj.size, obj.color, obj.missing, rawget(obj, "color"))
local calc = setmetatable({}, {__index = function(t, k) return k .. "!" end})
print(calc.hello, calc[42], rawget(calc, "hello"))
local base = setmetatable({}, {__index = {deep = "found"}})
local mid = setmetatable({}, {__index = base})
local top = setmetatable({}, {__index = mid})
print(top.deep, top.nothing)

-- __newindex: a function, a table, and rawset bypassing it
local log = {}
local watched = setmetatable({}, {__newindex = function(t, k, v) log[#log + 1] = k .. "=" .. tostring(v) rawset(t, k, v) end})
watched.a = 1 watched.b = 2 watched.a = 10   -- the last one finds a, so no call
print(table.concat(log, " "), watched.a, watched.b)
local store = {}
local proxy = setmetatable({}, {__newindex = store, __index = store})
proxy.x = "via proxy"
print(rawget(proxy, "x"), store.x, proxy.x)
rawset(proxy, "y", "raw") print(rawget(proxy, "y"), store.y)

-- OOP with inheritance
local Account = {}
Account.__index = Account
function Account.new(balance) return setmetatable({balance = balance}, Account) end
function Account:deposit(v) self.balance = self.balance + v return self end
function Account:show() return "balance " .. self.balance end
local Savings = setmetatable({}, {__index = Account})
Savings.__index = Savings
function Savings.new(balance) local s = Account.new(balance) return setmetatable(s, Savings) end
function Savings:show() return "savings " .. Account.show(self) end
local acc = Account.new(100):deposit(50)
local sav = Savings.new(10):deposit(5)
print(acc:show(), sav:show(), getmetatable(sav) == Savings)

-- arithmetic metamethods, from either side
local V = {}
V.__index = V
local function vec(x, y) return setmetatable({x = x, y = y}, V) end
V.__add = function(a, b) return vec(a.x + b.x, a.y + b.y) end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y) end
V.__mul = function(a, b)
  if type(a) == "number" then return vec(a * b.x, a * b.y) end
  if type(b) == "number" then return vec(a.x * b, a.y * b) end
  return a.x * b.x + a.y * b.y
end
V.__div = function(a, b) return vec(a.x / b, a.y / b) end
V.__mod = function(a, b) return "mod" end
V.__pow = function(a, b) return "pow" end
V.__unm = function(a) return vec(-a.x, -a.y) end
V.__tostring = function(v) return "(" .. v.x .. ", " .. v.y .. ")" end
V.__concat = function(a, b) return tostring(a) .. "|" .. tostring(b) end
local p, q = vec(1, 2), vec(3, 4)
print(tostring(p + q), tostring(q - p), p * q, tostring(2 * p), tostring(p * 3), tostring(q / 2))
print(p % q, p ^ 2, tostring(-p))
print(p .. q, p .. "s", "s" .. q, 1 .. p)
print(p, q)   -- print uses tostring, so __tostring

-- __eq: only for two tables sharing the metamethod
local E = {__eq = function(a, b) return a.id == b.id end}
local e1, e2, e3 = setmetatable({id = 1}, E), setmetatable({id = 1}, E), setmetatable({id = 2}, E)
local other = setmetatable({id = 1}, {__eq = function() return true end})
print(e1 == e2, e1 == e3, e1 ~= e3, e1 == other, rawequal(e1, e2), e1 == 1)

-- __lt and __le, and `<=` falling back to `not (b < a)`
local L = {__lt = function(a, b) return a.n < b.n end}
local l1, l2 = setmetatable({n = 1}, L), setmetatable({n = 2}, L)
print(l1 < l2, l2 < l1, l1 > l2, l1 <= l2, l2 >= l1, l1 <= l1)
local LE = {__lt = function(a, b) return a.n < b.n end, __le = function(a, b) return "le called" end}
local m1, m2 = setmetatable({n = 1}, LE), setmetatable({n = 2}, LE)
print(m1 <= m2, m2 >= m1)

-- __call
local callable = setmetatable({name = "c"}, {__call = function(self, a, b) return self.name, a + b end})
print(callable(2, 3))
local function tailcalls() return callable(10, 20) end
print(tailcalls())

-- __tostring with tostring, and __metatable protection
local hidden = setmetatable({}, {__metatable = "locked", __tostring = function() return "hidden!" end})
print(tostring(hidden), getmetatable(hidden))
print(getmetatable({}), getmetatable(1), getmetatable("abc").__index == string, ("x"):rep(2))

-- environments
print(getfenv() == _G, getfenv(0) == _G, getfenv(1) == _G, getfenv(print) == _G)
local sandbox = {print = print, tostring = tostring}
local function sandboxed() x_in_sandbox = 42 return x_in_sandbox end
setfenv(sandboxed, sandbox)
print(sandboxed(), sandbox.x_in_sandbox, rawget(_G, "x_in_sandbox"), getfenv(sandboxed) == sandbox)
local function selfSandbox()
  setfenv(1, {print = print})
  y_global = "inside"
  return y_global
end
print(selfSandbox(), y_global)
local function maker() return function() return z_value end end
local env2 = {z_value = "from env2"}
setfenv(maker, env2)
print(maker()(), z_value)
local function level2() return getfenv(2) end
-- (not `return level2()`: a tail call would lose caller's frame, and
-- getfenv(2) would be an error, as in lua)
local function caller() local e = level2() return e end
setfenv(caller, {getfenv = getfenv})
print(getfenv(caller) == caller() or "different")
local function inner() return getfenv(2) == _G end
print(inner())

-- a default for undefined globals, then logging global assignments
setmetatable(getfenv(), {__index = function(t, k) return "<" .. k .. ">" end})
print(undefined_one, undefined_two)
local assigned = {}
setmetatable(getfenv(), {__newindex = function(t, k, v) assigned[#assigned + 1] = k rawset(t, k, v) end})
new_global_a = 1 new_global_b = 2 new_global_a = 3
print(table.concat(assigned, ","), new_global_a, new_global_b)
