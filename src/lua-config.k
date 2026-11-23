// The configuration, and the operations on it that the rest builds on:
// tables, locals, output, errors.

requires "lua-literal.k"

module LUA-CONFIG
  imports LUA-LITERAL

  syntax KItem ::= "#init" | #chunk(Block)

  // <env>     Name |-> Loc for the locals in scope
  // <store>   Loc |-> Val; upvalues (M3) share a Loc
  // <callStack> the active Lua function calls, innermost first, as
  //           #frame(function, tail calls it replaced); globals are looked
  //           up in the innermost function's environment (see #genv)
  // <threadEnv> the thread's global table (getfenv(0); what library
  //           functions see)
  // <strMeta> the metatable shared by all strings
  // <varargs> the current function's `...` values
  // <funcs>   Id |-> #fun(...) for every closure created (see LUA-FUNCTION)
  // <epoch>   bumped whenever a local may outlive its block (closure
  //           creation, coroutine switches); see #restoreEnv in LUA-EVAL
  // <tables>  Id |-> #tbl(fields, array size, metatable); fields is a
  //           Val |-> Val map without nil values
  // <rand>    glibc random() state for math.random (empty until first use)
  // <iters>   Id |-> state of each string.gmatch iterator
  // <args>    the script name, which becomes arg[0] (M4)
  // krun exits with <exit-code>: 1 until <k> empties, so a stuck run or an
  // error fails.
  configuration
    <lua>
      <k> #init ~> #chunk($PGM:Block) </k>
      <env> .Map </env>
      <callStack> .List </callStack>
      <threadEnv> tref(0) </threadEnv>
      <strMeta> tref(6) </strMeta>
      <varargs> .List </varargs>
      <store> .Map </store>
      <nextLoc> 0 </nextLoc>
      <epoch> 0 </epoch>
      <tables> .Map </tables>
      <nextTable> 0 </nextTable>
      <funcs> .Map </funcs>
      <rand> .List </rand>
      <iters> .Map </iters>
      <nextFn> 0 </nextFn>
      <args> $ARGS:String </args>
      <output stream="stdout"> .List </output>
      <errors> .List </errors>
      <exit-code exit=""> 1 </exit-code>
    </lua>

  rule <k> .K </k> <exit-code> 1 => 0 </exit-code>

  // ---------------------------------------------------------- results
  // #vals is the result of a call or of a multi-value expression list.
  syntax KItem ::= #vals(List)

  // ----------------------------------------------------------- errors
  // A runtime error stops the program, recording "lua: msg" in <errors>
  // (K offers no stderr stream; klua prints the final configuration of a
  // failed run). pcall and positions come in M7. The rest of <k> is kept so
  // the configuration shows where it happened.
  syntax KItem ::= #error(String) | #halted(String)
  rule <k> (#error(S) => #halted(S)) ~> _ </k>
       <errors> ... .List => ListItem("lua: " +String S +String "\n") </errors>

  // ----------------------------------------------------------- output
  syntax KItem ::= #output(String)
  rule <k> #output(S) => .K ...</k> <output> ... .List => ListItem(S) </output>

  // ----------------------------------------------------------- locals
  syntax KItem ::= #bind(Name, Val)
  rule <k> #bind(X, V) => .K ...</k>
       <env> E => E [ X <- L ] </env>
       <store> S => S [ L <- V ] </store>
       <nextLoc> L => L +Int 1 </nextLoc>

  // ----------------------------------------------------------- tables
  // Keys: 0 and -0 are the same key. nil and NaN cannot be keys.
  syntax Val ::= #normKey(Val) [function, total]
  rule #normKey(F:Float) => 0.0 requires F ==Float 0.0
  rule #normKey(K) => K [owise]

  syntax Val ::= #rawget(Map, Val) [function, total]
               | #lookup(Map, Val) [function, total]
  rule #rawget(M, K) => #lookup(M, #normKey(K))
  rule #lookup(M, K) => {M [ K ]}:>Val requires K in_keys(M)
  rule #lookup(_, _) => nil [owise]

  syntax Map ::= #rawset(Map, Val, Val) [function, total]
  rule #rawset(M, K, nil) => M [ #normKey(K) <- undef ]
  rule #rawset(M, K, V) => M [ #normKey(K) <- V ] [owise]

  syntax Bool ::= #isNaNVal(Val) [function, total]
  rule #isNaNVal(F:Float) => isNaN(F)
  rule #isNaNVal(_) => false [owise]

  // A table: its fields, the size Lua 5.1 would give its array part (only
  // a constructor sets it; see #border), and its metatable (M6).
  syntax TableData ::= #tbl(Map, Int, Val)

  // ----------------------------------------------------------- functions
  // A closure's data: parameters, vararg?, needs the `arg` table?, body,
  // captured Name |-> Loc map, environment table. See LUA-FUNCTION.
  syntax FunInfo ::= #fun(List, Bool, Bool, Block, Map, Val)
  syntax Frame ::= #frame(Val, Int)

  // The environment globals are read from and written to: the innermost
  // Lua function's (its current one, so setfenv takes effect at once).
  // Calling a value (LUA-EVAL, LUA-FUNCTION, LUA-STDLIB give the rules).
  syntax KItem ::= #apply(Val, List) | "#first" | "#discard"

  syntax KItem ::= "#genv"
  rule <k> #genv => G ...</k>
       <callStack> ListItem(#frame(closure(I), _)) ... </callStack>
       <funcs> ... I |-> #fun(_, _, _, _, _, G) ... </funcs>
  rule <k> #genv => G ...</k> <callStack> .List </callStack> <threadEnv> G </threadEnv>

  // ----------------------------------------------------------- metatables
  // The metatable of a value: tables have their own, strings share
  // <strMeta>, other values have none.
  syntax KItem ::= #metaOf(Val) | #getTM(Val, String) | #tmK(String) | #tmFrom(Val, String)
  rule <k> #metaOf(tref(T)) => Mt ...</k> <tables> ... T |-> #tbl(_, _, Mt) ... </tables>
  rule <k> #metaOf(_:String) => SM ...</k> <strMeta> SM </strMeta>
  rule <k> #metaOf(V) => nil ...</k> requires notBool (isTRef(V) orBool isString(V))
  // A metamethod: the event's field in the metatable, read raw.
  rule <k> #getTM(V, E) => #metaOf(V) ~> #tmK(E) ...</k>
  rule <k> Mt:Val ~> #tmK(E) => #tmFrom(Mt, E) ...</k>
  rule <k> #tmFrom(tref(M), E) => #rawget(F, E) ...</k> <tables> ... M |-> #tbl(F, _, _) ... </tables>
  rule <k> #tmFrom(V, _) => nil ...</k> requires notBool isTRef(V)

  // ----------------------------------------------------------- t[k]
  // luaV_gettable: a raw hit, else __index (a function is called with
  // (t, k); anything else is indexed in turn), at most 100 levels deep.
  syntax KItem ::= #index(Val, Val) | #gettable(Val, Val, Int) | #gtRaw(Val, Val, Int) | #gtTM(Val, Val, Int, Bool)
  // fast path: a field that is present
  rule <k> #index(tref(T), K) => #rawget(M, K) ...</k> <tables> ... T |-> #tbl(M, _, _) ... </tables>
    requires #rawget(M, K) =/=K nil [priority(40)]
  rule <k> #index(T, K) => #gettable(T, K, 0) ...</k>
  rule <k> #gettable(_, _, C) => #error("loop in gettable") ...</k> requires C >=Int 100
  rule <k> #gettable(tref(T), K, C) => #rawget(M, K) ~> #gtRaw(tref(T), K, C) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
    requires C <Int 100
  rule <k> #gettable(V, K, C) => #getTM(V, "__index") ~> #gtTM(V, K, C, false) ...</k>
    requires C <Int 100 andBool notBool isTRef(V)
  rule <k> V:Val ~> #gtRaw(_, _, _) => V ...</k> requires V =/=K nil
  rule <k> nil ~> #gtRaw(T, K, C) => #getTM(T, "__index") ~> #gtTM(T, K, C, true) ...</k>
  rule <k> nil ~> #gtTM(_, _, _, true) => nil ...</k>
  rule <k> nil ~> #gtTM(V, _, _, false) => #error("attempt to index a " +String #type(V) +String " value") ...</k>
  rule <k> H:Val ~> #gtTM(V, K, _, _) => #apply(H, ListItem(V) ListItem(K)) ~> #first ...</k>
    requires #type(H) ==String "function"
  rule <k> H:Val ~> #gtTM(_, K, C, _) => #gettable(H, K, C +Int 1) ...</k>
    requires H =/=K nil andBool #type(H) =/=String "function"

  // ----------------------------------------------------------- t[k] = v
  // luaV_settable: a raw store if the key is present or there is no
  // __newindex; else __newindex (a function is called with (t, k, v);
  // anything else is assigned to in turn).
  syntax KItem ::= #setIndex(Val, Val, Val) | #settable(Val, Val, Val, Int) | #stTM(Val, Val, Val, Int, Bool)
                 | #rawsetT(Int, Val, Val)
  rule <k> #setIndex(T, K, V) => #settable(T, K, V, 0) ...</k>
  rule <k> #settable(_, _, _, C) => #error("loop in settable") ...</k> requires C >=Int 100
  rule <k> #settable(tref(T), K, V, C) => #rawsetT(T, K, V) ...</k>
       <tables> ... T |-> #tbl(M, _, Mt) ... </tables>
    requires C <Int 100 andBool (#rawget(M, K) =/=K nil orBool Mt ==K nil)
  rule <k> #settable(tref(T), K, V, C) => #getTM(tref(T), "__newindex") ~> #stTM(tref(T), K, V, C, true) ...</k>
       <tables> ... T |-> #tbl(M, _, Mt) ... </tables>
    requires C <Int 100 andBool #rawget(M, K) ==K nil andBool Mt =/=K nil
  rule <k> #settable(T, K, V, C) => #getTM(T, "__newindex") ~> #stTM(T, K, V, C, false) ...</k>
    requires C <Int 100 andBool notBool isTRef(T)
  rule <k> nil ~> #stTM(tref(T), K, V, _, true) => #rawsetT(T, K, V) ...</k>
  rule <k> nil ~> #stTM(T, _, _, _, false) => #error("attempt to index a " +String #type(T) +String " value") ...</k>
  rule <k> H:Val ~> #stTM(T, K, V, _, _) => #apply(H, ListItem(T) ListItem(K) ListItem(V)) ~> #discard ...</k>
    requires #type(H) ==String "function"
  rule <k> H:Val ~> #stTM(_, K, V, C, _) => #settable(H, K, V, C +Int 1) ...</k>
    requires H =/=K nil andBool #type(H) =/=String "function"

  // rawset, with the key checks.
  rule <k> #rawsetT(_, nil, _) => #error("table index is nil") ...</k>
  rule <k> #rawsetT(_, K, _) => #error("table index is NaN") ...</k> requires #isNaNVal(K)
  rule <k> #rawsetT(T, K, V) => .K ...</k>
       <tables> ... T |-> #tbl((M => #rawset(M, K, V)), _, _) ... </tables>
    requires K =/=K nil andBool notBool #isNaNVal(K)

  syntax KItem ::= #newTable(Map) | #newTableN(Map, Int)

  rule <k> #newTable(M) => #newTableN(M, 0) ...</k>
  rule <k> #newTableN(M, A) => tref(N) ...</k>
       <tables> Ts => Ts [ N <- #tbl(M, A, nil) ] </tables>
       <nextTable> N => N +Int 1 </nextTable>

  // Length of a table: a border, found as ltable.c luaH_getn does. With an
  // array part of size A whose last slot is nil, binary search inside it;
  // otherwise unbound_search from A: double j while t[j] ~= nil, then binary
  // search. Only constructors size the array part here (Lua's rehash, which
  // can resize it on insertion, is not modelled), so tables with holes may
  // get a different border than in lua; for sequences it is always n.
  syntax Int ::= #border(Map, Int) [function, total]
               | #unbound(Map, Int, Int) [function, total]
               | #binsearch(Map, Int, Int) [function, total]
  rule #border(M, A) => #binsearch(M, 0, A)
    requires A >Int 0 andBool #rawget(M, Int2Float(A, 53, 11)) ==K nil
  rule #border(M, A) => #unbound(M, A, A +Int 1) [owise]

  syntax Float ::= #lenF(Map, Int) [function, total]
  rule #lenF(M, A) => Int2Float(#border(M, A), 53, 11)
  rule #unbound(M, _, J) => #unbound(M, J, J *Int 2) requires #rawget(M, Int2Float(J, 53, 11)) =/=K nil
  rule #unbound(M, I, J) => #binsearch(M, I, J) [owise]
  rule #binsearch(M, I, J) => #binsearch(M, I, (I +Int J) /Int 2)
    requires J -Int I >Int 1 andBool #rawget(M, Int2Float((I +Int J) /Int 2, 53, 11)) ==K nil
  rule #binsearch(M, I, J) => #binsearch(M, (I +Int J) /Int 2, J)
    requires J -Int I >Int 1 andBool #rawget(M, Int2Float((I +Int J) /Int 2, 53, 11)) =/=K nil
  rule #binsearch(_, I, _) => I [owise]
endmodule
