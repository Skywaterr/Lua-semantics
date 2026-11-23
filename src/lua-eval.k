// Evaluation of expressions and statements.
//
// Expressions are evaluated in place on top of <k> and leave a Val. That is
// the single-value context: a call there is cut to its first result. Where
// Lua keeps every value (the last expression of an argument list, a return,
// an assignment or local right-hand side, ...) the list goes through
// #evalList, which leaves #vals(List).
//
// Lua operators are first rewritten to a few internal strict forms (#bin,
// #un, #and, #or, #idx), so the grammar module needs no strictness
// attributes and each operator's rules see values.

requires "lua-config.k"

module LUA-EVAL
  imports LUA-CONFIG

  // ======================================================= expressions

  rule <k> N:Numeral => #numeral(N) ...</k>
  rule <k> S:LString => #decodeLString(LString2String(S)) ...</k>

  // Variables: a local if one is in scope, else a field of the environment.
  rule <k> X:Name => V ...</k>
       <env> ... X |-> L ... </env>
       <store> ... L |-> V ... </store>
  rule <k> X:Name => #index(G, Name2String(X)) ...</k>
       <env> Env </env> <fenv> G </fenv>
    requires notBool X in_keys(Env)

  // ------------------------------------------------------ desugaring
  syntax Exp ::= #bin(String, Exp, Exp) [seqstrict]
               | #un(String, Exp)       [strict]
               | #and(Exp, Exp)         [strict(1)]
               | #or(Exp, Exp)          [strict(1)]
               | #idx(Exp, Exp)         [seqstrict]

  rule <k> A + B   => #bin("+", A, B)  ...</k>
  rule <k> A - B   => #bin("-", A, B)  ...</k>
  rule <k> A * B   => #bin("*", A, B)  ...</k>
  rule <k> A / B   => #bin("/", A, B)  ...</k>
  rule <k> A % B   => #bin("%", A, B)  ...</k>
  rule <k> A ^ B   => #bin("^", A, B)  ...</k>
  rule <k> A ^ - B   => #bin("^", A, #un("-", B))   ...</k>
  rule <k> A ^ not B => #bin("^", A, #un("not", B)) ...</k>
  rule <k> A ^ # B   => #bin("^", A, #un("#", B))   ...</k>
  rule <k> A .. B  => #bin("..", A, B) ...</k>
  rule <k> A == B  => #bin("==", A, B) ...</k>
  rule <k> A ~= B  => #bin("~=", A, B) ...</k>
  rule <k> A < B   => #bin("<", A, B)  ...</k>
  rule <k> A <= B  => #bin("<=", A, B) ...</k>
  rule <k> A > B   => #bin(">", A, B)  ...</k>
  rule <k> A >= B  => #bin(">=", A, B) ...</k>
  rule <k> - A     => #un("-", A)      ...</k>
  rule <k> not A   => #un("not", A)    ...</k>
  rule <k> # A     => #un("#", A)      ...</k>
  rule <k> A and B => #and(A, B) ...</k>
  rule <k> A or B  => #or(A, B)  ...</k>

  // A parenthesised expression is a single value; evaluating it in place
  // already gives exactly that. (The cast picks the Lua parenthesis over
  // K's own grouping brackets.)
  rule <k> ( E:Exp ):PPrefix => E ...</k>

  rule <k> P:NPrefix [ K:Exp ]   => #idx(P, K) ...</k>
  rule <k> P:PPrefix [ K:Exp ]   => #idx(P, K) ...</k>
  rule <k> P:NPrefix . N:Name    => #idx(P, Name2String(N)) ...</k>
  rule <k> P:PPrefix . N:Name    => #idx(P, Name2String(N)) ...</k>
  rule <k> #idx(T:Val, K:Val) => #index(T, K) ...</k>

  // ------------------------------------------------------ arithmetic
  syntax Bool ::= #isArith(String) [function, total]
  rule #isArith(Op) => Op ==String "+" orBool Op ==String "-" orBool Op ==String "*"
               orBool Op ==String "/" orBool Op ==String "%" orBool Op ==String "^"

  // Operands are numbers or strings that convert (tonumber). On failure
  // Lua blames the first operand that does not convert.
  rule <k> #bin(Op, A:Val, B:Val) => #arithF(Op, {#tonumber(A)}:>Float, {#tonumber(B)}:>Float) ...</k>
    requires #isArith(Op) andBool #tonumber(A) =/=K nil andBool #tonumber(B) =/=K nil
  rule <k> #bin(Op, A:Val, _:Val) => #arithError(A) ...</k>
    requires #isArith(Op) andBool #tonumber(A) ==K nil
  rule <k> #bin(Op, A:Val, B:Val) => #arithError(B) ...</k>
    requires #isArith(Op) andBool #tonumber(A) =/=K nil andBool #tonumber(B) ==K nil

  syntax KItem ::= #arithError(Val)
  rule <k> #arithError(V) => #error("attempt to perform arithmetic on a " +String #type(V) +String " value") ...</k>

  syntax Float ::= #arithF(String, Float, Float) [function, total]
  rule #arithF("+", X, Y) => X +Float Y
  rule #arithF("-", X, Y) => X -Float Y
  rule #arithF("*", X, Y) => X *Float Y
  rule #arithF("/", X, Y) => X /Float Y
  rule #arithF("%", X, Y) => X -Float floorFloat(X /Float Y) *Float Y   // luai_nummod
  rule #arithF("^", X, Y) => X ^Float Y
  rule #arithF(_, _, _) => NaN [owise]

  rule <k> #un("-", A:Val) => --Float {#tonumber(A)}:>Float ...</k> requires #tonumber(A) =/=K nil
  rule <k> #un("-", A:Val) => #arithError(A) ...</k> requires #tonumber(A) ==K nil

  // ------------------------------------------------------ comparison
  rule <k> #bin("==", A:Val, B:Val) => #rawEq(A, B) ...</k>
  rule <k> #bin("~=", A:Val, B:Val) => notBool #rawEq(A, B) ...</k>
  rule <k> #bin("<",  A:Float, B:Float)   => A <Float B ...</k>
  rule <k> #bin("<",  A:String, B:String) => A <String B ...</k>
  rule <k> #bin("<=", A:Float, B:Float)   => A <=Float B ...</k>
  rule <k> #bin("<=", A:String, B:String) => A <String B orBool A ==String B ...</k>
  rule <k> #bin(">",  A:Val, B:Val) => #bin("<",  B, A) ...</k>
  rule <k> #bin(">=", A:Val, B:Val) => #bin("<=", B, A) ...</k>
  rule <k> #bin(Op, A:Val, B:Val) => #compareError(A, B) ...</k>
    requires (Op ==String "<" orBool Op ==String "<=")
     andBool notBool (#isNumOrStr(A) andBool #type(A) ==String #type(B))

  syntax Bool ::= #isNumOrStr(Val) [function, total]
  rule #isNumOrStr(_:Float)  => true
  rule #isNumOrStr(_:String) => true
  rule #isNumOrStr(_) => false [owise]

  syntax KItem ::= #compareError(Val, Val)
  rule <k> #compareError(A, B) => #error("attempt to compare two " +String #type(A) +String " values") ...</k>
    requires #type(A) ==String #type(B)
  rule <k> #compareError(A, B) => #error("attempt to compare " +String #type(A) +String " with " +String #type(B)) ...</k>
    [owise]

  // ------------------------------------------------------ concatenation
  rule <k> #bin("..", A:Val, B:Val) => {#tostringCoerce(A)}:>String +String {#tostringCoerce(B)}:>String ...</k>
    requires #tostringCoerce(A) =/=K nil andBool #tostringCoerce(B) =/=K nil
  rule <k> #bin("..", A:Val, _:Val) => #error("attempt to concatenate a " +String #type(A) +String " value") ...</k>
    requires #tostringCoerce(A) ==K nil
  rule <k> #bin("..", A:Val, B:Val) => #error("attempt to concatenate a " +String #type(B) +String " value") ...</k>
    requires #tostringCoerce(A) =/=K nil andBool #tostringCoerce(B) ==K nil

  // ------------------------------------------------------ not, #, and, or
  rule <k> #un("not", A:Val) => notBool #truthy(A) ...</k>
  rule <k> #un("#", S:String) => Int2Float(lengthString(S), 53, 11) ...</k>
  rule <k> #un("#", tref(T)) => #border(M) ...</k> <tables> ... T |-> M:Map ... </tables>
  rule <k> #un("#", V:Val) => #error("attempt to get length of a " +String #type(V) +String " value") ...</k>
    [owise]

  // The second operand is evaluated in place, so it is a single value too.
  rule <k> #and(V:Val, B) => B ...</k> requires #truthy(V)
  rule <k> #and(V:Val, _) => V ...</k> requires notBool #truthy(V)
  rule <k> #or(V:Val, _)  => V ...</k> requires #truthy(V)
  rule <k> #or(V:Val, B)  => B ...</k> requires notBool #truthy(V)

  // ======================================================= calls

  // In an expression a call gives its first result (or nil).
  syntax KItem ::= #call(K) | "#first" | "#discard"
  rule <k> F:FunctionCall => #call(F) ~> #first ...</k>
  rule <k> #vals(L) ~> #first => #head(L) ...</k>
  rule <k> #vals(_) ~> #discard => .K ...</k>

  syntax KItem ::= #callArgs(Args) | #methodArgs(String, Args) | #methodFn(Val, Args)
                 | #applyTo(Val) | #prepend(Val) | #apply(Val, List)
  rule <k> #call(P:NPrefix A:Args) => P ~> #callArgs(A) ...</k>
  rule <k> #call(P:PPrefix A:Args) => P ~> #callArgs(A) ...</k>
  rule <k> #call(P:NPrefix : N:Name A:Args) => P ~> #methodArgs(Name2String(N), A) ...</k>
  rule <k> #call(P:PPrefix : N:Name A:Args) => P ~> #methodArgs(Name2String(N), A) ...</k>

  rule <k> F:Val ~> #callArgs(A) => #args(A) ~> #applyTo(F) ...</k>
  // o:m(...) evaluates o once and passes it as the first argument.
  rule <k> O:Val ~> #methodArgs(N, A) => #index(O, N) ~> #methodFn(O, A) ...</k>
  rule <k> F:Val ~> #methodFn(O, A) => #args(A) ~> #prepend(O) ~> #applyTo(F) ...</k>
  rule <k> #vals(L) ~> #prepend(O) => #vals(ListItem(O) L) ...</k>
  rule <k> #vals(L) ~> #applyTo(F) => #apply(F, L) ...</k>

  // Library functions are defined in LUA-STDLIB; Lua functions in M3.
  rule <k> #apply(F, _) => #error("attempt to call a " +String #type(F) +String " value") ...</k>
    [owise]

  syntax KItem ::= #args(Args)
  rule <k> #args(( Es:Exps ):Args) => #evalList(#exps2list(Es)) ...</k>
  rule <k> #args(T:TableCons) => #evalList(ListItem(T)) ...</k>
  rule <k> #args(S:LString) => #vals(ListItem(#decodeLString(LString2String(S)))) ...</k>

  // ======================================================= expression lists

  syntax List ::= #exps2list(Exps)     [function, total]
                | #neexps2list(NeExps) [function, total]
                | #vars2list(Vars)     [function, total]
                | #names2list(Names)   [function, total]
  rule #exps2list(E:Exp , Es:Exps) => ListItem(E) #exps2list(Es)
  rule #exps2list(_) => .List [owise]
  rule #neexps2list(E:Exp , Es:NeExps) => ListItem(E) #neexps2list(Es)
  rule #neexps2list(_) => .List [owise]
  rule #vars2list(V:Var , Vs:Vars) => ListItem(V) #vars2list(Vs)
  rule #vars2list(_) => .List [owise]
  rule #names2list(X:Name , Xs:Names) => ListItem(X) #names2list(Xs)
  rule #names2list(_) => .List [owise]

  // Every expression but the last gives one value; the last gives all of
  // its values if it is a call (or `...`, M3).
  syntax KItem ::= #evalList(List) | #evalAcc(List, List) | #pushVal(List, List)
                 | #appendVals(List) | #multi(K) | "#toVals"
  rule <k> #evalList(L) => #evalAcc(L, .List) ...</k>
  rule <k> #evalAcc(.List, Acc) => #vals(Acc) ...</k>
  rule <k> #evalAcc(ListItem(E) .List, Acc) => #multi(E) ~> #appendVals(Acc) ...</k>
  rule <k> #evalAcc(ListItem(E) L, Acc) => E ~> #pushVal(L, Acc) ...</k>
    requires L =/=K .List
  rule <k> V:Val ~> #pushVal(L, Acc) => #evalAcc(L, Acc ListItem(V)) ...</k>
  rule <k> #vals(Vs) ~> #appendVals(Acc) => #vals(Acc Vs) ...</k>
  rule <k> #multi(F:FunctionCall) => #call(F) ...</k>
  rule <k> #multi(E) => E ~> #toVals ...</k> [owise]
  rule <k> V:Val ~> #toVals => #vals(ListItem(V)) ...</k>

  // All single values, e.g. the three numbers of a numeric for.
  syntax KItem ::= #evalSingles(List) | #evalAccS(List, List) | #pushValS(List, List)
  rule <k> #evalSingles(L) => #evalAccS(L, .List) ...</k>
  rule <k> #evalAccS(.List, Acc) => #vals(Acc) ...</k>
  rule <k> #evalAccS(ListItem(E) L, Acc) => E ~> #pushValS(L, Acc) ...</k>
  rule <k> V:Val ~> #pushValS(L, Acc) => #evalAccS(L, Acc ListItem(V)) ...</k>

  // The first N values, padded with nil.
  syntax List ::= #adjust(List, Int) [function, total]
  rule #adjust(_, N) => .List requires N <=Int 0
  rule #adjust(L, N) => ListItem(#head(L)) #adjust(#tail(L), N -Int 1) [owise]

  // ======================================================= blocks

  // A block runs with its own scope. On exit the environment is restored;
  // if nothing since entry could have captured a local (the epoch did not
  // move), the locations allocated inside are freed and reused, which keeps
  // <store> small in long loops.
  syntax KItem ::= #block(Block) | #run(Block) | #restoreEnv(Map, Int, Int)
  rule <k> #chunk(B) => #block(B) ...</k>
  rule <k> #block(B) => #run(B) ~> #restoreEnv(Env, NL, Ep) ...</k>
       <env> Env </env> <nextLoc> NL </nextLoc> <epoch> Ep </epoch>

  rule <k> #run(Ss:Stmts) => Ss ...</k>
  rule <k> #run(Ss:Stmts L:LastStmt) => Ss ~> #last(L) ...</k>
  rule <k> #run(P:PStmt Ss:Stmts) => #exec(P) ~> Ss ...</k>
  rule <k> #run(P:PStmt Ss:Stmts L:LastStmt) => #exec(P) ~> Ss ~> #last(L) ...</k>

  rule <k> S:Stmt Ss:Stmts => #exec(S) ~> Ss ...</k>
  rule <k> .Stmts => .K ...</k>

  rule <k> #restoreEnv(Env, NL, Ep) => .K ...</k>
       <env> _ => Env </env> <epoch> Ep </epoch>
       <nextLoc> Cur => NL </nextLoc>
       <store> S => #free(S, NL, Cur) </store>
  rule <k> #restoreEnv(Env, _, _) => .K ...</k> <env> _ => Env </env> [owise]

  syntax Map ::= #free(Map, Int, Int) [function, total]
  rule #free(S, I, J) => #free(S [ I <- undef ], I +Int 1, J) requires I <Int J
  rule #free(S, _, _) => S [owise]

  // ======================================================= statements

  syntax KItem ::= #exec(K) | #last(LastStmt)

  rule <k> #exec((;):Stmt) => .K ...</k>
  rule <k> #exec(; P:PStmt) => #exec(P) ...</k>
  rule <k> #exec(F:FunctionCall) => #call(F) ~> #discard ...</k>
  rule <k> #exec(do B:Block end) => #block(B) ...</k>

  // ------------------------------------------------------ assignment
  // Lua 5.1 evaluates the targets' table and key expressions left to right,
  // then the right-hand side, then stores from the last target to the
  // first (so `a, a = 1, 2` leaves a == 1).
  rule <k> #exec(V:NVar = Es:NeExps) => #assign(ListItem(V), Es) ...</k>
  rule <k> #exec(V:NVar , Vs:Vars = Es:NeExps) => #assign(ListItem(V) #vars2list(Vs), Es) ...</k>
  rule <k> #exec(V:PVar = Es:NeExps) => #assign(ListItem(V), Es) ...</k>
  rule <k> #exec(V:PVar , Vs:Vars = Es:NeExps) => #assign(ListItem(V) #vars2list(Vs), Es) ...</k>

  syntax LValue ::= #lvName(Name) | #lvIdx(Val, Val)
  syntax KItem ::= #assign(List, NeExps) | #lvals(List, List, NeExps) | #lvIdxK(List, List, NeExps)
                 | #storeAll(List) | #storeRev(List, List) | #storeOne(LValue, Val)
  rule <k> #assign(Ts, Es) => #lvals(Ts, .List, Es) ...</k>
  rule <k> #lvals(ListItem(X:Name) Ts, Acc, Es) => #lvals(Ts, Acc ListItem(#lvName(X)), Es) ...</k>
  rule <k> #lvals(ListItem(P:NPrefix [ K:Exp ]) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(K)) ~> #lvIdxK(Ts, Acc, Es) ...</k>
  rule <k> #lvals(ListItem(P:PPrefix [ K:Exp ]) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(K)) ~> #lvIdxK(Ts, Acc, Es) ...</k>
  rule <k> #lvals(ListItem(P:NPrefix . N:Name) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(Name2String(N))) ~> #lvIdxK(Ts, Acc, Es) ...</k>
  rule <k> #lvals(ListItem(P:PPrefix . N:Name) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(Name2String(N))) ~> #lvIdxK(Ts, Acc, Es) ...</k>
  rule <k> #vals(ListItem(T:Val) ListItem(K:Val)) ~> #lvIdxK(Ts, Acc, Es)
        => #lvals(Ts, Acc ListItem(#lvIdx(T, K)), Es) ...</k>
  rule <k> #lvals(.List, Acc, Es) => #evalList(#neexps2list(Es)) ~> #storeAll(Acc) ...</k>
  rule <k> #vals(Vs) ~> #storeAll(Ts) => #storeRev(Ts, #adjust(Vs, size(Ts))) ...</k>
  rule <k> #storeRev(Ts ListItem(T:LValue), Vs ListItem(V:Val)) => #storeOne(T, V) ~> #storeRev(Ts, Vs) ...</k>
  rule <k> #storeRev(.List, _) => .K ...</k>

  rule <k> #storeOne(#lvName(X), V) => .K ...</k>
       <env> ... X |-> L ... </env>
       <store> S => S [ L <- V ] </store>
  rule <k> #storeOne(#lvName(X), V) => #setIndex(G, Name2String(X), V) ...</k>
       <env> Env </env> <fenv> G </fenv>
    requires notBool X in_keys(Env)
  rule <k> #storeOne(#lvIdx(T, K), V) => #setIndex(T, K, V) ...</k>

  // ------------------------------------------------------ local
  // The right-hand side is evaluated before the names come into scope.
  syntax KItem ::= #bindAll(List)
  rule <k> #exec(local Ns:Names = Es:NeExps) => #evalList(#neexps2list(Es)) ~> #bindAll(#names2list(Ns)) ...</k>
  rule <k> #exec(local Ns:Names) => #vals(.List) ~> #bindAll(#names2list(Ns)) ...</k>
  rule <k> #vals(Vs) ~> #bindAll(ListItem(X:Name) Xs) => #bind(X, #head(Vs)) ~> #vals(#tail(Vs)) ~> #bindAll(Xs) ...</k>
  rule <k> #vals(_) ~> #bindAll(.List) => .K ...</k>

  // ------------------------------------------------------ if
  syntax KItem ::= #cond(Block, ElseIfs, K) | #elseifs(ElseIfs, K)
  rule <k> #exec(if E:Exp then B:Block Es:ElseIfs end) => E ~> #cond(B, Es, .K) ...</k>
  rule <k> #exec(if E:Exp then B:Block Es:ElseIfs else B2:Block end) => E ~> #cond(B, Es, #block(B2)) ...</k>
  rule <k> V:Val ~> #cond(B, _, _) => #block(B) ...</k> requires #truthy(V)
  rule <k> V:Val ~> #cond(_, Es, Else) => #elseifs(Es, Else) ...</k> requires notBool #truthy(V)
  rule <k> #elseifs(elseif E:Exp then B:Block Es:ElseIfs, Else) => E ~> #cond(B, Es, Else) ...</k>
  rule <k> #elseifs(.ElseIfs, Else) => Else ...</k>

  // ------------------------------------------------------ loops and break
  // A loop leaves #breakTarget(env at loop entry) behind it; `break` drops
  // everything up to it.
  syntax KItem ::= #breakTarget(Map)
  rule <k> #breakTarget(_) => .K ...</k>
  rule <k> #last(break ;) => #last(break) ...</k>
  rule <k> #last(break) ~> #breakTarget(Env) => .K ...</k> <env> _ => Env </env>
  rule <k> #last(break) ~> (_:KItem => .K) ...</k> [owise]

  syntax KItem ::= #while(Exp, Block) | #whileTest(Exp, Block)
  rule <k> #exec(while E:Exp do B:Block end) => #while(E, B) ~> #breakTarget(Env) ...</k> <env> Env </env>
  rule <k> #while(E, B) => E ~> #whileTest(E, B) ...</k>
  rule <k> V:Val ~> #whileTest(E, B) => #block(B) ~> #while(E, B) ...</k> requires #truthy(V)
  rule <k> V:Val ~> #whileTest(_, _) => .K ...</k> requires notBool #truthy(V)

  // The `until` condition is inside the body's scope.
  syntax KItem ::= #repeat(Block, Exp) | #until(Block, Exp, Map, Int, Int) | #repeatIf(Bool, Block, Exp)
  rule <k> #exec(repeat B:Block until E:Exp) => #repeat(B, E) ~> #breakTarget(Env) ...</k> <env> Env </env>
  rule <k> #repeat(B, E) => #run(B) ~> E ~> #until(B, E, Env, NL, Ep) ...</k>
       <env> Env </env> <nextLoc> NL </nextLoc> <epoch> Ep </epoch>
  rule <k> V:Val ~> #until(B, E, Env, NL, Ep) => #restoreEnv(Env, NL, Ep) ~> #repeatIf(notBool #truthy(V), B, E) ...</k>
  rule <k> #repeatIf(true, B, E) => #repeat(B, E) ...</k>
  rule <k> #repeatIf(false, _, _) => .K ...</k>

  // Numeric for: start, limit and step are evaluated once and converted
  // with tonumber; each iteration gets a fresh local (lvm.c OP_FORLOOP).
  syntax KItem ::= #forPrep(Name, Block) | #forCheck(Val, Val, Val, Name, Block)
                 | #forLoop(Name, Float, Float, Float, Block) | #forBody(Name, Float, Block)
  rule <k> #exec(for X:Name = E1:Exp , E2:Exp do B:Block end)
        => #evalSingles(ListItem(E1) ListItem(E2) ListItem(1.0)) ~> #forPrep(X, B) ~> #breakTarget(Env) ...</k>
       <env> Env </env>
  rule <k> #exec(for X:Name = E1:Exp , E2:Exp , E3:Exp do B:Block end)
        => #evalSingles(ListItem(E1) ListItem(E2) ListItem(E3)) ~> #forPrep(X, B) ~> #breakTarget(Env) ...</k>
       <env> Env </env>
  rule <k> #vals(ListItem(A:Val) ListItem(L:Val) ListItem(S:Val)) ~> #forPrep(X, B)
        => #forCheck(#tonumber(A), #tonumber(L), #tonumber(S), X, B) ...</k>
  rule <k> #forCheck(A:Float, L:Float, S:Float, X, B) => #forLoop(X, A, L, S, B) ...</k>
  rule <k> #forCheck(nil, _, _, _, _) => #error("'for' initial value must be a number") ...</k>
  rule <k> #forCheck(_:Float, nil, _, _, _) => #error("'for' limit must be a number") ...</k>
  rule <k> #forCheck(_:Float, _:Float, nil, _, _) => #error("'for' step must be a number") ...</k>
  rule <k> #forLoop(X, V, L, S, B) => #forBody(X, V, B) ~> #forLoop(X, V +Float S, L, S, B) ...</k>
    requires (0.0 <Float S andBool V <=Float L) orBool (notBool 0.0 <Float S andBool L <=Float V)
  rule <k> #forLoop(_, _, _, _, _) => .K ...</k> [owise]
  rule <k> #forBody(X, V, B) => #bind(X, V) ~> #run(B) ~> #restoreEnv(Env, NL, Ep) ...</k>
       <env> Env </env> <nextLoc> NL </nextLoc> <epoch> Ep </epoch>

  // ------------------------------------------------------ return
  // Until functions exist (M3), `return` can only end the main chunk: its
  // values are evaluated, then the program stops.
  syntax KItem ::= "#returnTop"
  rule <k> #last(return Es:Exps ;) => #last(return Es) ...</k>
  rule <k> #last(return Es:Exps) => #evalList(#exps2list(Es)) ~> #returnTop ...</k>
  rule <k> #vals(_) ~> #returnTop ~> _ => .K </k>
endmodule
