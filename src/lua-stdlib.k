// The standard library: the initial global table and library functions.
// The base library so far (print, io.write, tostring, tonumber, type,
// select, unpack, _VERSION) and the initial global table; table, math and
// string live in lua-table.k, lua-math.k and lua-string.k. The rest arrives with later
// milestones (see ROADMAP.md).

requires "lua-string.k"

module LUA-STDLIB
  imports LUA-STRING

  // Tables 0-6: _G, io, table, math, arg (the interpreter name at -1 and
  // the script name at 0, as lua.c sets it up), string, and the metatable
  // of strings.
  rule <k> #init => .K ...</k>
       <args> Script </args>
       <tables> _ => 0 |-> #tbl(#globals, 0, nil)
                     1 |-> #tbl("write" |-> builtin("io.write"), 0, nil)
                     2 |-> #tbl(#tableLib, 0, nil)
                     3 |-> #tbl(#mathLib, 0, nil)
                     4 |-> #tbl((-1.0 |-> "lua" 0.0 |-> Script), 0, nil)
                     5 |-> #tbl(#stringLib, 0, nil)
                     6 |-> #tbl("__index" |-> tref(5), 0, nil)
       </tables>
       <nextTable> _ => 7 </nextTable>

  syntax Map ::= "#globals" [function, total]
  rule #globals =>
         "_G"       |-> tref(0)
         "_VERSION" |-> "Lua 5.1"
         "arg"      |-> tref(4)
         "io"       |-> tref(1)
         "getfenv"  |-> builtin("getfenv")
         "getmetatable" |-> builtin("getmetatable")
         "ipairs"   |-> builtin("ipairs")
         "math"     |-> tref(3)
         "next"     |-> builtin("next")
         "pairs"    |-> builtin("pairs")
         "print"    |-> builtin("print")
         "rawequal" |-> builtin("rawequal")
         "rawget"   |-> builtin("rawget")
         "rawset"   |-> builtin("rawset")
         "select"   |-> builtin("select")
         "setfenv"  |-> builtin("setfenv")
         "setmetatable" |-> builtin("setmetatable")
         "string"   |-> tref(5)
         "table"    |-> tref(2)
         "tonumber" |-> builtin("tonumber")
         "tostring" |-> builtin("tostring")
         "type"     |-> builtin("type")
         "unpack"   |-> builtin("unpack")

  // ------------------------------------------------------------ tostring
  // Addresses are made up (they differ between runs in lua too).
  syntax String ::= #tostr(Val) [function, total]
  rule #tostr(nil)        => "nil"
  rule #tostr(true)       => "true"
  rule #tostr(false)      => "false"
  rule #tostr(F:Float)    => #num2str(F)
  rule #tostr(S:String)   => S
  rule #tostr(tref(I))    => "table: 0x" +String #hex8(I +Int 1)
  rule #tostr(builtin(N)) => "function: builtin: " +String N
  rule #tostr(closure(I)) => "function: 0x" +String #hex8(I +Int 268435457)
  rule #tostr(gmatchIter(I)) => "function: 0x" +String #hex8(I +Int 268435457)

  syntax String ::= #hex8(Int) [function, total]
  rule #hex8(I) => #rep("0", 8 -Int lengthString(Base2String(I, 16))) +String Base2String(I, 16)

  // --------------------------------------------------------------- print
  syntax String ::= #joinTostr(List) [function, total]
  rule #joinTostr(ListItem(V:Val)) => #tostr(V)
  rule #joinTostr(ListItem(V:Val) L) => #tostr(V) +String "\t" +String #joinTostr(L)
    requires L =/=K .List
  rule #joinTostr(_) => "" [owise]

  // print calls the global `tostring` (looked up in the thread's globals,
  // as lua_getglobal does) on each argument and writes the results.
  syntax KItem ::= #print(List, Bool) | #printOne(List) | #printWrite(List)
  rule <k> #apply(builtin("print"), Args) => #print(Args, true) ...</k>
  rule <k> #print(.List, _) => #output("\n") ~> #vals(.List) ...</k>
  rule <k> #print(ListItem(V:Val) L, First) => #index(G, "tostring") ~> #printOne(ListItem(V))
           ~> #printWrite(ListItem(First) L) ...</k>
       <threadEnv> G </threadEnv>
  rule <k> F:Val ~> #printOne(Arg) => #apply(F, Arg) ~> #first ...</k>
  rule <k> S:Val ~> #printWrite(ListItem(First:Bool) L)
        => #output(#if First #then "" #else "\t" #fi +String {#tostringCoerce(S)}:>String) ~> #print(L, false) ...</k>
    requires #tostringCoerce(S) =/=K nil
  rule <k> S:Val ~> #printWrite(_) => #error("'tostring' must return a string to 'print'") ...</k>
    requires #tostringCoerce(S) ==K nil

  // ------------------------------------------------------------ io.write
  // Strings are written as they are, numbers with %.14g; anything else is
  // an error.
  syntax KItem ::= #writeAll(List, Int)
  rule <k> #apply(builtin("io.write"), Args) => #writeAll(Args, 1) ...</k>
  rule <k> #writeAll(ListItem(V:Val) L, N) => #output({#tostringCoerce(V)}:>String) ~> #writeAll(L, N +Int 1) ...</k>
    requires #tostringCoerce(V) =/=K nil
  rule <k> #writeAll(ListItem(V:Val) _, N)
        => #error("bad argument #" +String Int2String(N) +String " to 'write' (string expected, got "
                  +String #type(V) +String ")") ...</k>
    requires #tostringCoerce(V) ==K nil
  rule <k> #writeAll(.List, _) => #vals(.List) ...</k>

  // ------------------------------------------------- type, tostring, tonumber
  rule <k> #apply(builtin("type"), ListItem(V:Val) _) => #vals(ListItem(#type(V))) ...</k>
  // tostring uses __tostring if there is one (returning whatever it returns).
  syntax KItem ::= #tostringTM(Val)
  rule <k> #apply(builtin("tostring"), ListItem(V:Val) _) => #getTM(V, "__tostring") ~> #tostringTM(V) ...</k>
  rule <k> nil ~> #tostringTM(V) => #vals(ListItem(#tostr(V))) ...</k>
  rule <k> H:Val ~> #tostringTM(V) => #apply(H, ListItem(V)) ~> #first ~> #toVals ...</k> requires H =/=K nil
  rule <k> #apply(builtin("tonumber"), ListItem(V:Val)) => #vals(ListItem(#tonumber(V))) ...</k>
  rule <k> #apply(builtin("tonumber"), ListItem(V:Val) ListItem(10.0)) => #vals(ListItem(#tonumber(V))) ...</k>
  rule <k> #apply(builtin(N), .List) => #error("bad argument #1 to '" +String N +String "' (value expected)") ...</k>
    requires N ==String "type" orBool N ==String "tostring" orBool N ==String "tonumber"

  // -------------------------------------------------------------- select
  // select('#', ...) counts; select(n, ...) returns the arguments from the
  // n-th on, counting from the end if n < 0 (lbaselib.c luaB_select).
  syntax KItem ::= #select(Val, List)
  rule <k> #apply(builtin("select"), ListItem(S:String) Rest) => #vals(ListItem(Int2Float(size(Rest), 53, 11))) ...</k>
    requires #startsWith(S, "#")
  rule <k> #apply(builtin("select"), ListItem(N:Val) Rest) => #select(#tonumber(N), Rest) ...</k>
    requires notBool (isString(N) andBool #startsWith({N}:>String, "#"))
  rule <k> #apply(builtin("select"), .List) => #error("bad argument #1 to 'select' (number expected, got no value)") ...</k>
  rule <k> #select(F:Float, Rest) => #vals(#drop(#selectIndex(#truncInt(F), size(Rest) +Int 1) -Int 1, Rest)) ...</k>
    requires #selectIndex(#truncInt(F), size(Rest) +Int 1) >=Int 1
  rule <k> #select(_:Float, _) => #error("bad argument #1 to 'select' (index out of range)") ...</k> [owise]
  rule <k> #select(nil, _) => #error("bad argument #1 to 'select' (number expected)") ...</k>

  syntax Int ::= #selectIndex(Int, Int) [function, total]
  rule #selectIndex(I, N) => N +Int I requires I <Int 0
  rule #selectIndex(I, N) => N requires I >Int N
  rule #selectIndex(I, _) => I [owise]

  // -------------------------------------------------------------- unpack
  // unpack(t [, i [, j]]) returns t[i], ..., t[j]; i defaults to 1, j to #t.
  syntax KItem ::= #unpack(Map, Int, Val, Val)
  rule <k> #apply(builtin("unpack"), ListItem(tref(T)) Rest)
        => #unpack(M, A, #head(Rest), #head(#tail(Rest))) ...</k>
       <tables> ... T |-> #tbl(M, A, _) ... </tables>
  rule <k> #apply(builtin("unpack"), ListItem(V:Val) _)
        => #error("bad argument #1 to 'unpack' (table expected, got " +String #type(V) +String ")") ...</k>
    requires notBool isTRef(V)
  rule <k> #unpack(M, A, nil, J) => #unpack(M, A, 1.0, J) ...</k>
  rule <k> #unpack(M, A, I:Float, nil) => #unpack(M, A, I, #lenF(M, A)) ...</k>
  rule <k> #unpack(M, _, I:Float, J:Float) => #vals(#range(M, #truncInt(I), #truncInt(J))) ...</k>

  syntax List ::= #range(Map, Int, Int) [function, total]
  rule #range(M, I, J) => ListItem(#rawget(M, Int2Float(I, 53, 11))) #range(M, I +Int 1, J) requires I <=Int J
  rule #range(_, _, _) => .List [owise]

  // ======================================================= metatables
  // setmetatable(t, mt): t a table, mt nil or a table; refused if the
  // current metatable has a __metatable field. Returns t.
  syntax KItem ::= #setmt(Int, Val, Val)
  rule <k> #apply(builtin("setmetatable"), ListItem(tref(T)) ListItem(MT:Val) _)
        => #tmFrom(Old, "__metatable") ~> #setmt(T, MT, Old) ...</k>
       <tables> ... T |-> #tbl(_, _, Old) ... </tables>
    requires MT ==K nil orBool isTRef(MT)
  rule <k> P:Val ~> #setmt(T, MT, _) => #vals(ListItem(tref(T))) ...</k>
       <tables> ... T |-> #tbl(_, _, (_ => MT)) ... </tables>
    requires P ==K nil
  rule <k> P:Val ~> #setmt(_, _, _) => #error("cannot change a protected metatable") ...</k> requires P =/=K nil
  rule <k> #apply(builtin("setmetatable"), ListItem(V:Val) _) => #argError(1, "setmetatable", "table", V) ...</k>
    requires notBool isTRef(V)
  rule <k> #apply(builtin("setmetatable"), ListItem(tref(_)) Rest)
        => #error("bad argument #2 to 'setmetatable' (nil or table expected)") ...</k>
    requires notBool (#head(Rest) ==K nil orBool isTRef(#head(Rest))) orBool Rest ==K .List

  // getmetatable(v): the __metatable field if the metatable has one.
  syntax KItem ::= #getmt(Val) | #getmt2(Val)
  rule <k> #apply(builtin("getmetatable"), ListItem(V:Val) _) => #metaOf(V) ~> #getmt(nil) ...</k>
  rule <k> nil ~> #getmt(nil) => #vals(ListItem(nil)) ...</k>
  rule <k> MT:Val ~> #getmt(nil) => #tmFrom(MT, "__metatable") ~> #getmt2(MT) ...</k> requires MT =/=K nil
  rule <k> nil ~> #getmt2(MT) => #vals(ListItem(MT)) ...</k>
  rule <k> P:Val ~> #getmt2(_) => #vals(ListItem(P)) ...</k> requires P =/=K nil
  rule <k> #apply(builtin("getmetatable"), .List) => #error("bad argument #1 to 'getmetatable' (value expected)") ...</k>

  // ======================================================= raw access
  rule <k> #apply(builtin("rawget"), ListItem(tref(T)) ListItem(K:Val) _) => #vals(ListItem(#rawget(M, K))) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  rule <k> #apply(builtin("rawset"), ListItem(tref(T)) ListItem(K:Val) ListItem(V:Val) _)
        => #rawsetT(T, K, V) ~> #vals(ListItem(tref(T))) ...</k>
  rule <k> #apply(builtin(N), ListItem(V:Val) _) => #argError(1, N, "table", V) ...</k>
    requires (N ==String "rawget" orBool N ==String "rawset") andBool notBool isTRef(V)
  rule <k> #apply(builtin("rawequal"), ListItem(A:Val) ListItem(B:Val) _) => #vals(ListItem(#rawEq(A, B))) ...</k>

  // ======================================================= environments
  // getfenv(f) / setfenv(f, t): f is a function or a stack level (1, the
  // default for getfenv, is the function calling getfenv). Level 0 is the
  // thread's environment. Library functions have the thread's environment
  // and cannot be changed.
  //
  // Levels follow lua_getstack: count frames from the innermost, where a
  // frame that replaced N tail calls stands for N more (lost) levels.
  syntax LevelRes ::= #lvlFrame(Frame) | "#lvlLost" | "#lvlInvalid"
  syntax LevelRes ::= #level(List, Int) [function, total]
  rule #level(ListItem(F:Frame) _, 0) => #lvlFrame(F)
  rule #level(ListItem(#frame(_, T)) Rest, L) => #level(Rest, L -Int 1 -Int T) requires L >Int 0
  rule #level(_, L) => #lvlLost requires L <Int 0
  rule #level(_, _) => #lvlInvalid [owise]

  syntax KItem ::= #fenvOf(Val) | #levelFn(LevelRes, String, Int)
  rule <k> #fenvOf(closure(I)) => #vals(ListItem(FE)) ...</k> <funcs> ... I |-> #fun(_, _, _, _, _, FE) ... </funcs>
  rule <k> #fenvOf(F) => #vals(ListItem(G)) ...</k> <threadEnv> G </threadEnv> requires notBool isClosureVal(F)

  rule <k> #apply(builtin("getfenv"), .List) => #apply(builtin("getfenv"), ListItem(1.0)) ...</k>
  rule <k> #apply(builtin("getfenv"), ListItem(nil) _) => #apply(builtin("getfenv"), ListItem(1.0)) ...</k>
  rule <k> #apply(builtin("getfenv"), ListItem(F:Val) _) => #fenvOf(F) ...</k> requires #type(F) ==String "function"
  rule <k> #apply(builtin("getfenv"), ListItem(N:Val) _) => #vals(ListItem(G)) ...</k> <threadEnv> G </threadEnv>
    requires isFloat(#tonumber(N)) andBool #truncInt({#tonumber(N)}:>Float) ==Int 0
  rule <k> #apply(builtin("getfenv"), ListItem(N:Val) _)
        => #levelFn(#level(Stack, #truncInt({#tonumber(N)}:>Float) -Int 1), "getfenv", #truncInt({#tonumber(N)}:>Float)) ...</k>
       <callStack> Stack </callStack>
    requires isFloat(#tonumber(N)) andBool #truncInt({#tonumber(N)}:>Float) >Int 0
  rule <k> #apply(builtin(Fn), ListItem(N:Val) _) => #error("bad argument #1 to '" +String Fn +String "' (level must be non-negative)") ...</k>
    requires (Fn ==String "getfenv" orBool Fn ==String "setfenv") andBool isFloat(#tonumber(N)) andBool #truncInt({#tonumber(N)}:>Float) <Int 0
  rule <k> #apply(builtin("getfenv"), ListItem(V:Val) _) => #argError(1, "getfenv", "number", V) ...</k>
    requires V =/=K nil andBool #type(V) =/=String "function" andBool notBool isFloat(#tonumber(V))

  rule <k> #levelFn(#lvlFrame(#frame(F, _)), "getfenv", _) => #fenvOf(F) ...</k>
  rule <k> #levelFn(#lvlLost, _, L) => #error("no function environment for tail call at level " +String Int2String(L)) ...</k>
  rule <k> #levelFn(#lvlInvalid, Fn, _) => #error("bad argument #1 to '" +String Fn +String "' (invalid level)") ...</k>

  syntax KItem ::= #setfenvOf(Val, Val)
  rule <k> #apply(builtin("setfenv"), ListItem(_) ListItem(T:Val) _) => #argError(2, "setfenv", "table", T) ...</k>
    requires notBool isTRef(T)
  rule <k> #apply(builtin("setfenv"), ListItem(N:Val) ListItem(T:TRef) _) => #vals(.List) ...</k>
       <threadEnv> _ => T </threadEnv>
    requires isFloat(#tonumber(N)) andBool #truncInt({#tonumber(N)}:>Float) ==Int 0
  rule <k> #apply(builtin("setfenv"), ListItem(F:Val) ListItem(T:TRef) _) => #setfenvOf(F, T) ...</k>
    requires #type(F) ==String "function"
  rule <k> #apply(builtin("setfenv"), ListItem(N:Val) ListItem(T:TRef) _)
        => #levelFn(#level(Stack, #truncInt({#tonumber(N)}:>Float) -Int 1), "setfenv", #truncInt({#tonumber(N)}:>Float)) ~> #setfenvK(T) ...</k>
       <callStack> Stack </callStack>
    requires isFloat(#tonumber(N)) andBool #truncInt({#tonumber(N)}:>Float) >Int 0
  syntax KItem ::= #setfenvK(Val)
  rule <k> #levelFn(#lvlFrame(#frame(F, _)), "setfenv", _) ~> #setfenvK(T) => #setfenvOf(F, T) ...</k>
  rule <k> #setfenvOf(closure(I), T) => #vals(ListItem(closure(I))) ...</k>
       <funcs> ... I |-> #fun(_, _, _, _, _, (_ => T)) ... </funcs>
  rule <k> #setfenvOf(F, _) => #error("'setfenv' cannot change environment of given object") ...</k>
    requires notBool isClosureVal(F)
endmodule
