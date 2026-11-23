// The configuration, and the operations on it that the rest builds on:
// tables, locals, output, errors.

requires "lua-literal.k"

module LUA-CONFIG
  imports LUA-LITERAL

  syntax KItem ::= "#init" | #chunk(Block)

  // <env>     Name |-> Loc for the locals in scope
  // <store>   Loc |-> Val; upvalues (M3) share a Loc
  // <fenv>    the current function environment: the table globals live in
  // <varargs> the current function's `...` values
  // <funcs>   Id |-> #fun(...) for every closure created (see LUA-FUNCTION)
  // <epoch>   bumped whenever a local may outlive its block (closure
  //           creation, coroutine switches); see #restoreEnv in LUA-EVAL
  // <tables>  Id |-> Map of fields (Val |-> Val, no nil values)
  // <args>    the script name, which becomes arg[0] (M4)
  // krun exits with <exit-code>: 1 until <k> empties, so a stuck run or an
  // error fails.
  configuration
    <lua>
      <k> #init ~> #chunk($PGM:Block) </k>
      <env> .Map </env>
      <fenv> tref(0) </fenv>
      <varargs> .List </varargs>
      <store> .Map </store>
      <nextLoc> 0 </nextLoc>
      <epoch> 0 </epoch>
      <tables> .Map </tables>
      <nextTable> 0 </nextTable>
      <funcs> .Map </funcs>
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

  // t[k] and t[k] = v without metamethods (those come in M6).
  syntax KItem ::= #index(Val, Val) | #setIndex(Val, Val, Val) | #newTable(Map)
  rule <k> #index(tref(T), K) => #rawget(M, K) ...</k> <tables> ... T |-> M:Map ... </tables>
  rule <k> #index(V, _) => #error("attempt to index a " +String #type(V) +String " value") ...</k>
    [owise]

  rule <k> #setIndex(tref(_), nil, _) => #error("table index is nil") ...</k>
  rule <k> #setIndex(tref(_), K, _) => #error("table index is NaN") ...</k>
    requires #isNaNVal(K)
  rule <k> #setIndex(tref(T), K, V) => .K ...</k>
       <tables> ... T |-> (M:Map => #rawset(M, K, V)) ... </tables>
    requires K =/=K nil andBool notBool #isNaNVal(K)
  rule <k> #setIndex(V, _, _) => #error("attempt to index a " +String #type(V) +String " value") ...</k>
    [owise]

  rule <k> #newTable(M) => tref(N) ...</k>
       <tables> Ts => Ts [ N <- M ] </tables>
       <nextTable> N => N +Int 1 </nextTable>

  // Length of a table: a border, found like Lua's unbound_search (hash part):
  // double j while t[j] ~= nil, then binary search. For sequences this is n.
  syntax Float ::= #border(Map) [function, total]
  syntax Int ::= #unbound(Map, Int, Int) [function, total]
               | #binsearch(Map, Int, Int) [function, total]
  rule #border(M) => Int2Float(#unbound(M, 1, 2), 53, 11) requires #rawget(M, 1.0) =/=K nil
  rule #border(_) => 0.0 [owise]
  rule #unbound(M, _, J) => #unbound(M, J, J *Int 2) requires #rawget(M, Int2Float(J, 53, 11)) =/=K nil
  rule #unbound(M, I, J) => #binsearch(M, I, J) [owise]
  rule #binsearch(M, I, J) => #binsearch(M, I, (I +Int J) /Int 2)
    requires J -Int I >Int 1 andBool #rawget(M, Int2Float((I +Int J) /Int 2, 53, 11)) ==K nil
  rule #binsearch(M, I, J) => #binsearch(M, (I +Int J) /Int 2, J)
    requires J -Int I >Int 1 andBool #rawget(M, Int2Float((I +Int J) /Int 2, 53, 11)) =/=K nil
  rule #binsearch(_, I, _) => I [owise]
endmodule
