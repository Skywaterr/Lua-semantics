-- For any arithmetic operation applied to a string,
-- Lua tries to coerce the string into a number.
-- The reverse is also true when a number is used wherever
-- a string is expected. The number is converted to a string.
-- Coercion happens at runtime


-- Test 1
print("Printing a number", 1)

-- Test 2
print("Printing the addition of two integers", "1" + "1")

-- Test 3
print("Printing the subtraction of two floats", "1.1" - "1.0")

-- Test 4
print("Concatenating 1 and 2", 1 .. 2)

-- Test 5
some_string = 1 .. 2 .. 3 .. 4 .. 5 .. 6 .. 7 .. 8 .. 9 .. 0
print("Indices of substring 234567 in the string 1234567890", string.find(some_string, 234567))

-- Test 6
some_string = 1 + 2 .. 3 + 4 .. 5 + 6 .. 7 + 8 .. 9 + 0
print(string.format("The output of 1 + 2 .. 3 + 4 .. 5 + 6 .. 7 + 8 .. 9 + 0: %d", some_string))