// Lua 5.1 pattern matching, transcribed from lstrlib.c (match, max_expand,
// min_expand, classEnd, singlematch, matchbracketclass, matchbalance,
// captures). The C code mutates a capture array and backtracks; here every
// function is pure: it gets the captures so far and returns the end of the
// match with the captures then, so a failed branch simply drops its own.
//
// Positions are 0-based byte offsets into the subject S and pattern P; the
// end of P plays the role of C's '\0'.

requires "lua-values.k"

module LUA-PATTERN
  imports LUA-VALUES

  // A capture: start position and length, or -1 (unfinished) / -2 (a
  // position capture `()`).
  syntax Cap  ::= #cap(Int, Int)
  syntax MRes ::= #mok(Int, List)   // match ended at this position, captures
                | "#mfail"
                | #merr(String)     // a malformed pattern (luaL_error in C)

  syntax String ::= #at(String, Int) [function, total]   // "" past the end
  rule #at(S, I) => substrString(S, I, I +Int 1) requires I >=Int 0 andBool I <Int lengthString(S)
  rule #at(_, _) => "" [owise]

  // The byte at I, 0 past the end (C reads the terminating '\0').
  syntax Int ::= #byteAt(String, Int) [function, total]
  rule #byteAt(S, I) => ordChar(#at(S, I)) requires I >=Int 0 andBool I <Int lengthString(S)
  rule #byteAt(_, _) => 0 [owise]

  // ============================================================ match
  syntax MRes ::= #match(String, String, Int, Int, List) [function, total]   // S, P, s, p, captures
  rule #match(_, P, Si, Pi, Cs) => #mok(Si, Cs) requires Pi >=Int lengthString(P)
  // ( ... )   and the position capture ()
  rule #match(S, P, Si, Pi, Cs) => #startCap(S, P, Si, Pi +Int 2, Cs, -2)
    requires #at(P, Pi) ==String "(" andBool #at(P, Pi +Int 1) ==String ")"
  rule #match(S, P, Si, Pi, Cs) => #startCap(S, P, Si, Pi +Int 1, Cs, -1)
    requires #at(P, Pi) ==String "(" andBool #at(P, Pi +Int 1) =/=String ")"
  rule #match(S, P, Si, Pi, Cs) => #endCap(S, P, Si, Pi +Int 1, Cs, #toClose(Cs, size(Cs) -Int 1))
    requires #at(P, Pi) ==String ")"
  // %b, %f, %1-%9
  rule #match(S, P, Si, Pi, Cs) => #afterBalance(S, P, #matchBalance(S, P, Si, Pi +Int 2), Pi +Int 4, Cs)
    requires #at(P, Pi) ==String "%" andBool #at(P, Pi +Int 1) ==String "b"
  rule #match(S, P, Si, Pi, Cs) => #frontier(S, P, Si, Pi +Int 2, Cs)
    requires #at(P, Pi) ==String "%" andBool #at(P, Pi +Int 1) ==String "f"
  rule #match(S, P, Si, Pi, Cs) => #afterBackref(S, P, #matchCapture(S, Si, Cs, ordChar(#at(P, Pi +Int 1)) -Int 49), Pi +Int 2, Cs)
    requires #at(P, Pi) ==String "%" andBool #isDigitAt(P, Pi +Int 1)
  // $ at the very end anchors to the end of the subject
  rule #match(S, P, Si, Pi, Cs) => #if Si ==Int lengthString(S) #then #mok(Si, Cs) #else #mfail #fi
    requires #at(P, Pi) ==String "$" andBool Pi +Int 1 ==Int lengthString(P)
  rule #match(S, P, Si, Pi, Cs) => #single(S, P, Si, Pi, #classEnd(P, Pi), Cs) [owise]

  // default: a single-character class, maybe followed by ? * + -
  syntax MRes ::= #single(String, String, Int, Int, Int, List) [function, total]
                | #singleQ(MRes, String, String, Int, Int, List) [function, total]
  rule #single(_, _, _, _, Ep, _) => #merr("malformed pattern (ends with '%')") requires Ep ==Int -1
  rule #single(_, _, _, _, Ep, _) => #merr("malformed pattern (missing ']')") requires Ep ==Int -2
  rule #single(S, P, Si, Pi, Ep, Cs) =>
         #if #sm(S, P, Si, Pi, Ep)
         #then #singleQ(#match(S, P, Si +Int 1, Ep +Int 1, Cs), S, P, Si, Ep, Cs)
         #else #match(S, P, Si, Ep +Int 1, Cs) #fi
    requires Ep >=Int 0 andBool #at(P, Ep) ==String "?"
  rule #single(S, P, Si, Pi, Ep, Cs) => #maxExpand(S, P, Si, #countMatches(S, P, Si, Pi, Ep, 0), Ep, Cs)
    requires Ep >=Int 0 andBool #at(P, Ep) ==String "*"
  rule #single(S, P, Si, Pi, Ep, Cs) =>
         #if #sm(S, P, Si, Pi, Ep)
         #then #maxExpand(S, P, Si +Int 1, #countMatches(S, P, Si +Int 1, Pi, Ep, 0), Ep, Cs)
         #else #mfail #fi
    requires Ep >=Int 0 andBool #at(P, Ep) ==String "+"
  rule #single(S, P, Si, Pi, Ep, Cs) => #minExpand(S, P, Si, Pi, Ep, Cs)
    requires Ep >=Int 0 andBool #at(P, Ep) ==String "-"
  rule #single(S, P, Si, Pi, Ep, Cs) =>
         #if #sm(S, P, Si, Pi, Ep) #then #match(S, P, Si +Int 1, Ep, Cs) #else #mfail #fi
    [owise]
  // `?`: if the optional character matched but the rest failed, retry without it.
  rule #singleQ(#mfail, S, P, Si, Ep, Cs) => #match(S, P, Si, Ep +Int 1, Cs)
  rule #singleQ(R, _, _, _, _, _) => R [owise]

  // s < end && singlematch(*s, p, ep)
  syntax Bool ::= #sm(String, String, Int, Int, Int) [function, total]
  rule #sm(S, P, Si, Pi, Ep) => Si <Int lengthString(S) andBool #singlematch(#byteAt(S, Si), P, Pi, Ep)

  // How many characters from Si on match the class (max_expand's first loop).
  syntax Int ::= #countMatches(String, String, Int, Int, Int, Int) [function, total]
  rule #countMatches(S, P, Si, Pi, Ep, I) => #countMatches(S, P, Si, Pi, Ep, I +Int 1)
    requires #sm(S, P, Si +Int I, Pi, Ep)
  rule #countMatches(_, _, _, _, _, I) => I [owise]

  // Try the rest of the pattern after the longest run first, then shorter.
  syntax MRes ::= #maxExpand(String, String, Int, Int, Int, List) [function, total]
                | #maxExpand2(MRes, String, String, Int, Int, Int, List) [function, total]
  rule #maxExpand(_, _, _, I, _, _) => #mfail requires I <Int 0
  rule #maxExpand(S, P, Si, I, Ep, Cs) => #maxExpand2(#match(S, P, Si +Int I, Ep +Int 1, Cs), S, P, Si, I, Ep, Cs) [owise]
  rule #maxExpand2(#mfail, S, P, Si, I, Ep, Cs) => #maxExpand(S, P, Si, I -Int 1, Ep, Cs)
  rule #maxExpand2(R, _, _, _, _, _, _) => R [owise]

  // `-`: try the rest first, consume one more character only if it fails.
  syntax MRes ::= #minExpand(String, String, Int, Int, Int, List) [function, total]
                | #minExpand2(MRes, String, String, Int, Int, Int, List) [function, total]
  rule #minExpand(S, P, Si, Pi, Ep, Cs) => #minExpand2(#match(S, P, Si, Ep +Int 1, Cs), S, P, Si, Pi, Ep, Cs)
  rule #minExpand2(#mfail, S, P, Si, Pi, Ep, Cs) =>
         #if #sm(S, P, Si, Pi, Ep) #then #minExpand(S, P, Si +Int 1, Pi, Ep, Cs) #else #mfail #fi
  rule #minExpand2(R, _, _, _, _, _, _) => R [owise]

  // ---------------------------------------------------------- captures
  syntax MRes ::= #startCap(String, String, Int, Int, List, Int) [function, total]
                | #endCap(String, String, Int, Int, List, Int) [function, total]
  rule #startCap(_, _, _, _, Cs, _) => #merr("too many captures") requires size(Cs) >=Int 32
  rule #startCap(S, P, Si, Pi, Cs, W) => #match(S, P, Si, Pi, Cs ListItem(#cap(Si, W))) [owise]
  rule #endCap(_, _, _, _, _, L) => #merr("invalid pattern capture") requires L <Int 0
  rule #endCap(S, P, Si, Pi, Cs, L) => #match(S, P, Si, Pi, Cs [ L <- #cap(#capInit(Cs, L), Si -Int #capInit(Cs, L)) ]) [owise]

  // The innermost unfinished capture.
  syntax Int ::= #toClose(List, Int) [function, total]
  rule #toClose(_, L) => L requires L <Int 0
  rule #toClose(Cs, L) => L requires L >=Int 0 andBool #capLen(Cs, L) ==Int -1
  rule #toClose(Cs, L) => #toClose(Cs, L -Int 1) [owise]

  syntax Int ::= #capInit(List, Int) [function, total] | #capLen(List, Int) [function, total]
  rule #capInit(Cs, L) => #capInit2(Cs [ L ]) requires L >=Int 0 andBool L <Int size(Cs)
  rule #capInit(_, _) => 0 [owise]
  rule #capLen(Cs, L) => #capLen2(Cs [ L ]) requires L >=Int 0 andBool L <Int size(Cs)
  rule #capLen(_, _) => -1 [owise]
  syntax Int ::= #capInit2(KItem) [function, total] | #capLen2(KItem) [function, total]
  rule #capInit2(#cap(I, _)) => I
  rule #capInit2(_) => 0 [owise]
  rule #capLen2(#cap(_, N)) => N
  rule #capLen2(_) => -1 [owise]

  // %1-%9: the text of an earlier, finished capture must come next.
  syntax Int ::= #matchCapture(String, Int, List, Int) [function, total]   // end, -1 fail, -2 error
  rule #matchCapture(_, _, Cs, L) => -2 requires L <Int 0 orBool L >=Int size(Cs) orBool #capLen(Cs, L) ==Int -1
  rule #matchCapture(_, _, Cs, L) => -1 requires L >=Int 0 andBool L <Int size(Cs) andBool #capLen(Cs, L) ==Int -2
  rule #matchCapture(S, Si, Cs, L) => Si +Int #capLen(Cs, L)
    requires L >=Int 0 andBool L <Int size(Cs) andBool #capLen(Cs, L) >=Int 0
     andBool Si +Int #capLen(Cs, L) <=Int lengthString(S)
     andBool substrString(S, #capInit(Cs, L), #capInit(Cs, L) +Int #capLen(Cs, L))
             ==String substrString(S, Si, Si +Int #capLen(Cs, L))
  rule #matchCapture(_, _, _, _) => -1 [owise]
  syntax MRes ::= #afterBackref(String, String, Int, Int, List) [function, total]
  rule #afterBackref(_, _, -2, _, _) => #merr("invalid capture index")
  rule #afterBackref(_, _, -1, _, _) => #mfail
  rule #afterBackref(S, P, E, Pi, Cs) => #match(S, P, E, Pi, Cs) [owise]

  // %bxy: an x, then text balanced in x/y, up to the matching y.
  syntax Int ::= #matchBalance(String, String, Int, Int) [function, total]   // end, -1 fail, -2 error
               | #balance(String, Int, String, String, Int) [function, total]
  rule #matchBalance(_, P, _, Pi) => -2 requires Pi +Int 1 >=Int lengthString(P)
  rule #matchBalance(S, P, Si, Pi) => -1
    requires Pi +Int 1 <Int lengthString(P) andBool (Si >=Int lengthString(S) orBool #at(S, Si) =/=String #at(P, Pi))
  rule #matchBalance(S, P, Si, Pi) => #balance(S, Si +Int 1, #at(P, Pi), #at(P, Pi +Int 1), 1) [owise]
  rule #balance(S, I, _, _, _) => -1 requires I >=Int lengthString(S)
  rule #balance(S, I, _, E, 1) => I +Int 1 requires I <Int lengthString(S) andBool #at(S, I) ==String E
  rule #balance(S, I, B, E, N) => #balance(S, I +Int 1, B, E, N -Int 1)
    requires I <Int lengthString(S) andBool #at(S, I) ==String E andBool N =/=Int 1
  rule #balance(S, I, B, E, N) => #balance(S, I +Int 1, B, E, N +Int 1)
    requires I <Int lengthString(S) andBool #at(S, I) =/=String E andBool #at(S, I) ==String B
  rule #balance(S, I, B, E, N) => #balance(S, I +Int 1, B, E, N) [owise]
  syntax MRes ::= #afterBalance(String, String, Int, Int, List) [function, total]
  rule #afterBalance(_, _, -2, _, _) => #merr("unbalanced pattern")
  rule #afterBalance(_, _, -1, _, _) => #mfail
  rule #afterBalance(S, P, E, Pi, Cs) => #match(S, P, E, Pi, Cs) [owise]

  // %f[set]: the previous character is not in the set and the next one is.
  syntax MRes ::= #frontier(String, String, Int, Int, List) [function, total]
                | #frontier2(String, String, Int, Int, Int, List) [function, total]
  rule #frontier(_, P, _, Pi, _) => #merr("missing '[' after '%f' in pattern") requires #at(P, Pi) =/=String "["
  rule #frontier(S, P, Si, Pi, Cs) => #frontier2(S, P, Si, Pi, #classEnd(P, Pi), Cs) [owise]
  rule #frontier2(_, _, _, _, Ep, _) => #merr("malformed pattern (missing ']')") requires Ep <Int 0
  rule #frontier2(S, P, Si, Pi, Ep, Cs) =>
         #if #bracket(#byteAt(S, Si -Int 1), P, Pi, Ep -Int 1) orBool notBool #bracket(#byteAt(S, Si), P, Pi, Ep -Int 1)
         #then #mfail #else #match(S, P, Si, Ep, Cs) #fi
    [owise]

  // ---------------------------------------------------- character classes
  // End of the single-character class starting at Pi; -1 / -2 on errors.
  syntax Int ::= #classEnd(String, Int) [function, total]
               | #bracketEnd(String, Int) [function, total]
  rule #classEnd(P, Pi) => #if Pi +Int 1 >=Int lengthString(P) #then -1 #else Pi +Int 2 #fi
    requires #at(P, Pi) ==String "%"
  rule #classEnd(P, Pi) => #bracketEnd(P, #if #at(P, Pi +Int 1) ==String "^" #then Pi +Int 2 #else Pi +Int 1 #fi)
    requires #at(P, Pi) ==String "["
  rule #classEnd(_, Pi) => Pi +Int 1 [owise]
  // do { if end: error; if (*(p++) == '%' && *p) p++; } while (*p != ']')
  rule #bracketEnd(P, I) => -2 requires I >=Int lengthString(P)
  rule #bracketEnd(P, I) => #bracketEnd2(P, #if #at(P, I) ==String "%" andBool I +Int 1 <Int lengthString(P) #then I +Int 2 #else I +Int 1 #fi) [owise]
  syntax Int ::= #bracketEnd2(String, Int) [function, total]
  rule #bracketEnd2(P, I) => I +Int 1 requires #at(P, I) ==String "]"
  rule #bracketEnd2(P, I) => #bracketEnd(P, I) [owise]

  syntax Bool ::= #singlematch(Int, String, Int, Int) [function, total]
  rule #singlematch(_, P, Pi, _) => true requires #at(P, Pi) ==String "."
  rule #singlematch(C, P, Pi, _) => #matchClass(C, ordChar(#at(P, Pi +Int 1))) requires #at(P, Pi) ==String "%"
  rule #singlematch(C, P, Pi, Ep) => #bracket(C, P, Pi, Ep -Int 1) requires #at(P, Pi) ==String "["
  rule #singlematch(C, P, Pi, _) => ordChar(#at(P, Pi)) ==Int C [owise]

  // [set] between Pi ('[') and Ec (']'): ranges a-z, classes %x, ^ negates.
  syntax Bool ::= #bracket(Int, String, Int, Int) [function, total]
                | #bracketLoop(Int, String, Int, Int, Bool) [function, total]
  rule #bracket(C, P, Pi, Ec) => #bracketLoop(C, P, Pi +Int 2, Ec, false) requires #at(P, Pi +Int 1) ==String "^"
  rule #bracket(C, P, Pi, Ec) => #bracketLoop(C, P, Pi +Int 1, Ec, true) [owise]
  rule #bracketLoop(_, _, I, Ec, Sig) => notBool Sig requires I >=Int Ec
  rule #bracketLoop(C, P, I, Ec, Sig) =>
         #if #matchClass(C, ordChar(#at(P, I +Int 1))) #then Sig #else #bracketLoop(C, P, I +Int 2, Ec, Sig) #fi
    requires I <Int Ec andBool #at(P, I) ==String "%"
  rule #bracketLoop(C, P, I, Ec, Sig) =>
         #if ordChar(#at(P, I)) <=Int C andBool C <=Int ordChar(#at(P, I +Int 2)) #then Sig #else #bracketLoop(C, P, I +Int 3, Ec, Sig) #fi
    requires I <Int Ec andBool #at(P, I) =/=String "%" andBool #at(P, I +Int 1) ==String "-" andBool I +Int 2 <Int Ec
  rule #bracketLoop(C, P, I, Ec, Sig) =>
         #if ordChar(#at(P, I)) ==Int C #then Sig #else #bracketLoop(C, P, I +Int 1, Ec, Sig) #fi
    [owise]

  // %a %c %d %l %p %s %u %w %x %z in the C locale; upper case complements;
  // any other character stands for itself.
  syntax Bool ::= #matchClass(Int, Int) [function, total]
                | #classOf(Int, Int) [function, total]
  rule #matchClass(C, Cl) => notBool #classOf(C, Cl +Int 32)
    requires Cl >=Int 65 andBool Cl <=Int 90 andBool #isClassLetter(Cl +Int 32)
  rule #matchClass(C, Cl) => #classOf(C, Cl) requires #isClassLetter(Cl)
  rule #matchClass(C, Cl) => C ==Int Cl [owise]

  syntax Bool ::= #isClassLetter(Int) [function, total]
  rule #isClassLetter(Cl) => findString("acdlpsuwxz", chrChar(Cl), 0) >=Int 0 requires Cl >=Int 97 andBool Cl <=Int 122
  rule #isClassLetter(_) => false [owise]

  rule #classOf(C, 97)  => #isAlpha(C)                                     // a
  rule #classOf(C, 99)  => C <Int 32 orBool C ==Int 127                    // c
  rule #classOf(C, 100) => C >=Int 48 andBool C <=Int 57                   // d
  rule #classOf(C, 108) => C >=Int 97 andBool C <=Int 122                  // l
  rule #classOf(C, 112) => (C >=Int 33 andBool C <=Int 47) orBool (C >=Int 58 andBool C <=Int 64)
                    orBool (C >=Int 91 andBool C <=Int 96) orBool (C >=Int 123 andBool C <=Int 126)   // p
  rule #classOf(C, 115) => C ==Int 32 orBool (C >=Int 9 andBool C <=Int 13) // s
  rule #classOf(C, 117) => C >=Int 65 andBool C <=Int 90                   // u
  rule #classOf(C, 119) => #isAlpha(C) orBool (C >=Int 48 andBool C <=Int 57)   // w
  rule #classOf(C, 120) => (C >=Int 48 andBool C <=Int 57) orBool (C >=Int 97 andBool C <=Int 102)
                    orBool (C >=Int 65 andBool C <=Int 70)                 // x
  rule #classOf(C, 122) => C ==Int 0                                       // z
  rule #classOf(_, _) => false [owise]

  syntax Bool ::= #isAlpha(Int) [function, total]
  rule #isAlpha(C) => (C >=Int 65 andBool C <=Int 90) orBool (C >=Int 97 andBool C <=Int 122)

  // ---------------------------------------------------- capture values
  // push_onecapture / push_captures: the captured strings (positions as
  // numbers); with no captures, the whole match if `Whole`.
  syntax List ::= #capVals(String, List, Int, Int, Bool) [function, total]
                | #capValsFrom(String, List, Int) [function, total]
  rule #capVals(S, .List, Si, E, true) => ListItem(substrString(S, Si, E))
  rule #capVals(S, Cs, _, _, _) => #capValsFrom(S, Cs, 0) [owise]
  rule #capValsFrom(S, Cs, I) => ListItem(#capVal(S, Cs [ I ])) #capValsFrom(S, Cs, I +Int 1) requires I <Int size(Cs)
  rule #capValsFrom(_, _, _) => .List [owise]

  syntax Val ::= #capVal(String, KItem) [function, total]
  rule #capVal(_, #cap(I, -2)) => Int2Float(I +Int 1, 53, 11)
  rule #capVal(S, #cap(I, N)) => substrString(S, I, I +Int N) requires N >=Int 0
  rule #capVal(_, _) => nil [owise]

  // "unfinished capture" if a capture never closed.
  syntax Bool ::= #hasUnfinished(List) [function, total]
  rule #hasUnfinished(ListItem(#cap(_, -1)) _) => true
  rule #hasUnfinished(ListItem(_) L) => #hasUnfinished(L) [owise]
  rule #hasUnfinished(.List) => false
endmodule
