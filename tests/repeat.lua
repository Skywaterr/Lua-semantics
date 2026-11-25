-- Repeat tests


-- Test 1
print("a = 0, repeating until a == 10")
a = 0
repeat
    a = a + 5
until a == 10
print(string.format("a = %d", a))


-- Test 2
print("b = 0, repeatedly add 3 until b > 10")
b = 0
repeat
    b = b + 3
until b > 10
print(string.format("b = %d", b))


-- Test 3
print("c = 0, repeating until c < -15")
c = 0
repeat
    c = c - 3
until c < -15
print(string.format("c = %d", c))