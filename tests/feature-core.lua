-- M2 feature test: core evaluation without user functions or table
-- constructors. Expected output comes from real Lua 5.1.5 (make generate).

-- number formatting (%.14g)
print(1, -1, 0.5, 100, 1e14, 1e15, 123456789012345, 2^53, 0.1, 1/3, -1e-5, 1e-4)
print(1e100, 1e308 * 10, -1e308 * 10, 2^-1074, 3.14159265358979, 99999999999999.5)
print(1/0, -1/0, 255, 0xff, 0X1A, .5, 5., 314.16e-2, 1E2)

-- arithmetic
print(1 + 2, 7 - 10, 6 * 7, 7 / 2, 2 ^ 10, 2 ^ 0.5, -2 ^ 2, 2 ^ -1)
print(7 % 3, -7 % 3, 7 % -3, 5.5 % 2, 2 ^ 3 ^ 2, 1 + 2 * 3 - 4 / 2)

-- string <-> number coercion
print("10" + 5, "0x10" * 1, " 3 " * 2, "1e2" / 4, 10 .. "", 1.5 .. "|", 1e15 .. "")
print(tonumber("  0x1A  "), tonumber("1e"), tonumber(" .5"), tonumber("5."), tonumber(""))
print(tonumber("0x"), tonumber("1 2"), tonumber("-0x10"), tonumber("inf"), tonumber("1e400"))
print(tonumber(42), tonumber(nil), tonumber(true), tonumber("12", 10))

-- comparison and equality
print(1 == 1.0, "1" == 1, nil == false, 1 < 2, 2 <= 2, 3 > 4, 3 >= 4, 1 ~= 2)
print("a" < "b", "Z" < "a", "" < "a", "abc" < "abd", "abc" <= "abc", "b" > "abc")
print(0/0 == 0/0, 0/0 ~= 0/0)

-- logic: and/or return an operand
print(nil and 1, false or "x", 1 and 2, nil or false, 0 and "zero is true", not nil, not 0)
print(1 or error_if_evaluated, nil and error_if_evaluated)

-- strings
print("\65\066\0677", "a\
b", "tab\tq\"\x", 'single "q"', "\\", #"abc", #"", "a" .. "b" .. "c")
print([[
first newline skipped]], [==[with ]] inside]==], #[[12345]])

-- type and tostring
print(type(1), type("s"), type(nil), type(true), type(print), type(type), type(_G))
print(tostring(1.5), tostring(nil), tostring(false), tostring("s"))

-- globals live in _G
x = 10
print(x, _G.x, _G["x"])
_G.y = 20
print(y, undefined_global)

-- locals and scope
local a = 1
do
  local a = 2
  print("inner", a)
end
print("outer", a)
local b, c, d = 1, 2
print(b, c, d)
local e = 5
local e = e + 1
print(e)

-- multiple assignment evaluates everything, then stores right to left
local p, q = 1, 2
p, q = q, p
print(p, q)
r, r = 1, 2
print(r)

-- if / elseif / else
for i = 1, 4 do
  if i == 1 then print("one")
  elseif i == 2 then print("two")
  elseif i == 3 then print("three")
  else print("other") end
end

-- while and break
local n = 0
while true do
  n = n + 1
  if n >= 5 then break end
end
print("while", n)

-- repeat: the condition sees the body's locals
local k = 0
repeat
  local done = k >= 3
  k = k + 1
until done
print("repeat", k)

-- numeric for
for i = 1, 3 do io.write(i, " ") end
for i = 3, 1, -1 do io.write(i, " ") end
for i = 0, 1, 0.25 do io.write(i, " ") end
for i = 1, 0 do io.write("never") end
for i = "1", "2" do io.write(i, " ") end
io.write("\n")
for i = 1, 10 do
  if i > 2 then break end
  io.write("b", i, " ")
end
io.write("\n")
local i = "outer i"
for i = 1, 2 do end
print(i)

-- nested loops with break only leaving the inner one
for i = 1, 3 do
  for j = 1, 3 do
    if j > i then break end
    io.write(i, j, " ")
  end
end
io.write("\n")

-- io.write formats numbers like print
io.write(1, " ", 0.1, " ", 1e15, " ", -0.5, "\n")
