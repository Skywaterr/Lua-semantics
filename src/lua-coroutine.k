// Coroutines (lbaselib.c's coroutine library on top of ldo.c lua_resume /
// lua_yield).
//
// There is one <k>: the running thread's continuation. Resuming coroutine I
// puts I's saved continuation on top of <k>, followed by
//   #coBoundary(I, resumer's coroutine, env, varargs, call stack)
// and switches <env>, <varargs> and <callStack> to I's. Yielding moves the
// items above the boundary back into I's saved continuation and restores
// the resumer. A coroutine that returns or raises an error reaches the
// boundary itself and becomes dead.
//
// Switching moves <epoch>: a suspended coroutine's locals must not be freed
// by blocks of other threads that end meanwhile.

requires "lua-string.k"

module LUA-COROUTINE
  imports LUA-STRING

  // status: "suspended", "running", "normal" (it resumed another), "dead"
  syntax CoState ::= #co(String, K, Map, List, List)
  syntax KItem ::= #coFresh(Val)   // the saved continuation of a coroutine not yet started

  syntax Map ::= "#coroutineLib" [function, total]
  rule #coroutineLib =>
         "create"  |-> builtin("coroutine.create")  "resume"  |-> builtin("coroutine.resume")
         "running" |-> builtin("coroutine.running") "status"  |-> builtin("coroutine.status")
         "wrap"    |-> builtin("coroutine.wrap")    "yield"   |-> builtin("coroutine.yield")

  // ------------------------------------------------------------ create, wrap
  // The body must be a Lua function.
  syntax KItem ::= #newCo(Val)
  rule <k> #newCo(F) => thread(I) ...</k>
       <coroutines> Cs => Cs [ I <- #co("suspended", #coFresh(F), .Map, .List, .List) ] </coroutines>
       <nextCo> I => I +Int 1 </nextCo>
  rule <k> #applyB(builtin("coroutine.create"), ListItem(F:Val) _) => #newCo(F) ~> #toVals ...</k>
    requires isClosureVal(F)
  rule <k> #applyB(builtin("coroutine.wrap"), ListItem(F:Val) _) => #newCo(F) ~> #toWrap ...</k>
    requires isClosureVal(F)
  rule <k> #applyB(builtin(N), Args) => #badArg(1, "Lua function expected") ...</k>
    requires (N ==String "coroutine.create" orBool N ==String "coroutine.wrap")
     andBool notBool (size(Args) >Int 0 andBool isClosureVal(#head(Args)))
  syntax KItem ::= "#toWrap"
  rule <k> thread(I) ~> #toWrap => #vals(ListItem(coWrap(I))) ...</k>

  // ------------------------------------------------------------ resume
  // resume(co, ...): (true, values yielded or returned) or (false, error).
  rule <k> #applyB(builtin("coroutine.resume"), ListItem(thread(I)) Args) => #resume(I, Args) ...</k>
  rule <k> #applyB(builtin("coroutine.resume"), Args) => #badArg(1, "coroutine expected") ...</k>
    requires notBool (size(Args) >Int 0 andBool isThread(#head(Args)))

  syntax KItem ::= #resume(Int, List)
  rule <k> #resume(I, _) => #vals(ListItem(false) ListItem("cannot resume " +String #statusOf(I, Cur, St) +String " coroutine")) ...</k>
       <curCo> Cur </curCo>
       <coroutines> ... I |-> #co(St, _, _, _, _) ... </coroutines>
    requires #statusOf(I, Cur, St) =/=String "suspended"
  // from the main thread
  rule <k> #resume(I, Args) => #resumeK(Saved, Args) ~> #coBoundary(I, -1, Env, VA, Stack) ...</k>
       <curCo> -1 => I </curCo>
       <coroutines> ... I |-> #co(("suspended" => "running"), (Saved => .K), (CEnv => .Map), (CVA => .List), (CSt => .List)) ... </coroutines>
       <env> Env => CEnv </env> <varargs> VA => CVA </varargs> <callStack> Stack => CSt </callStack>
       <epoch> Ep => Ep +Int 1 </epoch>
  // from another coroutine, which becomes "normal"
  rule <k> #resume(I, Args) => #resumeK(Saved, Args) ~> #coBoundary(I, P, Env, VA, Stack) ...</k>
       <curCo> P => I </curCo>
       <coroutines> ... I |-> #co(("suspended" => "running"), (Saved => .K), (CEnv => .Map), (CVA => .List), (CSt => .List))
                        P |-> #co((_ => "normal"), _, _, _, _) ... </coroutines>
       <env> Env => CEnv </env> <varargs> VA => CVA </varargs> <callStack> Stack => CSt </callStack>
       <epoch> Ep => Ep +Int 1 </epoch>
    requires P =/=Int I

  // A fresh coroutine calls its body with the arguments; a suspended one
  // gets them as the results of its yield.
  syntax KItem ::= #resumeK(K, List) | "#coFinish"
  rule <k> #resumeK(#coFresh(F), Args) => #apply(F, Args) ~> #coFinish ...</k>
  rule <k> #resumeK(Saved, Args) => #vals(Args) ~> Saved ...</k> requires notBool isCoFresh(Saved)

  syntax Bool ::= isCoFresh(K) [function, total]
  rule isCoFresh(#coFresh(_)) => true
  rule isCoFresh(_) => false [owise]

  // The coroutine returned, or raised an error: it is dead.
  rule <k> #vals(R) ~> #coFinish ~> #coBoundary(I, P, Env, VA, Stack) => #coBack(P) ~> #vals(ListItem(true) R) ...</k>
       <coroutines> ... I |-> #co((_ => "dead"), _, _, _, _) ... </coroutines>
       <env> _ => Env </env> <varargs> _ => VA </varargs> <callStack> _ => Stack </callStack>
  rule <k> #throw(V) ~> #coBoundary(I, P, Env, VA, Stack) => #coBack(P) ~> #vals(ListItem(false) ListItem(V)) ...</k>
       <coroutines> ... I |-> #co((_ => "dead"), _, _, _, _) ... </coroutines>
       <env> _ => Env </env> <varargs> _ => VA </varargs> <callStack> _ => Stack </callStack>

  // Back in the resumer: it is running again.
  syntax KItem ::= #coBack(Int)
  rule <k> #coBack(-1) => .K ...</k> <curCo> _ => -1 </curCo> <epoch> Ep => Ep +Int 1 </epoch>
  rule <k> #coBack(P) => .K ...</k> <curCo> _ => P </curCo> <epoch> Ep => Ep +Int 1 </epoch>
       <coroutines> ... P |-> #co((_ => "running"), _, _, _, _) ... </coroutines>
    requires P =/=Int -1

  // ------------------------------------------------------------ yield
  // Collect the coroutine's continuation up to its boundary. The first item
  // is yield's own #popC; another library frame, a pcall, a metamethod or
  // a generic-for iterator call on the way is a C boundary, which 5.1 does
  // not allow to yield across (the main thread has no boundary at all).
  syntax KItem ::= #yieldCollect(List, K)
  rule <k> #applyB(builtin("coroutine.yield"), L) ~> #popC => #yieldCollect(L, #popC) ...</k>
  rule <k> #yieldCollect(L, Acc) ~> #coBoundary(I, P, Env, VA, Stack) => #coBack(P) ~> #vals(ListItem(true) L) ...</k>
       <coroutines> ... I |-> #co((_ => "suspended"), (_ => Acc), (_ => CEnv), (_ => CVA), (_ => CSt)) ... </coroutines>
       <env> CEnv => Env </env> <varargs> CVA => VA </varargs> <callStack> CSt => Stack </callStack>
  rule <k> #yieldCollect(L, Acc) ~> I:KItem => #yieldCollect(L, Acc ~> I) ...</k>
    requires notBool (#isBoundaryItem(I) orBool #crossesC(I))
  rule <k> #yieldCollect(_, _) ~> I:KItem => #rtError("attempt to yield across metamethod/C-call boundary") ~> I ...</k>
    requires #crossesC(I)
  rule <k> #yieldCollect(_, _) => #rtError("attempt to yield across metamethod/C-call boundary") </k>

  syntax Bool ::= #isBoundaryItem(KItem) [function, total] | #crossesC(KItem) [function, total]
  rule #isBoundaryItem(#coBoundary(_, _, _, _, _)) => true
  rule #isBoundaryItem(_) => false [owise]
  rule #crossesC(#popC) => true
  rule #crossesC(#mmMark) => true
  rule #crossesC(#catch(_, _, _, _)) => true
  rule #crossesC(_) => false [owise]

  // ------------------------------------------------------------ wrap
  // A wrap function resumes its coroutine and returns what it yields; an
  // error is raised again, a string one with the caller's position added.
  syntax KItem ::= "#wrapRes"
  rule <k> #applyB(coWrap(I), Args) => #resume(I, Args) ~> #wrapRes ...</k>
  rule <k> #vals(ListItem(true) R) ~> #wrapRes => #vals(R) ...</k>
  rule <k> #vals(ListItem(false) ListItem(V:Val) _) ~> #wrapRes => #error(#str(V)) ...</k> requires #isStrArg(V)
  rule <k> #vals(ListItem(false) ListItem(V:Val) _) ~> #wrapRes => #throw(V) ...</k> requires notBool #isStrArg(V)

  // ------------------------------------------------------------ status, running
  syntax String ::= #statusOf(Int, Int, String) [function, total]
  rule #statusOf(I, I, _) => "running"
  rule #statusOf(_, _, St) => St [owise]
  rule <k> #applyB(builtin("coroutine.status"), ListItem(thread(I)) _) => #vals(ListItem(#statusOf(I, Cur, St))) ...</k>
       <curCo> Cur </curCo>
       <coroutines> ... I |-> #co(St, _, _, _, _) ... </coroutines>
  rule <k> #applyB(builtin("coroutine.status"), Args) => #badArg(1, "coroutine expected") ...</k>
    requires notBool (size(Args) >Int 0 andBool isThread(#head(Args)))
  // In the main thread running() is nil (5.1).
  rule <k> #applyB(builtin("coroutine.running"), _) => #vals(ListItem(#if Cur ==Int -1 #then nil #else thread(Cur) #fi)) ...</k>
       <curCo> Cur </curCo>
endmodule
