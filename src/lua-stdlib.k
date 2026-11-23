// The standard library: the initial global table and library functions.
// The base library so far (print, io.write, tostring, tonumber, type,
// select, unpack, _VERSION) and the initial global table; table and math
// live in lua-table.k and lua-math.k. The rest arrives with later
// milestones (see ROADMAP.md).

requires "lua-math.k"

module LUA-STDLIB
  imports LUA-MATH

  // Tables 0-4: _G, io, table, math, and arg, which holds the interpreter
  // name at -1 and the script name at 0, as lua.c sets it up.
  rule <k> #init => .K ...</k>
       <args> Script </args>
       <tables> _ => 0 |-> #tbl(#globals, 0, nil)
                     1 |-> #tbl("write" |-> builtin("io.write"), 0, nil)
                     2 |-> #tbl(#tableLib, 0, nil)
                     3 |-> #tbl(#mathLib, 0, nil)
                     4 |-> #tbl((-1.0 |-> "lua" 0.0 |-> Script), 0, nil)
       </tables>
       <nextTable> _ => 5 </nextTable>

  syntax Map ::= "#globals" [function, total]
  rule #globals =>
         "_G"       |-> tref(0)
         "_VERSION" |-> "Lua 5.1"
         "arg"      |-> tref(4)
         "io"       |-> tref(1)
         "ipairs"   |-> builtin("ipairs")
         "math"     |-> tref(3)
         "next"     |-> builtin("next")
         "pairs"    |-> builtin("pairs")
         "print"    |-> builtin("print")
         "select"   |-> builtin("select")
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

  syntax String ::= #hex8(Int) [function, total]
  rule #hex8(I) => #rep("0", 8 -Int lengthString(Base2String(I, 16))) +String Base2String(I, 16)

  // --------------------------------------------------------------- print
  syntax String ::= #joinTostr(List) [function, total]
  rule #joinTostr(ListItem(V:Val)) => #tostr(V)
  rule #joinTostr(ListItem(V:Val) L) => #tostr(V) +String "\t" +String #joinTostr(L)
    requires L =/=K .List
  rule #joinTostr(_) => "" [owise]

  rule <k> #apply(builtin("print"), Args) => #output(#joinTostr(Args) +String "\n") ~> #vals(.List) ...</k>

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
  rule <k> #apply(builtin("tostring"), ListItem(V:Val) _) => #vals(ListItem(#tostr(V))) ...</k>
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
endmodule
