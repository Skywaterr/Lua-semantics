// The math library (lmathlib.c), the part that maps directly onto K floats,
// plus math.random reproducing glibc's rand(), which is what lua uses.
// log10, frexp, ldexp, modf and the hyperbolic functions come in M9.

requires "lua-table.k"

module LUA-MATH
  imports LUA-TABLE

  syntax Map ::= "#mathLib" [function, total]
  rule #mathLib =>
         "abs"   |-> builtin("math.abs")   "acos"  |-> builtin("math.acos")
         "asin"  |-> builtin("math.asin")  "atan"  |-> builtin("math.atan")
         "atan2" |-> builtin("math.atan2") "ceil"  |-> builtin("math.ceil")
         "cos"   |-> builtin("math.cos")   "deg"   |-> builtin("math.deg")
         "exp"   |-> builtin("math.exp")   "floor" |-> builtin("math.floor")
         "fmod"  |-> builtin("math.fmod")  "huge"  |-> Infinity
         "log"   |-> builtin("math.log")   "max"   |-> builtin("math.max")
         "min"   |-> builtin("math.min")   "mod"   |-> builtin("math.fmod")
         "pi"    |-> 3.141592653589793     "pow"   |-> builtin("math.pow")
         "rad"   |-> builtin("math.rad")   "random" |-> builtin("math.random")
         "randomseed" |-> builtin("math.randomseed")
         "sin"   |-> builtin("math.sin")   "sqrt"  |-> builtin("math.sqrt")
         "tan"   |-> builtin("math.tan")

  // --------------------------------------------- one and two arguments
  // Arguments are numbers or numeric strings (luaL_checknumber).
  syntax Bool ::= #isMath1(String) [function, total] | #isMath2(String) [function, total]
  rule #isMath1(N) => N ==String "math.abs" orBool N ==String "math.acos" orBool N ==String "math.asin"
               orBool N ==String "math.atan" orBool N ==String "math.ceil" orBool N ==String "math.cos"
               orBool N ==String "math.deg" orBool N ==String "math.exp" orBool N ==String "math.floor"
               orBool N ==String "math.log" orBool N ==String "math.rad" orBool N ==String "math.sin"
               orBool N ==String "math.sqrt" orBool N ==String "math.tan"
  rule #isMath2(N) => N ==String "math.fmod" orBool N ==String "math.pow" orBool N ==String "math.atan2"

  rule <k> #applyB(builtin(N), ListItem(X:Val) _) => #vals(ListItem(#math1(N, {#tonumber(X)}:>Float))) ...</k>
    requires #isMath1(N) andBool isFloat(#tonumber(X))
  rule <k> #applyB(builtin(N), ListItem(X:Val) ListItem(Y:Val) _)
        => #vals(ListItem(#math2(N, {#tonumber(X)}:>Float, {#tonumber(Y)}:>Float))) ...</k>
    requires #isMath2(N) andBool isFloat(#tonumber(X)) andBool isFloat(#tonumber(Y))
  rule <k> #applyB(builtin(N), Args) => #numArgError(N, Args, 1) ...</k>
    requires (#isMath1(N) andBool notBool (size(Args) >=Int 1 andBool isFloat(#tonumber(#head(Args)))))
      orBool (#isMath2(N) andBool notBool (size(Args) >=Int 2 andBool isFloat(#tonumber(#head(Args)))
                                            andBool isFloat(#tonumber(#head(#tail(Args))))))

  // The first argument that is not a number.
  syntax KItem ::= #numArgError(String, List, Int)
  rule <k> #numArgError(N, ListItem(V:Val) L, I) => #numArgError(N, L, I +Int 1) ...</k> requires isFloat(#tonumber(V))
  rule <k> #numArgError(N, ListItem(V:Val) _, I) => #argError(I, #shortName(N), "number", V) ...</k> [owise]
  rule <k> #numArgError(_, .List, I)
        => #badArg(I, "number expected, got no value") ...</k>

  syntax Float ::= #math1(String, Float) [function, total]
  rule #math1("math.abs", X)   => absFloat(X)
  rule #math1("math.acos", X)  => acosFloat(X)
  rule #math1("math.asin", X)  => asinFloat(X)
  rule #math1("math.atan", X)  => atanFloat(X)
  rule #math1("math.ceil", X)  => ceilFloat(X)
  rule #math1("math.cos", X)   => cosFloat(X)
  rule #math1("math.deg", X)   => X /Float (3.141592653589793 /Float 180.0)
  rule #math1("math.exp", X)   => expFloat(X)
  rule #math1("math.floor", X) => floorFloat(X)
  rule #math1("math.log", X)   => logFloat(X)
  rule #math1("math.rad", X)   => X *Float (3.141592653589793 /Float 180.0)
  rule #math1("math.sin", X)   => sinFloat(X)
  rule #math1("math.sqrt", X)  => sqrtFloat(X)
  rule #math1("math.tan", X)   => tanFloat(X)
  rule #math1(_, _) => NaN [owise]

  syntax Float ::= #math2(String, Float, Float) [function, total]
  rule #math2("math.fmod", X, Y)  => #fmod(X, Y)
  rule #math2("math.pow", X, Y)   => X ^Float Y
  rule #math2("math.atan2", X, Y) => atan2Float(X, Y)
  rule #math2(_, _, _) => NaN [owise]

  // C fmod (result has the sign of x, |result| < |y|), computed exactly:
  // with x = Mx * 2^Ex and y = My * 2^Ey (integers), bring both to the
  // smaller exponent and take the integer remainder. (K's %Float does not
  // behave as the IEEE remainder its documentation describes for negative
  // operands, so it is not used.)
  syntax Float ::= #fmod(Float, Float) [function, total]
  rule #fmod(X, Y) => NaN requires isNaN(X) orBool isNaN(Y) orBool isInfinite(X) orBool Y ==Float 0.0
  rule #fmod(X, Y) => X requires notBool isNaN(X) andBool notBool isInfinite(X) andBool isInfinite(Y)
  rule #fmod(X, Y) => X requires X ==Float 0.0 andBool notBool isNaN(Y) andBool Y =/=Float 0.0
  rule #fmod(X, Y) => #withSign(signFloat(X), #fmodPos(absFloat(X), absFloat(Y))) [owise]

  syntax Float ::= #withSign(Bool, Float) [function, total]
  rule #withSign(true, F) => --Float F
  rule #withSign(false, F) => F

  // x, y finite and positive
  syntax Float ::= #fmodPos(Float, Float) [function, total]
                 | #fmodInt(Int, Int, Int, Int) [function, total]
                 | #intTimes2(Int, Int) [function, total]
  rule #fmodPos(X, Y) => #fmodInt(#mant(X), exponentFloat(X) -Int 54, #mant(Y), exponentFloat(Y) -Int 54)
  rule #fmodInt(MX, EX, MY, EY)
    => #intTimes2((MX <<Int (EX -Int minInt(EX, EY))) %Int (MY <<Int (EY -Int minInt(EX, EY))), minInt(EX, EY))
  // R * 2^E as a float. The result is exactly representable, so the low
  // bits dropped to bring R under 55 bits are zero.
  rule #intTimes2(0, _) => 0.0
  rule #intTimes2(R, E) => #intTimes2(R >>Int (log2Int(R) -Int 53), E +Int (log2Int(R) -Int 53))
    requires R >Int 0 andBool log2Int(R) >Int 54
  rule #intTimes2(R, E) => #scale2(Int2Float(R, 53, 11), E) [owise]

  // ------------------------------------------------------------ max, min
  rule <k> #applyB(builtin("math.max"), Args) => #vals(ListItem(#fold(true, #numbers(Args)))) ...</k>
    requires size(Args) >=Int 1 andBool size(#numbers(Args)) ==Int size(Args)
  rule <k> #applyB(builtin("math.min"), Args) => #vals(ListItem(#fold(false, #numbers(Args)))) ...</k>
    requires size(Args) >=Int 1 andBool size(#numbers(Args)) ==Int size(Args)
  rule <k> #applyB(builtin(N), Args) => #numArgError(N, Args, 1) ...</k>
    requires (N ==String "math.max" orBool N ==String "math.min")
     andBool notBool (size(Args) >=Int 1 andBool size(#numbers(Args)) ==Int size(Args))

  // The arguments that convert to numbers, converted.
  syntax List ::= #numbers(List) [function, total]
  rule #numbers(ListItem(V:Val) L) => ListItem(#tonumber(V)) #numbers(L) requires isFloat(#tonumber(V))
  rule #numbers(ListItem(_) L) => #numbers(L) [owise]
  rule #numbers(.List) => .List

  // dmax = a1; for each a: if (a > dmax) dmax = a   (min with <)
  syntax Float ::= #fold(Bool, List) [function, total] | #foldFrom(Bool, Float, List) [function, total]
  rule #fold(IsMax, ListItem(X:Float) L) => #foldFrom(IsMax, X, L)
  rule #fold(_, _) => NaN [owise]
  rule #foldFrom(true, M, ListItem(X:Float) L)  => #foldFrom(true, #if X >Float M #then X #else M #fi, L)
  rule #foldFrom(false, M, ListItem(X:Float) L) => #foldFrom(false, #if X <Float M #then X #else M #fi, L)
  rule #foldFrom(_, M, _) => M [owise]

  // -------------------------------------------------------------- random
  // glibc random() (TYPE_3): r[0] = seed, r[i] = 16807 * r[i-1] mod (2^31 - 1)
  // for i < 31, r[i] = r[i-31] for i < 34, then r[i] = r[i-3] + r[i-31]
  // mod 2^32; the k-th output is r[k + 344] >> 1. <rand> holds the last 31
  // r values; it is seeded with 1 on first use, as C's rand() is.
  // math.random: r = (rand() % RAND_MAX) / RAND_MAX, then r, floor(r*m) + 1
  // or floor(r*(n-m+1)) + m.
  syntax KItem ::= "#randNext" | #randArgs(List)
  rule <k> #applyB(builtin("math.random"), Args) => #randNext ~> #randArgs(Args) ...</k>
  rule <k> #randNext ...</k> <rand> .List => #glibcSeed(1) </rand> [priority(40)]
  rule <k> #randNext => Int2Float((#randOut(W) >>Int 1) %Int 2147483647, 53, 11) /Float 2147483647.0 ...</k>
       <rand> W => range(W, 1, 0) ListItem(#randOut(W)) </rand>
    requires size(W) ==Int 31

  syntax Int ::= #randOut(List) [function, total]
  rule #randOut(W) => ({W [ 0 ]}:>Int +Int {W [ 28 ]}:>Int) %Int 4294967296 requires size(W) ==Int 31
  rule #randOut(_) => 0 [owise]

  rule <k> R:Float ~> #randArgs(.List) => #vals(ListItem(R)) ...</k>
  rule <k> R:Float ~> #randArgs(ListItem(M:Val)) => #vals(ListItem(floorFloat(R *Float #ik(#truncInt({#tonumber(M)}:>Float))) +Float 1.0)) ...</k>
    requires isFloat(#tonumber(M)) andBool 1 <=Int #truncInt({#tonumber(M)}:>Float)
  rule <k> R:Float ~> #randArgs(ListItem(M:Val) ListItem(N:Val))
        => #vals(ListItem(floorFloat(R *Float #ik(#truncInt({#tonumber(N)}:>Float) -Int #truncInt({#tonumber(M)}:>Float) +Int 1))
                          +Float #ik(#truncInt({#tonumber(M)}:>Float)))) ...</k>
    requires isFloat(#tonumber(M)) andBool isFloat(#tonumber(N))
     andBool #truncInt({#tonumber(M)}:>Float) <=Int #truncInt({#tonumber(N)}:>Float)
  rule <k> _:Float ~> #randArgs(ListItem(M:Val)) => #badArg(1, "interval is empty") ...</k>
    requires isFloat(#tonumber(M)) andBool 1 >Int #truncInt({#tonumber(M)}:>Float)
  rule <k> _:Float ~> #randArgs(ListItem(M:Val) ListItem(N:Val)) => #badArg(2, "interval is empty") ...</k>
    requires isFloat(#tonumber(M)) andBool isFloat(#tonumber(N))
     andBool #truncInt({#tonumber(M)}:>Float) >Int #truncInt({#tonumber(N)}:>Float)
  rule <k> _:Float ~> #randArgs(Args) => #error("wrong number of arguments") ...</k> requires size(Args) >Int 2

  // srand((int) x): the seed is a C unsigned int.
  rule <k> #applyB(builtin("math.randomseed"), ListItem(X:Val) _) => #vals(.List) ...</k>
       <rand> _ => #glibcSeed(#truncInt({#tonumber(X)}:>Float) modInt 4294967296) </rand>
    requires isFloat(#tonumber(X))
  rule <k> #applyB(builtin("math.randomseed"), Args) => #numArgError("math.randomseed", Args, 1) ...</k>
    requires notBool (size(Args) >=Int 1 andBool isFloat(#tonumber(#head(Args))))

  // The 31 values r[313..343] for a seed (srandom_r, then 310 discarded
  // outputs). r[0] is the seed as a signed 32-bit int; 0 becomes 1.
  syntax List ::= #glibcSeed(Int) [function, total]
                | #lcgFill(List, Int) [function, total]
                | #addFill(List, Int) [function, total]
  rule #glibcSeed(S) => range(#addFill(#lcgFill(ListItem(#if S ==Int 0 #then 1 #else S #fi), 1), 31), 313, 0)
  rule #lcgFill(L, I) => #lcgFill(L ListItem(#lcg(#signed32({L [ I -Int 1 ]}:>Int))), I +Int 1) requires I <=Int 30
  rule #lcgFill(L, _) => L [owise]
  rule #addFill(L, I) => #addFill(L ListItem({L [ I -Int 31 ]}:>Int modInt 4294967296), I +Int 1)
    requires I >=Int 31 andBool I <Int 34
  rule #addFill(L, I) => #addFill(L ListItem(({L [ I -Int 31 ]}:>Int +Int {L [ I -Int 3 ]}:>Int) modInt 4294967296), I +Int 1)
    requires I >=Int 34 andBool I <Int 344
  rule #addFill(L, _) => L [owise]

  syntax Int ::= #signed32(Int) [function, total] | #lcg(Int) [function, total]
  rule #signed32(X) => X -Int 4294967296 requires X >=Int 2147483648
  rule #signed32(X) => X [owise]
  // word = 16807 * lo - 2836 * hi with C's truncating division
  rule #lcg(W) => #lcgFix(16807 *Int (W %Int 127773) -Int 2836 *Int (W /Int 127773))
  syntax Int ::= #lcgFix(Int) [function, total]
  rule #lcgFix(W) => W +Int 2147483647 requires W <Int 0
  rule #lcgFix(W) => W [owise]
endmodule
