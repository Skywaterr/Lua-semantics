// The standard library: the initial global table and library functions.
// M2 covers print, io.write, tostring, tonumber, type and _VERSION; the
// rest arrives with later milestones (see ROADMAP.md).

requires "lua-eval.k"

module LUA-STDLIB
  imports LUA-EVAL

  // Table 0 is _G, table 1 is io.
  rule <k> #init => .K ...</k>
       <tables> _ => 0 |-> #globals
                     1 |-> ("write" |-> builtin("io.write"))
       </tables>
       <nextTable> _ => 2 </nextTable>

  syntax Map ::= "#globals" [function, total]
  rule #globals =>
         "_G"       |-> tref(0)
         "_VERSION" |-> "Lua 5.1"
         "io"       |-> tref(1)
         "print"    |-> builtin("print")
         "tonumber" |-> builtin("tonumber")
         "tostring" |-> builtin("tostring")
         "type"     |-> builtin("type")

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
endmodule
