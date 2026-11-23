// The string library (lstrlib.c). Pattern matching is in lua-pattern.k,
// string.format in lua-format.k.

requires "lua-math.k"
requires "lua-pattern.k"
requires "lua-format.k"

module LUA-STRING
  imports LUA-MATH
  imports LUA-PATTERN
  imports LUA-FORMAT

  // Table 5 is the string library. All strings share one metatable (table
  // 6, see <strMeta>) whose __index is the string table, which is what lets
  // s:upper() work.

  syntax Map ::= "#stringLib" [function, total]
  rule #stringLib =>
         "byte"    |-> builtin("string.byte")    "char"    |-> builtin("string.char")
         "dump"    |-> builtin("string.dump")    "find"    |-> builtin("string.find")
         "format"  |-> builtin("string.format")  "gfind"   |-> builtin("string.gmatch")
         "gmatch"  |-> builtin("string.gmatch")  "gsub"    |-> builtin("string.gsub")
         "len"     |-> builtin("string.len")     "lower"   |-> builtin("string.lower")
         "match"   |-> builtin("string.match")   "rep"     |-> builtin("string.rep")
         "reverse" |-> builtin("string.reverse") "sub"     |-> builtin("string.sub")
         "upper"   |-> builtin("string.upper")

  // Arguments: strings, or numbers converted with %.14g (luaL_checklstring).
  syntax Bool ::= #isStrArg(Val) [function, total]
  rule #isStrArg(V) => #tostringCoerce(V) =/=K nil
  syntax String ::= #str(Val) [function, total]
  rule #str(V) => {#tostringCoerce(V)}:>String requires #isStrArg(V)
  rule #str(_) => "" [owise]

  // The first argument of a string function must be a string.
  rule <k> #applyB(builtin(N), ListItem(V:Val) _) => #argError(1, #shortName(N), "string", V) ...</k>
    requires #startsWith(N, "string.") andBool N =/=String "string.char" andBool notBool #isStrArg(V)
  rule <k> #applyB(builtin(N), .List)
        => #badArg(1, "string expected, got no value") ...</k>
    requires #startsWith(N, "string.") andBool N =/=String "string.char"

  // posrelat: negative positions count from the end; below that is 0.
  syntax Int ::= #posrelat(Int, Int) [function, total]
  rule #posrelat(P, L) => #posrelat0(#if P <Int 0 #then P +Int L +Int 1 #else P #fi)
  syntax Int ::= #posrelat0(Int) [function, total]
  rule #posrelat0(P) => #if P >=Int 0 #then P #else 0 #fi

  // ============================================================ basics
  rule <k> #applyB(builtin("string.len"), ListItem(S:Val) _) => #vals(ListItem(Int2Float(lengthString(#str(S)), 53, 11))) ...</k>
    requires #isStrArg(S)

  // sub(s, i = 1, j = -1)
  rule <k> #applyB(builtin("string.sub"), ListItem(S:Val) Rest) =>
         #vals(ListItem(#sub(#str(S), #posrelat(#optInt(#head(Rest), 1), lengthString(#str(S))),
                                      #posrelat(#optInt(#head(#tail(Rest)), -1), lengthString(#str(S)))))) ...</k>
    requires #isStrArg(S)
  syntax String ::= #sub(String, Int, Int) [function, total]
  rule #sub(S, I, J) => substrString(S, maxInt(I, 1) -Int 1, minInt(J, lengthString(S)))
    requires maxInt(I, 1) <=Int minInt(J, lengthString(S))
  rule #sub(_, _, _) => "" [owise]

  rule <k> #applyB(builtin("string.upper"), ListItem(S:Val) _) => #vals(ListItem(#upper(#str(S)))) ...</k> requires #isStrArg(S)
  rule <k> #applyB(builtin("string.lower"), ListItem(S:Val) _) => #vals(ListItem(#lower(#str(S)))) ...</k> requires #isStrArg(S)
  syntax String ::= #upper(String) [function, total] | #upperFrom(String, Int, String) [function, total]
  rule #upper(S) => #upperFrom(S, 0, "")
  rule #upperFrom(S, I, Acc) => Acc requires I >=Int lengthString(S)
  rule #upperFrom(S, I, Acc) => #upperFrom(S, I +Int 1, Acc +String chrChar(ordChar(#charAt(S, I)) -Int 32))
    requires I <Int lengthString(S) andBool ordChar(#charAt(S, I)) >=Int 97 andBool ordChar(#charAt(S, I)) <=Int 122
  rule #upperFrom(S, I, Acc) => #upperFrom(S, I +Int 1, Acc +String #charAt(S, I)) [owise]

  rule <k> #applyB(builtin("string.rep"), ListItem(S:Val) ListItem(N:Val) _) => #vals(ListItem(#rep(#str(S), #optInt(N, 0)))) ...</k>
    requires #isStrArg(S) andBool isFloat(#tonumber(N))
  rule <k> #applyB(builtin("string.rep"), ListItem(S:Val) Rest) => #badArg(2, "number expected, got " +String #typeOrNone(Rest)) ...</k>
    requires #isStrArg(S) andBool notBool isFloat(#tonumber(#head(Rest)))
  rule <k> #applyB(builtin("string.reverse"), ListItem(S:Val) _) => #vals(ListItem(#reverse(#str(S), ""))) ...</k> requires #isStrArg(S)
  syntax String ::= #reverse(String, String) [function, total]
  rule #reverse("", Acc) => Acc
  rule #reverse(S, Acc) => #reverse(substrString(S, 1, lengthString(S)), #charAt(S, 0) +String Acc) [owise]

  // byte(s, i = 1, j = i)
  rule <k> #applyB(builtin("string.byte"), ListItem(S:Val) Rest) =>
         #vals(#bytes(#str(S), maxInt(#posrelat(#optInt(#head(Rest), 1), lengthString(#str(S))), 1),
                      minInt(#posrelat(#optInt(#head(#tail(Rest)), #optInt(#head(Rest), 1)), lengthString(#str(S))), lengthString(#str(S))))) ...</k>
    requires #isStrArg(S)
  syntax List ::= #bytes(String, Int, Int) [function, total]
  rule #bytes(S, I, J) => ListItem(Int2Float(ordChar(#charAt(S, I -Int 1)), 53, 11)) #bytes(S, I +Int 1, J) requires I <=Int J
  rule #bytes(_, _, _) => .List [owise]

  // char(...): each argument an integer 0..255
  rule <k> #applyB(builtin("string.char"), Args) => #chars(Args, 1, "") ...</k>
  syntax KItem ::= #chars(List, Int, String)
  rule <k> #chars(.List, _, Acc) => #vals(ListItem(Acc)) ...</k>
  rule <k> #chars(ListItem(V:Val) L, N, Acc) => #chars(L, N +Int 1, Acc +String chrChar(#truncInt({#tonumber(V)}:>Float))) ...</k>
    requires isFloat(#tonumber(V)) andBool #truncInt({#tonumber(V)}:>Float) >=Int 0 andBool #truncInt({#tonumber(V)}:>Float) <=Int 255
  rule <k> #chars(ListItem(V:Val) _, N, _) => #badArg(N, "invalid value") ...</k>
    requires isFloat(#tonumber(V))
     andBool notBool (#truncInt({#tonumber(V)}:>Float) >=Int 0 andBool #truncInt({#tonumber(V)}:>Float) <=Int 255)
  rule <k> #chars(ListItem(V:Val) _, N, _) => #argError(N, "char", "number", V) ...</k>
    requires notBool isFloat(#tonumber(V))

  rule <k> #applyB(builtin("string.dump"), _) => #error("unable to dump given function") ...</k>

  // ============================================================ format
  rule <k> #applyB(builtin("string.format"), ListItem(F:Val) Args) => #fmtResult(#format(#str(F), 0, Args, 2, "")) ...</k>
    requires #isStrArg(F)
  syntax KItem ::= #fmtResult(FmtRes)
  rule <k> #fmtResult(#fok(S)) => #vals(ListItem(S)) ...</k>
  rule <k> #fmtResult(#ferr(M)) => #error(M) ...</k>
  rule <k> #fmtResult(#fbad(N, M)) => #badArg(N, M) ...</k>

  // ============================================================ find, match
  // find(s, p, init = 1, plain): plain search if asked or if p has no
  // special characters; otherwise try the pattern at init, init+1, ...
  // (only at init if it starts with '^').
  syntax Bool ::= #hasSpecials(String) [function, total]
  rule #hasSpecials(P) => findChar(P, "^$*+?.([%-", 0) >=Int 0

  rule <k> #applyB(builtin(N), ListItem(S:Val) ListItem(P:Val) Rest) =>
         #find(#str(S), #str(P), #clampInit(#posrelat(#optInt(#head(Rest), 1), lengthString(#str(S))) -Int 1, lengthString(#str(S))),
               N ==String "string.find", N ==String "string.find" andBool #truthy(#head(#tail(Rest)))) ...</k>
    requires (N ==String "string.find" orBool N ==String "string.match") andBool #isStrArg(S) andBool #isStrArg(P)
  rule <k> #applyB(builtin(N), ListItem(S:Val) Rest) => #argError(2, #shortName(N), "string", #head(Rest)) ...</k>
    requires (N ==String "string.find" orBool N ==String "string.match" orBool N ==String "string.gmatch" orBool N ==String "string.gsub")
     andBool #isStrArg(S) andBool notBool #isStrArg(#head(Rest))

  syntax Int ::= #clampInit(Int, Int) [function, total]
  rule #clampInit(I, _) => 0 requires I <Int 0
  rule #clampInit(I, L) => L requires I >Int L
  rule #clampInit(I, _) => I [owise]

  // #find(subject, pattern, init (0-based), is find, plain)
  syntax KItem ::= #find(String, String, Int, Bool, Bool) [function, total]
                 | #findLoop(String, String, Int, Bool, Bool) [function, total]
                 | #findRes(MRes, String, String, Int, Bool, Bool) [function, total]
  rule #find(S, P, I, F, Plain) => #plainFind(S, P, findString(S, P, I))
    requires F andBool (Plain orBool notBool #hasSpecials(P))
  rule #find(S, P, I, F, Plain) => #findLoop(S, substrString(P, 1, lengthString(P)), I, F, true)
    requires notBool (F andBool (Plain orBool notBool #hasSpecials(P))) andBool #startsWith(P, "^")
  rule #find(S, P, I, F, Plain) => #findLoop(S, P, I, F, false)
    requires notBool (F andBool (Plain orBool notBool #hasSpecials(P))) andBool notBool #startsWith(P, "^")
  syntax KItem ::= #plainFind(String, String, Int) [function, total]
  rule #plainFind(_, _, -1) => #vals(ListItem(nil))
  rule #plainFind(_, P, I) => #vals(ListItem(Int2Float(I +Int 1, 53, 11)) ListItem(Int2Float(I +Int lengthString(P), 53, 11))) [owise]

  rule #findLoop(S, P, I, F, A) => #findRes(#match(S, P, I, 0, .List), S, P, I, F, A)
  rule #findRes(#merr(M), _, _, _, _, _) => #error(M)
  rule #findRes(#mok(_, Cs), _, _, _, _, _) => #error("unfinished capture") requires #hasUnfinished(Cs)
  rule #findRes(#mok(E, Cs), S, _, I, true, _) =>
         #vals(ListItem(Int2Float(I +Int 1, 53, 11)) ListItem(Int2Float(E, 53, 11)) #capVals(S, Cs, I, E, false))
    requires notBool #hasUnfinished(Cs)
  rule #findRes(#mok(E, Cs), S, _, I, false, _) => #vals(#capVals(S, Cs, I, E, true))
    requires notBool #hasUnfinished(Cs)
  rule #findRes(#mfail, S, P, I, F, false) => #findLoop(S, P, I +Int 1, F, false) requires I <Int lengthString(S)
  rule #findRes(#mfail, _, _, _, _, _) => #vals(ListItem(nil)) [owise]

  // ============================================================ gmatch
  // An iterator holding (subject, pattern, next position) in <iters>. As in
  // 5.1, '^' is not an anchor here. An empty match advances by one.
  rule <k> #applyB(builtin("string.gmatch"), ListItem(S:Val) ListItem(P:Val) _) => #vals(ListItem(gmatchIter(I))) ...</k>
       <iters> Its => Its [ I <- #gm(#str(S), #str(P), 0) ] </iters>
       <nextFn> I => I +Int 1 </nextFn>
    requires #isStrArg(S) andBool #isStrArg(P)
  syntax GmState ::= #gm(String, String, Int)
  rule <k> #applyB(gmatchIter(I), _) => #gmatchStep(I, S, P, Pos) ...</k>
       <iters> ... I |-> #gm(S, P, Pos) ... </iters>
  syntax KItem ::= #gmatchStep(Int, String, String, Int) | #gmatchRes(Int, MRes, String, String, Int)
  rule <k> #gmatchStep(_, S, _, Pos) => #vals(.List) ...</k> requires Pos >Int lengthString(S)
  rule <k> #gmatchStep(I, S, P, Pos) => #gmatchRes(I, #match(S, P, Pos, 0, .List), S, P, Pos) ...</k>
    requires Pos <=Int lengthString(S)
  rule <k> #gmatchRes(_, #merr(M), _, _, _) => #error(M) ...</k>
  rule <k> #gmatchRes(I, #mfail, S, P, Pos) => #gmatchStep(I, S, P, Pos +Int 1) ...</k>
  rule <k> #gmatchRes(_, #mok(_, Cs), _, _, _) => #error("unfinished capture") ...</k> requires #hasUnfinished(Cs)
  rule <k> #gmatchRes(I, #mok(E, Cs), S, _, Pos) => #vals(#capVals(S, Cs, Pos, E, true)) ...</k>
       <iters> ... I |-> #gm(_, _, (_ => #if E ==Int Pos #then E +Int 1 #else E #fi)) ... </iters>
    requires notBool #hasUnfinished(Cs)

  // ============================================================ gsub
  // gsub(s, p, repl, n = #s + 1): repl is a string (with %0-%9 and %%), a
  // table (indexed by the first capture) or a function (called with the
  // captures); a false/nil result keeps the original match.
  rule <k> #applyB(builtin("string.gsub"), ListItem(S:Val) ListItem(P:Val) ListItem(R:Val) Rest) =>
         #gsub(#str(S), #gsubPat(#str(P)), #startsWith(#str(P), "^"), R,
               #optInt(#head(Rest), lengthString(#str(S)) +Int 1), 0, 0, "") ...</k>
    requires #isStrArg(S) andBool #isStrArg(P) andBool (#isStrArg(R) orBool isTRef(R) orBool #type(R) ==String "function")
  rule <k> #applyB(builtin("string.gsub"), ListItem(S:Val) ListItem(P:Val) Rest)
        => #badArg(3, "string/function/table expected") ...</k>
    requires #isStrArg(S) andBool #isStrArg(P)
     andBool notBool (#isStrArg(#head(Rest)) orBool isTRef(#head(Rest)) orBool #type(#head(Rest)) ==String "function")

  syntax String ::= #gsubPat(String) [function, total]
  rule #gsubPat(P) => substrString(P, 1, lengthString(P)) requires #startsWith(P, "^")
  rule #gsubPat(P) => P [owise]

  // #gsub(subject, pattern, anchored, repl, max, position, count, output)
  syntax KItem ::= #gsub(String, String, Bool, Val, Int, Int, Int, String)
                 | #gsubMatched(MRes, String, String, Bool, Val, Int, Int, Int, String)
                 | #gsubAdd(Int, String, String, Bool, Val, Int, Int, Int, String)
                 | #gsubStep(Int, String, String, Bool, Val, Int, Int, Int, String)
                 | #gsubDone(String, Int)
  rule <k> #gsub(S, _, _, _, Max, Src, N, Acc) => #gsubDone(Acc +String substrString(S, Src, lengthString(S)), N) ...</k>
    requires N >=Int Max
  rule <k> #gsub(S, P, A, R, Max, Src, N, Acc) => #gsubMatched(#match(S, P, Src, 0, .List), S, P, A, R, Max, Src, N, Acc) ...</k>
    requires N <Int Max
  rule <k> #gsubMatched(#merr(M), _, _, _, _, _, _, _, _) => #error(M) ...</k>
  rule <k> #gsubMatched(#mfail, S, P, A, R, Max, Src, N, Acc) => #gsubStep(-1, S, P, A, R, Max, Src, N, Acc) ...</k>
  rule <k> #gsubMatched(#mok(_, Cs), _, _, _, _, _, _, _, _) => #error("unfinished capture") ...</k>
    requires #hasUnfinished(Cs)
  rule <k> #gsubMatched(#mok(E, Cs), S, P, A, R, Max, Src, N, Acc)
        => #gsubValue(R, S, Src, E, Cs) ~> #gsubAdd(E, S, P, A, R, Max, Src, N +Int 1, Acc) ...</k>
    requires notBool #hasUnfinished(Cs)

  syntax KItem ::= #gsubValue(Val, String, Int, Int, List)
  rule <k> #gsubValue(R, S, Src, E, Cs) => #addS(#str(R), 0, S, Src, E, Cs, "") ...</k> requires #isStrArg(R)
  rule <k> #gsubValue(T:TRef, S, Src, E, Cs) => #index(T, #head(#capVals(S, Cs, Src, E, true))) ...</k>
  rule <k> #gsubValue(F, S, Src, E, Cs) => #apply(F, #capVals(S, Cs, Src, E, true)) ~> #first ...</k>
    requires #type(F) ==String "function"

  rule <k> V:Val ~> #gsubAdd(E, S, P, A, R, Max, Src, N, Acc)
        => #gsubStep(E, S, P, A, R, Max, Src, N, Acc +String substrString(S, Src, E)) ...</k>
    requires notBool #truthy(V)
  rule <k> V:Val ~> #gsubAdd(E, S, P, A, R, Max, Src, N, Acc)
        => #gsubStep(E, S, P, A, R, Max, Src, N, Acc +String #str(V)) ...</k>
    requires #truthy(V) andBool #isStrArg(V)
  rule <k> V:Val ~> #gsubAdd(_, _, _, _, _, _, _, _, _) => #error("invalid replacement value (a " +String #type(V) +String ")") ...</k>
    requires #truthy(V) andBool notBool #isStrArg(V)

  // Move on: past a non-empty match, else copy one character; stop at the
  // end, or after the first try if anchored.
  rule <k> #gsubStep(E, S, P, A, R, Max, Src, N, Acc) => #gsubNext(S, P, A, R, Max, E, N, Acc) ...</k>
    requires E >Int Src
  rule <k> #gsubStep(E, S, P, A, R, Max, Src, N, Acc) => #gsubNext(S, P, A, R, Max, Src +Int 1, N, Acc +String #charAt(S, Src)) ...</k>
    requires notBool E >Int Src andBool Src <Int lengthString(S)
  rule <k> #gsubStep(_, _, _, _, _, _, _, N, Acc) => #gsubDone(Acc, N) ...</k> [owise]
  syntax KItem ::= #gsubNext(String, String, Bool, Val, Int, Int, Int, String)
  rule <k> #gsubNext(S, _, true, _, _, Src, N, Acc) => #gsubDone(Acc +String substrString(S, Src, lengthString(S)), N) ...</k>
  rule <k> #gsubNext(S, P, false, R, Max, Src, N, Acc) => #gsub(S, P, false, R, Max, Src, N, Acc) ...</k>
  rule <k> #gsubDone(Acc, N) => #vals(ListItem(Acc) ListItem(Int2Float(N, 53, 11))) ...</k>

  // add_s: copy the replacement string, expanding %0 (whole match), %1-%9
  // (captures) and %x (x itself, so %% is %).
  syntax KItem ::= #addS(String, Int, String, Int, Int, List, String) [function, total]
  rule #addS(R, I, _, _, _, _, Acc) => Acc requires I >=Int lengthString(R)
  rule #addS(R, I, S, Si, E, Cs, Acc) => #addS(R, I +Int 1, S, Si, E, Cs, Acc +String #charAt(R, I))
    requires I <Int lengthString(R) andBool #charAt(R, I) =/=String "%"
  rule #addS(R, I, S, Si, E, Cs, Acc) => #addS(R, I +Int 2, S, Si, E, Cs, Acc +String #charAt(R, I +Int 1))
    requires I <Int lengthString(R) andBool #charAt(R, I) ==String "%" andBool notBool #isDigitAt(R, I +Int 1)
  rule #addS(R, I, S, Si, E, Cs, Acc) => #addS(R, I +Int 2, S, Si, E, Cs, Acc +String substrString(S, Si, E))
    requires I <Int lengthString(R) andBool #charAt(R, I) ==String "%" andBool #charAt(R, I +Int 1) ==String "0"
  rule #addS(R, I, S, Si, E, Cs, Acc) => #addS(R, I +Int 2, S, Si, E, Cs, Acc +String #oneCapture(S, Cs, ordChar(#charAt(R, I +Int 1)) -Int 49, Si, E))
    requires I <Int lengthString(R) andBool #charAt(R, I) ==String "%" andBool #isDigitAt(R, I +Int 1)
     andBool #charAt(R, I +Int 1) =/=String "0"
     andBool #oneCaptureOk(Cs, ordChar(#charAt(R, I +Int 1)) -Int 49)
  rule #addS(_, _, _, _, _, _, _) => #error("invalid capture index") [owise]

  // push_onecapture as a string: capture L, or the whole match for %1
  // when there are no captures.
  syntax Bool ::= #oneCaptureOk(List, Int) [function, total]
  rule #oneCaptureOk(Cs, L) => L <Int size(Cs) orBool L ==Int 0
  syntax String ::= #oneCapture(String, List, Int, Int, Int) [function, total]
  rule #oneCapture(S, Cs, L, _, _) => #str(#capVal(S, Cs [ L ])) requires L <Int size(Cs)
  rule #oneCapture(S, _, _, Si, E) => substrString(S, Si, E) [owise]
endmodule
