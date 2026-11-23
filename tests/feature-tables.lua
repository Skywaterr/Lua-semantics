-- M4 feature test: table constructors, length, traversal, the table library
-- and basic math. Traversal order over non-sequence keys is hash-dependent
-- in Lua, so those keys are sorted before printing.

local function keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = tostring(k) end
  table.sort(ks)
  return table.concat(ks, " ")
end

-- constructors
local t = {10, 20, 30; x = 1, ["y z"] = 2, [100] = 3,}
print(t[1], t[2], t[3], t.x, t["y z"], t[100], #t)
print(keys(t))
local function three() return 1, 2, 3 end
print(#{three()}, #{three(), three()}, #{(three())}, #{three(), 10})
local function va(...) return {...}, {..., "end"} end
local a, b = va("p", "q")
print(#a, a[1], a[2], #b, b[1], b[2])
local nested = {{1, 2}, {3, {4}}}
print(nested[2][2][1], #nested, #nested[1])
print(#{}, #{nil}, #{1, nil, 3}, #{nil, nil, 3}, #{1, 2, nil}, #{n = 1})
local dup = {[1] = "keyed", "positional"}
print(dup[1])

-- keys: numbers are equal by value, -0 is 0, tables by identity
-- (A literal -0 would also turn later literal 0s into -0 in lua, through its
-- constant table, so negative zero is made at run time here.)
local k = {}
local z = 0
k[1] = "one" k[1.0] = "one again" k[-z] = "zero" k[0] = "zero again"
k["1"] = "string one"
print(k[1], k[0], k[-z], k["1"])
local t1, t2 = {}, {}
k[t1] = "t1" k[t2] = "t2"
print(k[t1], k[t2], t1 == t2, t1 == t1)
k[print] = "fn" print(k[print])
k[true] = "yes" print(k[true], k[false])

-- assigning nil removes a key
local r = {a = 1, b = 2}
r.a = nil
print(r.a, keys(r))

-- length of a sequence while growing and shrinking
local s = {}
for i = 1, 10 do s[i] = i * i end
print(#s, s[10])
s[#s] = nil s[#s] = nil
print(#s)

-- pairs, ipairs, next
local seq = {"a", "b", "c", nil, "e"}
for i, v in ipairs(seq) do io.write(i, "=", v, " ") end print()
local n = 0 for _ in pairs({1, 2, 3, x = 4, y = 5}) do n = n + 1 end print("pairs count", n)
for i, v in pairs({"x", "y", "z"}) do io.write(i, v, " ") end print()
print(next({}), next({7}))
local tk = {a = 1, b = 2, c = 3}
for key in pairs(tk) do tk[key] = nil end
print("cleared during traversal", next(tk))

-- table library
local l = {"b", "d"}
table.insert(l, "e") table.insert(l, 1, "a") table.insert(l, 3, "c")
print(table.concat(l, ","), table.getn(l), #l)
print(table.remove(l), table.remove(l, 1), table.concat(l, ","))
print(table.remove({}), table.concat({}), table.concat({1, 2.5, "x"}, "-"), table.concat({1, 2, 3, 4}, ":", 2, 3))
print(table.maxn({1, 2, [10] = 1, [3.5] = 1}), table.maxn({}))
table.foreachi({"x", "y"}, function(i, v) io.write(i, v, " ") end) print()
print(table.foreach({5}, function(k, v) return k + v end))
print(unpack({1, 2, 3})) print(unpack({1, 2, 3}, 2)) print(unpack({1, 2, 3}, 2, 5))

-- sort: default order, comparators, and the order of ties (Lua's quicksort)
local nums = {5, 2, 8, 1, 9, 3, 7, 4, 6, 0}
table.sort(nums) print(table.concat(nums, " "))
table.sort(nums, function(x, y) return x > y end) print(table.concat(nums, " "))
local words = {"pear", "Apple", "fig", "banana", "kiwi"}
table.sort(words) print(table.concat(words, " "))
local recs = {}
for i = 1, 12 do recs[i] = {id = i, g = i % 3} end
table.sort(recs, function(x, y) return x.g < y.g end)
for _, rec in ipairs(recs) do io.write(rec.id, " ") end print()
local one = {42} table.sort(one) print(one[1])

-- math basics
print(math.floor(3.7), math.ceil(3.2), math.abs(-4), math.max(1, 5, 3), math.min(2, -1))
print(math.fmod(7, 3), math.fmod(-7, 3), math.mod(5.5, 2), math.pow(2, 10), math.sqrt(16))
print(math.huge, -math.huge, math.pi, math.exp(0), math.log(1), math.sin(0), math.cos(0))
print(math.random(1, 1), math.random(10) <= 10, math.random() < 1)
math.randomseed(7) local r1 = math.random(1000)
math.randomseed(7) print(r1 == math.random(1000), r1)

-- the script's arguments
print(arg[0], type(arg[-1]), #arg)
