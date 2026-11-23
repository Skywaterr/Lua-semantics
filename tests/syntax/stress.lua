-- Grammar stress test: every Lua 5.1 syntactic form, for `make parse`.
-- It is valid Lua (`luac -p` accepts it) but is not meant to be run.

--[[ long comment
spanning lines ]] x = 1
--[==[ level-2 comment with ]] and ]=] inside ]==]
--[ not a long comment
--[= also not a long comment
--

-- numerals
local n1, n2, n3, n4, n5, n6, n7 = 3, 3.0, 3.1416, 314.16e-2, 0.31416E1, 0xff, 0X56
local n8, n9, n10 = .5, 5., 1e10

-- strings and escapes
local s1 = "double \"quoted\" \\ \n \t \065\66\0067 \
continued"
local s2 = 'single \'quoted\' "ok"'
local s3 = [[long
string with "quotes" and ]] .. [[second]]
local s4 = [=[level 1 with ]] inside]=]
local s5 = [==[level 2 with ]=] and ]] inside]==]
local s6 = [====[level 4]====]
local s7 = ""

-- assignment forms
a = 1
a, b, c = 1, 2
a.b.c = 3
a[1], a["k"], a.b[c].d = 1, 2, 3
local l1
local l2, l3 = 1
local function lf(...) return ... end

-- calls
print("x")
print "x"
print [[x]]
print {1, 2}
f(a)(b)(c)
a.b.c:d("x")
a:b"x":c{1}
;("s"):rep(2)   -- the `;` is required: Lua and this grammar both reject it otherwise
f()
local _ = (f())

-- function definitions
function g() end
function g.h.i(a, b) return a + b end
function g.h:m(...) return self, ... end
local anon = function(x, y, ...) return x end
local v = function(...) return select('#', ...) end

-- control flow
do local inner = 1 end
while a do break end
repeat local r = 1 until r == 1
if a then elseif b then elseif c then else end
if a then x = 1 end
if a then x = 1 else x = 2 end
for i = 1, 10 do end
for i = 10, 1, -1 do end
for k, v in pairs(t) do end
for k in next, t do end

-- semicolons
x = 1; y = 2;
do return end
do return; end
do return 1, 2 end
do return f() end
while true do break; end

-- tables
local t1 = {}
local t2 = {1, 2, 3}
local t3 = {x = 1, y = 2,}
local t4 = {[1] = "a"; [f(x)] = "b"; "c", g = function() end}
local t5 = {{}, {{}}, f(), ...}
local t6 = {1; 2; 3;}

-- operators and precedence
x = a or b and c
x = not a == b
x = a < b and b <= c or c > d and d >= e or e ~= f or f == g
x = a .. b .. c
x = 1 + 2 - 3 * 4 / 5 % 6
x = -2 ^ 2
x = 2 ^ -3
x = 2 ^ 3 ^ 2
x = #t + -x - - y
x = not not a
x = (a + b) * c
x = ...
x = nil, true, false

return t1
