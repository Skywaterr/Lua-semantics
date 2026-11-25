-- For tests


-- Test 1
print("Test 1, should print 0 through 10 inclusive")
for i = 0, 10 do
    print(i)
end

-- Test 2
print("Test 2, should print up to 9.99")
for i = 0, 10, 3.33 do
    print(i)
end

-- Test 3
print("Test 3, should NOT print up to 10.02")
for i = 0, 10, 3.33 do
    print(i)
end

-- Test 4
print("Test 4, count down from 10 to 0")
for i = 10, 0, -1 do
    print(i)
end

-- Test 5
print("Test 5, shouldn't count at all, no negative step")
for i = 10, 0 do
    print(i)
end

-- Test 6
print("Test 6, decimal steps between 0.2-0.8")
for i = 0.2, 0.8, 1/10 do
    print(i)
end

-- Test 7
print("Test 7, count up to 30, breaking at 15, with a step of 3")
for i = 0, 30, 3 do
    print(i)
    if i == 15 then 
        break
    end
end
 