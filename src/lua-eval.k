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
  rule <k> X:Name => #genv ~> #indexK(Name2String(X)) ...</k>
       <env> Env </env>
    requires notBool X in_keys(Env)
  syntax KItem ::= #indexK(Val) | #setIndexK(Val, Val)
  rule <k> G:Val ~> #indexK(K) => #index(G, K) ...</k>
  rule <k> G:Val ~> #setIndexK(K, V) => #setIndex(G, K, V) ...</k>

  // ------------------------------------------------------ desugaring
  // Each operator form also carries its operands' source expressions
  // (never evaluated), so that an error can name the variable involved:
  // "attempt to index global 'x' (a nil value)" (ldebug.c getobjname).
  syntax Exp ::= #bin(String, Exp, Exp, K, K) [seqstrict(2, 3)]
               | #un(String, Exp, K)          [strict(2)]
               | #and(Exp, Exp)               [strict(1)]
               | #or(Exp, Exp)                [strict(1)]
               | #idx(Exp, Exp, K)            [seqstrict(1, 2)]

  rule <k> A + B   => #bin("+", A, B, A, B)  ...</k>
  rule <k> A - B   => #bin("-", A, B, A, B)  ...</k>
  rule <k> A * B   => #bin("*", A, B, A, B)  ...</k>
  rule <k> A / B   => #bin("/", A, B, A, B)  ...</k>
  rule <k> A % B   => #bin("%", A, B, A, B)  ...</k>
  rule <k> A ^ B   => #bin("^", A, B, A, B)  ...</k>
  rule <k> A ^ - B   => #bin("^", A, #un("-", B, B), A, .K)   ...</k>
  rule <k> A ^ not B => #bin("^", A, #un("not", B, B), A, .K) ...</k>
  rule <k> A ^ # B   => #bin("^", A, #un("#", B, B), A, .K)   ...</k>
  rule <k> A .. B  => #bin("..", A, B, A, B) ...</k>
  rule <k> A == B  => #bin("==", A, B, A, B) ...</k>
  rule <k> A ~= B  => #bin("~=", A, B, A, B) ...</k>
  rule <k> A < B   => #bin("<", A, B, A, B)  ...</k>
  rule <k> A <= B  => #bin("<=", A, B, A, B) ...</k>
  rule <k> A > B   => #bin(">", A, B, A, B)  ...</k>
  rule <k> A >= B  => #bin(">=", A, B, A, B) ...</k>
  rule <k> - A     => #un("-", A, A)      ...</k>
  rule <k> not A   => #un("not", A, A)    ...</k>
  rule <k> # A     => #un("#", A, A)      ...</k>
  rule <k> A and B => #and(A, B) ...</k>
  rule <k> A or B  => #or(A, B)  ...</k>

  // A parenthesised expression is a single value; evaluating it in place
  // already gives exactly that. (The cast picks the Lua parenthesis over
  // K's own grouping brackets.)
  rule <k> ( E:Exp ):PPrefix => E ...</k>

  rule <k> P:NPrefix [ K:Exp ]   => #idx(P, K, P) ...</k>
  rule <k> P:PPrefix [ K:Exp ]   => #idx(P, K, P) ...</k>
  rule <k> P:NPrefix . N:Name    => #idx(P, Name2String(N), P) ...</k>
  rule <k> P:PPrefix . N:Name    => #idx(P, Name2String(N), P) ...</k>
  // fast path: a field that is present
  rule <k> #idx(tref(T), K:Val, _) => #rawget(M, K) ...</k> <tables> ... T |-> #tbl(M, _, _) ... </tables>
    requires #rawget(M, K) =/=K nil [priority(40)]
  rule <k> #idx(T:Val, K:Val, E) => #index(T, K) ~> #idxCtx(E) ...</k>
  syntax KItem ::= #idxCtx(K)
  rule <k> V:Val ~> #idxCtx(_) => V ...</k>
  // Indexing something that cannot be indexed names the indexed expression.
  rule <k> nil ~> #gtTM(V, _, 0, false) ~> #idxCtx(E) => #typeError(V, "index", E) ...</k> [priority(40)]

  // ------------------------------------------------------ error messages
  // luaG_typeerror: "attempt to OP KIND 'NAME' (a TYPE value)" when the
  // operand is a variable or field, "attempt to OP a TYPE value" otherwise.
  syntax KItem ::= #typeError(Val, String, K) | #describe(K) | #typeErrorMsg(Val, String)
  rule <k> #typeError(V, Op, E) => #describe(E) ~> #typeErrorMsg(V, Op) ...</k>
  rule <k> D:String ~> #typeErrorMsg(V, Op) => #rtError("attempt to " +String Op +String " a " +String #type(V) +String " value") ...</k>
    requires D ==String ""
  rule <k> D:String ~> #typeErrorMsg(V, Op)
        => #rtError("attempt to " +String Op +String " " +String D +String " (a " +String #type(V) +String " value)") ...</k>
    requires D =/=String ""

  // getobjname: a global, a local of the running function, an upvalue (a
  // local of an enclosing function, i.e. one the closure captured), a field
  // with a constant string key ('?' for other keys), or a method.
  rule <k> #describe(X:Name) => "global '" +String Name2String(X) +String "'" ...</k>
       <env> Env </env>
    requires notBool X in_keys(Env)
  rule <k> #describe(X:Name) => #if X in_keys(CEnv) andBool CEnv [ X ] ==K L
                                #then "upvalue '" #else "local '" #fi +String Name2String(X) +String "'" ...</k>
       <env> ... X |-> L ... </env>
       <callStack> ListItem(#frame(closure(I), _, _, _)) ... </callStack>
       <funcs> ... I |-> #fun(_, _, _, _, CEnv, _) ... </funcs>
  rule <k> #describe(_:NPrefix . N:Name) => "field '" +String Name2String(N) +String "'" ...</k>
  rule <k> #describe(_:PPrefix . N:Name) => "field '" +String Name2String(N) +String "'" ...</k>
  rule <k> #describe(_:NPrefix [ S:LString ]) => "field '" +String #decodeLString(LString2String(S)) +String "'" ...</k>
  rule <k> #describe(_:PPrefix [ S:LString ]) => "field '" +String #decodeLString(LString2String(S)) +String "'" ...</k>
  rule <k> #describe(_:NPrefix [ E:Exp ]) => "field '?'" ...</k> requires notBool isLString(E)
  rule <k> #describe(_:PPrefix [ E:Exp ]) => "field '?'" ...</k> requires notBool isLString(E)
  rule <k> #describe(( E:Exp ):PPrefix) => #describe(E) ...</k>
  rule <k> #describe(#method(N)) => "method '" +String N +String "'" ...</k>
  rule <k> #describe(_) => "" ...</k> [owise]

  // ------------------------------------------------------ arithmetic
  syntax Bool ::= #isArith(String) [function, total]
  rule #isArith(Op) => Op ==String "+" orBool Op ==String "-" orBool Op ==String "*"
               orBool Op ==String "/" orBool Op ==String "%" orBool Op ==String "^"

  // Operands are numbers or strings that convert (tonumber); otherwise the
  // event's metamethod of the first operand, else of the second, is called
  // (call_binTM). Without one Lua blames the first operand that does not
  // convert.
  rule <k> #bin(Op, A:Val, B:Val, _, _) => #arithF(Op, {#tonumber(A)}:>Float, {#tonumber(B)}:>Float) ...</k>
    requires #isArith(Op) andBool #tonumber(A) =/=K nil andBool #tonumber(B) =/=K nil
  rule <k> #bin(Op, A:Val, B:Val, EA, EB)
        => #binTM(#event(Op), A, B, #if #tonumber(A) ==K nil #then #typeError(A, "perform arithmetic on", EA)
                                    #else #typeError(B, "perform arithmetic on", EB) #fi) ...</k>
    requires #isArith(Op) andBool (#tonumber(A) ==K nil orBool #tonumber(B) ==K nil)

  syntax String ::= #event(String) [function, total]
  rule #event("+") => "__add"   rule #event("-") => "__sub"   rule #event("*") => "__mul"
  rule #event("/") => "__div"   rule #event("%") => "__mod"   rule #event("^") => "__pow"
  rule #event("..") => "__concat"
  rule #event(_) => "" [owise]

  // call_binTM(a, b, event): a's metamethod, else b's; call it with (a, b).
  syntax KItem ::= #binTM(String, Val, Val, K) | #binTM2(String, Val, Val, K) | #binTMCall(Val, Val, K)
  rule <k> #binTM(E, A, B, Err) => #getTM(A, E) ~> #binTM2(E, A, B, Err) ...</k>
  rule <k> nil ~> #binTM2(E, A, B, Err) => #getTM(B, E) ~> #binTMCall(A, B, Err) ...</k>
  rule <k> H:Val ~> #binTM2(_, A, B, _) => #apply(H, ListItem(A) ListItem(B)) ~> #first ...</k> requires H =/=K nil
  rule <k> nil ~> #binTMCall(_, _, Err) => Err ...</k>
  rule <k> H:Val ~> #binTMCall(A, B, _) => #apply(H, ListItem(A) ListItem(B)) ~> #first ...</k> requires H =/=K nil

  syntax Float ::= #arithF(String, Float, Float) [function, total]
  rule #arithF("+", X, Y) => X +Float Y
  rule #arithF("-", X, Y) => X -Float Y
  rule #arithF("*", X, Y) => X *Float Y
  rule #arithF("/", X, Y) => X /Float Y
  rule #arithF("%", X, Y) => X -Float floorFloat(X /Float Y) *Float Y   // luai_nummod
  rule #arithF("^", X, Y) => X ^Float Y
  rule #arithF(_, _, _) => NaN [owise]

  rule <k> #un("-", A:Val, _) => --Float {#tonumber(A)}:>Float ...</k> requires #tonumber(A) =/=K nil
  rule <k> #un("-", A:Val, E) => #binTM("__unm", A, A, #typeError(A, "perform arithmetic on", E)) ...</k>
    requires #tonumber(A) ==K nil

  // ------------------------------------------------------ comparison
  // ==: different types are never equal; two different tables are equal if
  // they share an __eq metamethod (the same one in both metatables) that
  // says so (luaV_equalval, get_compTM).
  rule <k> #bin("==", A:Val, B:Val, _, _) => #rawEq(A, B) ...</k>
    requires notBool (isTRef(A) andBool isTRef(B) andBool A =/=K B)
  rule <k> #bin("==", tref(A), tref(B), _, _) => #metaOf(tref(A)) ~> #eq1(tref(A), tref(B)) ...</k>
    requires A =/=Int B
  rule <k> #bin("~=", A:Val, B:Val, EA, EB) => #bin("==", A, B, EA, EB) ~> #not ...</k>
  syntax KItem ::= "#not" | #eq1(Val, Val) | #eq2(Val, Val, Val) | #eq3(Val, Val, Val, Val) | #eq4(Val, Val, Val)
                 | #callBool(Val, Val, Val)
  rule <k> V:Val ~> #not => notBool #truthy(V) ...</k>
  rule <k> M1:Val ~> #eq1(A, B) => #metaOf(B) ~> #eq2(M1, A, B) ...</k>
  rule <k> M2:Val ~> #eq2(M1, A, B) => #tmFrom(M1, "__eq") ~> #eq3(M1, M2, A, B) ...</k>
  rule <k> nil ~> #eq3(_, _, _, _) => false ...</k>
  rule <k> H:Val ~> #eq3(M, M, A, B) => #callBool(H, A, B) ...</k> requires H =/=K nil
  rule <k> H:Val ~> #eq3(M1, M2, A, B) => #tmFrom(M2, "__eq") ~> #eq4(H, A, B) ...</k>
    requires H =/=K nil andBool M1 =/=K M2
  rule <k> H2:Val ~> #eq4(H, A, B) => #callBool(H, A, B) ...</k> requires H2 =/=K nil andBool #rawEq(H, H2)
  rule <k> H2:Val ~> #eq4(H, _, _) => false ...</k> requires H2 ==K nil orBool notBool #rawEq(H, H2)
  // A metamethod's first result, as a boolean.
  rule <k> #callBool(H, A, B) => #apply(H, ListItem(A) ListItem(B)) ~> #first ~> #not ~> #not ...</k>
  rule <k> #bin("<",  A:Float, B:Float, _, _)   => A <Float B ...</k>
  rule <k> #bin("<",  A:String, B:String, _, _) => A <String B ...</k>
  rule <k> #bin("<=", A:Float, B:Float, _, _)   => A <=Float B ...</k>
  rule <k> #bin("<=", A:String, B:String, _, _) => A <String B orBool A ==String B ...</k>
  rule <k> #bin(">",  A:Val, B:Val, EA, EB) => #bin("<",  B, A, EB, EA) ...</k>
  rule <k> #bin(">=", A:Val, B:Val, EA, EB) => #bin("<=", B, A, EB, EA) ...</k>
  // Other operands of the same type: call_orderTM needs the same __lt
  // (or __le) metamethod in both; `a <= b` falls back to `not (b < a)`.
  // Operands of different types are always an error (luaV_lessthan).
  rule <k> #bin(Op, A:Val, B:Val, _, _) => #compareError(A, B) ...</k>
    requires (Op ==String "<" orBool Op ==String "<=") andBool #type(A) =/=String #type(B)
  rule <k> #bin("<", A:Val, B:Val, _, _) => #orderTM(A, B, "__lt", #compareError(A, B)) ...</k>
    requires #type(A) ==String #type(B) andBool notBool #isNumOrStr(A)
  rule <k> #bin("<=", A:Val, B:Val, _, _) => #orderTM(A, B, "__le", #orderTM(B, A, "__lt", #compareError(A, B)) ~> #not) ...</k>
    requires #type(A) ==String #type(B) andBool notBool #isNumOrStr(A)

  syntax KItem ::= #orderTM(Val, Val, String, K) | #orderTM2(Val, Val, String, K) | #orderTM3(Val, Val, Val, K)
  rule <k> #orderTM(A, B, E, Else) => #getTM(A, E) ~> #orderTM2(A, B, E, Else) ...</k>
  rule <k> nil ~> #orderTM2(_, _, _, Else) => Else ...</k>
  rule <k> H:Val ~> #orderTM2(A, B, E, Else) => #getTM(B, E) ~> #orderTM3(H, A, B, Else) ...</k> requires H =/=K nil
  rule <k> H2:Val ~> #orderTM3(H, A, B, _) => #callBool(H, A, B) ...</k>
    requires #rawEq(H, H2)
  rule <k> H2:Val ~> #orderTM3(H, _, _, Else) => Else ...</k> requires notBool #rawEq(H, H2)

  syntax Bool ::= #isNumOrStr(Val) [function, total]
  rule #isNumOrStr(_:Float)  => true
  rule #isNumOrStr(_:String) => true
  rule #isNumOrStr(_) => false [owise]

  // luaG_ordererror: no variable names.
  syntax KItem ::= #compareError(Val, Val)
  rule <k> #compareError(A, B) => #rtError("attempt to compare two " +String #type(A) +String " values") ...</k>
    requires #type(A) ==String #type(B)
  rule <k> #compareError(A, B) => #rtError("attempt to compare " +String #type(A) +String " with " +String #type(B)) ...</k>
    [owise]

  // ------------------------------------------------------ concatenation
  rule <k> #bin("..", A:Val, B:Val, _, _) => {#tostringCoerce(A)}:>String +String {#tostringCoerce(B)}:>String ...</k>
    requires #tostringCoerce(A) =/=K nil andBool #tostringCoerce(B) =/=K nil
  // Otherwise __concat (call_binTM); without one Lua blames the first
  // operand that is not a string or number.
  rule <k> #bin("..", A:Val, B:Val, EA, EB)
        => #binTM("__concat", A, B, #if #tostringCoerce(A) ==K nil #then #typeError(A, "concatenate", EA)
                                    #else #typeError(B, "concatenate", EB) #fi) ...</k>
    requires #tostringCoerce(A) ==K nil orBool #tostringCoerce(B) ==K nil

  // ------------------------------------------------------ not, #, and, or
  rule <k> #un("not", A:Val, _) => notBool #truthy(A) ...</k>
  rule <k> #un("#", S:String, _) => Int2Float(lengthString(S), 53, 11) ...</k>
  rule <k> #un("#", tref(T), _) => #lenF(M, A) ...</k> <tables> ... T |-> #tbl(M, A, _) ... </tables>
  rule <k> #un("#", V:Val, E) => #typeError(V, "get length of", E) ...</k>
    requires notBool (isString(V) orBool isTRef(V))

  // The second operand is evaluated in place, so it is a single value too.
  rule <k> #and(V:Val, B) => B ...</k> requires #truthy(V)
  rule <k> #and(V:Val, _) => V ...</k> requires notBool #truthy(V)
  rule <k> #or(V:Val, _)  => V ...</k> requires #truthy(V)
  rule <k> #or(V:Val, B)  => B ...</k> requires notBool #truthy(V)

  // ======================================================= calls

  // In an expression a call gives its first result (or nil).
  syntax KItem ::= #call(K)
  rule <k> F:FunctionCall => #call(F) ~> #first ...</k>
  rule <k> #vals(L) ~> #first => #head(L) ...</k>
  rule <k> #vals(_) ~> #discard => .K ...</k>

  // The function's source expression travels along for error messages.
  syntax KItem ::= #callArgs(Args, K) | #methodArgs(String, Args, K) | #methodFn(Val, Args, String)
                 | #applyTo(Val, K) | #prepend(Val)
  rule <k> #call(P:NPrefix A:Args) => P ~> #callArgs(A, P) ...</k>
  rule <k> #call(P:PPrefix A:Args) => P ~> #callArgs(A, P) ...</k>
  rule <k> #call(P:NPrefix : N:Name A:Args) => P ~> #methodArgs(Name2String(N), A, P) ...</k>
  rule <k> #call(P:PPrefix : N:Name A:Args) => P ~> #methodArgs(Name2String(N), A, P) ...</k>

  rule <k> F:Val ~> #callArgs(A, E) => #args(A) ~> #applyTo(F, E) ...</k>
  // o:m(...) evaluates o once and passes it as the first argument.
  rule <k> O:Val ~> #methodArgs(N, A, E) => #index(O, N) ~> #idxCtx(E) ~> #methodFn(O, A, N) ...</k>
  rule <k> F:Val ~> #methodFn(O, A, N) => #args(A) ~> #prepend(O) ~> #applyTo(F, #method(N)) ...</k>
  rule <k> #vals(L) ~> #prepend(O) => #vals(ListItem(O) L) ...</k>
  rule <k> #vals(L) ~> #applyTo(F, E) => #applyE(F, L, E) ...</k> requires #type(F) ==String "function"
  rule <k> #vals(L) ~> #applyTo(F, E) => #getTM(F, "__call") ~> #callTM(F, L, E) ...</k>
    requires #type(F) =/=String "function"

  // Lua functions are applied in LUA-FUNCTION. A library function runs in
  // a frame of its own on <callStack> (as a C function has a CallInfo), so
  // error positions and stack levels count it; its rules match #applyB.
  // Calling anything else uses its __call metamethod, which gets the called
  // value as an extra first argument (tryfuncTM). (Not [owise]: library
  // rules use owise among themselves.)
  syntax KItem ::= #callTM(Val, List, K) | #pushC(Val, K) | "#popC"
  rule <k> #applyE(F, Args, E) => #pushC(F, E) ~> #applyB(F, Args) ~> #popC ...</k> requires #isLibFn(F)
  rule <k> #pushC(F, E) => .K ...</k> <callStack> S => ListItem(#frame(F, 0, -1, E)) S </callStack>
  rule <k> #vals(R) ~> #popC => #vals(R) ...</k> <callStack> ListItem(_) S => S </callStack>
  rule <k> #applyE(F, Args, _) => #getTM(F, "__call") ~> #callTM(F, Args, .K) ...</k>
    requires #type(F) =/=String "function"
  rule <k> H:Val ~> #callTM(F, Args, _) => #apply(H, ListItem(F) Args) ...</k> requires #type(H) ==String "function"
  rule <k> H:Val ~> #callTM(F, _, E) => #typeError(F, "call", E) ...</k>
    requires #type(H) =/=String "function"

  syntax Bool ::= #isLibFn(Val) [function, total]
  rule #isLibFn(builtin(_)) => true
  rule #isLibFn(gmatchIter(_)) => true
  rule #isLibFn(_) => false [owise]

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
  // its values if it is a call or `...` (see LUA-FUNCTION).
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

  syntax KItem ::= #exec(K) | #last(LastStmt) | #setLine(Int)

  // Statements carry their source position (the Bison parser's [locations]);
  // running one records its line in the current frame, which error
  // messages and debug.getinfo read.
  // (#location is sort-parametric; the sorts pick the instances the parser
  // produces.)
  rule <k> #exec(#location(S:Stmt, _, L, _, _, _)) => #setLine(L) ~> #exec(S) ...</k>
  rule <k> #exec(#location(S:PStmt, _, L, _, _, _)) => #setLine(L) ~> #exec(S) ...</k>
  rule <k> #last(#location(S:LastStmt, _, L, _, _, _)) => #setLine(L) ~> #last(S) ...</k>
  rule <k> #setLine(L) => .K ...</k> <callStack> ListItem(#frame(_, _, (_ => L), _)) ... </callStack>

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

  syntax LValue ::= #lvName(Name) | #lvIdx(Val, Val, K)
  syntax KItem ::= #assign(List, NeExps) | #lvals(List, List, NeExps) | #lvIdxK(List, List, NeExps, K)
                 | #storeAll(List) | #storeRev(List, List) | #storeOne(LValue, Val)
  rule <k> #assign(Ts, Es) => #lvals(Ts, .List, Es) ...</k>
  rule <k> #lvals(ListItem(X:Name) Ts, Acc, Es) => #lvals(Ts, Acc ListItem(#lvName(X)), Es) ...</k>
  rule <k> #lvals(ListItem(P:NPrefix [ K:Exp ]) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(K)) ~> #lvIdxK(Ts, Acc, Es, P) ...</k>
  rule <k> #lvals(ListItem(P:PPrefix [ K:Exp ]) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(K)) ~> #lvIdxK(Ts, Acc, Es, P) ...</k>
  rule <k> #lvals(ListItem(P:NPrefix . N:Name) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(Name2String(N))) ~> #lvIdxK(Ts, Acc, Es, P) ...</k>
  rule <k> #lvals(ListItem(P:PPrefix . N:Name) Ts, Acc, Es)
        => #evalSingles(ListItem(P) ListItem(Name2String(N))) ~> #lvIdxK(Ts, Acc, Es, P) ...</k>
  rule <k> #vals(ListItem(T:Val) ListItem(K:Val)) ~> #lvIdxK(Ts, Acc, Es, E)
        => #lvals(Ts, Acc ListItem(#lvIdx(T, K, E)), Es) ...</k>
  rule <k> #lvals(.List, Acc, Es) => #evalList(#neexps2list(Es)) ~> #storeAll(Acc) ...</k>
  rule <k> #vals(Vs) ~> #storeAll(Ts) => #storeRev(Ts, #adjust(Vs, size(Ts))) ...</k>
  rule <k> #storeRev(Ts ListItem(T:LValue), Vs ListItem(V:Val)) => #storeOne(T, V) ~> #storeRev(Ts, Vs) ...</k>
  rule <k> #storeRev(.List, _) => .K ...</k>

  rule <k> #storeOne(#lvName(X), V) => .K ...</k>
       <env> ... X |-> L ... </env>
       <store> S => S [ L <- V ] </store>
  rule <k> #storeOne(#lvName(X), V) => #genv ~> #setIndexK(Name2String(X), V) ...</k>
       <env> Env </env>
    requires notBool X in_keys(Env)
  // Assigning into something that cannot be indexed names it, as #idx does.
  rule <k> #storeOne(#lvIdx(T, K, E), V) => #setIndex(T, K, V) ~> #stCtx(E) ...</k>
  syntax KItem ::= #stCtx(K)
  rule <k> #stCtx(_) => .K ...</k>
  rule <k> nil ~> #stTM(T, _, _, 0, false) ~> #stCtx(E) => #typeError(T, "index", E) ...</k> [priority(40)]

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
  rule <k> #forCheck(nil, _, _, _, _) => #rtError("'for' initial value must be a number") ...</k>
  rule <k> #forCheck(_:Float, nil, _, _, _) => #rtError("'for' limit must be a number") ...</k>
  rule <k> #forCheck(_:Float, _:Float, nil, _, _) => #rtError("'for' step must be a number") ...</k>
  rule <k> #forLoop(X, V, L, S, B) => #forBody(X, V, B) ~> #forLoop(X, V +Float S, L, S, B) ...</k>
    requires (0.0 <Float S andBool V <=Float L) orBool (notBool 0.0 <Float S andBool L <=Float V)
  rule <k> #forLoop(_, _, _, _, _) => .K ...</k> [owise]
  rule <k> #forBody(X, V, B) => #bind(X, V) ~> #run(B) ~> #restoreEnv(Env, NL, Ep) ...</k>
       <env> Env </env> <nextLoc> NL </nextLoc> <epoch> Ep </epoch>
endmodule
