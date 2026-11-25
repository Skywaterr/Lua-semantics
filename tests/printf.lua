-- an implementation of printf

function printf(...)
 io.write(string.format(...))
end

printf("Hello %s from %s", "World", "Lua 5.1")
