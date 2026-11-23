-- M3 feature test: functions, closures, varargs, multiple results, tail
-- calls, generic for. No table constructors yet (M4), so `_G` and the vararg
-- `arg` table stand in where a table is needed.

-- definitions and recursion
function fact(n) if n <= 1 then return 1 end return n * fact(n - 1) end
print(fact(5), fact(20))
local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end
print(fib(15))
local sq = function(x) return x * x end
print(sq(7), type(sq), sq == sq, sq == fib)

-- closures and shared upvalues
local function counter()
  local n = 0
  return function() n = n + 1 return n end, function() return n end
end
local inc, get = counter()
inc() inc() inc()
print("counter", get(), inc(), get())
local inc2 = counter()
print("independent", inc2(), get())

-- each loop iteration gets a fresh local
local f1, f2, f3
for i = 1, 3 do
  local function g() return i * 10 end
  if i == 1 then f1 = g elseif i == 2 then f2 = g else f3 = g end
end
print("fresh", f1(), f2(), f3())

-- an upvalue changed after the closure was made
local v = 1
local function getv() return v end
v = 2
print("late", getv())

-- multiple results and adjustment
local function three() return 1, 2, 3 end
local function none() end
print(three())
print(three(), "end")
print((three()))
print(none())
print(none(), "x")
local a, b, c, d = three()
print(a, b, c, d)
a, b = three(), 10
print(a, b)
local x, y = (three())
print(x, y)
print(three(), three())

-- varargs
local function count(...) return select('#', ...) end
print(count(), count(nil), count(1, nil, 3), count(three()))
local function pass(...) return ... end
print(pass(1, 2, 3))
print(select(2, "a", "b", "c"), select(-1, "a", "b", "c"))
local function firstOf(...) local a = ... return a end
print(firstOf(9, 8, 7))
local function mid(...) return ..., "last" end
print(mid(1, 2))
local function withFixed(a, b, ...) return a, b, select('#', ...) end
print(withFixed(1))
print(withFixed(1, 2, 3, 4))

-- the 5.0-style `arg` table of vararg functions
local function oldStyle(...) return arg.n, arg[1], arg[2], unpack(arg) end
print(oldStyle("p", "q"))
print(unpack(arg or _G, 1, 0))

-- methods with `:` and `self`
x = 42
function _G:getx() return self.x end
function _G.twice(n) return 2 * n end
print(_G:getx(), twice(4), _G.twice(5))

-- tail calls run in constant space
local function loop(n, acc) if n == 0 then return acc end return loop(n - 1, acc + n) end
print("tail", loop(100000, 0))
local function even(n) if n == 0 then return true end return odd(n - 1) end
function odd(n) if n == 0 then return false end return even(n - 1) end
print(even(10001), odd(7))

-- generic for with an iterator function
local function squares(limit, i)
  if i < limit then return i + 1, (i + 1) * (i + 1) end
end
for i, s in squares, 4, 0 do io.write(i, ":", s, " ") end
io.write("\n")
local function range(n)
  local i = 0
  return function() i = i + 1 if i <= n then return i end end
end
for i in range(5) do
  if i == 4 then break end
  io.write(i, " ")
end
io.write("\n")

-- functions as values
local function apply(f, ...) return f(...) end
print(apply(math_missing or sq, 6), apply(three))
local function compose(f, g) return function(...) return f(g(...)) end end
print(compose(sq, sq)(3))

-- a return at the end of the main chunk
do return print("bye") end
print("not reached")
