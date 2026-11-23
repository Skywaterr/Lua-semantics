-- M5 feature test: the string library, patterns and string.format.

-- basics and method syntax
local s = "Hello, World"
print(#s, s:len(), string.len(123), s:upper(), s:lower(), s:reverse())
print(s:sub(1, 5), s:sub(-5), s:sub(8), s:sub(0), s:sub(5, 2), s:sub(-100, 3), s:sub(3, 100))
print(s:byte(), s:byte(1, 3), s:byte(-1), s:byte(100), string.char(72, 105, 33), string.char())
print(("ab"):rep(3), ("x"):rep(0), ("-"):rep(-1), ("abc"):rep(2) .. "!")
print(("%d items"):format(3), ("x"):len())

-- string.format
print(string.format("%d %i %5d %-5d| %05d %+d % d %.3d", 42, -7, 42, 42, 42, 42, 42, 7))
print(string.format("%x %X %#x %o %#o %u %c%c", 255, 255, 255, 8, 8, 3000000000, 76, 117))
print(string.format("%f %.2f %10.3f %-10.1f| %+.1f %.0f %.0f %.0f %#.0f", 3.14159, 2.675, 1/3, 2.5, 1, 0.5, 1.5, 2.5, 3))
print(string.format("%e %.2E %.0e %10.3e", 12345.678, 0.000123, 5, -1/3))
print(string.format("%g %g %g %g %g %g %G", 100000, 1000000, 1e-5, 0.0001, 1/3, 2^60, 1e-10))
local z = 0  -- negative zero made at run time (a literal -0.0 shares 0's constant slot)
print(string.format("%.3g %.10g %#g %g %g %f", math.pi, math.pi, 1, 0, -z, -z))
print(string.format("%s %10s %-10s| %.3s %5.1s|", "str", "right", "left", "truncate", "xyz"))
print(string.format("%s %s %s", 1, 1.5, 1e20))
print(string.format("%q", 'a "quoted"\n\\ string\0end\r'))
print(string.format("%5.1f%%", 99.44), string.format("no specs"), string.format("%5s|%-5s|", 1, 2))
print(string.format("%g %g %f", 1/0, -1/0, 1/0))

-- find
print(s:find("World"), s:find("o"), s:find("o", 6), s:find("o", -3), s:find("xyz"))
print(s:find("l+"), s:find("(o)(r)"), s:find(".", 1, true), s:find("", 3), s:find("^H"), s:find("^W"))
print(("a.b.c"):find(".", 2, true), ("a+b"):find("+", 1, true), ("[x]"):find("[", 1, true))

-- match and captures
print(("key = value"):match("(%w+)%s*=%s*(%w+)"))
print(("2024-01-15"):match("(%d+)-(%d+)-(%d+)"))
print(("  trim me  "):match("^%s*(.-)%s*$") .. "|")
print(("hello"):match("()ll()"), ("hello"):match("l*"), ("hello"):match(".-l"), ("hello"):match(".*l"))
print(("abc123def"):match("%a+"), ("abc123def"):match("%d+"), ("abc123def"):match("[%d]+", 4))
print(("x = 10"):match("^(%a)%s*=%s*(%d+)$"), ("no match"):match("%d"))
print(("THE (quick) fox"):match("%((%a+)%)"), ("f(a(b)c)d"):match("%b()"))
print(("hello world"):match("%f[%w]%w+", 2), ("aXb"):match("%u"), ("aXb"):match("%U+"))
print(("abcabc"):match("(abc)%1"), ("abab"):match("(a)(b)%1%2"), ("a,b;c"):match("[,;]"))
print(("x-y"):match("[a-z]-[a-z]"), ("1+1=2"):match("[^%d]"), ("tab\there"):match("%c"))
print(("punct!?"):match("%p+"), ("0x1F"):match("%x+", 3), ("A1_"):match("[%w_]+"))
print(("aaa"):match("a?a?a?a"), ("ab"):match("a-b"), ("ab"):match("^(a?)(b)$"))

-- gmatch
for w in ("one two  three"):gmatch("%a+") do io.write("[", w, "]") end print()
for k, v in ("a=1, b=2, c=3"):gmatch("(%w+)=(%w+)") do io.write(k, ":", v, " ") end print()
for p in ("abc"):gmatch("()") do io.write(p, " ") end print()
local count = 0 for _ in string.gfind("aaa", "a") do count = count + 1 end print("gfind", count)

-- gsub
print(("hello world"):gsub("o", "0"))
print(("hello world"):gsub("(%w+)", "<%1>"))
print(("hello world"):gsub("%w+", "%0 %0", 1))
print(("hello"):gsub("", "-"))
print(("abc"):gsub(".", {a = "1", b = false}))
print(("abc"):gsub("%w", function(c) if c ~= "b" then return c:upper() end end))
print(("x = 1, y = 2"):gsub("(%w+) = (%w+)", "%2 = %1"))
print(("$name is $age"):gsub("%$(%w+)", {name = "Ann", age = 30}))
print(("aaa"):gsub("^a", "b"), ("50%"):gsub("%%", " percent"), ("a.b"):gsub("%.", "%%"))
print(("one two"):gsub("(%w+)", "%1", 0), ("abc"):gsub("b*", "X"))
print(string.gsub("hello", "l", function() return nil end))

-- numbers are accepted where strings are expected, and vice versa
print(string.rep(5, 3), string.upper(1.5), ("10"):rep("2"), string.sub(12345, 2, 3))
