// Lua functions: closures, calls and returns, varargs, tail calls, and the
// generic for (which is calls all the way down).
//
// A closure value is closure(Id); <funcs> maps Id to
//   #fun(Params, IsVararg, NeedsArg, Body, CapturedEnv, FunctionEnv)
// Locals live in <store> locations, and a closure captures the Name |-> Loc
// map of its definition site, so upvalues are shared locations.
//
// A call pushes #frame(function, tail calls, line, call expression) on
// <callStack> and leaves
// #returnTarget(caller env, varargs, nextLoc, epoch) behind the body;
// `return` drops <k> up to it, restores the caller and pops the frame.

requires "lua-eval.k"

module LUA-FUNCTION
  imports LUA-EVAL

  // =================================================== creating closures

  // Creating a closure moves <epoch>: from now on the locals it captured
  // may outlive their block, so no enclosing block may free them.
  syntax KItem ::= #mkClosure(FuncBody) | #mkMethod(FuncBody) | #newClosure(List, Bool, Block)
                 | #newClosureE(List, Bool, Block)
  // `()` is the empty Params list, so one rule covers every parameter list.
  rule <k> function FB:FuncBody => #mkClosure(FB) ...</k>
  rule <k> #mkClosure(( PL:ParList ) B:Block end) => #newClosure(#parNames(PL), #parVararg(PL), B) ...</k>
  // `function t:m(...)` has an implicit first parameter `self`.
  rule <k> #mkMethod(( PL:ParList ) B:Block end)
        => #newClosure(ListItem(String2Name("self")) #parNames(PL), #parVararg(PL), B) ...</k>

  // A vararg function also gets the Lua 5.0-style local `arg` table
  // (LUA_COMPAT_VARARG, on in 5.1.5's default build). A new closure gets
  // the environment of the function that creates it.
  rule <k> #newClosure(Ps, IsVA, B) => #genv ~> #newClosureE(Ps, IsVA, B) ...</k>
  rule <k> FE:Val ~> #newClosureE(Ps, IsVA, B) => closure(I) ...</k>
       <funcs> Fs => Fs [ I <- #fun(Ps, IsVA, IsVA, B, Env, FE) ] </funcs>
       <nextFn> I => I +Int 1 </nextFn>
       <env> Env </env>
       <epoch> Ep => Ep +Int 1 </epoch>

  syntax Name ::= String2Name(String) [function, total, hook(STRING.string2token)]

  syntax List ::= #parNames(ParList) [function, total]
                | #params2list(Params) [function, total]
  rule #parNames(Ps:Params) => #params2list(Ps)
  rule #parNames(Ns:Names , _:Vararg) => #names2list(Ns)
  rule #parNames(_:Vararg) => .List
  rule #params2list(X:Name , Ps:Params) => ListItem(X) #params2list(Ps)
  rule #params2list(_) => .List [owise]

  syntax Bool ::= #parVararg(ParList) [function, total]
  rule #parVararg(_:Params) => false
  rule #parVararg(_) => true [owise]

  // ============================================== function statements

  // function f() ... end          f = function() ... end
  // function a.b.c() ... end      a.b.c = function() ... end
  // function a.b:m() ... end      a.b.m = function(self) ... end
  // local function f() ... end    local f; f = function() ... end
  syntax KItem ::= #dotted(DottedName) | #fieldOf(String)
                 | #storeField(String, FuncBody, Bool) | #storeTo(LValue)
  rule <k> #exec(function X:Name FB:FuncBody) => #mkClosure(FB) ~> #storeTo(#lvName(X)) ...</k>
  rule <k> #exec(function D:DottedName . N:Name FB:FuncBody)
        => #dotted(D) ~> #storeField(Name2String(N), FB, false) ...</k>
  rule <k> #exec(function D:DottedName : N:Name FB:FuncBody)
        => #dotted(D) ~> #storeField(Name2String(N), FB, true) ...</k>
  rule <k> #exec(local function X:Name FB:FuncBody)
        => #bind(X, nil) ~> #mkClosure(FB) ~> #storeTo(#lvName(X)) ...</k>

  rule <k> #dotted(X:Name) => X ...</k>
  rule <k> #dotted(D:DottedName . N:Name) => #dotted(D) ~> #fieldOf(Name2String(N)) ...</k>
  rule <k> V:Val ~> #fieldOf(N) => #index(V, N) ...</k>
  rule <k> T:Val ~> #storeField(N, FB, false) => #mkClosure(FB) ~> #storeTo(#lvIdx(T, N, .K)) ...</k>
  rule <k> T:Val ~> #storeField(N, FB, true)  => #mkMethod(FB)  ~> #storeTo(#lvIdx(T, N, .K)) ...</k>
  rule <k> V:Val ~> #storeTo(LV) => #storeOne(LV, V) ...</k>

  // ======================================================= calling

  syntax KItem ::= #enter(Int, FunInfo, List, Int, K)
                 | #bindParams(List, List) | #argTable(Bool, List) | #bindVal(Name)
                 | "#return" | #returnTarget(Map, List, Int, Int)
                 | #popFrame(Map, List, Int, Int)
  rule <k> #applyE(closure(I), Args, E) => #enter(I, F, Args, 0, E) ...</k>
       <funcs> ... I |-> F:FunInfo ... </funcs>
  // #enter(closure id, its data, arguments, tail calls this frame replaced,
  // call expression)
  rule <k> #enter(I, #fun(Ps, IsVA, NA, B, CEnv, _), Args, Tails, E)
        => #bindParams(Ps, Args) ~> #argTable(NA, #drop(size(Ps), Args))
           ~> #run(B) ~> #vals(.List) ~> #return
           ~> #returnTarget(Env, VA, NL, Ep) ...</k>
       <env> Env => CEnv </env>
       <varargs> VA => #varargsOf(IsVA, #drop(size(Ps), Args)) </varargs>
       <callStack> Stack => ListItem(#frame(closure(I), Tails, 0, E)) Stack </callStack>
       <nextLoc> NL </nextLoc> <epoch> Ep </epoch>

  // Missing arguments are nil, extra ones are dropped (or become `...`).
  rule <k> #bindParams(ListItem(X:Name) Xs, Args) => #bind(X, #head(Args)) ~> #bindParams(Xs, #tail(Args)) ...</k>
  rule <k> #bindParams(.List, _) => .K ...</k>

  rule <k> #argTable(false, _) => .K ...</k>
  rule <k> #argTable(true, Ex)
        => #newTable(#seqMap(Ex, 1) ("n" |-> Int2Float(size(Ex), 53, 11))) ~> #bindVal(String2Name("arg")) ...</k>
  rule <k> V:Val ~> #bindVal(X) => #bind(X, V) ...</k>

  syntax List ::= #varargsOf(Bool, List) [function, total]
                | #drop(Int, List) [function, total]
  rule #varargsOf(true, L) => L
  rule #varargsOf(false, _) => .List
  rule #drop(N, ListItem(_) L) => #drop(N -Int 1, L) requires N >Int 0
  rule #drop(_, L) => L [owise]

  // {[1] = v1, [2] = v2, ...}, leaving out nils.
  syntax Map ::= #seqMap(List, Int) [function, total]
  rule #seqMap(ListItem(V:Val) L, I) => #rawset(#seqMap(L, I +Int 1), Int2Float(I, 53, 11), V)
  rule #seqMap(_, _) => .Map [owise]

  // ======================================================= returning

  // A body that runs off its end returns no values.
  rule <k> #last(return Es:Exps ;) => #last(return Es) ...</k>
  rule <k> #last(return Es:Exps) => #evalList(#exps2list(Es)) ~> #return ...</k>
  rule <k> #vals(L) ~> #return ~> #returnTarget(Env, VA, NL, Ep) => #popFrame(Env, VA, NL, Ep) ~> #vals(L) ...</k>
  rule <k> #vals(_) ~> #return ~> (_:KItem => .K) ...</k> [owise]

  // Leaving a frame frees its locations, as #restoreEnv does for blocks.
  rule <k> #popFrame(Env, VA, NL, Ep) => .K ...</k>
       <env> _ => Env </env> <varargs> _ => VA </varargs>
       <callStack> ListItem(_) Stack => Stack </callStack>
       <epoch> Ep </epoch>
       <nextLoc> Cur => NL </nextLoc> <store> S => #free(S, NL, Cur) </store>
  rule <k> #popFrame(Env, VA, _, _) => .K ...</k>
       <env> _ => Env </env> <varargs> _ => VA </varargs>
       <callStack> ListItem(_) Stack => Stack </callStack>
    [owise]

  // Tail call: `return f(args)` (not parenthesised) evaluates f and its
  // arguments, drops the current frame, then calls f in its place, so tail
  // recursion runs in constant space. The new frame counts the tail calls
  // it stands for (debug levels and getfenv see them as lost frames).
  syntax KItem ::= "#tailMark" | #tailApply(Val, K) | #applyTail(Val, List, Int)
  // (FunctionCall is not a subsort of Exp: it is the union of the name-led
  // and paren-led call sorts, hence the #isCall test.)
  rule <k> #last(return E:Exp , .Exps) => #call(E) ~> #tailMark ...</k>
    requires #isCall(E) [priority(45)]
  rule <k> #vals(L) ~> #applyTo(F, E) ~> #tailMark => #vals(L) ~> #tailApply(F, E) ...</k>
    requires #type(F) ==String "function" [priority(45)]
  // Not a function: the ordinary call path (__call, or an error naming the
  // callee); then return its results.
  rule <k> #vals(L) ~> #tailMark => #vals(L) ~> #return ...</k>
  // Only a Lua function replaces the frame: a library function called in
  // tail position runs inside the caller's frame, as OP_TAILCALL does it
  // (luaD_precall runs C functions right away), and then the caller returns.
  rule <k> #vals(L) ~> #tailApply(F, E) => #applyE(F, L, E) ~> #return ...</k>
    requires #type(F) ==String "function" andBool notBool isClosureVal(F) [priority(45)]
  rule <k> #vals(L) ~> #tailApply(F, _) ~> #returnTarget(Env, VA, NL, Ep)
        => #popFrame(Env, VA, NL, Ep) ~> #applyTail(F, L, T +Int 1) ...</k>
       <callStack> ListItem(#frame(_, T, _, _)) ... </callStack>
  // A tail-called function has no name (getfuncname gives up on it).
  rule <k> #applyTail(closure(I), L, T) => #enter(I, F, L, T, .K) ...</k>
       <funcs> ... I |-> F:FunInfo ... </funcs>
  rule <k> #applyTail(F, L, _) => #apply(F, L) ...</k> requires notBool isClosureVal(F)
  rule <k> #vals(_) ~> #tailApply(_, _) ~> (_:KItem => .K) ...</k> [owise]

  // ======================================================= the main chunk

  // The main chunk is a vararg function (without the `arg` local).
  syntax KItem ::= "#callMain"
  rule <k> #chunk(B) => closure(I) ~> #callMain ...</k>
       <funcs> Fs => Fs [ I <- #fun(.List, true, false, B, .Map, FE) ] </funcs>
       <nextFn> I => I +Int 1 </nextFn>
       <threadEnv> FE </threadEnv>
  rule <k> F:Val ~> #callMain => #apply(F, .List) ~> #discard ...</k>

  // ======================================================= varargs

  rule <k> _:Vararg => #head(VA) ...</k> <varargs> VA </varargs>
  rule <k> #multi(_:Vararg) => #vals(VA) ...</k> <varargs> VA </varargs>

  // ======================================================= generic for

  // for x, y in f, s, v do ... end: call f(s, v) until its first result is
  // nil; each iteration binds fresh locals.
  syntax KItem ::= #forInPrep(List, Block) | #forIn(List, Block, Val, Val, Val)
                 | #forInStep(List, Block, Val, Val)
  rule <k> #exec(for Ns:Names in Es:NeExps do B:Block end)
        => #evalList(#neexps2list(Es)) ~> #forInPrep(#names2list(Ns), B) ~> #breakTarget(Env) ...</k>
       <env> Env </env>
  rule <k> #vals(L) ~> #forInPrep(Xs, B)
        => #forIn(Xs, B, #head(L), #head(#tail(L)), #head(#tail(#tail(L)))) ...</k>
  rule <k> #forIn(Xs, B, F, S, V) => #applyE(F, ListItem(S) ListItem(V), #forgen) ~> #forInStep(Xs, B, F, S) ...</k>
  rule <k> #vals(R) ~> #forInStep(_, _, _, _) => .K ...</k> requires #head(R) ==K nil
  rule <k> #vals(R) ~> #forInStep(Xs, B, F, S)
        => #vals(R) ~> #bindAll(Xs) ~> #run(B) ~> #restoreEnv(Env, NL, Ep) ~> #forIn(Xs, B, F, S, #head(R)) ...</k>
       <env> Env </env> <nextLoc> NL </nextLoc> <epoch> Ep </epoch>
    requires #head(R) =/=K nil

  syntax Bool ::= isClosureVal(Val) [function, total]
  rule isClosureVal(closure(_)) => true
  rule isClosureVal(_) => false [owise]
endmodule
