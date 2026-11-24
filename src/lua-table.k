// Tables: constructors, traversal (next, pairs, ipairs) and the table
// library (ltablib.c).

requires "lua-function.k"

module LUA-TABLE
  imports LUA-FUNCTION

  syntax Float ::= #ik(Int) [function, total]   // an integer key
  rule #ik(I) => Int2Float(I, 53, 11)

  // ===================================================== constructors

  // As lcode.c/lvm.c do it: fields are evaluated in order; `[k] = v` and
  // `name = v` are stored as they come, positional values are stored at the
  // end (OP_SETLIST), nils included. The last field, if it is a call or
  // `...`, contributes all of its values. The array part gets the size
  // NEWTABLE asks for (the positional count, rounded up as luaO_int2fb
  // does), grown to the number of values actually stored.
  rule <k> T:TableCons => #tcons(#fieldsOf(T)) ...</k>

  syntax List ::= #fieldsOf(TableCons)     [function, total]
                | #fields2list(FieldList)  [function, total]
  rule #fieldsOf({ FL:FieldList }) => #fields2list(FL)
  rule #fieldsOf(_) => .List [owise]
  rule #fields2list(F:Field) => ListItem(F)
  rule #fields2list(F:Field _:FieldSep) => ListItem(F)
  rule #fields2list(F:Field _:FieldSep FL:FieldList) => ListItem(F) #fields2list(FL)

  syntax Bool ::= #isMultiExp(K) [function, total]
  rule #isMultiExp(E) => #isCall(E) orBool isVararg(E)

  syntax KItem ::= #tcons(List) | #tconsStart(List)
                 | #tfields(Int, List, List) | #tkeyed(Int, List, List) | #tnamed(Int, String, List, List)
                 | #tpos(Int, List, List) | #tlast(Int, List) | #tsetlist(Int, List, Int)
  rule <k> #tcons(Fs) => #newTable(.Map) ~> #tconsStart(Fs) ...</k>
  rule <k> tref(T) ~> #tconsStart(Fs) => #tfields(T, Fs, .List) ...</k>

  rule <k> #tfields(T, ListItem([ K:Exp ] = V:Exp) Fs, Pos)
        => #evalSingles(ListItem(K) ListItem(V)) ~> #tkeyed(T, Fs, Pos) ...</k>
  rule <k> #vals(ListItem(K:Val) ListItem(V:Val)) ~> #tkeyed(T, Fs, Pos)
        => #setIndex(tref(T), K, V) ~> #tfields(T, Fs, Pos) ...</k>
  rule <k> #tfields(T, ListItem((N:Name = V:Exp):Field) Fs, Pos) => V ~> #tnamed(T, Name2String(N), Fs, Pos) ...</k>
  rule <k> V:Val ~> #tnamed(T, K, Fs, Pos) => #setIndex(tref(T), K, V) ~> #tfields(T, Fs, Pos) ...</k>
  rule <k> #tfields(T, ListItem(E:Exp), Pos) => #multi(E) ~> #tlast(T, Pos) ...</k>
    requires #isMultiExp(E)
  rule <k> #tfields(T, ListItem(E:Exp) Fs, Pos) => E ~> #tpos(T, Fs, Pos) ...</k>
    requires Fs =/=K .List orBool notBool #isMultiExp(E)
  rule <k> V:Val ~> #tpos(T, Fs, Pos) => #tfields(T, Fs, Pos ListItem(V)) ...</k>
  rule <k> #tfields(T, .List, Pos) => #tsetlist(T, Pos, size(Pos)) ...</k>
  rule <k> #vals(Vs) ~> #tlast(T, Pos) => #tsetlist(T, Pos Vs, size(Pos)) ...</k>
  rule <k> #tsetlist(T, Vs, Na) => tref(T) ...</k>
       <tables> ... T |-> #tbl((M => #setlist(M, Vs, 1)), (_ => maxInt(#fbRound(Na), size(Vs))), _) ... </tables>

  syntax Map ::= #setlist(Map, List, Int) [function, total]
  rule #setlist(M, ListItem(V:Val) L, I) => #setlist(#rawset(M, #ik(I), V), L, I +Int 1)
  rule #setlist(M, _, _) => M [owise]

  // luaO_fb2int(luaO_int2fb(n)): n rounded up to the form (8..15) * 2^e.
  syntax Int ::= #fbRound(Int) [function, total] | #fbRound2(Int, Int) [function, total]
  rule #fbRound(X) => #fbRound2(X, 0)
  rule #fbRound2(X, E) => #fbRound2((X +Int 1) >>Int 1, E +Int 1) requires X >=Int 16
  rule #fbRound2(X, E) => X <<Int E [owise]

  // ===================================================== traversal

  // next(t, k) returns the smallest key after k in a fixed order: numbers
  // (ascending), strings, booleans, tables, functions. Lua's own order
  // depends on its hash function; for the array part 1..n it is the same.
  // Being an order on values, it stays well defined when the current key is
  // cleared during the traversal, as Lua allows.
  syntax Int ::= #keyRank(Val) [function, total]
  rule #keyRank(_:Float)  => 0
  rule #keyRank(_:String) => 1
  rule #keyRank(_:Bool)   => 2
  rule #keyRank(_:TRef)   => 3
  rule #keyRank(_:Fn)     => 4
  rule #keyRank(_:Thread) => 5
  rule #keyRank(_)        => 5 [owise]

  syntax Bool ::= #keyLt(Val, Val) [function, total]
  rule #keyLt(A, B) => #keyRank(A) <Int #keyRank(B) requires #keyRank(A) =/=Int #keyRank(B)
  rule #keyLt(A:Float, B:Float)   => A <Float B
  rule #keyLt(A:String, B:String) => A <String B
  rule #keyLt(A:Bool, B:Bool)     => notBool A andBool B
  rule #keyLt(tref(I), tref(J))   => I <Int J
  rule #keyLt(builtin(X), builtin(Y)) => X <String Y
  rule #keyLt(builtin(_), closure(_)) => true
  rule #keyLt(closure(I), closure(J)) => I <Int J
  rule #keyLt(thread(I), thread(J)) => I <Int J
  rule #keyLt(_, _) => false [owise]

  // Smallest key after `After` (nil: the first key); nil if none.
  syntax Val ::= #nextKey(List, Val, Val) [function, total]
  rule #nextKey(ListItem(X:Val) L, After, Best) => #nextKey(L, After, X)
    requires (After ==K nil orBool #keyLt(After, X)) andBool (Best ==K nil orBool #keyLt(X, Best))
  rule #nextKey(ListItem(_) L, After, Best) => #nextKey(L, After, Best) [owise]
  rule #nextKey(.List, _, Best) => Best

  syntax List ::= #nextPair(Map, Val) [function, total]
  rule #nextPair(_, nil) => ListItem(nil)
  rule #nextPair(M, K) => ListItem(K) ListItem(#rawget(M, K)) [owise]

  rule <k> #applyB(builtin("next"), ListItem(tref(T)) Rest)
        => #vals(#nextPair(M, #nextKey(keys_list(M), #head(Rest), nil))) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  rule <k> #applyB(builtin("pairs"), ListItem(tref(T)) _)
        => #vals(ListItem(builtin("next")) ListItem(tref(T)) ListItem(nil)) ...</k>
  rule <k> #applyB(builtin("ipairs"), ListItem(tref(T)) _)
        => #vals(ListItem(builtin("ipairs.aux")) ListItem(tref(T)) ListItem(0.0)) ...</k>
  // ipairs stops at the first nil, reading t[i] raw.
  rule <k> #applyB(builtin("ipairs.aux"), ListItem(tref(T)) ListItem(I:Float) _)
        => #vals(#ipairsStep(I +Float 1.0, #rawget(M, I +Float 1.0))) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  syntax List ::= #ipairsStep(Float, Val) [function, total]
  rule #ipairsStep(_, nil) => .List
  rule #ipairsStep(I, V) => ListItem(I) ListItem(V) [owise]

  rule <k> #applyB(builtin(N), ListItem(V:Val) _) => #argError(1, #shortName(N), "table", V) ...</k>
    requires (N ==String "next" orBool N ==String "pairs" orBool N ==String "ipairs"
              orBool N ==String "table.insert" orBool N ==String "table.remove" orBool N ==String "table.concat"
              orBool N ==String "table.sort" orBool N ==String "table.getn" orBool N ==String "table.maxn"
              orBool N ==String "table.foreach" orBool N ==String "table.foreachi")
     andBool notBool isTRef(V)

  // "bad argument #N to 'f' (T expected, got U)"; the name comes from the
  // call site (#badArg), the second argument is only documentation.
  syntax KItem ::= #argError(Int, String, String, Val)
  rule <k> #argError(I, _, Want, V) => #badArg(I, Want +String " expected, got " +String #type(V)) ...</k>

  syntax String ::= #shortName(String) [function, total]
  rule #shortName(N) => substrString(N, findString(N, ".", 0) +Int 1, lengthString(N))
    requires findString(N, ".", 0) >=Int 0
  rule #shortName(N) => N [owise]

  // ===================================================== table library

  syntax Map ::= "#tableLib" [function, total]
  rule #tableLib =>
         "concat"   |-> builtin("table.concat")
         "foreach"  |-> builtin("table.foreach")
         "foreachi" |-> builtin("table.foreachi")
         "getn"     |-> builtin("table.getn")
         "insert"   |-> builtin("table.insert")
         "maxn"     |-> builtin("table.maxn")
         "remove"   |-> builtin("table.remove")
         "setn"     |-> builtin("table.setn")
         "sort"     |-> builtin("table.sort")

  rule <k> #applyB(builtin("table.getn"), ListItem(tref(T)) _) => #vals(ListItem(#lenF(M, A))) ...</k>
       <tables> ... T |-> #tbl(M, A, _) ... </tables>
  rule <k> #applyB(builtin("table.setn"), _) => #error("'setn' is obsolete") ...</k>

  // Largest positive numeric key (any number, not only integers).
  rule <k> #applyB(builtin("table.maxn"), ListItem(tref(T)) _) => #vals(ListItem(#maxn(keys_list(M), 0.0))) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  syntax Float ::= #maxn(List, Float) [function, total]
  rule #maxn(ListItem(K:Float) L, Max) => #maxn(L, K) requires K >Float Max
  rule #maxn(ListItem(_) L, Max) => #maxn(L, Max) [owise]
  rule #maxn(.List, Max) => Max

  // ------------------------------------------------------------ insert
  // insert(t, v) appends at #t + 1; insert(t, pos, v) shifts t[pos..] up.
  syntax KItem ::= #tinsert(Int, Val, Val)
  rule <k> #applyB(builtin("table.insert"), ListItem(tref(T)) ListItem(V:Val)) => #vals(.List) ...</k>
       <tables> ... T |-> #tbl((M => #rawset(M, #ik(#border(M, A) +Int 1), V)), A, _) ... </tables>
  rule <k> #applyB(builtin("table.insert"), ListItem(tref(T)) ListItem(P:Val) ListItem(V:Val))
        => #tinsert(T, #tonumber(P), V) ...</k>
  rule <k> #applyB(builtin("table.insert"), ListItem(tref(_)) Rest) => #error("wrong number of arguments to 'insert'") ...</k>
    requires size(Rest) <Int 1 orBool size(Rest) >Int 2
  rule <k> #tinsert(T, P:Float, V) => #vals(.List) ...</k>
       <tables> ... T |-> #tbl((M => #rawset(#shiftUp(M, maxInt(#border(M, A) +Int 1, #truncInt(P)), #truncInt(P)), #ik(#truncInt(P)), V)), A, _) ... </tables>
  rule <k> #tinsert(_, P, _) => #argError(2, "insert", "number", P) ...</k> [owise]

  // t[i] = t[i - 1] for i = from, from - 1, ..., pos + 1
  syntax Map ::= #shiftUp(Map, Int, Int) [function, total]
  rule #shiftUp(M, I, P) => #shiftUp(#rawset(M, #ik(I), #rawget(M, #ik(I -Int 1))), I -Int 1, P) requires I >Int P
  rule #shiftUp(M, _, _) => M [owise]

  // ------------------------------------------------------------ remove
  // remove(t [, pos]) returns t[pos] (default #t) and shifts the rest down;
  // a position outside 1..#t removes nothing and returns nothing.
  syntax KItem ::= #tremove(Int, Map, Int, Int)
  rule <k> #applyB(builtin("table.remove"), ListItem(tref(T))) => #tremove(T, M, #border(M, A), #border(M, A)) ...</k>
       <tables> ... T |-> #tbl(M, A, _) ... </tables>
  rule <k> #applyB(builtin("table.remove"), ListItem(tref(T)) ListItem(P:Float) _)
        => #tremove(T, M, #border(M, A), #truncInt(P)) ...</k>
       <tables> ... T |-> #tbl(M, A, _) ... </tables>
  rule <k> #tremove(_, _, E, P) => #vals(.List) ...</k> requires notBool (1 <=Int P andBool P <=Int E)
  rule <k> #tremove(T, M0, E, P) => #vals(ListItem(#rawget(M0, #ik(P)))) ...</k>
       <tables> ... T |-> #tbl((M => #rawset(#shiftDown(M, P, E), #ik(E), nil)), _, _) ... </tables>
    requires 1 <=Int P andBool P <=Int E

  // t[i] = t[i + 1] for i = pos, ..., e - 1
  syntax Map ::= #shiftDown(Map, Int, Int) [function, total]
  rule #shiftDown(M, I, E) => #shiftDown(#rawset(M, #ik(I), #rawget(M, #ik(I +Int 1))), I +Int 1, E) requires I <Int E
  rule #shiftDown(M, _, _) => M [owise]

  // ------------------------------------------------------------ concat
  // concat(t [, sep [, i [, j]]]): strings and numbers only.
  rule <k> #applyB(builtin("table.concat"), ListItem(tref(T)) Rest)
        => #tconcat(M, #optInt(#head(#tail(Rest)), 1), #optInt(#head(#tail(#tail(Rest))), #border(M, A)),
                    #optStr(#head(Rest)), "") ~> #toVals ...</k>
       <tables> ... T |-> #tbl(M, A, _) ... </tables>

  // A String on success, an #error on a bad element.
  syntax KItem ::= #tconcat(Map, Int, Int, String, String) [function, total]
  rule #tconcat(M, I, J, Sep, Acc) => #tconcat(M, I +Int 1, J, Sep,
                Acc +String {#tostringCoerce(#rawget(M, #ik(I)))}:>String +String #if I <Int J #then Sep #else "" #fi)
    requires I <=Int J andBool #tostringCoerce(#rawget(M, #ik(I))) =/=K nil
  rule #tconcat(_, I, J, _, _) => #error("invalid value (at index " +String Int2String(I) +String ") in table for 'concat'")
    requires I <=Int J [owise]
  rule #tconcat(_, I, J, _, Acc) => Acc requires I >Int J

  syntax Int ::= #optInt(Val, Int) [function, total]
  rule #optInt(nil, D) => D
  rule #optInt(V, _) => #truncInt({#tonumber(V)}:>Float) requires isFloat(#tonumber(V))
  rule #optInt(_, D) => D [owise]

  syntax String ::= #optStr(Val) [function, total]
  rule #optStr(V) => {#tostringCoerce(V)}:>String requires #tostringCoerce(V) =/=K nil
  rule #optStr(_) => "" [owise]

  // --------------------------------------------------------- foreach(i)
  // foreach(t, f) calls f(k, v) for each pair, foreachi(t, f) f(i, t[i]) for
  // i = 1..#t; the first non-nil result stops the loop and is returned.
  syntax KItem ::= #foreach(Int, Val, Val) | #foreachi(Int, Val, Int, Int) | #foreachRes(K)
  rule <k> #applyB(builtin("table.foreach"), ListItem(tref(T)) ListItem(F:Val) _)
        => #foreach(T, F, #nextKey(keys_list(M), nil, nil)) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  rule <k> #foreach(_, _, nil) => #vals(.List) ...</k>
  rule <k> #foreach(T, F, K) => #apply(F, ListItem(K) ListItem(#rawget(M, K))) ~> #foreachRes(#foreachNext(T, F, K)) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
    requires K =/=K nil
  syntax KItem ::= #foreachNext(Int, Val, Val)
  rule <k> #foreachNext(T, F, K) => #foreach(T, F, #nextKey(keys_list(M), K, nil)) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>

  rule <k> #applyB(builtin("table.foreachi"), ListItem(tref(T)) ListItem(F:Val) _)
        => #foreachi(T, F, 1, #border(M, A)) ...</k>
       <tables> ... T |-> #tbl(M, A, _) ... </tables>
  rule <k> #foreachi(_, _, I, N) => #vals(.List) ...</k> requires I >Int N
  rule <k> #foreachi(T, F, I, N) => #apply(F, ListItem(#ik(I)) ListItem(#rawget(M, #ik(I)))) ~> #foreachRes(#foreachi(T, F, I +Int 1, N)) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
    requires I <=Int N
  rule <k> #vals(R) ~> #foreachRes(_) => #vals(ListItem(#head(R))) ...</k> requires #head(R) =/=K nil
  rule <k> #vals(R) ~> #foreachRes(Next) => Next ...</k> requires #head(R) ==K nil

  // -------------------------------------------------------------- sort
  // A transcription of ltablib.c auxsort (Lua 5.1's quicksort), working on
  // the table in place, so ties and inconsistent comparators come out as in
  // lua. a[i] < a[j] uses the comparator if one is given, else `<`.
  syntax KItem ::= #auxsort(Int, Int, Int, Val) | #as2(Int, Int, Int, Val) | #as3(Int, Int, Int, Val)
                 | #pivot(Int, Int, Int, Val)
                 | #ifLess(Int, Int, Int, Val, K, K) | #lessV(Val, Val, Val) | #branchK(K, K)
                 | #swap(Int, Int, Int)
                 | #partI(Int, Int, Int, Val, Val, Int, Int) | #partIcont(Int, Int, Int, Val, Val, Int, Int)
                 | #partJ(Int, Int, Int, Val, Val, Int, Int) | #partJcont(Int, Int, Int, Val, Val, Int, Int)
                 | #partCheck(Int, Int, Int, Val, Val, Int, Int)
                 | #afterPart(Int, Int, Int, Val, Int) | #recurse(Int, Int, Int, Val, Int)

  rule <k> #applyB(builtin("table.sort"), ListItem(tref(T)) Rest) => #auxsort(T, 1, #border(M, A), #head(Rest)) ~> #vals(.List) ...</k>
       <tables> ... T |-> #tbl(M, A, _) ... </tables>
    requires #head(Rest) ==K nil orBool #type(#head(Rest)) ==String "function"
  rule <k> #applyB(builtin("table.sort"), ListItem(tref(_)) ListItem(C:Val) _) => #argError(2, "sort", "function", C) ...</k>
    requires C =/=K nil andBool #type(C) =/=String "function"

  rule <k> #ifLess(T, I, J, C, K1, K2) => #lessV(#rawget(M, #ik(I)), #rawget(M, #ik(J)), C) ~> #branchK(K1, K2) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  rule <k> #lessV(A, B, nil) => #bin("<", A, B, .K, .K) ...</k>
  rule <k> #lessV(A, B, F) => #apply(F, ListItem(A) ListItem(B)) ~> #first ...</k> requires F =/=K nil
  rule <k> V:Val ~> #branchK(K1, _) => K1 ...</k> requires #truthy(V)
  rule <k> V:Val ~> #branchK(_, K2) => K2 ...</k> requires notBool #truthy(V)

  rule <k> #swap(T, I, J) => .K ...</k>
       <tables> ... T |-> #tbl((M => #rawset(#rawset(M, #ik(I), #rawget(M, #ik(J))), #ik(J), #rawget(M, #ik(I)))), _, _) ... </tables>

  // while (l < u): order a[l], a[(l+u)/2], a[u]; stop for 2 or 3 elements
  rule <k> #auxsort(_, L, U, _) => .K ...</k> requires L >=Int U
  rule <k> #auxsort(T, L, U, C) => #ifLess(T, U, L, C, #swap(T, L, U), .K) ~> #as2(T, L, U, C) ...</k>
    requires L <Int U
  rule <k> #as2(_, L, U, _) => .K ...</k> requires U -Int L ==Int 1
  rule <k> #as2(T, L, U, C)
        => #ifLess(T, (L +Int U) /Int 2, L, C, #swap(T, (L +Int U) /Int 2, L),
                   #ifLess(T, U, (L +Int U) /Int 2, C, #swap(T, (L +Int U) /Int 2, U), .K))
           ~> #as3(T, L, U, C) ...</k>
    requires U -Int L =/=Int 1
  rule <k> #as3(_, L, U, _) => .K ...</k> requires U -Int L ==Int 2
  // the pivot P = a[(l+u)/2] goes to u-1
  rule <k> #as3(T, L, U, C) => #swap(T, (L +Int U) /Int 2, U -Int 1) ~> #pivot(T, L, U, C) ...</k>
    requires U -Int L =/=Int 2
  rule <k> #pivot(T, L, U, C) => #partI(T, L, U, C, #rawget(M, #ik(U -Int 1)), L, U -Int 1) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>

  // repeat ++i while a[i] < P; repeat --j while P < a[j]
  rule <k> #partI(T, L, U, C, P, I, J)
        => #lessV(#rawget(M, #ik(I +Int 1)), P, C)
           ~> #branchK(#partIcont(T, L, U, C, P, I +Int 1, J), #partJ(T, L, U, C, P, I +Int 1, J)) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  rule <k> #partIcont(_, _, U, _, _, I, _) => #error("invalid order function for sorting") ...</k> requires I >Int U
  rule <k> #partIcont(T, L, U, C, P, I, J) => #partI(T, L, U, C, P, I, J) ...</k> requires I <=Int U
  rule <k> #partJ(T, L, U, C, P, I, J)
        => #lessV(P, #rawget(M, #ik(J -Int 1)), C)
           ~> #branchK(#partJcont(T, L, U, C, P, I, J -Int 1), #partCheck(T, L, U, C, P, I, J -Int 1)) ...</k>
       <tables> ... T |-> #tbl(M, _, _) ... </tables>
  rule <k> #partJcont(_, L, _, _, _, _, J) => #error("invalid order function for sorting") ...</k> requires J <Int L
  rule <k> #partJcont(T, L, U, C, P, I, J) => #partJ(T, L, U, C, P, I, J) ...</k> requires J >=Int L
  rule <k> #partCheck(T, L, U, C, _, I, J) => #afterPart(T, L, U, C, I) ...</k> requires J <Int I
  rule <k> #partCheck(T, L, U, C, P, I, J) => #swap(T, I, J) ~> #partI(T, L, U, C, P, I, J) ...</k> requires J >=Int I

  // put the pivot in place, sort the smaller half first, loop on the other
  rule <k> #afterPart(T, L, U, C, I) => #swap(T, U -Int 1, I) ~> #recurse(T, L, U, C, I) ...</k>
  rule <k> #recurse(T, L, U, C, I) => #auxsort(T, L, I -Int 1, C) ~> #auxsort(T, I +Int 1, U, C) ...</k>
    requires I -Int L <Int U -Int I
  rule <k> #recurse(T, L, U, C, I) => #auxsort(T, I +Int 1, U, C) ~> #auxsort(T, L, I -Int 1, C) ...</k>
    requires I -Int L >=Int U -Int I
endmodule
